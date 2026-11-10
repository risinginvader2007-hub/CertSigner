// Web Worker: all signing happens here, in memory. This file makes no network request other
// than loading its own code (zsign.js / zsign.wasm) from this site.
import createZsign from '../wasm/zsign.js';
import { inspectP12, signIPA, parseProfile, validate, targetBundleID, readIPAInfo } from './signer-core.js';

const ready = createZsign();
ready.then(() => postMessage({ type: 'ready' }), (error) => postMessage({ type: 'error', message: 'The signer could not start in this browser. ' + (error && error.message || '') }));

self.onmessage = async (event) => {
  const { ipa, p12, password, profile } = event.data;
  try {
    const module = await ready;
    postMessage({ type: 'stage', stage: 'validate' });
    const certificate = inspectP12(module, p12, password);
    const facts = parseProfile(profile);
    const verdict = await validate(facts, certificate);
    postMessage({
      type: 'checked',
      certificate: certificate.ok ? { name: certificate.name, notAfter: certificate.notAfter } : null,
      verdict,
    });
    if (!verdict.ok) return;

    const original = readIPAInfo(ipa);
    const bundleID = targetBundleID(facts, original.bundleID);
    postMessage({ type: 'log', message: bundleID ? `Explicit App ID: signing as ${bundleID} (was ${original.bundleID})` : `Keeping bundle ID ${original.bundleID}` });
    const result = signIPA(module, {
      ipa, p12, password, profile, bundleID,
      onLog: (message, level) => postMessage({ type: 'log', message: message.replace(/\s+$/, ''), level }),
      onStage: (stage) => postMessage({ type: 'stage', stage: stage === 'sign' ? 'sign' : stage }),
    });
    postMessage({ type: 'signed', ipa: result.ipa, bundleID: result.bundleID, version: result.version, title: result.title,
      certificateName: certificate.name, changedBundleID: bundleID !== null }, [result.ipa.buffer]);
  } catch (error) {
    postMessage({ type: 'error', message: (error && error.message) || 'Signing failed.' });
  } finally {
    // Wipe this worker's copies; the page terminates the worker right after.
    p12.fill(0);
    profile.fill(0);
  }
};
