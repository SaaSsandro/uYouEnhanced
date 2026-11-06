#!/usr/bin/env node
// Local web front-end for the YouTubeBuilder build workflow.
//
// Reads the workflow inputs from .github/workflows/buildapp.yml and the tweak
// registry from the Makefile, so both stay the single source of truth. Serves a
// small UI that can dispatch the GitHub Actions workflow or emit an equivalent
// local build script. No runtime dependencies.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { appendFileSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..');
const PUBLIC_DIR = path.join(__dirname, 'public');
const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';

const WORKFLOW_REL = '.github/workflows/buildapp.yml';
const WORKFLOW_NAME = 'buildapp.yml';
const MAKEFILE_REL = 'Makefile';
const PREREQ_BINS = ['make', 'git', 'curl', 'unzip', 'ldid', 'dpkg', 'cyan', 'xcodebuild'];
const TWEAK_INPUT = 'enabled_tweaks';
const MAX_BODY = 1 << 20;
const LOG_FILE = process.env.LOG_FILE || path.join(__dirname, 'server.log');

function log(kind, detail) {
  const line = `${new Date().toISOString()} [${kind}] ${detail}\n`;
  try { process.stderr.write(line); } catch { /* stderr already gone */ }
  try { appendFileSync(LOG_FILE, line); } catch { /* log file unwritable */ }
}

// A local server must not die from one bad request, a closed pipe, or a
// detached terminal. Log these paths and keep serving.
process.on('uncaughtException', (err) => log('uncaughtException', err?.stack || String(err)));
process.on('unhandledRejection', (err) => log('unhandledRejection', err?.stack || String(err)));
process.on('SIGHUP', () => log('signal', 'SIGHUP ignored'));
process.stdout.on('error', () => {});
process.stderr.on('error', () => {});

// ---------------------------------------------------------------------------
// Workflow / Makefile parsing
// ---------------------------------------------------------------------------

