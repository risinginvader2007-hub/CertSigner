// Get CertSigner page logic. The .p12, its password and the profile never leave this page:
// they are handed to the signing worker, and nothing here sends them anywhere.
import { parseProfile } from './signer-core.js';

const $ = (id) => document.getElementById(id);
const relay = (document.querySelector('meta[name="relay"]').content || '').replace(/\/$/, '');
const relayConfigured = /^https:\/\//.test(relay);
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

const state = { ipa: null, ipaError: null, p12: null, profile: null, facts: null, worker: null, workerReady: false, signed: null, downloadURL: null, expiryTimer: null };
const logLines = [];
const started = performance.now();

function log(message, level = 'info') {
  const line = `[+${((performance.now() - started) / 1000).toFixed(2)}s] ${level === 'error' ? 'ERROR ' : ''}${message}`;
  logLines.push(line);
  $('log').textContent = logLines.join('\n');
  $('log-card').hidden = false;
}

// ---------- the unsigned app (same origin) ----------

async function loadApp() {
  try {
    const response = await fetch('app/CertSigner.ipa', { cache: 'no-cache' });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    state.ipa = new Uint8Array(await response.arrayBuffer());
    log(`Loaded CertSigner.ipa (${(state.ipa.length / 1048576).toFixed(1)} MB)`);
    try {
      const build = await (await fetch('app/build.json', { cache: 'no-cache' })).json();
      $('app-version').textContent = `Version ${build.version} · build ${build.build}`;
      $('app-version').hidden = false;
    } catch { /* optional */ }
  } catch (error) {
    state.ipaError = "Couldn't download CertSigner. Check your connection and reload the page.";
    log('Download failed: ' + error.message, 'error');
  }
  refresh();
}

// ---------- signing worker ----------

function startWorker() {
  if (state.worker) state.worker.terminate();
  state.workerReady = false;
  state.worker = new Worker(new URL('./sign-worker.js', import.meta.url), { type: 'module' });
  state.worker.onmessage = onWorkerMessage;
  state.worker.onerror = () => fail('The signer could not start in this browser. Update iOS or try another browser.');
}

function stopWorker() {
  if (state.worker) state.worker.terminate();
  state.worker = null;
}

// ---------- inputs ----------

async function readFile(input) {
  const file = input.files && input.files[0];
  return file ? { name: file.name, bytes: new Uint8Array(await file.arrayBuffer()) } : null;
}

const fmtDate = (date) => date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });

function showFacts(facts, certificate) {
  const rows = [];
  const add = (label, value, tone = '') => rows.push([label, value, tone]);
  if (certificate) {
    add('Certificate', certificate.name);
    const expired = certificate.notAfter * 1000 < Date.now();
    add('Certificate expires', fmtDate(new Date(certificate.notAfter * 1000)), expired ? 'bad' : '');
  }
  add('Team', facts.teamName ? `${facts.teamName} (${facts.teamID})` : facts.teamID);
  add('App ID', facts.appID + (facts.isWildcard ? ' · wildcard' : ' · explicit'));
  if (facts.expires) add('Profile expires', fmtDate(facts.expires), facts.expires < new Date() ? 'bad' : '');
  add('Devices', facts.allDevices ? 'All devices (enterprise)' : `Device-limited · ${facts.deviceCount} UDID${facts.deviceCount === 1 ? '' : 's'}`, facts.allDevices ? '' : 'warn');
  add('get-task-allow', facts.getTaskAllow ? 'Yes (development)' : 'No');
  if (certificate) add('Certificate matches profile', certificate.matches ? 'Yes' : 'No', certificate.matches ? 'good' : 'bad');
  const list = $('facts');
  list.replaceChildren();
  for (const [label, value, tone] of rows) {
    const dt = document.createElement('dt'), dd = document.createElement('dd');
    dt.textContent = label;
    dd.textContent = value;
    if (tone) dd.className = tone;
    list.append(dt, dd);
  }
  list.hidden = false;
}

function showList(element, items) {
  element.replaceChildren();
  if (!items.length) { element.hidden = true; return; }
  const ul = document.createElement('ul');
  for (const item of items) { const li = document.createElement('li'); li.textContent = item; ul.append(li); }
  element.append(ul);
  element.hidden = false;
}

function refresh() {
  const password = $('password').value;
  const missing = [];
  if (!state.p12) missing.push('the .p12');
  if (!password) missing.push('its password');
  if (!state.profile) missing.push('the profile');
  const blocked = state.ipaError || (!state.ipa && 'Downloading CertSigner…') || (!state.workerReady && 'Starting the signer…');
  $('sign').disabled = missing.length > 0 || !!blocked;
  $('sign-hint').textContent = state.ipaError || (missing.length ? `Still needed: ${missing.join(', ')}.` : blocked || 'Everything is checked on this device before signing.');
}

