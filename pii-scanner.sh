#!/usr/bin/env bash
# pii-scanner.sh — Scan markdown files for PII patterns before they hit git.
# Version: 2.0.0
#
# Usage:
#   pii-scanner.sh [OPTIONS] <directory>
#   pii-scanner.sh --install-hook [<repo-path>]
#   pii-scanner.sh --help
#
# Options:
#   --count-only     Report totals per pattern type only
#   --config <file>  Load custom patterns from YAML config
#   --install-hook   Install as git pre-commit hook
#   --extensions <e> Comma-separated file extensions (default: md)
#   --help           Show this help

set -euo pipefail

VERSION="2.0.0"

# --- Defaults ---
count_only=0
config_file=""
extensions="md"
install_hook=0

# --- Built-in patterns (used when no config file provided) ---
# These catch common PII leaks in documentation repos.
builtin_patterns() {
  # Gmail thread/message IDs
  pat_names+=("GMAIL_ID")
  pat_regexes+=('gmail:[0-9a-fA-F]+')

  # Phone numbers (North American +1)
  pat_names+=("PHONE")
  pat_regexes+=('\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}')

  # Absolute paths with usernames (/Users/<name> or /home/<name>)
  pat_names+=("USER_PATH")
  pat_regexes+=('/(Users|home)/[A-Za-z0-9._-]+')

  # .credentials directory references
  pat_names+=("CREDENTIALS_REF")
  pat_regexes+=('\.credentials/')

  # Telegram/Discord/Slack numeric user IDs (10+ digits)
  pat_names+=("CHAT_USER_ID")
  pat_regexes+=('(chat_id|user_id|userId|telegram.*id)["'"'"': ]+[0-9]{8,}')

  # AWS access keys
  pat_names+=("AWS_KEY")
  pat_regexes+=('AKIA[0-9A-Z]{16}')

  # Generic API key/token/secret assignments
  pat_names+=("API_SECRET")
  pat_regexes+=('(api_key|api_secret|apikey|token|secret)["'"'"': =]+[A-Za-z0-9_\-]{20,}')
}

# --- Parse config file (simple YAML-ish: "name: regex" per line under patterns:) ---
load_config() {
  local file=$1
  local in_patterns=0
  local in_extensions=0
  local in_exclude=0

  while IFS= read -r line || [[ -n $line ]]; do
    # Strip comments
    line="${line%%#*}"
    # Skip blank
    [[ -z "${line// }" ]] && continue

    if [[ $line =~ ^patterns: ]]; then
      in_patterns=1; in_extensions=0; in_exclude=0; continue
    elif [[ $line =~ ^extensions: ]]; then
      in_patterns=0; in_extensions=1; in_exclude=0; continue
    elif [[ $line =~ ^exclude: ]]; then
      in_patterns=0; in_extensions=0; in_exclude=1; continue
    elif [[ $line =~ ^[a-z] ]]; then
      in_patterns=0; in_extensions=0; in_exclude=0
    fi

    if [[ $in_patterns -eq 1 && $line =~ ^[[:space:]]+-[[:space:]] ]]; then
      # Parse "  - NAME: regex"
      local entry="${line#*- }"
      local name="${entry%%:*}"
      local regex="${entry#*: }"
      # Trim whitespace
      name="$(echo "$name" | xargs)"
      regex="$(echo "$regex" | xargs)"
      # Strip surrounding quotes from regex
      regex="${regex#\"}"
      regex="${regex%\"}"
      regex="${regex#\'}"
      regex="${regex%\'}"
      pat_names+=("$name")
      pat_regexes+=("$regex")
    fi

    if [[ $in_extensions -eq 1 && $line =~ ^[[:space:]]+-[[:space:]] ]]; then
      local ext="${line#*- }"
      ext="$(echo "$ext" | xargs)"
      if [[ -z "$extensions_from_config" ]]; then
        extensions_from_config="$ext"
      else
        extensions_from_config="$extensions_from_config,$ext"
      fi
    fi
  done < "$file"
}

