# CertSigner — Development Handover (from Hermes Agent)

> **Archived historical document.** Preserved as written on 2026-11-10, except that the owner's
> email address and the Cloudflare account ID were redacted before it was committed (the repository
> is public). It was moved here from the repo root on 2026-11-13. Facts in it may be out of date;
> the current state lives in [`docs/STATUS.md`](../STATUS.md), and its content is distilled into
> [`CLAUDE.md`](../../CLAUDE.md), [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) and
> [`docs/DECISIONS.md`](../DECISIONS.md). Corrections found in the 2026-11-13 audit are listed in
> `docs/STATUS.md` under "Corrections to the Hermes handover".

Written 2026-11-10 at the end of the Hermes sessions. It is meant to be the main history reference
for Claude Code. Everything here comes from the actual sessions and the repository. Anything I
can't confirm is marked **(unverified)** or listed in §11.

- **Repo:** `C:\Users\Anas\Downloads\certsigner`, GitHub `risinginvader2007-hub/CertSigner`, public.
- **Branches:**
  - `main`: what CI publishes.
  - `ui-overhaul`: the working branch. Same commit as `main` when this was written: `59dcece`, "WebImport tests".
- **Tags:**
  - `latest`: moved by CI to each published release.
  - `pre-ui-overhaul`: commit `41316d2`, the state before the UI overhaul. A rollback point.
- **Latest published release:** "CertSigner (build 87)". It's an unsigned IPA on the `latest` release.
- **Live web installer:** https://risinginvader2007-hub.github.io/CertSigner/
- **Live install relay:** https://get-certsigner.risinginvader2007.workers.dev
- **This file is not committed.** It was written into the repo root and left uncommitted on purpose.

Other repo docs worth reading:
- `README.md`: user guide, architecture, and a full "Web installer" section.
- `DESIGN.md`: design tokens, components, rules and performance rules.
- `docs/FEATURE_INVENTORY.md`: feature list and iPhone checklist. It was last updated during the early UI stages, so it may be stale.
- `Vendor/README.md`: the zsign source commit and every local patch.

---

## 1. Project overview

**CertSigner** is a SwiftUI app for iOS 16 and later that signs IPAs on the iPhone. It's sideloaded,
not distributed through the App Store. Users bring their own Apple signing certificate (`.p12` plus
password) and a provisioning profile (`.mobileprovision`). The app re-signs `.ipa` files with them
using a vendored copy of **zsign**, then installs the result through iOS's `itms-services` flow,
served from a local web server running inside the app.

**Intended users:** sideloaders who have their own developer or enterprise certificate, the same
audience as FlareStore, Feather, ESign and similar apps. The owner (GitHub `risinginvader2007-hub`,
email [redacted]) is the only developer. He tests every build on a real iPhone,
and he has an iPhone 16 Pro Max (see §10).

**Main features (all implemented):**
- **Certificates:** import a `.p12`, its password and a `.mobileprovision` as a pair.
  - The password is stored in the Keychain.
  - Detail screen showing expiry, team, devices, entitlements, and the "Raw Profile Data" (the application-identifier and where it came from).
  - Choose the active certificate from a bottom sheet (`CertificatePickerSheet`).
  - Check whether this device's UDID is in the profile. The UDID has to be typed or pasted in Settings, because sideloaded apps can't read it.
- **Import IPAs:** from the Files picker, from Share / "Open in", or by drag and drop on Home. Imported apps go into the Library.
- **Review & Sign sheet (`SignAppSheet`):**
  - Pre-sign checklist.
  - Options: name, bundle ID, version, keep the original bundle ID, remove extensions, and a per-app signing mode.
  - Shows the certificate and its App ID.
