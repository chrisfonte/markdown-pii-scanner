# PII Scanner v3.0 — Bash Script Improvements

## Context
You're working on `markdown-pii-scanner`, a PII scanning tool with both a Node.js CLI (`bin/markdown-pii-scanner.js`) and a bash script (`pii-scanner.sh`). The Node version already has allowlist support. The bash version does NOT — that's the main bug.

The bash script is ~300 lines, uses parallel arrays for patterns (bash 3.2 compatible), and is the version used by pre-commit hooks in production.

## Tasks (all in `pii-scanner.sh`)

### 1. Implement allowlist support
The config YAML already has an `allowlist:` section with regex entries:
```yaml
allowlist:
  - '/(Users|home)/(username|yourname|realname|user)\b'
  - '\+1[- ]?555[- ]?[0-9]{3}[- ]?[0-9]{4}'
```

The `load_config` function already detects `allowlist:` as a section header (via the `in_exclude` flag on line 76 — it uses `exclude:` as the key, but should also support `allowlist:`). But it never actually parses the entries.

**Implementation:**
- Add a `pat_allowlist=()` array alongside `pat_names` and `pat_regexes`
- In `load_config`, under the `allowlist:` (or `exclude:`) section, parse entries the same way patterns are parsed but into `pat_allowlist`
- Also support the `allowlist:` key name (not just `exclude:`)
- In both count-only and full-scan modes: after a match is found, check if the matched text (`BASH_REMATCH[0]`) matches any allowlist regex — if so, skip it
- The Node version's behavior (lines 468-475, 547-553, 620-627 in the JS) is the reference

### 2. Add inline suppression
If a line contains `pii-ignore` (as a comment, anywhere on the line), skip all pattern matching for that line.

**Implementation:**
- In both the count-only and full-scan loops, before checking patterns, check: `if [[ "$line" == *"pii-ignore"* ]]; then continue; fi`
- Simple substring match is fine — it covers `# pii-ignore`, `<!-- pii-ignore -->`, `// pii-ignore`, etc.

### 3. Add TAILSCALE_HOST to built-in patterns
In the `builtin_patterns()` function, add:
```bash
pat_names+=("TAILSCALE_HOST")
pat_regexes+=('[a-z0-9-]+\.[a-z0-9-]+\.ts\.net')
```
This catches any Tailscale MagicDNS hostname (e.g., `my-machine.tailnet-name.ts.net`).

### 4. Bump version
Change `VERSION="2.0.0"` to `VERSION="3.0.0"` at the top of the file.

### 5. Update help text
Add `TAILSCALE_HOST` to the built-in patterns table in `show_help()`.
Add a note about `pii-ignore` inline suppression.
Add a note about `allowlist:` in the config file format section.

### 6. Sync skill copy
After all changes, the file at `~/clawd/skills/pii-scanner/scripts/pii-scanner.sh` should be identical to this one. Copy it there.

## Testing
The project has no formal test suite for the bash script. Verify manually:
1. `echo "path: /Users/realname/docs" | ./pii-scanner.sh /dev/stdin` → should detect USER_PATH
2. Create a temp config with an allowlist entry for `/Users/realname` and verify it's suppressed
3. `echo "path: /Users/realname/docs # pii-ignore" > /tmp/test.md && ./pii-scanner.sh /tmp/test.md` → should be clean
4. Test TAILSCALE_HOST: `echo "host: my-box.tailnet-abc.ts.net" > /tmp/test.md && ./pii-scanner.sh /tmp/test.md` → should detect

## Rules
- Keep bash 3.2 compatible (no associative arrays, no `readarray`)
- Keep the parallel array pattern consistent with existing code
- Don't change the Node.js file — only the bash script
- The `exclude:` section name should keep working (backward compat) alongside the new `allowlist:` name
