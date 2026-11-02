#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build
swift run --skip-build patched-operator-session-checks
# The full gate must run this script (demanded once the implementation exists).
grep -q 'verify-operator-session\.sh' scripts/verify.sh \
  || { echo "scripts/verify.sh does not include verify-operator-session.sh" >&2; exit 1; }
