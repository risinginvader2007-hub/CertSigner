// "Get CertSigner" install relay (Cloudflare Worker + KV).
//
// iOS only installs from an HTTPS URL, so the page hands the SIGNED app to this Worker for a few
// minutes. It never receives a certificate, a password or a profile: only the finished IPA.
//
//   POST /upload               signed IPA in the body  ->  { id, manifestURL, ipaURL, expiresIn }
//   GET  /i/<id>/manifest.plist  itms-services manifest (bundle ID, version, title read from the IPA)
//   GET  /i/<id>/app.ipa         the IPA
//
// Everything is deleted after 10 minutes, or 2 minutes after the first complete download.
// No accounts, no logs of file contents, nothing else stored.
import { readIPAInfo } from '../../web/site/js/signer-core.js';

export const MAX_BYTES = 25 * 1024 * 1024; // KV's per-value limit (a signed CertSigner is about 6 MB)
export const TTL_SECONDS = 600;
export const AFTER_DOWNLOAD_SECONDS = 120;

const xml = (s) => String(s).replace(/[<>&"']/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[c]));

function cors(env, request) {
  const allowed = (env.ALLOWED_ORIGIN || '').split(',').map((s) => s.trim()).filter(Boolean);
  const origin = request.headers.get('Origin') || '';
  const headers = { Vary: 'Origin' };
  if (allowed.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
    headers['Access-Control-Allow-Headers'] = 'Content-Type';
    headers['Access-Control-Max-Age'] = '600';
  }
  return { headers, ok: allowed.includes(origin) };
}

function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...extra },
  });
}

function manifest(ipaURL, meta) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>items</key><array><dict>
    <key>assets</key><array><dict>
      <key>kind</key><string>software-package</string>
      <key>url</key><string>${xml(ipaURL)}</string>
    </dict></array>
    <key>metadata</key><dict>
      <key>bundle-identifier</key><string>${xml(meta.bundleID)}</string>
      <key>bundle-version</key><string>${xml(meta.version)}</string>
      <key>kind</key><string>software</string>
      <key>title</key><string>${xml(meta.title)}</string>
    </dict>
  </dict></array>
