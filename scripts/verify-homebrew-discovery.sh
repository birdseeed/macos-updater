#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if ! command -v node >/dev/null 2>&1; then
    echo 'Homebrew discovery checks require an existing Node.js >=22 runtime.' >&2
    exit 1
fi
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Homebrew discovery checks require an existing Node.js >=22 runtime."); process.exit(1) }'
node --test services/catalogue/tests/homebrew-*.test.mjs
