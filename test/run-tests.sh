#!/usr/bin/env bash
# Plain-bash checks for pii-scanner.sh. Fixtures live in a temp directory.
# Override the scanner with SCANNER=/path/to/pii-scanner.sh.

set -u

here=$(cd "$(dirname "$0")" && pwd)
SCANNER=${SCANNER:-$here/../pii-scanner.sh}

if [[ ! -f $SCANNER || ! -x $SCANNER ]]; then
  echo "FAIL scanner-present"
  echo "scanner is missing or not executable" >&2
  exit 1
fi

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
home=$root/home
mkdir -p "$home"

pass_n=0
fail_n=0

pass() {
  printf 'PASS %s\n' "$1"
  pass_n=$((pass_n + 1))
}

fail() {
  printf 'FAIL %s\n' "$1"
  fail_n=$((fail_n + 1))
}

# Split a report line on unescaped colons. Sets path_field, line_field, name_field, match_field.
split_report() {
  local s=$1 cur="" i c n
  path_field=""
  line_field=""
  name_field=""
  match_field=""
  local -a fields=()
  n=${#s}
  for ((i=0; i<n; i++)); do
    c=${s:i:1}
    if [[ $c == '\' && $((i + 1)) -lt $n ]]; then
      cur+="$c"
      cur+="${s:i+1:1}"
      i=$((i + 1))
      continue
    fi
    if [[ $c == ':' ]]; then
      fields+=("$cur")
      cur=""
      continue
    fi
    cur+="$c"
  done
  fields+=("$cur")
  path_field=${fields[0]:-}
  line_field=${fields[1]:-}
  name_field=${fields[2]:-}
  if [[ ${#fields[@]} -gt 3 ]]; then
    match_field=${fields[3]}
    local j
    for ((j=4; j<${#fields[@]}; j++)); do
      match_field+=:${fields[$j]}
    done
  fi
}

unescape_path() {
  local s=$1 out="" i c n nxt
  n=${#s}
  for ((i=0; i<n; i++)); do
    c=${s:i:1}
    if [[ $c == '\' && $((i + 1)) -lt $n ]]; then
      nxt=${s:i+1:1}
      case "$nxt" in
        \\) out+=$'\\' ;;
        ':') out+=':' ;;
        n) out+=$'\n' ;;
        *) out+="$c$nxt" ;;
      esac
      i=$((i + 1))
      continue
    fi
    out+="$c"
  done
  printf '%s' "$out"
}

run_scan() {
  scan_out=""
  scan_err=""
  scan_rc=0
  scan_err=$root/err.txt
  : > "$scan_err"
  set +e
  scan_out=$(HOME="$home" "$SCANNER" "$@" 2>"$scan_err")
  scan_rc=$?
  set -e
}

new_dir() {
  mktemp -d "$root/case.XXXXXX"
}

gmail_text() {
  printf 'gmail:%s\n' "abc123"
}

# --- cases ---

d=$(new_dir)
printf '%s\n' "$(gmail_text)" > "$d/note.md"
run_scan "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":GMAIL_ID:gmail:"* ]]; then
  pass builtins-fire
else
  fail builtins-fire
fi

d=$(new_dir)
printf '%s@%s\n' "ada" "scanner-fixture.net" > "$d/note.md"
run_scan "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":EMAIL:"* ]]; then
  pass email-shape
else
  fail email-shape
fi

d=$(new_dir)
printf '%s-%s-%s\n' "212" "867" "5309" > "$d/note.md"
run_scan "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":PHONE:"* ]]; then
  pass phone-shape
else
  fail phone-shape
fi

d=$(new_dir)
key=$(printf '%s%s' "AKIA" "IOSFODNN7EXAMPLE")
printf '%s\n' "$key" > "$d/note.md"
run_scan "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":AWS_KEY:<redacted>"* && $scan_out != *"$key"* ]]; then
  pass aws-key-redacted
else
  fail aws-key-redacted
fi

d=$(new_dir)
cfg=$d/patterns.yaml
cat > "$cfg" <<'EOF'
patterns:
  - ZED: "zzz[0-9]+"
EOF
{
  gmail_text
  printf 'zzz%s\n' "4"
} > "$d/note.md"
run_scan --config "$cfg" "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":GMAIL_ID:"* && $scan_out == *":ZED:"* ]]; then
  pass custom-config-adds-to-builtins
else
  fail custom-config-adds-to-builtins
fi

d=$(new_dir)
cfg=$d/patterns.yaml
cat > "$cfg" <<'EOF'
patterns:
  - ZED: "zzz[0-9]+"   # note
EOF
printf 'zzz%s\n' "7" > "$d/note.md"
run_scan --config "$cfg" "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":ZED:"* ]]; then
  pass trailing-comment-pattern
else
  fail trailing-comment-pattern
fi

d=$(new_dir)
cfg=$d/patterns.yaml
cat > "$cfg" <<'EOF'
patterns:
  - HASHY: "foo#bar"
EOF
printf '%s#%s\n' "foo" "bar" > "$d/note.md"
run_scan --config "$cfg" "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":HASHY:"* ]]; then
  pass hash-inside-quoted-regex
else
  fail hash-inside-quoted-regex
fi

d=$(new_dir)
cfg=$d/patterns.yaml
cat > "$cfg" <<'EOF'
patterns:
  - HASHY: foo#bar[0-9]+
EOF
printf '%s#%s%s\n' "foo" "bar" "7" > "$d/note.md"
run_scan --config "$cfg" "$d"
if [[ $scan_rc -eq 1 && $scan_out == *":HASHY:"* ]]; then
  pass hash-without-leading-space
else
  fail hash-without-leading-space
fi

d=$(new_dir)
colon_name="note:a.md"
printf '%s\n' "$(gmail_text)" > "$d/$colon_name"
run_scan "$d"
split_report "$scan_out"
decoded=$(unescape_path "$path_field")
if [[ $scan_rc -eq 1 && $decoded == "$d/$colon_name" && $line_field == "1" && $name_field == "GMAIL_ID" && $scan_out != *$'\n'* ]]; then
  pass colon-filename
else
  fail colon-filename
fi

d=$(new_dir)
nl_name=$'note\nname.md'
printf '%s\n' "$(gmail_text)" > "$d/$nl_name"
run_scan "$d"
# One physical report line: the newline in the name is the two characters \ n.
split_report "$scan_out"
decoded=$(unescape_path "$path_field")
if [[ $scan_rc -eq 1 && $decoded == "$d/$nl_name" && $line_field == "1" && $name_field == "GMAIL_ID" && $scan_out != *$'\n'* ]]; then
  pass newline-filename
else
  fail newline-filename
fi

d=$(new_dir)
printf 'hello\n' > "$d/note.md"
run_scan "$d"
if [[ $scan_rc -eq 0 && -z $scan_out ]]; then
  pass exit-code-0
else
  fail exit-code-0
fi

d=$(new_dir)
printf '%s\n' "$(gmail_text)" > "$d/note.md"
run_scan "$d"
if [[ $scan_rc -eq 1 ]]; then
  pass exit-code-1
else
  fail exit-code-1
fi

d=$(new_dir)
cfg=$d/bad.yaml
printf '%s\n' "patterns:" '  - BAD: "("' > "$cfg"
run_scan "$d/missing"
rc_missing=$scan_rc
run_scan --config "$cfg" "$d"
rc_bad=$scan_rc
run_scan --not-an-option "$d"
rc_flag=$scan_rc
if [[ $rc_missing -eq 2 && $rc_bad -eq 2 && $rc_flag -eq 2 ]]; then
  pass exit-code-2
else
  fail exit-code-2
fi

d=$(new_dir)
git init -q "$d"
run_scan --install-hook --dry-run "$d"
hook=$d/.git/hooks/pre-commit
if [[ $scan_rc -eq 0 && ! -e $hook ]]; then
  pass install-hook-dry-run-writes-nothing
else
  fail install-hook-dry-run-writes-nothing
fi

d=$(new_dir)
git init -q "$d"
hook=$d/.git/hooks/pre-commit
printf '%s\n' "#!/bin/sh" "echo kept" > "$hook"
chmod +x "$hook"
before=$(shasum -a 256 "$hook")
run_scan --install-hook "$d"
after=$(shasum -a 256 "$hook")
if [[ $scan_rc -eq 2 && $before == "$after" ]]; then
  pass existing-hook-refused
else
  fail existing-hook-refused
fi

printf 'TOTAL pass=%s fail=%s\n' "$pass_n" "$fail_n"
if [[ $fail_n -ne 0 ]]; then
  exit 1
fi
exit 0