$('p12').addEventListener('change', async () => {
  state.p12 = await readFile($('p12'));
  $('p12-name').textContent = state.p12 ? state.p12.name : 'Choose file';
  $('p12-label').classList.toggle('chosen', !!state.p12);
  $('files-error').hidden = true;
  refresh();
});

$('profile').addEventListener('change', async () => {
  state.profile = await readFile($('profile'));
  state.facts = null;
  $('facts').hidden = true;
  $('files-error').hidden = true;
  $('files-notes').hidden = true;
  if (state.profile) {
    try {
      state.facts = parseProfile(state.profile.bytes);
      showFacts(state.facts, null);
    } catch {
      showList($('files-error'), ["That file isn't a provisioning profile (.mobileprovision)."]);
      state.profile = null;
      $('profile').value = '';
    }
  }
  $('profile-name').textContent = state.profile ? state.profile.name : 'Choose file';
  $('profile-label').classList.toggle('chosen', !!state.profile);
  refresh();
});

$('password').addEventListener('input', () => { $('files-error').hidden = true; refresh(); });

// ---------- flow ----------

const STAGES = ['read', 'validate', 'sign', 'upload'];
const PROGRESS = { read: 8, validate: 22, unpack: 34, sign: 55, pack: 78, upload: 88, done: 100 };

function setStage(stage, failed = false) {
  const index = STAGES.indexOf(stage === 'unpack' || stage === 'pack' ? 'sign' : stage);
  document.querySelectorAll('#stages li').forEach((item, i) => {
    item.classList.toggle('done', i < index || stage === 'done');
    item.classList.toggle('active', i === index && !failed && stage !== 'done');
    item.classList.toggle('failed', i === index && failed);
  });
  const value = PROGRESS[stage] ?? 0;
  if (!failed) {
    $('bar-fill').style.transform = `scaleX(${value / 100})`;
    $('bar').setAttribute('aria-valuenow', String(value));
  }
  state.stage = stage;
}

function setStep(step) {
  const order = ['files', 'sign', 'install'], at = order.indexOf(step);
  document.querySelectorAll('#steps li').forEach((item, i) => {
    item.classList.toggle('current', i === at);
    item.classList.toggle('done', i < at);
  });
}

function show(panel) {
  for (const id of ['panel-files', 'panel-work', 'panel-ready', 'panel-error']) $(id).hidden = id !== panel;
  $('tools').hidden = panel === 'panel-files' || panel === 'panel-work';
}

function fail(message) {
  log(message, 'error');
  if (state.stage) setStage(state.stage, true);
  $('error-message').textContent = message;
  show('panel-error');
  clearSecrets();
}

/// Forget the certificate, password and profile: fields, variables and the worker that held copies.
function clearSecrets() {
  stopWorker();
  if (state.p12) state.p12.bytes.fill(0);
  if (state.profile) state.profile.bytes.fill(0);
  state.p12 = null;
  state.profile = null;
  $('password').value = '';
  $('p12').value = '';
  $('profile').value = '';
  $('p12-name').textContent = 'Choose file';
  $('profile-name').textContent = 'Choose file';
  $('p12-label').classList.remove('chosen');
  $('profile-label').classList.remove('chosen');
}

$('sign').addEventListener('click', () => {
  if ($('sign').disabled) return;
  $('files-error').hidden = true;
  show('panel-work');
  setStep('sign');
  $('work-title').textContent = 'Signing…';
  setStage('read');
  log(`Certificate file: ${state.p12.name} (${state.p12.bytes.length} bytes); profile: ${state.profile.name}`);
  // Copies go to the worker; the originals are wiped in clearSecrets().
  state.worker.postMessage({
    ipa: state.ipa.slice(), p12: state.p12.bytes.slice(), password: $('password').value, profile: state.profile.bytes.slice(),
  });
});

async function onWorkerMessage(event) {
  const message = event.data;
  switch (message.type) {
    case 'ready':
      state.workerReady = true;
      refresh();
      break;
    case 'stage':
      setStage(message.stage);
      break;
    case 'log':
      log(message.message, message.level);
      break;
    case 'checked': {
      const { verdict, certificate } = message;
      if (certificate) {
        certificate.matches = !verdict.errors.some((e) => e.includes("isn't in the provisioning profile"));
        showFacts(state.facts, certificate);
        log(`Certificate: ${certificate.name}, expires ${fmtDate(new Date(certificate.notAfter * 1000))}; matches profile: ${certificate.matches ? 'yes' : 'no'}`);
      }
      if (!verdict.ok) {
        // Back to the form with the reasons; the files stay chosen so only the wrong one needs replacing.
        verdict.errors.forEach((e) => log(e, 'error'));
        showList($('files-error'), verdict.errors);
        show('panel-files');
        setStep('files');
        startWorker();
        refresh();
      } else {
        showList($('files-notes'), verdict.notes);
        verdict.notes.forEach((n) => log('Note: ' + n));
      }
      break;
    }
    case 'signed':
      state.signed = message;
      log(`Signed ${message.title} ${message.version} as ${message.bundleID} (${(message.ipa.length / 1048576).toFixed(1)} MB)`);
      clearSecrets();
      log('Certificate, password and profile cleared from memory');
      await publish();
      break;
    case 'error':
      fail(message.message);
      break;
  }
}

