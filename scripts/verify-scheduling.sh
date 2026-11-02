#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"

swift build --product patched-scheduling-checks
swift run --skip-build patched-scheduling-checks

# Keep this standalone gate in the full sequential gate.
if ! grep -q '^./scripts/verify-scheduling.sh$' scripts/verify.sh; then
    echo "FAIL scheduling: full gate does not run verify-scheduling.sh" >&2
    exit 1
fi
