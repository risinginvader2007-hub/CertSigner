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
| 2 | Design system, tab bar, certificates manager, library UI (sample data) | ✅ |
| 3 | IPA import (Files, share sheet, URL), icon/metadata extraction, persistence | |
| 4 | zsign integration, signing pipeline with progress | |
| 5 | Local HTTPS server and install flow | |
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

### Library (sample data in Stage 2)
- Grid / list toggle and sort (date, name, size) from the top-left menu; search by name or bundle ID; pull to refresh; long-press to copy the bundle ID or delete.
- Tap an app for its detail page (zoom transition on iOS 18+). **Sign App** opens a *demo* of the signing progress screen (no real signing yet).

### Settings
- Theme (System / Light / Dark), accent colour, device UDID, clear cache, version info.

## Limits of a sideloaded app
- No UDID access (manual entry instead).
- No private APIs or special entitlements; everything uses public frameworks.
