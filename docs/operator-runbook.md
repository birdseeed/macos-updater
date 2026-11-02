# PAT-2583 operator runbook: verify, sign, publish

Policy boundary, 27 October 2026: this runbook describes the existing pinned, fixture-v1 operator path, whose receipt prerequisites remain unchanged. It is not a universal central-download requirement for the consumer catalogue. PAT-2724 permits source-verified metadata/approved vendor-native routes, but their authenticated mapping and native v1/fixture v2, evidence and exact-URL migration still require PAT-2693 acceptance. No metadata record can manufacture this path’s live receipt or enable its refusing production signer/publisher.

**Status: implemented, fixture scope.** Verification, signing, publication, the controller and the shared view are implemented in `Sources/PatchedOperator`, and `Tests/PatchedOperatorTests` exercises them. This file describes what the code does and how to reproduce the checks. It is not itself evidence that a run passed: the result of each gate run, and of the explicit live commands below, is whatever the person who ran it recorded.

This proof is fixture scope only. It has no production key, no key discovery, no production publication, no SaaS database or host, no licensing or billing, and it grants no installation authority. `PatchedOperatorApp` is compiled by the gate and never launched by a gate or an agent.

## Three separate steps

Each step runs only on its own explicit choice. None starts another, and nothing runs at startup, on a timer or in the background.

1. **Verify.** `OperatorVerification.verifyPinnedArtifact(version:path:)` is the only source of a live receipt. It calls `ArtifactInspector.inspectLocal` itself for one compiled Firefox 157.0 or 157.0.1 pin and builds a `VerifiedArtifactReceipt` from that fresh inspection alone: byte integrity verified, no refusal, cleanup verified, app checks passed, exact identity, digest and length. The disk image's own signature, Gatekeeper and ticket results are recorded separately and stay failures for the two reviewed unsigned images. A caller's `InspectionReport`, `AppEvidence`, exported JSON or replay is refused by `acceptRecordedInspection` as `recordedEvidenceRefused`; no public entry takes one.
2. **Sign.** Builds the payload of `Fixtures/Catalogue/README.md` from the receipt's values and an explicit `CatalogueRequest` (`keyID`, `catalogueID`, `sequence`, `issuedAt`, `expiresAt`, `minimumOS`, `maximumOS`), asks the signer for a signature over `im.patched.catalogue.v1`, one NUL byte and the exact payload bytes, and verifies the answer against the root's public fixture trust before returning a `SignedCatalogue`. Signing writes no published file.
3. **Publish.** Writes the exact signed bytes and separate evidence into one new directory, reads the committed files back and only then returns a `PublishedCatalogue`.

`CataloguePublisher.sign` and `CataloguePublisher.publish` are the ordinary entries and always refuse with `notAuthorized`. A future production configuration needs its own separately approved scope.

## Operator surface

`OperatorController` and `OperatorView` are the surface. `OperatorConfiguration` is all a caller may supply: a display name and up to three callbacks that return the library's own output-only results (`VerifiedArtifactReceipt`, `SignedCatalogue`, `PublishedCatalogue`). No caller can manufacture one of those results or set a status directly: the types have no public constructor or decoder, and the surface takes no status or boolean. A callback can still return any result the library issued earlier, including one from another root or an earlier verification. Callbacks are trusted process code and nothing here is a sandbox; the controller checks that each result follows from the one it currently holds, as described below.

