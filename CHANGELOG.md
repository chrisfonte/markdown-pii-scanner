# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-03-05

### Added

- **GitHub Action marketplace-ready** — `action.yml` hardened for reliable output parsing and job summary generation
- **Parseable output** — all scan modes now emit `Total matches: N` summary line for machine consumption
- **Baseline output** — baseline mode now emits `New matches: N` for action integration
- **Job summary** — GitHub Action generates rich Markdown job summaries with match details
- **CHANGELOG.md** — this file

### Changed

- **action.yml** — rewritten with proper output forwarding, portable `grep` parsing, and correct baseline/fail-on-match interaction
- **Example workflow** — `.github/workflows/pii-scan.yml` now includes PR scan, push scan with baseline, and weekly audit jobs
- **README.md** — complete GitHub Action documentation with quick start, full configuration reference, all usage examples, badge snippet, and CLI vs hook vs action comparison table
- **Version references** — all examples now reference `@v2`

### Fixed

- Action output parsing now matches actual CLI output format (`Total matches: N` instead of non-existent format)
- Baseline mode correctly reports new match count to action outputs
- Job summary uses proper Markdown formatting (no escaped backticks)
- `fail-on-match` interaction with baseline mode — fails only on new matches, not existing ones

## [2.1.0] - 2026-02-28

### Added

- GitHub Action (`action.yml`) — composite action with shell-based runner
- Example workflow (`.github/workflows/pii-scan.yml`)
- Allowlist support in config files
- `.pii-ignore` file support (glob-based file exclusion)
- Baseline comparison mode (`--baseline`)
- Summary mode (`--summary`)
- Directory exclusion (`--exclude`)

## [2.0.0] - 2026-02-22

### Added

- Node.js CLI (`bin/markdown-pii-scanner.js`) — zero-dependency scanner
- Pre-commit hook installation (`--install-hook`)
- Custom pattern configuration via `.pii-patterns.yaml`
- Auto-config detection (target dir → repo root → home dir)
- Seven built-in PII patterns (GMAIL_ID, PHONE, USER_PATH, CREDENTIALS_REF, CHAT_USER_ID, AWS_KEY, API_SECRET)

## [1.0.0] - 2026-02-16

### Added

- Initial release — bash-only scanner (`pii-scanner.sh`)
- Core scanning with `--count-only` and `--config` support
- MIT license