# --- Install pre-commit hook ---
do_install_hook() {
  local repo_path="${1:-.}"
  local hook_dir="$repo_path/.git/hooks"
  local hook_file="$hook_dir/pre-commit"

  if [[ ! -d "$repo_path/.git" ]]; then
    echo "Error: $repo_path is not a git repository" >&2
    exit 2
  fi

  # Find the scanner script path
  local scanner_path
  scanner_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  local hook_content="#!/usr/bin/env bash
# PII Scanner pre-commit hook (installed by pii-scanner.sh)
# Scans staged .md files for PII patterns before commit.

SCANNER=\"$scanner_path\"
REPO_ROOT=\"\$(git rev-parse --show-toplevel)\"
CONFIG=\"\$REPO_ROOT/.pii-patterns.yaml\"

if [[ -f \"\$CONFIG\" ]]; then
  CONFIG_FLAG=\"--config \$CONFIG\"
else
  CONFIG_FLAG=\"\"
fi

# Only scan if there are staged .md files
STAGED=\$(git diff --cached --name-only --diff-filter=ACM | grep -E '\\.(md|markdown|txt)\$' || true)
if [[ -z \"\$STAGED\" ]]; then
  exit 0
fi

# Create temp dir with staged files
TMPDIR=\$(mktemp -d)
trap 'rm -rf \"\$TMPDIR\"' EXIT

for f in \$STAGED; do
  mkdir -p \"\$TMPDIR/\$(dirname \"\$f\")\"
  git show \":\$f\" > \"\$TMPDIR/\$f\" 2>/dev/null || true
done

# Run scanner
\$SCANNER \$CONFIG_FLAG --count-only \"\$TMPDIR\"
RESULT=\$?

if [[ \$RESULT -ne 0 ]]; then
  echo \"\"
  echo \"⚠️  PII detected in staged files. Review matches:\"
  \$SCANNER \$CONFIG_FLAG \"\$TMPDIR\"
  echo \"\"
  echo \"To commit anyway: git commit --no-verify\"
  exit 1
fi
"

  # Handle existing hook
  if [[ -f "$hook_file" ]]; then
    if grep -q "pii-scanner" "$hook_file" 2>/dev/null; then
      echo "PII scanner hook already installed at $hook_file"
      exit 0
    fi
    echo "Warning: pre-commit hook already exists at $hook_file"
    echo "Backing up to $hook_file.backup"
    cp "$hook_file" "$hook_file.backup"
  fi

  echo "$hook_content" > "$hook_file"
  chmod +x "$hook_file"
  echo "✅ PII scanner pre-commit hook installed at $hook_file"
  echo ""
  echo "Optional: create .pii-patterns.yaml in repo root to customize patterns."
  echo "Run '$0 --help' for config file format."
}

# --- Help ---
show_help() {
  cat <<'HELP'
pii-scanner.sh — Scan files for PII patterns

Usage:
  pii-scanner.sh [OPTIONS] <directory>
  pii-scanner.sh --install-hook [<repo-path>]

Options:
  --count-only        Report totals per pattern type only
  --config <file>     Load patterns from YAML config (see format below)
  --extensions <exts> Comma-separated extensions to scan (default: md)
  --install-hook      Install as git pre-commit hook in repo
  --help              Show this help

Exit codes:
  0  No PII found (clean)
  1  PII matches found
  2  Usage error

Output format (default mode):
  file:line:PATTERN_NAME:matched_text

Config file format (.pii-patterns.yaml):
  patterns:
    - GMAIL_ID: 'gmail:[0-9a-fA-F]+'
    - PHONE: '\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}'
    - COMPANY_EMAIL: '[A-Za-z0-9._%+-]+@(mycompany|otherdomain)\b'
  extensions:
    - md
    - txt
    - yaml

Built-in patterns (when no config):
  GMAIL_ID         gmail:<hex> thread/message IDs
  PHONE            +1 North American phone numbers
  USER_PATH        /Users/<name> or /home/<name> paths
  CREDENTIALS_REF  .credentials/ directory references
  CHAT_USER_ID     Telegram/Discord numeric user IDs
  AWS_KEY          AWS access key IDs (AKIA...)
  API_SECRET       Generic API key/token/secret values
HELP
}

# --- Parse args ---
pat_names=()
pat_regexes=()
extensions_from_config=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) show_help; exit 0 ;;
    --version) echo "pii-scanner $VERSION"; exit 0 ;;
    --count-only) count_only=1; shift ;;
    --config) config_file="$2"; shift 2 ;;
    --extensions) extensions="$2"; shift 2 ;;
    --install-hook) install_hook=1; shift ;;
    -*) echo "Unknown option: $1" >&2; show_help >&2; exit 2 ;;
    *) break ;;
  esac
