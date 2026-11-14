# CertSigner feature inventory (regression checklist)

Baseline: tag `pre-ui-overhaul` (commit `41316d2`, release build 24).
Every item below must still exist and behave the same after each UI sub-stage.
`[x]` = verified present in code after the stage named in the table at the bottom; device checks are listed separately.
Last brought up to date: 2026-11-13 against build 87 (`59dcece`), from the code; which of these were
tested on a device is tracked in [`STATUS.md`](STATUS.md).

## App shell
- [x] App launches into Home tab; stores wired at launch (certificates, library, signed apps, queue, server certs, sources, toasts, router, importer)
- [x] Tabs: Home, Library, Sources, Settings (+ Search tab on iOS 26)
- [x] iOS 26: native Liquid Glass TabView, Search tab as separate glass button, tab bar minimises on scroll down
- [x] iOS 16–25: custom floating glass tab bar (safe-area inset), hides while keyboard is up, tabs stay alive and cross-fade
- [x] Library tab badge = signed apps expiring/expired
- [x] Haptic on tab switch
- [x] Appearance (System/Light/Dark) and accent colour applied app-wide
- [x] SF Rounded font everywhere
- [x] Toast overlay (success / error / warning / info), plain toasts 2.5 s, toasts with Undo 5 s, swipe or tap to dismiss
- [x] "Open in" / Share → CertSigner: `.ipa` → import + review sheet; `.p12`/`.pfx`/`.mobileprovision` → certificate import sheet; unsupported / unreadable → error toast
- [x] `certsigner://import#…` (from the web installer): imports the certificate, skips duplicates, sets it active, toast "Imported … Ready to sign"
- [x] First launch after a (re)sign: "Signed with <certificate>, expires <date>" toast, once per signature
- [x] One-time animated intro (tap or Skip)
- [x] Animated aurora background (paused while scrolling, with a sheet up, in Low Power Mode, with Reduce Motion, or when turned off in Settings)
- [x] Root sheets: certificate import, Review & Sign (from imports), Install (auto-install after signing)

## Home
- [x] Stat cards: Certificates count, Signed apps count, Days left on active certificate (warning tint when attention needed)
- [x] "Needs attention" banner (expiring/expired apps and/or active certificate) → opens Library filtered to attention items
- [x] Importing card with spinner while an IPA is being imported
- [x] Import IPA drop zone: tap → Files picker (`.item`), drag & drop an IPA, highlight while drag-over
- [x] Quick Sign row: requires a certificate (else toast + opens certificate import), picks IPA and auto-signs with defaults
- [x] Active certificate card: status badge, lifetime progress bar, expiry countdown, Switch (bottom sheet, when >1 cert), Manage → Certificates
- [x] No-certificate card with Add button
- [x] Pull to refresh (reload certificates + signed apps)

## Library
- [x] Empty state "Your library is empty" with action → Home
- [x] Signing section: live jobs (step, progress ring/percentage), "Tap for log", failed jobs with reason, Retry / Remove, swipe to remove
- [x] Signing log sheet per job (live log, steps, result; Retry for failed; Done; Share signing log)
- [x] Attention-only filter banner ("Showing items that need attention. Tap to show all.")
- [x] Signed Apps section: icon, name, version, certificate used, status badge, expiry countdown
- [x] Row actions: Install, Re-sign, Share (ShareLink); swipe left Delete (shared delete animation, "Deleted <app>" toast with Undo for 5 s), swipe right Re-sign
- [x] Sort & Filter sheet: Sort (date / name / expiry) and Status as sliding controls, Certificate filter with spring checkmark, Clear Filters, "No signed apps match your filters"
- [x] Search signed apps (inline `.searchable` on iOS 16–25)
- [x] Pull to refresh
- [x] Install sheet from a row
- [x] Signed app detail: details card, Install, Re-sign, Share, Share signing log, Delete (pops back first, then the row animates out), "App removed" state

