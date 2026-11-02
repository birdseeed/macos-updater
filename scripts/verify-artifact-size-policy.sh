#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build --product artifact-inspection-checks
swift build --product patched-core-checks
status=0
swift run --skip-build artifact-inspection-checks --size-policy || status=1
swift run --skip-build patched-core-checks --size-policy || status=1
node --test services/catalogue/tests/artifact-size-preservation.test.mjs || status=1
./scripts/verify-catalogue-protocol.sh || status=1
exit "$status"
