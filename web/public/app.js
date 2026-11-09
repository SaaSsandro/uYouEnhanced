const output = document.getElementById('output');
const form = document.getElementById('build-form');
const dispatchBtn = document.getElementById('dispatch');
const scriptBtn = document.getElementById('script');
const scriptActions = document.getElementById('script-actions');
const checkBtn = document.getElementById('check-updates');
const updateBtn = document.getElementById('update-tweaks');
const syncBtn = document.getElementById('sync');
const updateSummary = document.getElementById('update-summary');

let config = null;
let updates = null;
let currentScript = '';

function h(tag, props = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === 'text') node.textContent = value;
    else if (key === 'class') node.className = value;
    else if (value !== undefined && value !== null) node.setAttribute(key, value);
  }
  for (const child of [].concat(children)) if (child) node.append(child);
  return node;
}

function setOutput(text, cls = '') {
  output.textContent = text;
  output.className = cls;
}

function tweakBoxes() {
  return [...document.querySelectorAll('#tweak-default input[data-tweak], #tweak-optional input[data-tweak]')];
}

function updateCount() {
  const boxes = tweakBoxes();
  document.getElementById('tweak-count').textContent = `${boxes.filter((b) => b.checked).length} / ${boxes.length} selected`;
}

function renderPrereqs() {
  const list = document.getElementById('prereqs');
  list.replaceChildren();
  const items = config.prereqs.map((p) => ({ label: p.name, ok: p.ok, title: p.detail || 'not found' }));
  items.push({ label: 'Theos', ok: config.theos.ok, title: config.theos.path || 'not found (set $THEOS)' });
  for (const item of items) {
    list.append(h('li', { class: item.ok ? 'ok' : 'bad', title: item.title, text: `${item.ok ? '✓' : '✗'} ${item.label}` }));
  }
}

function renderInputs() {
  const wrap = document.getElementById('inputs');
  wrap.replaceChildren();
  for (const [key, spec] of Object.entries(config.inputs)) {
    if (key === config.tweakInput) continue;
    const id = `input-${key}`;
    const desc = spec.description ? h('span', { class: 'desc', text: spec.description }) : null;
    if (spec.type === 'boolean') {
      const box = h('input', { type: 'checkbox', id });
      box.checked = Boolean(spec.default);
      box.dataset.key = key;
      box.dataset.kind = 'boolean';
      wrap.append(h('div', { class: 'field check' }, [box, h('label', { for: id, text: key }), desc]));
    } else {
      const input = h('input', { type: key === 'decrypted_youtube_url' ? 'url' : 'text', id, value: spec.default ?? '' });
      input.dataset.key = key;
      input.dataset.kind = 'string';
      wrap.append(h('div', { class: 'field' }, [h('label', { for: id, text: spec.required ? `${key} *` : key }), input, desc]));
    }
  }
}

function updateFor(id) {
  return (updates && updates.tweaks ? updates.tweaks : []).find((t) => t.id === id) || null;
}

function renderTweaks({ keepSelection = false } = {}) {
  const defaults = document.getElementById('tweak-default');
  const optional = document.getElementById('tweak-optional');
  const selected = keepSelection ? new Set(tweakBoxes().filter((b) => b.checked).map((b) => b.dataset.tweak)) : null;
  defaults.replaceChildren();
  optional.replaceChildren();
  for (const tweak of config.tweaks) {
    const box = h('input', { type: 'checkbox' });
    box.checked = selected ? selected.has(tweak.id) : tweak.default;
    box.dataset.tweak = tweak.id;
    box.addEventListener('change', updateCount);
    const info = updateFor(tweak.id);
    const meta = [tweak.dylib, tweak.version].filter(Boolean).join(' · ');
    const badge = info && info.outdated
      ? h('a', {
        class: 'badge outdated',
        href: info.url || '#',
        target: '_blank',
        rel: 'noreferrer',
        title: `${tweak.id}: ${info.local_version} -> ${info.upstream_version} (${info.url || 'no upstream url'})`,
        text: `${info.local_version} → ${info.upstream_version}`,
      })
      // The badge sits inside the label, which would toggle the checkbox.
      : null;
    if (badge) badge.addEventListener('click', (event) => event.stopPropagation());
    const label = h('label', { class: 'tweak', title: info && info.note ? info.note : tweak.description || '' }, [
      box,
      h('span', {}, [
        h('span', { class: 'id', text: tweak.id }),
        meta ? h('span', { class: 'meta', text: `  ${meta}` }) : null,
        badge,
      ]),
    ]);
    (tweak.default ? defaults : optional).append(label);
  }
  updateCount();
}

