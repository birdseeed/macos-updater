#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
expected_node="$(cat service/licensing/.node-version)"
if [[ "$(node --version)" != "v${expected_node}" ]]; then
  echo "Licensing fixture requires Node ${expected_node} on PATH; current: $(node --version). See service/licensing/README.md." >&2
  exit 1
fi
if [[ "$(npm --version)" != '11.19.0' ]]; then
  echo 'Licensing fixture requires npm 11.19.0 on PATH.' >&2
  exit 1
fi
npm --prefix service/licensing ci --ignore-scripts
npm --prefix service/licensing run typecheck
npm --prefix service/licensing run test:unit
npm --prefix service/licensing run test:d1-local

# PAT-2642 additive account/session actual D1 checks; T0 runner stays unchanged.
node service/licensing/tests/d1-local/account-owner-check.mjs controls
node service/licensing/tests/d1-local/account-owner-check.mjs suite
node service/licensing/tests/d1-local/account-runtime-controls.mjs

# PAT-2643 additive S1b local D1 trial/lease/cleanup checks.
node service/licensing/tests/d1-local/cleanup-owner-check.mjs controls
node service/licensing/tests/d1-local/cleanup-owner-check.mjs runtime-controls
node service/licensing/tests/d1-local/cleanup-owner-check.mjs suite

# PAT-2643 additive required-write and retention-boundary regressions.
node service/licensing/tests/d1-local/s1b-boundaries.test.ts

# PAT-2645 additive synthetic billing unit and actual D1 checks.
./scripts/verify-billing.sh

# PAT-2644 additive single-owner actual D1 activation checks.
node service/licensing/tests/d1-local/activation-concurrency.test.ts

# PAT-2644 fresh bounded repair independent actual D1 regressions.
node service/licensing/tests/d1-local/activation-repair.test.ts

# PAT-2644 independent safe-integer operator guard boundary.
node service/licensing/tests/d1-local/activation-guard-boundary.test.ts

# PAT-2675 independent exact native fixture-fault projection controls.
node service/licensing/tests/d1-local/fixture-fault-schema-controls.mjs
node --test service/licensing/tests/d1-local/fixture-fault-schema-binding-controls.mjs
node --test service/licensing/tests/d1-local/fixture-fault-schema-binding-edge-controls.mjs

# PAT-2649 additive source web infrastructure, actual D1 and existing-Chrome checks.
node service/licensing/tests/d1-local/account-web-runtime-controls.mjs
node service/licensing/tests/d1-local/account-web.test.ts
node service/licensing/tests/browser/account-web.test.mjs
