# Portable macOS validation runner proposal

Policy scope, 27 October 2026: this portable runner is a proposed tool for targeted mechanism proof, not a prerequisite to centrally download and VM-test every published release. PAT-2724 permits source-verified metadata and approved vendor-native routes; their authenticated productive mapping still requires PAT-2693 acceptance. Select tests for new/materially changed routes, credible failures/risk and representative success, refusal and recovery. Clients still verify actual downloaded trust and installed results. Vendors own app functionality/data migration; restoring a bundle does not reverse migrated data. The proposed runner’s own isolation, target, budget and evidence prerequisites below remain intact; no execution or provisioning follows.

PAT-2700, 18 October 2026. Documentation-only preparation under the approved
18 October queue plan. The full issue remains incomplete. This proposal adds
no worker, protocol, VM, installation, benchmark or production commitment.

Andy decided on 16 October to use the existing M4 Mac with 24GB RAM during
development and beta, deferring dedicated hardware until measured demand and
production readiness. Recommend one VM at a time initially. Neither VM
feasibility nor available capacity on that host has been demonstrated here.
The exact VM tool, guest/image, install list, destinations, budget and execution
scope remain unresolved; none blocks acceptance of this documentation slice.

## Baseline and contract boundaries

The [catalogue architecture](catalogue-service-architecture.md) and accepted
acquisition design govern this proposal.
AutoPkg selection remains deferred to the unexecuted
acquisition comparison. Tart and Apple
Virtualization Framework are evaluation candidates named by the issue, without
any support, licensing, automation or nested-virtualisation feasibility claim.

Existing catalogue/job/evidence-v2 codecs are offline fixture formats, with no
authenticated worker or installed authority. Native catalogue verification is
still the separate v1 consumer. A native catalogue-v2 consumer and its explicit
app-trust/checkpoint migration require their own scope and proof. The proposed
release-admission-v1, acquisition-receipt-v1, job-v3 and evidence-v3 in the
amendment draft and
vector plan are unaccepted concrete
contracts. This runner proposal adopts none of them and invents no wire schema.

The [disposable native contract](client-installed-flow.md) and
[existing harness](disposable-proof-runtime.md) bind a particular guest, binary,
artifact pair and roots. They are constraints and prior proof machinery, not a
portable runner interface or permission to select another target. Existing
personal-host exclusions, refusing defaults and fixture labels remain intact.

## Portable responsibilities and trust

| Component | Proposed responsibility and boundary |
| --- | --- |
| Durable service | Own approved job identity, immutable descriptors, attempts, lease epochs, outbox, evidence acceptance and audit. Queue messages notify; they are not durable job truth. |
| Host worker | Initiate authenticated outbound claims/uploads/status requests; schedule one guest; retain restart journal and reconcile ambiguous outcomes. No inbound home endpoint is required. |
| Acquisition adapter | Discover and retrieve only under independently approved source policy. AutoPkg/Installomator inputs remain untrusted; executable processors need separate admission. |
| Disposable guest | Run the exact approved native verification/install/recovery sequence against a clean baseline and scoped destination; emit raw observations. |
| Independent evaluator | Recompute retained-byte bindings, authenticate worker/attempt context, assess freshness and native policy, then record accepted or held outcomes. Worker success is not policy acceptance. |
| Signer/publisher | Remain separately controlled under C4/C5. Runner and guest possess no catalogue signing, publication, app-release or licensing authority. |

Treat the persistent host as a separate trust boundary even when installers run
in guests. A guest snapshot or destruction does not remove host downloads,
mounts, processes, credentials or contamination. Prefer retrieval into bounded
inert storage and native execution in the guest; any host-side parser, recipe,
mount or verifier needs an explicit reviewed execution boundary. No upstream
recipe may silently become a host shell command.

Before activation, specify dedicated worker account/access, host patching and
physical access, encrypted storage, network egress and household isolation,
sleep/power behaviour, audit visibility and incident ownership. Personal data,
shared folders, host sockets, clipboard and credentials must not be implicitly
exposed to guests. Chosen tooling must demonstrate the intended isolation.
Host trust failure stops new jobs and needs separate host remediation authority;
destroying a guest supplies no host-removal permission or host-clean proof.

## Durable jobs, retries and lost acknowledgements

The following are semantic requirements for later contract acceptance, not API
names or implemented transitions. Commit job creation and dispatch intent
durably together. Reconcile the outbox against authoritative job state after
queue duplication, expiry, outage or worker downtime. Offline idle workers do
not consume execution attempts. Report backlog age and degraded state visibly.

Claim atomically with worker identity, attempt identity and increasing lease
epoch. Renew only while the authorised attempt remains live; the service owns
expiry decisions. A stale worker cannot renew, accept or overwrite a newer
attempt. Fence local guest operations as well as result writes: lease expiry
does not kill an installer. Reassignment waits until prior guest disposition is
known or isolated; a replacement never operates inside the old guest.

Use stable job/deduplication identity bound to artifact, route, policy, checker
and environment, while retaining separate attempt identities. Identical result
identity and bytes return the already recorded disposition. Different bytes
under that identity conflict and hold. A changed artifact at the same version
creates held evidence, retaining both attempts rather than refreshing success.

After a lost claim, upload or completion acknowledgement, query authoritative
state using the original identity before retrying. If committed, retrieve the
recorded digest/disposition; if absent, resume only the same permitted transfer
or transition. If indeterminate, hold and reconcile. Never infer failure from
timeout and repeat an installation. A crash/restart first reconciles leases,
local journals, guest/process identity and evidence before claiming new work.

