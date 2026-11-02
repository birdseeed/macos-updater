#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build --product patched-disposable-proof
swift build --product patched-disposable-proof-checks
bin=$(swift build --show-bin-path)
# Host-only packaging. The guest wrapper never runs Swift or probes a toolchain.
mkdir -p .build/disposable-runtime
cp "$bin/patched-disposable-proof" .build/disposable-runtime/patched-disposable-proof
cp scripts/prove-disposable.sh .build/disposable-runtime/prove-disposable.sh
swift run --skip-build patched-disposable-proof-checks
