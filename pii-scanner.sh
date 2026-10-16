#!/usr/bin/env bash
# pii-scanner.sh — Scan markdown files for PII patterns before they hit git.
# Version: 3.2.1
#
# Usage:
#   pii-scanner.sh [OPTIONS] <directory>
#   pii-scanner.sh --install-hook [--dry-run] [<repo-path>]
#   pii-scanner.sh --help
#
# Options:
#   --count-only     Report totals per pattern type only
#   --config <file>  Load custom patterns from YAML config
#   --config-context <dir>  Discover config from the original directory of a temporary copy
#   --install-hook   Install as git pre-commit hook
#   --dry-run        Preview hook installation without writing
#   --extensions <e> Comma-separated file extensions (default: md)
#   --help           Show this help
# Exit: 0 clean/installed/preview; 1 findings; 2 usage, config, install refusal, or unreadable input.
#
# Config comments: in a config line, a # that is preceded by whitespace and is outside
# double or single quotes starts a comment. A # inside quotes, or not preceded by
# whitespace, is part of the value, so a regex that contains # keeps working.
# Report lines are PATH:LINE:PATTERN:MATCH. In PATH, a backslash is written as \\,
# a colon as \:, and a newline as \n. Split on unescaped colons. A colon in a
# filename is \: in the path field, so it is not the field separator.
# Hook upgrade: --install-hook refuses an existing hook that differs. A hook installed
# by an older version cannot be upgraded in place. The old hook has to be removed by
# hand first.

set -euo pipefail

VERSION="3.2.1"

# --- Defaults ---
count_only=0
config_file=""
config_context=""
extensions="md"
extensions_given=0
install_hook=0
dry_run=0

# --- Built-in patterns (always loaded; configuration adds patterns) ---
# These catch common PII leaks in documentation repos.
builtin_patterns() {
  # Gmail thread/message IDs
  pat_names+=("GMAIL_ID")
  pat_regexes+=('gmail:[0-9a-fA-F]+')

  # Phone numbers, North American: with or without +1, and the everyday shapes 803-555-0142, 803.555.0142,
  # (803) 555-0142. Separators are required between the groups, so a bare 10-digit id is not a phone number.
  pat_names+=("PHONE")
  pat_regexes+=('(\+1[-. ]?[0-9]{3}[-. ]?[0-9]{3}[-. ]?[0-9]{4})|((^|[^0-9A-Za-z./_-])(1[-. ])?(\([0-9]{3}\) ?|[0-9]{3}[-. ])[0-9]{3}[-. ][0-9]{4}($|[^0-9A-Za-z_-]))')

  # Email addresses. Reserved documentation domains and obvious placeholders are allowlisted below; a real
  # person's or company's address in a public file is the leak this exists to catch.
  pat_names+=("EMAIL")
  pat_regexes+=('[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}')

  # User-home paths are scanned with line context below, so URL and code paths are excluded.

  # .credentials directory references
  pat_names+=("CREDENTIALS_REF")
  pat_regexes+=('\.credentials(/|$)')

  # Telegram/Discord/Slack numeric user IDs (10+ digits)
  pat_names+=("CHAT_USER_ID")
  pat_regexes+=('(chat_id|user_id|userId|telegram.*id)["'"'"': ]+[0-9]{8,}')

  # AWS access keys
  pat_names+=("AWS_KEY")
  pat_regexes+=('AKIA[0-9A-Z]{16}')

  # Generic API key/token/secret assignments
  pat_names+=("API_SECRET")
  pat_regexes+=('(api_key|api_secret|apikey|token|secret)["'"'"': =]+[A-Za-z0-9_\-]{20,}')

  # Tailscale MagicDNS hostnames
  pat_names+=("TAILSCALE_HOST")
  pat_regexes+=('[a-z0-9-]+\.[a-z0-9-]+\.ts\.net')

  # Built-in allowlist: RFC 2606 / RFC 6761 reserved names, and placeholder domains nobody should mistake for
  # a real mailbox. Prefer example.com in new text; these exist so old placeholders do not drown real hits.
  pat_allowlist+=('@([A-Za-z0-9-]+\.)*example\.(com|org|net)$')
  pat_allowlist+=('@([A-Za-z0-9-]+\.)*[A-Za-z0-9-]+\.(example|test|invalid|localhost)$')
  pat_allowlist+=('@(domain|company|client|vendor|email|yourdomain|yourcompany|mycompany|acme)\.(com|org|net)$')
  # NOT allowlisted: no-reply@<real-domain>. It names a real organization and, in a filter rule, a real relationship.
  # Things that look like an address and are not one:
  pat_allowlist+=('@[0-9]+x\.[A-Za-z0-9]+$')                                     # image@2x.webp (a retina asset name)
  pat_allowlist+=('@[A-Za-z0-9_.%<>-]*\.(service|socket|timer|mount|target|path|slice|scope)$')  # unit@NAME.service (a systemd template)
  pat_allowlist+=('@[0-9xX]+(\.[0-9xX]+){3}$')                                   # user@100.x.x.x (an SSH target; the IP patterns own that)
  pat_allowlist+=('^git@')            # git@github.com:owner/repo is a transport, not a mailbox
  # Reserved for fiction and examples: area code 555, and the 555-0100..0199 block in any area code.
  pat_allowlist+=('(^|[^0-9])555[-. )]+[0-9]{3}[-. ][0-9]{4}')
  pat_allowlist+=('[-. )]555[-. ]01[0-9]{2}([^0-9]|$)')
}