Retry only classified transient failures within prospectively accepted limits;
integrity, identity, policy or evidence conflicts quarantine immediately.
Retry count, backoff, lease duration, offline grace and maximum elapsed time
remain explicitly unselected pending measured scope. Earlier architecture
numbers remain proposals, not defaults adopted here. Preserve first detection,
original observation time and failed attempts through every retry/reconnect.

## Clean guest and evidence lifecycle

Pin and independently admit image provenance, OS build, configuration, image
digest, tool/dependency versions and reviewed worker/checker source revision.
Keep the accepted base immutable. Record a fresh guest identity and owned run
root per attempt; reject unexpected drift or pre-existing target state.
Snapshot restore alone cannot prove cleanliness or replace image provenance.
Binary hashes and builder receipts bind measured tools to parent claims; they
are not independent source attestation.

Preserve chronology: independent product/route/network approval precedes
retrieval. If no expected digest exists, retain untrusted acquired bytes and
original URL chain/time, compute observed digest/length, then independently
admit product/publisher/edition/channel/release/build identity before a bound
inspection job. Later matching descriptors cannot authorise an earlier fetch.
Expected-digest disagreement holds without silently replacing the expectation.

Independently recompute artifact/job/report/output digests and lengths from
retained exact bytes. Bind initial URL, each exact approved redirect and final
URL, policy/checker/image versions, worker/epoch/nonce, OS/build/architecture
and observation times. A hostname match cannot widen exact-hop permission.
URL syntax is no DNS/connection or publisher proof; draft query support must
not be silently added to existing v2 formats. Preserve original vendor bytes,
extracted payload and transformed outputs separately. No installer mirror or
redistribution follows from private verification storage.

Capture signature integrity, publisher identity, container assessment,
Gatekeeper/notarisation, install outcome, recovery and teardown separately.
Signature/hash success does not prove safe installation or compatibility.
Unsigned container failures stay failures even when payload checks pass.
Unavailable, stale, nonzero or mismatched observations cannot become success;
re-signing, cache hits and re-upload cannot create a fresh native assessment.

After child exit, independently read back installed identity/version, physical
state, logs and recovery baseline before classifying installation. On crash,
retain incomplete state and apply only the approved recovery sequence. Finally
export accepted evidence, verify its custody, stop the guest, and verify the
authorised guest teardown disposition. Missing teardown proof marks cleanup
incomplete and prevents guest reuse. Quarantine unresolved resources; do not
delete arbitrary host paths or run blanket cleanup. Preserve separately gated
destructive authority and the exact existing harness's retained artifacts.

## Secrets, retention and exceptions

Use a worker-specific least-privilege credential limited to its claim/report
scope, with bounded evidence upload capability. The guest receives no broad
cloud-account token, personal SSH key, signer secret or deploy credential.
Provisioning, rotation and revocation require exact custody and owner scope.

| Category | Proposed handling; numeric limits remain unselected |
| --- | --- |
| Job/attempt and trust audit | Retain immutable identity, epochs, approvals, decisions and failure chronology; restrict operator access and preserve recovery checkpoints. |
| Native outputs/evidence | Private bounded storage; redact personal paths, URL secrets and identifiers before approved export while preserving restricted originals where necessary for verification. Record derived redaction hashes separately. |
| Vendor artifacts/cache | Separate from evidence; licence/terms, provenance, byte ceilings, expiry and authorised deletion policy required. No public installer storage. |
| Guest disks/snapshots | Separate clean bases from disposable attempts and forensic holds; inventory ownership and verified disposition. |
| Credentials and incident material | Exclude secrets from logs/exports; restrict incident holds and secret custody independently. |

Before execution select per-category byte/count/time limits, encryption/access,
backup locations, retention/deletion intervals and incident-hold rules from the
measured scope. No numeric retention policy is adopted by this document.
The existing catalogue architecture proposes 90 days for raw native evidence
and 12 months for audit, with evidence/incident holds; those remain unaccepted
proposals to reconcile explicitly when selecting this runner's measured scope.

Hardware dependencies, extensions, UI/permission interaction and other
VM-incompatible behaviours need a named per-route exception record with failed
or unavailable checks, affected OS/architecture and remaining risk. Hold that
route or propose separately authorised physical-target/manual proof. An
exception cannot manufacture a pass or broaden catalogue-wide eligibility.

## Migration and production decision

Keep configuration, immutable input/evidence references, job identities and
checkpoint manifests independent of host paths. A future export must preserve
attempt history, pending outbox/leases, accepted digests, trust versions,
high-water checkpoints and retention holds, with independent restore readback.
Drain/fence the old worker before replacement, reconcile unknown guests/results,
then enrol a separately authorised worker key and retire old access without
resetting epochs or replay history. Export, secret replacement, migration and
host removal remain gated future actions, not permission granted here.

Compare dedicated home Mac mini, rental physical Apple Silicon/on-demand macOS
and GitHub Actions macOS only after current availability, licensing, VM/workflow
restrictions, isolation and workload suitability are verified. None is selected
or priced here. The issue records Andy's local colocation quote of £250/month
excluding data charges; it is an owner quote, not verified current pricing or
an approved purchase. The proof plan defines
the evidence required before any production hosting decision.
