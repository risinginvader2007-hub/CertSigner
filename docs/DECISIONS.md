# Technical decisions and pitfalls

Why things are the way they are, what was tried and rejected, and mistakes not to repeat.
Originally from the Hermes handover (§5, §6), 2026-11-07 → 11-10. Add new entries with a date.

## Decisions

### Signing
- **Compatibility is the default signing mode** (build 45). It passes no bundle-ID override to
  zsign, keeps and signs every appex, framework and dylib, and skips App-ID mismatch checks. Verified
  on device by the owner: Husk (`com.husk.app`, two extensions) installs and works this way,
  matching FlareStore. **Strict** keeps the original behaviour (rewrite bundle ID, block on mismatch).
- **Entitlements come from the profile, unchanged, for every executable** (zsign without an
  entitlements file; `archo.cpp` uses one blob for the app and each appex). With an explicit
  profile for another App ID, every signed app and extension gets that App ID as
  `application-identifier` and the profile's App Groups / keychain groups — it shares that app's
  identity (Keychain, App Groups, system UI such as the Dynamic Island's Now Playing tap, which
  opened CertSigner because the web installer gives CertSigner the profile's App ID as its bundle
  ID). Build 103: Compatibility shows a **non-blocking** warning for this; Strict refuses
  CertSigner's own bundle ID (app and pipeline) and `suggestedBundleID` no longer proposes it for
  other apps; the signing log reads each bundle's real entitlements back from its signature.
  Deferred until the owner has a wildcard or matching profile: per-bundle entitlements
  (`TEAMID.<bundle ID>`, app's own groups filtered by the profile) — a single explicit profile can't
  give other apps a valid identity of their own, so it would not help with explicit-only profiles.
- **Conclusion (2026-11-14):** Dynamic Island/Now Playing opening CertSigner is caused by sideloaded
  apps sharing the profile's explicit App ID; fix needs a second profile with a different App ID or
  a wildcard; not a CertSigner code bug. (The owner's FlareStore dev and dist profiles both use
  `A2V52T4RD8.app.serval455.apricot580`; the per-bundle entitlements fix is dropped for now.)
- The app reads the App ID from `Entitlements["application-identifier"]`, never `Name` /
  `AppIDName` (confirmed with the "Raw Profile Data" screen, build 42).

### Install
- **Install phases are driven by server events** (manifest request, IPA GET, bytes, completion).
  Lifecycle-driven phases caused permanent waits — the CapCut "stuck at Confirm" bug.
- **One app-wide `InstallSession`**; every start gets a fresh port and path token, and stale
  server events are dropped by `generation`.
- **LaunchServices private classes for "is installed"** — guarded with `responds(to:)`, treated as
  optional.
- **Semi-Local falls back to Fully Local** when `api.palera.in` is down (setting, default on).

### Sources
- **Refreshes are owned by `RepositoryStore`**, not view `.task`: view re-renders kept cancelling
  them and showing "cancelled". `CancellationError` / `URLError.cancelled` are never shown as
  errors. 20 s timeout, one retry after 1.5 s, ETag / Last-Modified, Retry button (build 53).
- **Parallel downloads only for files ≥ 8 MB** (up to 8 byte-range connections).
- History: on 2026-11-08 the owner briefly dropped Sources / URL downloads; they were re-added the
  same day (build 17) and are a shipped feature.

### UI
- **Two shapes only:** actions are 52 pt `AppButtonStyle` capsules; navigation / info are rows in
  one clipped card. Buttons in Lists go *under* the card with `.buttonRow()`.
- **Certificate picker is a bottom sheet, not a `Menu`:** on iOS 26 the menu snapshot blurred the
  pill and showed a square box, and long IDs wrapped mid-word. Short-label menus were kept.
  `.identifierText()` = one line, middle truncation.
- **Pills use non-interactive glass:** `.interactive()` bloom bled outside the capsule.
- **Delete animation:** one shared motion (press 0.96 → slide left + fade, no blur → spring
  collapse). The clip (`DeleteClipShape`) applies only during a delete so shadows survive at rest.
  Data is removed **before** re-render so stale cards don't flash back. Detail screens pop first,
  then animate the row.
- **Undo only for signed apps.** Certificates would need a Keychain password restore.
- **Toasts:** 2.5 s plain, 5 s with Undo (reconciled two conflicting owner requirements).
- **No rolling numbers for download sizes or progress** — the owner said they "make me dizzy".
  `numericTransition` is used only on list counts (added later in the audit).
- **App icon change uses private `_setAlternateIconName:completionHandler:`** (no alert), via the
  ObjC runtime, guarded, falling back to the public API. `AppIconStore` is optimistic and reverts on
  error. Rejected: testing by really changing the simulator icon — it hung the simulator host; the
  setter is injected in tests.
- **Icon change crash on iOS 27.2 (build 98 diagnostics, 2026-11-14):** the private call changes the
  icon, then the app dies with SIGTRAP ~2 s later. Cause: UIKit calls the completion block off the
  main thread, and the block called `AppIconStore.select`'s closure, which Swift had inferred as
  main-actor isolated (formed inside a `@MainActor` method, passed as a non-`@Sendable` parameter);
  the runtime isolation check traps. The "app closes, alert over the Home Screen, relaunch" was this
  crash, not iOS closing the app. Fix: the setter's completion is `@Sendable` (never isolated); the
  block is built in a `nonisolated static func`, captures no main-actor state, logs
  "completion fired on main=…", and hops to `DispatchQueue.main` for everything else. Rule: any
  closure handed to a system or private API callback must be `@Sendable`/nonisolated and hop to main
  itself; never `MainActor.assumeIsolated` there. Whether the private API still shows the alert on
  iOS 27.2 is not yet known (the crash hid it).
- **Accents:** selection stored by id; old `AccentOption` raw values are the solid ids, so they
  migrate. Labels are black or white at ≥ 4.5:1; per-appearance readable tint ≥ 3:1.

### Theme and performance (2026-11-09, build 67)
- **Theme: animate one value, never publish per frame.** Before, `ThemeStore` published on every
  CADisplayLink frame (~8 publishes per change in tests). Now 1 (+1 to clear the fade).
- **Background: one Canvas at 30 fps with pause triggers.** Rejected: a view per blob at 60 fps.
  Measured in the simulator: frame 1.28 ms → 0.23 ms (dark), 0.34 → 0.23 ms (light). In dark mode
  lights are drawn straight onto the base (an extra transparency layer cost more than it saved).
- **Appearance switch uses a snapshot cross-fade** — SwiftUI can't animate `preferredColorScheme`
  without a flash.
- Card shadow on a single base shape; no shine sweep on repeated Library rows.

### Web installer
- **Signing happens in the browser.** Rejected: server-side signing (privacy requirement).
- **The relay holds only the signed IPA**, in KV. KV rather than R2 because R2 was believed to need
  a card on the free plan (not re-checked). KV's 25 MB value limit set the max upload; the original
  spec said 50 MB, knowingly lowered (a signed CertSigner is ~6 MB).
- **Certificate goes to the app via a URL fragment of a `certsigner://` link** — local only, never
  requested over the network. Rejected: uploading the certificate to the relay for the app to
  fetch (breaks the "never uploaded" guarantee).
- **Entitlements are the profile's, via zsign's default behaviour.** Explicit pruning of
  entitlements the profile doesn't allow was not separately implemented.
- **Cloudflare deploy was done from the owner's PC with `wrangler login` OAuth.** Browser automation
  was blocked by Turnstile; no API token was created, so CI can't redeploy the Worker.

## Pitfalls (don't repeat)

### Swift / XcodeGen
- `ProvisioningProfile.parse` does not exist — use `ProfileParser.parse(data:)` (broke run 82).
- `AppIconStore.shared` must be initialised on the main actor (a default argument reading
  `UIApplication` caused an isolation warning).
- `ThemeStore.currentTraits` is intentionally non-private: tests must resolve colours with the same
  traits as the store.
- Known pre-existing warnings to filter from CI logs: `Services/FileDownloader.swift`, and
  `Services/LocalHTTPServer.swift` ~lines 105–110 (captured `var resumed` in a concurrent closure,
  Swift 6 warning).

### zsign
- **Under Emscripten, `mmap(MAP_SHARED)` writes never reach MEMFS**, so binaries came out unsigned.
  `msync` alone didn't help. Keep patch 4 in `Vendor/zsign/common/fs.cpp` (buffered map +
  write-back, `__EMSCRIPTEN__` only; no effect on iOS).

