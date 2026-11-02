#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
swift build
swift run --skip-build reference-verification-checks
swift run --skip-build patched-proof verify-references

./scripts/verify-artifacts.sh
./scripts/verify-mach-o-architectures.sh
./scripts/verify-unstapled-evidence.sh
./scripts/verify-pinned-signature.sh

./scripts/verify-core.sh

./scripts/verify-artifact-size-policy.sh

./scripts/verify-transaction.sh

./scripts/verify-ui.sh

./scripts/verify-native-shell.sh

swift run --skip-build patched-update-preferences-checks
swift run --skip-build patched-activity-checks

./scripts/verify-client-flow.sh

./scripts/verify-operator.sh

./scripts/verify-operator-session.sh

./scripts/verify-scheduling.sh
bash scripts/verify-attention.sh

./scripts/verify-licensing.sh

./scripts/verify-activation.sh

./scripts/verify-licence-support.sh

./scripts/verify-installomator-discovery.sh
./scripts/verify-vendor-discovery.sh
./scripts/verify-homebrew-discovery.sh
bash scripts/verify-autopkg-transport-plan.sh
node --test services/catalogue/tests/vendor-electron-boundaries.test.mjs
node --test services/catalogue/tests/upstream-resource.test.mjs

./scripts/verify-catalogue-protocol.sh
node --test services/catalogue/tests/catalogue-protocol-boundaries.test.mjs
node --test services/catalogue/tests/package-registration-preservation.test.mjs
node --test services/catalogue/tests/native-composition-package-registration-preservation.test.mjs
node --test services/catalogue/tests/preferences-package-registration-preservation.test.mjs
node --test services/catalogue/tests/activity-package-registration-preservation.test.mjs
node --test services/catalogue/tests/schedule-record-registration-preservation.test.mjs

./scripts/verify-support-request-protocol.sh
node --test services/catalogue/tests/coverage-wire.test.mjs

bash scripts/verify-inspection-protocol.sh
node --test services/catalogue/tests/inspection-protocol-boundaries.test.mjs

./scripts/verify-disposable-proof.sh

./scripts/verify-disposable-boundaries.sh

swift run --skip-build patched-disposable-client-checks
swift run --skip-build patched-disposable-gateway-checks
swift run --skip-build patched-disposable-process-checks

./scripts/verify-owned-process.sh
swift run --skip-build patched-disposable-native-ui-checks

./scripts/verify-licence-support-ui.sh
bash scripts/verify-network.sh
bash scripts/verify-development-toolset.sh
