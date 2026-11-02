#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
if ! grep -q '^./scripts/verify-activation.sh$' scripts/verify.sh; then
    echo "FAIL activation: full gate does not run verify-activation.sh" >&2
    exit 1
fi
swift build --product patched-activation-checks
swift run --skip-build patched-activation-checks --emit-fixed-proof-replay
swift run --skip-build patched-activation-checks
