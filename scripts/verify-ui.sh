#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build
swift run --skip-build patched-ui-checks
swift run --skip-build patched-licence-ui-checks
