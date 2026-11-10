// Signs the real unsigned CertSigner.ipa with the WebAssembly zsign, in Node, using throwaway
// fixture certificates. Run: bash web/tests/make-fixtures.sh && node --test web/tests
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { unzipSync } from '../site/js/vendor/fflate.js';
import {
  inspectP12, signIPA, parseProfile, parsePlist, validate, targetBundleID, readIPAInfo,
} from '../site/js/signer-core.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = (name) => new Uint8Array(readFileSync(path.join(here, 'fixtures', name)));
const password = readFileSync(path.join(here, 'fixtures', 'password.txt'), 'utf8');
const ipaPath = process.env.IPA || path.join(here, '..', 'site', 'app', 'CertSigner.ipa');
const wasmDir = path.join(here, '..', 'site', 'wasm');

async function loadModule() {
  const { default: createZsign } = await import(pathToFileURL(path.join(wasmDir, 'zsign.js')).href);
  return createZsign({ wasmBinary: readFileSync(path.join(wasmDir, 'zsign.wasm')) });
}

function contains(bytes, text) {
  return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).includes(Buffer.from(text));
}

test('p12 inspection: right password, wrong password, legacy encryption, not a p12', async () => {
  const module = await loadModule();
  const good = inspectP12(module, fixture('cert.p12'), password);
  console.log('inspect:', JSON.stringify(good));
  assert.equal(good.ok, true);
  assert.match(good.name, /Web Test main/);
  assert.ok(good.notAfter * 1000 > Date.now());
  assert.deepEqual(inspectP12(module, fixture('cert.p12'), 'wrong'), { ok: false, error: 'password' });
  assert.equal(inspectP12(module, fixture('legacy.p12'), password).sha1, good.sha1, 'legacy (RC2/3DES) p12 opens too');
  assert.equal(inspectP12(module, fixture('wildcard.mobileprovision'), password).error, 'format');
});

test('profile facts and validation messages', async () => {
  const module = await loadModule();
  const certificate = inspectP12(module, fixture('cert.p12'), password);
  const wildcard = parseProfile(fixture('wildcard.mobileprovision'));
  assert.equal(wildcard.teamID, 'ABCDE12345');
  assert.equal(wildcard.isWildcard, true);
  assert.equal(wildcard.deviceCount, 2);
  assert.equal(wildcard.getTaskAllow, true);
  const ok = await validate(wildcard, certificate);
  assert.equal(ok.ok, true, ok.errors.join(' | '));
  assert.match(ok.notes.join(' '), /UDID/);

  const explicit = parseProfile(fixture('explicit.mobileprovision'));
  assert.equal(explicit.isWildcard, false);
  assert.equal(targetBundleID(explicit, 'com.certsigner.app'), 'com.example.signedweb');
  assert.equal(targetBundleID(wildcard, 'com.certsigner.app'), null);

  const expired = await validate(parseProfile(fixture('expired.mobileprovision')), certificate);
  assert.equal(expired.ok, false);
  assert.match(expired.errors.join(' '), /profile expired/);
  const mismatch = await validate(parseProfile(fixture('mismatch.mobileprovision')), certificate);
  assert.equal(mismatch.ok, false);
  assert.match(mismatch.errors.join(' '), /isn't in the provisioning profile/);
  const wrong = await validate(wildcard, inspectP12(module, fixture('cert.p12'), 'nope'));
  assert.match(wrong.errors.join(' '), /Wrong password/);
});

test('signs CertSigner.ipa: wildcard keeps the bundle ID, explicit rewrites it', { skip: !existsSync(ipaPath) && 'no IPA at ' + ipaPath }, async () => {
  const ipa = new Uint8Array(readFileSync(ipaPath));
  const original = readIPAInfo(ipa);
  console.log('unsigned IPA:', JSON.stringify(original), ipa.length, 'bytes');
  const originalFiles = unzipSync(ipa);

  for (const [profileName, expectedID] of [['wildcard', original.bundleID], ['explicit', 'com.example.signedweb']]) {
    const module = await loadModule();
    const profileBytes = fixture(profileName + '.mobileprovision');
    const profile = parseProfile(profileBytes);
    const log = [];
    const started = Date.now();
    const result = signIPA(module, {
      ipa, p12: fixture('cert.p12'), password, profile: profileBytes,
      bundleID: targetBundleID(profile, original.bundleID),
      onLog: (message) => log.push(message),
    });
    console.log(`${profileName}: signed in ${Date.now() - started} ms, ${result.ipa.length} bytes, bundle ID ${result.bundleID}, ${log.length} log lines`);
    for (const line of log) console.log('  zsign| ' + line.trimEnd());
    assert.equal(result.bundleID, expectedID);
    assert.equal(result.version, original.version);

    const files = unzipSync(result.ipa);
    const app = Object.keys(files).find((n) => /^Payload\/[^/]+\.app\/Info\.plist$/.test(n)).replace('/Info.plist', '');
    assert.ok(files[app + '/_CodeSignature/CodeResources'], 'CodeResources written');
    assert.deepEqual(Buffer.from(files[app + '/embedded.mobileprovision']), Buffer.from(profileBytes), 'profile embedded');
    const info = parsePlist(files[app + '/Info.plist']);
    assert.equal(info.CFBundleIdentifier, expectedID);
    const executable = app + '/' + info.CFBundleExecutable;
    assert.ok(!Buffer.from(files[executable]).equals(Buffer.from(originalFiles[executable])), 'main binary re-signed');
    const markers = ['Web Test main', 'Web Test WWDR CA', 'CertSigner Test', 'ABCDE12345', 'application-identifier', 'get-task-allow']
      .map((m) => `${m}=${contains(files[executable], m)}`).join(', ');
    console.log(`${profileName}: markers in the signed binary: ${markers}; binary ${originalFiles[executable].length} -> ${files[executable].length} bytes`);
    assert.ok(contains(files[executable], 'ABCDE12345'), 'signature carries the team ID');
    assert.ok(contains(files[executable], 'ABCDE12345.' + (profile.isWildcard ? '*' : expectedID)), 'entitlements carry the profile App ID');
    const nested = Object.keys(files).filter((n) => /\.(framework|appex)\/_CodeSignature\/CodeResources$/.test(n));
    const nestedOriginal = Object.keys(originalFiles).filter((n) => /\.(framework|appex)\/Info\.plist$/.test(n));
    console.log(`${profileName}: nested bundles signed ${nested.length} of ${nestedOriginal.length}`);
    assert.equal(nested.length, nestedOriginal.length, 'every nested framework / extension signed');
    // Secrets are gone from the in-memory filesystem.
    assert.throws(() => module.FS.stat('/work'));
    assert.ok(!log.join('\n').includes(password), 'log never contains the password');
  }
});
