# CertSigner

An on-device iOS signing and sideloading app (FlareStore / Feather style) for **your own certificates and your own devices**.
Built with SwiftUI (iOS 16+), compiled by GitHub Actions — no Mac needed.

## Get the IPA

**Direct link (always the newest build):**
https://github.com/risinginvader2007-hub/CertSigner/releases/latest/download/CertSigner.ipa

Open it in Safari on your iPhone, then share the downloaded file to FlareStore (or any signer) to install.

Every push to `main` rebuilds the app and replaces the `latest` release. The zipped copy is also kept under **Actions → run → Artifacts** (`CertSigner-ipa`).

## Architecture

```
Sources/
  App/         CertSignerApp (entry, environment objects), RootView (TabView), TabRouter
  Models/      Certificate, ProvisioningProfile (+ ProfileParser), LibraryApp, SigningStep
  Services/    CertificateStore, LibraryStore, Keychain, P12Inspector, DERCertificateParser,
               CacheService, Haptics   (plain Swift, no UI; unit-testable)
  Views/       Library, Sources, Certificates, Signed, Settings
  Components/  Theme, PrimaryButton, Card, StatusBadge, ProgressRing/ProgressBar,
               EmptyStateView, AppIconView, ToastView, Effects (shimmer, shake, checkmark)
  Extensions/  Formatting helpers
```

- **MVVM**: `@MainActor ObservableObject` stores injected as environment objects; views stay thin.
- **Storage**: certificates in `Documents/Certificates/<uuid>/` (`certificate.p12`, `embedded.mobileprovision`) plus `index.json`; p12 passwords in the Keychain (`p12-<uuid>`).
- **Signing (Stage 4)**: zsign vendored as a C++ target with an Objective-C++ wrapper, driven by a `SigningService` that reports `SigningStep` progress and log lines to `SigningProgressView`.
- **Install (Stage 5)**: local HTTPS server + `itms-services://` manifest.

## Roadmap

| Stage | Contents | Status |
|---|---|---|
| 1 | Skeleton + CI unsigned IPA | ✅ |
| 2 | Design system, tab bar, certificates manager, library UI | ✅ |
| 3 | IPA import (Files, share sheet, URL), icon/metadata extraction, persistence | ✅ (basic, shipped with 4) |
| 4 | zsign integration, signing pipeline with progress | ✅ |
| 5 | Local HTTPS server and install flow | ✅ |
| 6 | Signed apps list, re-sign, sources/repos | |
| 7 | Tweaks (dylib/.deb injection), settings polish, log export, app icons | |

## Features so far

### Certificates
- **Import**: Certificates tab → **+**. Pick your `.p12`, your `.mobileprovision`, enter a nickname (auto-filled from the profile) and the password.
  The password is checked against the `.p12` immediately; a wrong password shakes the button and shows an error.
- Each certificate shows its team, profile type (Development / Ad Hoc / Enterprise / App Store), a status badge (valid, expiring within 7 days, expired) and a lifetime bar.
- Tap a certificate for full details: profile info, signing certificate name and expiry, whether the `.p12` matches the profile, devices and entitlements.
- **Active certificate**: long-press → *Set as Active*, or the button on the detail screen.
- **UDID check**: sideloaded apps cannot read the device UDID (Apple restricts it). Paste your UDID in **Settings → This Device**; each certificate then shows whether this iPhone is in its profile.
- Certificates imported in Stage 1 are migrated automatically.

### Library
- **Add apps**: Library → **+** → *Import from Files* or *Download from URL* (direct HTTPS link to an .ipa), or share an .ipa from Files → **CertSigner**.
- Name, bundle ID, version, size, minimum iOS, extensions and the icon are read from the IPA.
- Grid / list toggle and sort (date, name, size) from the top-left menu; search; pull to refresh; long-press to copy the bundle ID or delete.

### Signing
- Open an app → **Sign App**. Pick a certificate, optionally change display name / bundle ID / version, remove app extensions or the Watch app.
- Pre-flight checks block signing with a clear message when: the bundle ID (or an extension's) doesn't match the profile's App ID, the certificate is expired, the .p12 isn't in the profile, or your UDID (from Settings) isn't in the profile.
  Explicit (non-wildcard) profiles pre-fill their exact bundle ID.
- Pipeline: **Unpacking** (unzip) → **Patching** (Info.plist edits, nested bundle IDs, `embedded.mobileprovision`) → **Signing** (zsign on-device; frameworks, dylibs and extensions first, main binary last; entitlements from the profile) → **Packaging** (re-zip). Live progress ring and log.
- The result lands in the **Signed** tab (date, certificate, expiry countdown). Share the IPA from there until on-device install arrives in Stage 5.

### Install
- **Signed → Install** (or **Install Now** right after signing). CertSigner starts a tiny server on the phone's loopback interface (never reachable from Wi-Fi), opens
  `itms-services://?action=download-manifest&url=…`, iOS shows its install prompt, then downloads the IPA from the local server. Status: server → prompt → transfer % → installing. The server stops ~15 s after the transfer (or on cancel / failure / 3-minute timeout).
- **Methods** (Settings → Install):
  - *Fully Local (HTTPS)*: manifest + IPA over HTTPS from the phone. iOS requires a publicly trusted certificate, so the server uses a hostname that resolves to 127.0.0.1:
    - **backloop.dev** (what Feather uses): `local.backloop.dev` → 127.0.0.1, certificate + key published at `https://backloop.dev/pack.json`. Free, but third-party and can lapse (it was expired on 2026-11-08).
    - **Your own domain** (most reliable): see below.
  - *Semi-Local*: IPA served over HTTP from the phone; only the manifest comes from `api.palera.in` (Feather's fallback). Needs internet, no certificate.
  - *Automatic* (default): Fully Local when a valid certificate exists, otherwise Semi-Local.

#### Using your own domain for Fully Local
1. Own a domain (e.g. `example.com`) with DNS you control (Cloudflare is easiest).
2. Add a DNS **A record** `install.example.com → 127.0.0.1` (no proxy / grey cloud).
3. Get a trusted certificate for it with a **DNS-01** challenge (HTTP challenges can't reach 127.0.0.1), e.g.
   `certbot certonly --manual --preferred-challenges dns -d install.example.com` or `acme.sh --issue --dns dns_cf -d install.example.com`.
4. Copy `fullchain.pem` and `privkey.pem` (unencrypted) to the iPhone's Files app.
5. Settings → Install → **Add My Own Certificate** → enter `install.example.com`, pick both files → Save.
6. Renew before it expires (Let's Encrypt: every 90 days) and re-import.

The signing engine is [zsign](https://github.com/zhlynn/zsign) (MIT), vendored in `Vendor/zsign` and built as the `ZSign` static library with OpenSSL 3; see `Vendor/README.md`.

### Settings
- Theme (System / Light / Dark), accent colour, device UDID, clear cache, version info.

## Limits of a sideloaded app
- No UDID access (manual entry instead).
- No private APIs or special entitlements; everything uses public frameworks.
