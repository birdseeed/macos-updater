#!/bin/sh
set -eu
if [ -L "$0" ]; then
    echo 'Vendor discovery checks refuse a symlink script entry point.' >&2
    exit 1
fi
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$ROOT"
if ! command -v node >/dev/null 2>&1; then
    echo 'Vendor discovery checks require an existing Node.js >=22 runtime.' >&2
    exit 1
fi
node --version
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Vendor discovery checks require Node.js >=22"); process.exit(1); }'
result=0
node --test services/catalogue/tests/vendor-sparkle.test.mjs services/catalogue/tests/vendor-electron.test.mjs services/catalogue/tests/vendor-candidates.test.mjs services/catalogue/tests/vendor-boundaries.test.mjs services/catalogue/tests/vendor-installed-metadata.test.mjs services/catalogue/tests/vendor-vscode-product.test.mjs || result=$?
git diff --check || result=1
exit "$result"
