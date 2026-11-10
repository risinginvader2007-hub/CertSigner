// The install relay, exercised in Node with an in-memory KV: accepts only a real IPA from the
// allowed origin, serves manifest + IPA, and expires on schedule.
import test from 'node:test';
import assert from 'node:assert/strict';
import { zipSync } from '../site/js/vendor/fflate.js';
import worker, { MAX_BYTES, TTL_SECONDS, AFTER_DOWNLOAD_SECONDS } from '../../worker/src/index.js';

const ORIGIN = 'https://example.github.io';
const text = (s) => new TextEncoder().encode(s);

function fakeEnv({ limit = true } = {}) {
  const map = new Map();
  return {
    ALLOWED_ORIGIN: ORIGIN,
    map,
    STORE: {
      async put(key, value, options) { map.set(key, { value: new Uint8Array(value).slice(), ...options }); },
      async getWithMetadata(key, { type }) {
        const entry = map.get(key);
        if (!entry) return { value: null, metadata: null };
        const value = type === 'arrayBuffer' ? entry.value.slice().buffer : new Blob([entry.value]).stream();
        return { value, metadata: entry.metadata };
      },
      async delete(key) { map.delete(key); },
    },
    UPLOAD_LIMITER: { async limit() { return { success: limit }; } },
  };
}

function ipa(bundleID = 'com.example.app') {
  const plist = `<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>${bundleID}</string>` +
    '<key>CFBundleShortVersionString</key><string>2.5</string><key>CFBundleName</key><string>Tom &amp; Jerry</string></dict></plist>';
  return zipSync({ 'Payload/Test.app/Info.plist': text(plist), 'Payload/Test.app/Test': new Uint8Array(70000).fill(7) });
}

const ctx = () => { const pending = []; return { waitUntil: (p) => pending.push(p), settle: () => Promise.all(pending) }; };
const post = (body, headers = {}) => new Request('https://relay.example/upload', { method: 'POST', body, headers: { Origin: ORIGIN, ...headers } });

test('rejects what is not a signed IPA from the page', async () => {
  const env = fakeEnv();
  assert.equal((await worker.fetch(post(ipa(), { Origin: 'https://evil.example' }), env, ctx())).status, 403);
  assert.equal((await worker.fetch(post(text('hello, not a zip')), env, ctx())).status, 415);
  assert.equal((await worker.fetch(post(zipSync({ 'readme.txt': text('no payload') })), env, ctx())).status, 415);
  assert.equal((await worker.fetch(post(new Uint8Array(MAX_BYTES + 1)), env, ctx())).status, 413);
  assert.equal((await worker.fetch(post(ipa()), fakeEnv({ limit: false }), ctx())).status, 429);
  assert.equal((await worker.fetch(new Request('https://relay.example/upload'), env, ctx())).status, 405);
  assert.equal(env.map.size, 0, 'nothing stored');
});

test('upload -> manifest -> IPA -> expiry', async () => {
  const env = fakeEnv(), file = ipa('com.example.signed');
  const response = await worker.fetch(post(file), env, ctx());
  assert.equal(response.status, 201);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  const { id, manifestURL, ipaURL, expiresIn } = await response.json();
  assert.match(id, /^[0-9a-f]{64}$/);
  assert.equal(expiresIn, TTL_SECONDS);
  assert.equal([...env.map.values()][0].expirationTtl, TTL_SECONDS);

  const manifest = await (await worker.fetch(new Request(manifestURL), env, ctx())).text();
  assert.match(manifest, /<string>com\.example\.signed<\/string>/, 'bundle ID read from the IPA');
  assert.match(manifest, /<string>2\.5<\/string>/);
  assert.match(manifest, /<string>Tom &amp; Jerry<\/string>/, 'title is XML-escaped');
  assert.ok(manifest.includes(`<string>${ipaURL}</string>`) && ipaURL.startsWith('https://'));

  const part = await worker.fetch(new Request(ipaURL, { headers: { Range: 'bytes=0-99' } }), env, ctx());
  assert.equal(part.status, 206);
  assert.equal(part.headers.get('Content-Range'), `bytes 0-99/${file.length}`);
  assert.equal((await part.arrayBuffer()).byteLength, 100);
  assert.equal([...env.map.values()][0].metadata.done, undefined, 'a partial read does not start the countdown');

  const c = ctx();
  const full = await worker.fetch(new Request(ipaURL), env, c);
  assert.equal(full.headers.get('Content-Type'), 'application/octet-stream');
  assert.deepEqual(new Uint8Array(await full.arrayBuffer()), file);
  await c.settle();
  const stored = [...env.map.values()][0];
  assert.equal(stored.expirationTtl, AFTER_DOWNLOAD_SECONDS, 'kept 2 more minutes after a complete download');
  assert.ok(stored.metadata.done);

  // Past the 2 minutes: gone and deleted.
  stored.metadata.done -= (AFTER_DOWNLOAD_SECONDS + 1) * 1000;
  assert.equal((await worker.fetch(new Request(ipaURL), env, ctx())).status, 404);
  assert.equal(env.map.size, 0);
  assert.equal((await worker.fetch(new Request(manifestURL), env, ctx())).status, 404);
  assert.equal((await worker.fetch(new Request('https://relay.example/i/' + 'a'.repeat(64) + '/app.ipa'), env, ctx())).status, 404);
});

test('an unread upload expires after 10 minutes', async () => {
  const env = fakeEnv();
  const { manifestURL } = await (await worker.fetch(post(ipa()), env, ctx())).json();
  [...env.map.values()][0].metadata.created -= (TTL_SECONDS + 1) * 1000;
  assert.equal((await worker.fetch(new Request(manifestURL), env, ctx())).status, 404);
  assert.equal(env.map.size, 0);
});
