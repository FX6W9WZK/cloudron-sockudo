#!/usr/bin/env python3
"""Point the package at a new Sockudo release.

Usage: bump-upstream.py <upstream-version> <sha256-of-musl-tarball>

Updates the Dockerfile ARGs, CloudronManifest.json (upstreamVersion, version,
dockerImage) and prepends a CHANGELOG.md entry. The package version is bumped
at the same level as the upstream change (major/minor/patch). Prints the new
package version.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCKERFILE = ROOT / "Dockerfile"
MANIFEST = ROOT / "CloudronManifest.json"
CHANGELOG = ROOT / "CHANGELOG.md"


def parse(version):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not match:
        sys.exit(f"not a plain semver version: {version}")
    return tuple(int(part) for part in match.groups())


def bump(package, old_upstream, new_upstream):
    major, minor, patch = package
    if new_upstream[0] != old_upstream[0]:
        return (major + 1, 0, 0)
    if new_upstream[1] != old_upstream[1]:
        return (major, minor + 1, 0)
    return (major, minor, patch + 1)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    new_upstream, sha256 = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        sys.exit(f"invalid sha256: {sha256}")

    manifest = json.loads(MANIFEST.read_text())
    old_upstream = manifest["upstreamVersion"]
    if parse(new_upstream) <= parse(old_upstream):
        sys.exit(f"{new_upstream} is not newer than {old_upstream}")

    version = ".".join(str(part) for part in bump(parse(manifest["version"]), parse(old_upstream), parse(new_upstream)))
    image = manifest["dockerImage"].rsplit(":", 1)[0]

    manifest["upstreamVersion"] = new_upstream
    manifest["version"] = version
    manifest["dockerImage"] = f"{image}:{version}"
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")

    dockerfile = DOCKERFILE.read_text()
    dockerfile = re.sub(r"^ARG SOCKUDO_VERSION=.*$", f"ARG SOCKUDO_VERSION={new_upstream}", dockerfile, flags=re.M)
    dockerfile = re.sub(r"^ARG SOCKUDO_SHA256=.*$", f"ARG SOCKUDO_SHA256={sha256}", dockerfile, flags=re.M)
    DOCKERFILE.write_text(dockerfile)

    entry = (
        f"[{version}]\n"
        f"* Update Sockudo to {new_upstream}\n"
        f"* [Full changelog](https://github.com/sockudo/sockudo/releases/tag/v{new_upstream})\n\n"
    )
    CHANGELOG.write_text(entry + CHANGELOG.read_text())

    print(version)


if __name__ == "__main__":
    main()