## Review & Sign sheet
- [x] Header: icon, name, bundle ID, version badge, size badge, extension count badge
- [x] No-certificate card → Add Certificate (dismisses, opens import)
- [x] Certificate picker (bottom sheet) + status/type badges + App ID row
- [x] Signing mode sliding control: Compatibility (default) / Strict
- [x] Pre-sign checks list (pass / fail / unknown icons, title, detail; stepper rail, passed checks collapse)
- [x] Warnings card (amber, non-blocking) above the errors card: shared-identity warning (Compatibility + explicit profile for another App ID), no saved password, device not checked
- [x] Strict refuses CertSigner's own bundle ID ("would replace CertSigner"); the suggested bundle ID is never CertSigner's own for another app
- [x] Signing log: "Signed identity per bundle" (application-identifier, team, app groups, keychain groups, get-task-allow, count; flags a shared identity)
- [x] Options: display name, keep original bundle ID toggle (+ bundle ID field when off), version, remove extensions (when any), remove Watch app (when present)
- [x] After Signing: "Install when done" toggle (also persists the setting)
- [x] Error list; Sign button disabled + shake when issues; "Fix the issues above" label
- [x] Quick Sign / Sources GET: auto-start when checks pass, warning toast otherwise
- [x] Cancel; staged IPA discarded if the sheet closes without signing
- [x] On sign: queue job, toast "Signing…", switch to Library, dismiss

## Install sheet
- [x] Header with app icon, bundle ID, version, method description
- [x] Status icon per phase, status text (incl. transfer %), stage list (server → prompt → transfer → install) with progress bar
- [x] Troubleshooting tips on failure, live log, Try Again, Install Settings, Done / Cancel
- [x] One app-wide install session (re-shown sheet keeps the running install); each attempt uses a fresh port and path
- [x] Stalls: "iOS hasn't asked for the app yet" (15 s) / "Waiting for iOS to download the app" (30 s) with Reopen Prompt and Try Again; 180 s overall timeout; 30 s transfer stall fails
- [x] Install confirmed through LaunchServices (when available); "already installed" hint (update in place / different team)
- [x] Semi-Local: checks `api.palera.in` first, falls back to Fully Local when it's down (setting, on by default)
- [x] Share Install Log
- [x] Auto-close ~1 s after a successful install (Settings → Install → "Close install sheet automatically", on by default); failures never auto-close

## Certificates
- [x] List with glyph, nickname, team, status; context menu Set as Active / Delete (shared delete animation; no Undo for certificates)
- [x] Empty state "No certificates" + import action; Import certificate toolbar button; pull to refresh
- [x] Import sheet: nickname, .p12 picker, .mobileprovision picker, password, Import (validates password, keychain), Cancel; prefilled from shared files
- [x] Detail: Set as Active, This Device check (UDID in profile / Open Settings), Provisioning Profile, Signing Certificate (matches profile), Password (Change), Devices, Entitlements, Raw Profile Data (application-identifier + source key, team ID, type, App ID), Rename (alert), Change Password (alert), Delete (pops back first, then animates), "Certificate removed" state

## Sources
- [x] Empty state + Add Source; toolbar + and Edit (reorder)
- [x] All Apps row (count) → combined searchable list
- [x] Source rows: icon, name, app count / updated time, refresh spinner, error text; swipe Remove / Refresh; context menu Refresh / Copy Source URL / Remove
- [x] Add Source sheet: URL field, Paste from Clipboard, Add (validates, loading state, error + shake), Cancel
- [x] Source page: header (icon, host, subtitle, error, app count, Website link), search, pull to refresh
- [x] App rows with GET pill → download (progress ring, tap to cancel) → sign & install
- [x] One row per app (sources that list each version as its own entry are merged per bundle ID); "N versions" chip; GET disabled with the reason when the latest has no usable download
- [x] App detail: header badges, Get / Download & Review, download progress card (bytes, speed, Cancel), What's New, About (More/Less), Screenshots, Versions (newest first; version, build, date, size, minimum iOS, "Latest" badge; per-version GET; menu: Sign & Install, Download & Review, Copy Download Link; show all), Information
- [x] Auto refresh every 30 min on appear; refreshes owned by the store (never shown as "cancelled"), 20 s timeout, one retry, ETag / Last-Modified
- [x] Loading skeleton, empty state, plain-language error with Retry and Details
- [x] Downloads of files ≥ 8 MB use up to 8 parallel connections

