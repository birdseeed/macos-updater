# Architecture inspection source slice (PAT-2706)

Productive architecture inspection reads an already held regular-file descriptor.
It never invokes lipo. Its parser accepts 64-bit MH_EXECUTE arm64/x86_64 thin
headers and 32/64-bit universal tables in either byte order. Only generic
ARM64_ALL and X86_64_ALL base subtypes satisfy the current pins. High eight
capability bits are masked for architecture naming. Specialised and unknown
base subtypes refuse; universal table and slice raw subtype words must still
agree exactly.

The reader uses pread, retains caller ownership and offset, compares pre/post
file identity, size, mode and modification/change timestamps, and reads only
bounded headers. Universal tables allow at most 64 entries, reject overflow,
invalid alignment, table/slice overlap, overlapping slices, truncated headers,
unsupported CPUs and mismatched inner headers. At most 8 + 64*32 + 64*32 bytes
are requested in universal inspection, plus the initial four-byte magic read.
Load commands and signatures are outside this architecture parser. Existing
strict codesign and affirmative Gatekeeper checks remain mandatory.

Live AppEvidence now uses schemaVersion 2 and an architectureObservation with
exact executablePath and canonical architectures. Its strict replay schema
rejects mixed, unknown and duplicate fields. An old seven-key record retains
its historical command snapshot semantics for fixture/replayed evaluation only.
The internal live evaluator refuses that legacy schema. Imported v2 observations
also remain fixture/replayed; their fields cannot request a live origin or
installation authority.

The dormant disposable flow reads the HeldFile descriptor between its existing
identity checks and manifest snapshots. Child report observations require exact
executable path and pinned names. Final native acceptance independently reads
current and retained-old held trees; historical staged or unmounted paths are
not reopened. Existing journal and manifest/source mappings remain required.
This is source implementation, not proof of any installed flow.

The focused gate is `./scripts/verify-mach-o-architectures.sh`, registered in the
full `./scripts/verify.sh`. Synthetic headers never run as executables. The
source guard additionally scans every Swift source for productive lipo references;
its single explicit legacy-snapshot carve-out is not a live invocation allowance.
Two early specialised-subtype expectations were corrected from acceptance to
refusal after comparison with Apple architecture naming. All other original
assertions remain unchanged; additional subtype and capability-bit cases cover
the correction.

This atomic slice preserves xcrun/stapler and its existing policy. PAT-2707
separately removes the stapling requirement and remaining CLT dependency; the
final command audit follows that source change. Clean-Mac/no-CLT, genuine
notarised-but-unstapled and native installed acceptance remain deferred until
the SSD and exact disposable target authority are available. Fixture/source
checks do not satisfy those acceptance items or authorise a client release.

The preceding stapling statement describes the historical PAT-2706 partition.
The separate [PAT-2707 current policy](unstapled-notarisation-policy.md) removes
current ticket collection while preserving signature and notarisation checks.
Its source change does not supply the held native or installed acceptance proof.
