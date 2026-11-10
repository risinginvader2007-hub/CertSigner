// Signing core shared by the page's Web Worker and the Node tests.
// Everything here works on bytes in memory. It never makes a network request.
import { unzipSync, zipSync } from './vendor/fflate.js';

// ---------- property lists ----------

/// Parses an XML property list (the subset Apple writes) into plain JS values.
/// <data> stays a base64 string; <date> becomes a Date.
export function parseXMLPlist(xml) {
  const tokens = xml.match(/<(?:[^>"]|"[^"]*")*>|[^<]+/g) || [];
  let i = 0;
  const unescape = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16))).replace(/&amp;/g, '&');
  const text = (close) => {
    let out = '';
    while (i < tokens.length && tokens[i] !== close) out += tokens[i++];
    i++;
    return out;
  };
  const skip = () => { while (i < tokens.length && !tokens[i].startsWith('<')) i++; };
  const value = () => {
    skip();
    const tag = tokens[i++];
    if (tag === undefined) throw new Error('Unexpected end of property list');
    switch (tag.replace(/\s+/g, '')) {
      case '<dict>': {
        const dict = {};
        for (;;) {
          skip();
          if (tokens[i] === '</dict>') { i++; return dict; }
          if (tokens[i] !== '<key>') throw new Error('Malformed property list');
          i++;
          const key = unescape(text('</key>'));
          dict[key] = value();
        }
      }
      case '<array>': {
        const list = [];
        for (;;) {
          skip();
          if (tokens[i] === '</array>') { i++; return list; }
          list.push(value());
        }
      }
      case '<dict/>': return {};
      case '<array/>': return [];
      case '<string/>': return '';
      case '<data/>': return '';
      case '<true/>': return true;
      case '<false/>': return false;
      case '<string>': return unescape(text('</string>'));
      case '<data>': return text('</data>').replace(/\s+/g, '');
      case '<date>': return new Date(text('</date>').trim());
      case '<integer>': return parseInt(text('</integer>'), 10);
      case '<real>': return parseFloat(text('</real>'));
      default: throw new Error('Unsupported property list tag ' + tag);
    }
  };
  const start = tokens.findIndex((t) => /^<plist[\s>]/.test(t));
  if (start < 0) throw new Error('Not a property list');
  i = start + 1;
  return value();
}

/// Parses a binary property list (bplist00) into plain JS values.
export function parseBinaryPlist(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const trailer = bytes.length - 32;
  const offsetSize = bytes[trailer + 6], refSize = bytes[trailer + 7];
  const count = Number(view.getBigUint64(trailer + 8)), top = Number(view.getBigUint64(trailer + 16));
  const table = Number(view.getBigUint64(trailer + 24));
  const uint = (at, size) => { let n = 0; for (let k = 0; k < size; k++) n = n * 256 + bytes[at + k]; return n; };
  const offset = (index) => uint(table + index * offsetSize, offsetSize);
  const read = (index, depth = 0) => {
    if (index >= count || depth > 64) throw new Error('Malformed binary property list');
    let at = offset(index);
    const marker = bytes[at++], type = marker >> 4;
    let info = marker & 15;
    const length = () => {
      if (info !== 15) return info;
      const size = 1 << (bytes[at++] & 15);
      const n = uint(at, size);
      at += size;
      return n;
    };
    switch (type) {
      case 0x0: return info === 9 ? true : info === 8 ? false : null;
      case 0x1: return uint(at, 1 << info);
      case 0x2: return info === 2 ? view.getFloat32(at) : view.getFloat64(at);
      case 0x3: return new Date((view.getFloat64(at) + 978307200) * 1000);
      case 0x4: { const n = length(); return bytes.slice(at, at + n); }
      case 0x5: { const n = length(); return new TextDecoder('ascii').decode(bytes.subarray(at, at + n)); }
      case 0x6: { const n = length(); return new TextDecoder('utf-16be').decode(bytes.subarray(at, at + n * 2)); }
      case 0xA: { const n = length(); const list = []; for (let k = 0; k < n; k++) list.push(read(uint(at + k * refSize, refSize), depth + 1)); return list; }
      case 0xD: {
        const n = length(), dict = {};
        for (let k = 0; k < n; k++) {
          const key = read(uint(at + k * refSize, refSize), depth + 1);
          dict[key] = read(uint(at + (n + k) * refSize, refSize), depth + 1);
        }
        return dict;
      }
      default: return null;
    }
  };
  return read(top);
}

export function parsePlist(bytes) {
  if (bytes.length > 8 && new TextDecoder('ascii').decode(bytes.subarray(0, 6)) === 'bplist') return parseBinaryPlist(bytes);
  return parseXMLPlist(new TextDecoder().decode(bytes));
}