- The default configuration has no artifact, no signing capability and no output location. All three steps are disabled, each with its own reason, and choosing one does nothing.
- Creating a controller runs nothing. It owns no timer, network request, scan or store, and the view has no `task` or `onAppear`.
- `choose(_:)` is the only action. It calls the chosen step's own callback once and never another step's. A disabled step calls nothing, and so does a choice made from inside a running callback.
- A step reads as done only while the controller holds that step's result. Choosing Verify first drops the receipt, the signature and the publication result, so a refused verification leaves Sign and Publish disabled. Choosing Sign first drops the signature and the publication result. Choosing Publish first drops the publication result.
- A signed result is held only when it was made from the receipt the controller currently holds: the same held artifact object the verification issued, with the same origin and inspection record SHA-256, fixture catalogue origin and no fresh OS validation, installation authority or published flag. Two verifications of unchanged bytes produce identical public records, so an equal digest, path or encoding is not enough; the signed result of an earlier verification is refused after verifying again.
- A published result is held only when it reports the signed catalogue the controller currently holds: the same `keyID`, `catalogueID`, sequence, envelope SHA-256 and byte length, payload SHA-256, inspection record SHA-256 and receipt origin, fixture origin and no fresh OS validation, installation authority or production publication. Its directory must be exactly `publications/sequence-<n>` beneath the root that signed catalogue was signed in, with exactly `catalogue.json`, `evidence.json`, `inspection-record.json` and `publication.json` inside it. The same payload published from another root is refused.
- A result that fails either check is dropped and the step shows `Refused` with the sentence for `invalidState`. A refused Sign leaves Publish disabled. The callback has still run once; the check decides only what the surface holds and says.
- A refused step shows `Refused` and one plain sentence. Each of the 32 `OperatorFailure` cases has its own sentence in `OperatorViewText.refusalReason`; any other error shows `The step was refused.` The code name is never shown.
- The artifact line shows the caller's display name until a receipt is held, then the file name the receipt itself records. The display name is words only and carries no path authority.
- Verify status comes from the receipt's own fields. A fixture receipt reads `Fixture bytes matched. macOS checks not run`. A live receipt reads `Bytes matched the approved pin. App checks passed.` followed by the disk image's own result, which for the two reviewed unsigned images is `Disk image checks did not pass`. No wording says the disk image passed when it did not, and none says anything was installed.
- Sign reads `Signed with the fixture key. Not published` until Publish is chosen and succeeds, then Publish reads `Published to the local fixture folder`. Both stay fixture wording whatever the receipt's origin, because the key and the consumer authority are fixture only.

The view is plain SwiftUI with system text styles and a SwiftUI-drawn button style, so the same view paints offscreen. Nothing in the repository wires `OperatorConfiguration` to a live artifact, a key or an output folder: `PatchedOperatorApp` uses the default configuration, is compile-only and is never launched by a gate or an agent.

## Test-only authority

`FixtureOperatorAuthority` is `@_spi(Testing)`. It owns one root it exclusively created as a direct child of the `.build` directory that holds the running check executable, named `patched-operator-fixture-<suffix>`. It holds no key. The only private key bytes are deterministic fixture bytes in `Tests/PatchedOperatorTests/Support.swift`; the library receives a signing callback and can neither mint a receipt through it nor skip verifying its answer.

`fixtureReceipt` accepts a single-link owned mode-0600 regular file of 1 to 65,536 bytes directly inside the root's `input` directory. Its receipt is always `origin: fixture` with every macOS field false. Output signed with fixture trust is `origin: fixture`, `freshOSValidation: false`, `installationAuthorized: false` for the catalogue consumer, whatever the receipt's origin. A live receipt's origin is recorded only in the separate evidence.

## Root layout

`createFreshRoot` is the separate authority to create a namespace. It refuses any existing entry at the name. `reopenRoot` is ordinary use and refuses missing, altered or unsafe state without repairing it.

| Entry | Contents |
| --- | --- |
| `namespace.json` | `schemaVersion: 1`, `namespace: patched-operator-fixture-v1`, `keyID`, `catalogueID` |
| `checkpoint.json` | `schemaVersion: 1`, `keyID`, `catalogueID`, `sequence`, `payloadSHA256`. A fresh root records sequence 0 and 64 zeros. |
| `lock` | Empty. Held exclusively and without blocking for each sign and publish. A second process, or a call made from inside a signer or hook of the same process, is refused as `busy`. Nothing waits or retries. |
| `input/` | Fixture artifacts. |
| `publications/sequence-<n>/` | `catalogue.json`, `inspection-record.json`, `evidence.json`, `publication.json` |

Directories are mode 0700 and files mode 0600, single-link and owned by the effective user. Every path is reached through held no-follow descriptors. Symlinks, hard links, special files, unsafe modes, traversal, aliases, renamed ancestors and replaced names are refusals.

## Sequence and state

Signing records the highest signed sequence and the SHA-256 of its exact payload in `checkpoint.json` before returning. A lower sequence is refused as `replay`. An equal sequence is accepted only for the identical payload bytes. Publishing requires the signed catalogue to be the one the checkpoint records, so a superseded signature is refused as `replay`.

Request limits match the consumer: positive sequence, times from 0 to 9,007,199,254,740,991, expiry after issue, lifetime at most 259,200 seconds, issue at most 300 seconds ahead of a finite clock in the same range, expiry exclusive, and numeric dotted OS versions with minimum not above maximum. Out-of-range values refuse before any conversion.

## Evidence revalidation

Sign and publish each recheck the artifact the receipt named: the path must still name the held file beneath unchanged ancestors, with one link and the exact length and digest. In-place edits refuse as `digestMismatch` or `lengthMismatch`, an added link as `hardlink`, and a deleted, renamed or replaced file or directory as `identityChanged`.

