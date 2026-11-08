# CertSigner feature inventory (regression checklist)

Baseline: tag `pre-ui-overhaul` (commit `41316d2`, release build 24).
Every item below must still exist and behave the same after each UI sub-stage.
`[x]` = verified present in code after the stage named in the table at the bottom; device checks are listed separately.

## App shell
- [x] App launches into Home tab; stores wired at launch (certificates, library, signed apps, queue, server certs, sources, toasts, router, importer)
- [x] Tabs: Home, Library, Sources, Settings (+ Search tab on iOS 26)
- [x] iOS 26: native Liquid Glass TabView, Search tab as separate glass button, tab bar minimises on scroll down
- [x] iOS 16–25: custom floating glass tab bar (safe-area inset), hides while keyboard is up, tabs stay alive and cross-fade
- [x] Library tab badge = signed apps expiring/expired
- [x] Haptic on tab switch
- [x] Appearance (System/Light/Dark) and accent colour applied app-wide
- [x] SF Rounded font everywhere
- [x] Toast overlay (success / error / warning / info), auto-dismiss ~2.8 s, tap to dismiss
- [x] "Open in" / Share → CertSigner: `.ipa` → import + review sheet; `.p12`/`.pfx`/`.mobileprovision` → certificate import sheet; unsupported / unreadable → error toast
- [x] Root sheets: certificate import, Review & Sign (from imports), Install (auto-install after signing)

## Home
- [x] Stat cards: Certificates count, Signed apps count, Days left on active certificate (warning tint when attention needed)
- [x] "Needs attention" banner (expiring/expired apps and/or active certificate) → opens Library filtered to attention items
- [x] Importing card with spinner while an IPA is being imported
- [x] Import IPA drop zone: tap → Files picker (`.item`), drag & drop an IPA, highlight while drag-over
- [x] Quick Sign row: requires a certificate (else toast + opens certificate import), picks IPA and auto-signs with defaults
- [x] Active certificate card: status badge, lifetime progress bar, expiry countdown, Switch menu (when >1 cert), Manage → Certificates
- [x] No-certificate card with Add button
- [x] Pull to refresh (reload certificates + signed apps)

## Library
- [x] Empty state "Your library is empty" with action → Home
- [x] Signing section: live jobs (step, progress ring/percentage), "Tap for log", failed jobs with reason, Retry / Remove, swipe to remove
- [x] Signing log sheet per job (live log, steps, result; Retry for failed; Done)
- [x] Attention-only filter banner ("Showing items that need attention. Tap to show all.")
- [x] Signed Apps section: icon, name, version, certificate used, status badge, expiry countdown
- [x] Row actions: Install, Re-sign, Share (ShareLink); swipe left Delete (with confirmation), swipe right Re-sign
- [x] Sort (date / name / expiry), Status filter, Certificate filter, Clear Filters, "No signed apps match your filters"
- [x] Search signed apps (inline `.searchable` on iOS 16–25)
- [x] Pull to refresh
- [x] Install sheet from a row
- [x] Signed app detail: details card, Install, Re-sign, Share, Delete (confirmation), "App removed" state

## Review & Sign sheet
- [x] Header: icon, name, bundle ID, version badge, size badge, extension count badge
- [x] No-certificate card → Add Certificate (dismisses, opens import)
- [x] Certificate picker + status/type badges + App ID row
- [x] Pre-sign checks list (pass / fail / unknown icons, title, detail)
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
- [x] One app-wide install session (re-shown sheet keeps the running install)

## Certificates
- [x] List with glyph, nickname, team, status; context menu Set as Active / Delete; swipe delete (confirmation)
- [x] Empty state "No certificates" + import action; Import certificate toolbar button; pull to refresh
- [x] Import sheet: nickname, .p12 picker, .mobileprovision picker, password, Import (validates password, keychain), Cancel; prefilled from shared files
- [x] Detail: Set as Active, This Device check (UDID in profile / Open Settings), Provisioning Profile, Signing Certificate (matches profile), Password (Change), Devices, Entitlements, Rename (alert), Change Password (alert), Delete (confirmation), "Certificate removed" state

## Sources
- [x] Empty state + Add Source; toolbar + and Edit (reorder)
- [x] All Apps row (count) → combined searchable list
- [x] Source rows: icon, name, app count / updated time, refresh spinner, error text; swipe Remove / Refresh; context menu Refresh / Copy Source URL / Remove
- [x] Add Source sheet: URL field, Paste from Clipboard, Add (validates, loading state, error + shake), Cancel
- [x] Source page: header (icon, host, subtitle, error, app count, Website link), search, pull to refresh
- [x] App rows with GET pill → download (progress ring, tap to cancel) → sign & install
- [x] App detail: header badges, Get / Download & Review, download progress card (bytes, speed, Cancel), What's New, About (More/Less), Screenshots, Versions (menu: Sign & Install, Download & Review, Copy Download Link; show all), Information
- [x] Auto refresh every 30 min on appear

## Search (iOS 26 tab)
- [x] Signed apps, Sources apps, Certificates sections; empty prompt; no-results text; navigation to detail screens

## Settings
- [x] Certificates section: active picker, list link, Add Certificate
- [x] Signing: Install after signing, Delete original IPA, Remove extensions by default, Keep bundle ID by default
- [x] Install: Install Method & Server → method picker, backloop.dev update, public cert status, My Certificate (hostname, PEM files, save/remove), tips
- [x] This Device: UDID field, Clear UDID
- [x] Appearance: Theme picker, Accent colour picker, App icon picker (Ocean / Sunset / Mint / Midnight)
- [x] Storage: per-area usage, total, Clear Cache, Remove Unused Imported IPAs (confirmation)
- [x] Diagnostics: Export Log File (ShareLink, preparing state), Clear Log
- [x] About: version, Source on GitHub link
- [x] Pull to refresh

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

