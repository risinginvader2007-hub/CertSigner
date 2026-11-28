#!/usr/bin/env bash
# Downloads the published release IPA for the self-update signing tests.
#
#   fetch-release-ipa.sh <owner/repo> <output .ipa>
#
# Exit 0 + "required"  : the IPA was downloaded; the tests must sign it.
# Exit 0 + "bootstrap" : this repository has never published a release (no published release now,
#                        and no successful "Build IPA" run on main ever): the tests may skip.
# Exit 1               : anything else (API or auth error, release without the IPA, download
#                        failure, or a release that existed but didn't come back in time).
#
# The only release is "latest", which build.yml deletes and re-creates on every publish, so
# "no release right now" alone is not proof of a new repository: when main has published before,
# this waits for the release to come back instead of skipping.
#
# Test hooks: GH (the gh command), FETCH_WAIT_TRIES / FETCH_WAIT_SECONDS (polling).
set -uo pipefail

REPO="$1"
OUT="$2"
GH="${GH:-gh}"
TRIES="${FETCH_WAIT_TRIES:-12}"
WAIT="${FETCH_WAIT_SECONDS:-15}"

fail() { echo "ERROR: $*" >&2; exit 1; }

published_count() {
  # Published (non-draft) releases. Fails the script on any API error.
  local count
  count=$("$GH" api "repos/$REPO/releases?per_page=100" --jq '[.[] | select(.draft | not)] | length') \
    || fail "couldn't list releases (API or authentication error)"
  [[ "$count" =~ ^[0-9]+$ ]] || fail "unexpected answer listing releases: $count"
  echo "$count"
}

count=$(published_count) || exit 1
if [ "$count" -eq 0 ]; then
  published_before=$("$GH" api "repos/$REPO/actions/workflows/build.yml/runs?branch=main&status=success&per_page=1" --jq '.total_count') \
    || fail "couldn't read the Build IPA run history (API or authentication error)"
  [[ "$published_before" =~ ^[0-9]+$ ]] || fail "unexpected answer reading the run history: $published_before"
  if [ "$published_before" -eq 0 ]; then
    echo "bootstrap"
    echo "No release has ever been published from main: the self-update tests will skip." >&2
    exit 0
  fi
  # main has published before: the release is being re-created right now. Wait for it.
  for _ in $(seq 1 "$TRIES"); do
    sleep "$WAIT"
    count=$(published_count) || exit 1
    [ "$count" -gt 0 ] && break
  done
  [ "$count" -gt 0 ] || fail "main has published releases before, but none is published now (checked for $((TRIES * WAIT)) s)"
fi

assets=$("$GH" api "repos/$REPO/releases/tags/latest" --jq '[.assets[].name] | join(",")') \
  || fail "$count published release(s), but the 'latest' release can't be read (missing tag or API error)"
case ",$assets," in
  *,CertSigner.ipa,*) ;;
  *) fail "the 'latest' release has no CertSigner.ipa (assets: ${assets:-none})" ;;
esac

"$GH" release download latest -R "$REPO" -p CertSigner.ipa -O "$OUT" --clobber || fail "downloading CertSigner.ipa failed"
[ -s "$OUT" ] || fail "the downloaded CertSigner.ipa is empty"
echo "required"
