#!/usr/bin/env bash
# Builds the browser signer: the vendored zsign + OpenSSL (libcrypto) compiled to WebAssembly
# with Emscripten. Output: web/site/wasm/zsign.js + zsign.wasm.
# Needs emcc on PATH (CI uses setup-emsdk). OpenSSL is built once into .wasm-build/ (cached in CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/web/site/wasm}"
WORK="${WASM_WORK:-$ROOT/.wasm-build}"
OPENSSL_VERSION="3.3.2"
OPENSSL_SHA256="2e8a40b01979afe8be0bbfb3de5dc1c6709fedb46d6c89c10da114ab5fc3d281"

mkdir -p "$OUT" "$WORK"

if [ ! -f "$WORK/openssl/libcrypto.a" ]; then
  echo "== Building OpenSSL $OPENSSL_VERSION for WebAssembly"
  cd "$WORK"
  curl -fsSL -o openssl.tar.gz "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
  echo "$OPENSSL_SHA256  openssl.tar.gz" | sha256sum -c -
  rm -rf "openssl-$OPENSSL_VERSION" && tar xzf openssl.tar.gz
  cd "openssl-$OPENSSL_VERSION"
  # no-module: the legacy provider (RC2 / 3DES p12 files) is built into libcrypto.
  emconfigure ./Configure linux-generic32 no-asm no-threads no-shared no-module no-engine no-dso \
    no-tests no-apps no-sock no-ui-console no-afalgeng no-secure-memory no-docs -Os
  sed -i 's|^CROSS_COMPILE=.*$|CROSS_COMPILE=|' Makefile
  emmake make -j"$(nproc)" build_generated libcrypto.a >/dev/null
  mkdir -p "$WORK/openssl"
  cp libcrypto.a "$WORK/openssl/"
  rm -rf "$WORK/openssl/include" && cp -RL include "$WORK/openssl/include"
  # zsign's sources include <OpenSSL/...> (the iOS xcframework's spelling).
  ln -sfn openssl "$WORK/openssl/include/OpenSSL"
  cd "$WORK" && rm -rf "openssl-$OPENSSL_VERSION" openssl.tar.gz
fi

echo "== Building zsign.wasm"
cd "$ROOT"
em++ -O2 -std=c++17 -fexceptions -DZSIGN_IOS=1 -Wno-deprecated-declarations \
  -I Vendor/zsign -I Vendor/zsign/common -I "$WORK/openssl/include" \
  Vendor/zsign/*.cpp Vendor/zsign/common/*.cpp web/wasm/zsign_web.cpp "$WORK/openssl/libcrypto.a" \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createZsign -sENVIRONMENT=web,worker,node \
  -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=67108864 -sSTACK_SIZE=4194304 \
  -sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=FS,ccall,UTF8ToString \
  -o "$OUT/zsign.js"
ls -la "$OUT"
