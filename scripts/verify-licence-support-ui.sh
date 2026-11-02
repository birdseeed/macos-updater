#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
if ! grep -q '^./scripts/verify-licence-support-ui.sh$' scripts/verify.sh; then
    echo 'FAIL support UI: full gate does not run verify-licence-support-ui.sh' >&2
    exit 1
fi
swift build --product patched-licence-support-ui-checks
swift run --skip-build patched-licence-support-ui-checks
