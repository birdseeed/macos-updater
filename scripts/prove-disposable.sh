#!/bin/sh
set -eu
# Packaged beside the measured native executable. No toolchain, default case or implicit build.
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
if [ ! -x "$directory/patched-disposable-proof" ]; then
    echo 'Run the packaged wrapper beside its verified native executable.' >&2
    exit 2
fi
exec "$directory/patched-disposable-proof" "$@"
