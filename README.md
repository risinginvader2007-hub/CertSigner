# CertSigner

An on-device iOS signer for **your own certificates, your own devices and IPAs you already have**.
Import an IPA from Files, review it, sign it on the phone with zsign, and install it with the system install prompt.
SwiftUI (iOS 16+), built by GitHub Actions — no Mac needed.

## Get the app

**Direct link (always the newest successful build):**
https://github.com/risinginvader2007-hub/CertSigner/releases/latest/download/CertSigner.ipa

Open it in Safari on your iPhone, then share the file to FlareStore (or any signer) to install CertSigner itself.

**Updates:** once installed, CertSigner checks this repository's latest release (at most every 12 hours,
or Settings → About → Updates). Tap **Update**: it downloads the new build, checks it against the
release's `update.json` (size, SHA-256, bundle ID, build), signs it with your own certificate from
the same team (keeping your bundle ID) and opens the iOS install prompt. CertSigner closes while
iOS updates it; your certificates, apps and settings stay.

### From GitHub Actions
1. Push to `main`, or open **Actions → Build IPA → Run workflow**.
2. Wait for the green tick (about 2–4 minutes).
3. Every green build on `main` also replaces the **latest** release, so the direct link above updates automatically.
4. Or open the run, scroll to **Artifacts**, download **CertSigner-ipa** and unzip it to get `CertSigner.ipa`.

## Using CertSigner

