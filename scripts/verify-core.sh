#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build
swift run --skip-build patched-core-checks
swift run --skip-build patched-core-regression-checks
