#!/bin/bash
set -euo pipefail
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
# Exclusive local output. No application, helper or installer is launched.
mkdir -p .build/attention-checks
run_dir=$(mktemp -d "$PWD/.build/attention-checks/run.XXXXXXXX")
chmod 700 "$run_dir"
sources=()
while IFS= read -r path; do sources+=("$path"); done < <(find Sources/PatchedScheduling -name '*.swift' -type f | LC_ALL=C sort)
checks=()
while IFS= read -r path; do checks+=("$path"); done < <(find Tests/PatchedAttentionChecks -name '*.swift' -type f | LC_ALL=C sort)
swiftc -swift-version 6 -parse-as-library -emit-library -emit-module -module-name PatchedScheduling \
    -emit-module-path "$run_dir/PatchedScheduling.swiftmodule" -o "$run_dir/libPatchedScheduling.dylib" "${sources[@]}"
swiftc -swift-version 6 -I "$run_dir" -L "$run_dir" -lPatchedScheduling \
    -Xlinker -rpath -Xlinker "$run_dir" -o "$run_dir/attention-checks" "${checks[@]}"
"$run_dir/attention-checks"
