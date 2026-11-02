# Installomator community discovery contract

Original PAT-2619 preparation, 9 October 2026. This packet proposes an ongoing metadata input for the consumer catalogue. The original packet enabled no importer, retrieval, schedule, signing, publication or installation. PAT-2622 now adds only the separately accepted local I1 fixture model described below. The existing [catalogue architecture](catalogue-service-architecture.md), [C1–C10 briefs](catalogue-service-implementation-plan.md) and [release gates](consumer-release-gates.md) retain their own acceptance and authority. A merged planning packet does not make a feed operational or a follow-up ready.

The PAT-2693 acquisition decision records the accepted PR #82 design baseline and pinned source comparison; exact versioned common contracts and vectors still require engineering acceptance and review. Its future benchmark is unmeasured and execution is not authorised. Under the 12 October owner ruling, official Cask metadata is a separate data-only discovery input. PAT-2674 separately owns optional explicit manual per-app Homebrew actions preserving its owning user and ownership, outside Update all, unattended scheduling and the privileged helper. Neither route permits customer execution of upstream recipes.

## Upstream baseline and provenance

Propose immutable snapshots of `Installomator/Installomator` main for community discovery. Resolve and retain its exact commit before reading any tree or fragment. The exact current main SHA has not been collected for this packet; a mutable branch URL is never a checkpoint. The latest tagged release is a comparison/reference baseline, not a substitute for main head. Main is the beta of the next Installomator engine release; that says nothing about a vendor application's release channel. Independently enforce Patched's stable-app policy.

Official guidance checked 9 October 2026 by the parent:

| Source | Use and limit |
| --- | --- |
| [Upstream README](https://github.com/Installomator/Installomator/blob/main/README.md) and [Branches and Betas](https://github.com/Installomator/Installomator/wiki/Branches-and-Betas) | Branch/release context; mutable guidance is not immutable provenance. |
| [Label variables](https://github.com/Installomator/Installomator/wiki/Label-Variables-Reference) and [utils guidance](https://github.com/Installomator/Installomator/blob/main/utils/README.md) | Labels in `fragments/labels/` are the discovery input; the generated root script is not the editable label source or a parser input. Variable guidance does not authorise shell evaluation. |
| [Release v10.9](https://github.com/Installomator/Installomator/releases/tag/v10.9) | Latest tagged release at the check date, commit `1db6d22dbab9221dda9b59561c1bfbbad1956ce9`; reference only, not main head. |
| [Pinned Apache 2.0 licence](https://github.com/Installomator/Installomator/blob/1db6d22dbab9221dda9b59561c1bfbbad1956ce9/LICENSE) | Keep licence, original copyright/attribution and applicable notices with snapshots and derivatives; mark modifications and preserve any applicable NOTICE content. |

Keep the existing `source-provenance.json`, `References/Legacy/firefox.recipe.json` and `ThirdParty/Installomator/LICENSE` byte-for-byte unchanged. Their historical pins describe selective reuse, not this proposed feed. PAT-53/41/512 are historical references; their Done state supplies no consumer service proof. No subtree pull, upstream code merge, shell evaluation, fetched-script execution or trusted-engine replacement is allowed. Customer code never executes upstream recipes.

## Proposed snapshot and parsing contract

All cadence, schema, grammar and numerical bounds below are proposed implementation baselines requiring explicit acceptance. They are not enabled schedules or approved production parameters. Lower limits may be justified and recorded; bounds must never silently increase.

Retrieve a pinned complete bounded tree, without archive extraction, submodule traversal or following symlinks. Admit only regular label files under the exact approved fragment prefix; reject absolute paths, traversal, duplicate/ambiguous paths, malformed UTF-8 and unsafe ancestor/file types. Proposed caps are 10,000 labels, 1 MiB per label and 32 MiB total bytes per snapshot. Over-limit or incomplete retrieval does not advance the checkpoint. Do not partially import a truncated tree.

The proposed initial grammar is deliberately narrower than upstream and is not a zsh parser. These are parent proposal parameters requiring acceptance before I1 is armed, not accepted production defaults. Preserve original bytes/digests, including line endings; never normalise into a different checkpoint.

| Element | Proposed accepted subset |
| --- | --- |
| File and arm | Regular file with ASCII basename matching `^[A-Za-z0-9_-]+\.sh$`; one case label matching `^[A-Za-z0-9_-]+\)$`, whose identifier equals the basename without `.sh`, and final `;;`. No text before/after that one arm except blank lines or comments. |
| Encoding and lines | UTF-8, LF or CRLF, at most 256 lines. Reject BOM, bare CR and control bytes except permitted line endings and tab indentation. Only blank lines and full-line `#` comments; no trailing inline comments. |
| Assignments | Exactly one each of `name`, `type`, `downloadURL` and `expectedTeamID`, in any order, with optional indentation and no spaces around `=`. Each value is one nonempty single- or double-quoted literal. |
| Literal bytes | No quote escapes, backslashes, dollar signs, backticks, embedded newlines or ASCII controls. |
| Field bounds | `name` at most 128 UTF-8 bytes; `type` exactly `dmg`, `pkg` or `zip` as inert metadata; `expectedTeamID` exactly ten uppercase ASCII alphanumerics as an untrusted claim; `downloadURL` at most 2,048 UTF-8 bytes, syntactically absolute HTTPS with no userinfo or fragment. A syntactically accepted URL is never self-approved or fetched by this parser. |

Every other shell form, extra assignment, type or pattern is held. This includes substitutions, variable expansion/indirection, concatenation, branching, functions, arrays, commands, alternation and ambiguous precedence. Unsupported or malformed syntax produces a visible held record retaining its path, original digest and reason; never guess a partial candidate or emulate zsh. Grammar extension is a reviewed targeted repair with regression cases, not automatic coverage expansion.

Each immutable checkpoint binds repository, resolved commit and tree, every label path/content SHA-256, parser and policy versions, observation time and prior checkpoint identity. Retain original attribution/licence alongside source bytes. Commit only after complete retrieval and complete parsing/classification; explicit unsupported/held records count as classified, not admitted. Record failed retrieval separately without replacing the last complete checkpoint. A resume must validate prior checkpoint/digests/parser/policy before proceeding; stale replay, mismatched ancestry or incompatible policy refuses advancement rather than resetting state.

| Observation | Required discovery result |
| --- | --- |
| Added label | New untrusted proposal; independently reviewed route required for a new app. |
| Changed label | Retain old/new bytes and provenance, invalidate affected acceptance, classify semantic changes; source/identity/edition/generation/channel/method changes hold for route review. |
| Identical snapshot or duplicate delivery | No candidate/job/verification work; retain bounded observation/dedup evidence without refreshing artifact acceptance. |
| Removed label | Emit `withdrawn-upstream` discovery fact; no automatic deletion of approved support, signed withdrawal, evidence refresh or publication grant. |
| Unsupported, malformed or hostile metadata | Held with explicit reason and original digest; no shell execution, guessed value or silent omission. |
| Partial retrieval, outage or checkpoint mismatch | Visible degraded/refused observation; prior complete checkpoint and its real age remain intact. |

Propose daily conditional retrieval, respecting upstream rate limits, with at most one run at a time. Network budget is three total attempts per discovery observation: initial plus two retries after one and five minutes. A valid Retry-After up to 24 hours becomes a durable next-due time, never a sleeping worker; longer/invalid instructions hold for diagnosis under accepted policy. Network waiting is separate from active verification work. Repeated failure reports outage/age/next action and preserves stale state honestly. Cadence/hosting/authentication and actual first execution require I2 acceptance; none occurs here.

## Candidate, verification and publication boundaries

Discovery yields proposed metadata only. Route review may independently approve source hosts/paths/ports/redirects, developer and bundle identity, edition/paid generation, stable channel, installer method and evidence requirements. Upstream URLs, Team IDs, hashes and assertions cannot approve themselves. Existing approved-route release candidates may progress autonomously under that policy; any trust/identity/edition/generation/channel/installer change returns to route review.

Future retrieval must use approved HTTPS destinations, reject embedded credentials, IP literals, private/link-local/loopback and ambiguous destinations, and revalidate each redirect, DNS resolution and actual connection. Bounds apply to responses and redirects. Exact network implementation and independent security review are required: URL string checking alone is not SSRF protection. No arbitrary fetch from label or customer input, and no customer inventory, support request or purchase credential is a discovery input.

For the acquired-artifact route proposed in the original 9 October contract, lifecycle is: discovered proposal → explicit route review or admitted candidate under existing policy → resolution within approved source policy → verification of exact artifact bytes/hash/length, publisher/code identity, notarisation and separate container outcomes, OS/architecture and route-specific compatibility → applicable safe installation/recovery evidence → independent policy acceptance, signer assembly and publication → hosted exact-byte independent readback. Later PAT-2724 policy also permits source-verified metadata and approved vendor-native routes without central download/VM testing of every release. Those routes need an accepted authenticated mapping under PAT-2693; this contract supplies none. Clients still verify actual downloads and installed outcomes, with no byte-inspection pass when bytes were not inspected. Targeted tests cover new/materially changed mechanisms and representative success, refusal and recovery, not vendor functional/data-migration certification. Unknown, failed or unavailable checks hold. A signature is not publication, and publication is not readback. Discovery and the VM have no production signing key, signer binding or policy-write authority. C3–C5/PAT-2603/941/7 retain their interlocks.

Vendor-direct downloads, no customer Homebrew dependency, local inventory/matching, stable native/universal launch eligibility and paid-generation/App Store routing remain in force. Include every executed installer/tool/helper/plugin architecture; existing Rosetta cannot widen eligibility. Previously published support retains its own expiry/freshness/withdrawal rules through outages. Re-signing, importing a label or rerunning a failed observation cannot freshen old evidence. Imported label counts never equal supported-app coverage.

## Verify, diagnose, repair and reverify

Start with a small representative set of labels and source/installer patterns, chosen for the accepted parser subset and known refusal cases. For each bounded batch, import with immutable provenance, verify under approved policy, diagnose the exact result, make a targeted reviewed parser/source-mapping/candidate repair, then reverify the changed case and affected previously passing and refusing cases. Expand only after the current slice meets its acceptance criteria. A failed check is evidence to improve the importer or proposal, never permission to weaken checks.

Proposed verification budget: ten candidates per batch, three total attempts per candidate (initial plus two reviewed repairs) and 30 minutes of active work per batch, whichever limit is reached first. Network backoff does not consume that active-work clock. Exhaustion holds the unfinished candidate with reason and next action; independent candidates may continue only within the remaining batch budget. Start a new batch only under the accepted work policy, never to evade an exhausted candidate's cap. Genuine trust mismatch holds immediately without automated repair retries.

| Outcome | Diagnosis, next action and resume condition |
| --- | --- |
| Expected refusal | Negative control behaved correctly; retain refusal evidence, never count as admitted coverage. Resume only for new relevant input or reviewed policy/test change. |
| Extraction/source failure | Record exact parser/mapping error; targeted reviewed repair inside approved policy may progress autonomously, followed by affected positive/refusal regressions. |
| Unavailable environment | Missing native/tool/network capability is distinct from extraction failure. Hold; a later bounded daily conditional availability probe may establish restored capability without resetting acceptance/freshness. |
| Security/trust mismatch | Wrong publisher, tamper or changed trust holds immediately for investigation/independent route review. Never turn it into extraction repair or override success. |
| Passed applicable checks | Record precisely which scope passed; fixture admission is not native verification, route support or publication. |

Each append-only attempt retains attempt/candidate IDs, upstream repository/commit/path/digest, candidate identity and artifact digest/length when known, parser/checker/policy versions, actual environment/capabilities, observed time, outcome/reason, diagnostic evidence digests/references and prior attempt ID. Missing artifact/native evidence stays explicitly absent. Repairs record changed version/bytes and rationale; preserve earlier attempts. Changed bytes, checker or policy invalidate affected results; unrelated valid evidence need not be discarded. Resume requires new upstream data, a reviewed repair or restored capability, with remaining/exhausted budgets visible. Never spin on the same unchanged failure or pass on budget expiry.

Measure verified coverage for the actual parser/policy/native scope, held reasons and ages, repair attempts, unavailable capacity and regressions. Later authorised hosted/native acceptance repeats the same loop with actual evidence. No label total, bulk import target, timer or catalogue-size goal can bypass checks or signer/release gates.

## Future slices and acceptance gate

The dependency-ordered [I1–I3 briefs](catalogue-service-implementation-plan.md#installomator-discovery-follow-ups-i1i3) specify exact proposed files, input/output ownership, executable future commands and meaningful red/green cases. I1 is offline and standalone; I2 requires accepted C1/C2 and actual hosting/access/schedule authority; I3 requires accepted C3–C5 and PAT-2603/941 prerequisites. Later mappings must be accepted against real APIs, never assumed compatible.

Concrete unresolved proposals before arming I1 are its standalone schema, acceptance of the exact initial grammar and its parameters above, resource/attempt/time bounds, available supported Node runtime and full-gate wiring. Recommendation: accept those together before creating a ready implementation brief, because parser semantics and replay/evidence identity must agree. I2 additionally needs hosted access/authentication and cadence authority; I3 needs route-review/job/evidence/private-call/publication mappings and trust gates. Keep those slices unarmed while unresolved; merging prose is not acceptance of production parameters.

**Documentation DONE-WHEN:** parent reads all six actual Markdown diffs against the live ticket and design decisions; `git diff --check` and affected local Markdown file/anchor checks pass; historical reference/provenance/licence bytes remain unchanged. This documentation task has manual acceptance, no executable red/green claim. Parent owns acceptance, Linear, deliberate atomic publication and required PR/main CI. Future logic requires independent full-diff OpenCode/NVIDIA correctness/security review; this prose packet creates no operating proof, resource, key, schedule or follow-up issue.

## Accepted local I1 implementation, 9 October 2026

PAT-2622 implements the bounded offline fixture model following the parent's independently observed Phase A red and explicit Phase B release. The original literal grammar and the accepted standalone snapshot/route/attempt schemas are executable in `services/catalogue/discovery/upstream`. The complete API key sets, canonical identities, independently retained head assumptions, resource ceilings and iteration semantics are maintained in [the fixture contract](../Fixtures/InstallomatorDiscovery/README.md). These are accepted local fixture parameters; the broader retrieval, cadence, route authority, native evidence, service and publication proposals above remain separately gated.

`./scripts/verify-installomator-discovery.sh` exercises the four frozen acceptance files with an existing Node >=22 runtime and whitespace checking. The separate `services/catalogue/tests/upstream-resource.test.mjs` supplements the frozen checks for 1024-byte path and 128MiB metadata limits and hostile recursive/accessor shapes; the full `./scripts/verify.sh` runs both. No dependency/tool installation or workflow change is introduced. Local check success is not parent acceptance, independent review, merged-main proof, native verification or operating-feed evidence.

Snapshots carry injected regular-file/ancestor descriptions and byte arrays. Validation neither opens real filesystem paths nor authenticates an upstream Git tree/ancestry. Same-source reviewed reclassification preserves source parentCommit and observedAt, links the previous classification and invalidates affected acceptance without claiming newer source data. Iteration stores append-only detached history, revalidates the full history against an independently retained fixture head, and cannot reset lifetime candidate attempts by switching batches. Unfinished work retains its originating active-time budget. Valid new evidence refs are fully reverified into a newly bound row; bad publisher, artifact, check or availability observations remain held. No fixture result includes nativeEvidence or publication authority.

The three-attempt lifetime candidate cap and finite saved-state ceiling deliberately stop local fixture work. They are not a future production feed's release-job policy. I2 retrieval and I3 publication/integration are still unarmed, and no real filesystem race safety, producer authentication, durable anti-rollback, native execution or installation claim follows from these tests. Historical source-provenance/recipe/licence files remain byte-for-byte unchanged.