async function publish() {
  const signed = state.signed;
  if (state.downloadURL) URL.revokeObjectURL(state.downloadURL);
  state.downloadURL = URL.createObjectURL(new Blob([signed.ipa], { type: 'application/octet-stream' }));
  $('download').href = state.downloadURL;
  $('ready-summary').textContent = `${signed.title} ${signed.version}, signed with “${signed.certificateName}”` +
    (signed.changedBundleID ? `, as ${signed.bundleID} to match your profile.` : '.');

  let link = null, problem = null;
  if (relayConfigured) {
    setStage('upload');
    $('work-title').textContent = 'Preparing the install link…';
    try {
      // The only upload this page ever makes: the signed app, nothing else.
      const response = await fetch(relay + '/upload', { method: 'POST', body: signed.ipa, headers: { 'Content-Type': 'application/octet-stream' } });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.message || `The install service answered ${response.status}.`);
      link = body;
      log(`Install link ready (expires in ${Math.round(body.expiresIn / 60)} minutes)`);
    } catch (error) {
      problem = error instanceof TypeError ? "Couldn't reach the install service. Check your connection." : error.message;
      log('Upload failed: ' + problem, 'error');
    }
  } else {
    problem = 'One-tap install is not set up for this site yet.';
    log('No install relay configured');
  }

  setStage('done');
  setStep('install');
  show('panel-ready');
  const install = $('install'), hint = $('install-hint');
  install.hidden = !link;
  hint.hidden = false;
  if (link) {
    install.href = 'itms-services://?action=download-manifest&url=' + encodeURIComponent(link.manifestURL);
    $('ready-title').textContent = 'Ready to install';
    $('next').hidden = false;
    countdown(link.expiresIn, hint);
    if (!isIOS) hint.textContent = 'Open this page in Safari on your iPhone to install. On a computer, download the signed IPA instead.';
  } else {
    $('ready-title').textContent = 'Signed';
    $('next').hidden = true;
    hint.textContent = `${problem} You can still download the signed IPA and install it with a computer or another signer.`;
    if (relayConfigured) { $('retry-upload')?.remove(); addRetryUpload(); }
  }
}

function addRetryUpload() {
  const button = document.createElement('button');
  button.id = 'retry-upload';
  button.className = 'button primary';
  button.textContent = 'Try the install link again';
  button.addEventListener('click', async () => { button.remove(); show('panel-work'); await publish(); });
  $('install-hint').before(button);
}

function countdown(seconds, element) {
  clearInterval(state.expiryTimer);
  const end = Date.now() + seconds * 1000;
  const tick = () => {
    const left = Math.max(0, Math.round((end - Date.now()) / 1000));
    if (isIOS) element.textContent = left > 0 ? `Install link expires in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}.` : 'The install link has expired. Start over to make a new one.';
    if (left === 0) { clearInterval(state.expiryTimer); $('install').hidden = true; }
  };
  tick();
  state.expiryTimer = setInterval(tick, 1000);
}

$('install').addEventListener('click', () => log('Install tapped: iOS prompt requested'));

function reset() {
  clearInterval(state.expiryTimer);
  clearSecrets();
  state.signed = null;
  if (state.downloadURL) URL.revokeObjectURL(state.downloadURL);
  state.downloadURL = null;
  state.facts = null;
  state.stage = null;
  $('facts').hidden = true;
  $('files-error').hidden = true;
  $('files-notes').hidden = true;
  $('retry-upload')?.remove();
  setStage('read');
  $('bar-fill').style.transform = 'scaleX(0)';
  setStep('files');
  show('panel-files');
  startWorker();
  refresh();
}

$('reset').addEventListener('click', () => { log('Start over'); reset(); });
$('retry').addEventListener('click', () => { log('Try again'); reset(); });

$('share-log').addEventListener('click', async () => {
  const text = 'Get CertSigner signing log\n' + navigator.userAgent + '\n\n' + logLines.join('\n') + '\n';
  const file = new File([text], 'get-certsigner-log.txt', { type: 'text/plain' });
  try {
    if (navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file] }); return; }
  } catch (error) {
    if (error && error.name === 'AbortError') return;
  }
  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url;
  a.download = file.name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
});

if (typeof WebAssembly !== 'object' || typeof Worker !== 'function') {
  state.ipaError = 'This browser is too old to sign apps. Update iOS (16 or later) and use Safari.';
  refresh();
} else {
  startWorker();
  loadApp();
}
