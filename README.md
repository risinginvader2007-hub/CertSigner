<div align="center">

<img src="web/site/icon.png" alt="CertSigner app icon" width="112" height="112">

# CertSigner

**Sign and install IPAs on your iPhone, with your own certificate.**

[![Build IPA](https://github.com/risinginvader2007-hub/CertSigner/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/risinginvader2007-hub/CertSigner/actions/workflows/build.yml)
[![Signing test](https://github.com/risinginvader2007-hub/CertSigner/actions/workflows/signing-test.yml/badge.svg?branch=ui-overhaul)](https://github.com/risinginvader2007-hub/CertSigner/actions/workflows/signing-test.yml)

[**Install from Safari**](https://risinginvader2007-hub.github.io/CertSigner/) ·
[**Download the IPA**](https://github.com/risinginvader2007-hub/CertSigner/releases/latest/download/CertSigner.ipa) ·
[**Report an issue**](https://github.com/risinginvader2007-hub/CertSigner/issues)

</div>

CertSigner is a SwiftUI app that signs IPA files directly on the device. You bring a `.p12`
certificate and a matching `.mobileprovision` profile; CertSigner unpacks the app, signs it, and
hands it to the iOS install prompt. No computer is needed for day-to-day use.

A companion web page installs CertSigner itself from Safari, signing it inside the browser.

> CertSigner does not provide certificates, profiles or apps. Use certificates you are entitled to
> use, on devices covered by your profile, with apps you have the right to install.

## Contents

[Features](#features) ·
[Requirements](#requirements) ·
[Installation](#installation) ·
[Usage](#usage) ·
[Updating](#updating) ·
[Install methods](#install-methods) ·
[Privacy and security](#privacy-and-security) ·
[Known limitations](#known-limitations) ·
[Troubleshooting](#troubleshooting) ·
[Building](#building-from-source) ·
[Web installer](#web-installer) ·
[Project structure](#project-structure) ·
[Contributing](#contributing) ·
[License](#license)

## Features

**Signing**
- On-device signing with a vendored build of [zsign](https://github.com/zhlynn/zsign) and OpenSSL. App extensions, frameworks and dylibs are signed along with the app.
- Two modes, selectable per app: **Compatibility** keeps the original bundle ID; **Strict** enforces the profile's App ID.
- Change the display name and version, or remove the Watch app. Strict mode can also change the bundle ID and remove app extensions.
- Pre-sign checks for expiry, the certificate and profile pairing, the App ID (Strict) and the device UDID.
- A persistent job queue with live progress, retry, and a shareable log per job.

**Certificates**
- Import several certificate and profile pairs, and switch the active one at any time.
- Inspect team, profile type, App ID, devices, entitlements, expiry and raw profile data.
- Warnings when the active certificate or a signed app has expired or expires within 7 days.

**Library and sources**
- Import from Files, the share sheet, or drag and drop.
- Install, re-sign, share, search, sort and filter signed apps. Deleting one can be undone for 5 seconds.
- Add HTTPS app sources in JSON format, browse apps and version history, and download, sign and install from one place.

**App experience**
- Automatic detection of new CertSigner builds and in-app updating.
- Light and dark appearance, solid or blended accent colours, four app icons, and Reduce Motion and Reduce Transparency support.
- Liquid Glass interface on iOS 26 and later, with material fallbacks on earlier versions.
- Storage dashboard and exportable diagnostic log.

## Requirements

| | |
|---|---|
| **System** | iOS 16.0 or later |
| **Device** | iPhone. The build also targets iPad, but its layout has not been verified there. |
| **Certificate** | A `.p12` containing the private key, and its password |
| **Profile** | A `.mobileprovision` that includes that certificate |
| **Device registration** | Your UDID must be in the profile, unless the profile covers all devices |
| **Network** | Needed for sources, updates and some [install methods](#install-methods); signing a local IPA is offline |

An explicit App ID profile is enough to install CertSigner. A **wildcard** profile lets Strict mode
sign apps under different bundle IDs. See [Known limitations](#known-limitations) before signing
several apps with one profile.

## Installation

### From Safari (recommended)

1. Open **[Get CertSigner](https://risinginvader2007-hub.github.io/CertSigner/)** in Safari on your iPhone.
2. Choose your `.p12`, enter its password, and choose your `.mobileprovision`.
3. Tap **Check & Sign**, then **Install CertSigner**, and confirm the iOS prompt.
4. If iOS says the developer is not trusted, open **Settings › General › VPN & Device Management**, select your certificate and tap **Trust**.
5. Return to the page and tap **Import Certificate into CertSigner** to add the same certificate to the app.

### From the IPA

Every successful build of `main` publishes an unsigned
[CertSigner.ipa](https://github.com/risinginvader2007-hub/CertSigner/releases/latest/download/CertSigner.ipa).
Sign and install it with your usual signing workflow. iOS cannot install the unsigned file as it is.

## Usage

### 1. Add a certificate

Go to **Settings › Certificates › Add Certificate**, select the `.p12` and `.mobileprovision`, and
enter a nickname and password. You can also open either file in CertSigner from the share sheet.

Optionally paste your UDID in **Settings › This Device** so CertSigner can check it against your
profiles. iOS does not let the app read the UDID itself.

### 2. Import and sign an app

1. On **Home**, tap **Import IPA**, or share an `.ipa` to CertSigner.
2. Choose the certificate, signing mode and options in **Review & Sign**.
3. Resolve any failing checks, then tap **Sign**.

**Quick Sign** skips the review and uses your defaults when all blocking checks pass.

| Mode | Bundle ID | App ID mismatch | Extensions |
|---|---|---|---|
| **Compatibility** (default) | Kept | Allowed; a warning appears when the app would share another App ID's identity | Kept and signed |
| **Strict** | Kept or changed to fit the profile | Blocks signing | Kept if they match, or removed |

Strict mode refuses to give another app CertSigner's own bundle ID, since installing it would
replace CertSigner.

### 3. Install and manage

Signed apps appear in **Library**, with their certificate and expiry. Tap **Install** and confirm the
iOS prompt; use **Re-sign** to renew an app with the active certificate. Enable **Install after
signing** in Settings to open the prompt automatically.

### 4. Use sources

In **Sources**, tap **+** and enter an `https://` URL that returns a JSON app catalogue. **GET**
downloads, signs and installs using your defaults; **Download & Review** opens the review first.
Earlier versions are listed on each app's page. CertSigner does not include or endorse any source.

## Updating

When **Check for updates automatically** is on (the default), CertSigner checks this repository's
latest release at launch and when it returns to the foreground, at most once a minute. A newer build
is indicated on Home, the Settings tab and the **Updates** row.

Updating downloads the build, verifies its size, SHA-256, bundle ID and build number against the
release's `update.json`, signs it with your certificate and opens the iOS install prompt.

- The certificate must belong to the **same team** that signed the installed copy.
- The bundle ID is kept, so iOS updates in place and preserves your data.
- **Skip This Build** hides a release until a newer one is published.

The checksum detects a damaged or mismatched download. `update.json` is not itself signed, and there
is no automatic rollback to a previous build.

## Install methods

Choose one in **Settings › Install Method & Server**. In every method, the signed IPA is served from
the device's loopback interface and is not uploaded.

| Method | How it works |
|---|---|
| **Automatic** (default) | Uses Fully Local when a valid server certificate is available, otherwise Semi-Local |
| **Fully Local (HTTPS)** | Serves the manifest and the IPA from the iPhone; needs a trusted certificate for a hostname that resolves to `127.0.0.1` |
| **Semi-Local** | Serves the IPA from the iPhone; gets the small install manifest from `api.palera.in`, so it needs internet access |

Fully Local can use the public `backloop.dev` certificate when it is valid. **As of 24 November 2026
the published certificate is expired** (29 October 2026), so Automatic uses Semi-Local unless you add
your own certificate.

<details>
<summary><strong>Use your own domain for Fully Local</strong></summary>

1. Create a DNS **A record** such as `install.example.com` pointing to `127.0.0.1`.
2. Obtain a trusted certificate using a DNS challenge, for example:

   ```bash
   certbot certonly --manual --preferred-challenges dns -d install.example.com
   ```

3. Copy `fullchain.pem` and an unencrypted `privkey.pem` to Files on the iPhone.
4. In **Settings › Install Method & Server**, tap **Add My Own Certificate**.
5. Repeat the import when the certificate is renewed.

</details>

## Privacy and security

- **Certificates and profiles** are stored in the app's own container. Passwords are stored in the iOS Keychain, limited to this device and available after its first unlock.
- **No accounts, analytics or advertising** are included.
- **The install server** listens on loopback only, with a new port and a random path for every attempt.

CertSigner contacts these services:

| Service | When | What it receives |
|---|---|---|
| GitHub | Update checks and downloads | Standard requests for release files |
| `api.palera.in` | Semi-Local installs | App name, bundle ID, version and a local `127.0.0.1` URL |
| `backloop.dev` | Fetching its public server certificate | A standard request |
| Sources you add | Refreshing and downloading | Standard requests to the source and the hosts it links to |

> [!WARNING]
> Apps signed with the same App ID and entitlements can share Keychain access. An app signed with
> the profile that signed CertSigner may be able to read the certificate passwords CertSigner saved.
> Only sign apps you trust with that profile, or use a separate App ID.

## Known limitations

- **Entitlements come from the profile.** They are copied unchanged to the app and its extensions; an app's original entitlements are not preserved. Push notifications, App Groups, iCloud and similar features may not work, including in extensions.
- **Shared identity.** Apps signed with one explicit App ID profile share that identity, whatever their bundle ID. This can affect the Keychain, App Groups and system features such as opening an app from Now Playing. Use profiles with different App IDs to keep apps separate.
- **Wildcard App IDs** are written to the signature as they appear in the profile, not expanded for each app.
- **No verification pass.** The app logs the entitlements it reads back from each signed bundle, but does not run a full signature verification before packaging.
- **Revocation is not checked.** iOS decides whether a certificate is still accepted.
- **Installation needs confirmation.** iOS always shows its own prompt. Final confirmation that an app installed relies on private system APIs and may be unavailable.
- **Changing the app icon** can show the standard iOS alert.

## Troubleshooting

| Problem | What to check |
|---|---|
| **Unable to install** | The UDID is in the profile, the certificate is not expired or revoked, and there is enough free storage |
| **An app with the same ID exists** | If a different team signed the installed copy, delete it first. This also deletes its data |
| **Untrusted developer** | Trust the certificate in **Settings › General › VPN & Device Management** |
| **The install prompt does not appear** | Tap **Reopen Prompt** or **Try Again**. Check your connection for Semi-Local, or the server certificate for Fully Local |
| **Strict mode reports a mismatch** | Use a matching or wildcard profile, remove unsupported extensions, or use Compatibility |
| **Wrong password** | Re-enter the `.p12` password in the certificate's details |
| **A source does not load** | Use an `https://` URL that returns JSON. Links using plain `http://` are not supported |
| **Update refused** | Use a certificate from the team that signed the installed copy, with a profile that allows its bundle ID |

Logs can be shared from signing jobs and the install sheet, or with **Settings › Diagnostics ›
Export Log File**. Review a log before posting it: it can contain app names, bundle IDs, certificate
names and team identifiers. Never post a `.p12`, its password or a provisioning profile.

## Building from source

Building requires macOS with Xcode, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode
project is generated from [`project.yml`](project.yml); Swift Package Manager resolves the dependencies.

```bash
git clone https://github.com/risinginvader2007-hub/CertSigner.git
cd CertSigner
brew install xcodegen
xcodegen generate
```

Create an unsigned IPA:

```bash
xcodebuild -project CertSigner.xcodeproj -scheme CertSigner \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir Payload
cp -r build/Build/Products/Release-iphoneos/CertSigner.app Payload/
zip -r CertSigner.ipa Payload
```

A local build has build number 1 unless you also pass `CURRENT_PROJECT_VERSION=<number>`.

<details>
<summary><strong>Run the signing tests</strong></summary>

Fixture generation also requires Homebrew's `openssl@3`. Replace `<simulator-udid>` with an available
iPhone simulator.

```bash
bash .github/scripts/make-signing-fixtures.sh "$PWD/build/fixtures"
TEST_RUNNER_CS_FIXTURES="$PWD/build/fixtures" xcodebuild test \
  -project CertSigner.xcodeproj -scheme SigningTests \
  -destination "id=<simulator-udid>" -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

The self-update tests also need a released `CertSigner.ipa` saved as
`build/fixtures/certsigner.ipa`. The source refresh tests use the network.

</details>

### Continuous integration

| Workflow | Runs on | Purpose |
|---|---|---|
| [Build IPA](.github/workflows/build.yml) | Pushes to `main` or `master`, or manually | Builds the app and web signer, runs the web tests, and on `main` publishes the release and website |
| [Signing test](.github/workflows/signing-test.yml) | Pushes to `ui-overhaul`, or manually | Runs the app tests in a simulator and checks the signed output |

Release build numbers come from the Build IPA run number, so they are not always consecutive.

## Web installer

[Get CertSigner](https://risinginvader2007-hub.github.io/CertSigner/) runs the same vendored zsign
code, compiled to WebAssembly, in a Web Worker.

- The `.p12`, password and profile are **never uploaded**. Automated tests check the page's requests in Chromium and WebKit.
- They are held in page memory for the optional import into CertSigner, then cleared when you import, start over or leave the page.
- Only the finished, signed IPA is uploaded, to a temporary relay that gives iOS an HTTPS install link.
- The relay accepts IPAs of up to 25 MB. Links expire after 10 minutes, or 2 minutes after the first complete download.
- Without a relay, the page can still sign and offer the IPA as a download.

A wildcard profile keeps CertSigner's bundle ID when it fits. An explicit profile signs CertSigner
with that profile's App ID.

<details>
<summary><strong>Build and test the web installer</strong></summary>

CI uses Linux, Node.js 22, Emscripten 3.1.74 and Playwright 1.65.0. Emscripten and OpenSSL must be on
your `PATH`, and an unsigned IPA must be saved as `web/site/app/CertSigner.ipa`.

```bash
bash web/wasm/build.sh
bash web/tests/make-fixtures.sh
cd web
npm install --no-save playwright@1.65.0
npx playwright install chromium webkit
node --test tests/*.test.mjs
node scripts/prepare-site.mjs https://your-relay.workers.dev
```

The finished site is written to `web/dist`. Omit the URL to build without a relay.

</details>

<details>
<summary><strong>Deploy your own copy</strong></summary>

1. In your fork, set **Settings › Pages › Source** to **GitHub Actions**.
2. For the relay, create a Cloudflare API token that can edit Workers scripts and Workers KV storage.
3. Add it as the Actions secret `CLOUDFLARE_API_TOKEN`. Add `CLOUDFLARE_ACCOUNT_ID` if the token can access more than one account.
4. Run **Build IPA** on `main`. It creates the KV namespace, deploys the relay and publishes the page.

If the relay is deployed separately, set the Actions variable `RELAY_URL` to its HTTPS URL. This
repository's hosted page uses that option. To deploy from a terminal, with the token already in the
environment:

```bash
PAGES_ORIGIN=https://your-name.github.io bash worker/deploy.sh
```

Forks should also update the repository links in `web/site/index.html`,
`Sources/Views/Settings/SettingsView.swift` and `Sources/Services/UpdateService.swift`.

</details>

## Project structure

```text
Sources/
  App/           App entry point, navigation and file handling
  Components/    Design system and reusable views
  Models/        Certificates, profiles, apps, sources and options
  Services/      Signing, installation, storage, sources and updates
  Views/         Home, Library, Sources, Search, Settings and sheets
Tests/           XCTest suites
Vendor/          zsign and its Objective-C++ bridge
web/             Browser installer, WebAssembly signer and tests
worker/          Temporary install relay (Cloudflare Worker)
project.yml      XcodeGen project definition
```

The UI conventions are documented in [DESIGN.md](DESIGN.md), and vendored code and patches in
[Vendor/README.md](Vendor/README.md).

## Contributing

Bug reports and focused pull requests are welcome.

- For a bug, include the CertSigner build, iOS version, device, steps to reproduce and a reviewed log.
- Keep each change to one issue, add tests where practical, and follow [DESIGN.md](DESIGN.md) for UI work.
- State what was tested in CI and what was tested on a device.
- Never commit certificates, profiles, passwords or tokens.

## License

CertSigner is open source under the [MIT License](LICENSE).

Third-party components keep their own licenses:

| Component | Use | License |
|---|---|---|
| [zsign](https://github.com/zhlynn/zsign) | Code signing | MIT ([text](Vendor/zsign/LICENSE)) |
| [fflate](https://github.com/101arrowz/fflate) | ZIP handling in the web installer | MIT ([text](web/site/js/vendor/fflate.LICENSE)) |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ZIP handling in the app | See project |
| [OpenSSL](https://www.openssl.org/) via [OpenSSL package](https://github.com/krzyzanowskim/OpenSSL) | Cryptography | See project |