## Publish ordering

Publish exclusively creates `publications/pending-sequence-<n>`, writes the inspection record, the evidence, the catalogue and the publication record, calls `fsync` and `F_FULLFSYNC` on each file, syncs the pending directory, renames it to `sequence-<n>` without replacing anything, syncs `publications`, then reads the committed files back. Partial files exist only under the pending name. A failed step refuses with `persistenceFailed`, leaves what it wrote in place as evidence and is never retried into the same name: an existing pending or accepted directory refuses as `existingOutput`. There is no weaker flush fallback and no recursive cleanup.

`evidence.json` and `inspection-record.json` are separate from the signed catalogue and linked by SHA-256 through `publication.json`. The catalogue envelope and payload carry exactly the fields of the fixture contract and nothing else.

## Recovery and manual failure handling

Nothing repairs, resets or cleans up on its own. Each case below is left for a person to inspect.

- `busy`: another step holds the lock. Wait for it to finish and choose the step again.
- `missingState` or `corruptState`: `reopenRoot` refuses and changes nothing. There is no reset entry. The only way forward is a new root from `createFreshRoot` at a new name, which starts again at sequence 0 and has no memory of the old root's sequences.
- `existingNamespace`: `createFreshRoot` found something at the name, including what an interrupted creation left. It is not reused or removed. Choose a new name.
- `persistenceFailed` during Sign: the checkpoint may or may not have advanced. Reopen the root and read `checkpoint.json` before signing again; an equal sequence is accepted only for identical payload bytes.
- `persistenceFailed` or an interruption during Publish: `publications/pending-sequence-<n>` or `sequence-<n>` may exist, complete or partial. Both then refuse as `existingOutput` for that sequence. Inspect the directory by hand, treat a pending directory as unpublished, and sign a higher sequence to publish again. The library never deletes either.
- `existingOutput` on a second Publish of the same catalogue: the first publication is untouched. The surface shows `Refused` for that choice because it no longer holds a result; the files on disk are the record.
- `identityChanged`, `digestMismatch`, `lengthMismatch` or `hardlink` at Sign or Publish: the artifact changed after it was verified. Verify again.

## Checks

`./scripts/verify-operator.sh` runs `patched-operator-checks` and is part of `./scripts/verify.sh`. Three narrower explicit commands run only the root creation boundary, root lock reentrancy and result chain regressions:

```sh
swift run --skip-build patched-operator-checks --root-creation-regressions
swift run --skip-build patched-operator-checks --root-lock-regressions
swift run --skip-build patched-operator-checks --result-chain-regressions
```

The surface checks paint the actual `OperatorView` offscreen with `ImageRenderer` from the check executable, in the default, refused, verified, signed and published states, and keep the PNGs in new `patched-operator-ui-fixture-<id>` directories beneath `.build`. The default and refused pictures are written together with a `metadata.json`; the verified, signed and published pictures are written to a second directory that has no metadata file. The gate prints the paths. These are fixture pictures for visual review. They are not product, deployment or installation evidence.

The unit gate mounts no disk image and uses no network. It builds physical fixtures beneath `.build`, verifies signed bytes independently with CryptoKit, runs the real `CatalogueVerifier` over the physically published file in this process and in a separate process, restarts the operator in a separate process, holds the lock from another descriptor and injects refusals at each write, flush and rename boundary. Test hooks can observe or refuse and can never return a result.

Fresh inspection of an existing pinned image is a separate explicit command, not part of the gate:

```sh
swift run --skip-build patched-operator-checks --live-inspection 157.0.1 /absolute/path/to/Firefox.dmg
```

It mounts the image read-only through the existing inspector and launches nothing.

### Live catalogue proof

One further explicit command, also outside the gate, checks that the actual pinned verification happens before the exact verified artifact's catalogue is signed:

```sh
swift run --skip-build patched-operator-checks --live-catalogue-proof 157.0.1 "/Users/example/Documents/Patched/proofs/firefox-inspection-20261007/Firefox 157.0.1.dmg"
```

It accepts only 157.0.1 at that one approved preserved path and exits 2 for anything else. It takes no output path, and nothing is read or written for a refused argument. The unit gate and an implementation task never run it, and no positive OS inspection starts automatically. An explicit, owner-authorised, read-only parent acceptance run may invoke it against that existing approved pinned source. That grants no new network, artifact, installation or key authority, and this file records no result for it. The steps it asserts, in order:

