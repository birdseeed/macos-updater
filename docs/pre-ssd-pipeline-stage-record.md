# Pre-SSD pipeline stage record

PAT-2700 preparation partition, 20 October 2026. This record concretises the
readiness and read-only control route in the trial brief.
It does not complete full PAT-2700 or execute the [17 portable runner proof
cases](validation-runner-proof-plan.md). All 17 remain unrun. No build, test,
application execution, installation or live acquisition is performed by writing
this document. Historical documents retain their original scope and observations.

## Authority and custody

Owner instruction: “Arm that pipeline preparation batch with the scopes and
budgets it needs, then run it autonomously as far as we can before the SSD arrives.”
The exact accepted batch is `run-20261020-pipeline-preparation`, parent/controller
chat `01a15a5e-e015-75d3-a2cd-d3b4b76c6de2`, sole owner of
`mac-updater-queue-controller.lock`. The parent must recheck ownership, live issue
scope, remaining budgets and explicit holds before every group. This document
neither takes that lock nor resets historical attempts.

Owner-private evidence root:
`/Users/example/Documents/Patched/evidence/run-20261020-pipeline-preparation/`.
The source scope is `PLAN.json`, read at SHA-256
`387cb1bb2d70e0c5fc957d9b5f303e6049373643067e5a92f71a76f51dbf942b`.
This identifies the read snapshot; later counter updates require a new retained
snapshot/hash, never replacement of original evidence. The parent retains raw
bytes, source/review/build manifests, group registration, output digests and
adjudications there, with no secret values or external redistribution of private
host evidence. No automatic evidence pruning is authorised in this batch.

The documentation implementer was requested as `gpt-6.1-sol`, `medium`, fresh
context (`none`); observed runtime metadata was unavailable. Parent acceptance,
independent whole-artifact correctness/security review and required source CI
remain separate delivery gates. This preparation slice grants no worker service,
scheduler, signing, catalogue publication, customer delivery or client release.

## Dated readiness observations

The raw record `PAT-2700/readiness-R1.json`, collected
`2026-10-20T17:49:09.262138+00:00`, has SHA-256
`1f840e3eb735c7a0ccb4d03ad6671083abb130d341f8d8e88816e00f099abc79`.
It retains each argv, start time, exit, stdout and stderr and declares
`changes_made: false`. These are dated observations, not reservations or
permanent availability. They do not establish an admitted clean image or a
fresh disposable guest.

| Raw record | Observation | Limit of evidence |
| --- | --- | --- |
| `host-user`, `host-os`, `host-arch` | Current user uid 501; macOS 27.0.1, build 26A434; arm64 | Current M4 user session is the approved read-only inspection target; no app execution/install. |
| `host-capacity` | Mac16,1; 25,769,803,776 bytes RAM; 10 CPUs | Inventory, not a capacity benchmark or concurrency entitlement. |
| `host-disk` | Data volume available 14,781,056 KiB at collection | Snapshot; remeasure destination capacity and batch footprint before execution. |
| `host-clt`, `host-swift` | `/Library/Developer/CommandLineTools`; Apple Swift 6.4 (`swiftlang-6.4.0.34.1 clang-2100.3.34.1`), target arm64-apple-macosx27.0.0 | Does not prove guest toolchain or stapler availability. |
| `existing-vm` | `patched-macos-01`, UUID `{039b103f-8971-45b9-beb8-2afffb33edc9}`, APPLE_VZ_VM, running; 4 CPUs, 8192 MB RAM, 100000 MB disk; GuestTools reported 27.0.3-58680 | Existing persistent VM; restore-image field empty. No clean-baseline provenance, guest OS/tool hashes or admitted installed target supplied here. |
| `existing-vm` isolation fields | Host folders/profile/clipboard/cloud sharing off; app sharing both directions off; bridged default network; SmartMount removable/CD/DVD/network shares on; host location on; cameras/gamepads automatic sharing on; encryption and EFI Secure Boot reported off | Observed configuration only, not security acceptance. Do not change it in this scope. |
| `runner` | GitHub runner id 21, name `patched-macos-01`, online and not busy; labels self-hosted/macOS/ARM64/patched-macos-01/parallels/macos-27 | A point-in-time API result, not execution or exact-checkout proof. Runner21 is CI/readiness only. |

R1 includes host executable presence, executable bits and SHA-256:

| Host path | SHA-256 |
| --- | --- |
| `/usr/bin/hdiutil` | `82b49498870a824e8dcbddee86ee8f321a0b5d3577d5e171f94c357892e555ff` |
| `/usr/bin/codesign` | `d517c9be608ffd266ec106c685e880cda71abc94001450e36d2476016406dd1e` |
| `/usr/sbin/spctl` | `3c6c3c50e9b8d462b6b9497246cdcf588570d9e5bb01a7f39ec2ccbdb87b94f3` |
| `/usr/bin/swift` | `34129c71a01a74f7f3b2443521519b2e5447553fa187f5fcafaaf8c42cc192e2` |
| `/usr/bin/xcode-select` | `49cf1e59551a8a401d86ac444aa6b2a9ab7ec6d3882c98c004dab02a0e484e53` |
| `/usr/bin/curl` | `625cd93eb0043214d5f74974d34f0b4d748977473e236a2e7f4704ecc2b95950` |

Host `xcrun`/stapler path, version and hash, Parallels executable version/hash,
guest OS/build/tool hashes, runner service account and actual CI checkout SHA
are unresolved in R1. The record's root-guest-collection warning expressly
prevents treating root inventory as runner-user execution. Any later readback
must retain its own raw evidence and identity; do not fill these gaps from
historical results or VM labels. Current schema 3 uses Security APIs and four
command observations, with no `xcrun`/stapler invocation; their absence is not a
new sample prerequisite. Missing an actually required tool holds the sample;
there is no installation prompt or provisioning authority. See the current
[pinned signature contract](pinned-signature-validation.md), which supersedes
the historical app command/ticket requirements in first-proof-target.

## Source and exact admitted inputs

The source inventory baseline is commit
`595ba81b2026c2d702646dfe66ed72fc4693403a`. At that baseline
[ArtifactInspection.swift](../Sources/ArtifactInspection/ArtifactInspection.swift)
has SHA-256 `a3cf673335254c0bc5ca1c809193086e01e0eb9c7916d49c5e5d89f52a51342c`
and [Inspector.swift](../Sources/ArtifactInspection/Inspector.swift) has SHA-256
`cd411ed5fce62e7ff98c15d9030cfef100b37e2160dc691e848381439e67a768`.
This is source inventory, not accepted PAT-2710 code or a measured executable.
Before samples, freeze the accepted PAT-2710 source SHA, whole review artifact,
build recipe and inspector binary hash in the parent packet. The baseline
inspector stages and hashes bytes but then passes pathnames to image tools;
this record does not assert the later descriptor-binding fix already exists.

The compiled `FirefoxTargets.pins` and [pin record](firefox-artifact-evidence.json)
identify exactly these universal mac/en-US inputs, bundle `org.mozilla.firefox`,
Team ID `43AQ936H96`, architectures exactly arm64 plus x86_64:

| Sample / version | Exact initial URL | Expected bytes | SHA-256 |
| --- | --- | ---: | --- |
| S1 / 157.0 | `https://archive.mozilla.org/pub/firefox/releases/157.0/mac/en-US/Firefox%20157.0.dmg` | 161304638 | `df6d8c79b6126bcf24cb70ebab9371916a662028e2d706e462d432e78fdf396c` |
| S2 / 157.0.1 | `https://archive.mozilla.org/pub/firefox/releases/157.0.1/mac/en-US/Firefox%20157.0.1.dmg` | 161550118 | `40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982` |

Total expected response bodies are 322854756 bytes. Hashes bind bytes to reviewed
pins; they are not independent publisher authentication. Current
[Download.swift](../Sources/ArtifactInspection/Download.swift) requires the exact
compiled initial URL, HTTPS on `archive.mozilla.org` with no explicit port,
credentials, query or fragment, safe path syntax, maximum three redirects,
180-second transfer and exact pinned response/final length. It permits other
syntactically safe paths on that host after the initial URL; it does not compare
redirect paths against an approved exact-URL set. Later length/hash verification
cannot undo a request already sent to an unapproved path.

This batch retains its stricter exact-hop egress boundary. Exact initial, hop
and final URL approval and enforcement must be accepted before any transfer;
that prerequisite is unresolved here. Current downloader checks alone do not
satisfy it, so `download-inspect` remains held unless a reviewed invocation and
accepted enforcement supply that boundary. Correcting this description grants
no alternate path/URL authority and does not silently widen a future inspector
policy. No alternate version, publisher, recipe or retry is allowed. The 2 GiB
absolute source ceiling in [artifact-size-policy](artifact-size-policy.md) does
not widen these pins.

## Serial limits and stop conditions

The parent registers groups prospectively and retains failure accounting. Caps
are maxima, not automatic entitlements to retry. Read live counters rather than
infer remaining allowance from this document.

