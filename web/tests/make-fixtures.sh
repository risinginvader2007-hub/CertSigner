#!/usr/bin/env bash
# Test fixtures for the web signer (throwaway keys, made fresh on every run; nothing real):
# a test CA + leaf certificate as .p12 (modern and legacy encryption), and CMS-wrapped
# provisioning profiles: wildcard, explicit, expired, and one for a different certificate.
set -euo pipefail
F="$(cd "$(dirname "$0")" && pwd)/fixtures"
rm -rf "$F" && mkdir -p "$F" && cd "$F"
PASSWORD="fixture-Passw0rd-$(openssl rand -hex 6)"
printf '%s' "$PASSWORD" > password.txt

openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 60 \
  -subj "/CN=Web Test WWDR CA/O=CertSigner Test/C=US" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
printf "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n" > leaf.ext
leaf() { # name
  openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" \
    -subj "/CN=iPhone Developer: Web Test $1 (ABCDE12345)/OU=ABCDE12345/O=CertSigner Test/C=US" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -extfile leaf.ext -out "$1.pem" 2>/dev/null
}
leaf main
leaf other
openssl pkcs12 -export -inkey main.key -in main.pem -certfile ca.pem -out cert.p12 -passout "pass:$PASSWORD" -name "Web Test"
openssl pkcs12 -export -legacy -inkey main.key -in main.pem -certfile ca.pem -out legacy.p12 -passout "pass:$PASSWORD" -name "Web Test"

profile() { # file appid expiry certname
  local der
  der=$(openssl x509 -in "$4.pem" -outform DER | base64 | tr -d '\n')
  cat > profile.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>AppIDName</key><string>Web Test</string>
  <key>Name</key><string>Web Test Profile $1</string>
  <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
  <key>TeamName</key><string>CertSigner Test</string>
  <key>UUID</key><string>11111111-2222-3333-4444-555555555555</string>
  <key>CreationDate</key><date>2026-01-01T00:00:00Z</date>
  <key>ExpirationDate</key><date>$3</date>
  <key>ProvisionedDevices</key><array><string>00008110-00000000000000AA</string><string>00008110-00000000000000BB</string></array>
  <key>DeveloperCertificates</key><array><data>$der</data></array>
  <key>Entitlements</key><dict>
    <key>application-identifier</key><string>ABCDE12345.$2</string>
    <key>com.apple.developer.team-identifier</key><string>ABCDE12345</string>
    <key>get-task-allow</key><true/>
    <key>keychain-access-groups</key><array><string>ABCDE12345.*</string></array>
  </dict>
</dict></plist>
EOF
  openssl cms -sign -nodetach -binary -outform DER -in profile.plist -signer main.pem -inkey main.key -out "$1.mobileprovision"
}
profile wildcard '*' 2031-01-01T00:00:00Z main
profile explicit 'com.example.signedweb' 2031-01-01T00:00:00Z main
profile expired '*' 2020-01-01T00:00:00Z main
profile mismatch '*' 2031-01-01T00:00:00Z other
rm -f profile.plist ./*.csr ./*.srl leaf.ext
ls -la "$F"
