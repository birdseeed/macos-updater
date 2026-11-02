#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if ! command -v node >/dev/null 2>&1; then
    echo 'Installomator discovery check requires an existing Node.js >=22 runtime.' >&2
    exit 1
fi
node --version
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Installomator discovery check requires Node.js >=22"); process.exit(1); }'
result=0
node --test services/catalogue/tests/upstream-snapshot.test.mjs services/catalogue/tests/upstream-parser.test.mjs services/catalogue/tests/upstream-diff.test.mjs services/catalogue/tests/upstream-iteration.test.mjs || result=$?
git diff --check || result=1
exit "$result"
