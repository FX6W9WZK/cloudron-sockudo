#!/usr/bin/env python3
"""Record the current CloudronManifest.json as a published version in CloudronVersions.json.

Cloudron installations that added this package as a community app read
CloudronVersions.json to discover updates. `file://` references in the
manifest are inlined, and the changelog is reduced to the current version's
section, the same way `cloudron versions add` does it.

Exits 0 without changes when the version is already recorded.
"""

import json
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "CloudronManifest.json"
VERSIONS = ROOT / "CloudronVersions.json"


def changelog_section(text, version):
    lines, found = [], False
    for line in text.splitlines():
        if line.strip() == f"[{version}]":
            found = True
            continue
        if found and re.match(r"^\[.+\]\s*$", line):
            break
        if found:
            lines.append(line)
    if not found:
        sys.exit(f"CHANGELOG.md has no [{version}] section")
    return "\n".join(lines).strip() + "\n"


def main():
    manifest = json.loads(MANIFEST.read_text())
    version = manifest["version"]

    for field in ("description", "changelog", "postInstallMessage"):
        value = manifest.get(field, "")
        if value.startswith("file://"):
            manifest[field] = (ROOT / value[len("file://"):]).read_text()
    manifest["changelog"] = changelog_section(manifest["changelog"], version)

    catalog = json.loads(VERSIONS.read_text()) if VERSIONS.exists() else {"stable": True, "versions": {}}
    if version in catalog["versions"]:
        print(f"{version} already recorded, nothing to do")
        return

    now = format_datetime(datetime.now(timezone.utc), usegmt=True)
    catalog["versions"][version] = {
        "manifest": manifest,
        "creationDate": now,
        "ts": now,
        "publishState": "published",
    }
    VERSIONS.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"recorded {version} ({manifest['dockerImage']})")


if __name__ == "__main__":
    main()
