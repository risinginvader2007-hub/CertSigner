# CertSigner

An on-device iOS signer for **your own certificates, your own devices and IPAs you already have**.
Import an IPA from Files, review it, sign it on the phone with zsign, and install it with the system install prompt.
SwiftUI (iOS 16+), built by GitHub Actions — no Mac needed.

## Get the app

**Direct link (always the newest successful build):**
https://github.com/risinginvader2007-hub/CertSigner/releases/latest/download/CertSigner.ipa

Open it in Safari on your iPhone, then share the file to FlareStore (or any signer) to install CertSigner itself.

### From GitHub Actions
1. Push to `main`, or open **Actions → Build IPA → Run workflow**.
2. Wait for the green tick (about 2–4 minutes).
3. Every green build on `main` also replaces the **latest** release, so the direct link above updates automatically.
4. Or open the run, scroll to **Artifacts**, download **CertSigner-ipa** and unzip it to get `CertSigner.ipa`.

## Using CertSigner

### 1. Add a certificate (Settings → Certificates, or the Home card)
- Tap **Add Certificate**, pick your `.p12`, your `.mobileprovision`, enter a nickname and the `.p12` password.
- The password is checked straight away and stored only in the iOS Keychain.
- Certificate details: team, profile type, App ID, devices, entitlements, expiry, and whether the `.p12` is in the profile.
- **Switch** the active certificate from Home or Settings. Sharing a `.p12` / `.mobileprovision` to CertSigner opens the import sheet too.
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
- **Install when done** starts the install prompt automatically after signing.

### 4. Library
- **Signing**: live jobs with step progress (Unpacking → Patching → Signing → Packaging) and a progress ring. Tap a job for the live log. Failed jobs show the reason with **Retry** / **Remove**. Jobs survive relaunch (an interrupted job is marked failed so you can retry).
- **Signed Apps**: icon, version, certificate used, status badge (valid / expiring / expired) and expiry countdown, with **Install**, **Re-sign** (with the active certificate, replaces the old copy) and **Share**. Swipe left to delete, right to re-sign. Search, sort (date, name, expiry) and filter (status, certificate).
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
  - Semi-Local serves the IPA locally and gets only the small manifest from `api.palera.in` (needs internet).

#### Using your own domain for Fully Local
1. Add a DNS **A record** such as `install.example.com → 127.0.0.1` (Cloudflare: proxy off).
2. Get a certificate with a **DNS-01** challenge, e.g. `certbot certonly --manual --preferred-challenges dns -d install.example.com`.
3. Put `fullchain.pem` and `privkey.pem` (unencrypted) in Files, then Settings → Install → **Add My Own Certificate**.
4. Renew before it expires (Let's Encrypt: 90 days) and import again.

### 7. Settings
Certificates, signing defaults (remove extensions, keep bundle ID), install after signing, delete original IPA after signing, install method, UDID, appearance (system / light / dark), accent colour, **app icon** (Ocean, Sunset, Mint, Midnight), storage usage with Clear Cache and Remove Unused Imports, **Export Log File**, and About.

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

- **Colour**: near-black base with lifted depth layers (`Theme.background`, `surface`, `surfaceRaised`) and an airy light mode. The default **Aurora** accent is a deep indigo → electric violet → cyan gradient (`Theme.signature`); every accent in Settings has its own gradient (`AccentOption.gradient`, exposed as the `themeGradient` environment value). Semantic success / warning / danger colours are tuned to glow slightly on dark surfaces.
- **Surfaces**: cards use `CardSurface`: depth fill, soft top inner highlight, gradient hairline border, gentle shadow (stronger borders with Increase Contrast). Screens sit on `AuroraBackground`: three large radial gradients drifting slowly (no blur filters; static with Reduce Motion; paused on hidden tabs). Liquid Glass (`glassEffect`) is used on iOS 26, with material + highlight + hairline fallbacks (opaque with Reduce Transparency).
- **Type**: SF Rounded everywhere, tabular digits for numbers, tight tracking on large numbers and titles.
- **Shape and spacing**: 4/8 pt grid (`Space.x1…x8`), one continuous-corner scale (`Radius.xs 8, sm 12, md 16, lg 22, xl 28`), 44 pt minimum touch targets on custom controls.
- **Icons**: SF Symbols with symbol effects on iOS 17+ (`symbolBounce`, `symbolPulse`, `symbolVariableColor`, `symbolReplace`), all no-ops with Reduce Motion or on iOS 16.
- **Controls**: glowing gradient primary buttons with a lit edge and success/error morph, sliding glass segmented control, focus-glow text fields, gradient progress rings/bars, expiry rings, swipe-to-dismiss toasts, consistent sheet chrome (grabber, large corners).

### Motion tokens (`Motion` in Theme.swift)
| Token | Curve | Used for |
|---|---|---|
| `snappy` | spring 0.28 s, damping 0.82 | taps, toggles, selection pills, segmented control |
| `smooth` | spring 0.45 s, damping 0.86 | layout changes, cards, staggered entrances (`Theme.spring`) |
| `bouncy` | spring 0.5 s, damping 0.66 | confirmations, badges, icons popping in (`Theme.bouncy`) |
| `gentle` | ease-in-out 0.6 s | ambient glows, breathing |
| `quick` / `standard` / `slow` | 0.18 / 0.3 / 0.6 s | fades and timed transitions |
| `stagger` | 0.05 s | delay between items in staggered lists |

`Motion.adaptive(_:reduceMotion:)` turns any of them into a short cross-fade when Reduce Motion is on. Progress numbers never animate (they update in place).

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
  App/         CertSignerApp (stores wired in init), RootView (floating tab bar shell)
  Models/      Certificate, ProvisioningProfile, LibraryApp, Repository (+ parser), SigningOptions/SignedApp, SigningStep, InstallMethod
  Services/    CertificateStore, LibraryStore (staged imports), SignedAppsStore, RepositoryStore (sources + downloads), SigningQueue, SigningPipeline (worker),
               AppBundlePatcher, SigningValidator, IPAInspector, ZSignService, InstallSession, LocalHTTPServer,
               ServerCertificateStore, Keychain, P12Inspector, DERCertificateParser, AppLog, StorageService
  Views/       Home, Library, Sources, Certificates, Install, Settings, Search
  Components/  Theme (tokens + Motion), DesignSystem (glass, aurora, glow, symbol effects, controls), IntroOverlay, FloatingTabBar, PrimaryButton, Card, StatusBadge, ProgressRing/Bar, EmptyStateView,
               AppIconView, ToastView, DocumentPicker, Effects (shimmer, shake, checkmark draw-in, zoom transition)
  Resources/   Assets.xcassets (original app icons)
Vendor/        zsign (MIT, patched for iOS) + Objective-C++ bridge + TLS helper — see Vendor/README.md
```

Storage lives in the app's Documents folder: `Certificates/`, `Library/` (staged imports), `Signed/`, `Signing/queue.json`, `Sources/sources.json`, `Server/`, `Logs/`.

## Limits of a sideloaded app
- No UDID access (paste it in Settings).
- CertSigner can't see whether iOS finished installing; it reports up to the point iOS has the IPA.
- No private APIs or special entitlements.
