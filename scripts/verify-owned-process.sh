#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
root=$(pwd -P)

node --test services/catalogue/tests/owned-process-package-registration-preservation.test.mjs

# Resolve the installed compiler and its own built-in Swift Testing macro plugin.
swift=$(/usr/bin/xcrun --find swift)
case "$swift" in
    /*) ;;
    *) echo 'Owned-process verification requires an absolute installed Swift path' >&2; exit 1 ;;
esac
toolchain_usr=$(CDPATH= cd -- "$(dirname -- "$swift")/.." && pwd -P)
plugin="$toolchain_usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ ! -f "$plugin" ]; then
    echo "Owned-process verification requires the installed Swift Testing plugin: $plugin" >&2
    exit 1
fi

# All writable SwiftPM state and the fresh result remain inside the project.
if [ -L .build ] || { [ -e .build ] && [ ! -d .build ]; }; then
    echo 'Owned-process verification requires .build to be a plain directory' >&2
    exit 1
fi
mkdir -p .build
for directory in .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security; do
    if [ -L "$directory" ] || { [ -e "$directory" ] && [ ! -d "$directory" ]; }; then
        echo "Owned-process verification requires a plain directory: $directory" >&2
        exit 1
    fi
    mkdir -p "$directory"
done
result="$root/.build/owned-process-fullgate-results.xml"
if [ -L "$result" ] || { [ -e "$result" ] && [ ! -f "$result" ]; }; then
    echo 'Owned-process verification refuses an unsafe prior XML result' >&2
    exit 1
fi
rm -f "$result"
"$swift" test \
    -Xswiftc -load-plugin-library -Xswiftc "$plugin" \
    --jobs 2 --disable-xctest --enable-swift-testing \
    --filter OwnedProcessLifecycleTests \
    --cache-path "$root/.build/swiftpm-cache" \
    --config-path "$root/.build/swiftpm-config" \
    --security-path "$root/.build/swiftpm-security" \
    --manifest-cache local --scratch-path "$root/.build" \
    --xunit-output "$result" --disable-keychain --disable-netrc

/usr/bin/python3 -I -B - <<'PY'
import os
import stat
import xml.etree.ElementTree as ET

path = '.build/owned-process-fullgate-results.xml'
info = os.lstat(path)
if not stat.S_ISREG(info.st_mode) or info.st_size == 0 or info.st_size > 16 * 1024 * 1024:
    raise SystemExit('Owned-process verification requires fresh bounded regular XML results')
with open(path, 'rb') as source:
    data = source.read(16 * 1024 * 1024 + 1)
if len(data) != info.st_size:
    raise SystemExit('Owned-process XML results changed during reading')
root = ET.fromstring(data)
nodes = list(root.iter())
if any(node.tag in ('failure', 'error', 'skipped') for node in nodes):
    raise SystemExit('Owned-process XML reports a failure, error or skipped test')
for node in nodes:
    for attribute in ('failures', 'errors', 'skipped', 'skips'):
        value = node.get(attribute)
        if value is not None and (not value.isdecimal() or int(value) != 0):
            raise SystemExit('Owned-process XML advertises failures, errors or skips')
cases = sum(node.tag == 'testcase' for node in nodes)
if cases < 55:
    raise SystemExit(f'Owned-process XML contains only {cases} actual test cases; at least 55 required')
print(f'Owned-process verification: {cases} actual test cases, no failures, errors or skips')
PY
