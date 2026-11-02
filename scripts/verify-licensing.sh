#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build --product patched-licensing-checks
swift run --skip-build patched-licensing-checks
if ! grep -q '^./scripts/verify-licensing.sh$' scripts/verify.sh; then
    echo "FAIL licensing: full gate does not run verify-licensing.sh" >&2
    exit 1
fi
