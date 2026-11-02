#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
# Parent owns execution and Package registration. Never launch an App product.
swift build
swift run --skip-build patched-shell-checks