- **Signing modes:** `.compatibility` (the default) and `.strict`. See §5.
- **Signing queue:** persistent jobs with progress, logs and retry. A detailed signing log can be shared with "Share signing log".
- **Library:** signed apps with search, Sort & Filter (a sheet), install, re-sign, share, and delete with Undo.
- **Install:** a local HTTP or HTTPS server inside the app serves the manifest and the IPA to iOS. There are three methods: Automatic, Fully Local and Semi-Local. See §2.4.
- **Sources:** AltStore-style repositories. You can browse apps and tap GET to download, sign and install. Downloads use up to 8 parallel byte-range connections, but only for files of 8 MB or more.
- **Search tab:** on iOS 26 only, as the native Liquid Glass search tab.
- **Settings:**
  - Signing defaults and the signing mode picker.
  - Install method and server certificates (backloop.dev, or your own domain's certificate).
  - This Device (UDID).
  - Appearance: System / Light / Dark, accent colours (solid, blended and custom blends), the background animation toggle, and alternate app icons.
  - Storage dashboard.
  - Diagnostics (log export and clear).
  - About.
- **Visual system:**
  - Animated "aurora" background.
  - Glass shine on buttons.
  - Sliding selection controls.
  - One shared delete animation.
  - Toasts with Undo.
  - Liquid Glass on iOS 26.
  - Reduce Motion respected everywhere.
- **Web installer, "Get CertSigner":** a GitHub Pages site that signs CertSigner itself inside Safari, using zsign compiled to WebAssembly. A Cloudflare Worker relay serves the signed app so it can install. The page then hands the certificate to the installed app over the `certsigner://` URL scheme. See §2.6.

---

## 2. Architecture

### 2.1 Project layout and build

- **Project generation:** XcodeGen (`project.yml`). There is no checked-in `.xcodeproj`. CI runs `xcodegen generate`.
  - Deployment target iOS 16.0, `SWIFT_VERSION` 5.0, `MARKETING_VERSION` 1.0.
  - The bundle ID is `com.certsigner.app`; the test target's is `com.certsigner.app.tests`.
- **Swift packages:**
  - `ZIPFoundation` (from 0.9.19), used for IPA zip and unzip.
  - `OpenSSL` (`krzyzanowskim/OpenSSL`, from 3.3.0).
- **Targets:**
  - `ZSign`: a static library built from `Vendor/zsign` and `Vendor/ZSignBridge`, with `GCC_PREPROCESSOR_DEFINITIONS ZSIGN_IOS=1`.
  - `CertSigner`: the app.
  - `CertSignerTests`: a unit-test bundle with sources in `Tests/`.
- **Schemes:**
  - `CertSigner`: explicit, so adding tests didn't change the IPA build.
  - `SigningTests`: runs `CertSignerTests`.
- **Info.plist:** generated at `Support/Info.plist` from `project.yml` `info.properties`.
  - `LSSupportsOpeningDocumentsInPlace: false`.
  - Document types for ipa, p12 and mobileprovision.
  - Imported UTIs.
  - `CFBundleURLTypes` with the scheme **`certsigner`**, added for the web import.
  - Alternate icons. The Info.plist has them; the asset sets are AppIcon, AppIcon-Sunset, AppIcon-Mint and AppIcon-Midnight, plus `IconPreview-*` imagesets.

### 2.2 Source tree (`Sources/`)

- **`App/`**
  - **`CertSignerApp.swift`:** creates the stores and injects them as environment objects:
    - `CertificateStore`, `LibraryStore`, `SignedAppsStore`, `SigningQueue`, `ServerCertificateStore`
    - `ToastCenter`, `TabRouter`, `ImportCoordinator`, `RepositoryStore`
  - **`RootView.swift`:**
    - `ThemeStore` (`@StateObject`). Its accent, gradient, fade and on-accent colour go into the environment.
    - `.onOpenURL`: handles file URLs and `certsigner://import`.
    - The first-launch signature toast.
    - Sheets for certificate import, review and install.
    - The tab shell. `NativeTabShell` is used on iOS 26 (native `TabView`, Liquid Glass, Search tab). `LegacyTabShell` is used on iOS 16–25: a ZStack of all tabs plus the `FloatingTabBar` in a `safeAreaInset`.
- **`Components/`:** design system and shared UI.
  - **Tokens and theme:**
    - `DesignTokens.swift`: `Space`, `Radius` (including `tile(side)` and `inner`), `TypeScale`, `SemanticColor`, `Border`, elevation and `Motion`.
    - `Theme.swift`: legacy theme constants, `AccentOption`, `SettingsKeys`, environment keys, `PressableButtonStyle`.
    - `ThemeStore.swift`: `ThemeStore`, `ThemeFade`, `RGBA` with WCAG helpers, `AppearanceCrossfade`, `PowerMonitor`, `AuroraClock`.
    - `Accent.swift`: the `Accent` model, the 16 blends, `AccentLibrary` (custom blends) and the `themeOnAccent` environment key.
  - **Animation and effects:**
    - `DesignSystem.swift`:
      - `AuroraBackground`: a single Canvas.
      - Delete motion: `DeletePhase`, `DeleteMotion`, `.deleteExit`, `DeleteClipShape`.
      - `glassSurface` (ConcentricRectangle on iOS 26) and `sheetChrome()`.
      - Ambient glow, focus glow, scroll tilt and the empty-state entrance.
    - `BackgroundActivity.swift`: pauses the aurora while scrolling (a passive window gesture recognizer) or while a sheet is open.
    - `GlassShine.swift`:
      - `.glassShine()`: a lit edge plus a sweep.
      - `ShinePressStyle` and `ShinePressEffect`: a press flash that follows the touch, using `TouchTracker`.
      - `accentPillBackground`.
  - **Buttons:** `PrimaryButton.swift` holds:
    - `AppButtonStyle`: a 52 pt capsule in primary, secondary or destructive, or a compact 36 pt version.
    - `PrimaryButton`, `RowPressStyle` and `.buttonRow()`.
  - **Shared views:**
    - `Components.swift`: SectionHeader, ListRow, IconTile, StatTile, ErrorState, LoadingSkeleton and others.
    - `SlidingSegmentedControl.swift`: generic, with one `matchedGeometryEffect` highlight, scrubbing, VoiceOver and a 48 pt height.
    - `Card.swift`: `Card`, `CardSection`, `CardSurface`, `InfoRow`.
    - `ToastView.swift`: `ToastCenter` with Undo support. Plain toasts last 2.5 s and Undo toasts 5 s.
    - `FloatingTabBar.swift`: the custom tab bar for iOS 16–25, plus glass helpers.
    - `AppIconStore.swift`: alternate-icon selection, optimistic, with the private alert-less API.
    - Also: `AppIconView`, `DocumentPicker` (UIKit, not `fileImporter`), `Effects`, `EmptyStateView`, `IntroOverlay` (a one-time intro), `ProgressRing`, `StatusBadge`.
- **`Models/`:**
  - `Certificate`
  - `InstallMethod`: also holds `InstallManifest`, the palera URL builder, `checkManifestService` and the itms URL.
  - `LibraryApp`
  - `ProvisioningProfile` and `ProfileParser`. Use `ProfileParser.parse(data:)`; `ProvisioningProfile.parse` does not exist.
  - `Repository`
  - `SigningOptions`: includes `SigningMode`.
  - `SigningStep`
- **`Services/`:**
  - **Certificates:**
    - `CertificateStore`: stores pairs in `Documents/Certificates/<uuid>/` as `certificate.p12` and `embedded.mobileprovision`, with an `index.json`. The password goes in the Keychain under `p12-<uuid>`. Provides `importCertificate`, `existing(p12Data:profileData:)`, `setActive` and `delete(id)`.
    - `P12Inspector`, `DERCertificateParser`, `Keychain`.
  - **Signing:**
    - `SigningPipeline`: unpack, patch with `AppBundlePatcher`, run zsign through `ZSignService`, then zip.
    - `SigningQueue`, `SigningValidator` (takes `mode:`), `IPAInspector`.
  - **Library and storage:** `LibraryStore` (imported IPAs), `SignedAppsStore` (signed apps; delete with Undo and pending-delete finalisation), `StorageService`, `CacheService`.
  - **Install:**
    - `InstallSession`: the install state machine. See §2.4.
    - `LocalHTTPServer`: built on `NWListener`, HTTP or HTTPS, with Range support.
    - `InstalledApps`: LaunchServices queries through the guarded ObjC runtime.
    - `ServerCertificateStore`: backloop.dev and custom server certificates.
  - **Sources:** `RepositoryStore` (store-owned refresh tasks, ETag and Last-Modified, an icon disk cache, `reason(for:)`, `technicalDetail(for:)`) and `FileDownloader`.
  - **Web hand-off:** `WebImport` parses `certsigner://import#…`. `LaunchSignature` produces "Signed with X, expires Y" from the app's own embedded profile, once per signature.
  - **Other:** `ImportCoordinator` (incoming files and import routing), `AppLog`, `Haptics`.
- **`Views/`:**
  - `Home/HomeView`
  - `Library/`: `LibraryView` (includes `LibraryFilterSheet`), `SignAppSheet`, `SignedAppDetailView`, `SigningProgressView`
  - `Certificates/`: `CertificatesView`, `CertificateDetailView`, `CertificatePickerSheet`, `ImportCertificateView`, `ProfileRawDataView`
  - `Sources/`: `SourcesView`, `SourceAppDetailView`
  - `Settings/`: `SettingsView` (includes `AccentPicker`, `CustomBlendSheet`, `AppIconPicker`), `InstallSettingsView`, `StorageDashboard`
  - `Install/InstallSheet`
  - `Search/SearchView`
- **`Vendor/` (repo root):**
  - `zsign/`: from zhlynn/zsign at commit `9299685…`, MIT licence. The patches are listed in `Vendor/README.md`:
    1. `<OpenSSL/...>` include casing.
    2. No `popen(csreq)` when `ZSIGN_IOS` is defined.
    3. `ZLog::SetLogCallback`.
    4. Under `__EMSCRIPTEN__` only, `MapFile`/`UnmapFile` read into a buffer and write it back.
  - `ZSignBridge/`: `zsign_api.{h,cpp}` (the C entry point `zsign_sign_folder`), `ZSignBridge.{h,mm}`, `CSTLSUtil.{h,mm}`.

### 2.3 Signing flow (in the app)

1. The import creates a `LibraryApp`.
2. `SignAppSheet` builds `SigningOptions`, including the mode.
3. `SigningValidator(mode:)` runs the pre-flight checks.
4. `SigningQueue` creates a job and `SigningPipeline` runs it:
   1. Unzip.
   2. `AppBundlePatcher`: name, version, bundle ID (Strict only), and removing extensions if asked.
   3. `ZSignService` → `ZSignBridge` → `zsign_sign_folder(app, p12, password, profile, entitlements=NULL)`.
      - The certificate is taken from the p12. Nested frameworks, dylibs and extensions are signed before the main binary.
      - Entitlements come from the profile.
   4. Zip.
5. The result goes to `SignedAppsStore`. A per-job signing log is saved (`savedLog`) and can be shared.

### 2.4 Install flow (`InstallSession`, rewritten 2026-11-09)

- **One app-wide session** (`InstallSession.shared`). Re-showing the sheet never restarts the server. The sheet's `begin()` runs inside an unstructured `Task`, so dismissing the sheet can't cancel it.
- **Every `start` is completely fresh:**
  - Stops the previous server.
  - Increments `generation`, and events from older servers are ignored.
  - Picks a new random port (4000–8000, avoiding the last one) and a new UUID path token: `/<token>/manifest.plist`, `/<token>/app.ipa`, `/<token>/icon.png`.
  - Cancels all timers.
- **Phases:** `idle → preparing → waitingForPrompt → manifestSent → (stalled(.noManifest | .noPayload)) → downloading(p) → installing → installed`, or `failed(msg)` at any point.
  - Phases advance only on **server events**: a manifest request, an IPA GET, bytes sent, or payload completed.
  - App lifecycle notifications are logged only. They used to drive the phases, which caused the CapCut "stuck at Confirm on the iOS prompt" bug.
- **Timers:**
  - 15 s with no manifest request (Fully Local) → `stalled(.noManifest)`.
  - 30 s with no IPA request → `stalled(.noPayload)`.
  - 180 s overall → failed.
  - Transfer stalled for 30 s → failed.
  - While stalled, the sheet shows **Reopen Prompt** (the same itms URL) and **Try Again**.
- **After the transfer:** polls `InstalledApps.info(bundleID)` every second for up to 2 minutes. It's private LaunchServices: `LSApplicationProxy.applicationProxyForIdentifier:` and `LSApplicationWorkspace applicationIsInstalled:`, both guarded with `responds(to:)`. It reaches `.installed` when this succeeds.
- **"Already installed" hint:** checks the installed app's `teamID` against the signing certificate's team. It says either "will update in place" or "different team, delete first".
- **Install methods:**
  - **Fully Local:** HTTPS on the loopback using a trusted certificate for a hostname that resolves to 127.0.0.1. That's backloop.dev's public certificate, or the user's own domain and certificate. The manifest and the IPA are both served locally.
  - **Semi-Local:** the manifest comes from `api.palera.in`, which builds a manifest pointing at `http://127.0.0.1:<port>/…`. The IPA is served over plain HTTP locally.
    - It first checks the service with `InstallManifest.checkManifestService()`.
    - If the service is down and `SettingsKeys.installPaleraFallback` is on (the default), it falls back to Fully Local.
  - **Automatic:** prefers Fully Local when a valid certificate exists, and re-checks backloop.dev at most every 12 h.
- **Log:** `LocalHTTPServer.Event.served` logs each request as method, short path (token hidden), status, bytes and time. The log is shareable ("Share Install Log").

### 2.5 Theme, background and performance

- **`ThemeStore`:**
  - One `@Published state` holding accent, gradient, onAccent and fade.
  - `apply(Accent)` publishes **once**, inside `withAnimation(.easeInOut(0.35))`, then once more about 0.4 s later to clear `fade`.
  - Before 2026-11-09 it published on every CADisplayLink frame, about 8 times per change in tests. **Don't go back to that.**
  - `ThemeFade` lets per-frame drawers interpolate gradient stops locally.
- **`AuroraBackground`:**
  - One `Canvas` with `drawingGroup`: 4 radial-gradient blobs on 21–39 s figure-eight paths.
  - Breathing: ±12% size, with opacity between 0.65 and 1.
  - Strength is (dark 0.85 / light 0.36) × (0.55 + 0.45 × intensity). Dark mode uses the `.plusLighter` blend.
  - `TimelineView(.animation(minimumInterval: 1/30))`.
  - **Paused (static) when:** the tab is hidden (`\.auroraActive`), the scene isn't active, the setting is off, Reduce Motion is on, Low Power Mode is on, or `BackgroundActivity.paused` (scrolling or a sheet open).
  - **Accent changes:** it still redraws during the fade.
  - **`AuroraClock`:** holds keyed pauses, so the drift resumes without jumping.
- **`AppearanceCrossfade`:** System/Light/Dark switches take a snapshot view of the window, change the appearance, then fade the snapshot out over 0.35 s. This avoids any white or black flash.

### 2.6 Web installer ("Get CertSigner")

Everything lives under `web/` and `worker/`; the README has a full section.

- **WASM signer:**
  - `web/wasm/build.sh` compiles OpenSSL 3.3.2 (sha256 pinned, `no-module` so the legacy provider is built in) together with `Vendor/zsign/*.cpp` and `web/wasm/zsign_web.cpp`, using Emscripten 3.1.74.
  - Output: `web/site/wasm/zsign.{js,wasm}`, as an ES module with factory `createZsign`. It's ignored by git and built in CI.
  - `zsign_web.cpp` exports:
    - `zsign_web_sign(app, p12, pw, profile, bundleId)`: returns 0, -1 (assets couldn't be loaded) or -2 (signing failed).
    - `zsign_web_inspect(p12, pw)`: returns JSON with `{ok,name,notAfter,sha1}`, or an error of `password`, `format` or `empty`.
- **`web/site/js/signer-core.js`:** the shared core used by the page, the Worker and the tests.
  - XML and binary plist parsers.
  - `parseProfile`.
  - `validate`: checks the p12 password, certificate and profile expiry, and that the certificate's SHA-1 is in the profile's `DeveloperCertificates`. It also adds a device-limited note and a revocation note.
  - `targetBundleID`: `*` keeps the ID; `TEAM.prefix.*` keeps it if it fits, otherwise uses `prefix+certsigner`; an explicit App ID uses that App ID.
  - `readIPAInfo`, `inspectP12`, `signIPA`: in memory, using MEMFS and fflate.
  - `web/site/js/vendor/fflate.js`: fflate 0.8.2, MIT, vendored.
- **Page:**
  - `index.html`, `style.css` and `js/app.js`, with signing in `js/sign-worker.js` (a module Web Worker).
  - Strict CSP: `default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self' <relay>; style-src 'self'`. No inline styles or scripts.
  - `__RELAY_URL__` and `__RELAY_ORIGIN__` placeholders are filled in by `web/scripts/prepare-site.mjs`, which writes `web/dist` and `app/build.json`.
  - The unsigned IPA is copied same-origin to `app/CertSigner.ipa`.
- **Flow:** files → check and sign → upload only the signed IPA to the relay → **Install** (`itms-services://…`) → **Import Certificate into CertSigner** → `certsigner://import#<base64url JSON {v:1,name,p12,profile,password}>`.
  - The app's `RootView.importFromWeb` parses it, avoids duplicates, imports, and sets the certificate active.
  - The page keeps the certificate data (`state.handoff`) in memory only until import, Start Over, or `pagehide`.
  - The Import button only shows on iOS.
- **Relay (`worker/src/index.js`):** a Cloudflare Worker with the KV binding `STORE` and the rate limiter `UPLOAD_LIMITER` (5 uploads per 60 s per IP).
  - `POST /upload`:
    - Origin must be in `ALLOWED_ORIGIN` (`https://risinginvader2007-hub.github.io`).
    - At most 25 MB, because of KV's value limit. The original spec said 50 MB, so this was knowingly lowered.
    - Must be a ZIP with `Payload/*.app/Info.plist`.
    - Returns a 256-bit hex id.
  - `GET /i/<id>/manifest.plist`: metadata is read from the IPA.
  - `GET /i/<id>/app.ipa`: supports Range.
  - **Expiry:** KV TTL of 600 s. After the first complete download it's re-put with a 120 s TTL. Every read also checks the age and deletes expired entries.
- **Deployed resources (Cloudflare account [owner's email, redacted], account id [redacted]):**
  - workers.dev subdomain `risinginvader2007`, registered through the API.
  - Worker `get-certsigner`.
  - KV namespace `get-certsigner-store` (`b99216883f054524a52bbb3527f44045`).
  - Deployed from this PC with `wrangler login` (OAuth). The token lives in `%APPDATA%\xdg.config\.wrangler\config\default.toml` on this PC only.
- **GitHub configuration:**
  - Pages source: GitHub Actions (enabled through the API).
  - Repository **variable** `RELAY_URL=https://get-certsigner.risinginvader2007.workers.dev`.
  - **No** `CLOUDFLARE_API_TOKEN` secret. So CI's `relay` job prints "not set: nothing deployed" and succeeds, and the page gets the relay URL from the variable.

---

## 3. Development history (chronological; commits on `main`)

**Stage work, 2026-11-07/08 (before Hermes took over fully; details mostly from commit messages):**
- Starter project and CI IPA build; publishing to the `latest` release.
- Stage 2: design system, tab bar, certificate manager and library UI.
- File-picker fixes. Replaced `fileImporter` with a UIKit `DocumentPicker` and registered the document types.
- Stage 4a: vendored zsign as a static C++ target with an ObjC++ bridge and OpenSSL.
- Stage 4b: real IPA import and the signing pipeline.
- Stage 5: the loopback install server, itms-services, backloop.dev and custom server certificates.
- Polish A–E: floating tab bar, Home dashboard, persistent signing queue, review sheet, settings, SF Rounded.
- Native Liquid Glass TabView with a Search tab on iOS 26.

**Sources and downloads:**
- Sources: AltStore-style repos, GET (download, sign, install), build 17.
- Download diagnostics for every hop.
- Parallel byte-range downloads: 8 connections, files of 8 MB or more.

**Install:**
- Detailed install logging.
- One app-wide `InstallSession` (`f1b5a8a`).
- `41316d2`: fixed a misplaced `@discardableResult`.

**UI overhaul, stages 1–6 (build 36):**
- Motion tokens, glass tab bar, aurora, depth rows, a stepper checklist, and a launch intro.

**Builds 38–55:**
- **Build 38:** certificate card layout, faint dividers, instant delete, install sheet auto-close toggle.
- **Build 40:** fixed a black screen on certificate details. It came from a missing navigationDestination; fixed with view-based NavigationLinks and Home's `HomeRoute`.
- **Build 42:** "Raw Profile Data". It confirmed the app reads `Entitlements["application-identifier"]` and never Name or AppIDName. Also added `isWildcard`. A `diag/profile` probe passed 7/7 cases.
- **Build 45:** signing modes (Compatibility and Strict), the detailed signing log, "Share signing log", and the first XCTest target with a signing fixture script.
- **Build 48:**
  - Living background.
  - Glass shine.
  - Touch-following press flash.
  - A 0.6 s shared accent fade, later shortened to 0.35 s.
  - Background animation toggle.
  - Brightness raised twice after the user said the colours were "very faint".
- **Build 53:**
  - Sources "cancelled" bug: refreshes are now owned by `RepositoryStore`. Added a 20 s timeout, one retry after 1.5 s, cancellation never shown as an error, ETag and Last-Modified, and Retry.
  - The certificate picker became a bottom sheet instead of a `Menu`.
- **Build 55:**
  - Delete animation redesign: press to 0.96 scale, slide left and fade with no blur, then collapse with a spring.
  - Detail screen: pop back first, then animate the row.
  - Undo toast: Undo for signed apps only.

**Four-part design pass, 2026-11-09 (build 51 per my report then; build numbers on `main` are not strictly sequential with what I reported, see §11):**
1. **Design system:**
   - Tokens; about 205 literal values replaced.
   - `Components.swift`.
   - `AppearanceCrossfade`.
2. **Sliding selection:**
   - `SlidingSegmentedControl` in Settings (appearance, signing mode, install method) and in Review.
   - The Library Sort & Filter sheet.
   - Sliding swatch rings.
   - The legacy tab bar's sliding pill.
3. **Storage dashboard:**
   - Recursive on-disk sizes, computed off the main thread.
   - A ring chart.
   - Five categories with detail screens.
   - Sized buttons with "Freed" toasts, and tips.
4. **Audit (partial):**
   - Display names in toasts.
   - Plain-language errors with an `ErrorState` Details section.
   - Loading and empty states on the source screen.
   - `numericTransition` on counts.
   - `DESIGN.md`.

**Five-issue pass, 2026-11-09 (build 67):** one commit per issue.
1. **Shapes:** a single `AppButtonStyle` capsule. Action rows were converted to buttons placed under their cards. One card radius, and `Radius.tile`.
2. **App icon:** the alert-less private API, `AppIconStore` (optimistic, reverts on error), and a 2.5 pt concentric ring.
3. **Install:** the `InstallSession` rewrite (§2.4), `InstalledApps`, the palera check and fallback, and Share log.
4. **Performance:** single-publish theme, a one-Canvas aurora at 30 fps, pause triggers, card shadow on a single shape, no shine sweep on Library rows.
   - Measured in the simulator, same run:
     - Theme publishes per change went from 8 to 1 (plus 1 at the end).
     - Background frame went from 1.28 ms to 0.23 ms in dark mode, and from 0.34 ms to 0.23 ms in light.
5. **Liquid Glass:** iOS 26 sheets no longer override the corner radius, and `glassSurface` uses `ConcentricRectangle`.
- **Test fix:** a Sources refresh test was timing-dependent. It failed when a fast HTTP 304 finished in under 50 ms, so it was rewritten.

**2026-11-10:**
- **Accent blends (`b2be2f6`):**
  - An `Accent` model with 16 blend presets.
  - Custom blends: two ColorPickers, saved to UserDefaults `ui.customAccents`, deleted by long press.
  - A Solid/Blended sliding switch.
  - Black or white labels at 4.5:1 or better, with surface stops nudged if needed.
  - A per-appearance readable tint at 3:1 or better.
  - The selection is stored by id. Old `AccentOption` raw values are the solid ids, so it migrates automatically.
- **Web installer:** commits `a89850b` through `1e96feb` (§2.6).
  - Fixed a zsign WASM bug: signatures written through `mmap(MAP_SHARED)` never reached MEMFS, so the binaries came out unsigned. `msync` alone didn't help; the fix was buffered map and write-back under `__EMSCRIPTEN__`.
  - Pinned Playwright to 1.65.0.
  - Also fixed: a YAML step name with a colon broke the workflow, and `node --test tests` became a glob.
- **First-launch confirmation (`08bdac0`, `c16a527`):** "Signed with <cert>, expires <date>".
- **Cloudflare setup:** deployed by hand (see §2.6), relay smoke-tested live, then `RELAY_URL` was set.
- **Certificate hand-off (commits after `c16a527`, ending at `59dcece`):** the user reported that after installing from the web page the app said "No certificates yet". Fixed with the Import button and `certsigner://` (build 87).

**Reverted or abandoned:**
- The user once said "revert everything you did from the latest prompt i gave you the one i stopped right now". This happened in the compacted history. **(Unverified)** what exactly was reverted; I believe it was an in-progress change around the background motion request.
- Diagnostic branches (`diag/screens`, `diag/screens2`, `diag/screens3`, `diag/profile`) were created to get simulator screenshots or probes and then deleted. None of them were merged.

---

## 4. Current state

**Works (verified by CI and/or the user):**
- **CI:**
  - The app builds on CI. Only the pre-existing warnings remain.
  - **25/25** XCTests pass in the simulator (`Signing test` workflow).
  - **8/8** web tests pass: WASM signing of the real IPA, relay logic, and a Playwright end-to-end run in Chromium and WebKit, including the "no request contains the p12, password or key" check.
- **User-confirmed on a real iPhone:**
  - The web page signs and installs CertSigner.
  - Earlier builds' signing, install, sources, deletes and the UI generally.
- **Live:** Pages site, relay and `latest` release (build 87).

**Implemented but NOT verified on a device (please ask the user):**
- **Web certificate hand-off:** "Import Certificate into CertSigner" (build 87, just shipped). This is the user's most recent bug report, and the fix is untested on iPhone.
- **Install:** the rewrite. Specifically CapCut, delete and reinstall, the stall states with Reopen Prompt, and LaunchServices confirmation. Private API availability on device is unknown.
- **App icon:** whether the alert really disappears with the private API.
- **Appearance:** accent blends and custom blend UI; the iOS 26 sheet concentric corners (seen only in a simulator screenshot).
- **Performance:** on an iPhone 16 Pro Max at 120 Hz. Instruments was never run, because there's no Mac.
- **Launch toast:** the first-launch "Signed with…" toast on a real install.

**Incomplete:**
- **Part 4 audit:**
  - Settings rows and Home are not rebuilt from `ListRow`/`ErrorState`.
  - About 14 `.system(size:)` icon fonts and some deliberate colour literals remain (the orange/pink Quick Sign tile).
  - No contrast audit, no iPhone SE / Pro Max / iPad layout pass, no FPS measurement.
- **Features the user asked for that don't exist, so nothing was converted:**
  - "Signed Versions to Keep" setting.
  - Grid, layout and font settings.
  - Sources filters and sort.
- **Undo exists only for signed apps.** Certificates would need a Keychain password restore.
- **The web installer's entitlement pruning is zsign's default behaviour.** It uses the profile's entitlements. Explicit removal of entitlements the profile doesn't allow was not separately implemented.
- **Keychain access group for an explicit bundle-ID re-sign was not specifically tested** (the spec asked for it).

**Broken / known failing:** nothing known to be failing in CI at handover.

---

## 5. Technical decisions (and rejected alternatives)

- **Compatibility signing is the default.**
  - It passes no bundle-ID override to zsign, keeps and signs every appex, framework and dylib, and skips the App-ID mismatch checks.
  - The user verified on device that Husk (`com.husk.app`, two extensions) installs and works this way, matching FlareStore.
  - Strict keeps the original behaviour unchanged: rewrite the bundle ID and block on mismatch.
- **Source refreshes are owned by `RepositoryStore`**, not by view `.task`. Views re-rendering kept cancelling them and showing "cancelled". `CancellationError` and `URLError.cancelled` are never shown as errors.
- **Certificate picker is a bottom sheet, not a `Menu`.**
  - On iOS 26 the menu's snapshot made the pill blur and show a square box, and long raw IDs wrapped mid-word.
  - Short-label menus were kept.
  - `.identifierText()` gives one line with middle truncation.
- **Pills:** use non-interactive glass. `.interactive()` bloom bled outside the capsule.
- **Delete animation:**
  - One shared motion.
  - The clip (`DeleteClipShape`) applies only while a delete runs, so shadows and glows survive at rest.
  - No blur.
  - The item is removed from the data **before** re-render, so stale cards don't flash back.
- **Toast durations:** Undo toasts last 5 s and plain toasts 2.5 s. This reconciled two conflicting user requirements.
- **No animated or rolling numbers for download sizes or progress.** The user said they "make me dizzy". The `numericTransition` on counts was added later, in the audit, for list counts only.
- **Parallel downloads only for files of 8 MB or more.**
- **Theme:** animate one value; never publish per frame.
- **Background:** one Canvas at 30 fps with pause triggers. A view per blob at 60 fps was rejected.
- **Appearance switch uses a snapshot cross-fade.** SwiftUI can't animate `preferredColorScheme` without flashing.
- **Two shapes only:** action buttons are 52 pt capsules; navigation and info are rows inside a single clipped card. Buttons in Lists go *under* the card using `.buttonRow()`.
- **App icon change uses private `_setAlternateIconName:completionHandler:`** via the ObjC runtime, guarded with `responds(to:)`, falling back to the public API.
  - **Rejected:** testing it by actually changing the simulator icon. The first test hung the simulator host, so the setter is injected in tests.
- **Install phases are driven by server events.** Lifecycle-driven phases caused permanent waits.
- **LaunchServices private classes for "is installed"** are guarded with `responds(to:)` and treated as optional.
- **Web installer:**
  - Signing is in the browser. Rejected: server-side signing, because of the privacy requirement.
  - The relay holds only the signed IPA. KV was used, not R2; R2 needs a card on the free plan **(believed; not re-checked)**. KV's 25 MB value limit made the maximum 25 MB.
  - The certificate goes to the app through a URL fragment of a custom-scheme link. That's local only and never requested over the network.
  - **Rejected:** uploading the certificate to the relay for the app to fetch. That would break the "never uploaded" guarantee.
- **Cloudflare deploy was done from this PC using `wrangler login` OAuth.**
  - The browser automation path was blocked by Cloudflare's Turnstile.
  - The user did not create an API token, so CI can't redeploy the Worker.
- **Undo only for signed apps.** Certificates would need a Keychain password restore.

---

## 6. Known bugs, pitfalls, and things not to repeat

- **Pre-existing compiler warnings to ignore when grepping CI logs:**
  - `Services/FileDownloader.swift`.
  - `Services/LocalHTTPServer.swift` lines ~105–110: a captured `var resumed` in a concurrent closure, a Swift 6 warning.
- **zsign under Emscripten:** `MAP_SHARED` writes are lost. Keep patch 4 in `Vendor/zsign/common/fs.cpp`. It only affects WASM.
- **Signing test fixtures need a CA chain.**
  - A self-signed leaf failed in zsign. The leaf is issued by a test CA carried in the p12, like Apple's WWDR intermediate (`.github/scripts/make-signing-fixtures.sh`).
  - The app test fixture p12 password is `test`. The web fixtures generate a random password per run in `web/tests/fixtures/password.txt`, which is gitignored.
- **Tests depending on timing are flaky:**
  - The ThemeStore fade sampling windows needed widening.
  - The Sources refresh 50 ms check raced a fast 304.
  - Prefer deterministic checks: `ThemeFade.stops(at:)`, and checking completion instead of "still running".
- **`ThemeStore.currentTraits` is intentionally non-private.** Tests must resolve colours with the same traits as the store.
- **XcodeGen gotchas:**
  - Use `ProfileParser.parse(data:)`, not `ProvisioningProfile.parse`. This broke one build.
  - `AppIconStore.shared` must be initialised on the main actor. A default argument that read `UIApplication` caused an isolation warning.
- **GitHub Actions:**
  - An unquoted `name: Test: …` in YAML breaks the workflow file, and `workflow_dispatch` then reports "no trigger".
  - Playwright 1.49 can't install deps on the current Ubuntu runner, so use 1.65.0.
  - Actions had a major outage on 2026-11-09. Runs that failed with "workflow file issue" and zero jobs were GitHub's fault; re-run them.
  - The `Signing test` workflow `tee`s the full log and greps all results. `tail -n 60` used to hide the earlier suites.
- **WebKit CSP:** Playwright's WebKit screenshot injects an inline style that the CSP refuses. The e2e test checks console errors *before* taking screenshots.
- **GitHub Pages caching:** up to about 10 minutes. Use `?v=$RANDOM` when verifying.
- **New workers.dev subdomains** take a few minutes to answer: connection code 000, then 200.
- **Simulator test `CertificateStore()`** uses the real `Documents` folder of the test host. `WebImportTests` deletes what it creates.
- **The user's "WuXu's Library" source URL is unknown.** The test source is `https://apps.sidestore.io/`.

---

## 7. Dependencies and integrations

- **Swift packages:** ZIPFoundation (≥0.9.19) and OpenSSL xcframework `krzyzanowskim/OpenSSL` (≥3.3.0).
- **Vendored code:**
  - zsign, MIT, from zhlynn/zsign at commit `9299685bab7ef99827e06e5dfda93af747386590`. Some files were removed; see `Vendor/README.md`.
  - fflate 0.8.2, MIT, in `web/site/js/vendor/`.
- **Web build:** Emscripten 3.1.74 through `mymindstorm/setup-emsdk@v14`, OpenSSL 3.3.2 source (sha256 `2e8a40b0…d281`), Node 22, Playwright 1.65.0 (CI only, `--no-save`).
- **Relay:** Cloudflare Workers, KV and the Rate Limiting binding; Wrangler 4 (4.160.0 used locally).
- **External services:**
  - **`api.palera.in`:** builds Semi-Local manifests.
  - **backloop.dev:** a public DNS name pointing at 127.0.0.1, with a published certificate. Run by a third party; can lapse.
  - **GitHub:** Releases, Pages and Actions.
  - **Cloudflare.**
- **Private Apple APIs used (all guarded):**
  - `_setAlternateIconName:completionHandler:`.
  - `LSApplicationProxy`, `LSApplicationWorkspace`.
- **Tools on the dev PC (Windows 11):**
  - `gh` CLI at `C:\Program Files\GitHub CLI`. Sessions may need `export PATH="$PATH:/c/Program Files/GitHub CLI"`.
  - Account `risinginvader2007-hub`.
  - git identity: risinginvader2007-hub <[redacted]>.
  - Node is available. **There's no Mac, no Xcode and no Swift locally**, so all Swift compiling happens on CI.

---

## 8. Remaining work (priority order, my judgement)

1. **Get on-device confirmation of the build 87 web import.**
   - Steps: re-sign on the page, Install, then Import Certificate into CertSigner, then Open, and the toast "Imported … Ready to sign".
   - The installed app must be build 87 or later; older builds don't register the `certsigner` scheme.
2. **Verify the install rewrite on device.** CapCut, delete and reinstall, install twice, dismiss the prompt to check the stall UI, and the already-installed hints.
3. **Verify the app icon change has no alert, plus the blends UI and performance at 120 Hz.**
4. **Optional: let CI deploy the Worker.** The user would add `CLOUDFLARE_API_TOKEN` (and possibly `CLOUDFLARE_ACCOUNT_ID`) as repo secrets. Never paste these in chat. Until then, redeploy from the PC with `bash worker/deploy.sh` and wrangler OAuth.
5. **Finish the design audit leftovers** (§4 Incomplete).
6. **Web installer gaps against the original spec:**
   - Explicit pruning of disallowed entitlements.
   - Keychain access group behaviour after a bundle-ID rewrite.
   - The 50 MB to 25 MB size limit difference.
   - Desktop browsers sign and offer Download, but Install only makes sense on iOS.
7. **`docs/FEATURE_INVENTORY.md` is probably stale.** Update it.

No other planned features were requested and left unstarted, as far as I know.

---

## 9. Development workflow

The user's standing workflow:
1. Work on the `ui-overhaul` branch.
2. Make small commits, one issue per commit.
3. Push.
4. Get CI green.
5. Merge to `main` with a fast-forward.
6. Give the user a list of changed files and an iPhone test checklist.

**Commands used throughout:**
```bash
export PATH="$PATH:/c/Program Files/GitHub CLI"; R=risinginvader2007-hub/CertSigner
# app build on a branch (Build IPA only auto-runs on push to main)
gh workflow run build.yml -R $R --ref ui-overhaul
#   web-only (skips the macOS app build, uses the IPA from the latest release):
gh workflow run build.yml -R $R --ref ui-overhaul -f web_only=true
id=$(gh run list -R $R -w "Build IPA" -b ui-overhaul -L 1 --json databaseId -q '.[0].databaseId')
timeout 390 gh run watch $id -R $R --exit-status --interval 20 >/dev/null; echo $?
# new compiler warnings / errors (filter the pre-existing ones)
gh run view $id -R $R --log | grep -E "\.swift:[0-9]+:[0-9]+: (error|warning)" | grep -v "FileDownloader\|LocalHTTPServer.swift:1[01][0-9]"
# simulator tests run automatically on push to main and ui-overhaul ("Signing test" workflow)
gh run view <id> -R $R --log | grep -E "Test Case .*(passed|failed)|Executed [0-9]+ tests"
# release
git checkout main && git merge --ff-only ui-overhaul && git push origin main && git checkout ui-overhaul
gh release view latest -R $R
```

**Workflows:**
- **`.github/workflows/build.yml` ("Build IPA"):** runs on push to `main` and on `workflow_dispatch` (input `web_only`). Jobs:
  - `build` (macos-latest): runs xcodegen, then an unsigned Release `xcodebuild -sdk iphoneos`, then zips `Payload/` into `CertSigner.ipa`. On `main` it publishes the `latest` release, titled "CertSigner (build <run_number>)".
  - `web` (ubuntu): gets the IPA, builds the WASM with the OpenSSL build cached, installs Playwright, makes fixtures, and runs `node --test tests/*.test.mjs`. Uploads `web-site` (wasm and app) and `web-test-screenshots`.
  - `relay` (main only): `bash worker/deploy.sh`. It's a no-op without the secret.
  - `pages` (main only): `node web/scripts/prepare-site.mjs`, with `RELAY_URL` from the relay job's output or `vars.RELAY_URL`, then deploy-pages.
- **`.github/workflows/signing-test.yml` ("Signing test"):** runs on push to `main` and `ui-overhaul`.
  - Makes fixtures with `.github/scripts/make-signing-fixtures.sh`: a 2-extension IPA, a framework, a dylib, a CA-issued p12 with password `test`, and an explicit mismatching profile `ABCDE12345.com.other.app` against app `com.husk.test`.
  - Runs `xcodebuild test -scheme SigningTests` on an iPhone simulator with `TEST_RUNNER_CS_FIXTURES`.
  - Then checks the PlugIns folder of the signed IPA.
- **Test suites (`Tests/`):**
  - Signing pipeline.
  - ThemeStore, Accent, AppearanceCrossfade.
  - DeleteFlow, SourcesRefresh (needs network: sidestore.io).
  - StorageService, InstallServer, AppIconStore, Performance.
  - LaunchSignature, WebImport.
- **Diagnostics without a Mac:**
  - Push a throwaway `diag/<name>` branch containing a `diag-screens.yml` workflow. It builds for the simulator (the largest iOS 26 Pro Max), launches with env hooks (`SIMCTL_CHILD_CS_TAB`, `CS_SHEET`, `CS_SCROLL`), and runs `simctl io screenshot`.
  - Download the artifact and inspect it, then delete the branch.
  - These hooks were **diag-only** and are not on `main`.
- **Web locally:** see the README "Run it yourself". Local Node can run `worker.test.mjs` without WASM; the other tests need Emscripten output.
- **Worker deploy from the PC:**
  - `cd worker && npx wrangler login`.
  - Then a deploy with a config whose KV id is `b99216883f054524a52bbb3527f44045`. `worker/deploy.sh` does this when `CLOUDFLARE_API_TOKEN` is set.
  - With OAuth only, copy `wrangler.toml` to `wrangler.deploy.toml`, sed the id in, run `CI=1 npx wrangler deploy --config wrangler.deploy.toml`, then delete it. That's what was done.
- **Windows quirks:**
  - Files are often CRLF; edit while preserving line endings.
  - Hermes' file writer sometimes refused overwrites (not relevant to Claude Code).
  - Long `gh run watch` calls were wrapped in `timeout`.

---

## 10. Important context about the user and expectations

- **How he works:**
  - Sends long, structured specs with numbered parts and strict rules: "Don't break, remove or move any feature, button or setting", "Keep the shared button style, sliding selection, delete animation, haptics and Liquid Glass", "Respect Reduce Motion", "Keep the GitHub Actions build green", and "list every file changed".
  - Expects small commits, CI green on every push, honest reporting of what's unverified, and an **iPhone test checklist** with each delivery.
  - He often says he won't download a build until everything is finished.
- **Recently** he repeatedly asked for speed because his usage was running out. Keep replies short.
- **Bug reports** arrive as plain observations ("the certificates weren't imported", "colors are very faint", "numbers make me dizzy").
- **Has an iPhone 16 Pro Max.** It's referenced as the performance target; that he owns one is **(believed)**. His iOS version is **(unverified)**, likely iOS 26 given the Liquid Glass reports.
- **He wants Claude Pro subscription capacity, not API billing.** This is context for Hermes, not the project.
- **Secrets policy:**
  - Never ask him to paste tokens or passwords in chat.
  - Cloudflare and GitHub secrets are added by him or through OAuth flows.
  - The test p12 passwords in the repo are throwaway fixtures.

---

## 11. Things I cannot confidently recall / verify

- **Build numbers:** the exact mapping of build numbers to commits for builds between 55 and 87, and my earlier "build 51" report. The run_number increments on every Build IPA run, including branch and web-only runs.
- **The revert:** the exact contents of the change the user asked me to revert ("revert everything you did from the latest prompt… the one I stopped").
- **The 16:05 paste (the five-issue pass) was handled in full** (§3). Earlier pasted specs exist only as summaries in my context.
- **Feature inventory:** whether `docs/FEATURE_INVENTORY.md` reflects the current app.
- **Live behaviour:** whether `api.palera.in` and backloop.dev are currently live and working.
- **Device facts:** whether the private APIs (alert-less icon change, LSApplicationProxy fields such as `teamID`) work on the user's iOS version.
- **On-device results:** the outcome of the web import on device (build 87), and of the install rewrite.
- **Cloudflare free plan:** whether the Rate Limiting binding actually enforces limits on the free plan. It deployed and listed "5 requests/60s", but enforcement wasn't tested live.
