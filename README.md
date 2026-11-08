# CertSigner

An on-device iOS signer for **your own certificates, your own devices and IPAs you already have**.
Import an IPA from Files, review it, sign it on the phone with zsign, and install it with the system install prompt.
SwiftUI (iOS 16+), built by GitHub Actions — no Mac needed.

## Get the app

**Direct link (always the newest successful build):**
https://github.com/risinginvader2007-hub/CertSigner/releases/latest/download/CertSigner.ipa

Open it in Safari on your iPhone, then share the file to FlareStore (or any signer) to install CertSigner itself.

### From GitHub Actions
1. Push to `main`, or open **Actions → Build IPA → Run workflow**.
2. Wait for the green tick (about 2–4 minutes).
3. Every green build on `main` also replaces the **latest** release, so the direct link above updates automatically.
4. Or open the run, scroll to **Artifacts**, download **CertSigner-ipa** and unzip it to get `CertSigner.ipa`.

## Using CertSigner

### 1. Add a certificate (Settings → Certificates, or the Home card)
- Tap **Add Certificate**, pick your `.p12`, your `.mobileprovision`, enter a nickname and the `.p12` password.
- The password is checked straight away and stored only in the iOS Keychain.
- Certificate details: team, profile type, App ID, devices, entitlements, expiry, and whether the `.p12` is in the profile.
- **Switch** the active certificate from Home or Settings. Sharing a `.p12` / `.mobileprovision` to CertSigner opens the import sheet too.
- Paste your **UDID** in Settings → This Device so CertSigner can check your iPhone is in each profile (sideloaded apps can't read it themselves).

### 2. Home
- Stat cards: certificates, signed apps, days left on the active certificate.
- **Needs attention** banner when a signed app or the active certificate expires within 7 days (or has expired); tap it to see those apps in Library.
- **Import IPA**: tap to browse Files, drop an `.ipa` on it, or share an `.ipa` from Files → **CertSigner**.
- **Quick Sign**: pick an IPA and queue it immediately with your defaults (if the pre-sign checks pass).

### 3. Review & Sign
- Shows the icon, name, bundle ID, version, size and extensions read from the IPA.
- Options: display name, version, **keep original bundle ID** or set a new one (explicit profiles pre-fill their exact App ID), remove app extensions, remove the Watch app.
- **Pre-sign checks**: certificate not expired, `.p12` matches the profile, bundle ID (and extensions) allowed by the App ID, this iPhone's UDID in the profile. Failing checks block signing with a clear reason.
- **Install when done** starts the install prompt automatically after signing.

### 4. Library
- **Signing**: live jobs with step progress (Unpacking → Patching → Signing → Packaging) and a progress ring. Tap a job for the live log. Failed jobs show the reason with **Retry** / **Remove**. Jobs survive relaunch (an interrupted job is marked failed so you can retry).
- **Signed Apps**: icon, version, certificate used, status badge (valid / expiring / expired) and expiry countdown, with **Install**, **Re-sign** (with the active certificate, replaces the old copy) and **Share**. Swipe left to delete, right to re-sign. Search, sort (date, name, expiry) and filter (status, certificate).
- The Library tab badge counts signed apps that are expiring or expired.

### 5. Install
- CertSigner serves the signed IPA from the phone's loopback interface and opens `itms-services://`; iOS shows its install prompt.
- **Settings → Install** picks the method: *Automatic* (default), *Fully Local (HTTPS)* or *Semi-Local*.
  - Fully Local needs a trusted certificate for a hostname that resolves to 127.0.0.1: the public backloop.dev certificate (when valid) or your own domain (see below).
  - Semi-Local serves the IPA locally and gets only the small manifest from `api.palera.in` (needs internet).

#### Using your own domain for Fully Local
1. Add a DNS **A record** such as `install.example.com → 127.0.0.1` (Cloudflare: proxy off).
2. Get a certificate with a **DNS-01** challenge, e.g. `certbot certonly --manual --preferred-challenges dns -d install.example.com`.
3. Put `fullchain.pem` and `privkey.pem` (unencrypted) in Files, then Settings → Install → **Add My Own Certificate**.
4. Renew before it expires (Let's Encrypt: 90 days) and import again.

### 6. Settings
Certificates, signing defaults (remove extensions, keep bundle ID), install after signing, delete original IPA after signing, install method, UDID, appearance (system / light / dark), accent colour, **app icon** (Ocean, Sunset, Mint, Midnight), storage usage with Clear Cache and Remove Unused Imports, **Export Log File**, and About.

## Architecture

```
Sources/
  App/         CertSignerApp (stores wired in init), RootView (floating tab bar shell)
  Models/      Certificate, ProvisioningProfile, LibraryApp, SigningOptions/SignedApp, SigningStep, InstallMethod
  Services/    CertificateStore, LibraryStore (staged imports), SignedAppsStore, SigningQueue, SigningPipeline (worker),
               AppBundlePatcher, SigningValidator, IPAInspector, ZSignService, InstallSession, LocalHTTPServer,
               ServerCertificateStore, Keychain, P12Inspector, DERCertificateParser, AppLog, StorageService
  Views/       Home, Library, Certificates, Install, Settings
  Components/  Theme, FloatingTabBar, PrimaryButton, Card, StatusBadge, ProgressRing/Bar, EmptyStateView,
               AppIconView, ToastView, DocumentPicker, Effects (shimmer, shake, checkmark draw-in, zoom transition)
  Resources/   Assets.xcassets (original app icons)
Vendor/        zsign (MIT, patched for iOS) + Objective-C++ bridge + TLS helper — see Vendor/README.md
```

Storage lives in the app's Documents folder: `Certificates/`, `Library/` (staged imports), `Signed/`, `Signing/queue.json`, `Server/`, `Logs/`.

## Limits of a sideloaded app
- No UDID access (paste it in Settings).
- CertSigner can't see whether iOS finished installing; it reports up to the point iOS has the IPA.
- No private APIs or special entitlements.