</dict></plist>
`;
}

async function upload(request, env) {
  const { headers, ok } = cors(env, request);
  if (!ok) return json(403, { error: 'origin', message: 'Uploads are only accepted from the Get CertSigner page.' }, headers);

  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  if (env.UPLOAD_LIMITER) {
    const { success } = await env.UPLOAD_LIMITER.limit({ key: ip });
    if (!success) return json(429, { error: 'rate', message: 'Too many uploads from this network. Wait a minute and try again.' }, headers);
  }

  const declared = Number(request.headers.get('Content-Length') || 0);
  if (declared > MAX_BYTES) return json(413, { error: 'size', message: 'The signed app is larger than 25 MB.' }, headers);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length === 0 || bytes.length > MAX_BYTES) {
    return json(bytes.length ? 413 : 400, { error: 'size', message: bytes.length ? 'The signed app is larger than 25 MB.' : 'Empty upload.' }, headers);
  }

  // Must be a ZIP with Payload/<App>.app/Info.plist; the manifest's metadata comes from it.
  let info;
  try {
    if (!(bytes[0] === 0x50 && bytes[1] === 0x4b)) throw new Error('not a zip');
    info = readIPAInfo(bytes);
    if (!/^[A-Za-z0-9.-]{1,155}$/.test(info.bundleID)) throw new Error('bundle id');
  } catch {
    return json(415, { error: 'format', message: 'That is not an IPA (a ZIP with a Payload folder).' }, headers);
  }

  const id = Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, '0')).join('');
  const meta = {
    bundleID: info.bundleID,
    version: String(info.version).slice(0, 32),
    title: String(info.title).replace(/[\u0000-\u001f]/g, '').slice(0, 64),
    created: Date.now(),
  };
  await env.STORE.put('ipa:' + id, bytes, { expirationTtl: TTL_SECONDS, metadata: meta });
  const base = new URL(request.url).origin;
  return json(201, {
    id,
    manifestURL: `${base}/i/${id}/manifest.plist`,
    ipaURL: `${base}/i/${id}/app.ipa`,
    expiresIn: TTL_SECONDS,
  }, headers);
}

/// Live metadata for an id, or null (also deletes entries that are past their time).
async function lookup(env, id, withBody) {
  const key = 'ipa:' + id;
  const entry = await env.STORE.getWithMetadata(key, { type: withBody ? 'arrayBuffer' : 'stream' });
  if (!entry || !entry.value || !entry.metadata) return null;
  const meta = entry.metadata, now = Date.now();
  const expired = now > meta.created + TTL_SECONDS * 1000 || (meta.done && now > meta.done + AFTER_DOWNLOAD_SECONDS * 1000);
  if (expired) {
    if (!withBody && entry.value.cancel) entry.value.cancel();
    await env.STORE.delete(key);
    return null;
  }
  if (!withBody && entry.value.cancel) entry.value.cancel();
  return { key, meta, body: withBody ? entry.value : null };
}

async function serve(request, env, ctx, id, file) {
  const plain = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
  const gone = () => new Response('This install link has expired. Sign again on the Get CertSigner page.\n', { status: 404, headers: { ...plain, 'Content-Type': 'text/plain; charset=utf-8' } });

  if (file === 'manifest.plist') {
    const found = await lookup(env, id, false);
    if (!found) return gone();
    const body = manifest(`${new URL(request.url).origin}/i/${id}/app.ipa`, found.meta);
    return new Response(request.method === 'HEAD' ? null : body, { headers: { ...plain, 'Content-Type': 'text/xml; charset=utf-8' } });
  }

  const found = await lookup(env, id, true);
  if (!found) return gone();
  const bytes = new Uint8Array(found.body), total = bytes.length;
  const headers = { ...plain, 'Content-Type': 'application/octet-stream', 'Accept-Ranges': 'bytes', 'Content-Disposition': 'attachment; filename="app.ipa"' };
  if (request.method === 'HEAD') return new Response(null, { headers: { ...headers, 'Content-Length': String(total) } });

  let start = 0, end = total - 1, status = 200;
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('Range') || '');
  if (range && (range[1] || range[2])) {
    if (range[1]) { start = Number(range[1]); if (range[2]) end = Math.min(Number(range[2]), total - 1); }
    else { start = Math.max(0, total - Number(range[2])); }
    if (start > end || start >= total) return new Response(null, { status: 416, headers: { ...headers, 'Content-Range': `bytes */${total}` } });
    status = 206;
    headers['Content-Range'] = `bytes ${start}-${end}/${total}`;
  }
  // The response reaches the end of the file: start the 2-minute countdown (once).
  if (end === total - 1 && !found.meta.done) {
    const meta = { ...found.meta, done: Date.now() };
    ctx.waitUntil(env.STORE.put(found.key, bytes, { expirationTtl: AFTER_DOWNLOAD_SECONDS, metadata: meta }));
  }
  return new Response(bytes.subarray(start, end + 1), { status, headers: { ...headers, 'Content-Length': String(end - start + 1) } });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      const { headers, ok } = cors(env, request);
      return new Response(null, { status: ok ? 204 : 403, headers });
    }
    if (url.pathname === '/upload') {
      if (request.method !== 'POST') return json(405, { error: 'method' }, { Allow: 'POST, OPTIONS' });
      return upload(request, env);
    }
    const match = /^\/i\/([0-9a-f]{64})\/(manifest\.plist|app\.ipa)$/.exec(url.pathname);
    if (match && (request.method === 'GET' || request.method === 'HEAD')) return serve(request, env, ctx, match[1], match[2]);
    if (url.pathname === '/' && request.method === 'GET') {
      return new Response('Get CertSigner install relay. Signed apps are held for at most 10 minutes; nothing else is stored.\n',
        { headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' } });
    }
    return new Response('Not found\n', { status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' } });
  },
};
