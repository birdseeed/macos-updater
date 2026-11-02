# Build and reference verification

The Swift package declares macOS 13 or later and Swift 6 or later; this is a source-build floor, not promised consumer OS support. See the [platform launch contract](platform-launch-contract.md) for the conditional macOS 15+ Apple-silicon product boundary. Foundation, Darwin and CryptoKit come from the Apple SDK. The original twelve reference cases use a dependency-free executable; historical Command Line Tools observations below do not qualify every later check or native test toolchain.

From the repository root:

```sh
./scripts/verify.sh
swift run patched-proof verify-references
swift run patched-proof verify-references --root /absolute/path/to/checkout
```

The full gate builds declared targets and invokes the Swift/Node source, fixture, boundary and offscreen checks registered in `scripts/verify.sh`, including later client, scheduler, discovery, networking and development-toolset registrations. The script is the current command index; counts in the dated component notes below describe their original proof slices, not a current total. `reference-verification-checks` and the real reference check remain part of that gate. A successful command prints that two preserved references match the manifest. Usage errors exit 2; verification failures exit 1 with a reason. The default root is the working directory. Use a physical root path: symlinks in the root, its ancestors, the manifest, reference directories or files are refused.

The verifier reads schema 1 of `source-provenance.json`. Exactly the licence and historical recipe destinations are permitted, with positive bounded integer byte lengths, lowercase SHA-256 values and explicit `extracted: true`, `read_only_reference: true`, `actionable: false` flags. Reference records have a closed set of field names; unexpected execution flags fail. Root documentation fields are permitted to evolve. SHA-256 and lengths are checked over the bytes read from each opened descriptor, with a one-MiB limit per file, including the manifest. Files must be regular files. Descriptor-relative opens refuse symlinks without a separate path-check/read window.

Checks use copies of the committed references. They cover preservation of inputs, same-length corruption, truncation, missing files, malformed JSON/schema/records, duplicate or missing destinations, invalid lengths/digests/flags, unknown execution fields, unsafe paths, directory substitution and file/directory/root/ancestor symlinks. The parent observed all twelve cases fail against an empty-result stub. CHECK-MODIFIED: the fixture's Foundation path resolution retained `/var`, so its baseline now uses POSIX `realpath` to obtain `/private/var`; explicit adversarial symlinks are preserved. A repeated parent red/green check is required against the corrected harness.

The same gate runs on the configured private runner `patched-macos-01` for pull requests, pushes to `main` and manual dispatches, with read-only contents permission. The workflow variable `PATCHED_MACOS_ACTIONS_ENABLED` and same-repository pull-request guard control these CI jobs. The shared owner queue pause separately controls queue execution; ordinary CI does not resume that queue. Checkout is pinned to `11d5960a326750d5838078e36cf38b85af677262` and does not persist credentials. See [private runner CI routing](linux-runner-ci.md) for its operating procedure and the evidence required for live proof. These source-verification workflows do not provide release or deployment proof. A configured route does not establish native execution or a successful check.

This is reference integrity against a repository-selected manifest. A coordinated change to reference bytes and their manifest can pass; neither the digest nor recorded source metadata independently authenticates a vendor. The verifier never interprets or executes recipe contents. It supplies no artifact signature, Team ID, notarisation, catalogue-trust, app build, installed update or release evidence. The provenance manifest's historical no-build and publication status fields remain the original bootstrap record.

Parent full-diff acceptance, independent review under the current canonical workspace review policy and CI results remain publication gates. Actual provider cost is unknown, not zero; the owner cost-reconciliation waiver and £500 cap remain in force.

## Catalogue core proof

The full gate additionally runs `./scripts/verify-artifacts.sh` (179 fixture cases plus the reviewed pin record) and `./scripts/verify-core.sh`. The core uses a dependency-free acceptance executable because this Mac has Command Line Tools without XCTest discovery. The parent observed the Phase 1 API stubs fail all 236 original behavioural cases before implementation. The implemented core retains those unchanged checks and adds thirteen clock/flush/bootstrap-ancestor regressions; both executables run in the full gate. `patched-core-proof` is a fixture-only consumer for explicit bootstrap, ordinary catalogue verification and artifact byte consistency. Required `F_FULLFSYNC` failures refuse acceptance; native syscall/restart proof is not a hardware power-loss guarantee. See [the catalogue fixture contract](../Fixtures/Catalogue/README.md) for state, signature and test boundaries.

## Fixture transaction and native view

The full gate includes `./scripts/verify-transaction.sh` (260 cases) and `./scripts/verify-ui.sh` (51 cases). The transaction checks operate on newly created owned disposable fixture roots beneath `.build`, including injected failures and recovery by a separate process. The view checks render the actual shared SwiftUI view offscreen in four states and retain PNGs and metadata under a new `.build/patched-ui-fixture-<UUID>` directory for inspection. `PatchedApp` is compiled and never launched by the gate. Neither fixture operation nor rendered output proves an installed update or fresh macOS trust. See [the transaction and view contract](transaction-recovery.md).

## Read-only operator session

The full gate also runs `./scripts/verify-operator-session.sh` (19 cases). It builds `PatchedOperatorApp`, paints the session view offscreen in four states under a new `.build/patched-operator-session-<UUID>` directory and exercises the real verifier only with a ten-byte and a missing file. No app is launched and nothing is mounted. See [operator session](operator-session.md).

## Documentation reconciliation on relevant delivery

Before accepting a relevant delivery, compare affected current guidance with the exact source, later owner decisions and live owning Linear issues. Update stale capability descriptions and conditional test requirements, date historical proof without changing raw evidence, and check affected local links. Separate source/fixture/offscreen, native, installed, hosted and client-release claims. Keep pending implementation with its existing owner rather than creating a parallel status list or duplicate ticket. This documentation check starts no queue, native run, service or schedule.
