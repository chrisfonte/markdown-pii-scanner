# PII Scanner Roadmap

## Product Vision

Lightweight, zero-dependency PII scanning for git workflows. The missing guardrail for AI-assisted development.

**Tagline**: *PII guardrails for the AI-assisted development era.*

## The Gap

As of Feb 2026, no tool fills this niche:

| Tool | What It Is | Why It's Not This |
|------|-----------|-------------------|
| Microsoft Presidio | NLP-based PII framework (Python) | Heavy, meant for data pipelines, not git hooks |
| Octopii (RedHunt Labs) | AI-powered PII scanner (Python) | Security research focused, not CI/CD |
| thoughtbot/top_secret | Ruby PII filter | Filters before sending to LLMs, not git-aware |
| AWS Sensitive Data Protection | Enterprise cloud PII | Cloud-scale, not dev tooling |
| git-secrets / detect-secrets | Secret scanners | Credentials only — not PII (names, phones, paths, IDs) |
| truffleHog | Git history secret scanner | Secrets in git history, not PII in docs |
| GitHub Actions Marketplace | — | **Zero results** for "pii scanner" |

**What's missing**: A fast, zero-dependency scanner that runs in pre-commit hooks AND GitHub Actions, catches PII (not just secrets), and works regardless of who or what made the commit — human, Copilot, Claude, Codex, or any autonomous agent.

## Why Now

AI agents are writing and committing code autonomously. They're fast, productive, and terrible at remembering what's sensitive. A human might catch a real phone number in a PR review. An agent committing at 3 AM won't.

- **Copilot** autocompletes real paths, emails, IDs from context
- **Codex/Claude** generate example data that's sometimes real data
- **Autonomous agents** commit without human review
- **`git commit --no-verify`** bypasses local hooks — server-side enforcement needed

PII scanning should be infrastructure, not discipline.

## Distribution Channels

Three ways to use it, all agent-agnostic:

1. **CLI** — `npx markdown-pii-scanner <dir>` (or bash: `pii-scanner.sh <dir>`)
2. **Pre-commit hook** — `pii-scanner.sh --install-hook <repo>` (local enforcement)
3. **GitHub Action** — one-line workflow YAML (server-side enforcement, can't bypass)

## Marketing Angles

1. **AI Safety** — "Your AI agent just committed your phone number to a public repo. Again."
2. **Compliance** — GDPR, CCPA, HIPAA all care about PII in source code
3. **Zero Friction** — `npx markdown-pii-scanner .` — that's it. No config, no signup, no cloud.
4. **Belt and Suspenders** — Local hook catches it before commit. GitHub Action catches it if the hook was bypassed.
5. **Agent-Agnostic** — Doesn't matter if a human, Copilot, Claude, or Codex wrote it. PII is PII.

## What's Next

Actionable items, feature requests, and discussion live in [GitHub Issues](https://github.com/chrisfonte/markdown-pii-scanner/issues).

Key milestones:
- **v2.1** — Dogfooding, npm/ClawHub publish ([#1](https://github.com/chrisfonte/markdown-pii-scanner/issues/1))
- **v3.0** — GitHub Action ([#2](https://github.com/chrisfonte/markdown-pii-scanner/issues/2))
- **Future** — Pre-commit frameworks ([#3](https://github.com/chrisfonte/markdown-pii-scanner/issues/3)), VS Code extension ([#4](https://github.com/chrisfonte/markdown-pii-scanner/issues/4)), community pattern library ([#5](https://github.com/chrisfonte/markdown-pii-scanner/issues/5))

## Key Insight

> The best feature ideas came from one real scan, not from planning sessions. v1 shipped, one scan of a real repo revealed 4 missing features, v2 shipped the same day.

## Links
- **GitHub**: https://github.com/chrisfonte/markdown-pii-scanner
- **OpenClaw Skill**: Available on [ClawHub](https://clawhub.com) (coming soon)
