// End-to-end in real browser engines (Chromium, and WebKit as on iPhone Safari): the whole page
// flow with throwaway fixture files, and the privacy guarantee: NO network request ever contains
// the .p12, its password or the private key. The install relay is faked inside the test.
//
// Needs: the WASM build, an IPA in site/app, fixtures, and `npm i --no-save playwright`.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { fillPlaceholders } from '../scripts/prepare-site.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const site = path.join(here, '..', 'site');
const fixtures = path.join(here, 'fixtures');
const shots = path.join(here, '..', 'test-results');
const RELAY = 'https://relay.test';
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png', '.json': 'application/json', '.ipa': 'application/octet-stream' };

let playwright = null;
try { playwright = await import('playwright'); } catch { /* skipped below */ }
const ready = playwright && existsSync(path.join(site, 'wasm', 'zsign.wasm')) && existsSync(path.join(site, 'app', 'CertSigner.ipa')) && existsSync(path.join(fixtures, 'cert.p12'));

function serve() {
  const server = http.createServer((request, response) => {
    const name = decodeURIComponent(new URL(request.url, 'http://x').pathname);
    const file = path.join(site, name === '/' ? 'index.html' : name);
    if (!file.startsWith(site) || !existsSync(file)) { response.writeHead(404).end('not found'); return; }
    let body = readFileSync(file);
    if (file.endsWith('index.html')) body = Buffer.from(fillPlaceholders(body.toString('utf8'), RELAY));
    response.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' }).end(body);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

/// Every window of `size` bytes from `secret`, stepping by `step`, must be absent from `haystack`.
function leaks(haystack, secret, size = 48, step = 97) {
  for (let at = 0; at + size <= secret.length; at += step) if (haystack.includes(secret.subarray(at, at + size))) return at;
  return -1;
}

for (const engine of ['chromium', 'webkit']) {
  test(`${engine}: sign in the page; no request carries the certificate or password`, { skip: !ready && 'needs playwright + WASM build + IPA + fixtures', timeout: 180000 }, async () => {
    const password = readFileSync(path.join(fixtures, 'password.txt'), 'utf8');
    const p12 = readFileSync(path.join(fixtures, 'cert.p12'));
    const privateKey = Buffer.from(readFileSync(path.join(fixtures, 'main.key'), 'utf8').replace(/-----[^-]+-----|\s/g, ''), 'base64');
    const server = await serve();
    const origin = `http://127.0.0.1:${server.address().port}`;
    const browser = await playwright[engine].launch();
    try {
      const context = await browser.newContext(engine === 'webkit' ? playwright.devices['iPhone 14'] : { viewport: { width: 390, height: 844 } });
      const page = await context.newPage();
      const requests = [], uploads = [], consoleErrors = [];
      page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()); });
      page.on('pageerror', (error) => consoleErrors.push(String(error)));
      context.on('request', (request) => requests.push({ url: request.url(), method: request.method(), body: request.postDataBuffer() }));
      await context.route(RELAY + '/**', async (route) => {
        const request = route.request();
        const cors = { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
        if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
        uploads.push(request.postDataBuffer());
        return route.fulfill({ status: 201, headers: cors, contentType: 'application/json',
          body: JSON.stringify({ id: 'f'.repeat(64), manifestURL: `${RELAY}/i/${'f'.repeat(64)}/manifest.plist`, ipaURL: `${RELAY}/i/${'f'.repeat(64)}/app.ipa`, expiresIn: 600 }) });
      });

      await page.goto(origin + '/');
      await page.setInputFiles('#p12', path.join(fixtures, 'cert.p12'));
      await page.setInputFiles('#profile', path.join(fixtures, 'mismatch.mobileprovision'));
      await page.fill('#password', 'not-the-password');
      await page.waitForFunction(() => !document.getElementById('sign').disabled, null, { timeout: 60000 });
      assert.match(await page.textContent('#facts'), /Device-limited · 2 UDIDs/);

      // Wrong password: a readable message, nothing signed, nothing sent.
      await page.click('#sign');
      await page.waitForSelector('#files-error:not([hidden])');
      assert.match(await page.textContent('#files-error'), /Wrong password/);

      // Right password, but a profile made for another certificate: blocked.
      await page.fill('#password', password);
      await page.waitForFunction(() => !document.getElementById('sign').disabled);
      await page.click('#sign');
      await page.waitForFunction(() => /isn't in the provisioning profile/.test(document.getElementById('files-error').textContent));
      assert.match(await page.textContent('#facts'), /Certificate matches profileNo/);

      // An expired profile: blocked.
      await page.setInputFiles('#profile', path.join(fixtures, 'expired.mobileprovision'));
      await page.waitForFunction(() => !document.getElementById('sign').disabled);
      await page.click('#sign');
      await page.waitForFunction(() => /profile expired/.test(document.getElementById('files-error').textContent));
      assert.equal(uploads.length, 0, 'nothing uploaded while blocked');

      // The matching explicit profile: signs, uploads the signed app only, offers Install.
      await page.setInputFiles('#profile', path.join(fixtures, 'explicit.mobileprovision'));
      await page.waitForFunction(() => !document.getElementById('sign').disabled);
      await page.click('#sign');
      await page.waitForSelector('#panel-ready:not([hidden])', { timeout: 120000 });
      const href = await page.getAttribute('#install', 'href');
      assert.equal(href, 'itms-services://?action=download-manifest&url=' + encodeURIComponent(`${RELAY}/i/${'f'.repeat(64)}/manifest.plist`));
      assert.match(await page.textContent('#ready-summary'), /as com\.example\.signedweb to match your profile/);
      assert.match(await page.getAttribute('#download', 'href'), /^blob:/);
      mkdirSync(shots, { recursive: true });
      await page.screenshot({ path: path.join(shots, `${engine}-ready.png`), fullPage: true });

      // Secrets are cleared from the page.
      assert.equal(await page.inputValue('#password'), '');
      assert.equal(await page.evaluate(() => document.getElementById('p12').files.length + document.getElementById('profile').files.length), 0);
      const logText = await page.textContent('#log');
      assert.ok(!logText.includes(password), 'the log never shows the password');
      assert.match(logText, /cleared from memory/);

      // The privacy guarantee, checked against every request the browser made.
      assert.equal(uploads.length, 1, 'exactly one upload');
      const upload = uploads[0];
      assert.ok(upload && upload.length > 1_000_000 && upload[0] === 0x50 && upload[1] === 0x4b, 'the upload is the signed IPA (a ZIP)');
      const passwordBytes = Buffer.from(password);
      for (const request of requests) {
        assert.ok(!request.url.includes(encodeURIComponent(password)) && !request.url.includes(password), 'no URL carries the password');
        const outside = !request.url.startsWith(origin);
        if (outside) assert.ok(request.url.startsWith(RELAY + '/'), `unexpected request to ${request.url}`);
        if (!request.body) continue;
        assert.ok(request.url === RELAY + '/upload', `only the upload has a body (${request.method} ${request.url})`);
        assert.ok(!request.body.includes(passwordBytes), 'no request body contains the password');
        assert.equal(leaks(request.body, p12), -1, 'no request body contains any part of the .p12');
        assert.equal(leaks(request.body, privateKey), -1, 'no request body contains the private key');
      }
      const others = requests.filter((r) => !r.url.startsWith(origin));
      console.log(`${engine}: ${requests.length} requests, ${others.length} to the relay, upload ${upload.length} bytes, console errors: ${consoleErrors.length}`);
      assert.deepEqual(consoleErrors, [], 'no console errors (CSP violations show up here)');

      // Start Over returns to a clean form.
      await page.click('#reset');
      await page.waitForSelector('#panel-files:not([hidden])');
      await page.screenshot({ path: path.join(shots, `${engine}-start.png`), fullPage: true });
    } finally {
      await browser.close();
      server.close();
    }
  });
}
