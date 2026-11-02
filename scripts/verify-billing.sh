#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
[[ "$(node --version)" == 'v24.21.0' ]] || { echo 'Billing fixture requires pinned Node 24.21.0 on PATH.' >&2; exit 1; }
[[ "$(npm --version)" == '11.19.0' ]] || { echo 'Billing fixture requires pinned npm 11.19.0 on PATH.' >&2; exit 1; }
status=0
npm --prefix service/licensing ci --ignore-scripts || status=1
npm --prefix service/licensing run typecheck || status=1
(
 cd service/licensing
 ./node_modules/.bin/tsc --ignoreConfig --noEmit --target ES2022 --module ESNext --moduleResolution Bundler --strict --skipLibCheck --allowImportingTsExtensions --types @cloudflare/workers-types,node tests/d1-local/billing-runtime.ts tests/d1-local/billing-inbox.test.ts || status=1
 ./node_modules/.bin/vitest run tests/billing || status=1
 exit "$status"
) || status=1
node service/licensing/tests/d1-local/billing-inbox.test.ts || status=1
(
 cd service/licensing
 ./node_modules/.bin/tsc --ignoreConfig --noEmit --target ES2022 --module ESNext --moduleResolution Bundler --strict --skipLibCheck --allowImportingTsExtensions --types @cloudflare/workers-types,node tests/d1-local/billing-lifecycle-runtime.ts tests/d1-local/billing-lifecycle.test.ts tests/d1-local/billing-lifecycle-races.test.ts tests/d1-local/billing-lifecycle-faults.test.ts tests/d1-local/billing-lifecycle-restart.test.ts
) || status=1
node service/licensing/tests/d1-local/billing-lifecycle.test.ts || status=1
node service/licensing/tests/d1-local/billing-lifecycle-races.test.ts || status=1
node service/licensing/tests/d1-local/billing-lifecycle-faults.test.ts || status=1
node service/licensing/tests/d1-local/billing-lifecycle-restart.test.ts || status=1
exit "$status"
