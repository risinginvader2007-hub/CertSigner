# CertSigner architecture

Last checked against the code: 2026-11-13 (commit `59dcece`). Originally from the Hermes handover
(§2, §7, §9), verified and corrected. Design tokens and UI rules are in [`DESIGN.md`](../DESIGN.md).

## 1. Build and project

- **XcodeGen** (`project.yml`); no checked-in `.xcodeproj`. CI runs `xcodegen generate`.
  - Deployment target iOS 16.0, `SWIFT_VERSION` 5.0, `MARKETING_VERSION` 1.0.
  - Bundle IDs: app `com.certsigner.app`, tests `com.certsigner.app.tests`.
- **Swift packages:** `ZIPFoundation` (from 0.9.19, IPA zip/unzip) and `krzyzanowskim/OpenSSL`
  (from 3.3.0, OpenSSL 3 xcframework).
- **Targets:**
  - `ZSign`: static library from `Vendor/zsign` + `Vendor/ZSignBridge`, `ZSIGN_IOS=1`.
  - `CertSigner`: the app. `CertSignerTests`: unit tests from `Tests/`.
- **Schemes:** `CertSigner` (explicit, so adding tests didn't change the IPA build) and
  `SigningTests` (runs `CertSignerTests`).
- **Info.plist** (generated at `Support/Info.plist` from `project.yml` `info.properties`):
  `LSSupportsOpeningDocumentsInPlace: false`; document types and imported UTIs for ipa, p12 and
  mobileprovision; URL scheme **`certsigner`** (web certificate hand-off); alternate icons
  (asset sets `AppIcon`, `AppIcon-Sunset`, `AppIcon-Mint`, `AppIcon-Midnight`, plus `IconPreview-*`).

## 2. Source tree (`Sources/`)

### App
- `CertSignerApp.swift`: creates and injects the stores: `CertificateStore`, `LibraryStore`,
  `SignedAppsStore`, `SigningQueue`, `ServerCertificateStore`, `ToastCenter`, `TabRouter`,
  `ImportCoordinator`, `RepositoryStore`.
- `RootView.swift`: owns `ThemeStore` (accent, gradient, fade, on-accent colour into the
  environment); `.onOpenURL` for file URLs and `certsigner://import` (`importFromWeb`); the
  first-launch signature toast; root sheets (certificate import, review, install); the tab shell —
  `NativeTabShell` on iOS 26 (native `TabView`, Liquid Glass, Search tab), `LegacyTabShell` on
  iOS 16–25 (ZStack of all tabs + `FloatingTabBar` in a `safeAreaInset`).

### Components (design system)
- Tokens and theme: `DesignTokens.swift` (`Space`, `Radius` incl. `tile(side)` / `inner`,
  `TypeScale`, `SemanticColor`, `Border`, elevation, `Motion`); `Theme.swift` (legacy constants,
  `AccentOption`, `SettingsKeys`, environment keys, `PressableButtonStyle`); `ThemeStore.swift`
  (`ThemeStore`, `ThemeFade`, `RGBA` + WCAG helpers, `AppearanceCrossfade`, `PowerMonitor`,
  `AuroraClock`); `Accent.swift` (`Accent` model, 16 blends, `AccentLibrary` custom blends,
  `themeOnAccent`).
- Effects: `DesignSystem.swift` (`AuroraBackground`, delete motion `DeletePhase` / `DeleteMotion` /
  `.deleteExit` / `DeleteClipShape`, `glassSurface`, `sheetChrome()`, glows, scroll tilt,
  empty-state entrance); `BackgroundActivity.swift` (pauses the aurora while scrolling or with a
  sheet up); `GlassShine.swift` (`.glassShine()`, `ShinePressStyle` / `ShinePressEffect` with
  `TouchTracker`, `accentPillBackground`).
- Controls and views: `PrimaryButton.swift` (`AppButtonStyle`, `PrimaryButton`, `RowPressStyle`,
  `.buttonRow()`); `Components.swift` (SectionHeader, ListRow, IconTile, StatTile, ErrorState,
  LoadingSkeleton…); `SlidingSegmentedControl.swift`; `Card.swift`; `ToastView.swift`
  (`ToastCenter`, Undo); `FloatingTabBar.swift`; `AppIconStore.swift`; `AppIconView`,
  `DocumentPicker` (UIKit, not `fileImporter`), `Effects`, `EmptyStateView`, `IntroOverlay`,
  `ProgressRing`, `StatusBadge`.

### Models
`Certificate`, `InstallMethod` (also `InstallManifest`, palera URL builder,
`checkManifestService`, itms URL), `LibraryApp`, `ProvisioningProfile` + `ProfileParser`
(use `ProfileParser.parse(data:)`), `Repository`, `SigningOptions` (incl. `SigningMode`),
`SigningStep`.

### Services
- Certificates: `CertificateStore` — pairs in `Documents/Certificates/<uuid>/` as
  `certificate.p12` + `embedded.mobileprovision` with `index.json`; password in the Keychain under
  `p12-<uuid>`; `importCertificate`, `existing(p12Data:profileData:)`, `setActive`, `delete(id)`.
  Also `P12Inspector`, `DERCertificateParser`, `Keychain`.
- Signing: `SigningPipeline`, `AppBundlePatcher`, `ZSignService`, `SigningQueue`,
  `SigningValidator` (takes `mode:`), `IPAInspector`.
- Library and storage: `LibraryStore` (imported IPAs), `SignedAppsStore` (delete with Undo and
  pending-delete finalisation), `StorageService`, `CacheService`.
- Install: `InstallSession`, `LocalHTTPServer` (`NWListener`, HTTP/HTTPS, Range), `InstalledApps`
  (private LaunchServices, guarded), `ServerCertificateStore` (backloop.dev + custom certificates).
- Sources: `RepositoryStore` (store-owned refresh tasks, ETag / Last-Modified, icon disk cache,
  `reason(for:)`, `technicalDetail(for:)`), `FileDownloader` (up to 8 parallel byte-range
  connections for files ≥ 8 MB).
- Web hand-off: `WebImport` (parses `certsigner://import#…`), `LaunchSignature` ("Signed with X,
  expires Y" from the app's own embedded profile, once per signature).
- Other: `ImportCoordinator`, `AppLog`, `Haptics`. `Extensions/Formatting.swift`.

### Views
`Home/HomeView`; `Library/` (`LibraryView` + `LibraryFilterSheet`, `SignAppSheet`,
`SignedAppDetailView`, `SigningProgressView`); `Certificates/` (`CertificatesView`,
`CertificateDetailView`, `CertificatePickerSheet`, `ImportCertificateView`, `ProfileRawDataView`);
`Sources/` (`SourcesView`, `SourceAppDetailView`); `Settings/` (`SettingsView` incl.
`AccentPicker`, `CustomBlendSheet`, `AppIconPicker`; `InstallSettingsView`, `StorageDashboard`);
`Install/InstallSheet`; `Search/SearchView`.

### On-disk layout (app Documents)
`Certificates/`, `Library/` (staged imports), `Signed/`, `Signing/queue.json`,
`Sources/sources.json`, `Server/`, `Logs/`.

## 3. Signing flow (app)

1. Import creates a `LibraryApp`.
2. `SignAppSheet` builds `SigningOptions`, including the `SigningMode`.
3. `SigningValidator(mode:)` runs the pre-sign checks.
4. `SigningQueue` creates a persistent job; `SigningPipeline` runs it:
   unzip → `AppBundlePatcher` (name, version, bundle ID in Strict only, optional extension removal)
   → `ZSignService` → `ZSignBridge` → `zsign_sign_folder(app, p12, password, profile,
   entitlements=NULL)` (certificate from the p12, entitlements from the profile, nested
   frameworks / dylibs / extensions signed before the main binary) → zip.
5. Result goes to `SignedAppsStore`; the per-job log is saved and shareable ("Share signing log").

**Modes:** `.compatibility` (default) passes no bundle-ID override, keeps and signs every appex,
framework and dylib, and skips App-ID mismatch checks. `.strict` rewrites the bundle ID and blocks
on mismatch (the original behaviour).

## 4. Install flow (`InstallSession`, rewritten 2026-11-09)

- One app-wide session (`InstallSession.shared`). Re-showing the sheet never restarts the server;
  `begin()` runs in an unstructured `Task` so dismissing the sheet can't cancel it.
- Every `start` is fresh: stops the previous server, increments `generation` (stale server events
  ignored), new random port 4000–8000 (never the previous one), new UUID path token
  (`/<token>/manifest.plist`, `/<token>/app.ipa`, `/<token>/icon.png`), cancels all timers.
- Phases: `idle → preparing → waitingForPrompt → manifestSent → (stalled(.noManifest | .noPayload))
  → downloading(p) → installing → installed`, or `failed(msg)`. Phases advance **only on server
  events** (manifest request, IPA GET, bytes sent, payload complete). Lifecycle notifications are
  only logged.
- Timers (`InstallSession.swift` ~line 99): 15 s without a manifest request (Fully Local) →
  `stalled(.noManifest)`; 30 s without an IPA request → `stalled(.noPayload)`; 180 s overall →
  failed; transfer stalled 30 s → failed. While stalled the sheet offers **Reopen Prompt** and
  **Try Again**.
- After the transfer: polls `InstalledApps.info(bundleID)` every second, up to 120 times, to reach
  `.installed`.
- "Already installed" hint compares the installed app's `teamID` with the signing team ("will update
  in place" / "different team, delete first").
- Each request is logged (`LocalHTTPServer.Event.served`: method, short path with token hidden,
  status, bytes, time); "Share Install Log".

**Methods:**
- **Fully Local:** HTTPS on loopback with a trusted certificate for a hostname resolving to
  127.0.0.1 — backloop.dev's published certificate (`https://backloop.dev/pack.json`) or the user's
  own domain + certificate. Manifest and IPA both local.
- **Semi-Local:** manifest from `https://api.palera.in/genPlist` pointing at
  `http://127.0.0.1:<port>/…`; IPA over local HTTP. Checks the service first
  (`InstallManifest.checkManifestService()`); if down and `SettingsKeys.installPaleraFallback`
  (default on) → Fully Local.
- **Automatic:** prefers Fully Local when a valid certificate exists; re-checks backloop.dev at
  most every 12 h.

## 5. Theme and background

- `ThemeStore` has one `@Published state` (accent, gradient, onAccent, fade). `apply(Accent)`
  publishes once inside `withAnimation(.easeInOut(duration: 0.35))`, then once ~0.4 s later to
  clear `fade`. `ThemeFade` lets per-frame drawers interpolate gradient stops locally.
- `AuroraBackground`: one `Canvas` (`drawingGroup`), 4 radial-gradient blobs on 21–39 s
  figure-eight paths, ±12 % breathing, opacity 0.65–1; strength (dark 0.85 / light 0.36) ×
  (0.55 + 0.45 × intensity); `.plusLighter` in dark mode;
  `TimelineView(.animation(minimumInterval: 1/30))`. Drift is paused when the tab is hidden, the
  scene is inactive, the setting is off, Reduce Motion or Low Power Mode is on, or
  `BackgroundActivity.paused`; it still redraws colours during an accent fade. `AuroraClock` holds
  keyed pauses so the drift resumes without jumping.
- `AppearanceCrossfade`: System/Light/Dark switch = window snapshot fading out over 0.35 s.

## 6. Web installer ("Get CertSigner")

Live at https://risinginvader2007-hub.github.io/CertSigner/. User-facing description and setup are
in the README.

- **WASM signer:** `web/wasm/build.sh` builds OpenSSL 3.3.2 (sha256-pinned, `no-module`) with
  `Vendor/zsign/*.cpp` and `web/wasm/zsign_web.cpp` using Emscripten 3.1.74 → `web/site/wasm/
  zsign.{js,wasm}` (ES module, factory `createZsign`; gitignored, built in CI).
  - `zsign_web_sign(app, p12, pw, profile, bundleId)` → 0 / -1 (assets) / -2 (signing).
  - `zsign_web_inspect(p12, pw)` → JSON `{ok,name,notAfter,sha1}` or error `password` /
    `format` / `empty`.
- **`web/site/js/signer-core.js`** (shared by page, Worker and tests): XML + binary plist parsers,
  `parseProfile`, `validate` (p12 password, cert/profile expiry, cert SHA-1 in the profile's
  `DeveloperCertificates`, device-limited and revocation notes), `targetBundleID` (`*` keeps the ID;
  `TEAM.prefix.*` keeps it if it fits, else `prefix+certsigner`; explicit App ID uses it),
  `readIPAInfo`, `inspectP12`, `signIPA` (in memory, MEMFS + fflate 0.8.2 vendored in
  `web/site/js/vendor/`).
- **Page:** `index.html`, `style.css`, `js/app.js`; signing in `js/sign-worker.js` (module Web
  Worker). Strict CSP: `default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src
  'self' <relay>; style-src 'self'` — no inline styles or scripts. `web/scripts/prepare-site.mjs`
  fills `__RELAY_URL__` / `__RELAY_ORIGIN__` and writes `web/dist` + `app/build.json`; the unsigned
  IPA is copied same-origin to `app/CertSigner.ipa`.
- **Flow:** pick files → check and sign → upload only the signed IPA → **Install**
  (`itms-services://…`) → **Import Certificate into CertSigner** →
  `certsigner://import#<base64url JSON {v:1,name,p12,profile,password}>`. The app's
  `RootView.importFromWeb` parses it (`WebImport`), skips duplicates, imports and sets it active.
  The page keeps the certificate (`state.handoff`) in memory only until import, Start Over or
  `pagehide`; the Import button shows only on iOS. Requires an installed app at build 87 or later.
- **Relay** (`worker/src/index.js`, Cloudflare Worker `get-certsigner`, KV binding `STORE`, rate
  limiter `UPLOAD_LIMITER` 5 uploads / 60 s / IP):
  - `POST /upload`: origin must be in `ALLOWED_ORIGIN`; ≤ 25 MB (`MAX_BYTES`, KV value limit);
    ZIP with `Payload/*.app/Info.plist`; returns a 256-bit hex id.
  - `GET /i/<id>/manifest.plist` (metadata from the IPA), `GET /i/<id>/app.ipa` (Range).
  - Expiry: KV TTL 600 s; re-put with 120 s TTL after the first complete download; every read also
    checks the age.

## 7. CI (`.github/workflows/`)

- **`build.yml` ("Build IPA")** — push to `main`, or `workflow_dispatch` (input `web_only`):
  - `build` (macos-latest): xcodegen → unsigned Release `xcodebuild -sdk iphoneos` → zip `Payload/`
    → `CertSigner.ipa`. On `main` it replaces the `latest` release ("CertSigner (build
    <run_number>)").
  - `web` (ubuntu): IPA (from this build, or from the latest release when web-only) → WASM build
    (OpenSSL cached) → Playwright → fixtures → `node --test tests/*.test.mjs`. Artifacts
    `web-site`, `web-test-screenshots`.
  - `relay` (main only): `bash worker/deploy.sh`; no-op without `CLOUDFLARE_API_TOKEN`.
  - `pages` (main only): `prepare-site.mjs` with the relay job's URL or `vars.RELAY_URL`, then
    deploy-pages.
- **`signing-test.yml` ("Signing test")** — push to `main` / `ui-overhaul`, or dispatch:
  `.github/scripts/make-signing-fixtures.sh` (2-extension IPA, framework, dylib, CA-issued p12 with
  password `test`, explicit mismatching profile `ABCDE12345.com.other.app` vs app `com.husk.test`)
  → `xcodebuild test -scheme SigningTests` on a simulator with `TEST_RUNNER_CS_FIXTURES` → checks
  the signed IPA's PlugIns. The log is `tee`d and every result grepped.
- **Test suites (`Tests/`):** SigningPipeline, ThemeStore, Accent, AppearanceCrossfade,
  DeleteFlow, SourcesRefresh (network: apps.sidestore.io), StorageService, InstallServer,
  AppIconStore, Performance, LaunchSignature, WebImport. Web: `sign`, `worker`, `e2e` (Chromium +
  WebKit; asserts no request contains the p12, password or key).

## 8. Infrastructure and external services

- **GitHub:** public repo `risinginvader2007-hub/CertSigner`; Releases (`latest`), Pages (source:
  GitHub Actions), Actions. Repository **variable** `RELAY_URL =
  https://get-certsigner.risinginvader2007.workers.dev`. No repository secrets.
- **Cloudflare:** Worker `get-certsigner` on the `risinginvader2007` workers.dev subdomain, KV
  namespace `get-certsigner-store` (id `b99216883f054524a52bbb3527f44045`). Deployed by hand from
  the owner's PC with `wrangler login` (OAuth; token stored only on that PC). CI cannot redeploy it
  until the owner adds `CLOUDFLARE_API_TOKEN` (and possibly `CLOUDFLARE_ACCOUNT_ID`) as secrets.
  - Manual redeploy (OAuth): `cd worker && npx wrangler login`, copy `wrangler.toml` to
    `wrangler.deploy.toml`, set the KV id in it, `CI=1 npx wrangler deploy --config
    wrangler.deploy.toml`, delete the copy. With a token: `bash worker/deploy.sh`.
- **Third parties:** `api.palera.in` (Semi-Local manifests), backloop.dev (public 127.0.0.1
  hostname + certificate, run by a third party, can lapse), ZIPFoundation, OpenSSL.
- **Private Apple APIs (all guarded with `responds(to:)`):** `_setAlternateIconName:
  completionHandler:`, `LSApplicationProxy`, `LSApplicationWorkspace`.
- **Vendored:** zsign (MIT, commit `9299685bab7ef99827e06e5dfda93af747386590`, patches in
  `Vendor/README.md`), fflate 0.8.2 (MIT).
- **Web toolchain:** Emscripten 3.1.74 (`mymindstorm/setup-emsdk@v14`), OpenSSL 3.3.2 source,
  Node 22, Playwright 1.65.0 (CI, `--no-save`), Wrangler 4.

## 9. Diagnostics without a Mac

Push a throwaway `diag/<name>` branch with a `diag-screens.yml` workflow that builds for the
simulator (largest iOS 26 Pro Max), launches with env hooks (`SIMCTL_CHILD_CS_TAB`, `CS_SHEET`,
`CS_SCROLL`) and takes `simctl io screenshot`; download the artifact, then delete the branch. The
hooks were diag-only and are **not** on `main` (they would have to be re-added on the diag branch).
Earlier diag branches (`diag/screens*`, `diag/profile`) were deleted, never merged.
