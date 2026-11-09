#!/usr/bin/env bash
# Builds test fixtures for SigningPipelineTests: a multi-extension IPA, a self-signed .p12 and a CMS-wrapped
# provisioning profile with an explicit App ID that does NOT match the app.
set -euo pipefail
F="$1"
rm -rf "$F" && mkdir -p "$F/build" && cd "$F/build"
OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
cc() { xcrun -sdk iphoneos clang -arch arm64 -mios-version-min=15.0 "$@"; }

echo 'int main(void){return 0;}' > main.c
echo 'int kit_value(void){return 42;}' > lib.c

APP=Payload/Multi.app
mkdir -p "$APP/PlugIns/Share.appex" "$APP/PlugIns/Widget.appex" "$APP/Frameworks/Kit.framework"
cc main.c -o "$APP/Multi"
cc main.c -o "$APP/PlugIns/Share.appex/Share"
cc main.c -o "$APP/PlugIns/Widget.appex/Widget"
cc -dynamiclib lib.c -install_name @rpath/Kit.framework/Kit -o "$APP/Frameworks/Kit.framework/Kit"
cc -dynamiclib lib.c -install_name @rpath/libextra.dylib -o "$APP/Frameworks/libextra.dylib"

plist() { # path id exec type
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" \
    -c "Add :CFBundleExecutable string $3" -c "Add :CFBundleName string $3" \
    -c "Add :CFBundlePackageType string $4" -c "Add :CFBundleShortVersionString string 1.0" \
    -c "Add :CFBundleVersion string 1" -c "Add :MinimumOSVersion string 15.0" "$1/Info.plist" >/dev/null
}
plist "$APP" com.husk.test Multi APPL
plist "$APP/PlugIns/Share.appex" com.husk.test.share Share XPC!
plist "$APP/PlugIns/Widget.appex" com.husk.test.widget Widget XPC!
plist "$APP/Frameworks/Kit.framework" com.husk.test.kit Kit FMWK
for ext in Share Widget; do
  /usr/libexec/PlistBuddy -c "Add :NSExtension dict" \
    -c "Add :NSExtension:NSExtensionPointIdentifier string com.apple.widgetkit-extension" \
    "$APP/PlugIns/$ext.appex/Info.plist" >/dev/null
done
zip -qry "$F/test.ipa" Payload

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 30 \
  -subj "/CN=iPhone Distribution: CertSigner Test (ABCDE12345)/OU=ABCDE12345/O=CertSigner Test/C=US" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey key.pem -in cert.pem -out "$F/cert.p12" -passout pass:test -name "CertSigner Test"
DER_B64=$("$OPENSSL" x509 -in cert.pem -outform DER | base64 | tr -d '\n')

cat > profile.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>AppIDName</key><string>Other App</string>
  <key>Name</key><string>CertSigner Test Explicit Profile</string>
  <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
  <key>TeamName</key><string>CertSigner Test</string>
  <key>UUID</key><string>11111111-2222-3333-4444-555555555555</string>
  <key>CreationDate</key><date>2026-01-01T00:00:00Z</date>
  <key>ExpirationDate</key><date>2030-01-01T00:00:00Z</date>
  <key>ProvisionedDevices</key><array><string>00008110-00000000000000AA</string></array>
  <key>DeveloperCertificates</key><array><data>$DER_B64</data></array>
  <key>Entitlements</key><dict>
    <key>application-identifier</key><string>ABCDE12345.com.other.app</string>
    <key>com.apple.developer.team-identifier</key><string>ABCDE12345</string>
    <key>get-task-allow</key><true/>
    <key>keychain-access-groups</key><array><string>ABCDE12345.*</string></array>
  </dict>
</dict></plist>
EOF
"$OPENSSL" cms -sign -nodetach -binary -outform DER -in profile.plist -signer cert.pem -inkey key.pem \
  -out "$F/profile.mobileprovision"
ls -la "$F"
