# markdown-pii-scanner

Scan markdown (and other text) files for common PII patterns. This is a pure Node.js CLI with zero dependencies.

## Usage

```bash
markdown-pii-scanner [OPTIONS] <directory>
markdown-pii-scanner --install-hook [<repo-path>]
```

Options:

- `--count-only`        Report totals per pattern type only
- `--config <file>`     Load patterns from YAML config (see format below)
- `--extensions <exts>` Comma-separated extensions to scan (default: md)
- `--install-hook`      Install as git pre-commit hook in repo
- `--help`              Show help
- `--version`           Show version

Exit codes:

- `0` No PII found (clean)
- `1` PII matches found
- `2` Usage error

## Examples

```bash
# Scan a directory
markdown-pii-scanner ./docs

# Count-only
markdown-pii-scanner --count-only ./docs

# Custom extensions
markdown-pii-scanner --extensions md,markdown,txt ./docs

# Custom config
markdown-pii-scanner --config ./docs/.pii-patterns.yaml ./docs
```

## Output format

```
file:line:PATTERN_NAME:matched_text
```

## Config format

Config is a very small YAML subset. Only `patterns:` and `extensions:` are supported.

```yaml
patterns:
  - GMAIL_ID: 'gmail:[0-9a-fA-F]+'
  - PHONE: '\\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}'
  - COMPANY_EMAIL: '[A-Za-z0-9._%+-]+@(mycompany|otherdomain)\\b'
extensions:
  - md
  - txt
  - yaml
```

## Built-in patterns

Used when no config file is found.

- `GMAIL_ID`         gmail:<hex> thread/message IDs
- `PHONE`            +1 North American phone numbers
- `USER_PATH`        /Users/<name> or /home/<name> paths
- `CREDENTIALS_REF`  .credentials/ directory references
- `CHAT_USER_ID`     Telegram/Discord numeric user IDs
- `AWS_KEY`          AWS access key IDs (AKIA...)
- `API_SECRET`       Generic API key/token/secret values

## Config auto-detect order

1. `<target-dir>/.pii-patterns.yaml`
2. Git repo root containing `<target-dir>`
3. `~/.pii-patterns.yaml`
4. Built-in patterns

## Pre-commit hook

Install the hook:

```bash
markdown-pii-scanner --install-hook
```

This creates `.git/hooks/pre-commit` that scans staged markdown files. If any PII is found, the commit is blocked and you can bypass with `git commit --no-verify`.

## Bash alternative

The original bash implementation is kept as `pii-scanner.sh`.
