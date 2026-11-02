# PAT-2584 bounded disposable guest harness

This is the separate source implementation for the owner-approved 10 October
2026 proof. Local checks exercise synthetic mechanics only. Parent acceptance,
independent canonical review, publication and fresh guest execution remain
separate gates.

Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required. No result here claims a shipped updater or installed Firefox
proof on the host.

## Fixed authority and bootstrap

The only selector is parallels-0A0A0A0A-0000-4000-8000-000000000001. Every runtime
entry observes real/effective uid 501, account and console owner andy,
HOME/account home /Users/andy, mac-staging.local, arm64, hypervisor 1,
macOS 27.0.1 build 26A434, and the compiled hash of the uppercase platform UUID.
The raw platform UUID is read in-process through IOKit and never enters reports.
A caller cannot supply guest observations, time, installed version or OS trust.

**PAT-2636 replacement binding, 10 October 2026.** Andy accepted the exact
Parallels staging target, existing-key SSH route and isolated PAT-2584 scope.
The retired UTM selector utm-9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246 and its
macOS 26.6.2/build 25G83 binding are historical and no longer accepted.
The replacement platform UUID digest is
d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959;
the VM selector and guest platform identity are distinct. Native observation,
real/effective uid and console checks, storage guards and artifact pins are
unchanged. Parent verification, independent review, exact PR/main CI and
source/binary-bound guest preparation remain required.

The accepted transfer/execution route is existing-key SSH as andy, uid 501,
to 10.211.55.3 using `ssh -F <private-parent-config> mac-staging-parallels`.
The task-specific private config pins strict host-key verification to the
replacement key independently observed through Parallels guest execution;
the global SSH config is not the accepted route. The parent verified Remote
Login and console uid 501. No root proof execution or
passwordless sudo is part of this route. The fresh guest lacks Command Line
Tools/stapler; this native validation prerequisite remains pending. No software
installation or successful native proof is established by this binding change.

Focused binding checks run with `swift run patched-disposable-proof-checks`.
The separate `verify-disposable-boundaries.sh` checks native boundaries and
does not run these selector/parser checks. Full `./scripts/verify.sh` remains
the acceptance gate. **CHECK-MODIFIED, PAT-2636:** The parent accepted the old
exact-selector assertion becoming the exact Parallels expectation. A second
explicit exception changes only CatalogueFixtures' test-only minimumOS and
maximumOS from 26.0/26.9 to exact 27.0.1/27.0.1. The old signed fixtures
declared the replacement OS incompatible, causing six unchanged catalogue
checkpoint/refusal checks to fail with notAuthorized after rebinding. Their
failure log is retained. Test signing seeds, signature construction, lifetime,
other payload fields, Core verification and native guards are unchanged; all
unrelated original checks and the new literal binding checks are retained.

The parent transfers only reviewed, measured tools to an exclusively created
mode-0700 /Users/andy/PatchedProof/.bootstrap-<run-id>. The bootstrap toolset
may contain the measured native proof binary, packaged wrapper, independently
measured read-only artifact inspector and builder-receipt.json. It is retained.
The proof binary must be named patched-disposable-proof and run from that exact
bootstrap directory. The wrapper takes no defaults and never invokes Swift.