function parseWorkflowInputs(yaml) {
  const inputs = {};
  let inInputs = false;
  let current = null;
  for (const line of yaml.split(/\r?\n/)) {
    if (!inInputs) {
      if (/^ {4}inputs:\s*$/.test(line)) inInputs = true;
      continue;
    }
    if (/^\S/.test(line)) break;
    const name = /^ {6}([A-Za-z0-9_-]+):\s*$/.exec(line);
    if (name) {
      current = name[1];
      inputs[current] = { name: current, type: 'string', default: '', required: false, description: '' };
      continue;
    }
    if (!current) continue;
    const prop = /^ {8}(description|default|required|type):\s*(.*)$/.exec(line);
    if (!prop) continue;
    const [, key, rest] = prop;
    let raw = rest.trim();
    if (raw.length >= 2 && ((raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'")))) {
      raw = raw.slice(1, -1);
    }
    if (key === 'default') {
      if (raw === 'true') inputs[current].default = true;
      else if (raw === 'false') inputs[current].default = false;
      else inputs[current].default = raw;
    } else if (key === 'required') {
      inputs[current].required = raw === 'true';
    } else if (key === 'type') {
      inputs[current].type = raw;
    } else {
      inputs[current].description = raw;
    }
  }
  return inputs;
}

function parseMakefileTweaks(text) {
  const joined = text.replace(/\\\r?\n[ \t]*/g, ' ');
  const lines = joined.split(/\r?\n/);
  const readVar = (name) => {
    const re = new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*[:?]?=\\s*(.*)$`);
    for (const line of lines) {
      const m = re.exec(line);
      if (m) return m[1].trim();
    }
    return null;
  };
  const list = (v) => (v || '').split(/\s+/).filter(Boolean);
  const ids = list(readVar('TWEAK_REGISTRY'));
  const defaults = new Set(list(readVar('DEFAULT_TWEAKS')));
  const tweaks = ids.map((id) => ({
    id,
    subproject: readVar(`${id}_SUBPROJECT`),
    dylib: readVar(`${id}_DYLIB`),
    default: defaults.has(id),
  }));
  return { tweaks, defaults: [...defaults] };
}

async function readControl(id) {
  try {
    const txt = await readFile(path.join(REPO_ROOT, 'Tweaks', id, 'control'), 'utf8');
    const field = (name) => {
      const m = new RegExp(`^${name}:\\s*(.+)$`, 'm').exec(txt);
      return m ? m[1].trim() : undefined;
    };
    return { name: field('Name'), version: field('Version'), description: field('Description') };
  } catch {
    return {};
  }
}

// ---------------------------------------------------------------------------
// Environment introspection
// ---------------------------------------------------------------------------

async function readRepoInfo() {
  const info = { owner: null, repo: null, branch: null };
  try {
    const { stdout } = await execFileAsync('git', ['remote', 'get-url', 'origin'], { cwd: REPO_ROOT });
    const m = /github\.com[:/]([^/]+)\/([^/]+?)(?:\.git)?$/.exec(stdout.trim());
    if (m) {
      info.owner = m[1];
      info.repo = m[2];
    }
  } catch { /* no remote */ }
  try {
    const { stdout } = await execFileAsync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: REPO_ROOT });
    const branch = stdout.trim();
    if (branch && branch !== 'HEAD') info.branch = branch;
  } catch { /* detached */ }
  return info;
}

async function which(bin) {
  try {
    const { stdout } = await execFileAsync('sh', ['-c', `command -v ${bin}`]);
    return { name: bin, ok: true, detail: stdout.trim() };
  } catch {
    return { name: bin, ok: false, detail: null };
  }
}

async function findTheos() {
  const candidates = [process.env.THEOS, path.join(REPO_ROOT, '.theos'), path.join(homedir(), 'theos')].filter(Boolean);
  for (const dir of candidates) {
    try {
      const s = await stat(path.join(dir, 'makefiles', 'common.mk'));
      if (s.isFile()) return { ok: true, path: dir };
    } catch { /* keep looking */ }
  }
  return { ok: false, path: null };
}

// ---------------------------------------------------------------------------
// Config assembly
// ---------------------------------------------------------------------------

async function buildConfig() {
  const [workflowYaml, makefile, repo, theos, ...prereqs] = await Promise.all([
    readFile(path.join(REPO_ROOT, WORKFLOW_REL), 'utf8'),
    readFile(path.join(REPO_ROOT, MAKEFILE_REL), 'utf8'),
    readRepoInfo(),
    findTheos(),
    ...PREREQ_BINS.map(which),
  ]);
  const inputs = parseWorkflowInputs(workflowYaml);
  const { tweaks } = parseMakefileTweaks(makefile);
  const enriched = await Promise.all(
    tweaks.map(async (t) => ({ ...t, ...(await readControl(t.id)) })),
  );
  return {
    workflow: WORKFLOW_NAME,
    repo,
    inputs,
    tweakInput: TWEAK_INPUT,
    tweaks: enriched,
    prereqs,
    theos,
  };
}

// ---------------------------------------------------------------------------
// Input normalisation for dispatch / script generation
// ---------------------------------------------------------------------------

function normaliseTweaks(value, valid) {
  const raw = Array.isArray(value) ? value.join(' ') : String(value ?? '');
  const seen = new Set();
  const out = [];
  for (const id of raw.split(/[\s,]+/).filter(Boolean)) {
    if (!valid.has(id)) throw new Error(`Unknown tweak id: ${id}`);
    if (!seen.has(id)) {
      seen.add(id);
      out.push(id);
    }
  }
  return out;
}

function resolveInputs(config, submitted) {
  const values = {};
  const validTweaks = new Set(config.tweaks.map((t) => t.id));
  for (const [key, spec] of Object.entries(config.inputs)) {
    if (key === config.tweakInput) {
      values[key] = normaliseTweaks(submitted?.[key], validTweaks).join(' ');
      continue;
    }
    const provided = submitted?.[key];
    const value = provided === undefined || provided === null || provided === '' ? spec.default : provided;
    if (spec.type === 'boolean') {
      values[key] = value === true || value === 'true' || value === '1' ? 'true' : 'false';
    } else {
      const str = value === undefined || value === null ? '' : String(value);
      if (spec.required && str.trim() === '') throw new Error(`Missing required input: ${key}`);
      values[key] = str;
    }
  }
  return values;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

async function dispatchWorkflow({ token, owner, repo, ref, inputs }) {
  const url = `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/actions/workflows/${WORKFLOW_NAME}/dispatches`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'YouTubeBuilder-WebUI',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ ref, inputs }),
    signal: AbortSignal.timeout(30000),
  });
  const body = await res.text();
  return { status: res.status, ok: res.ok, body };
}

function shq(value) {
  return `"${String(value).replace(/[\\$"`]/g, (c) => `\\${c}`)}"`;
}

function buildLocalScript(cfg, values) {
  return `#!/usr/bin/env bash
# Generated by the YouTubeBuilder web UI. Mirrors .github/workflows/${WORKFLOW_NAME}.
# Requires: Theos (THEOS), make, curl, unzip, ldid, dpkg.
set -euo pipefail

export THEOS=\${THEOS:-$HOME/theos}
IPA_URL=${shq(values.decrypted_youtube_url)}
SDK_VERSION=${shq(values.sdk_version)}
YTPLUS_VERSION=${shq(values.ytplus_version)}
IPA_PREFIX=${shq(values.ipa_prefix)}
BUNDLE_ID=${shq(values.bundle_id)}
APP_NAME=${shq(values.app_name)}
ENABLED_TWEAKS=${shq(values.enabled_tweaks)}

command -v make >/dev/null || { echo "error: make not found" >&2; exit 1; }
[ -f "$THEOS/makefiles/common.mk" ] || { echo "error: Theos not found at $THEOS" >&2; exit 1; }
[ -n "$IPA_URL" ] || { echo "error: decrypted_youtube_url is empty" >&2; exit 1; }

git submodule update --init --recursive

rm -f YouTube.ipa
rm -rf Payload
curl -fsSL "$IPA_URL" -o YouTube.ipa
unzip -q YouTube.ipa
YT_VERSION=$(defaults read "$PWD/Payload/YouTube.app/Info" CFBundleVersion)
echo "YouTube version: $YT_VERSION"

make package THEOS_PACKAGE_SCHEME=rootless IPA=Payload/YouTube.app FINALPACKAGE=1 \\
  SDK_VERSION="$SDK_VERSION" \\
  BUNDLE_ID="$BUNDLE_ID" \\
  DISPLAY_NAME="$APP_NAME" \\
  YTPLUS_VERSION="$YTPLUS_VERSION" \\
  IPA_PREFIX="$IPA_PREFIX" \\
  ENABLED_TWEAKS="$ENABLED_TWEAKS"

echo "Built: $(ls -t packages | head -n1)"
`;
}

// ---------------------------------------------------------------------------
// HTTP plumbing
// ---------------------------------------------------------------------------

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function sendJson(res, status, payload) {
  if (res.writableEnded || res.destroyed) return;
  const body = JSON.stringify(payload);
  res.writeHead(status, { 'Content-Type': MIME['.json'], 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw new Error('Request body too large');
    chunks.push(chunk);
  }
  if (size === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

async function serveStatic(req, res, pathname) {
  if (res.writableEnded || res.destroyed) return;
  const rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const file = path.resolve(PUBLIC_DIR, rel);
  if (file !== PUBLIC_DIR && !file.startsWith(PUBLIC_DIR + path.sep)) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  try {
    const data = await readFile(file);
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not found');
  }
}

async function handleApi(req, res, pathname) {
  if (req.method === 'GET' && pathname === '/api/config') {
    sendJson(res, 200, await buildConfig());
    return true;
  }
  if (req.method === 'POST' && (pathname === '/api/dispatch' || pathname === '/api/local-script')) {
    const body = await readBody(req);
    const config = await buildConfig();
    const values = resolveInputs(config, body.inputs);
    if (pathname === '/api/local-script') {
      sendJson(res, 200, { script: buildLocalScript(config, values) });
      return true;
    }
    const token = (body.token || process.env.GITHUB_TOKEN || '').trim();
    const owner = (body.owner || config.repo.owner || '').trim();
    const repo = (body.repo || config.repo.repo || '').trim();
    const ref = (body.ref || config.repo.branch || 'main').trim();
    if (!token) throw new Error('A GitHub token is required to dispatch the workflow');
    if (!owner || !repo) throw new Error('GitHub owner/repository could not be determined');
    const result = await dispatchWorkflow({ token, owner, repo, ref, inputs: values });
    sendJson(res, result.ok ? 200 : 502, {
      ok: result.ok,
      status: result.status,
      message: result.ok
        ? `Workflow dispatched on ${owner}/${repo}@${ref}.`
        : `GitHub responded ${result.status}: ${result.body.slice(0, 500)}`,
      runsUrl: `https://github.com/${owner}/${repo}/actions/workflows/${WORKFLOW_NAME}`,
    });
    return true;
  }
  return false;
}

const server = createServer(async (req, res) => {
  let pathname = '/';
  req.on('error', (err) => log('request', err.message));
  res.on('error', (err) => log('response', err.message));
  res.on('close', () => {
    if (!res.writableEnded) log('request', `${req.method} ${pathname} aborted by client`);
  });
  try {
    pathname = new URL(req.url, `http://${req.headers.host || 'localhost'}`).pathname;
    if (pathname.startsWith('/api/')) {
      if (await handleApi(req, res, pathname)) return;
      sendJson(res, 404, { error: 'Unknown endpoint' });
      return;
    }
    await serveStatic(req, res, pathname);
  } catch (err) {
    log('handler', `${req.method} ${pathname}: ${err.stack || err}`);
    try {
      if (!res.writableEnded && !res.destroyed) {
        if (pathname.startsWith('/api/')) sendJson(res, 400, { error: err.message });
        else {
          res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
          res.end(`Internal error: ${err.message}`);
        }
      }
    } catch (nested) {
      log('handler', `could not send error response: ${nested.message}`);
    }
  }
});

server.on('clientError', (err, socket) => {
  log('clientError', err.code || err.message);
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
});
server.on('error', (err) => log('server', err.stack || err.message));

server.headersTimeout = 20000;
server.requestTimeout = 60000;
server.keepAliveTimeout = 5000;

server.listen(PORT, HOST, () => {
  console.log(`YouTubeBuilder web UI: http://${HOST}:${PORT}`);
  console.log(`Repository: ${REPO_ROOT}`);
  log('start', `listening on ${HOST}:${PORT}`);
});
