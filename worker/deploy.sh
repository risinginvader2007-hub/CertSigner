#!/usr/bin/env bash
# Deploys the install relay to Cloudflare Workers. Used by CI; also works on your own machine.
#
# Needs CLOUDFLARE_API_TOKEN in the environment (a token with "Workers Scripts: Edit" and
# "Workers KV Storage: Edit"), and CLOUDFLARE_ACCOUNT_ID if the token can see several accounts.
# Optional PAGES_ORIGIN: the page's origin, e.g. https://yourname.github.io
# The token is only ever read from the environment: never put it in a file or a command line.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "CLOUDFLARE_API_TOKEN is not set: nothing deployed."
  exit 0
fi

npm install --no-save --silent wrangler@4

find_namespace() {
  npx wrangler kv namespace list 2>/dev/null | node -e '
    let text = ""; process.stdin.on("data", (d) => text += d).on("end", () => {
      const start = text.indexOf("["); if (start < 0) return;
      const found = JSON.parse(text.slice(start)).find((n) => /get-certsigner-store$/.test(n.title));
      if (found) console.log(found.id);
    });'
}

KV_ID="$(find_namespace)"
if [ -z "$KV_ID" ]; then
  echo "Creating the KV namespace"
  npx wrangler kv namespace create get-certsigner-store >/dev/null
  KV_ID="$(find_namespace)"
fi
[ -n "$KV_ID" ] || { echo "Could not find or create the KV namespace"; exit 1; }

cp wrangler.toml wrangler.deploy.toml
sed -i "s/KV_NAMESPACE_ID/$KV_ID/" wrangler.deploy.toml
if [ -n "${PAGES_ORIGIN:-}" ]; then
  sed -i "s|^ALLOWED_ORIGIN = .*|ALLOWED_ORIGIN = \"$PAGES_ORIGIN\"|" wrangler.deploy.toml
fi

npx wrangler deploy --config wrangler.deploy.toml | tee deploy.log
URL="$(grep -oE 'https://[a-z0-9.-]+\.workers\.dev' deploy.log | head -1 || true)"
rm -f wrangler.deploy.toml deploy.log
echo "Relay URL: ${URL:-unknown}"
if [ -n "${GITHUB_OUTPUT:-}" ] && [ -n "$URL" ]; then echo "url=$URL" >> "$GITHUB_OUTPUT"; fi