is_allowlisted_match() {
  local matched_text=$1
  local j
  for j in "${!pat_allowlist[@]}"; do
    if [[ $matched_text =~ ${pat_allowlist[$j]} ]]; then
      return 0
    fi
  done
  return 1
}

# Drop a trailing comment from one config line.
# A # preceded by whitespace, outside double or single quotes, starts the comment.
# A # inside quotes, or not preceded by whitespace, stays in the value.
# A backslash inside quotes escapes the next character, so \" does not end the string.
strip_config_comment() {
  local line=$1
  local i n c prev in_single=0 in_double=0
  n=${#line}
  for ((i=0; i<n; i++)); do
    c=${line:i:1}
    if [[ $c == '\' && ( $in_single -eq 1 || $in_double -eq 1 ) && $((i + 1)) -lt $n ]]; then
      i=$((i + 1))
      continue
    fi
    if [[ $c == "'" && $in_double -eq 0 ]]; then
      if [[ $in_single -eq 0 ]]; then in_single=1; else in_single=0; fi
      continue
    fi
    if [[ $c == '"' && $in_single -eq 0 ]]; then
      if [[ $in_double -eq 0 ]]; then in_double=1; else in_double=0; fi
      continue
    fi
    if [[ $c == '#' && $in_single -eq 0 && $in_double -eq 0 ]]; then
      if [[ $i -eq 0 ]]; then
        printf '%s' ""
        return 0
      fi
      prev=${line:i-1:1}
      if [[ $prev == [[:space:]] ]]; then
        printf '%s' "${line:0:i}"
        return 0
      fi
    fi
  done
  printf '%s' "$line"
}

# --- Parse config file (simple YAML-ish: "name: regex" per line under patterns:) ---
load_config() {
  local file=$1
  local in_patterns=0
  local in_extensions=0
  local in_allowlist=0

  while IFS= read -r line || [[ -n $line ]]; do
    line=$(strip_config_comment "$line")
    [[ $line =~ ^[[:space:]]*# ]] && continue
    # Skip blank
    [[ -z "${line// }" ]] && continue

    if [[ $line =~ ^patterns: ]]; then
      in_patterns=1; in_extensions=0; in_allowlist=0; continue
    elif [[ $line =~ ^extensions: ]]; then
      in_patterns=0; in_extensions=1; in_allowlist=0; continue
    elif [[ $line =~ ^exclude: ]] || [[ $line =~ ^allowlist: ]]; then
      in_patterns=0; in_extensions=0; in_allowlist=1; continue
    elif [[ $line =~ ^[a-z] ]]; then
      in_patterns=0; in_extensions=0; in_allowlist=0
    fi

    if [[ $in_patterns -eq 1 && $line =~ ^[[:space:]]+-[[:space:]] ]]; then
      # Parse "  - NAME: regex"
      local entry="${line#*- }"
      local name="${entry%%:*}"
      local regex="${entry#*: }"
      # Trim whitespace (sed instead of xargs — xargs fails on strings with single quotes)
      name="$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      regex="$(echo "$regex" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
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
      ext="$(echo "$ext" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [[ -z "$extensions_from_config" ]]; then
        extensions_from_config="$ext"
      else
        extensions_from_config="$extensions_from_config,$ext"
      fi
    fi

    if [[ $in_allowlist -eq 1 && $line =~ ^[[:space:]]+-[[:space:]] ]]; then
      local allow_entry="${line#*- }"
      local allow_regex="$allow_entry"
      if [[ $allow_entry == *": "* ]]; then
        allow_regex="${allow_entry#*: }"
      fi
      allow_regex="$(echo "$allow_regex" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      allow_regex="${allow_regex#\"}"
      allow_regex="${allow_regex%\"}"
      allow_regex="${allow_regex#\'}"
      allow_regex="${allow_regex%\'}"
      pat_allowlist+=("$allow_regex")
    fi
  done < "$file"
}

# --- Install pre-commit hook ---
do_install_hook() {
  local repo_path="${1:-.}"
  local hook_dir="$repo_path/.git/hooks"
  local hook_file="$hook_dir/pre-commit"
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "refused: hook target must be a git repository root with a .git directory" >&2
    exit 2
  fi
  if [[ -n "$(git -C "$repo_path" config --get core.hooksPath || true)" || -L "$hook_dir" ]]; then
    echo "refused: custom or redirected hook directory; retain existing checks and consult the hook owner" >&2
    exit 2
  fi
  local scanner_path hook_content body_file
  scanner_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  # Write the template to a file. A ')' inside $(cat <<'HOOK') is parsed as the
  # end of the substitution on bash 3.2, which executes the rest of the template.
  body_file=$(mktemp)
  {
    printf '#!/usr/bin/env bash\n# Managed PII scanner hook 3.2.1\nSCANNER=%q\n' "$scanner_path"
    cat <<'HOOK'
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)" || exit 2
cd "$REPO_ROOT" || exit 2
hook_work="$(mktemp -d)" || exit 2
trap 'rm -rf "$hook_work"' EXIT
mkdir "$hook_work/files"
git diff --cached --name-only -z --diff-filter=ACMR > "$hook_work/staged" || {
  echo "unverified: could not enumerate staged files" >&2; exit 2;
}
while IFS= read -r -d '' f; do
  case "$f" in
    *$'\n'*|*:* ) echo "unverified: unsupported staged filename for scanner output" >&2; exit 2 ;;
  esac
  ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in md|markdown|txt|yaml|yml|html|json) ;; *) continue ;; esac
  mkdir -p -- "$hook_work/files/$(dirname -- "$f")"
  git show ":$f" > "$hook_work/files/$f" 2>/dev/null || {
    echo "unverified: could not read a staged blob" >&2; exit 2;
  }
done < "$hook_work/staged"
rc=0
"$SCANNER" --config-context "$REPO_ROOT" --extensions md,markdown,txt,yaml,yml,html,json \
  --count-only "$hook_work/files" || rc=$?
case "$rc" in
  0) exit 0 ;;
  1) echo "PII findings: inspect and remediate or route them, then run the checks again." >&2; exit 1 ;;
  *) echo "unverified: staged-file scan failed; fix the check before committing" >&2; exit 2 ;;
esac
HOOK
  } > "$body_file"
  hook_content=$(cat "$body_file")
  rm -f "$body_file"
  # A backup does not preserve an active check. Never replace an unknown or modified hook.
  if [[ -e "$hook_file" || -L "$hook_file" ]]; then
    if [[ -f "$hook_file" && ! -L "$hook_file" ]] && cmp -s "$hook_file" <(printf '%s\n' "$hook_content"); then
      echo "PII scanner hook already matches at $hook_file"
      return 0
    fi
    echo "refused: existing hook differs; retain it and consult the hook owner" >&2
    exit 2
  fi
  if [[ $dry_run -eq 1 ]]; then
    echo "dry-run: would install PII scanner hook at $hook_file"
    return 0
  fi
  [[ -d "$hook_dir" ]] || { echo "refused: hook directory is missing" >&2; exit 2; }
  (set -o noclobber; printf '%s\n' "$hook_content" > "$hook_file") || {
    echo "refused: could not create hook without replacing a file" >&2; exit 2;
  }
  chmod +x "$hook_file"
  echo "PII scanner pre-commit hook installed at $hook_file"
}

