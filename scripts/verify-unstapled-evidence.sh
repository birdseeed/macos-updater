#!/bin/sh
set -eu
# Runs the installed repository check from scripts/verify-unstapled-evidence.sh.
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build --product artifact-inspection-checks
status=0
swift run --skip-build artifact-inspection-checks --pat-2707-unstapled || status=1
node scripts/checks/NoCLTTrustSourceGuard.mjs || status=1
node --test services/catalogue/tests/unstapled-live-proof-preservation.test.mjs || status=1
node --test services/catalogue/tests/verified-image-registration-preservation.test.mjs || status=1
exit "$status"
