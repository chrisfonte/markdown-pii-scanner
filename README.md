# markdown-pii-scanner

A zero-dependency CLI tool that scans markdown and text files for personally identifiable information (PII) before it leaks into git.

## Why This Exists

If you maintain documentation alongside code — especially across public and private repos — PII leaks are inevitable. Phone numbers end up in meeting notes. Gmail thread IDs get pasted into working sessions. Absolute paths like `/Users/yourname/` reveal usernames. API keys sneak into config examples.

These aren't hypothetical. This tool was born from real incidents: a public documentation repo that accumulated phone numbers, email thread IDs, credential references, and infrastructure hostnames across hundreds of markdown files over months of active use. A pre-commit hook would have caught every single one.

**The problem**: Git never forgets. Once PII hits a public commit, it's in the history forever (or until you run `git-filter-repo`, which is painful). Prevention beats remediation.

**The solution**: Scan before you commit. This tool catches common PII patterns in `.md`, `.txt`, `.yaml`, and other text files, with configurable patterns for your specific environment.

## Install

```bash
# npm (global)
npm install -g markdown-pii-scanner

# npx (no install)
npx markdown-pii-scanner ./docs

# Or use the bash version directly (no Node required)
curl -O https://raw.githubusercontent.com/chrisfonte/markdown-pii-scanner/main/pii-scanner.sh
chmod +x pii-scanner.sh
```

## Quick Start

```bash
# Scan a directory
markdown-pii-scanner ./docs

# Just the counts
markdown-pii-scanner --count-only ./docs

# Install a pre-commit hook (the real value)
markdown-pii-scanner --install-hook
```

## What It Catches

Seven built-in patterns cover the most common documentation PII leaks:

| Pattern | What It Catches | Example |
|---------|----------------|---------|
| `GMAIL_ID` | Gmail thread/message IDs | `gmail:18a4f2b3c5d6e7f8` |
| `PHONE` | North American phone numbers | `+1 555-123-4567` |
| `USER_PATH` | Absolute paths with usernames | `/Users/john/projects/` |
| `CREDENTIALS_REF` | Credential directory references | `.credentials/api-key` |
| `CHAT_USER_ID` | Telegram/Discord numeric IDs | `user_id: 1234567890` |
| `AWS_KEY` | AWS access key IDs | `AKIAIOSFODNN7EXAMPLE` |
| `API_SECRET` | API keys, tokens, secrets | `api_key = "sk-abc123..."` |

## Custom Patterns

The built-in patterns are a starting point. For your own environment, create a `.pii-patterns.yaml` config file:

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

### Config Auto-Detection

The scanner looks for config files automatically (first found wins):

1. `<target-dir>/.pii-patterns.yaml` — per-directory config
2. Git repo root `/.pii-patterns.yaml` — per-repo config
3. `~/.pii-patterns.yaml` — global user config
4. Built-in patterns — fallback if no config found

Override with `--config <file>` to use a specific config (useful when your config lives in a private repo).

## Pre-Commit Hook

The killer feature. Install once, never commit PII again:

```bash
# Install in current repo
markdown-pii-scanner --install-hook

# Install in a specific repo
markdown-pii-scanner --install-hook /path/to/repo
```

The hook:
- Scans only **staged** `.md`, `.markdown`, and `.txt` files (fast — doesn't scan the whole repo)
- Auto-loads `.pii-patterns.yaml` from repo root if present
- Blocks the commit and shows matches if PII is found
- Override when needed: `git commit --no-verify`
- Backs up any existing pre-commit hook before installing

## Output Format

Default mode outputs one match per line, greppable:

```
docs/meeting-notes.md:47:PHONE:+1 555-867-5309
docs/setup-guide.md:12:USER_PATH:/Users/jsmith
docs/api-docs.md:89:CREDENTIALS_REF:.credentials/prod
```

Count-only mode (`--count-only`) gives a summary:

```
GMAIL_ID:3
PHONE:2
USER_PATH:15
CREDENTIALS_REF:8
CHAT_USER_ID:0
AWS_KEY:0
API_SECRET:1
```

## All Options

```
markdown-pii-scanner [OPTIONS] <directory>
markdown-pii-scanner --install-hook [<repo-path>]

Options:
  --count-only        Report totals per pattern type only
  --config <file>     Load patterns from a specific config file
  --extensions <exts> Comma-separated extensions to scan (default: md)
  --install-hook      Install as git pre-commit hook
  --help              Show help
  --version           Show version

Exit codes:
  0  No PII found (clean)
  1  PII matches found
  2  Usage error
```

## Bash Alternative

The original bash implementation (`pii-scanner.sh`) is included in this repo. Same features, same output format, same exit codes. Use it when Node.js isn't available — it works with bash 3.2+ (stock macOS).

```bash
./pii-scanner.sh --count-only ./docs
./pii-scanner.sh --install-hook
```

## Tips

- **Start with `--count-only`** on an existing repo to see the scope before diving into individual matches
- **Not every match is a real leak** — `.credentials/` mentioned in a credentials-management doc is documentation, not a leak. Use judgment.
- **Put your config in a private repo** if your patterns themselves reveal internal infrastructure (domain names, hostnames, etc.)
- **Install the hook on every public repo** — it's the single highest-value action

## License

MIT
