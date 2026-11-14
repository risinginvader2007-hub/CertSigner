# CertSigner status

Living document: update it whenever something is verified, shipped or found broken.
Last updated: **2026-11-14** (builds 88–101; in-app update, Sources and light-mode glows verified on iPhone).

## Snapshot

| | |
|---|---|
| Branches | `main` = `8fe2b35` (build 100); `ui-overhaul` = `main` + the update dot (branch build 101, not released) |
| Tags | `latest` (moved by CI to each release), `pre-ui-overhaul` = `41316d2` (rollback point, release build 24) |
| Latest release | "CertSigner (build 100)" from `8fe2b35`, published 2026-11-14 (same code as branch build 99) |
| CI at `8fe2b35` | Build IPA runs 99, 100 ✅ (app + web tests); Signing test run 74 ✅ (65/65 XCTests) |
| Web installer | https://risinginvader2007-hub.github.io/CertSigner/ — HTTP 200 on 2026-11-13 |
| Relay | https://get-certsigner.risinginvader2007.workers.dev — HTTP 200 on 2026-11-13 |
| `api.palera.in/genPlist` | HTTP 200 on 2026-11-13 (Semi-Local available) |
| backloop.dev certificate | **Expired 2026-10-29** (checked 2026-11-13). Fully Local works only with the owner's own domain certificate; Automatic falls back to Semi-Local |

## Verified

- **CI:** app builds (only the known warnings); 62/62 XCTests (at `5dcf580`); 8/8 web tests (WASM signing of the
  real IPA, relay logic, Playwright e2e in Chromium + WebKit incl. "no request contains the p12,
  password or key").
- **On the owner's iPhone:** the web page signs and installs CertSigner; earlier builds' signing,
  install (Semi-Local via palera), Sources, deletes and the UI in general; Compatibility mode with
  Husk; **in-app update build 95 → 96** (2026-11-14). Builds ≤ 94 can't self-update (read-only
  `OpenSSL.framework/OpenSSL` made zsign fail; fixed in `80e5e7f`). **Sources** one row per app,
  versions newest first (checklist 21), and **light-mode glows**, Glow intensity, light/dark
  cross-fade (checklist 18–19), both 2026-11-14.

## Implemented, NOT verified on a device

Ask the owner to test these (iPhone test checklist in `docs/FEATURE_INVENTORY.md`):

0. **Update dot** (branch build 101, checklist item 22): red dot on the Settings tab and Updates row
   from the cached check at launch; quiet re-check on launch / foreground (once a minute); skip,
   install and failed-check behaviour. The iOS 26 native tab bar uses an empty `.badge(Text(""))`,
   expected to render as a plain dot — not seen on a device yet.
0. **App icon change** (build 100, checklist item 3): no crash after the private call (the
   completion block now hops to main; cause in `docs/DECISIONS.md`); whether iOS 27.2 still shows
   the alert. Logs "Icon change: completion fired on main=…".
0. **Updater error cases** (checklist item 20, not yet tested): update sheet's error text,
   Share Log, certificate picker, retry; Skip This Build; a certificate from another team is
   refused.
1. **Web certificate hand-off** (build 87): re-sign on the page → Install → "Import Certificate into
   CertSigner" → Open → toast "Imported … Ready to sign". Needs installed app ≥ build 87. This was
   the owner's last bug report ("No certificates yet" after installing from the web).
2. **Install rewrite:** CapCut, delete + reinstall, install twice, dismiss the prompt (stall UI with
   Reopen Prompt / Try Again), already-installed hints, LaunchServices confirmation (private API
   availability on device unknown).
3. **App icon change without the system alert** (private API).
4. **Accent blends** and the custom-blend UI; iOS 26 sheet concentric corners (only seen in a
   simulator screenshot).
5. **Performance at 120 Hz** on an iPhone 16 Pro Max (Instruments never run — no Mac).
6. **First-launch "Signed with …, expires …" toast** on a real install.
7. Whether the relay's Rate Limiting binding actually enforces 5/60 s on the free plan.

## Incomplete

- **Updater:** no rollback copy of the current app before updating; `update.json` is not signed.
- **Glow intensity** changes apply without animation.
- **Design audit leftovers:** Settings rows and Home not rebuilt from `ListRow` / `ErrorState`;
  ~14 `.system(size:)` icon fonts and some deliberate colour literals (orange/pink Quick Sign tile);
  no contrast audit; no iPhone SE / Pro Max / iPad layout pass; no FPS measurement.
