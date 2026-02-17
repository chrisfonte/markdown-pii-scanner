# markdown-pii-scanner

Scan markdown and text files for personally identifiable information before it hits git.

## The Problem

Documentation repos accumulate PII over time. Phone numbers land in meeting notes. Gmail thread IDs get pasted into working sessions. Absolute paths like `/Users/yourname/` reveal usernames. API keys sneak into config examples that were supposed to be placeholders.

Git never forgets. Once PII hits a public commit, it lives in the history forever, or until you run `git-filter-repo` (which means force-pushing and asking every contributor to re-clone). Prevention is always cheaper than remediation.

This tool was built after a real incident: a public documentation repo that accumulated hundreds of PII matches across months of active work. Phone numbers, email thread IDs, credential references, internal hostnames, all sitting in plain sight in markdown files. A pre-commit hook would have caught every single one.

## Install

```bash
# Global install
npm install -g markdown-pii-scanner

# One-shot (no install)
npx markdown-pii-scanner ./docs

# Bash alternative (no Node required)
curl -O https://raw.githubusercontent.com/chrisfonte/markdown-pii-scanner/main/pii-scanner.sh
chmod +x pii-scanner.sh
```

## Quick Start

```bash
# Scan a directory
markdown-pii-scanner ./docs

# Counts only (good for initial assessment)
markdown-pii-scanner --count-only ./docs

# Install pre-commit hook
markdown-pii-scanner --install-hook
```

## Built-in Patterns

Seven patterns cover the most common documentation PII leaks:

| Pattern | Catches | Example |
|---------|---------|---------|
| `GMAIL_ID` | Gmail thread/message IDs | `gmail:18a4f2b3c5d6e7f8` |
| `PHONE` | North American phone numbers | `+1 555-123-4567` |
| `USER_PATH` | Absolute user directory paths | `/Users/john/projects/` |
| `CREDENTIALS_REF` | Credential directory references | `.credentials/api-key` |
| `CHAT_USER_ID` | Telegram/Discord numeric user IDs | `user_id: 1234567890` |
| `AWS_KEY` | AWS access key IDs | `AKIAIOSFODNN7EXAMPLE` |
| `API_SECRET` | API keys, tokens, and secrets | `api_key = "sk-abc123..."` |

## Output

Default mode prints one match per line (greppable):

```
docs/meeting-notes.md:47:PHONE:+1 555-867-5309
docs/setup-guide.md:12:USER_PATH:/Users/jsmith
docs/api-docs.md:89:CREDENTIALS_REF:.credentials/prod
```

Count mode (`--count-only`) gives a summary:

```
GMAIL_ID:3
PHONE:2
USER_PATH:15
CREDENTIALS_REF:8
CHAT_USER_ID:0
AWS_KEY:0
API_SECRET:1
```

Exit codes: `0` clean, `1` matches found, `2` usage error.

## Custom Patterns

The built-in patterns are a starting point. For your own environment, create a `.pii-patterns.yaml` config:

```yaml
patterns:
  # Keep the built-ins you want
  - GMAIL_ID: 'gmail:[0-9a-fA-F]+'
  - PHONE: '\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}'
  - USER_PATH: '/(Users|home)/[A-Za-z0-9._-]+'

  # Add your own
  - COMPANY_EMAIL: '[A-Za-z0-9._%+-]+@(mycompany|internaldomain)\b'
  - INTERNAL_HOST: '[a-z0-9-]+\.internal\.mycompany\.net'
  - JIRA_TICKET: 'PRIV-[0-9]+'

extensions:
  - md
  - txt
  - yaml
```

**Tip**: If your patterns themselves reveal internal infrastructure (domain names, hostnames), keep the config in a private repo and pass it with `--config`.

### Config Auto-Detection

The scanner looks for `.pii-patterns.yaml` automatically, first match wins:

1. Target directory (`.pii-patterns.yaml` in the dir you're scanning)
2. Git repo root (`.pii-patterns.yaml` at the root of the repo containing the target)
3. Home directory (`~/.pii-patterns.yaml`)
4. Built-in patterns (fallback when no config is found)

Override everything with `--config <file>`.

## Pre-Commit Hook

This is the highest-value feature. Install once, never accidentally commit PII again.

```bash
# Install in current repo
markdown-pii-scanner --install-hook

# Install in a specific repo
markdown-pii-scanner --install-hook /path/to/repo
```

**What the hook does:**

- Scans only staged `.md`, `.markdown`, and `.txt` files (fast, not a full repo scan)
- Auto-loads `.pii-patterns.yaml` from repo root if present
- Blocks the commit and shows matches when PII is found
- Backs up any existing pre-commit hook before installing

**Override when needed:** `git commit --no-verify`

## All Options

```
markdown-pii-scanner [OPTIONS] <directory>
markdown-pii-scanner --install-hook [<repo-path>]

Options:
  --count-only        Totals per pattern type only
  --config <file>     Load patterns from a specific config file
  --extensions <exts> Comma-separated file extensions to scan (default: md)
  --install-hook      Install as git pre-commit hook
  --help              Show help
  --version           Show version
```

## Triage: Not Every Match Is a Leak

Context matters. A `.credentials/` reference in a credentials-management doc is documentation, not a leak. `/Users/<name>` in a path convention doc is an example, not an exposure.

**Likely legitimate:**
- Pattern inside a code block or example with placeholder values
- Documentation that explains the pattern itself
- Files in private repos (private is fine)

**Likely a real leak:**
- Real phone numbers or email addresses in prose
- Gmail thread IDs in public docs
- Absolute paths with actual usernames (not `/Users/<name>`)
- API keys or tokens in any file, anywhere

**When in doubt:** If you have to think about whether it's a leak, it probably is.

## Bash Alternative

The original bash implementation (`pii-scanner.sh`) is included in this repo. Same features, same output format, same exit codes. Works with bash 3.2+ (stock macOS included). Use it when Node isn't available.

```bash
./pii-scanner.sh --count-only ./docs
./pii-scanner.sh --install-hook
```

## OpenClaw Skill

This scanner is also available as an [OpenClaw](https://github.com/openclaw/openclaw) skill that adds agent intelligence: automatic scanning triggers, result triage, and PII remediation workflows. See [ClawHub](https://clawhub.ai) for installation.

## Contributing

Issues and PRs welcome at [github.com/chrisfonte/markdown-pii-scanner](https://github.com/chrisfonte/markdown-pii-scanner).

## License

MIT
