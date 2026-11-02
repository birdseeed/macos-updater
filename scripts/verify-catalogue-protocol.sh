#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
node --version
swift --version
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Catalogue protocol checks require installed Node >=22"); process.exit(1); }'
mkdir -p .build/catalogue-protocol-module-cache
swift -module-cache-path .build/catalogue-protocol-module-cache tools/catalogue-protocol-vectors.swift > .build/catalogue-protocol-swift-vectors.json
node --test services/catalogue/tests/catalogue-protocol.test.mjs
