# Exact toolchain follow-up, 2 November 2026

This follow-up records bounded local checks against the private personal snapshot at `824aacb2b361fd86ce2c8305fbcff20e9ed4e094`. It supplements the earlier candidate record; it does not rewrite its historical results or certify the product.

## Scope and evidence

The exact Node v24.21.0 archive was verified against the official HTTPS distribution SHA-256 manifest. npm 11.19.0 was verified against npm registry version metadata and SHA-512 integrity. The report records commands, exit codes, outputs, checksums, source manifests and prerequisite-recovery evidence in the persistent Codex Security artifact `artifacts/exact-tool-checks/REPORT.md` (44 accompanying evidence files). Temporary tools and caches were isolated; no global installation or profile changes were made.

For `service/licensing`, `npm ci --ignore-scripts --no-audit --no-fund` passed without lifecycle scripts, followed by direct `tsc --noEmit` and the Vitest unit suite: 647 tests passed across 10 files. The first disposable subtree omitted 23 tracked synthetic Activation/Licensing fixture files: 412 tests passed and two suites failed with missing-fixture errors. The missing tracked fixtures were then copied into the disposable check tree and the complete unit suite passed. The original snapshot source remained unchanged.

The report's source comparison covered 1,711 copied source files with zero hash mismatches. No Wrangler, emulator, product, helper, workflow, service, deployment or native installed-app journey was started.

## Limits

These results cover the listed licensing checks only. They do not establish full native application behaviour, complete security, release readiness or deployed remediation. In particular, fixture and type-check results do not certify the complete consumer installed-update journey, which remains unfinished in this discontinued prototype.
