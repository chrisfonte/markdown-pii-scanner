#!/usr/bin/env node
/*
 * markdown-pii-scanner.js — Scan markdown files for PII patterns before they hit git.
 * Pure Node.js, zero dependencies.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execFileSync } = require('child_process');

const VERSION = '2.1.0';

// --- Defaults ---
let countOnly = false;
let summaryOnly = false;
let configFile = '';
let extensions = 'md';
let installHook = false;
let excludeDirs = [];
let baselineFile = '';

// --- Patterns ---
const patNames = [];
const patRegexes = [];
const allowlistRegexes = [];

function addPattern(name, regex) {
  patNames.push(name);
  patRegexes.push(regex);
}

function builtinPatterns() {
  addPattern('GMAIL_ID', 'gmail:[0-9a-fA-F]+');
  addPattern('PHONE', '\\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}');
  addPattern('USER_PATH', '/(Users|home)/[A-Za-z0-9._-]+');
  addPattern('CREDENTIALS_REF', '\\.credentials/');
  addPattern('CHAT_USER_ID', "(chat_id|user_id|userId|telegram.*id)[\"': ]+[0-9]{8,}");
  addPattern('AWS_KEY', 'AKIA[0-9A-Z]{16}');
  addPattern('API_SECRET', "(api_key|api_secret|apikey|token|secret)[\"': =]+[A-Za-z0-9_\\-]{20,}");
}

// --- Parse config file (simple YAML-ish) ---
function loadConfig(file) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  let inPatterns = false;
  let inExtensions = false;
  let inAllowlist = false;
  let extensionsFromConfig = [];

  for (let raw of lines) {
    // Strip comments
    const hashIndex = raw.indexOf('#');
    if (hashIndex !== -1) raw = raw.slice(0, hashIndex);
    if (!raw.trim()) continue;

    if (/^patterns:\s*$/.test(raw)) {
      inPatterns = true; inExtensions = false; inAllowlist = false; continue;
    }
    if (/^extensions:\s*$/.test(raw)) {
      inPatterns = false; inExtensions = true; inAllowlist = false; continue;
    }
    if (/^exclude:\s*$/.test(raw)) {
      inPatterns = false; inExtensions = false; inAllowlist = false; continue;
    }
    if (/^allowlist:\s*$/.test(raw)) {
      inPatterns = false; inExtensions = false; inAllowlist = true; continue;
    }
    if (/^[a-z]/.test(raw)) {
      inPatterns = false; inExtensions = false; inAllowlist = false;
    }

    if (inPatterns && /^\s+-\s+/.test(raw)) {
      const entry = raw.replace(/^\s+-\s+/, '');
      const colonIndex = entry.indexOf(':');
      if (colonIndex === -1) continue;
      let name = entry.slice(0, colonIndex).trim();
      let regex = entry.slice(colonIndex + 1).trim();
      if ((regex.startsWith('"') && regex.endsWith('"')) || (regex.startsWith("'") && regex.endsWith("'"))) {
        regex = regex.slice(1, -1);
      }
      if (name) addPattern(name, regex);
    }

    if (inExtensions && /^\s+-\s+/.test(raw)) {
      const ext = raw.replace(/^\s+-\s+/, '').trim();
      if (ext) extensionsFromConfig.push(ext);
    }

    if (inAllowlist && /^\s+-\s+/.test(raw)) {
      let entry = raw.replace(/^\s+-\s+/, '').trim();
      if ((entry.startsWith('"') && entry.endsWith('"')) || (entry.startsWith("'") && entry.endsWith("'"))) {
        entry = entry.slice(1, -1);
      }
      if (entry) {
        try {
          allowlistRegexes.push(new RegExp(entry));
        } catch (err) {
          // If it's not a valid regex, treat as literal string
          allowlistRegexes.push(new RegExp(entry.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
        }
      }
    }
  }

  if (extensionsFromConfig.length > 0) {
    extensions = extensionsFromConfig.join(',');
  }
}

// --- Install pre-commit hook ---
function doInstallHook(repoPath) {
  const repoRoot = repoPath || '.';
  const gitDir = path.join(repoRoot, '.git');
  if (!fs.existsSync(gitDir)) {
    console.error(`Error: ${repoRoot} is not a git repository`);
    process.exit(2);
  }

  const hookDir = path.join(gitDir, 'hooks');
  const hookFile = path.join(hookDir, 'pre-commit');

  const scannerPath = path.join(__dirname, path.basename(__filename));

  const hookContent = `#!/usr/bin/env bash
# PII Scanner pre-commit hook (installed by markdown-pii-scanner)
# Scans staged .md files for PII patterns before commit.

SCANNER="${scannerPath}"
REPO_ROOT="\$(git rev-parse --show-toplevel)"
CONFIG="\$REPO_ROOT/.pii-patterns.yaml"

if [[ -f "\$CONFIG" ]]; then
  CONFIG_FLAG="--config \$CONFIG"
else
  CONFIG_FLAG=""
fi

# Only scan if there are staged .md files
STAGED=\$(git diff --cached --name-only --diff-filter=ACM | grep -E '\\.(md|markdown|txt)\$' || true)
if [[ -z "\$STAGED" ]]; then
  exit 0
fi

# Create temp dir with staged files
TMPDIR=\$(mktemp -d)
trap 'rm -rf "\$TMPDIR"' EXIT

for f in \$STAGED; do
  mkdir -p "\$TMPDIR/\$(dirname "\$f")"
  git show ":\$f" > "\$TMPDIR/\$f" 2>/dev/null || true
done

# Run scanner
\$SCANNER \$CONFIG_FLAG --count-only "\$TMPDIR"
RESULT=\$?

if [[ \$RESULT -ne 0 ]]; then
  echo ""
  echo "PII detected in staged files. Review matches:"
  \$SCANNER \$CONFIG_FLAG "\$TMPDIR"
  echo ""
  echo "To commit anyway: git commit --no-verify"
  exit 1
fi
`;

  if (!fs.existsSync(hookDir)) fs.mkdirSync(hookDir, { recursive: true });

  if (fs.existsSync(hookFile)) {
    const existing = fs.readFileSync(hookFile, 'utf8');
    if (existing.includes('markdown-pii-scanner') || existing.includes('pii-scanner')) {
      console.log(`PII scanner hook already installed at ${hookFile}`);
      process.exit(0);
    }
    console.log(`Warning: pre-commit hook already exists at ${hookFile}`);
    console.log(`Backing up to ${hookFile}.backup`);
    fs.copyFileSync(hookFile, `${hookFile}.backup`);
  }

  fs.writeFileSync(hookFile, hookContent, { mode: 0o755 });
  console.log(`PII scanner pre-commit hook installed at ${hookFile}`);
  console.log('');
  console.log('Optional: create .pii-patterns.yaml in repo root to customize patterns.');
  console.log(`Run '${path.basename(__filename)} --help' for config file format.`);
}

// --- Help ---
function showHelp() {
  const help = `markdown-pii-scanner — Scan files for PII patterns

Usage:
  markdown-pii-scanner [OPTIONS] <directory>
  markdown-pii-scanner --install-hook [<repo-path>]

Options:
  --count-only        Report totals per pattern type only
  --summary           Summary by directory and top files (mutually exclusive with --count-only)
  --config <file>     Load patterns from YAML config (see format below)
  --exclude <dirs>    Comma-separated directory basenames to skip
  --extensions <exts> Comma-separated extensions to scan (default: md)
  --install-hook      Install as git pre-commit hook in repo
  --baseline <file>   JSON baseline file for per-pattern delta reporting
  --help              Show this help
  --version           Show version

Exit codes:
  0  No PII found (clean)
  1  PII matches found
  2  Usage error

Output format (default mode):
  file:line:PATTERN_NAME:matched_text
Output format (--summary):
  === By Directory ===
  1061  docs/03-client-projects
  891   docs/04-professional
  === Top Files ===
  159  projects/production/monitoring/.../link.txt
  91   docs/04-professional/.../playoutone-analysis.md

Ignore files:
  .pii-ignore in target dir or repo root, one glob per line
  Supports *, **, ? (like minimatch); # comments and blanks ignored

Baseline mode:
  --baseline <file> stores/compares per-pattern counts in JSON
  Exit code is 1 only when new matches appear vs baseline

Config file format (.pii-patterns.yaml):
  patterns:
    - GMAIL_ID: 'gmail:[0-9a-fA-F]+'
    - PHONE: '\\+1[- ]?[0-9]{3}[- ]?[0-9]{3}[- ]?[0-9]{4}'
    - COMPANY_EMAIL: '[A-Za-z0-9._%+-]+@(mycompany|otherdomain)\\b'
  allowlist:
    - '/Users/(username|yourname|realname)'
    - '\\+1 555-'
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
`;
  process.stdout.write(help);
}

function usageError(msg) {
  if (msg) console.error(msg);
  showHelp();
  process.exit(2);
}

// --- Arg parsing ---
const args = process.argv.slice(2);
let i = 0;
while (i < args.length) {
  const arg = args[i];
  if (arg === '--help' || arg === '-h') {
    showHelp();
    process.exit(0);
  } else if (arg === '--version') {
    console.log(`markdown-pii-scanner ${VERSION}`);
    process.exit(0);
  } else if (arg === '--count-only') {
    countOnly = true; i += 1;
  } else if (arg === '--summary') {
    summaryOnly = true; i += 1;
  } else if (arg === '--config') {
    if (!args[i + 1]) usageError('Error: --config requires a file path');
    configFile = args[i + 1]; i += 2;
  } else if (arg === '--baseline') {
    if (!args[i + 1]) usageError('Error: --baseline requires a file path');
    baselineFile = args[i + 1]; i += 2;
  } else if (arg === '--exclude') {
    if (!args[i + 1]) usageError('Error: --exclude requires a value');
    excludeDirs = args[i + 1].split(',').map(s => s.trim()).filter(Boolean);
    i += 2;
  } else if (arg === '--extensions') {
    if (!args[i + 1]) usageError('Error: --extensions requires a value');
    extensions = args[i + 1]; i += 2;
  } else if (arg === '--install-hook') {
    installHook = true; i += 1;
  } else if (arg.startsWith('-')) {
    usageError(`Unknown option: ${arg}`);
  } else {
    break;
  }
}

if (installHook) {
  const repoPath = args[i] || '.';
  doInstallHook(repoPath);
  process.exit(0);
}

const remaining = args.slice(i);
if (remaining.length !== 1) usageError('Error: directory argument required');
const targetDir = remaining[0];

if (!fs.existsSync(targetDir) || !fs.statSync(targetDir).isDirectory()) {
  usageError(`Error: directory not found: ${targetDir}`);
}

if (summaryOnly && countOnly) usageError('Error: --summary is mutually exclusive with --count-only');
if (baselineFile && summaryOnly) usageError('Error: --baseline cannot be used with --summary');
if (baselineFile && !countOnly) countOnly = true;

let repoRoot = '';
try {
  repoRoot = execFileSync('git', ['-C', targetDir, 'rev-parse', '--show-toplevel'], { stdio: ['ignore', 'pipe', 'ignore'] })
    .toString().trim();
} catch (err) {
  // ignore
}

// --- Config selection ---
if (!configFile) {
  const candidates = [];
  candidates.push(path.join(targetDir, '.pii-patterns.yaml'));
  if (repoRoot) candidates.push(path.join(repoRoot, '.pii-patterns.yaml'));
  if (process.env.HOME) candidates.push(path.join(process.env.HOME, '.pii-patterns.yaml'));

  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) {
      configFile = candidate;
      break;
    }
  }
}

if (configFile) {
  if (!fs.existsSync(configFile)) {
    usageError(`Error: config file not found: ${configFile}`);
  }
  loadConfig(configFile);
}

if (patNames.length === 0) builtinPatterns();

// --- Build extension set ---
const extList = extensions.split(',').map(s => s.trim()).filter(Boolean);
const extSet = new Set(extList.map(e => e.toLowerCase()));
const excludeDirSet = new Set(excludeDirs);

// --- .pii-ignore ---
function loadIgnorePatterns() {
  const patterns = [];
  const candidates = [];
  candidates.push(path.join(targetDir, '.pii-ignore'));
  if (repoRoot && repoRoot !== targetDir) candidates.push(path.join(repoRoot, '.pii-ignore'));
  for (const candidate of candidates) {
    if (!candidate || !fs.existsSync(candidate)) continue;
    const lines = fs.readFileSync(candidate, 'utf8').split(/\r?\n/);
    for (let raw of lines) {
      const trimmed = raw.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      patterns.push(trimmed);
    }
  }
  return patterns;
}

function globToRegExp(glob) {
  let pattern = glob;
  if (pattern.startsWith('/')) pattern = pattern.slice(1);
  let re = '^';
  let i = 0;
  while (i < pattern.length) {
    const ch = pattern[i];
    if (ch === '*') {
      const next = pattern[i + 1];
      if (next === '*') {
        re += '.*';
        i += 2;
      } else {
        re += '[^/]*';
        i += 1;
      }
      continue;
    }
    if (ch === '?') {
      re += '[^/]';
      i += 1;
      continue;
    }
    if ('\\.[]{}()+-^$|'.includes(ch)) {
      re += `\\${ch}`;
    } else {
      re += ch;
    }
    i += 1;
  }
  re += '$';
  return new RegExp(re);
}

const ignorePatterns = loadIgnorePatterns();
const ignoreRegexes = ignorePatterns.map(p => ({
  pattern: p,
  hasSlash: p.includes('/'),
  re: globToRegExp(p)
}));

function isIgnored(relPath) {
  if (ignoreRegexes.length === 0) return false;
  const normalized = relPath.split(path.sep).join('/');
  const base = path.posix.basename(normalized);
  for (const entry of ignoreRegexes) {
    if (entry.hasSlash) {
      if (entry.re.test(normalized)) return true;
    } else {
      if (entry.re.test(base)) return true;
    }
  }
  return false;
}

// --- Find files (skip .git) ---
function collectFiles(dir, out) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name === '.git') continue;
    if (entry.isDirectory() && excludeDirSet.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectFiles(full, out);
    } else if (entry.isFile()) {
      const ext = path.extname(entry.name).replace(/^\./, '').toLowerCase();
      if (extSet.has(ext)) out.push(full);
    }
  }
}

const files = [];
collectFiles(targetDir, files);
const filteredFiles = [];
for (const file of files) {
  const rel = path.relative(targetDir, file);
  if (!isIgnored(rel)) filteredFiles.push(file);
}
if (filteredFiles.length === 0) process.exit(0);

// --- Count-only mode ---
if (countOnly) {
  const counts = new Array(patNames.length).fill(0);

  for (const file of filteredFiles) {
    let content;
    try {
      content = fs.readFileSync(file, 'utf8');
    } catch (err) {
      continue;
    }
    for (let p = 0; p < patRegexes.length; p += 1) {
      const re = new RegExp(patRegexes[p], 'g');
      const rawMatches = content.match(re);
      if (rawMatches && rawMatches.length > 0) {
        if (allowlistRegexes.length > 0) {
          for (const m of rawMatches) {
            let allowed = false;
            for (const alRe of allowlistRegexes) {
              if (alRe.test(m)) { allowed = true; break; }
            }
            if (!allowed) counts[p] += 1;
          }
        } else {
          counts[p] += rawMatches.length;
        }
      }
    }
  }

  let total = 0;
  for (let p = 0; p < patNames.length; p += 1) {
    if (!baselineFile) {
      console.log(`${patNames[p]}:${counts[p]}`);
    }
    total += counts[p];
  }

  if (!baselineFile) {
    process.exit(total > 0 ? 1 : 0);
  }

  let baselineData = null;
  if (fs.existsSync(baselineFile)) {
    try {
      baselineData = JSON.parse(fs.readFileSync(baselineFile, 'utf8'));
    } catch (err) {
      usageError(`Error: baseline file is not valid JSON: ${baselineFile}`);
    }
  }

  if (!baselineData) {
    const out = {};
    for (let p = 0; p < patNames.length; p += 1) out[patNames[p]] = counts[p];
    fs.writeFileSync(baselineFile, JSON.stringify(out, null, 2));
    process.exit(0);
  }

  let hasNew = false;
  for (let p = 0; p < patNames.length; p += 1) {
    const name = patNames[p];
    const current = counts[p];
    const base = Number(baselineData[name] || 0);
    const delta = current - base;
    let deltaText = 'no change';
    if (delta > 0) {
      deltaText = `+${delta} new`;
      hasNew = true;
    } else if (delta < 0) {
      deltaText = `-${Math.abs(delta)} fewer`;
    }
    console.log(`${name}: ${current} (baseline: ${base}, ${deltaText})`);
  }

  process.exit(hasNew ? 1 : 0);
}

// --- Summary mode ---
if (summaryOnly) {
  const fileCounts = new Map();
  let totalMatches = 0;

  for (const file of filteredFiles) {
    let content;
    try {
      content = fs.readFileSync(file, 'utf8');
    } catch (err) {
      continue;
    }
    let fileMatchCount = 0;
    for (let p = 0; p < patRegexes.length; p += 1) {
      const re = new RegExp(patRegexes[p], 'g');
      const rawMatches = content.match(re);
      if (rawMatches && rawMatches.length > 0) {
        if (allowlistRegexes.length > 0) {
          for (const m of rawMatches) {
            let allowed = false;
            for (const alRe of allowlistRegexes) {
              if (alRe.test(m)) { allowed = true; break; }
            }
            if (!allowed) fileMatchCount += 1;
          }
        } else {
          fileMatchCount += rawMatches.length;
        }
      }
    }
    if (fileMatchCount > 0) {
      fileCounts.set(file, fileMatchCount);
      totalMatches += fileMatchCount;
    }
  }

  if (fileCounts.size === 0) process.exit(0);

  const dirCounts = new Map();
  for (const [file, count] of fileCounts.entries()) {
    const rel = path.relative(targetDir, file).split(path.sep).join('/');
    const dirName = path.posix.dirname(rel);
    const parts = dirName === '.' ? [] : dirName.split('/');
    let group = '.';
    if (parts.length === 1) group = parts[0];
    if (parts.length >= 2) group = `${parts[0]}/${parts[1]}`;
    dirCounts.set(group, (dirCounts.get(group) || 0) + count);
  }

  const dirRows = Array.from(dirCounts.entries())
    .sort((a, b) => (b[1] - a[1]) || a[0].localeCompare(b[0]));
  const fileRows = Array.from(fileCounts.entries())
    .sort((a, b) => (b[1] - a[1]) || a[0].localeCompare(b[0]))
    .slice(0, 10);

  const maxDirCount = Math.max(...dirRows.map(r => r[1]));
  const maxFileCount = Math.max(...fileRows.map(r => r[1]));
  const dirWidth = String(maxDirCount).length;
  const fileWidth = String(maxFileCount).length;

  console.log('=== By Directory ===');
  for (const [dir, count] of dirRows) {
    console.log(`${String(count).padStart(dirWidth)}  ${dir}`);
  }
  console.log('=== Top Files ===');
  for (const [file, count] of fileRows) {
    const rel = path.relative(targetDir, file).split(path.sep).join('/');
    console.log(`${String(count).padStart(fileWidth)}  ${rel}`);
  }

  process.exit(totalMatches > 0 ? 1 : 0);
}

// --- Full scan mode ---
let matches = 0;

function scanFile(file) {
  return new Promise((resolve) => {
    const input = fs.createReadStream(file, { encoding: 'utf8' });
    input.on('error', () => resolve());

    const rl = readline.createInterface({ input, crlfDelay: Infinity });
    let lineNo = 0;

    rl.on('line', (line) => {
      lineNo += 1;
      for (let p = 0; p < patRegexes.length; p += 1) {
        const re = new RegExp(patRegexes[p]);
        const m = line.match(re);
        if (m) {
          // Check allowlist — skip if the matched text is allowlisted
          const matchedText = m[0];
          let allowed = false;
          for (const alRe of allowlistRegexes) {
            if (alRe.test(matchedText)) { allowed = true; break; }
          }
          if (allowed) continue;
          console.log(`${file}:${lineNo}:${patNames[p]}:${m[0]}`);
          matches += 1;
        }
      }
    });

    rl.on('close', resolve);
  });
}

(async () => {
  for (const file of filteredFiles) {
    await scanFile(file);
  }
  process.exit(matches > 0 ? 1 : 0);
})();