# --- Help ---
show_help() {
  cat <<'HELP'
pii-scanner.sh — Scan files for PII patterns

Usage:
  pii-scanner.sh [OPTIONS] <directory>
  pii-scanner.sh --install-hook [--dry-run] [<repo-path>]

Options:
  --count-only        Report totals per pattern type only
  --config <file>     Load patterns from YAML config (see format below)
  --config-context <dir>  Discover config from the original directory of a temporary copy
  --extensions <exts> Comma-separated extensions to scan (default: md)
  --install-hook      Install as git pre-commit hook in repo
  --dry-run           Preview hook installation without writing
  --help              Show this help

A hook installed by an older version cannot be upgraded by --install-hook.
The old hook has to be removed by hand first. Then run --install-hook again.

Exit codes:
  0  No PII found, hook installed, or installation preview
  1  PII matches found
  2  Usage, configuration, installation refusal, or unreadable input

Output format (default mode):
  PATH:LINE:PATTERN_NAME:matched_text
  In PATH, backslash is \\, colon is \:, and newline is \n.
  Split on unescaped colons. A colon in a filename is \: in PATH.

Config comments:
  A # preceded by whitespace, outside quotes, starts a comment.
  A # inside quotes, or not preceded by whitespace, is part of the value.

Config file format (.pii-patterns.yaml):
  patterns:
    - GMAIL_ID: 'gmail:[0-9a-fA-F]+'
    - PHONE: '\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}'
    - COMPANY_EMAIL: '[A-Za-z0-9._%+-]+@(mycompany|otherdomain)\b'
  allowlist:             # "exclude:" also supported for backward compatibility
    - '/(Users|home)/(username|yourname|realname|user)\b'
    - '\+1[- ]?555[- ]?[0-9]{3}[- ]?[0-9]{4}'
  extensions:
    - md
    - txt
    - yaml

Built-in patterns (always loaded; configuration adds patterns):
  GMAIL_ID         gmail:<hex> thread/message IDs
  PHONE            +1 North American phone numbers
  USER_PATH        /Users/<name> or /home/<name> paths
  CREDENTIALS_REF  .credentials/ directory references
  CHAT_USER_ID     Telegram/Discord numeric user IDs
  AWS_KEY          AWS access key IDs (AKIA...)
  API_SECRET       Generic API key/token/secret values
  TAILSCALE_HOST   Tailscale MagicDNS hostnames (*.ts.net)

Findings are never hidden by inline suppression markers. Classify explanatory
matches explicitly; do not exempt a whole line or file from inspection.
HELP
}

