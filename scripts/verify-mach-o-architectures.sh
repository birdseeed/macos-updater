#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build --product artifact-inspection-checks
status=0
swift run --skip-build artifact-inspection-checks --pat-2706-mach-o || status=1
node Tests/ArtifactInspectionChecks/NoLipoSourceGuard.mjs || status=1
exit "$status"
