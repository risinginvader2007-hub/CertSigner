#!/usr/bin/env bash
# Tests fetch-release-ipa.sh against a fake `gh` with controlled answers (no network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fake gh. Answers come from files in $WORK/case/:
#   releases      : list answers, one per line, used in order (last one repeats); "ERR" = API error
#   runs          : successful Build IPA runs on main; "ERR" = API error
#   assets        : asset names of the 'latest' release; missing file = no such tag
#   download      : "ok" writes a file, anything else fails
cat > "$WORK/gh" <<'EOF'
#!/usr/bin/env bash
C="$FAKE_CASE"
answer() { # file -> next line (the last line repeats)
  local file="$C/$1" n; n=$(cat "$C/.$1.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$C/.$1.n"
  local line; line=$(sed -n "${n}p" "$file"); [ -n "$line" ] || line=$(tail -n 1 "$file"); echo "$line"
}
case "$1 $2" in
  "api repos/"*"/releases?per_page=100") a=$(answer releases); [ "$a" = ERR ] && { echo "HTTP 401" >&2; exit 1; }; echo "$a" ;;
  "api repos/"*"/actions/"*) a=$(answer runs); [ "$a" = ERR ] && { echo "HTTP 500" >&2; exit 1; }; echo "$a" ;;
  "api repos/"*"/releases/tags/latest") [ -f "$C/assets" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }; cat "$C/assets" ;;
  "release download")
    out=""; while [ $# -gt 0 ]; do [ "$1" = "-O" ] && out="$2"; shift; done
    [ "$(cat "$C/download" 2>/dev/null)" = ok ] || { echo "download failed" >&2; exit 1; }
    echo "IPA" > "$out" ;;
  *) echo "unexpected gh call: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$WORK/gh"

failures=0
check() { # name, expected exit, expected first stdout line ("" = none), setup...
  local name="$1" want_exit="$2" want_out="$3"; shift 3
  local dir="$WORK/$name"; mkdir -p "$dir"
  for kv in "$@"; do printf '%b\n' "${kv#*=}" > "$dir/${kv%%=*}"; done
  local out code
  out=$(FAKE_CASE="$dir" GH="$WORK/gh" FETCH_WAIT_TRIES=3 FETCH_WAIT_SECONDS=0 \
        bash "$HERE/fetch-release-ipa.sh" owner/repo "$dir/out.ipa" 2>"$dir/err")
  code=$?
  if [ "$code" = "$want_exit" ] && [ "$(echo "$out" | head -n 1)" = "$want_out" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: exit $code (want $want_exit), out '$out' (want '$want_out'); stderr: $(cat "$dir/err")"
    failures=$((failures + 1))
  fi
}

check empty-repository          0 bootstrap releases=0 runs=0
check success                   0 required  releases=1 assets="CertSigner.ipa,update.json" download=ok
check missing-tag-other-release 1 ""        releases=1
check missing-asset             1 ""        releases=1 assets="update.json"
check releases-api-error        1 ""        releases=ERR
check runs-api-error            1 ""        releases=0 runs=ERR
check download-failure          1 ""        releases=1 assets="CertSigner.ipa" download=no
check republish-window          0 required  releases="0\n0\n1" runs=7 assets="CertSigner.ipa" download=ok
check release-never-returns     1 ""        releases=0 runs=7

[ "$failures" -eq 0 ] && echo "all fetch-release-ipa cases passed" || { echo "$failures case(s) failed"; exit 1; }
