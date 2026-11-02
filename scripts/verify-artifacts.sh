#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build
swift run --skip-build artifact-inspection-checks
swift run --skip-build artifact-inspector verify-record "$(pwd -P)/docs/firefox-artifact-evidence.json"
