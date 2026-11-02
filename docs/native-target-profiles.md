# Disposable native target profiles

`DisposableTargetProfile` selects one of two compiled contracts. Selection is
intent only. The harness requires an exact `--target-id`; the disposable native
UI accepts the same optional flag and defaults to the legacy contract when it is
omitted. Unknown selectors, case-folded IDs and caller-supplied guest facts refuse.
The ordinary client and its inventory traversal are unchanged.

| Contract | Legacy | SSD testing |
|---|---|---|
| Target ID | `parallels-0A0A0A0A-0000-4000-8000-000000000001` | `parallels-0A0A0A0A-0000-4000-8000-000000000002` |
| Host VM selector UUID | `0a0a0a0a-0000-4000-8000-000000000001` | `0a0a0a0a-0000-4000-8000-000000000002` |
| Physical IOPlatformUUID SHA256 | `d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959` | `a44c836bfbda0c6beb1df7b3b3178a171479d362ecfacd534a62b09890dde705` |
| Account / home | `andy` / `/Users/andy` | `runner` / `/Users/runner` |
| Hostname | `mac-staging.local` | `patched-test-01` |
| Run parent | `/Users/andy/PatchedProof` | `/Users/runner/PatchedTesting` |

Both contracts require real, effective and console UID 501, hypervisor 1,
macOS 27.0.1 build 26A434 and arm64. Host selector UUIDs are distinct from the
physical IOPlatformUUID hashes. The raw physical identifier stays inside the
physical observer. These compiled expectations do not establish fresh guest proof.

The validated request retains an immutable typed profile. Physical guest
observation precedes runtime and native scope admission and repeats at existing
confirmation boundaries. The guard reads the account, HOME, console,
hypervisor, OS, build, architecture, hostname and physical UUID independently.
It never accepts synthetic facts or decoded evidence as authority. A mismatch
refuses the selected profile without falling back to legacy.

The profile follows bootstrap/run paths, run/case markers, journal binding and
recovery, owned mount markers, native held bindings, fixed child argv and
explicit child HOME/USER, and report expectations. Existing strict schemas
retain their keysets. Run/case markers use one internal strict pure parser;
productive callers supply held physical identities, while Testing SPI supplies
declared scalar data and receives only a Bool. Journal binding defaults remain
legacy; productive callers explicitly bind their selected profile. Physical
ownership, modes, ACLs, no-follow descriptors, device/inode, provenance, locking,
space, one-use execution and signature checks retain their existing guards.

The parent container must already pass the existing owner-private ancestry,
mode and ACL checks. This source does not create or adopt a missing/unsafe
container. Existing `native-proof-parent.py` remains legacy-only. SSD transport,
container preparation and native execution require their separately reviewed
plan. Nested confined copies do not become visible through the existing depth-4
inventory traversal. This change makes no native acceptance, installation,
release or product-readiness claim.

PAT-2710 implementation handoff is source-only. No build, check executable,
guest, native issuer or app execution was performed by the implementer. Parent
verification and independent full-artifact correctness/security review remain
required before acceptance.