- **Read-only files in an IPA break on-device signing** (2026-11-13). zsign opens every binary
  for writing to insert the signature; a file without write permission (CertSigner's own
  `OpenSSL.framework/OpenSSL` is stored 0555) is skipped as "non-Mach-O" and the app fails with
  "Can't parse BundleExecute file". `SigningWorker` now gives the owner write permission on every
  unpacked file before zsign runs (`AppBundlePatcher.makeWritable`). The WebAssembly signer never
  hit this (in-memory files have no permissions), which is why the web installer worked.

### Tests
- **Signing fixtures need a CA chain.** A self-signed leaf fails in zsign; the leaf is issued by a
  test CA carried in the p12 (like Apple's WWDR). App fixture p12 password: `test`. Web fixtures
  generate a random password per run in `web/tests/fixtures/password.txt` (gitignored).
- **Timing-based tests are flaky.** ThemeStore fade sampling windows needed widening; the Sources
  refresh "still running after 50 ms" check raced a fast 304. Prefer deterministic checks
  (`ThemeFade.stops(at:)`, checking completion).
- Simulator `CertificateStore()` uses the real test-host `Documents`; tests must delete what they
  create (`WebImportTests` does).
- The test source is `https://apps.sidestore.io/`. The owner's "WuXu's Library" source URL is unknown.

### GitHub Actions / web
- An unquoted `name: Test: …` breaks the workflow file; `workflow_dispatch` then reports "no trigger".
- Playwright 1.49 can't install deps on the current Ubuntu runner — pinned to 1.65.0.
- The `Signing test` workflow `tee`s the full log; `tail -n 60` used to hide earlier suites.
- Playwright's WebKit screenshot injects an inline style the CSP refuses: check console errors
  *before* screenshots.
- On 2026-11-09 Actions had a major outage: runs failing with "workflow file issue" and zero jobs
  were GitHub's fault — re-run them.
- GitHub Pages caches up to ~10 min; add `?v=$RANDOM` when verifying.
- New workers.dev subdomains take a few minutes to answer (000, then 200).