// ---------- provisioning profile ----------

function indexOf(bytes, needle, from = 0) {
  const n = new TextEncoder().encode(needle);
  outer: for (let i = from; i <= bytes.length - n.length; i++) {
    for (let k = 0; k < n.length; k++) if (bytes[i + k] !== n[k]) continue outer;
    return i;
  }
  return -1;
}

/// Reads the facts the page shows from a .mobileprovision (a CMS envelope around an XML plist).
export function parseProfile(bytes) {
  const start = indexOf(bytes, '<?xml');
  const end = indexOf(bytes, '</plist>', Math.max(start, 0));
  if (start < 0 || end < 0) throw new Error('This file is not a provisioning profile.');
  const plist = parseXMLPlist(new TextDecoder().decode(bytes.subarray(start, end + 8)));
  const entitlements = plist.Entitlements || {};
  const appID = String(entitlements['application-identifier'] || entitlements['com.apple.application-identifier'] || '').trim();
  const teamID = (plist.TeamIdentifier && plist.TeamIdentifier[0]) || entitlements['com.apple.developer.team-identifier'] || appID.split('.')[0] || '';
  const pattern = appID.startsWith(teamID + '.') ? appID.slice(teamID.length + 1) : appID;
  return {
    name: plist.Name || '',
    teamID,
    teamName: plist.TeamName || '',
    appID,
    bundleIDPattern: pattern,
    isWildcard: pattern === '*' || pattern.endsWith('.*'),
    expires: plist.ExpirationDate instanceof Date ? plist.ExpirationDate : null,
    deviceCount: Array.isArray(plist.ProvisionedDevices) ? plist.ProvisionedDevices.length : 0,
    allDevices: plist.ProvisionsAllDevices === true,
    getTaskAllow: entitlements['get-task-allow'] === true,
    certificates: Array.isArray(plist.DeveloperCertificates) ? plist.DeveloperCertificates : [],
  };
}