## Search (iOS 26 tab)
- [x] Signed apps, Sources apps, Certificates sections; empty prompt; no-results text; navigation to detail screens

## Settings
- [x] Certificates section: active picker, list link, Add Certificate
- [x] Signing: Signing mode (sliding control), Install after signing, Delete original IPA, Remove extensions by default, Keep bundle ID by default
- [x] Install: Close install sheet automatically toggle; Install Method & Server → method sliding control, Semi-Local fallback toggle, backloop.dev update, public cert status, My Certificate (hostname, PEM files, save/remove), tips
- [x] This Device: UDID field, Clear UDID
- [x] Appearance: Theme sliding control (System / Light / Dark, snapshot cross-fade), Accent picker with Solid / Blended switch (16 blends), custom blends (two colour pickers, long-press delete), background animation toggle, Glow intensity (Low / Normal / High sliding control, stored separately for light and dark), App icon picker (Ocean / Sunset / Mint / Midnight, no system alert where supported)
- [x] Storage dashboard: ring chart, device free space, five categories with detail screens (sort, swipe delete, Delete All), Clear Cache, Remove Unused IPAs, Clear Log with "Freed …" toasts, tips
- [x] Diagnostics: Export Log File (ShareLink, preparing state), Clear Log
- [x] About: version, Updates row (status → update sheet), Check for updates automatically, Source on GitHub link
- [x] Update sheet: build, size, date, What's new, Signs with (certificate, team, expiry, bundle ID kept), checks, Update / Skip This Build; Download → Verify → Sign → Install progress, Reopen Prompt, Try Again, Cancel; never blank: "Checking for updates…" / "Loading build N…" with a spinner while the details load (it loads them itself when opened, or waits for a running background check), "Couldn't check" with Try Again + Share Log, or "up to date"
- [x] Home card "CertSigner build N is available" (from the saved check at launch; notes line once details load); "Updated to build N" toast after the update
- [x] Update indicator: iOS 16–25 a small red dot (no number) on the custom tab bar's Settings tab; iOS 26+ the system tab bar's red count badge "1" on Settings (an empty badge isn't reliably drawn there); a red dot next to the Updates row (whose status reads "Build N available"); the Home card. All four follow one state, shown at launch from the saved last check (no network wait); quiet re-check on launch and each return to the foreground (at most once a minute, off when "Check for updates automatically" is off); hidden for a skipped build, while installing, and once the installed build catches up; a failed check keeps the saved state; pop-in (fade only with Reduce Motion). Log: "update dot: show=… installed=… savedLatest=… skipped=… installing=… source=…"
- [x] Pull to refresh

## Web installer (`web/`, `worker/`)
- [x] Pick `.p12`, password, `.mobileprovision`; profile facts; checks (password, expiry, certificate in profile) block signing with the reason
- [x] Signs CertSigner in the browser (WebAssembly zsign in a Web Worker); nothing but the signed IPA is uploaded
- [x] Install (iOS, through the relay) / Download signed IPA; share log; Start Over
- [x] Import Certificate into CertSigner (iOS only) → `certsigner://import#…`

## Sub-stage verification log
| Stage | CI run | Inventory re-checked |
|---|---|---|
| 0 — inventory | — | baseline (162 control/flow markers in code) |
| 1 — design system, tokens, motion | 42506499158 ✅ | all present |
| 2 — tab bar, Home | 42506851863 ✅ | all present |
| 3 — Library, signed apps, signing/install progress, Sources lists | 42507298043 ✅ | all present |
| 4 — review sheet, Certificates, import | 42507744763 ✅ | all present |
| 5 — Settings, sheets, toasts, empty/loading | 42508094893 ✅ | all present; Theme `Picker` replaced by `GlassSegmentedControl` (same options, same setting, labelled "Theme") |
| 6 — launch/intro, accessibility, performance, docs | 42508508673 ✅ | all present; built Info.plist has `UILaunchScreen.UIColorName = LaunchBackground` |
| Builds 38–87 (catch-up, 2026-11-13) | 42836969298 ✅ (build 87) | inventory updated from the code; Theme control is now `SlidingSegmentedControl`; delete "dissolve" replaced by the shared delete animation |

Automated check after stage 6: every Button / Label / Toggle / Picker / sheet / swipe / context-menu / dialog / alert / refresh / search / drop / share / navigation marker from `pre-ui-overhaul` still exists (162 → 166; additions: intro Skip + accessibility labels; one replacement: Theme picker → glass segmented control).

## iPhone test checklist (new build)
1. First launch: intro plays once (tap or Skip); relaunch → no intro.
2. Home: stats count up once; drop-zone border moves; drag an IPA over it → glow; Quick Sign and Import still open Files.
3. Settings → Appearance: switch System/Light/Dark with the glass control; try each accent (Aurora first) → buttons, rings, tab pill follow; change app icon → preview updates.
4. Import an IPA → Review & Sign: tap a passed check to expand/collapse; sign → Library shows the gradient step bar → finished app shows an expiry ring; Install works.
5. Library: swipe left Delete / right Re-sign, Share, filters, search.
6. Certificates: set another certificate active → glow/border moves; import sheet: focus glow on fields, wrong password → button flashes red.
7. Sources: add a source, GET an app (download → sign → install).
8. Toasts: swipe up to dismiss.
9. Accessibility: Reduce Motion (no drift/tilt/bounce, fades only), Reduce Transparency (opaque glass), Increase Contrast (stronger borders), largest Dynamic Type on Home and Settings.
10. Web installer → Install → **Import Certificate into CertSigner** → Open → "Imported … Ready to sign"; the certificate is active (app must be build 87 or later).
11. First launch after installing a newly signed CertSigner: "Signed with …, expires …" toast once.
12. Install: CapCut; delete and reinstall; install the same app twice; dismiss the iOS prompt → stall message with Reopen Prompt; already-installed hint; Share Install Log.
13. Signing modes: Compatibility signs an app with extensions (e.g. Husk) and keeps its bundle ID; Strict blocks on an App ID mismatch. With the explicit profile: Compatibility shows the amber "will share the identity of …" warning and still signs; Strict on another app says to use Compatibility and never pre-fills CertSigner's bundle ID; the signing log lists "Signed identity per bundle".
14. Library delete → Undo within 5 s restores the app in place.
15. Settings → Appearance: Blended accents, a custom blend (create, long-press delete), background animation toggle; app icon change. — ✅ no crash on iPhone (iOS 27.2) 2026-11-14; the system alert still appears (accepted).
16. Storage dashboard: categories, detail screens, Clear Cache / Remove Unused IPAs show "Freed …".
17. Scrolling and accent changes feel smooth at 120 Hz.
18. Light mode: background glows clearly visible (default accent and a blend); text on and around them readable; dark mode looks exactly as before. — ✅ verified on iPhone 2026-11-14.
20. In-app update (needs an installed build that has the updater and a newer release): Home card / Settings → Updates → sheet shows notes, certificate, all checks green → Update → download, verify, sign → iOS prompt → Install → CertSigner closes → open it → "Updated to build N"; certificates, signed apps and settings still there. — ✅ verified on iPhone 2026-11-14 (build 95 → 96). Also: Skip This Build hides the card; a certificate from another team is refused with a clear message; Share Log on a failed update. — not yet tested.
22. Update indicator (needs a newer release than the installed build): open the app → right away, before any network: Home card "build N is available", Settings tab badge (iOS 26+: red "1"; iOS 16–25: red dot), red dot + "Build N available" on Settings → Updates; also in Airplane Mode once a check has run. Log shows "update dot: show=true … source=cache". Skip This Build → all gone; they return for a newer build. Update → gone while installing and on the new build.
21. Sources: search "Instag" (AppTesters) → one Instagram row per source with "N versions"; the detail lists every version newest first (454.0.0 on top, "Latest"), each with its own GET. Same in All Apps, each source's list and the Search tab; scrolling a big source stays smooth. — ✅ verified on iPhone 2026-11-14.
19. Switch Light ↔ Dark in Settings and from Control Center: the glows fade over with no flash. Glow intensity Low / Normal / High changes the glows, and each appearance remembers its own choice. — ✅ verified on iPhone 2026-11-14.