# --- Parse args ---
pat_names=()
pat_regexes=()
pat_allowlist=()
extensions_from_config=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h) show_help; exit 0 ;;
    --version) echo "pii-scanner $VERSION"; exit 0 ;;
    --count-only) count_only=1; shift ;;
    --config) [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { echo "refused: --config needs a path" >&2; exit 2; }; config_file="$2"; shift 2 ;;
    --config-context) [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { echo "refused: --config-context needs a directory" >&2; exit 2; }; config_context="$2"; shift 2 ;;
    --extensions) [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9]+(,[A-Za-z0-9]+)*$ ]] || { echo "refused: --extensions needs a comma-separated extension list" >&2; exit 2; }; extensions="$2"; extensions_given=1; shift 2 ;;
    --install-hook) install_hook=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --) shift; break ;;
    -*) echo "refused: unknown option" >&2; exit 2 ;;
    *) break ;;
  esac
done

# Handle install-hook
if [[ $install_hook -eq 1 ]]; then
  [[ $# -le 1 && -z "$config_file" && -z "$config_context" && $extensions_given -eq 0 && $count_only -eq 0 ]] || { echo "refused: incompatible hook-install arguments" >&2; exit 2; }
  do_install_hook "${1:-.}"
  exit 0
fi

[[ $dry_run -eq 0 ]] || { echo "refused: --dry-run is for hook installation" >&2; exit 2; }

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
discovery_dir="${config_context:-$target_dir}"
[[ -d "$discovery_dir" ]] || { echo "refused: configuration context is not a directory" >&2; exit 2; }
if [[ -z "$config_file" ]]; then
  # Auto-detect config: check target dir, then repo root, then home
  for candidate in \
    "$discovery_dir/.pii-patterns.yaml" \
    "$(git -C "$discovery_dir" rev-parse --show-toplevel 2>/dev/null)/.pii-patterns.yaml" \
    "$HOME/.pii-patterns.yaml"; do
    if [[ -f "$candidate" ]]; then
      config_file="$candidate"
      break
    fi
  done
fi

if [[ -n "$config_file" ]]; then
  if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
    echo "Error: config file not found: $config_file" >&2
    exit 2
  fi
  load_config "$config_file"
  # An --extensions given on the command line wins: a wrapper that asks for yaml and html must get them.
  [[ -n "$extensions_from_config" && $extensions_given -eq 0 ]] && extensions="$extensions_from_config"
fi

# Built-in patterns ALWAYS load; a config ADDS patterns and allowlist entries. (Before 3.1.0 a config replaced
# the built-ins, so a file with one custom pattern silently switched every other protection off.)
builtin_patterns

# A pattern grep cannot compile would match nothing and read as a clean scan. Refuse it instead.
for i in "${!pat_regexes[@]}"; do
  rc=0; printf '' | grep -Eq -- "${pat_regexes[$i]}" 2>/dev/null || rc=$?
  if [[ $rc -ge 2 ]]; then echo "Error: pattern ${pat_names[$i]} is not a valid extended regular expression" >&2; exit 2; fi
done
for i in "${!pat_allowlist[@]}"; do
  rc=0; [[ "" =~ ${pat_allowlist[$i]} ]] || rc=$?
  if [[ $rc -ge 2 ]]; then echo "Error: allowlist entry $((i+1)) is not a valid regular expression" >&2; exit 2; fi
done

# Build find expression for extensions
IFS=',' read -ra ext_array <<< "$extensions"
find_expr=()
for i in "${!ext_array[@]}"; do
  [[ $i -gt 0 ]] && find_expr+=("-o")
  find_expr+=("-iname" "*.${ext_array[$i]}")   # case-insensitive: NOTES.MD is a Markdown file, and a skipped file reads as clean
done

# A scan path with no ':' or newline, so grep's file:line:match split stays unambiguous.
# The real path is restored, with escapes, only when the report is printed.
resolve_abs() {
  local f=$1 dir base absdir
  dir=$(dirname -- "$f") || return 1
  base=$(basename -- "$f") || return 1
  absdir=$(cd -- "$dir" && pwd -P) || return 1
  printf '%s/%s' "$absdir" "$base"
}

escape_report_path() {
  local s=$1 out="" i c n
  n=${#s}
  for ((i=0; i<n; i++)); do
    c=${s:i:1}
    case "$c" in
      \\) out+='\\' ;;
      ':') out+='\:' ;;
      $'\n') out+='\n' ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

lookup_orig() {
  local s=$1 i
  for i in "${!safe_paths[@]}"; do
    if [[ ${safe_paths[$i]} == "$s" ]]; then
      printf '%s' "${orig_paths[$i]}"
      return 0
    fi
  done
  return 1
}

# Find files; a failed enumeration is not an empty successful scan.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
find "$target_dir" -type d \( -name .git -o -name .stversions -o -name node_modules \) -prune -o -type f \( "${find_expr[@]}" \) -print0 > "$work/files" || {
  echo "Error: could not enumerate scan input" >&2; exit 2;
}
mkdir -p "$work/scan"
sort -z "$work/files" > "$work/sorted-files"
safe_paths=()
orig_paths=()
file_count=0
while IFS= read -r -d '' f; do
  file_count=$((file_count + 1))
  id=$(printf '%08d' "$file_count")
  safe="$work/scan/$id"
  abs=$(resolve_abs "$f") || { echo "Error: could not read a scan path" >&2; exit 2; }
  ln -s -- "$abs" "$safe" || { echo "Error: could not read a scan path" >&2; exit 2; }
  safe_paths+=("$safe")
  orig_paths+=("$f")
done < "$work/sorted-files"

if [[ $file_count -eq 0 ]]; then
  exit 0
fi

: > "$work/safe"
for i in "${!safe_paths[@]}"; do
  printf '%s\0' "${safe_paths[$i]}" >> "$work/safe"
done

# --- Collect matches ---
# One grep per PATTERN over all files (3.1.0). The previous loop started a grep per line per pattern, which made
# a directory scan take minutes: long enough to be killed by an agent's shell limit and read as "no output".
# Grep sees colon-free stand-in names. A match may itself contain ':', so only the first two separators are structural.
: > "$work/candidates"
for i in "${!pat_names[@]}"; do
  if ! xargs -0 sh -c 'grep -EnoH -- "$@"; rc=$?; [ "$rc" -le 1 ]' sh "${pat_regexes[$i]}" < "$work/safe" 2>/dev/null \
    | awk -v name="${pat_names[$i]}" '
        BEGIN { FS = ":" }
        {
          m = $0; sub(/^[^:]*:[^:]*:/, "", m); if (m == "") next
          if (name == "AWS_KEY" || name == "API_SECRET") m = "<redacted>"
          print $1 ":" $2 ":" name ":" m }' >> "$work/candidates"; then
    echo "Error: scan input could not be read" >&2
    exit 2
  fi
done
# USER_PATH needs the prefix of each match to distinguish a home path from a URL or code path.
# The other patterns retain their batched grep path and custom configurations retain their behavior.
if ! xargs -0 awk -f "$(dirname "$0")/user-paths.awk" < "$work/safe" >> "$work/candidates"; then
  echo "Error: user-path scan input could not be read" >&2
  exit 2
fi
: > "$work/hits"
while IFS= read -r cand; do
  matched_text="${cand#*:*:*:}"
  is_allowlisted_match "$matched_text" && continue
  printf '%s\n' "$cand" >> "$work/hits"
done < "$work/candidates"
sort -t: -k1,1 -k2,2n -s "$work/hits" > "$work/sorted"

# --- Count-only mode ---
if [[ $count_only -eq 1 ]]; then
  total=0
  for name in "${pat_names[@]}" USER_PATH; do
    n=$(awk -F: -v name="$name" '$3 == name { c++ } END { print c + 0 }' "$work/sorted")
    printf "%s:%d\n" "$name" "$n"
    total=$(( total + n ))
  done
  [[ $total -gt 0 ]] && exit 1
  exit 0
fi

# --- Full scan mode ---
# Restore the real path. Escape \ : and newline so the path field stays one field.
: > "$work/report"
while IFS= read -r cand || [[ -n $cand ]]; do
  [[ -z $cand ]] && continue
  safe=${cand%%:*}
  rest=${cand#*:}
  orig=$(lookup_orig "$safe") || { echo "Error: scan path map missing an entry" >&2; exit 2; }
  printf '%s:%s\n' "$(escape_report_path "$orig")" "$rest" >> "$work/report"
done < "$work/sorted"
cat "$work/report"
[[ -s "$work/report" ]] && exit 1
exit 0