| Partition | Maximum groups | Per-group wall ceiling | Conditions |
| --- | ---: | ---: | --- |
| PAT-2700 readiness/preparation | 3 | 600 seconds | Read-only existing inventory; documentation preparation. |
| PAT-2700 executable preparation correction, only if needed | 3 | 1800 seconds | Separate source/check budget; none introduced by this document. |
| PAT-2710 descriptor-bound source/check work | 5 | 1800 seconds | Separate implementation/check and independent acceptance gates. |
| PAT-2693 preparation source/check work | 5 | 1800 seconds | Existing acquisition prerequisites and evidence preparation only. |
| PAT-2693 S1 then S2 live inspection | 2 total | 1200 seconds | At most one actual transfer per pin; no rerun, automatic retry or reset. |

All native/check/acquisition groups are serial, Swift jobs at most 2, free disk
floor 5 GiB (5368709120 bytes), maximum incremental retained/build footprint
4 GiB (4294967296 bytes) for the batch. Before each sample separately confirm
both the batch floor and the opened staging volume's exact pin length plus
64 MiB reserve using the existing descriptor capacity check. That snapshot is
not a reservation or mounted-payload capacity proof. Preserve failure evidence
within the footprint; stop if it cannot fit. No resource increase or purchase.
The existing £500 known-spend-plus-commitments cap remains; unavailable provider
actual cost is unknown, never zero.

Use only existing approved host/VM capacity and owned bounded process groups.
Existing inspector command limits are 30 seconds and 1 MiB combined output per
command, with descendant termination on timeout/output excess. The parent must
bind the overall sample watchdog and actual argv/process identity before start;
this document adds no executable watchdog. No application binary, installer,
helper or UI is launched. No tool install, VM creation/rebinding/reset/destroy,
host/security/network/configuration change, credentials or persistent activation.

Stop the affected sample for lost controller, identity/source/binary/tool drift,
unknown exact egress or target, exhausted limits, disk floor/footprint breach,
byte/publisher/trust conflict, missing raw evidence or unsafe cleanup. Preserve
its original failure and do not use S2 as a retry of S1. Independent preparation
may continue within its own caps. No installation follows a container failure.

## Stage handoff and evidence mapping

S1 and S2 are **prepared, not executed by this record**. They are held until
PAT-2700 readiness is accepted and PAT-2710 descriptor-bound source passes local
checks, independent review, exact-head/main CI and source readback. Then perform
fresh sample preflight on the current user Mac. Runner21 remains CI/readiness
only unless a later exact sample record independently admits it.

The initially scoped method is `artifact-inspector download-inspect <version>`;
its unresolved exact-hop enforcement prerequisite above holds that method.
A prepared alternative is exact-URL acquisition with the existing
`/usr/bin/curl`, with redirect following disabled (`-L` absent and
`--max-redirs 0`), followed by the accepted
`artifact-inspector inspect-local <version> <absolute-owned-input-path>`.
The acquisition must require HTTP status 200 and exact pinned body length and
SHA-256 before inspection; a redirect response is a refusal, with no follow-up
request. Curl exit zero alone is insufficient. Retain its raw headers, status,
effective URL, byte count, exit and output plus independent input length/hash.
`inspect-local` does not make the acquisition fresh transport evidence: its
`transportObservedThisRun=false` and local source path must remain distinct from
the separate curl acquisition record.

Both variants require an exact independently reviewed invocation policy,
accepted source/build recipe and frozen measured binary/tool identities as
preflight. The curl alternative is prepared only, not an approved live argv
policy. Its exact argv/environment/configuration, HTTPS443/180-second transfer
and byte bounds, owned destination, watchdog and cleanup must be frozen and
accepted before use. It introduces no downloader engine or AutoPkg selection.
Neither variant has run under this record. Selecting a variant does not add
samples: the same two-sample cap, one per pin, serial and without retry, applies.
This is a handoff specification, not a new shell script or candidate-supplied
policy. The parent owns the invocation, evidence paths, watchdog and final
disposition. Use only the accepted measured inspector and explicit S1/S2 version.
For each stage retain group/sample ID, UTC start/finish, expected/actual result,
source/binary/tool identities, input pin, raw output bytes and SHA-256/length,
argv/exit/timeout/output-limit flags, resource observations, refusal and cap use.
Store sample records under `PAT-2693/S1/` and `PAT-2693/S2/` in the private root;
never overwrite a failed record.

