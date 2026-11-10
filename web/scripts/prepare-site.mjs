// Builds the publishable site: web/site -> web/dist with the relay URL filled in and
// app/build.json written from the IPA. Usage: node scripts/prepare-site.mjs [relay URL]
import { cpSync, rmSync, readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readIPAInfo } from '../site/js/signer-core.js';

const web = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const site = path.join(web, 'site'), dist = path.join(web, 'dist');
const relay = (process.argv[2] || process.env.RELAY_URL || '').trim().replace(/\/$/, '');
if (relay && !/^https:\/\/[a-z0-9.-]+$/i.test(relay)) throw new Error('Relay URL must look like https://host');

export function fillPlaceholders(html, relayURL) {
  return html.replaceAll('__RELAY_URL__', relayURL).replaceAll('__RELAY_ORIGIN__', relayURL);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  rmSync(dist, { recursive: true, force: true });
  cpSync(site, dist, { recursive: true });
  writeFileSync(path.join(dist, 'index.html'), fillPlaceholders(readFileSync(path.join(site, 'index.html'), 'utf8'), relay));
  const ipa = path.join(dist, 'app', 'CertSigner.ipa');
  if (existsSync(ipa)) {
    const info = readIPAInfo(new Uint8Array(readFileSync(ipa)));
    mkdirSync(path.join(dist, 'app'), { recursive: true });
    writeFileSync(path.join(dist, 'app', 'build.json'), JSON.stringify({ version: info.version, build: process.env.BUILD_NUMBER || 'dev', commit: (process.env.GITHUB_SHA || '').slice(0, 7) }) + '\n');
  }
  writeFileSync(path.join(dist, '.nojekyll'), '');
  console.log(`web/dist ready (relay: ${relay || 'not configured'})`);
}