### 1. Add a certificate (Settings → Certificates, or the Home card)
- Tap **Add Certificate**, pick your `.p12`, your `.mobileprovision`, enter a nickname and the `.p12` password.
- The password is checked straight away and stored only in the iOS Keychain.
- Certificate details: team, profile type, App ID, devices, entitlements, expiry, whether the `.p12` is in the profile, and **Raw Profile Data** (the `application-identifier` and where it came from).
- **Switch** the active certificate from Home or Settings (a bottom sheet). Sharing a `.p12` / `.mobileprovision` to CertSigner opens the import sheet too.
- Installed CertSigner from the web installer? Tap **Import Certificate into CertSigner** on that page to bring the same certificate into the app.
- Paste your **UDID** in Settings → This Device so CertSigner can check your iPhone is in each profile (sideloaded apps can't read it themselves).

### 2. Home
- Stat cards: certificates, signed apps, days left on the active certificate.
- **Needs attention** banner when a signed app or the active certificate expires within 7 days (or has expired); tap it to see those apps in Library.
- **Import IPA**: tap to browse Files, drop an `.ipa` on it, or share an `.ipa` from Files → **CertSigner**.
- **Quick Sign**: pick an IPA and queue it immediately with your defaults (if the pre-sign checks pass).

### 3. Review & Sign
- Shows the icon, name, bundle ID, version, size and extensions read from the IPA.
- Options: display name, version, **keep original bundle ID** or set a new one (explicit profiles pre-fill their exact App ID), remove app extensions, remove the Watch app.
- **Pre-sign checks**: certificate not expired, `.p12` matches the profile, bundle ID (and extensions) allowed by the App ID, this iPhone's UDID in the profile. Failing checks block signing with a clear reason.
- **Signing mode** (per app; default in Settings):
  - *Compatibility* (default): keeps the app's bundle ID, signs every extension, framework and dylib, and skips the App ID mismatch checks (like FlareStore).
  - *Strict*: rewrites the bundle ID and blocks signing when the App ID doesn't match.
- **Install when done** starts the install prompt automatically after signing.

### 4. Library
- **Signing**: live jobs with step progress (Unpacking → Patching → Signing → Packaging) and a progress ring. Tap a job for the live log (**Share signing log** for a detailed copy). Failed jobs show the reason with **Retry** / **Remove**. Jobs survive relaunch (an interrupted job is marked failed so you can retry).
- **Signed Apps**: icon, version, certificate used, status badge (valid / expiring / expired) and expiry countdown, with **Install**, **Re-sign** (with the active certificate, replaces the old copy) and **Share**. Swipe left to delete (with **Undo** for 5 s), right to re-sign. Search, and **Sort & Filter** (date, name, expiry; status, certificate).
- The Library tab badge counts signed apps that are expiring or expired.

### 5. Sources
- **Sources tab → +**: paste a source URL (AltStore / SideStore / Feather JSON; the older ESign and Scarlet layouts work too). `altstore://source?url=…` links are accepted as well.
- Browse a source or **All Apps**: icon, version, size, description, screenshots, version history.
- **GET** downloads the IPA, signs it with your active certificate and defaults, and opens the install prompt. **Download & Review** opens Review & Sign first. Any older version can be picked from **Versions**.
- Pull to refresh (sources also refresh on their own every 30 minutes while you browse); swipe to refresh or remove; Edit to reorder. Source apps show up in Search too.
- Sources need `https://` links (iOS blocks plain http).

### 6. Install
- CertSigner serves the signed IPA from the phone's loopback interface and opens `itms-services://`; iOS shows its install prompt.
- **Settings → Install** picks the method: *Automatic* (default), *Fully Local (HTTPS)* or *Semi-Local*.
  - Fully Local needs a trusted certificate for a hostname that resolves to 127.0.0.1: the public backloop.dev certificate (when valid) or your own domain (see below).
    The backloop.dev certificate expired on 2026-10-29; until it is renewed, Automatic uses Semi-Local unless you add your own.
  - Semi-Local serves the IPA locally and gets only the small manifest from `api.palera.in` (needs internet). If that service is down, CertSigner falls back to Fully Local (setting, on by default).
- The install sheet follows what iOS actually requests. If iOS doesn't ask for the app, it offers **Reopen Prompt** and **Try Again**; after the download it confirms the app is installed, and it tells you when an app with the same ID is already installed (update in place, or from a different team: delete it first). **Share Install Log** helps with reports.

#### Using your own domain for Fully Local
1. Add a DNS **A record** such as `install.example.com → 127.0.0.1` (Cloudflare: proxy off).
2. Get a certificate with a **DNS-01** challenge, e.g. `certbot certonly --manual --preferred-challenges dns -d install.example.com`.
3. Put `fullchain.pem` and `privkey.pem` (unencrypted) in Files, then Settings → Install → **Add My Own Certificate**.
4. Renew before it expires (Let's Encrypt: 90 days) and import again.

### 7. Settings
Certificates, signing defaults (signing mode, remove extensions, keep bundle ID), install after signing, delete original IPA after signing, install method and server certificates, close the install sheet automatically, UDID, appearance (system / light / dark), accent colour (solid colours, blends and your own custom blends), background animation and glow intensity (separately for light and dark), **app icon** (Ocean, Sunset, Mint, Midnight), a **storage dashboard** (usage by category, Clear Cache, Remove Unused Imports, Clear Log), **Export Log File**, and About.

## Web installer ("Get CertSigner")

Install CertSigner from Safari with only your own `.p12` and `.mobileprovision`, no other
sideloading app: **https://risinginvader2007-hub.github.io/CertSigner/**

### How it works

| Part | Where | What it does |
|---|---|---|
| Page | `web/site` (GitHub Pages) | Picks the files, shows the profile facts, runs the signer, offers Install / Download. |
| Signer | `web/wasm` → `zsign.wasm` | The same vendored zsign as the app plus OpenSSL, compiled to WebAssembly with Emscripten. Runs in a Web Worker, entirely in memory. |
| Unsigned app | `app/CertSigner.ipa` on Pages | A same-origin copy of the IPA from this build (no CORS). |
| Install relay | `worker/` (Cloudflare Worker + KV) | Holds the **signed** IPA for a few minutes and serves the `itms-services` manifest, because iOS only installs from an HTTPS URL. |

**Privacy.** The `.p12`, its password and the profile are read into memory in the page, passed to
the signing worker, and cleared when signing ends (the worker is terminated and the fields are
emptied). No network request contains them. That is enforced by a test: `web/tests/e2e.test.mjs`
drives the real page in Chromium and WebKit and checks every request the browser makes. The only
upload is the signed IPA. The page has a strict Content-Security-Policy (no third-party scripts,
styles or fonts; it may only connect to itself and the relay), no cookies, no analytics.

**Signing rules.** A wildcard profile keeps CertSigner's bundle ID. A profile with an explicit
App ID re-signs CertSigner with that bundle ID so iOS accepts it. The profile's entitlements are
used as they are (so `get-task-allow` is kept when the profile has it), and every nested framework
is signed. Signing is blocked, with the reason, when the password is wrong, the certificate is not
in the profile, or the profile or certificate has expired. On first launch the app shows
"Signed with <certificate>, expires <date>".

**The relay** (`worker/src/index.js`):

- `POST /upload` accepts only a ZIP with `Payload/<App>.app/Info.plist`, up to 25 MB (KV's value
  limit; a signed CertSigner is about 6 MB), only from the page's origin, 5 uploads per minute per
  IP. Returns an unguessable 256-bit id.
- `GET /i/<id>/manifest.plist` and `GET /i/<id>/app.ipa`. The manifest's bundle ID, version and
  title are read from the uploaded IPA.
- Entries expire after 10 minutes, or 2 minutes after the first complete download (KV expiry, plus
  a check on every read). No accounts; file contents are never logged.

### Set it up (one time)

1. **GitHub Pages**: Settings → Pages → Source: **GitHub Actions** (already set for this repository).
2. **Cloudflare** (free plan, no card needed for Workers + KV):
   1. Create an account, then My Profile → API Tokens → Create Token → "Edit Cloudflare Workers" template.
   2. In this repository: Settings → Secrets and variables → Actions → **New repository secret**
      named `CLOUDFLARE_API_TOKEN`. If your login can see more than one Cloudflare account, also add
      `CLOUDFLARE_ACCOUNT_ID`. Never paste the token anywhere else.
3. Push to `main` (or re-run the "Build IPA" workflow). CI creates the KV namespace, deploys the
   Worker, and publishes the page with the Worker's URL in it.

> **This repository today:** the Worker was deployed by hand (wrangler OAuth) and there is no
> `CLOUDFLARE_API_TOKEN` secret, so CI skips the relay deploy and the page takes the relay URL from
> the `RELAY_URL` variable. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#8-infrastructure-and-external-services).

Without the Cloudflare secret everything else still works: the page signs and offers
"Download signed IPA", and says one-tap install is not set up.

If the Worker is deployed some other way, set the repository **variable** `RELAY_URL`
(e.g. `https://get-certsigner.<you>.workers.dev`) and the page will use it.

### Run it yourself

```bash
# Signer (needs Emscripten on PATH); builds OpenSSL once into .wasm-build/
bash web/wasm/build.sh
# Put an unsigned IPA at web/site/app/CertSigner.ipa, then:
bash web/tests/make-fixtures.sh            # throwaway test certificate + profiles
cd web && npm i --no-save playwright && npx playwright install chromium webkit
node --test tests/*.test.mjs               # WASM signing, relay, page in real browsers
node scripts/prepare-site.mjs https://your-relay.workers.dev   # -> web/dist

# Relay: deploy by hand (token only from the environment)
CLOUDFLARE_API_TOKEN=... PAGES_ORIGIN=https://<you>.github.io bash worker/deploy.sh
```

Fork notes: `ALLOWED_ORIGIN` in `worker/wrangler.toml` (set from `PAGES_ORIGIN` by the deploy
script) must be your Pages origin, and the source link in `web/site/index.html` points at this repository.

## Design language

"Futuristic, calm, alive": dark-first, layered glass, one signature gradient, motion that explains instead of decorates.

- **Colour**: near-black base with lifted depth layers and an airy light mode. Accents are solid colours or multi-colour blends (16 presets plus your own), with labels kept readable (4.5:1) on every gradient. An accent change cross-fades once over 0.35 s.
- **Surfaces**: layered cards with a soft highlight and hairline border over a living "aurora" background (one Canvas, 30 fps, holds still while scrolling, with a sheet up, in Low Power Mode and with Reduce Motion). Liquid Glass on iOS 26, with material fallbacks before (opaque with Reduce Transparency).
- **Type**: SF Rounded everywhere, tabular digits for numbers.
- **Shapes**: two only: 52 pt capsule buttons for actions, rows inside one rounded card for navigation and information. Every choice of 2–5 options is a sliding control.
- **Motion**: springs for taps, selection and layout; one shared delete animation; every movement becomes a short fade with Reduce Motion. Progress numbers never animate.

Tokens, components and rules: [`DESIGN.md`](DESIGN.md).

### What you'll see
- First launch: a one-time animated intro (tap or Skip), on the same colour as the launch screen.
- Home: staggered entrance, stat cards that count up once, a breathing "Needs attention" banner, an import zone with a marching gradient border that glows on drag-over, and a hero certificate card that tilts slightly as you scroll (iOS 17+).
- Library / Sources: rows on depth surfaces over the aurora, expiry rings with days left, gradient Install buttons, a shimmering gradient step bar while signing.
- Review & Sign: a stepper checklist (status icons joined by a rail, passed checks collapse, failing ones stay open).
- Certificates: the active card glows with a gradient border and a tinted sheet behind it.
- Settings: sliding glass theme control, live app-icon preview, animated storage bar.
- Feature regression checklist: [`docs/FEATURE_INVENTORY.md`](docs/FEATURE_INVENTORY.md).

## Architecture

```
Sources/
  App/         CertSignerApp (stores wired in init), RootView (tab shell, URL handling, root sheets)
  Models/      Certificate, ProvisioningProfile (+ ProfileParser), LibraryApp, Repository, SigningOptions (+ SigningMode), SigningStep, InstallMethod
  Services/    certificates, signing pipeline + queue (zsign), library and storage, install session + local server, sources, web hand-off
  Views/       Home, Library, Sources, Certificates, Install, Settings, Search
  Components/  design system: tokens, theme, aurora background, buttons, cards, sliding control, toasts, tab bar
  Resources/   Assets.xcassets (app icons)
Vendor/        zsign (MIT, patched) + Objective-C++ bridge + TLS helper — see Vendor/README.md
web/, worker/  the web installer and its install relay
```

Details (files, flows, CI, infrastructure): [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Current status and remaining work: [`docs/STATUS.md`](docs/STATUS.md).
Why things are built this way: [`docs/DECISIONS.md`](docs/DECISIONS.md).

Storage lives in the app's Documents folder: `Certificates/`, `Library/` (staged imports), `Signed/`, `Signing/queue.json`, `Sources/sources.json`, `Server/`, `Logs/`.

## Limits of a sideloaded app
- No UDID access (paste it in Settings).
- Confirming that iOS finished installing, and the alert-free app icon change, use private iOS APIs. They are checked before use and skipped when unavailable, in which case CertSigner reports up to the point iOS has the IPA, and the icon change shows the usual system alert.
- No special entitlements.