| Stage | Required raw mapping and independent readback | Prepared result / acceptance boundary |
| --- | --- | --- |
| P0 readiness and scope | R1 plus later scoped inventory; controller, source/build/review manifests; group registry; target/tool/egress/disk preflight | R1 observed above; missing identities stay unresolved. No clean-VM or security proof. |
| P1 acquisition | Selected method and separate acquisition record; inspector `sourceURL`, `redirectChain`, `transportObservedThisRun`; curl raw headers/status/effective URL/exit if selected; transfer refusal, bytes/time and exact hop evidence | Pending S1/S2. A successful transfer is acquisition only. Missing transfer details are unavailable, not fabricated. |
| P2 digest/staging | Selected `pin`, exact length/hash, `byteIntegrityVerified`, descriptor-bound accepted source and input custody | Pending. Refuse mismatch before image tools; same-UID in-place mutation is not solved merely by chmod or a read-only descriptor. |
| P3 native image/payload | `commands`, `evidence.infoPlist`, OS/build/time, architecture observation, structured Security API statuses/requirement/identity and Gatekeeper output; raw refusals if partial | Pending. Image verification and app identity/native trust have distinct outcomes. Security-framework signature observation is not replaced by a fixture flag. |
| P4 container | Separate current container codesign and Gatekeeper open outputs/exits; assessment container fields if supplied | Pending fresh observations. Schema 3 runs no ticket tool and keeps `containerTicketPassed=false` as unassessed. Historical unsigned-container and stapler failures remain failed, without a new stapler run. No blanket pass or install eligibility. |
| P5 owned mount/workspace cleanup | Raw attach/detach argv/exits and exclusively owned mount identity, `cleanupVerified`, `workspacePreserved`, mount readback and parent adjudication | Pending. Detach only owned mount; remove only known staged file and empty owned directories. Preserve uncertain/mounted workspaces, no recursive cleanup or guest destruction. |
| P6 installed/launch/recovery/teardown | No installed or guest lifecycle action in this batch | Held, SSD-dependent and separately scoped. `installationAuthorized` stays false. |

Do not collapse acquisition, byte integrity, native payload, container, cleanup
and installed-pending outcomes into one green result. `InspectionReport`
[fields](../Sources/ArtifactInspection/Inspector.swift) retain refusal, partial
commands, assessment and cleanup separately; an exception before a complete
report also needs captured stderr/exit and an incomplete-stage record. An absent
assessment or command is unavailable, not success. Current report/replay shapes
must be preserved by PAT-2710; replay cannot create fresh OS evidence.

The [7 October historical record](firefox-artifact-evidence.json) says both
payloads passed their then-current app checks, while both unsigned DMGs returned
container codesign 1, Gatekeeper open 3 and stapler 65. Its original overall
`inspection_pass: false` remains false. Neither those observations nor a future
read-only sample prove installed old-to-new update, launch, recovery or release.

## Existing CI and full-ticket remainder

verify.yml gates ordinary source checks on
`PATCHED_MACOS_ACTIONS_ENABLED`, same-repository PRs, runner labels, non-root
identity and exact `GITHUB_SHA`, with a 15-minute job ceiling. It uses pinned
checkout/setup-node actions then `scripts/verify.sh`. The
manual smoke workflow is a separate
five-minute toolchain/Foundation/AppKit control. Its old paused-workflow comment
is historical; this document changes no workflow or variable. Historical and
disposable diagnostics retain their separate disabled holds. Source CI must
retain actual SHA, runner, step outputs and terminal result; online labels or
root guest collection cannot substitute for them. `verify-artifacts.sh` builds,
runs synthetic checks and verifies the pin record; it does not run live samples.

The trial brief and
[runner architecture](validation-runner-architecture.md) still require an admitted
clean image, reviewed worker/authenticated claims/uploads, durable jobs/outbox/
leases, fencing/restart reconciliation, fault/recovery/teardown authority and
reproducible independent readback for full portable execution. The fixed native
harness's compiled guest binding cannot be reinterpreted as a portable guest.
No Tart/AVF selection, clean-VM lifecycle or permanent runner readiness is implied.

The acquisition benchmark and
contract review still require accepted common
contracts, exact tools/recipe/parent/processor/dependency provenance, vendor terms,
comparable variants and raw measurements. AutoPkg remains unselected. No new
recipe, downloader engine, production schema, HTTP-versus-AutoPkg winner,
maintenance/cost saving, throughput or hosting/purchase recommendation follows
from these two inspection controls. Chrome/VLC/ZIP/PKG and large-artifact/low-space
SSD proof remain parked. Full PAT-2693 and PAT-2710 remainders are separate.

PAT-2700 bounded preparation can be accepted after the parent verifies the dated
raw inventory and this exact stage record and completes its delivery gates.
That completes preparation source only. Full PAT-2700 stays incomplete: all
17 prospective E2E/reliability/failure/security/reproducibility/exception/measurement
cases remain unrun, with installed testing and capacity/security acceptance held.
