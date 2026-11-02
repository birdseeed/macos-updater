#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
if ! command -v node >/dev/null 2>&1; then
    echo 'AutoPkg offline planner checks require an existing Node.js >=22 runtime (CI pin: 24.21.0).' >&2
    exit 1
fi
node --version
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("AutoPkg offline planner checks require Node.js >=22"); process.exit(1); }'
node --test services/catalogue/tests/autopkg-transport-plan.test.mjs