function base64ToBytes(text) {
  const binary = atob(text);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

async function sha1Hex(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-1', bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, '0')).join('');
}

/// SHA-1 fingerprints of the certificates the profile allows.
export async function profileCertificateFingerprints(profile) {
  return Promise.all(profile.certificates.map((c) => sha1Hex(base64ToBytes(c))));
}

/// Decides whether signing may go ahead. `certificate` is the result of inspectP12.
/// Returns { ok, errors: [..], notes: [..] } with messages ready to show.
export async function validate(profile, certificate, now = new Date()) {
  const errors = [], notes = [];
  if (!certificate.ok) {
    errors.push(certificate.error === 'password' ? 'Wrong password for this .p12 file.'
      : certificate.error === 'empty' ? 'This .p12 has no signing certificate with a private key in it.'
      : "This file isn't a valid .p12 certificate.");
    return { ok: false, errors, notes };
  }
  if (certificate.notAfter && certificate.notAfter * 1000 < now.getTime()) {
    errors.push(`This certificate expired on ${new Date(certificate.notAfter * 1000).toLocaleDateString()}.`);
  }
  if (profile.expires && profile.expires.getTime() < now.getTime()) {
    errors.push(`This provisioning profile expired on ${profile.expires.toLocaleDateString()}.`);
  }
  const allowed = await profileCertificateFingerprints(profile);
  if (!allowed.includes(certificate.sha1)) {
    errors.push("This certificate isn't in the provisioning profile. Use the .p12 and the profile that were made together.");
  }
  if (!profile.appID) errors.push('This profile has no App ID.');
  if (!profile.allDevices) {
    notes.push(`Device-limited profile (${profile.deviceCount} device${profile.deviceCount === 1 ? '' : 's'}). Make sure this iPhone's UDID is in the profile, or iOS will refuse to install.`);
  }
  notes.push('If the certificate has been revoked, signing still works here but iOS will refuse to open the app.');
  return { ok: errors.length === 0, errors, notes };
}

/// The bundle ID CertSigner must be signed with for this profile, or null to keep the original.
/// Explicit App ID: that ID. "TEAM.*": keep. "TEAM.prefix.*": keep if it already fits, else prefix + "certsigner".
export function targetBundleID(profile, original) {
  const pattern = profile.bundleIDPattern;
  if (pattern === '*') return null;
  if (pattern.endsWith('.*')) {
    const prefix = pattern.slice(0, -1);
    return original.startsWith(prefix) ? null : prefix + 'certsigner';
  }
  return pattern === original ? null : pattern;
}

// ---------- IPA ----------

function findApp(names) {
  for (const name of names) {
    const match = /^Payload\/([^/]+\.app)\//.exec(name);
    if (match) return 'Payload/' + match[1];
  }
  return null;
}

/// Reads bundle ID, version and name from an IPA's main Info.plist.
export function readIPAInfo(ipa) {
  let app = null;
  const files = unzipSync(ipa, {
    filter: (file) => {
      if (!app) app = findApp([file.name]);
      return /^Payload\/[^/]+\.app\/Info\.plist$/.test(file.name);
    },
  });
  const name = Object.keys(files)[0];
  if (!name) throw new Error("This IPA has no Payload/<App>.app/Info.plist.");
  const info = parsePlist(files[name]);
  return {
    bundleID: info.CFBundleIdentifier || '',
    version: info.CFBundleShortVersionString || info.CFBundleVersion || '1.0',
    title: info.CFBundleDisplayName || info.CFBundleName || 'App',
  };
}

function removeTree(FS, path) {
  let stat;
  try { stat = FS.stat(path); } catch { return; }
  if (FS.isDir(stat.mode)) {
    for (const entry of FS.readdir(path)) if (entry !== '.' && entry !== '..') removeTree(FS, path + '/' + entry);
    FS.rmdir(path);
  } else {
    FS.unlink(path);
  }
}

function collect(FS, dir, prefix, out) {
  for (const entry of FS.readdir(dir)) {
    if (entry === '.' || entry === '..') continue;
    const full = dir + '/' + entry, name = prefix + entry;
    if (FS.isDir(FS.stat(full).mode)) collect(FS, full, name + '/', out);
    // Unix host + rwxr-xr-x, so the app's binaries stay executable after install.
    else out[name] = [FS.readFile(full), { os: 3, attrs: (0o100755 << 16) >>> 0, level: 6 }];
  }
}

/// Opens the .p12 inside the WASM module and describes its certificate.
export function inspectP12(module, p12, password) {
  const FS = module.FS;
  FS.writeFile('/inspect.p12', p12);
  try {
    return JSON.parse(module.ccall('zsign_web_inspect', 'string', ['string', 'string'], ['/inspect.p12', password]));
  } finally {
    FS.unlink('/inspect.p12');
  }
}

/// Signs an IPA in memory and returns { ipa: Uint8Array, bundleID, version, title }.
/// `bundleID` null keeps the app's own. The p12 and profile are deleted from the in-memory
/// filesystem as soon as zsign returns.
export function signIPA(module, { ipa, p12, password, profile, bundleID = null, onLog = () => {}, onStage = () => {} }) {
  const FS = module.FS, work = '/work';
  removeTree(FS, work);
  FS.mkdir(work);
  try {
    onStage('unpack');
    const files = unzipSync(ipa);
    const app = findApp(Object.keys(files));
    if (!app) throw new Error("This IPA has no Payload/<App>.app folder.");
    for (const [name, data] of Object.entries(files)) {
      if (name.endsWith('/')) { FS.mkdirTree(work + '/' + name.slice(0, -1)); continue; }
      const slash = name.lastIndexOf('/');
      if (slash > 0) FS.mkdirTree(work + '/' + name.slice(0, slash));
      FS.writeFile(work + '/' + name, data);
    }
    FS.writeFile(work + '/signing.p12', p12);
    FS.writeFile(work + '/signing.mobileprovision', profile);

    onStage('sign');
    module.onZsignLog = (color, message) => onLog(message, color === 12 ? 'error' : color === 6 ? 'warning' : 'info');
    let code;
    try {
      code = module.ccall('zsign_web_sign', 'number', ['string', 'string', 'string', 'string', 'string'],
        [work + '/' + app, work + '/signing.p12', password, work + '/signing.mobileprovision', bundleID || '']);
    } finally {
      module.onZsignLog = null;
      FS.unlink(work + '/signing.p12');
      FS.unlink(work + '/signing.mobileprovision');
    }
    if (code === -1) throw new Error("The certificate or profile couldn't be loaded. Check the password and that the two files belong together.");
    if (code !== 0) throw new Error('Signing failed. See the log for the file that could not be signed.');

    onStage('pack');
    const out = {};
    collect(FS, work + '/Payload', 'Payload/', out);
    const info = parsePlist(FS.readFile(work + '/' + app + '/Info.plist'));
    const signed = zipSync(out);
    return {
      ipa: signed,
      bundleID: info.CFBundleIdentifier || bundleID || '',
      version: info.CFBundleShortVersionString || info.CFBundleVersion || '1.0',
      title: info.CFBundleDisplayName || info.CFBundleName || 'CertSigner',
    };
  } finally {
    removeTree(FS, work);
  }
}
