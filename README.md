# markdown-pii-scanner

**PII guardrails for the AI-assisted development era.**

Lightweight, zero-dependency PII scanning for git workflows. Catches personal information leaks before they hit version control — whether committed by a human, GitHub Copilot, Claude, Cursor, or any AI coding agent.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub Action](https://img.shields.io/badge/GitHub_Action-available-blue)](https://github.com/chrisfonte/markdown-pii-scanner)

## The Problem

Documentation repos accumulate PII over time. Phone numbers land in meeting notes. Gmail thread IDs get pasted into working sessions. Absolute paths like `/Users/yourname/` reveal usernames. API keys sneak into config examples that were supposed to be placeholders.

Git never forgets. Once PII hits a public commit, it lives in the history forever, or until you run `git-filter-repo` (which means force-pushing and asking every contributor to re-clone). Prevention is always cheaper than remediation.

**This matters more now than ever.** AI agents (Copilot, Codex, Claude, autonomous coding tools) are writing and committing code without human review. They're fast, productive, and terrible at remembering what's sensitive. A human might catch a phone number in a PR review. An agent committing at 3 AM won't.

PII scanning should be infrastructure, not discipline.

## Why This Matters Now

**AI coding assistants are productive, fast, and terrible at remembering what's sensitive.**

GitHub Copilot, Claude, Cursor, Windsurf, and other AI agents write code and documentation at unprecedented speed. They're also context-blind: they'll happily include real phone numbers from your chat history, paste actual file paths from examples, or leak Gmail thread IDs from debug logs.

A human might catch a phone number in a PR review. An autonomous agent committing at 3 AM won't.

**PII scanning should be infrastructure, not discipline.**

This tool provides three layers of defense:
1. **Pre-commit hook** — catches leaks before they enter git history
2. **GitHub Action** — enforces scans on all PRs (can't be bypassed with `--no-verify`)
3. **CLI** — one-shot audits for repos, documentation sites, knowledge bases

## Why Not Just Use...

| Tool | What It Does | Why It's Not Enough |
|------|-------------|-------------------|
| **Gitleaks** | Blocks secrets (API keys, tokens) | Secrets only. Won't catch phone numbers, user paths, or Gmail IDs. Requires license for orgs. |
| **TruffleHog** | Secret detection + verification | AGPL license (less permissive). Heavy-weight. Not markdown-specific. |
| **detect-secrets** | Baseline-driven secret prevention | Python-based. Generic secrets, not PII-focused. No official GitHub Action. |
| **Microsoft Presidio** | NLP-based PII detection framework | Python, heavy dependencies, designed for data pipelines. Not a git hook. |

**This tool is different:**
- ✅ **Markdown-specific** — designed for docs, wikis, knowledge bases
- ✅ **PII-focused** — catches phone numbers, emails, file paths, chat IDs (not just API keys)
- ✅ **Zero dependencies** — pure Node.js or bash, runs in milliseconds
- ✅ **Triple distribution** — CLI + pre-commit hook + GitHub Action
- ✅ **MIT licensed** — no enterprise upsell, no proprietary restrictions
- ✅ **AI-era positioning** — explicitly designed to catch leaks from AI coding agents

## Install

```bash
# Clone and use directly (npm publish coming soon)
git clone https://github.com/chrisfonte/markdown-pii-scanner.git
cd markdown-pii-scanner
node bin/markdown-pii-scanner.js ./your-docs

# Or just grab the bash version (no Node required)
curl -O https://raw.githubusercontent.com/chrisfonte/markdown-pii-scanner/main/pii-scanner.sh
chmod +x pii-scanner.sh
./pii-scanner.sh ./your-docs
```

Once published to npm:
```bash
# One-shot (no install needed)
npx markdown-pii-scanner ./docs

# Global install
npm install -g markdown-pii-scanner
```

## Quick Start

```bash
# Scan a directory
markdown-pii-scanner ./docs

# Counts only (good for initial assessment)
markdown-pii-scanner --count-only ./docs

# Install pre-commit hook (highest-value feature)
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

Default mode prints one match per line (greppable), plus a summary:

```
docs/meeting-notes.md:47:PHONE:+1 555-867-5309
docs/setup-guide.md:12:USER_PATH:/Users/jsmith
docs/api-docs.md:89:CREDENTIALS_REF:.credentials/prod
Total matches: 3
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
Total matches: 29
```

Exit codes: `0` clean, `1` matches found, `2` usage error.

## Distribution Channels

This tool provides **three complementary ways** to prevent PII leaks:

### 1. CLI (One-Shot Scans)

```bash
npx markdown-pii-scanner ./docs
```

Good for: ad-hoc audits, local development, non-Git workflows, CI systems other than GitHub.

### 2. Pre-Commit Hook (Developer-Side Prevention)

Install once, never accidentally commit PII again.

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

**Override when needed:** `git commit --no-verify` (but consider why you need to).

**Limitation:** Hooks are local. Contributors who forget to install the hook (or bypass it with `--no-verify`) won't be protected. For team enforcement, use the GitHub Action.

### 3. GitHub Action (Team-Side Enforcement)

**The pre-commit hook provides fast feedback. The GitHub Action provides enforcement.**

Add to your repo's `.github/workflows/pii-scan.yml`:

```yaml
name: PII Scanner

on:
  pull_request:
    paths: ['**.md']
  push:
    branches: [main]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: chrisfonte/markdown-pii-scanner@v2
        with:
          path: '.'
          fail-on-match: true
```

That's it — three lines in your workflow (plus checkout), and every PR and push is scanned.

**Add a badge to your README:**

```markdown
[![PII Scanner](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/pii-scan.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/pii-scan.yml)
```

**Why use the GitHub Action?**

| Scenario | Local Hook | GitHub Action | Winner |
|----------|------------|---------------|--------|
| Developer forgets to install | ❌ No protection | ✅ Catches it | **Action** |
| Developer bypasses with `--no-verify` | ❌ No protection | ✅ Catches it | **Action** |
| New contributor (first PR) | ❌ No hook installed | ✅ Scans automatically | **Action** |
| Fast local feedback | ✅ Instant | ❌ Waits for CI | **Hook** |
| Works offline | ✅ Yes | ❌ No | **Hook** |

**Both are necessary.** The hook provides speed. The action provides safety.

#### Action Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `path` | Directory to scan | `.` |
| `config` | Custom config file path | (auto-detected) |
| `baseline` | Baseline file for delta comparison | (none) |
| `exclude` | Comma-separated dirs to skip | (none) |
| `fail-on-match` | Fail workflow if PII found | `true` |
| `summary` | Show directory summary | `false` |

#### Action Outputs

| Output | Description |
|--------|-------------|
| `matches-found` | Number of PII matches |
| `new-matches` | New matches since baseline |

#### Workflow Examples

**PR Scanning (Changed Files Only)**

Fast, targeted scanning for pull requests:

```yaml
name: PII Scanner

on:
  pull_request:
    paths: ['**.md']

jobs:
  pr-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Get changed files
        id: changed
        run: |
          git diff --name-only origin/${{ github.base_ref }}...HEAD \
            | grep -E '\.(md|markdown)$' > changed.txt || true
      
      - uses: chrisfonte/markdown-pii-scanner@v2
        if: hashFiles('changed.txt') != ''
        with:
          path: '.'
          fail-on-match: true
```

**Scheduled Full Repo Audit**

Weekly scan of entire repo:

```yaml
name: PII Audit

on:
  schedule:
    - cron: '0 9 * * 1'  # Mondays at 9 AM UTC

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: chrisfonte/markdown-pii-scanner@v2
        with:
          path: 'docs'
          exclude: 'archive,vendor'
          summary: true
```

**Baseline Mode (Track Known PII, Flag New Only)**

For repos with existing PII that can't be removed:

```yaml
name: PII Scanner

on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Download baseline
        uses: dawidd6/action-download-artifact@v3
        continue-on-error: true
        with:
          workflow: pii-scan.yml
          branch: main
          name: pii-baseline
      
      - uses: chrisfonte/markdown-pii-scanner@v2
        with:
          baseline: '.pii-baseline.json'
          fail-on-match: true  # Only fails on NEW matches
      
      - name: Upload updated baseline
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: pii-baseline
          path: .pii-baseline.json
```

**Custom Config for Private Patterns**

Use repository secrets or committed config files:

```yaml
- uses: chrisfonte/markdown-pii-scanner@v2
  with:
    config: '.pii-patterns.yaml'  # In repo
    path: 'docs'
```

Or use GitHub Secrets for sensitive patterns:

```yaml
- name: Create config from secret
  run: echo "${{ secrets.PII_CONFIG }}" > .pii-config.yaml

- uses: chrisfonte/markdown-pii-scanner@v2
  with:
    config: '.pii-config.yaml'
```

### When to Use Which

| Use Case | CLI | Pre-Commit Hook | GitHub Action |
|----------|-----|-----------------|---------------|
| Ad-hoc audit of a docs folder | ✅ | — | — |
| Block PII before every commit | — | ✅ | — |
| Enforce across all PRs | — | — | ✅ |
| Catch `--no-verify` bypasses | — | ❌ | ✅ |
| New contributor (first PR) | — | ❌ (not installed) | ✅ |
| Fastest feedback loop | ✅ | ✅ | — |
| Works offline | ✅ | ✅ | ❌ |
| Scheduled weekly audit | — | — | ✅ |
| CI/CD pipeline (non-GitHub) | ✅ | — | — |

**Best practice:** Use the pre-commit hook AND the GitHub Action together. The hook provides instant feedback during development. The action provides enforcement that can't be bypassed.

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

### Allowlists

Suppress false positives by adding an `allowlist:` section to your config. Each entry is a regex matched against the detected text:

```yaml
allowlist:
  - '\.credentials/'           # CLI tools that document credential paths
  - '/(Users|home)/the-user'   # Generic example paths in docs
  - '\+1[- ]?555'              # Placeholder phone numbers
```

**Format**: Each entry is `- 'regex'` (a bare regex string). The `- NAME: 'regex'` format used in `patterns:` does **not** work for allowlist entries.

`exclude:` is also accepted as an alias for `allowlist:`.

**Example**: A CLI tool that documents `~/.credentials/api-key` in its README would add `'\.credentials/'` to the allowlist so those references aren't flagged.

### Config Auto-Detection

The scanner looks for `.pii-patterns.yaml` automatically. First match wins:

1. Target directory (`.pii-patterns.yaml` in the dir you're scanning)
2. Git repo root (`.pii-patterns.yaml` at the root of the repo containing the target)
3. Home directory (`~/.pii-patterns.yaml`)
4. Built-in patterns (fallback when no config is found)

Override everything with `--config <file>`.

## Summary Mode

Get a high-level view of where PII lives in your repo:

```bash
markdown-pii-scanner --summary ./docs
```

Output:
```
=== By Directory ===
1061  docs/03-client-projects
891   docs/04-professional
272   projects/production
=== Top Files ===
159  projects/production/monitoring/link.txt
91   docs/research/playoutone-analysis.md
```

## Baseline Comparison

Track PII over time. First run saves the baseline, subsequent runs report the delta:

```bash
# First run: saves counts to baseline file
markdown-pii-scanner --count-only --baseline .pii-baseline.json ./docs

# Later runs: shows what changed
markdown-pii-scanner --count-only --baseline .pii-baseline.json ./docs
# PHONE: 45 (baseline: 43, +2 new)
# USER_PATH: 30 (baseline: 30, no change)
```

Exit code is `0` if no NEW matches appeared since baseline, even if the total count is non-zero. This makes CI integration practical for existing repos with known PII.

## Excluding Directories

Focus your scan by skipping directories:

```bash
markdown-pii-scanner --exclude node_modules,vendor,dist ./docs
```

Matches against directory basename, not full path.

## Ignore File

Create a `.pii-ignore` file in your repo root (like `.gitignore`):

```
# Legitimate credential documentation
docs/meta/credentials-management/**

# Test fixtures
tests/fixtures/**

# Generated files
dist/**
```

Supports `*`, `**`, and `?` glob patterns. Comments (`#`) and blank lines are ignored.

## All Options

```
markdown-pii-scanner [OPTIONS] <directory>
markdown-pii-scanner --install-hook [<repo-path>]

Options:
  --count-only        Totals per pattern type only
  --summary           Group by directory + top 10 files (Node only)
  --config <file>     Load patterns from a specific config file
  --exclude <dirs>    Comma-separated directory names to skip (Node only)
  --extensions <exts> Comma-separated file extensions to scan (default: md)
  --baseline <file>   JSON baseline for delta comparison (Node only)
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

The original bash implementation (`pii-scanner.sh`) is included in this repo. Works with bash 3.2+ (stock macOS). Use it when Node isn't available or for maximum portability in CI.

```bash
./pii-scanner.sh ./docs
./pii-scanner.sh --count-only ./docs
./pii-scanner.sh --config .pii-patterns.yaml ./docs
./pii-scanner.sh --install-hook
```

**Feature parity note:** The bash version supports core scanning (`--count-only`, `--config`, `--extensions`, `--install-hook`). Advanced features (`--summary`, `--baseline`, `--exclude`, `.pii-ignore`) are Node-only. Both versions produce identical output format and exit codes for the features they share.

## Use With AI Agents

If you're running autonomous coding agents (OpenClaw, Devin, Cursor, Windsurf, or custom setups), this tool provides guardrails for agent-generated commits:

- **Pre-commit hook**: Blocks PII before it reaches git, regardless of who created the file
- **CI integration**: Server-side enforcement that can't be bypassed with `--no-verify`
- **Baseline mode**: Lets agents work in repos with existing PII without false positives on every commit

This tool is also available as an [OpenClaw](https://github.com/openclaw/openclaw) skill with agent intelligence: automatic scanning triggers, result triage, and PII remediation workflows. See [ClawHub](https://clawhub.com) for installation.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for product vision and competitive landscape. Feature requests and discussion in [GitHub Issues](https://github.com/chrisfonte/markdown-pii-scanner/issues).

## Contributing

Issues, feature requests, and PRs welcome at [github.com/chrisfonte/markdown-pii-scanner](https://github.com/chrisfonte/markdown-pii-scanner).

**Good first contributions:**
- New built-in patterns for common PII types
- Support for additional file extensions
- CI pipeline examples (GitLab, Bitbucket)
- Integration with pre-commit frameworks (husky, pre-commit.com, lefthook)

## License

MIT
