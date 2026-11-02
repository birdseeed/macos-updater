#!/bin/sh
set -u
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)" || exit 1
build_status=0
swift_status=0
guard_status=0
preservation_status=0
swift build --product artifact-inspection-checks || build_status=$?
swift run --skip-build artifact-inspection-checks --pat-2708-pinned-signature || swift_status=$?
node scripts/checks/PinnedSignatureSourceGuard.mjs || guard_status=$?
node --test services/catalogue/tests/pinned-signature-live-proof-preservation.test.mjs || preservation_status=$?
printf 'PAT-2708 focused statuses: build=%s swift=%s source=%s preservation=%s\n' "$build_status" "$swift_status" "$guard_status" "$preservation_status"
[ "$build_status" -eq 0 ] && [ "$swift_status" -eq 0 ] && [ "$guard_status" -eq 0 ] && [ "$preservation_status" -eq 0 ]
