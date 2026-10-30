#!/usr/bin/env python3
"""Point a package at a new upstream release.

Usage: bump-upstream.py <app-dir> <upstream-version> <release-url> NAME=VALUE [NAME=VALUE ...]

Sets the given Dockerfile ARGs (which must already exist), updates
CloudronManifest.json (upstreamVersion, version, dockerImage) and prepends a
CHANGELOG.md entry. The package version is bumped at the same level as the
upstream change (major/minor/patch). Prints the new package version.

Example: bump-upstream.py . 5.3.0 https://github.com/sockudo/sockudo/releases/tag/v5.3.0 \\
             SOCKUDO_VERSION=5.3.0 SOCKUDO_SHA256=<sha256>
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


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
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    root = REPO / sys.argv[1]
    new_upstream, release_url = sys.argv[2], sys.argv[3]
    args = dict(arg.split("=", 1) for arg in sys.argv[4:])

    manifest_file = root / "CloudronManifest.json"
    dockerfile_file = root / "Dockerfile"
    changelog_file = root / "CHANGELOG.md"

    manifest = json.loads(manifest_file.read_text())
    old_upstream = manifest["upstreamVersion"]
    if parse(new_upstream) <= parse(old_upstream):
        sys.exit(f"{new_upstream} is not newer than {old_upstream}")

    dockerfile = dockerfile_file.read_text()
    for name, value in args.items():
        if not re.fullmatch(r"[A-Za-z0-9.:~+_-]+", value):
            sys.exit(f"refusing unexpected characters in {name}={value}")
        dockerfile, count = re.subn(rf"^ARG {name}=.*$", f"ARG {name}={value}", dockerfile, flags=re.M)
        if count != 1:
            sys.exit(f"Dockerfile has no single 'ARG {name}=' line")

    version = ".".join(str(part) for part in bump(parse(manifest["version"]), parse(old_upstream), parse(new_upstream)))
    image = manifest["dockerImage"].rsplit(":", 1)[0]
    manifest["upstreamVersion"] = new_upstream
    manifest["version"] = version
    manifest["dockerImage"] = f"{image}:{version}"

    dockerfile_file.write_text(dockerfile)
    manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")
    entry = (
        f"[{version}]\n"
        f"* Update {manifest['title']} to {new_upstream}\n"
        f"* [Full changelog]({release_url})\n\n"
    )
    changelog_file.write_text(entry + changelog_file.read_text())

    print(version)


if __name__ == "__main__":
    main()
