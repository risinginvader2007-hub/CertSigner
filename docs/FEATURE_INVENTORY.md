# CertSigner feature inventory (regression checklist)

Baseline: tag `pre-ui-overhaul` (commit `41316d2`, release build 24).
Every item below must still exist and behave the same after each UI sub-stage.
`[x]` = verified present in code after the stage named in the table at the bottom; device checks are listed separately.

## App shell
- [ ] App launches into Home tab; stores wired at launch (certificates, library, signed apps, queue, server certs, sources, toasts, router, importer)
- [ ] Tabs: Home, Library, Sources, Settings (+ Search tab on iOS 26)
- [ ] iOS 26: native Liquid Glass TabView, Search tab as separate glass button, tab bar minimises on scroll down
- [ ] iOS 16–25: custom floating glass tab bar (safe-area inset), hides while keyboard is up, tabs stay alive and cross-fade
- [ ] Library tab badge = signed apps expiring/expired
- [ ] Haptic on tab switch
- [ ] Appearance (System/Light/Dark) and accent colour applied app-wide
- [ ] SF Rounded font everywhere
- [ ] Toast overlay (success / error / warning / info), auto-dismiss ~2.8 s, tap to dismiss
- [ ] "Open in" / Share → CertSigner: `.ipa` → import + review sheet; `.p12`/`.pfx`/`.mobileprovision` → certificate import sheet; unsupported / unreadable → error toast
- [ ] Root sheets: certificate import, Review & Sign (from imports), Install (auto-install after signing)

## Home
- [ ] Stat cards: Certificates count, Signed apps count, Days left on active certificate (warning tint when attention needed)
- [ ] "Needs attention" banner (expiring/expired apps and/or active certificate) → opens Library filtered to attention items
- [ ] Importing card with spinner while an IPA is being imported
- [ ] Import IPA drop zone: tap → Files picker (`.item`), drag & drop an IPA, highlight while drag-over
- [ ] Quick Sign row: requires a certificate (else toast + opens certificate import), picks IPA and auto-signs with defaults
- [ ] Active certificate card: status badge, lifetime progress bar, expiry countdown, Switch menu (when >1 cert), Manage → Certificates
- [ ] No-certificate card with Add button
- [ ] Pull to refresh (reload certificates + signed apps)

## Library
- [ ] Empty state "Your library is empty" with action → Home
- [ ] Signing section: live jobs (step, progress ring/percentage), "Tap for log", failed jobs with reason, Retry / Remove, swipe to remove
- [ ] Signing log sheet per job (live log, steps, result; Retry for failed; Done)
- [ ] Attention-only filter banner ("Showing items that need attention. Tap to show all.")
- [ ] Signed Apps section: icon, name, version, certificate used, status badge, expiry countdown
- [ ] Row actions: Install, Re-sign, Share (ShareLink); swipe left Delete (with confirmation), swipe right Re-sign
- [ ] Sort (date / name / expiry), Status filter, Certificate filter, Clear Filters, "No signed apps match your filters"
- [ ] Search signed apps (inline `.searchable` on iOS 16–25)
- [ ] Pull to refresh
- [ ] Install sheet from a row
- [ ] Signed app detail: details card, Install, Re-sign, Share, Delete (confirmation), "App removed" state

## Review & Sign sheet
- [ ] Header: icon, name, bundle ID, version badge, size badge, extension count badge
- [ ] No-certificate card → Add Certificate (dismisses, opens import)
- [ ] Certificate picker + status/type badges + App ID row
- [ ] Pre-sign checks list (pass / fail / unknown icons, title, detail)
- [ ] Options: display name, keep original bundle ID toggle (+ bundle ID field when off), version, remove extensions (when any), remove Watch app (when present)
- [ ] After Signing: "Install when done" toggle (also persists the setting)
- [ ] Error list; Sign button disabled + shake when issues; "Fix the issues above" label
- [ ] Quick Sign / Sources GET: auto-start when checks pass, warning toast otherwise
- [ ] Cancel; staged IPA discarded if the sheet closes without signing
- [ ] On sign: queue job, toast "Signing…", switch to Library, dismiss

## Install sheet
- [ ] Header with app icon, bundle ID, version, method description
- [ ] Status icon per phase, status text (incl. transfer %), stage list (server → prompt → transfer → install) with progress bar
- [ ] Troubleshooting tips on failure, live log, Try Again, Install Settings, Done / Cancel
- [ ] One app-wide install session (re-shown sheet keeps the running install)

## Certificates
- [ ] List with glyph, nickname, team, status; context menu Set as Active / Delete; swipe delete (confirmation)
- [ ] Empty state "No certificates" + import action; Import certificate toolbar button; pull to refresh
- [ ] Import sheet: nickname, .p12 picker, .mobileprovision picker, password, Import (validates password, keychain), Cancel; prefilled from shared files
- [ ] Detail: Set as Active, This Device check (UDID in profile / Open Settings), Provisioning Profile, Signing Certificate (matches profile), Password (Change), Devices, Entitlements, Rename (alert), Change Password (alert), Delete (confirmation), "Certificate removed" state

## Sources
- [ ] Empty state + Add Source; toolbar + and Edit (reorder)
- [ ] All Apps row (count) → combined searchable list
- [ ] Source rows: icon, name, app count / updated time, refresh spinner, error text; swipe Remove / Refresh; context menu Refresh / Copy Source URL / Remove
- [ ] Add Source sheet: URL field, Paste from Clipboard, Add (validates, loading state, error + shake), Cancel
- [ ] Source page: header (icon, host, subtitle, error, app count, Website link), search, pull to refresh
- [ ] App rows with GET pill → download (progress ring, tap to cancel) → sign & install
- [ ] App detail: header badges, Get / Download & Review, download progress card (bytes, speed, Cancel), What's New, About (More/Less), Screenshots, Versions (menu: Sign & Install, Download & Review, Copy Download Link; show all), Information
- [ ] Auto refresh every 30 min on appear

## Search (iOS 26 tab)
- [ ] Signed apps, Sources apps, Certificates sections; empty prompt; no-results text; navigation to detail screens

## Settings
- [ ] Certificates section: active picker, list link, Add Certificate
- [ ] Signing: Install after signing, Delete original IPA, Remove extensions by default, Keep bundle ID by default
- [ ] Install: Install Method & Server → method picker, backloop.dev update, public cert status, My Certificate (hostname, PEM files, save/remove), tips
- [ ] This Device: UDID field, Clear UDID
- [ ] Appearance: Theme picker, Accent colour picker, App icon picker (Ocean / Sunset / Mint / Midnight)
- [ ] Storage: per-area usage, total, Clear Cache, Remove Unused Imported IPAs (confirmation)
- [ ] Diagnostics: Export Log File (ShareLink, preparing state), Clear Log
- [ ] About: version, Source on GitHub link
- [ ] Pull to refresh

## Sub-stage verification log
| Stage | CI run | Inventory re-checked |
|---|---|---|
| 0 — inventory | — | baseline |
