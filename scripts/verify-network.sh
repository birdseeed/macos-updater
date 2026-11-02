#!/bin/sh
set -u
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)" || exit 1
# Both independent acceptance paths run even while Phase A has meaningful red.
status=0
if swift build --product patched-network-checks; then
    swift run --skip-build patched-network-checks || status=1
else
    status=1
fi
node --test services/catalogue/tests/network-package-registration-preservation.test.mjs || status=1
exit "$status"