- **Requested features that don't exist:** "Signed Versions to Keep" setting; grid / layout / font
  settings; Sources filters and sort.
- **Undo** exists only for signed apps (certificates would need Keychain password restore).
- **Web installer vs original spec:** no explicit pruning of disallowed entitlements (profile's
  entitlements used as-is); Keychain access group after a bundle-ID rewrite not tested; max upload
  25 MB instead of 50 MB; desktop browsers can sign and Download, but Install only works on iOS.
- **CI can't redeploy the Worker** until the owner adds `CLOUDFLARE_API_TOKEN` (optional).

Known failing: nothing.

## Remaining work (priority)

1. On-device check of the icon change (build 100) and the update dot (build 101), then release 101.
1. On-device check of the updater's error cases (checklist item 20).
2. On-device confirmation of the build 87 web import.
3. On-device verification of the install rewrite.
4. Verify alert-free icon change, accent blends UI and 120 Hz performance.
5. Decide what to do about backloop.dev's expired certificate (Fully Local / Automatic).
6. Optional: let CI deploy the Worker (owner adds the secret in GitHub; never via chat).
7. Updater hardening: rollback copy before updating, signed `update.json`.
8. Finish the design audit leftovers; animate Glow intensity changes.
9. Web installer spec gaps (above).

## Build → commit map (published releases from `main`)

Build number = "Build IPA" run number, which also counts branch and web-only runs, so it skips.

| Build | Commit | Date | Notes |
|---|---|---|---|
| 1 | `9e8eb20` | 11-07 | Starter project |
| 17 | `bc3a717` | 11-08 | Sources (AltStore-style), GET |
| 24 | `41316d2` | 11-08 | `pre-ui-overhaul` |
| 36 | `0f9734f` | 11-08 | UI overhaul stages 1–6 done |
| 38 | `2b7ea00` | 11-08 | Instant deletes, install auto-close toggle |
| 40 | `33e839b` | 11-08 | Certificate details black screen fixed |
| 42 | `74f16a0` | 11-08 | Raw Profile Data |
| 45 | `5b94758` | 11-09 | Signing modes, signing log, XCTest target |
| 48 | `c1e3e12` | 11-09 | Living background, glass shine |
| 51 | `51a626d` | 11-09 | Brighter background |
| 53 | `a237b34` | 11-09 | Sources refresh fix, certificate picker sheet |
| 55 | `73c693f` | 11-09 | Delete animation redesign, Undo |
| 61 | `a249bb2` | 11-09 | Four-part design pass, DESIGN.md |
| 67 | `caac2fb` | 11-09 | Five-issue pass (shapes, icon, install, performance, Liquid Glass) |
| 70 | `b2be2f6` | 11-10 | Accent blends |
| 84 / 85 | `c16a527` | 11-10 | Web installer, first-launch signature toast |
| 87 | `59dcece` | 11-10 | Web certificate hand-off (`certsigner://import`) |
| 90 | `7e747bb` | 11-13 | Light-mode glows, Glow intensity setting |
| 93 | `fecc71c` | 11-13 | In-app updater (`update.json`, update sheet) |
| 94 | `e4c2b1c` | 11-13 | Sources: one row per app (duplicates fixed) |
| 95 / 96 | `5dcf580` | 11-13 | Update signing fix (read-only files made writable); 96 = manual run to test the updater |
| 98 | `dde6b8d` | 11-14 | Icon-change diagnostics (found the SIGTRAP after the private call) |
| 100 | `8fe2b35` | 11-14 | Icon change: nonisolated completion block (crash fix; = branch build 99) |

Full list: `gh run list -R risinginvader2007-hub/CertSigner -w "Build IPA" -b main`.

## Corrections to the Hermes handover (audit 2026-11-13)

- The web certificate hand-off is a single commit, `59dcece` (message "WebImport tests"), not
  several commits after `c16a527`.
- The build → commit mapping is recoverable from `gh run list` (table above), contrary to §11.
- backloop.dev's certificate is expired (not mentioned in the handover).
- Node is not on the Bash tool's PATH in the Claude Code environment.
- A local `latest` tag may lag behind GitHub's; trust `gh release view latest`.
- `DESIGN.md` (and commit `5bf84b8`'s message) said the background holds still during accent
  changes; the code keeps drifting and redraws for the fade. `DESIGN.md` was corrected.

## Unknown history

- The owner's original numbered specs exist only as summaries.
- The exact content of one reverted, abandoned change (believed to be around background motion).