1. `createFreshRoot` makes a new operator root beneath `.build`.
2. The approved source is checked against the compiled pin, copied to a mode-0600 file in the root's `input`, and both are checked again. The source is never changed.
3. `OperatorVerification.verifyPinnedArtifact` inspects the copy and returns a live receipt with the unsigned container results kept as failures.
4. `FixtureOperatorAuthority.sign` with the test-only signer, an explicit current clock and request. The signature, frame and payload are checked with CryptoKit against the compiled pin.
5. `publish`, then the four physical files are read back: `inspection-record.json` must be the inspector's own report as the receipt bound it, and `evidence.json` must say `receiptOrigin: live` beside `catalogueOrigin: fixture`.
6. The real `CatalogueVerifier` and `ArtifactVerifier` consume the published bytes and the copied artifact, using the OS version the inspector recorded. The installed version `157.0` is a policy comparison input, not a statement about any installed Firefox.
7. `patched-core-proof` consumes the same files in a separate process, given only the exported public key.
8. A changed envelope and an unrelated key are refused in both processes, and no state or operator file changes.

The operator root and a separate `patched-operator-live-proof-<id>` directory are kept either way. The second holds the public key, the child output and `proof.json`, or `failure.json` when any step failed. What a pass shows, kept separate:

- The app inside the image passed the inspector's app checks on that run, on that Mac.
- The disk image's own signature, Gatekeeper and ticket results are recorded as observed. For this unsigned image they are failures and stay failures.
- The catalogue is signed with the deterministic test key and published to a local fixture folder. It is a fixture-key publication.
- The consumer accepted it under fixture trust only: `origin: fixture`, `freshOSValidation: false`, `installationAuthorized: false`.

A pass is therefore an operating proof of a local test-key catalogue only: not an installation, a product release, a production key or production trust.

## Limits

- The persistence assumption is a trusted same-user namespace. A process running as the same user can restore an earlier complete checkpoint, or swap a newly created directory before its first open; owner, mode and exclusive-create checks still apply.
- Revalidation narrows but does not close the window between the last check of an artifact and a later use of it by something else. The receipt binds bytes and a physical file at the times it was checked.
- A matching digest binds bytes to a reviewed pin. It does not independently authenticate Mozilla.
- Successful syscalls and restart checks are not a power-loss guarantee.
- File bounds for this proof: fixture artifact 1 to 65,536 bytes, inspection record 4,194,304, evidence 16,384, state files 8,192, envelope 131,072, payload 65,536. A live artifact must be exactly the compiled pin's length. Anything outside refuses as `resourceLimit` or `lengthMismatch`.
- The checkpoint is a single high-water mark per root. It is not shared between roots, and a new root starts at 0.
- The surface runs each callback synchronously on the main actor. A live verification of a large image would hold the window until it returns. Nothing wires that today.
- There is no production trust anywhere in this proof: no production key, key discovery, production catalogue, licence or billing.
- A painted view, a fixture publication or a passing gate is not a released app, a production catalogue or an installed update.

## Ticket path note

The ticket listed `Sources/PatchedOperator/PatchedOperatorApp.swift`. The app entry lives at `Sources/PatchedOperatorApp/PatchedOperatorApp.swift` so that the library and the compile-only executable are separate targets and the check executable can link the library without a second `@main`.

## Proposed hosted catalogue successor

The [catalogue service architecture](catalogue-service-architecture.md) and [bounded implementation briefs](catalogue-service-implementation-plan.md) describe the proposed Cloudflare successor for PAT-2606. These are proposed interfaces only. The current fixture roots, output-only receipts, test key, local publication and default production refusals above remain the actual contract at this source revision.

Proposed hosted actions keep Verify, Sign and Publish distinct. Verify supplies exact current artifact/evidence identity; Sign submits a policy-bound publication intent to the dedicated non-public signer rather than arbitrary bytes; Publish stages immutable signed objects, conditionally commits the revision and independently fetches/verifies public bytes before reporting hosted success. Signer-owned policy/sequence state, app-distributed verification keys, key recovery, expiry, withdrawal, source/channel/paid-generation compatibility and per-route interaction/restart evidence are defined in the architecture. No endpoint, key, production configuration, schedule or installation capability is enabled by these links.

Proposed latest-owner interfaces: [platform launch proof matrix](platform-launch-contract.md), [shared public support projection](website-catalogue-contract.md) and [website build brief](website-catalogue-implementation-plan.md). Publication must bind exact native/universal dependency and verified route scope, withhold unverified/research entries and keep private notes/status out of public metadata. Optional notes/vendor link and private in-app status/completion are accepted; no attachments or launch email. These links add no operator signing/publication, target installation or website deployment authority.
