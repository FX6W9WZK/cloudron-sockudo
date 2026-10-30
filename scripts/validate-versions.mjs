// Validate CloudronVersions.json files the way a Cloudron server does before installing or updating
// a community app (box/src/community.js): parseVersions on the whole file, then
// checkVersionsRequirements on every version that is not revoked.
//
// Needs @cloudron/manifest-format next to this script, see the "Validate for Cloudron" step in
// .github/workflows/package.yml.
//
// Usage: node validate-versions.mjs <CloudronVersions.json>...

import fs from 'node:fs';
import manifestFormat from '@cloudron/manifest-format';

let failed = false;

for (const file of process.argv.slice(2)) {
    const versionsRoot = JSON.parse(fs.readFileSync(file, 'utf8'));
    const errors = [];

    const versionsError = manifestFormat.parseVersions(versionsRoot);
    if (versionsError) errors.push(versionsError.message);

    for (const [version, data] of Object.entries(versionsRoot.versions || {})) {
        if (data.publishState === 'revoked') continue;
        const manifestError = manifestFormat.checkVersionsRequirements(data.manifest);
        if (manifestError) errors.push(`${version}: ${manifestError.message}`);
    }

    if (errors.length) {
        failed = true;
        for (const error of errors) console.log(`::error file=${file}::${error}`);
    } else {
        console.log(`${file}: OK (${Object.keys(versionsRoot.versions).join(', ')})`);
    }
}

process.exit(failed ? 1 : 0);
