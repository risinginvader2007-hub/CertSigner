#!/usr/bin/env python3
"""Writes update.json for the in-app updater: what the release contains and how to check it.

Usage: make-update-json.py <CertSigner.ipa> <build number> <commit sha> <notes file>

The notes file is either .github/release-notes.md (written by hand; "- " list items, or plain
lines) or the commit subjects since the previous release, one per line.
Fails when the IPA's own build number isn't <build number> (the app compares the two).
"""
import datetime
import hashlib
import json
import os
import plistlib
import sys
import zipfile


def main() -> None:
    ipa_path, build_text, commit, notes_path = sys.argv[1:5]
    build = int(build_text)

    with open(ipa_path, "rb") as handle:
        data = handle.read()

    with zipfile.ZipFile(ipa_path) as archive:
        names = [n for n in archive.namelist()
                 if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count("/") == 2]
        if len(names) != 1:
            sys.exit(f"expected one Payload/<App>.app/Info.plist, found {names}")
        info = plistlib.loads(archive.read(names[0]))

    bundle_build = str(info.get("CFBundleVersion", ""))
    if bundle_build != str(build):
        sys.exit(f"CFBundleVersion is {bundle_build!r}, expected {build} (is CURRENT_PROJECT_VERSION stamped?)")

    notes = []
    with open(notes_path, encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            if text.startswith(("- ", "* ")):
                text = text[2:].strip()
            notes.append(text[:240])
    notes = notes[:40]

    manifest = {
        "schema": 1,
        "build": build,
        "version": str(info.get("CFBundleShortVersionString", "")),
        "commit": commit,
        "bundleID": str(info.get("CFBundleIdentifier", "")),
        "minimumOS": str(info.get("MinimumOSVersion", "")),
        "ipa": {
            "name": os.path.basename(ipa_path),
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        },
        "published": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "notes": notes,
    }
    json.dump(manifest, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
