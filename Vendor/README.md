# Vendored code

## zsign (`Vendor/zsign`)
- Source: https://github.com/zhlynn/zsign, commit `9299685bab7ef99827e06e5dfda93af747386590`, MIT licence (see `zsign/LICENSE`).
- Copied from `src/`. Removed: `zsign.cpp` (CLI), `certcheck.*` (OCSP over raw sockets), `metadata.*`,
  `common/archive.*` and `third-party/` (zip/zlib; the app zips with ZIPFoundation instead).
- Patches (search for "CertSigner patch"):
  1. `#include <openssl/...>` → `<OpenSSL/...>` to match the OpenSSL xcframework's headers.
  2. `signing.cpp`: skip the `popen("/usr/bin/csreq")` debug path when `ZSIGN_IOS` is defined.
  3. `common/log.*`: `ZLog::SetLogCallback` forwards log lines to the app.

## ZSignBridge (`Vendor/ZSignBridge`)
- `zsign_api.{h,cpp}`: a C entry point (`zsign_sign_folder`) over `ZSignAsset` + `ZBundle::SignFolder`.
- `ZSignBridge.{h,mm}`: the Objective-C wrapper Swift calls (`ZSignBridge.sign(appPath:...)`).

OpenSSL comes from the `krzyzanowskim/OpenSSL` Swift package (OpenSSL 3.x xcframework).