builder-receipt.json is bounded JSON containing binarySHA256 and sourceRevision
(the clean, merged source commit's 40 lowercase hexadecimal characters).
The parent measures the built binary independently and verifies that exact
clean merged revision. The runtime compares the receipt's binary hash with its
own kernel-selected executable, records the exact receipt bytes and their hash,
and reports sourceRevisionObservedByHarness=false. This is parent provenance,
not source attestation and never authority. Additional receipt fields are data.

The native init-run action exclusively creates the actual <run-id> root and its
Incoming, Evidence and Cases children. It never adopts a parent-created run or
case. Run and case markers bind guest hash, uid, run/case, device/inode and binary
hash. The actual run/case names cannot name .bootstrap-* or arbitrary paths.
Every private directory is owned mode 0700 without ACL entries; ancestry grants
are conservatively refused. Nothing changes existing home or parent ACLs.

## Inputs and commands

Use the packaged native binary or its adjacent prove-disposable.sh wrapper with
--target-id, --run-id, --case-root, --case and --explicit-trigger.
init-run omits --case-root. prepare-root exclusively creates one allowlisted case.
Other actions reopen authenticated state in that case. There are thirteen roots,
as listed in the installed-proof runbook; linked recovery pairs reuse only their
own root. Missing markers, stale bindings and malformed state refuse.

For example, from the verified bootstrap directory, substitute the accepted safe
run ID for RUN. These commands are the parent-owned guest route after review:

```sh
./patched-disposable-proof --target-id parallels-0A0A0A0A-0000-4000-8000-000000000001 --run-id RUN --case init-run --explicit-trigger
./patched-disposable-proof --target-id parallels-0A0A0A0A-0000-4000-8000-000000000001 --run-id RUN --case-root update --case prepare-root --explicit-trigger
./patched-disposable-proof --target-id parallels-0A0A0A0A-0000-4000-8000-000000000001 --run-id RUN --case-root update --case update --explicit-trigger
```

Each row below uses the same explicit target/run/trigger flags. First run
prepare-root for each unique case root after transferring the exact old image.
The action names are literal --case values; no automatic case loop is built in.

| Case root | Action | Additional required argument/condition |
| --- | --- | --- |
| tampered-artifact | tampered-artifact | Actual tampered fixed image |
| truncated-artifact | truncated-artifact | Actual truncated fixed image |
| recorded-evidence | recorded-evidence | --recorded-evidence /Users/andy/PatchedProof/RUN/Incoming/inspection-157.0.1.json |
| wrong-signer-target | wrong-signer-target | Parent's authorised target mutation |
| wrong-signer-staged | wrong-signer-staged | --pause before-swap; parent mutates exact stage |
| invalid-signature | invalid-catalogue | Fixed invalid-signature envelope |
| untrusted-key | invalid-catalogue | Fixed untrusted-key envelope |
| replayed-sequence | replayed-catalogue | Fixed replay envelope plus valid checkpoint seed |
| expired-catalogue | replayed-catalogue | Fixed expired envelope |
| open-app | open-app | Person-launched exact case bundle; isolation gate |
| staging | staging-failure, then recover-after-staging | --pause stage-copy on first action; actual process death |
| update | update, then restore-old | Actual committed update before restoration |
| swap | interrupted-swap, then recover-after-swap | --pause before-commit on first action; actual process death |

report reopens one authenticated case and records its current physical state.

Parent-transferred inputs are fixed files in the run's Incoming directory:

- Firefox 157.0.dmg and Firefox 157.0.1.dmg, the exact compiled pins.
- tampered.dmg and truncated.dmg for their separate refusal roots.
- catalogue-valid.json, catalogue-invalid-signature.json,
  catalogue-untrusted-key.json, catalogue-replayed-sequence.json and
  catalogue-expired-catalogue.json.
- inspection-157.0.1.json, the separate recorded read-only inspection report.

The check executable's explicit --emit-current-catalogue-fixtures mode prints a
JSON map of base64 envelopes. The parent generates fresh envelopes after the reviewed build, image inspection
and all thirteen prepare-root operations, immediately before the actual case
sequence. This avoids spending the one-hour envelope lifetime on baseline copies.
Each decoded envelope is written exclusively to its fixed Incoming filename.
Signing seeds exist only in the check target. Runtime holds only a fixed TEST
public key and calls the unchanged Core verifier with freshly observed time,
OS and target Info.plist version. A fixed-pin refusal precedes replay checkpoint
acceptance. Refusal cases retain the checkpoint's exact bytes.

recorded-evidence requires --recorded-evidence naming exactly the fixed
Incoming/inspection-157.0.1.json. It holds and reads that actual bounded regular
file, records its path/hash/length as offered recorded input, and refuses it.
For successful reports the same fixed report may be hashed as a comparison;
it never becomes fresh evidence or installation authority.

## Physical storage and proof order

All run children, case roots and their Applications/Transaction/Baseline/Work
directories must share the captured run device before use; fresh read-only
artifact mounts are the separate permitted volume boundary.

All critical file I/O, journals and exchanges use retained nofollow descriptors.
Every external command has fixed absolute executable/argv, bounded output/time,
and anchor checks before and after. The same-user race limitations below still
apply to external commands that require paths.

Owned image staging copies bytes into a new exclusive file and seals that
file to mode 0400 on its existing descriptor before the final flush, closure
and lasting HeldFile capture. Ordinary bundle copying and source image modes
are unchanged. Native image verification and read-only attachment remain
enabled; strict identity, mode, mtime and ctime checks remain unchanged.
A controlled host comparison found that hdiutil verify added its checksum
cache attribute and changed ctime on a 0600 copy, while a 0400 copy retained
its ctime and gained no cache attribute. This explains a possible refusal
mechanism; the original guest failure's exact phase remains unobserved.
Synthetic checks exercise shared staging and actual metadata/replacement
refusals. They do not establish successful guest preparation or installed proof.

prepare-root copies the genuine old payload directly from its own freshly
verified read-only mount into Applications/Firefox.app and separately into
Baseline/Firefox-157.0.app. There is no retained SourceOLD. Each copy must match
the full content manifest and pass fresh codesign deep strict, exact signer/
identifier, Gatekeeper Notarized Developer ID, stapler and universal lipo checks.

Before trusting mtree, each case creates an owned throwaway probe, captures and
successfully verifies its manifest, deliberately changes its bytes, and requires
mtree exit 2 with mismatch output. The target's independent manifest is
Baseline/target-157.0.mtree. Both target and held baseline must verify against it.
Baseline/baseline.json binds the manifest hashes and physical identities.
Recovery verifies both the retained baseline and the restored old target.

The new payload is copied once into Work/Source.app only in stage cases
wrong-signer-staged, staging, update and swap. It is independently checked, and
the image is detached with actual mounted-path readback before interruptible
stage copying begins. Source and every other artifact remain as evidence.

The stage copy runs in-process with descriptor streaming and native metadata
copy, never an orphanable external copier. It hashes and rechecks every file.
Real bundle bounds are separate from the historical fixture limits: 20,000
entries, depth 40, 2 GiB total. Executable modes and safe internal relative links
are supported; unsafe modes, hardlinks, special nodes, escaping/cyclic/dangling
links, cross-volume entries, races and truncated walks refuse.

At each copy the runtime records available bytes and a conservative reservation:
max(next copy size, 22,000,000,000 minus retained logical run bytes) plus 2 GiB
headroom. Parent host measurements found 163 entries/depth 8 and roughly 535 MB
for each pinned bundle; these are planning measurements, not guest proof.
Insufficient space refuses without deletion or resource provisioning.

## Pauses and actual interruption

The journal progresses prepared, staging, staged, swapIntended, swapped,
committed or rolledBack. Every journal write is strict, bound, flock-serialised,
atomically replaced and fully flushed with fsync/F_FULLFSYNC without fallback.
The only bundle replacement primitive is descriptor-relative RENAME_SWAP.

staging-failure pauses during a real regular-file stream after nonzero bytes
have been written and flushed, while the file is incomplete. Its durable
Transaction/pause-stage-copy-<transaction-id>.json includes file identity,
relative path, copied and expected bytes, PID, run/case and journal state.
The parent kills that actual harness process. No copying child remains.

wrong-signer-staged pauses after staged validation and before exchange at
Transaction/pause-before-swap-<transaction-id>.json. The parent applies the
authorised ad hoc mutation only to that stage, then creates the corresponding
resume-before-swap-<transaction-id>.txt containing exactly "resume" and LF.
Continuing grants no acceptance: native checks and manifests run again.
An unaltered negative-case input returns caseConditionMissing.

interrupted-swap pauses after the actual exchange and durable swapped journal,
before commit, at pause-before-commit-<transaction-id>.json. The parent kills
the actual process. A killed process writes no completed report. Pauses wait at
most 900 seconds and can only continue to ordinary validation or refuse.

recover-after-staging and recover-after-swap authenticate the existing journal
and physically compare full trees and identities. They either retain the whole
old target or atomically restore the retained whole old bundle, checking it
freshly with macOS and mtree. Interrupted recovery is resumable; ambiguous or
changed evidence refuses and remains in place. restore-old first records
swapIntended for a valid committed pair, then uses the same recovery mechanics.
No baseline copy is used for restoration, and nothing is deleted.

A durable owned mount marker precedes attachment. On reopening a case, only the
exact marked mount whose hdiutil image/path mapping and read-only state match
may be detached. Detach failure preserves all evidence and stops. No foreign
mount is detached.

## Evidence and limits

Reports are written exclusively under Evidence only on completed operations.
Command observations and refusals are separate durable files, so incomplete
runs retain evidence without a completed report. Reports include physical guest
facts, actual binary hash, parent provenance receipt, exact image pins/held
paths, catalogue identity/sequence/hash, native app observations, manifests,
mtree file hashes, transaction states, exchange path, space observations,
harness signing observation and actual mount absence.

Container signature/open-assessment/stapler results remain separately named raw
observations. Their failures never become a blanket pass because app checks
passed. Only an actual committed update with freshly accepted physical installed
target can set installedFirefoxProof=true, scoped to its case; productionTrust
and globalProductReadiness remain false.

The harness neither starts nor quits Firefox. open-app must observe an actual
process belonging to the exact physical case bundle. Unverifiable live
same-user process observations refuse. Case 8's person-controlled launch and
profile-isolation prerequisites remain with the parent under the runbook.

PAT-2638 adds observation only for unresolved native process failures. A
`process-observation-<case>-<action>-<uuid>.json` file is attempted in the
authenticated run's Evidence directory immediately before the existing
`commandFailed` refusal. Its closed stage identifies `proc_listallpids.size`,
`proc_listallpids.read`, `proc_pidinfo`, `proc_pidpath` or `fstatat.ancestor`;
the remaining fields are the original numeric errno and return size/result,
plus PID and observed UID when available. No unrelated executable or ancestor
paths or contents are recorded. Errno is captured before liveness probes can
overwrite it. An evidence-write failure still yields `commandFailed`.
Existing disappeared-process handling, enumeration, AppKit fallback, app-running
refusals and fail-closed guards remain unchanged; these diagnostics confer no
process, trust or installation authority. Pure post-change regression checks
cover encoding and refusal behaviour without scanning host processes. The
observation-only checkpoint did not establish the failing API or resolve the
earlier guest refusal; the subsequent bounded diagnosis is recorded below.

PAT-2638's subsequent ownership-query correction retains all-PID enumeration
and uses `PROC_PIDT_SHORTBSDINFO` with an exact `proc_bsdshortinfo` size before
checking either effective or real UID. Apple XNU explicitly exempts this
minimal ownership query from the full BSDINFO same-user privilege check while
retaining MAC policy checks:
[proc_info.c ownership-query policy](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c#L2074-L2089).
Unknown ownership, permission refusals and incomplete reads still fail closed;
only the existing vanished-process rules skip a failed query. Effective-root
processes with the current real UID remain in scope. No root privilege, ignored
EPERM, process-name inference or filtered-list omission is introduced.

The separate read-only UID-501 guest collector observed 585 unique PIDs:
329 complete full BSDINFO reads and 256 failures. All successfully decoded
short records among those failures had foreign effective and real UIDs;
one process disappeared. Effective/real filtered unions contained 329 PIDs
before and after the scan. This supports the narrower query but does not
establish the ownership of the earlier vanished PID 3206 or guarantee atomic
process absence. Local numeric synthetic checks grant no native acceptance;
the fresh binary-bound guest refusal case and unchanged-target verification
remain separate acceptance requirements.

A same-user process that rewrites all state and bundles consistently before
capture is outside this proof. Path-based native tools retain a same-user race
window despite pre/post identity checks. Flush success is not hardware or power
loss proof. Manifests cover type/mode/size/link/content, not byte equality of ACLs,
xattrs, resource forks or quarantine; fresh native checks assess copied payload
trust. Existing profiles and unrelated app contents are never inspected.

**CHECK-MODIFIED, 10 October 2026:** The parent recorded and accepted one explicit
freeze-baseline exception for the eleven additive Package.swift registration
lines. Only its digest in services/catalogue/protocol/fixtures/catalogue-v2/frozen-v1-sha256.json
changes from df81875acc408e535797fb72b5610cb453463d4ca16ce2d66ff4b493a34dde2b
to dd790f3f10b95a2405ece319c18eb830905808a2dcc84c003fd7d0d728442c48.
The test code and every other manifest entry remain byte-identical. The original
failed full-gate receipt is retained; this is an approved build-registration
baseline correction, not a behavioural test relaxation.
