# Artifact size and staging capacity

ArtifactSizePolicy defines one absolute ceiling of 2,147,483,648 bytes (2 GiB).
Every artifact still needs an exact positive authenticated byte-length pin and
SHA-256 digest. The signed schema-v1 catalogue preserves its existing fields
and exact byte count; larger valid lengths do not grant download or installation
authority. Ordinary network inspection remains restricted to the compiled
Firefox targets and reviewed HTTPS redirect policy.

Catalogue decoding, ordinary download limits and descriptor-based streaming
hash/copy use that same ceiling. The downloader requires the response length
to equal the pin before accepting its body, checks each chunk against the pin
before writing, and requires exact final length and hash. Hash/copy reads stay
bounded to 65,536 bytes; integer overflow, truncated bodies and excess bytes
refuse. A configurable lower download limit remains stricter than the ceiling.

Before creating artifact.dmg or starting a download, staging checks capacity on
the opened private destination directory using fstatfs. It uses space available
to the current user, checked block-to-byte multiplication and the validated
artifact length plus a 67,108,864-byte (64 MiB) reserve. Unknown, invalid,
overflowing or insufficient capacity refuses. Local staging copies apply the
same preflight. This is a snapshot, not a disk reservation: subsequent write or
sync failure still refuses. The reserve covers neither mounted/extracted payload
size nor installation/replacement requirements.

The Testing SPI drives the ordinary receiver header/chunk/finalisation methods,
real descriptor hashing and the ordinary local staging path with tiny synthetic
bytes and injected destination capacity. It constructs no network session,
OS assessment or installation authority. Production capacity is always read
from its destination descriptor; ordinary calls accept no injected capacity.

Source/synthetic acceptance does not prove a real large artifact or low-space
installed operation. Later SSD-backed acceptance needs separately confirmed
target and test authority: authorised artifacts above 170 MB and near the
ceiling, bounded resident memory, exact digest/length, destination-volume
capacity plus reserve, low-space refusal before transfer/copy and safe refusal
if space is exhausted after preflight. No multi-GB fixture allocation or real
mount, app/helper launch or installation is part of the source gate.

## Dated large synthetic size and staging evidence (PAT-2709, 24 October 2026)

Two bounded, local, data-only controls exercised the real streaming generation, hashing and staging path with synthetic bytes. The first fixture was 180,355,072 bytes (172 MiB), SHA-256 `159493a9844cb58858adf1d91d63065c268138177d2beaf6a6d252584db2145e`. The second control extended that same fixture, retaining filesystem device and inode `16777230:109870`, to 2,147,483,648 bytes (2 GiB). It wrote 1,967,128,576 additional bytes and produced SHA-256 `382045c648d7c2a42a01bb3132186a0397d40e2e4e85a99377dbc79c20e6671e`.

Both controls reported successful exact-size and digest checks, use of the ordinary destination-capacity check, and successful staging through a read-only descriptor whose file was already unlinked while the closure used it and whose descriptor was closed afterward. The source fixture remained unchanged during each control. Maximum process RSS was 7,225,344 bytes for the 172 MiB run and 7,192,576 bytes for the 2 GiB run. These observations demonstrate bounded memory for these two executions; they do not guarantee a continuous or universal peak-memory bound.

The destination had ample available capacity in both runs. Capacity observation is a point-in-time check, not a reservation, and these runs did not exhaust a disk or test refusal on a nearly full physical volume. The separate 18 injected local refusal cases remain distinct evidence. This result therefore adds actual-size synthetic staging evidence to the source and fixture checks; it does not establish low-space SSD behaviour.

The first data control used native slot 1 of 2 and the extension used slot 2 of 2. All three admitted offline groups were used. The original five failed source repair rounds and the one-round fixture amendment remain sealed. After the controls, exact-PID guest readbacks established `ESRCH` for PID 962 and PID 1298 under the admitted root pair and UID. The first transport attempt had exited 255 and left quiescence unknown; that original failure remains recorded. A reviewed read-only recovery obtained the first actual exit readback. The transport marker remained `UNKNOWN` and was not treated as proof of guest quiescence. No data-control retry or fixture cleanup was performed while quiescence was unknown.

Resource monitoring recorded 205 samples from 11:53:22 to 12:22:59 UTC, with a maximum sample gap of 9.085 seconds. The largest sampled aggregate was 11,993,706,496 bytes, below the 14,463,129,088-byte engineering guard and 15,000,000,000-byte hard limit; minimum sampled workspace free space was 16,169,234,432 bytes and minimum sampled external SSD free space was 411,505,369,088 bytes. All samples were recorded safe. Monitoring stopped intentionally after both data controls and actual process-exit readbacks completed, with CI online and idle. These discrete samples do not establish a continuous peak guarantee.

The 2 GiB fixture was retained on the stopped TEST guest without manual cleanup. The recorded role return was TEST stopped, CI running, runner 21 online and idle, and both MASTER and AutoPkg untouched. This is the observed state at the end of this bounded experiment, not a general runner-readiness claim.

Historical failures remain part of the evidence: the earlier V2 `SIGXFSZ`, the first quiescence transport exit 255, and the initial overstrict cross-boot `st_dev` assertion. They were not reset or replaced by the later successful observations.

This was synthetic local data only. It involved no vendor transfer or vendor trust, no real disk exhaustion, native inspection, mount, app/helper installation, or client release. It does not establish production download behaviour, installed-app behaviour, or low-space refusal on a physical SSD. The evidence supports the bounded size/capacity partition; vendor-transfer and physical low-space behaviour remain separate unmeasured cases.

Supporting evidence is retained outside the source repository at `/Users/example/Documents/Patched/evidence/run-20261021-owner-run-73f48805/`. The parent acceptance record is `PAT2709-real-size-native-partition-parent-acceptance-v1.json`. The captured controls are `PAT2709-native-capture-prerequisite-recovery-v3/first-complete.log` and `extend-complete.log`, with functional records in `PAT2709-native-V3-controls-admission-v1/first-functional-parent-acceptance.json` and `extend-functional-parent-acceptance.json`. Actual process-exit records are `PAT2709-native-V3-controls-admission-v1/first-quiescence-recovery-parent-acceptance.json` and `extend-quiescence-parent-acceptance.json`. The admission records, original failure records, resource samples and review records remain alongside them.