function renderUpdateSummary() {
  if (!updates) {
    updateSummary.textContent = 'Update check failed.';
    return;
  }
  const when = String(updates.checked_at || '').replace('T', ' ').replace('Z', ' UTC');
  const parts = [updates.outdated.length
    ? `${updates.outdated.length} outdated: ${updates.outdated.join(', ')}`
    : `all ${updates.tweaks.length} tweaks up to date`];
  const support = updates.outdated_support || [];
  if (support.length) parts.push(`shared modules behind: ${support.join(', ')}`);
  if (updates.offline) parts.push('check incomplete - some repositories were unreachable');
  if (when) parts.push(`checked ${when}${updates.cached ? ' (cached)' : ''}`);
  updateSummary.textContent = parts.join(' · ');
}

function renderTarget() {
  const wrap = document.getElementById('target');
  wrap.replaceChildren();
  const fields = [
    ['owner', 'Owner', config.repo.owner || '', false],
    ['repo', 'Repository', config.repo.repo || '', false],
    ['ref', 'Git ref', config.repo.branch || 'main', false],
    ['token', 'GitHub token', '', true],
  ];
  for (const [key, label, value, secret] of fields) {
    const input = h('input', { type: secret ? 'password' : 'text', id: `target-${key}`, value });
    input.dataset.target = key;
    wrap.append(h('div', { class: 'field' }, [h('label', { for: `target-${key}`, text: label }), input]));
  }
}

function collectTarget() {
  const target = {};
  for (const el of document.querySelectorAll('#target [data-target]')) target[el.dataset.target] = el.value;
  return target;
}

function collect() {
  const inputs = {};
  for (const el of document.querySelectorAll('#inputs [data-key]')) {
    inputs[el.dataset.key] = el.dataset.kind === 'boolean' ? el.checked : el.value;
  }
  inputs[config.tweakInput] = tweakBoxes().filter((b) => b.checked).map((b) => b.dataset.tweak);
  return { inputs, target: collectTarget() };
}

async function post(path, body) {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || data.message || `HTTP ${res.status}`);
  return data;
}

async function checkUpdates(refresh = false) {
  updateSummary.textContent = 'Checking upstream versions…';
  try {
    updates = await post('/api/updates', { token: document.getElementById('target-token')?.value || '', refresh });
  } catch (err) {
    updates = null;
    updateSummary.textContent = `Update check failed: ${err.message}`;
    return;
  }
  renderTweaks({ keepSelection: true });
  renderUpdateSummary();
}

async function reloadConfig() {
  const fresh = await (await fetch('/api/config')).json();
  config = fresh;
  renderPrereqs();
  renderTweaks({ keepSelection: true });
}

document.querySelectorAll('[data-preset]').forEach((button) => {
  button.addEventListener('click', () => {
    const preset = button.dataset.preset;
    for (const box of tweakBoxes()) {
      const tweak = config.tweaks.find((t) => t.id === box.dataset.tweak);
      box.checked = preset === 'all' ? true : preset === 'none' ? false : tweak.default;
    }
    updateCount();
  });
});

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const { inputs, target } = collect();
  dispatchBtn.disabled = true;
  scriptActions.hidden = true;
  setOutput('Dispatching workflow…');
  try {
    const data = await post('/api/dispatch', { ...target, inputs });
    setOutput(`${data.message}\n\nWatch progress: ${data.runsUrl}`, 'ok');
  } catch (err) {
    setOutput(`Error: ${err.message}`, 'error');
  } finally {
    dispatchBtn.disabled = false;
  }
});

