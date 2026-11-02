#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
if ! grep -q '^./scripts/verify-licence-support.sh$' scripts/verify.sh; then
    echo 'FAIL support: full gate does not run verify-licence-support.sh' >&2
    exit 1
fi
swift build --product patched-licence-support-checks
swift run --skip-build patched-licence-support-checks