done

# Handle install-hook
if [[ $install_hook -eq 1 ]]; then
  do_install_hook "${1:-.}"
  exit 0
fi

# Need a directory argument
if [[ $# -ne 1 ]]; then
  show_help >&2
  exit 2
fi

target_dir=$1
if [[ ! -d "$target_dir" ]]; then
  echo "Error: directory not found: $target_dir" >&2
  exit 2
fi

# Load patterns — check explicit --config, then default locations, then built-ins
if [[ -z "$config_file" ]]; then
  # Auto-detect config: check target dir, then repo root, then home
  for candidate in \
    "$target_dir/.pii-patterns.yaml" \
    "$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null)/.pii-patterns.yaml" \
    "$HOME/.pii-patterns.yaml"; do
    if [[ -f "$candidate" ]]; then
      config_file="$candidate"
      break
    fi
  done
fi

if [[ -n "$config_file" ]]; then
  if [[ ! -f "$config_file" ]]; then
    echo "Error: config file not found: $config_file" >&2
    exit 2
  fi
  load_config "$config_file"
  [[ -n "$extensions_from_config" ]] && extensions="$extensions_from_config"
fi

# Fall back to built-in patterns if none loaded
if [[ ${#pat_names[@]} -eq 0 ]]; then
  builtin_patterns
fi

# Build find expression for extensions
IFS=',' read -ra ext_array <<< "$extensions"
find_expr=()
for i in "${!ext_array[@]}"; do
  [[ $i -gt 0 ]] && find_expr+=("-o")
  find_expr+=("-name" "*.${ext_array[$i]}")
done

# Find files
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$target_dir" -type d -name .git -prune -o -type f \( "${find_expr[@]}" \) -print)

if [[ ${#files[@]} -eq 0 ]]; then
  exit 0
fi

# --- Count-only mode ---
if [[ $count_only -eq 1 ]]; then
  # Use parallel arrays instead of associative (bash 3.2 compat)
  pat_counts=()
  for i in "${!pat_names[@]}"; do
    pat_counts[$i]=0
  done

  for f in "${files[@]}"; do
    for i in "${!pat_names[@]}"; do
      c=$(grep -Eo "${pat_regexes[$i]}" "$f" 2>/dev/null | wc -l | tr -d ' ') || true
      prev=${pat_counts[$i]}
      pat_counts[$i]=$(( prev + c ))
    done
  done

  total=0
  for i in "${!pat_names[@]}"; do
    printf "%s:%d\n" "${pat_names[$i]}" "${pat_counts[$i]}"
    total=$(( total + ${pat_counts[$i]} ))
  done

  [[ $total -gt 0 ]] && exit 1
  exit 0
fi

# --- Full scan mode ---
matches=0

for f in "${files[@]}"; do
  ln=0
  while IFS= read -r line || [[ -n $line ]]; do
    ln=$((ln+1))
    for i in "${!pat_names[@]}"; do
      if [[ $line =~ ${pat_regexes[$i]} ]]; then
        printf "%s:%d:%s:%s\n" "$f" "$ln" "${pat_names[$i]}" "${BASH_REMATCH[0]}"
        matches=$((matches+1))
      fi
    done
  done < "$f"
done

[[ $matches -gt 0 ]] && exit 1
exit 0
