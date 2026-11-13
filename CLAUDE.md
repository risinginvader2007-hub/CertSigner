# CertSigner — instructions for Claude Code

CertSigner is a sideloaded SwiftUI app (iOS 16+) that re-signs IPAs **on the iPhone** with the
user's own `.p12` + `.mobileprovision`, using a vendored, patched **zsign** (C++ / OpenSSL), and
installs them through `itms-services` served by a web server inside the app. There is also a
**web installer** (GitHub Pages + zsign compiled to WebAssembly + a Cloudflare Worker relay) that
signs CertSigner itself in Safari.

Single developer (GitHub `risinginvader2007-hub`), who tests on a real iPhone.

## Docs map (read the relevant one before working in an area)

| File | What it holds |
|---|---|
| `docs/STATUS.md` | **Current state**: verified / unverified on device / incomplete, prioritised remaining work, build → commit map. Update it when that changes. |
| `docs/ARCHITECTURE.md` | Source tree, signing / install flows, web installer, relay, CI, infrastructure. |
| `docs/DECISIONS.md` | Technical decisions with rejected alternatives, and pitfalls not to repeat. |
| `DESIGN.md` | Design tokens, components, UI rules, performance rules. Follow it for any UI work. |
| `docs/FEATURE_INVENTORY.md` | Every user-visible feature (regression checklist) + iPhone test checklist. |
| `README.md` | User guide and the web installer's setup. |
| `Vendor/README.md` | zsign source commit and every local patch ("CertSigner patch"). |
| `docs/history/HERMES_HANDOVER.md` | Archived handover from the previous agent (2026-11-10). History only; may be stale. |

## Environment facts

- **No Mac, no Xcode, no Swift locally** (Windows 11). Every Swift compile and test runs on
  GitHub Actions. A change is only "builds" when CI says so.
- XcodeGen: `project.yml` is the source of truth; there is no checked-in `.xcodeproj`.
  `Support/Info.plist` is generated.
- `gh` is installed and authenticated. In the Bash tool add it to PATH first:
  `export PATH="$PATH:/c/Program Files/GitHub CLI"`. Node is not on the Bash tool's PATH here.
- Repo files use LF line endings.

## Workflow (the owner's standing process)

1. Work on branch `ui-overhaul`. `main` is what CI publishes.
2. Small commits, **one issue per commit**. Commit / push only when the owner asks.
3. Push, get the CI the change needs green (see "CI efficiency" below), then release with a fast-forward:
   `git checkout main && git merge --ff-only ui-overhaul && git push origin main && git checkout ui-overhaul`
4. Each delivery ends with: the list of changed files, what is verified vs not, and an
   **iPhone test checklist**.

```bash
export PATH="$PATH:/c/Program Files/GitHub CLI"; R=risinginvader2007-hub/CertSigner
gh workflow run build.yml -R $R --ref ui-overhaul                 # app build on the branch
gh workflow run build.yml -R $R --ref ui-overhaul -f web_only=true # web only (uses latest release IPA)
id=$(gh run list -R $R -w "Build IPA" -b ui-overhaul -L 1 --json databaseId -q '.[0].databaseId')
timeout 390 gh run watch $id -R $R --exit-status --interval 20 >/dev/null; echo $?
# new compiler warnings/errors (filters the known pre-existing ones)
gh run view $id -R $R --log | grep -E "\.swift:[0-9]+:[0-9]+: (error|warning)" | grep -v "FileDownloader\|LocalHTTPServer.swift:1[01][0-9]"
# XCTests ("Signing test" runs on every push to main / ui-overhaul)
gh run view <id> -R $R --log | grep -E "Test Case .*(passed|failed)|Executed [0-9]+ tests"
```

The release title "CertSigner (build N)" uses the **Build IPA run number**, which counts every run
(branch and web-only runs too), so build numbers skip.

## CI efficiency (standing rule)

Be conservative with CI. Before starting a workflow, decide whether the change actually needs it,
and say briefly why when a run is expensive or could be redundant.

| Change | CI |
|---|---|
| Documentation only | None. |
| UI only | The relevant UI tests; a Build IPA only when the owner needs it for device verification. |
| Isolated logic | Targeted tests first, not the full suite. |
| Signing pipeline / certificates | The relevant signing tests. |
| Release preparation | The checks that validate the exact release commit. |

- No duplicate runs. Never re-run successful tests for an unchanged commit.
- Don't run the full suite to verify a small, isolated fix when targeted tests are enough.
- Don't start Build IPA just because the Signing test ran, or the other way round.
- Keep the essential release safety checks. Never claim something was tested when it wasn't.
- Be aware the workflows also start **automatically**: "Signing test" on every push to `main` or
  `ui-overhaul` (full suite; there is no input for running a subset), and "Build IPA" on every push
  to `main` (that run publishes the release). Count those before dispatching anything extra, and
  don't dispatch a second run of what a push already started.

## Rules for any change

- Don't break, remove or move any existing feature, button or setting (check
  `docs/FEATURE_INVENTORY.md`).
- Keep: the shared `AppButtonStyle`, sliding selection, the one delete animation, haptics,
  Liquid Glass on iOS 26, and Reduce Motion support everywhere. Follow `DESIGN.md`.
- Keep both GitHub Actions workflows green. Prefer deterministic tests; never timing races.
- Be explicit about what was verified on CI vs what still needs the iPhone.
- Short, plain replies; bug reports arrive as plain observations ("colours are very faint").
- **Secrets:** never ask the owner to paste tokens, passwords or keys into chat. Cloudflare /
  GitHub secrets are added by the owner in the web UI or through OAuth. Test p12 passwords in the
  repo are throwaway fixtures. Don't commit personal data (the repo is public).

## Pitfalls that already cost builds (details in `docs/DECISIONS.md`)

- Use `ProfileParser.parse(data:)` — `ProvisioningProfile.parse` does not exist.
- Never publish theme state per frame; `ThemeStore.apply` publishes once inside one animation.
- Keep zsign patch 4 (`Vendor/zsign/common/fs.cpp`, `__EMSCRIPTEN__` only) or WASM signing
  silently produces unsigned binaries.
- Quote YAML step names that contain a colon, or the workflow file breaks ("no trigger").
- Playwright is pinned to 1.65.0. Signing fixtures need a CA-issued leaf, not a self-signed one.
- Private APIs (`_setAlternateIconName:`, `LSApplicationProxy`, `LSApplicationWorkspace`) must stay
  guarded with `responds(to:)` and optional.
- Install phases advance only on server events, never on app-lifecycle notifications.
