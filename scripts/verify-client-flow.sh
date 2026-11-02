#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"

swift build
swift run --skip-build patched-client-checks

# The full gate must keep running this script.
if ! grep -q 'verify-client-flow.sh' scripts/verify.sh; then
    echo "FAIL client-flow: scripts/verify.sh does not run scripts/verify-client-flow.sh" >&2
    exit 1
fi
