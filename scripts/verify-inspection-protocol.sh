#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
node --version
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Inspection format checks require installed Node >=22"); process.exit(1); }'
node --test services/catalogue/tests/inspection-protocol.test.mjs