scriptBtn.addEventListener('click', async () => {
  const { inputs } = collect();
  scriptBtn.disabled = true;
  scriptActions.hidden = true;
  setOutput('Generating script…');
  try {
    const data = await post('/api/local-script', { inputs });
    currentScript = data.script;
    setOutput(data.script);
    scriptActions.hidden = false;
  } catch (err) {
    setOutput(`Error: ${err.message}`, 'error');
  } finally {
    scriptBtn.disabled = false;
  }
});

checkBtn.addEventListener('click', async () => {
  checkBtn.disabled = true;
  try {
    await checkUpdates(true);
  } finally {
    checkBtn.disabled = false;
  }
});

updateBtn.addEventListener('click', async () => {
  if (!updates || !Array.isArray(updates.outdated)) {
    setOutput('Run a version check first.', 'error');
    return;
  }
  const ids = updates.outdated;
  if (!ids.length) {
    setOutput('Nothing to update - every tweak is up to date.', 'ok');
    return;
  }
  // The server falls back to $GITHUB_TOKEN, so an empty field is fine here.
  const target = collectTarget();
  const branch = target.ref || 'the branch';
  if (!confirm(`Update ${ids.length} tweak(s) on GitHub?\n\n${ids.join(', ')}\n\n` +
    `The workflow bumps the sources, compiles the bumped tweaks and pushes to ${branch}.`)) return;
  updateBtn.disabled = true;
  setOutput(`Dispatching ${config.updateWorkflow}…`);
  try {
    const data = await post('/api/dispatch', {
      ...target,
      workflow: config.updateWorkflow,
      inputs: {
        only: ids.join(' '),
        include_payload: true,
        include_support: true,
        verify: true,
        push: true,
      },
    });
    setOutput(`${data.message}\n\nWatch progress: ${data.runsUrl}\n\n` +
      'When it finished, use "Sync repository" and then dispatch a build.', 'ok');
  } catch (err) {
    setOutput(`Error: ${err.message}`, 'error');
  } finally {
    updateBtn.disabled = false;
  }
});

syncBtn.addEventListener('click', async () => {
  syncBtn.disabled = true;
  setOutput('Syncing repository…');
  try {
    const data = await post('/api/sync', {});
    setOutput(`Repository synced.\n\n${data.output}`, 'ok');
    await reloadConfig();
    await checkUpdates(true);
  } catch (err) {
    setOutput(`Error: ${err.message}`, 'error');
  } finally {
    syncBtn.disabled = false;
  }
});

document.getElementById('download').addEventListener('click', () => {
  const blob = new Blob([currentScript], { type: 'text/x-shellscript' });
  const url = URL.createObjectURL(blob);
  const link = h('a', { href: url, download: 'build-youtubebuilder.sh' });
  link.click();
  URL.revokeObjectURL(url);
});

document.getElementById('copy').addEventListener('click', async () => {
  await navigator.clipboard.writeText(currentScript);
  setOutput(currentScript);
});

try {
  config = await (await fetch('/api/config')).json();
  document.getElementById('workflow-name').textContent = config.workflow;
  renderPrereqs();
  renderInputs();
  renderTweaks();
  renderTarget();
  setOutput('Ready. Pick your tweaks, then dispatch a GitHub Actions build or generate a local build script.');
  // The version check talks to GitHub, so it runs after the UI is usable.
  checkUpdates(false);
} catch (err) {
  setOutput(`Failed to load configuration: ${err.message}`, 'error');
}
