# Licensing implementation briefs (PAT-2605)

**Internal planning document, originally prepared 9 October 2026.** The merged local fixture slices L1, L2, A1, P1 and A1 diagnostics are implemented and verified as recorded below. Remaining service, native-key, provider, payment, application-composition and release work is proposed; this document alone does not authorise or prove it. Each future bounded slice still needs its own accepted scope and gates. The historical preparation changed documentation only; it is not a statement about the later merged implementation commits.

The initial reconciliation used supplied 9 October owner records on documentation base `c026fbf`; its source/CI observations remain historical. The later merged fixture work and verification are recorded in the slice notes below. Purchase ownership contract B0 is a technical preparation dependency, not another request to decide the accepted customer experience.

## Phase 0: source and policy

Read canonical `/Users/example/Development/Patched.im/AGENTS.md`, `commercial-direction.md`, repository `AGENTS.md`, and live PAT-2605, PAT-2587, PAT-2588, PAT-2589, PAT-2590, PAT-2592 before any future code. Refresh main and record the exact SHA; this packet read `33c23cd9bf04df04c28aec59a5a52aa8495f19d6`, matching HEAD/origin/main. Later source changes need reinspection, never replacing that historical evidence with a guessed current SHA. Inspect `Package.swift`, `scripts/verify.sh`, `Sources/PatchedApp/PatchedApp.swift`, `Sources/PatchedClient/ClientController.swift`, `Sources/PatchedOperator/OperatorController.swift`, and `Sources/PatchedCore/UpdateTransaction.swift` before composition. The current client/operator are read-only prototypes, not inert shells; public real transaction entry points still refuse. No licence may enable fixture authority.

Read complete [licence](licensing-contract.md), [allocation](device-allocation-contract.md), [billing](billing-lifecycle-contract.md), [support](licence-support-contract.md) and [CF readiness](cloudflare-licensing-readiness.md) contracts. Newer owner policy wins. Linked omnibus tickets retain their own acceptance; this plan creates no duplicate implementation tickets. Read PAT-2606/2607/2608/2609 for catalogue, helper, internal requirements and independent Sparkle self-updates. Their preparation docs, once accepted, are interface dependencies, not shipped capabilities.

Policy reconciled: seven-day renewable beta with at least seven days' notice; no trial during active beta; explicit no-card once-per-account 14-day trial; five registered household slots; paid outage cap and fixed confirmed failed-renewal grace; partial refund/dispute/reversal/cancellation rules; routine retention and fixed 12-month trial marker; broad compatibility/hardware preferred with explicit cloneable fallback; one shared physical Mac/household slot; recovery old-email notice, 72-hour wait, customer web code and complete session/activation reset with history preserved. Expiry leaves local discovery/catalogue matching/accurate update display and Patched self-updates available. New third-party manual/scheduled/queued installations are gated at the actual start boundary. Vendor updater settings remain unchanged. Ownership evidence, privacy/financial review, helper-declined activation behaviour and live runtime/release evidence remain gates.

## Latest launch, setup and shared-core boundaries

OWNER decisions recorded later on 9 October supersede the provisional product-floor language: launch is macOS 15+ on Apple silicon, pending actual proof. Current source `Package.swift` macOS 13 remains recorded implementation state only. A future accepted native packaging/integration slice must reconcile deployment targets, architectures, helper APIs and Sparkle/key adapters with 15+; do not raise the floor for optional App Attest or silently promise Intel/13/14 support. Pure parser/policy fixtures can run in existing proof scope without asserting release compatibility.

Download Patched and drag it into Applications; initial local scan, catalogue matching/update visibility and newly supported-apps page remain account-free. Licence/network/key adapters are lazy: anonymous discovery must work when no session, activation key, licence Worker or helper exists. New third-party manual/scheduled/queued installation requires valid beta/trial/paid access and all normal trust/consent checks at actual start. Explicit Start trial requires verified email. App-originated confirmed purchase auto-activates the securely bound purchasing Mac without email-first sign-in; website purchase needs purchase-email code plus confirmed entitlement/device proof. Neither starts a trial or opts into automatic installation. Additional Macs, recovery, sensitive household actions and private support requests require verified ownership. Checkout contact email never grants/merges an existing household. The proposed [payment activation contract](payment-activation-contract.md) owns the restricted pending-owner/claim protocol, distinct from verified household control. Sign-in never auto-starts a trial. Native/universal candidates must have a usable Apple-silicon execution route across app, installer, helper, tools and plugins; hidden Intel-only dependencies defer, Rosetta presence does not widen policy and Patched never automatically installs it. Intel-only installed apps stay visible. An offered Intel-to-native migration needs exact product/edition/channel/licence, data compatibility and transaction/recovery evidence, not bundle-ID equality. Manual Intel/Rosetta work needs separate scope.

Setup explains optional helper approval separately from App Management consent and per-installer permissions. Record the actual responsible signed app/helper/installer identity, code requirement and OS permission outcomes; helper administrator approval is not privacy consent. Never bypass OS approval or request blanket Full Disk Access/Accessibility. Account-free scan/view remains available when installation/helper permission is denied; preserve the existing disclosed shared-Mac activation dependency, without extra slots per login. UI shows permission-needed/deferred state and supported navigation, not hidden permission assumptions.

**Future SME boundary review required in every acceptance.** Keep one shared codebase. Reusable catalogue verification/discovery/matching, transaction/recovery and helper operations must not embed household email flow, five-Mac cap or consumer pricing. Place those concrete rules in PatchedLicensing, consumer allocation/billing and UI/service policy modules. Stable opaque ownership IDs and explicit authorization enter shared interfaces; product mode never bypasses installer trust. Later smaller self-service business needs could add organisation ownership/roles, managed settings and business billing at those boundaries, with explicit schema/ownership migration and fresh trust/privacy review. Consumer rollout/installed proof first; no numerical size cutoff, enterprise procurement/questionnaires, tenants/remote inventory/commands, generic policy framework, speculative feature implementation or fork. Residual migration of account/ownership/billing schemas and helper membership may still be necessary; no promise of zero rework.

**Named platform proof matrix, proposed targets, no authority to install.** Coordinate these proposed IDs with [consumer release gates](consumer-release-gates.md) and the [central platform launch contract](platform-launch-contract.md); this table states the licensing/native cases, not a second coverage ledger.

| Proposed target | Platform | Required evidence (all unrun) |
| --- | --- | --- |
| AS15-LIC | Named approved Apple-silicon Mac, macOS 15 latest supported test patch recorded at run | Signed drag/drop/setup/relocation; no-account scan/match/view; correct signed identity; App Management allow/deny/not-decided/revoked; helper decline/remove/reapprove; native UI; key fallback/enclave; signed catalogue/lease refusal; exact installed success/recovery; multi-user/queue; self-update/upgrade identity continuity. |
| AS26-LIC | Named approved Apple-silicon Mac, macOS 26 exact patch | Same complete matrix; source build success on another OS is insufficient. |
| AS27-LIC | Named approved Apple-silicon Mac, macOS 27 exact patch | Same complete matrix; current-host read-only CLI inspection alone proves none of installed/setup/permission/self-update paths. |

Fixture acceptance adds anonymous discovery with all licensing adapters refusing, sign-in with no trial timestamps, explicit trial then start, expired access, permission denial/revocation and no Rosetta mutation. Operating matrix records hardware/OS/build/source/signing identities, approval prompts, before/after/recovery evidence and per-case outcome. New named targets, app/helper installation, keys and signing remain separately authorised. Future OS versions need fresh proof before support claims.

## Common execution and review contract

Each later leaf brief owns only its named files, no recursive delegation and no commits unless the parent explicitly assigns sole-writer atomic authority. Parent reads the actual complete diff, runs the relevant full gate, accepts and owns publication under standing authority. Follow the current Codex model and escalation policy in the canonical `/Users/example/Development/Patched.im/AGENTS.md`: during pre-production, use `gpt-6.1-sol` at medium for orchestration and implementation, including trust-boundary work and diffs over 400 lines; try Sol at high for a concrete unresolved problem, then use a fresh bounded `gpt-6-astra` at high only if that attempt fails or a specific capability gap is recorded. Keep collection on `gpt-6-luna` at low where appropriate. Record requested runtime metadata; if unavailable, say so. Independent reviewer floors remain unchanged: logic diffs require the canonical independent full-diff security/correctness review, and Codex or Claude self-review is not a substitute. Red/green evidence must demonstrate the security invariant, not mirror implementation. Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required.

Future service and remote-operation scripts below remain proposals and are not present as implementation. The existing local fixture gates, including the merged licensing, activation and support slices, are listed in the repository [README](../README.md); PR #32 records combined-gate verification at that revision. Native app/check binaries are never launched except separately scoped offscreen checks or explicitly approved operating proof. Tests write only disposable `.build` or isolated local service state, never real Keychain or production D1 by default.

## Proposed service harness and repository amendment (T0)

**PAT-2639 local implementation state, 11 October 2026.** The parent observed
compiling red (12 unit failures with the network-denial canary passing, plus
actual local D1 schema/readback followed by the fixture rollback refusal), froze
the nine check/tooling/verifier files and released the minimal fixture runtime.
`service/licensing` now implements only marker checks, deterministic injected
adapters and two hardcoded toy D1 batch operations. The focused gate passes
locally; parent native full-gate verification, independent review and publication
remain required. See its README for the exact toy schema, rollback proof and
limits. No licence/account/session/provider API or deployment exists.

Official preflight refreshed Node 24.21.0 LTS and its bundled npm 11.19.0,
TypeScript 7.0.2, Wrangler 4.149.0, Vitest 5.0.3, workers-types 5.20261011.1
and Node24 types 24.19.2. Exact local development dependencies and lockfile
install with `npm ci --ignore-scripts`; registry audit returned zero advisories.
Node 24 was absent from the inspected local tool locations, so the official
archive and SHASUMS were downloaded and SHA256-verified only under this
worktree's ignored `.build/toolchain`, with no global activation. Ordinary host
PATH remains Node 26; the verifier honestly requires pinned Node/npm on PATH.
`wrangler.jsonc` follows current Wrangler guidance for new configuration, with
explicit 2026-10-11 compatibility date, fake database ID and mandatory local
marker. Read-only path-scoped CI pins Node and action revisions; the existing
native verification workflow remains required. The original proposal below
records preparation history, superseded by these checked local tooling facts.

Placement `service/licensing/` and separate service/native deployment are OWNER-settled. Proposed tooling is Node 24 LTS, npm 11, TypeScript `7.0.2`, Wrangler `4.149.0`, Vitest `5.0.3`, `@cloudflare/workers-types` `5.20261009.1`, no production dependency initially (Workers Web Crypto/fetch and a small explicit router). These package versions were read from official npm registry `latest` endpoints on 9 October, not installed or evaluated together. Node/npm exact patch and compatibility remain an implementation-preflight fact: choose an available supported patch, record it in `.node-version`/`packageManager` and engines, prove the versions together and refresh vulnerable/incompatible pins before acceptance. Do not fabricate an installed toolchain. Exact dev dependency pins without `^`/`~`, committed `package-lock.json`, `npm ci` only in CI, reviewed lockfile diffs, no ad hoc curl installers. Do not add an SDK or canonicalisation library without a reason/security/licence review.

Scope: `service/licensing/{package.json,package-lock.json,tsconfig.json,wrangler.toml,.node-version}`, `service/licensing/src/{index,environment}.ts`, `service/licensing/tests/harness.test.ts`, `scripts/verify-service.sh`, repo `AGENTS.md`, `.github/workflows/licensing-verify.yml`. No app packaging/deploy workflow in T0. Proposed commands:

```sh
npm --prefix service/licensing ci --ignore-scripts
npm --prefix service/licensing run typecheck
npm --prefix service/licensing run test:unit
npm --prefix service/licensing run test:d1-local
./scripts/verify-service.sh
```

Proposed script meanings: `typecheck` runs `tsc --noEmit`; `test:unit` runs `vitest run tests/unit`; `test:d1-local` drives local Wrangler D1 with an isolated `.build/licensing-d1` persistence directory and no remote flags; verifier combines them. First implement the harness with network-denying fake adapters and deterministic clock/randomness; a fixture marker forbids production configuration. Wrangler compatibility date is an explicit reviewed proposal recorded in config at implementation, not inferred from latest CLI.

AGENTS amendment authorises only the accepted local service scope, preserves all current no-launch/install/fixture-trust constraints, records separate licence/catalogue/release identities and path-scoped gates, and requires runtime credential/deploy scope separately. CI read-only permissions, pinned action revisions, no secrets in PR verification, paths scoped to licensing/shared fixtures/scripts with native gate also required when Package/Sources change. Whole-repo passing status cannot skip a touched component's gate. Deploy identity later has no catalogue signing or app-release authority. No account IDs/secret values in fixture config.

DONE-WHEN: accepted tool versions/lockfile reproducibly install in authorised scope, no network by unit tests, local D1 fixture schema rollback smoke test fails before implementation and passes after, wrong/mixed environment refuses, existing native gate remains green, independent pipeline review passes. UNBLOCKS-WHEN: parent accepts toolchain/scope and permitted installation in the future task; reason: repo currently has only dependency-free Swift scope. No live CF/Paddle/Keychain prerequisite.

## L1: pure lease and entitlement policy

**PAT-2613 merged state.** The pure L1 fixture slice is merged in PR #28 at `d3409f5585c06d48d4b0ca7e004e113a8ba9576f`. PR #32 (`62b831bc3dc791b153f82683da4e93f01add8a4d`) records combined-gate verification at that revision. It includes strict exact-byte signature verification, state/evidence bounds, injected replay checkpoints and time, refresh classification and a new-start-only gate. The earlier Phase A failure and focused mutation evidence under `.build/pat-2613-evidence` are historical implementation evidence. The signed contract remains a proposal outside this accepted subset. Clock interpretation accepted by the parent: a wall reading below the injected highest observed wall refuses new starts conservatively, as section 12 specifies; otherwise effective time uses the maximum of server-plus-monotonic-elapsed, wall and high water. A frozen nondecreasing wall still ages via elapsed time. This trades availability for fail-closed rollback handling. No OS clock, durable cache/session, service, native key, app composition or installation proof is implied. Fixture preparation uses a fixed exact-message RFC8032 signature corpus independently produced with existing Node built-in crypto and verified by CryptoKit. CryptoKit signing randomises signatures, so the Swift fixture assembler cannot be described as a general deterministic signer. Unknown corpus inputs refuse; the Worker producer and cross-runtime implementation remain future S1 work.

Scope: `Package.swift`; `Sources/PatchedLicensing/{Entitlement,LicenceStrictJSON,SignedLease,LicencePolicy,LicenceClock,LicenceGate}.swift`; `Tests/PatchedLicensingChecks/{main,LeaseChecks,ClockChecks,PolicyChecks,Fixtures}.swift`; `Fixtures/Licensing/{README.md,vectors/*.json}`; `scripts/verify-licensing.sh`; append the new gate in `scripts/verify.sh`. No PatchedCore change or app wiring. Module default trust empty/refusing; fixture signing keys only in the check target. `LicenceGate` accepts only third-party new-start candidates and cannot express recovery or Patched self-update authority.

Proposed command: `./scripts/verify-licensing.sh` builds then runs `swift run --skip-build patched-licensing-checks`, followed by existing `./scripts/verify.sh`.

Red/green: exact-byte/domain separation; unknown key; malformed/duplicate/escaped duplicate/unknown claims; 16KiB envelope/8KiB payload/depth4/base6464-byte signature bounds; cross-account/key/activation; every exclusive deadline and checked overflow; late trial lease with incorrect original start/end; beta seven-day/scheduled cap; no inferred grace; time rollback/frozen wall/sleep/reboot; replay/equal sequence with different bytes; empty default. Anonymous first launch with no session/key/Worker and expired trial/paid/outage leave discovery/self-update policy independent but deny new third-party starts. Full local-state snapshot restoration is an admitted limitation, not a falsely passed tamper test.

Completed for the merged L1 fixture scope in PR #28; PR #32 records combined-gate verification at that revision. These checks establish only the stated source-level policy bounds. No Cloudflare, mail, Paddle, real key or native-launch capability is included.

## L2: injected client, replay and session state

**PAT-2614 merged state.** The fixture-only L2 client is merged in PR #29 at `4857e0b2959bde5945dfb03cb061a60078255196`; PR #32 records combined-gate verification at that revision. It persists request/clock-observation fences, accepts responses through versioned atomic replacement, preserves replay and terminal state independently of cached bytes, rejects changed session generations and gates only third-party new starts. The Phase A red, 133-case focused run, 13-failure mutation and restoration are historical implementation evidence. L1 source, the fixed signature corpus, Core and app composition remain unchanged. The new checks use the existing test-only dynamic signer. No native behaviour or release readiness is implied.

**Explicit fake storage contract.** A read returns one coherent versioned record, separating the replay checkpoint, verification block, terminal revocation and in-flight fence from cached envelope bytes and time anchor. Compare-and-swap atomically replaces the whole record only at the expected version. Acknowledged success is durable in the fake model; conflict writes nothing; a thrown write can leave either the old record or the complete replacement, never a partial replacement. Each committed CAS increments the version by exactly one without reuse, including after restart; `UInt64.max` cannot be incremented. Tests retain only that store across simulated client restarts, never an in-memory client latch. This is a future adapter requirement, not proof of Keychain, disk atomicity, real multi-user coordination, power-loss durability or resistance to restoring an earlier complete valid snapshot.

**Parent-adjudicated failure boundary.** Persist a fence before issuing a refresh and before observing clock values whose high water must be saved. If that first write fails, refuse without issuing the request or observing time. The original live operation may resolve only its own still-current session/generation fence through atomic acceptance. Successful nonterminal refusal persistence leaves a recoverable verification block; only a valid newer own-request response for the unchanged binding/session clears it. New sign-in preserves safety metadata. A fence orphaned by interruption, session change or uncertain persistence is terminal uncertainty for that activation in this slice: a restart cannot distinguish an unanswered request from a received revocation whose subsequent writes all failed, or recover an advanced clock value that was not saved. New sign-in and paid renewal cannot clear that uncertainty. This deliberately sacrifices availability after interrupted operations. Native/operator recovery is unimplemented; transparent restart recovery is not promised.

**Initialization/recovery limit.** Fixtures explicitly seed previously authenticated safety history and, when testing cached starts, its matching previously accepted envelope/anchor. Missing, corrupt or unreadable whole safety history cannot be bootstrapped from zero by this client, even when a response could be fetched. A retained trusted checkpoint with missing/damaged cached bytes can recover only by a valid newer authenticated refresh. First sign-in and authoritative restoration of unknown replay history are outside this subset; it is not a complete first-sign-in client. An explicitly provisioned known-history fixture with no cached bytes grants nothing before its successful refresh.

After L1, scope `Sources/PatchedLicensing/{LicenceClient,SessionStore,LicenceCache,LicenceTransport}.swift`, `Tests/PatchedLicensingChecks/{ClientChecks,StorageChecks}.swift`; fakes only. No real Keychain/network. Integrate shared account/activation/revision/time identity checks; retain `verificationBlocked` and terminal markers separately from cached bytes. Success means valid newer authenticated lease, not HTTP200. Never heal missing/corrupt state from defaults.

Proposed command: `./scripts/verify-licensing.sh`, then existing full gate. Red/green: 401/403/bad TLS/malformed/foreign response followed by 503 cannot revive cache; revocation plus restart; dropped response and stale sequence; cancelled old session; response/account switched midrequest; shared activation sequence advanced by another user; corruption/partial persistence; known revoked ID never becomes active after paid renewal. DONE-WHEN: deterministic transport/storage schedules prove latch durability and atomic acceptance, no real credential writes. UNBLOCKS-WHEN: L1 accepted; fake storage needs no native API fact.

## S1: local account, trial and cleanup service

After T0/L1, scope `service/licensing/src/{auth,store,entitlements,leases,email,ratelimit,audit,retention}.ts`, `migrations/0001_accounts.sql`, `tests/unit/{auth,trial,leases,retention}.test.ts`, `tests/d1-local/{account-concurrency,cleanup}.test.ts`. T0 owns the runtime entry point, so change it sequentially. Migration 0001 owns `account_guard`, accounts, challenges, sessions, source ledger, protected trial marker, ordinary request and audit tables. Email/key adapters use only fake secrets and recipients. Shared vectors must produce identical lease payload/signature bytes in Worker and Swift.

Proposed commands: T0 service verifier and L1 verifier, then full native gate if shared vectors/Package change. Red/green: concurrent code consumption creates one session; challenge send/attempt limits/non-enumeration; purpose/session/case binding; token rotation with lost response; explicit concurrent trial start; active beta refuses without consuming trial; checked UTC clocks; account/source revisions and nonce-fenced dependencies; lost audit rolls back. Trial deletion/re-registration at one second before, exactly at and after 12-calendar-month expiry; leap-day/month-end clamp; refused request/re-registration never extends marker. Cleanup before/at deadline, twice, under concurrent refresh/release; no outstanding grant/financial dependency removed; deleting account strips ordinary profile while restricted necessary denial/history stays bounded. No deleting real data.

DONE-WHEN: local fixture SQL constraints and every race schedule pass, source vectors agree, no automatic invoice/provider/mail action, no credential in logs and review accepted. UNBLOCKS-WHEN: T0 accepted; local implementation can proceed without live CF; privacy basis/HMAC custody/runtime restore block live acceptance, not fake policy work.

**PAT-2640 local retention-only subset.** After independent parent observation of
compiling Phase A red and freezing 251 additive unit checks, the pure
`service/licensing/src/retention.ts` module now passes them locally. It provides
closed-category deadlines, separate trial-marker proposals and trial eligibility,
and cleanup eligibility requiring all explicit protections to be clear. Its
technical domain is integer UTC Unix seconds `0..253402300799`, checked
86,400-second days, and original-UTC calendar-month addition with day clamping.
Marker expiry is exactly 12 months from original deletion; unexpired existing
markers win and existing account trial history never resets. Injected inputs
establish no identity, immutability or deletion authority. Active accounts and
financial categories receive no automatic cleanup schedule. See the service
README for exact assumptions and validation. No SQL, storage, HMAC/key custody,
authentication, provider, network, real cleanup or native wiring is implemented.
The wider S1 proposal, privacy/financial review, D1 race/restore evidence, parent
acceptance, independent review and publication remain separate requirements.

## A1/A2: activation model then local D1 allocation

**PAT-2615 merged state.** The ordinary pure reference-model subset is merged in PR #30 at `4b95fdf760d782d3a721e6ecdc58348fe77455c7`; PR #32 records combined-gate verification at that revision. The six-file dependency-free target implements strict action/proof parsing, P-256 possession, explicit optional fixture attestation and the atomic five-slot value ledger. The default key provider remains refusing. This establishes neither native key security, remote concurrency nor product readiness.

**PAT-2620 merged diagnostic state.** Check-only bounded capture is merged in PR #32 at `62b831bc3dc791b153f82683da4e93f01add8a4d`. It adds stale-capture/output-bound coverage and independently replays exact public last-prepared proof bytes; apply guard, current ledger state and model-state replay remain unobserved. Original assertions/vectors and production activation sources stay frozen. Diagnostics collect evidence; they are not a cryptographic correctness fix or native capability.


The local fixture interface injects service-owned session/challenge/account state and grant windows through `@_spi(Testing)`; it does not implement household authentication or entitlement issuance. A batch is one value transition. Failed shared account CAS and audit roll the entire snapshot back. Activation-revision `stale` instead follows allocation section 6: a terminal stored/audited result may consume its challenge, without slot/history mutation; failed stale audit rolls back its claim/nonce too. Transient guard refusals have no persisted retry row in this local subset. Recovery uses the parent-approved local encoding assumption of a 32-lowercase-hex case ID and 64-lowercase-hex SHA-256 case digest, compared with trusted case/challenge values. That encoding is not an established live service contract; service/support compatibility remains an integration gate. Names reject forbidden raw controls before trimming and NFC normalisation, while hashes retain the original action bytes. Under allocation section 6, replay of any completed active `leased` result yields `superseded` with no allowance, even when it is still the latest sequence; a fresh request must obtain any new allowance. Section 9 identical-input retries apply to the revoked denial, never a stored active grant. See the fixture README for evidence and limitations.

A1 after L1: exact `Sources/PatchedActivation/` files in allocation section 12, `Tests/PatchedActivationChecks/`, `Fixtures/Activation/vectors/`, `Package.swift`, `scripts/verify-activation.sh` and full-gate hook. Include hardware/fallback assurance labels, shared-household model and recovery possession operation5; no Keychain/helper. A2 after T0/S1/A1: `service/licensing/src/{activations,deviceProof,attestation}.ts`, `migrations/0002_activations.sql`, `tests/unit/activation.test.ts`, `tests/d1-local/activation-concurrency.test.ts`. Optional attestation adapter defaults absent. Store last granting bounds and maximum of every issued grant atomically; do not store only a last response that can understate an older valid grant.

Proposed commands: `./scripts/verify-activation.sh` (`swift build`, `swift run --skip-build patched-activation-checks`), service verifier, existing full gate. Red/green: five/six/final-slot N-way race; simultaneous same-household key reuses one slot; other accounts never coalesce; replace/deactivate race; identical request/action replay; changed proof with stable action retry; lost response; stale guards with no dependent writes; released IDs never restored after request-row TTL; copy session without key refuses; cloned fallback identity is explicitly accepted limitation; recovery proof binds case/digest and changes no grant. Support/operator deactivation uses its own verified operator guard and `operatorDeactivated` reason, same shared revision/audit/slot invariants.

DONE-WHEN: model plus local SQL all orderings/rollback/refusal tests pass; no copied-key hardware-uniqueness claim. UNBLOCKS-WHEN: shared contracts accepted and local harness exists; actual remote D1 correctness still needs R1 below.

## U1/A4/A5: display and fake account page

After L1/A1, scope `Sources/PatchedUI/{LicenceView,LicenceViewText,ManageMacsView,ManageMacsText}.swift`, `Sources/PatchedLicensing/LicencePresentation.swift`, `Sources/PatchedActivation/ManageMacsPresentation.swift`, relevant existing offscreen UI checks. After S1/A2, scope `service/licensing/web/account/{index.html,account.js,account.css}`, `service/licensing/tests/unit/account.test.ts`. No live origins/real sessions, no PatchedApp composition yet. UI uses system font. Web cookie Secure/HttpOnly/host-only/SameSiteStrict, 12h absolute expiry, exact Origin/CSRF for mutations; no third-party scripts/localStorage tokens.

Proposed commands: licence/activation/service verifiers plus existing `./scripts/verify-ui.sh`. Red/green: anonymous entry before first sign-in with refusing licence/network/key adapters, sign-in alone consuming no trial, explicit Start trial transition, every expired/verification/slot state, trial unavailable during beta, duplicate Mac labels differentiated, untrusted strings render text, CSRF/wrong Origin/cross-account refusal, no web key creation/activation minting. Display available updates independently with freshness/unknown state; expired licence never conceals matched updates. DONE-WHEN: offscreen/state assertions pass and no UI value grants installation. UNBLOCKS-WHEN: accepted fake interfaces; live host/session proof separate.

## B0: purchase-to-installation/household contract before purchase integration

Product experience is OWNER-settled. The now-existing [payment activation contract](payment-activation-contract.md) proposes pending-owner/provisional-account identity, protected one-use claims, restricted sessions, website email-code activation, guarded promotion/transfer and exact P1-P3 paths. B0 denotes joint technical acceptance of that proposal under billing R8/licensing G10, not a competing implementation or another owner decision. Resolve exact signed schema/lease compatibility, shared two-owner transfer/slot atomicity, custody/loss/retry, collision isolation and provider correlation before S1/A2/B2 purchase extensions. Ordinary verified-session mechanics do not implement initial paid claims.

Use payment contract P1's `service/licensing/src/{purchase-claims,ownership-resolution}.ts`, migration `0005_payment_activation.sql`, `service/licensing/tests/payment-activation.test.ts` and proposed `scripts/verify-payment-activation.sh`; payment P2 owns the named Swift client/state/check paths. Do not create a second `billing/purchaseBinding.ts` or competing claim module. Retain delayed/duplicate/out-of-order/cancelled/refunded payment, expired/foreign/replayed/already-claimed claim/code, concurrent one-slot consumption, wrong environment/price/device, lost installation, generic account collision and verified-session-change fixtures. Confirmed payment/code alone cannot grant unrelated access, private support, recovery or trial. Actual E3/E4 and payment P3 sandbox proof precede integration, not independent L1/A1/support-P1 fixtures. All proposed commands remain unrun/nonexistent until introduced.

## B1–B4: fixture billing, dependency order

After T0 and accepted shared service schema, B1 owns `service/licensing/src/billing/{config,webhook,strictjson,canonical,inbox}.ts`, `migrations/0003_billing.sql`, `tests/billing/{inbox,signature}.test.ts`, `Fixtures/Billing/events/` exact bytes and metadata. After S1/A2 and B0 contract acceptance for purchase paths, B2 adds `billing/{paddle,intent,reconcile,derive,periods}.ts`, `tests/billing/{fake-paddle,reconcile}.test.ts`, snapshot/expected fixtures. B3 adds `billing/{grace,adjustments,status,renewalStop}.ts`, lifecycle tests and `Sources/PatchedLicensing/SubscriptionSummary.swift` with its checks. B4 adds `billing/{reminders,outbox}.ts`, `src/web/billing.ts`, reminder/page checks. Sequential changes to migration/harness only; no parallel writers.

Proposed `scripts/verify-billing.sh` runs service typecheck and `npm --prefix service/licensing run test:billing` (Vitest `tests/billing`), plus licence verifier for native summary; existing full gate remains green. B1 red/green: raw-byte HMAC and strict parser, duplicate event/different notification/whitespace dedup, conflicting event quarantine, failed durable inbox no200. B2: forged callback/email/custom_data grants nothing; qualifying transaction ownership/price/env/currency/quantity, delayed/out-of-order events, contradictory provider read sets, older provider time, shared CAS loser writes zero, periods never re-dated. B3: fixed renewal grace, cancelled/refunded/chargeback exclusions; cancellation acknowledgement before confirmed grace void; partial refunds unchanged; warning/open dispute unchanged; full refund/chargeback only affected period; reversed chargeback remaining original span after review only; reversed refund no automatic restore. Simultaneous customer cancel/support refund/chargeback join one renewal-stop row; refund rejection cannot cancel another cause; lost dispatch/result read-back never resends. B4: generation change invalidates unsent notices, actual send claim race audited, lost send acknowledgement stays ambiguous, no email sent by tests.

DONE-WHEN per slice: its deterministic cases pass red/green, independent review accepted; labelled fixture implementation only. UNBLOCKS-WHEN: preceding local slice accepted. Provider shapes E1–E12 and actual API scope/authority block sandbox/live acceptance, not fake derivation. Reminder wording and recipient authority remain separate.

## P1–P5: support and recovery

**PAT-2616 P1 merged state.** The pure licence-support mechanics are merged in PR #31 at `7580b0a6964d9f8a3dd523d5adbf89397f23d408`; PR #32 records combined-gate verification at that revision. The six `PatchedLicenceSupport` sources implement strict exact-byte parsing, typed targets, literal display and Testing SPI transaction/recovery mechanics; the ordinary default client permanently refuses. The Phase A failure, 249-case focused gate, full-gate result, ownership-guard mutation and restoration are historical implementation evidence. `Fixtures/LicenceSupport/README.md` records local schema choices and limits. These are reference choices, not live provider/identity/service formats. Descriptor/case hashes bind bytes but authenticate nobody. Real ownership standards/authentication, notices, recovery mutation, native/app composition and provider/service work remain unimplemented. L1/L2/A1/Core stay unchanged.

P1 owns pure `Sources/PatchedLicenceSupport/` paths, fixture/check targets and gate named in support section12; P2 adds its separate UI/paint checks. `./scripts/verify-licence-support.sh` now runs `patched-licence-support-checks`; the local P2 `./scripts/verify-licence-support-ui.sh` runs `patched-licence-support-ui-checks`. Pure targets hold no service identity or keys. P3 after S1/A2/B3 owns `service/licensing/src/operator/{auth,lookup,prepare,actions,recovery,audit}.ts`, `migrations/0004_support.sql`, `tests/operator/`. Build local fake identity/provider policy without live Access. P4 real operator sign-in/credential storage and P5 `Sources/PatchedOperatorApp/PatchedOperatorApp.swift` composition are separately gated native trust-boundary scopes; never share catalogue configuration/key authority.


**PAT-2650 P2 local source state, 11 October 2026.** The parent observed compiling
83-case Phase A red with 37 failures and froze the additive checks and interface
before releasing implementation. The standalone controller/view/text target now
uses a permanently refusing ordinary client; only Testing SPI injects fake
client, context, time and typed provider readback. Confirmation requires an
explicit post-display call with the exact bytes/digest and unchanged synthetic
operator/customer/session/revisions/time. Reentrant callbacks invalidate older
generations; dispatched request/digest pairs remain fenced for controller life.
The closed bounded whitelist displays full safe identifiers, target bounds and
compiled consequences while omitting nonce, codes, claims, evidence, note hashes,
notes and raw errors. This deliberately narrower local preview does not implement
the future full service/operator evidence or reason-note workflow. Provider intent
commit means requested, with separate fresh fully bound fake readback required
for synthetic confirmation. Refresh/readback ambiguity never establishes success.
Recovery and email change always remain unavailable. Native system-font views
paint offscreen beneath `.build`, without app composition/launch, real auth,
provider, network, key, mail, storage or installation authority. Parent acceptance,
visual inspection, independent review and publication remain separate gates.
CHECK-MODIFIED covers only additive target/check/full-gate registrations and the
explicit parent-accepted Package.swift digest change in the catalogue v2 frozen
baseline from `43d5eb107f9821cfc9e36a8d22f0154b6422057cc41d2b887b8bdc59877109c2`
to `8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699`.
All other baseline entries and existing behavioural assertions stay exact.

Red/green: consumer session cannot gain operator; exact identifier lookup, no enumeration/logging secrets; wrong customer or stale account/activation/provider mappings refuses; descriptor bytes/digest exactly match displayed confirmation; audit rollback; independent fresh human auth required, token `iat` insufficient; once-only provider intent shared with B3. Recovery: old email/receipt/copy token alone refuses; possession only is insufficient; purpose/case/digest mismatch; notice acceptance plus 259,200s exclusive boundary; objection/ambiguous notice holds; new-address code customer-only/current; collision with existing account; all-session revoke/all-activation release while preserving trial/beta/period/account ID; auth refusal then outage does not resurrect. Pure/fake cases cannot establish human ownership.

DONE-WHEN P1/P2/P3: fixture checks and service verifier pass with actual review and clear unconfigured/refusing defaults. UNBLOCKS-WHEN for real P3/P4/P5: operator identity issuer/audience/stable subject and supported native flow verified, fresh interactive-authentication evidence bound to purpose/session demonstrated, applicable credential/Keychain authority, real provider proof and privacy acceptance. Recovery mutation remains disabled until Andy accepts adequate paid/trial/beta evidence standard and explicit exceptional lost-email/all-Macs procedure; recommendation: retain mandatory device check in routine path and manually refuse unsupported exceptional claims because a receipt/new email/stolen unlocked Mac does not identify the owner.

## N1: approved native key and machine-wide broker proof

After A1/A2/L2 and PAT-2607 accepted architecture, scope `Sources/PatchedActivationKeychain/{SecureEnclaveActivationKey,SecureStorageActivationKey}.swift`, `Sources/PatchedMachineIdentity/{MachineIdentityStore,MembershipVerifier,PurposeBoundSigning,MachineLeaseStore}.swift`, `Sources/PatchedPrivilegedHelper/ActivationDispatcher.swift`, `Sources/PatchedHelperProtocol/ActivationCapability.swift`, separately named checks and signed proof harness. Parent must reconcile actual helper file ownership with PAT-2607 before assigning the writer, not create competing IPC. Follow the common execution and review contract above; the independent canonical security review floor remains in force.

Proposed `scripts/verify-activation-native.sh` defaults to fixture/refusal checks; real mode requires exact named-target approval, signed caller/helper and explicit disposable Keychain namespaces. No real mode runs in ordinary CI. Red/green operating cases: two simultaneous local users/same account one key/slot; different households isolated; wrong signer/UID/replayed/foreign capability refuses; no arbitrary signing; helper disabled/unapproved/removal/reapproval explains unavailable activation; user removal leaves other household users; wipe/lost key/reinstall/migration; enclave unavailable explicit fallback; permissions/symlink/corrupt broker state refuse; lease sequence and cached blocks remain consistent across users. Real matrix records OS/hardware/signing identity, prompts, key ACL/accessibility, reboot/first-unlock behaviour and safe cleanup. DONE-WHEN: signed native multi-user proof passes on approved targets and the no-broker experience is accepted; no remote hardware-uniqueness claim. UNBLOCKS-WHEN: named-target/key/helper installation permission, signing access and accepted IPC/key custody. Proposed shared store is not verified because Apple docs load or Swift compiles.

## R1: remote service concurrency and restore

After local service/activation gates and PAT-2592 access/approved resource plan, use isolated approved non-customer D1 and fake delivery/provider. Proposed `scripts/verify-licensing-remote.sh` explicitly requires the named isolated environment and refuses live by default. Concurrent code consumes, trial starts, final slot/replace/deactivate, cross-account/shared CAS and forced dependent-write errors must demonstrate actual remote atomicity. Export/restore into a second isolated resource, then replay late events/requests and reconcile: sessions/challenges/leases stay disabled during restore, old snapshot cannot reopen released activations or reset trial markers, provider ledger converges before signing resumes. Preserve/recover high-water revocation/max-grant state from independently verified checkpoint/audit; if unavailable, hold issuance through the latest possible outstanding-grant horizon and require explicit recovery, never silently default revisions. Backup alone is insufficient. Actual resource creation/export/restore/deploy needs its own authority and reviewed path.

DONE-WHEN: request IDs, revisions, result counts, actual deployed source/config revision and redacted remote evidence prove races/rollback/restore without mail/charges. UNBLOCKS-WHEN: accepted runtime source, bindings, isolated targets and deploy authority; reason: emulator tests cannot prove remote runtime or disaster recovery. Existing `patched-licensing-dev` is recorded evidence, not permission to recreate or overwrite it.

## R2: provider sandbox and R3: composition/release

R2 also verifies B0 app/website ownership binding and collision/claim cases in E3/E4, not only payment completion. R2 executes billing E1–E12 only under approved sandbox credential/customer/mutation scope: household GBP/USD annual1999 tax-inclusive/no-provider-trial, actual checkout/totals/receipt, lifecycle/entity read-backs, delivered webhooks/signature retry behaviour, failed renewal, cancel during grace, partial/full refunds/disputes/reversal, renewal-stop independence, portal permissions and reminder ownership. Record sandbox/UI/API/received-mail evidence separately; simulator cannot establish entity lifecycle. No live charge/refund, price creation, email or credential read is authorised by this packet. DONE-WHEN: all applicable E cases evidenced, exact provider schema frozen into fixture tests and independent review accepted. UNBLOCKS-WHEN: suitable new consumer product/category/checkout, account access and explicit sandbox authority; never reuse retired SaaS default links/prices silently.

R3 app composition is last, after a separately scoped real update command and accepted catalogue/helper/self-update interfaces. Proposed `Sources/PatchedClient/UpdateCommand.swift` wraps every NEW third-party manual/scheduled/queued start with fresh licence gate plus independent user consent, app/source/artifact/destination/running-state checks. Re-evaluate at dequeue/start, not only enqueue/disabled button; no grant bypass. Safe transaction completion/recovery is separate and ungated. Independent Sparkle self-update path checks/downloads/applies after trial/paid expiry, with persistent opt-out, network/power policy, safe quiescence and required permission/restart consent. Test expired trial/paid/outage/opted-out, stale queue and known revocation with helper safety states. Actual path is a proposal until installed-update command owner accepts it.

Service deployment is separate from native app release: proposed `.github/workflows/licensing-deploy.yml` only after trust review, scoped identity, protected environment and approved secrets/bindings; no licence Worker can deploy/sign catalogue or native releases. Monitor established workflow and verify deployed revision plus actual behaviour; no manual fallback. Roll back code with forward-compatible schema, never delete revocation/financial ledger; new-sales stop retains webhook/reconciliation/cancel/refund functions. Live acceptance additionally needs justified privacy/disclosure/financial schedule, adequate recovery evidence, live Paddle approval/terms, independent signing/key custody/backup/rotation proof, approved installation targets and real signed app distribution/self-update proof under PAT-941/PAT-7/PAT-2609. Preparation and fixtures do not close release gates.

## Primary references checked for this preparation

On 9 October read [D1 database API](https://developers.cloudflare.com/d1/worker-api/d1-database/) for prepared bindings/batch rollback only, and [Paddle cancellation](https://developer.paddle.com/api-reference/subscriptions/cancel-subscription/) for scheduled cancellation capability only. Apple [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) and [Secure Enclave key guidance](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave) opened but returned JavaScript documentation shells to this tool; no detailed native capability, eligibility or exact ACL behaviour was verified from those responses. Re-read complete current primary docs in N1 before API selection. Official registry endpoints `https://registry.npmjs.org/typescript/latest`, `wrangler/latest`, `vitest/latest` and `@cloudflare/workers-types/latest` returned the T0 candidate versions; this proves package metadata, not compatibility/security or installation. No test/source/runtime fact is inferred from documentation alone.

## Final activation amendment

Integrate [payment activation P1-P3](payment-activation-contract.md) after shared licensing/allocation/billing guards exist. It owns initial paid checkout/claim, limited pending-owner session and website email-code activation, not the old verified-session-only purchase assumption. Joint review must resolve lease/account schema, shared capacity/transfer atomicity and provider sandbox associations before implementation. Existing household management/private support requires verified ownership; active paid access is not required for support requests. Explicit trial and valid private beta are unchanged. Red/green P1 fixtures, P2 pure client gate and separately authorised P3 real sandbox proof remain distinct acceptance evidence.

### PAT-2642 local S1a implementation boundary

The accepted local S1a slice implements only synthetic account challenges,
app/web sessions, exact account/session reauth, historical refresh replay
revocation and one shared audited account CAS writer. The parent observed Phase A
red and froze the unit/D1 checks, migration, route registration and verifier before
releasing implementation. See `service/licensing/README.md` for the explicit
fake controls, strict JSON/clock/entropy bounds, pending-delivery fencing and
mandatory same-nonce transactional dependencies. No productive API exists.
S1b entitlement/trial/lease/retention work remains separate. Emulator checks do
not establish real email ownership, remote D1 atomicity or service readiness;
full parent acceptance, independent review and publication remain required.

The parent accepted the S1a fake entropy-collision exception: request collisions
refuse uniformly with identifier-free 503, retaining the prior challenge and quota
reservation. Normal database/delivery failures still return 202. Two additive D1
cases were independently observed red and re-frozen before releasing the narrow
fix. The parent also accepted `Connection: close` test headers only, preserving
all 29 original assertions and their timeouts/status expectations. See the service
README CHECK-MODIFIED note and retained original ECONNRESET receipts.

### PAT-2643 local S1b implementation boundary

The frozen additive checks/schema register the local explicit trial, exact L1
synthetic producer, deletion marker and protected cleanup slice. The implementation
reuses unchanged S1a authentication/shared CAS and immutable retention policy.
Grant bytes are withheld until audit, dependency and minimal nonce evidence commit;
released lease identity and historical grant maxima remain. Cleanup is bounded,
uses actual S1a/session and trial retry anchors, and holds unknown/financial/protected
histories and unproved S1a request/audit dependencies. Signing requires an explicit
TEST-only header seed verified against the immutable fixture public identity.
No hosted D1, paid ownership, activation allocation, real keys/delivery/provider,
app composition, installation or release is added. Parent acceptance, independent
review and publication remain separate from local verification.

### PAT-2645 B1 local synthetic Phase A, 11 October 2026

Phase A prepares refusing typed billing stubs, independently computed exact
raw/canonical/HMAC fixtures, additive 0003 evidence tables and independent unit
and actual workerd/D1 checks. Parent-observed meaningful red and exact
schema/API/SQL/check/harness freeze precede any implementation release.
The approved local plan supersedes historical provider prerequisites for this
explicitly synthetic proof only. No Paddle compatibility, account association,
paid purchase, entitlement effect, reconciliation or hosted operation is added.
See `service/licensing/README.md` and `Fixtures/Billing/events/README.md`.
`./scripts/verify-billing.sh` is the focused gate; the unchanged native full gate
and service verification remain required. Dedicated D1 setup uses only fixture,
0001 and 0003 migrations; the parked A2/0002 implementation is not imported.

### PAT-2645 B1 local Phase B implementation, 11 October 2026

This later note supersedes the Phase A stub status for the five billing modules
only. The accepted synthetic interface now implements bounded raw-byte HMAC,
strict duplicate/resource/schema refusal, complete canonical event comparison and
atomic append-only inbox/quarantine/audit/receipt storage. Missing explicit fake
composition still refuses. The frozen start and independent final assertions
abort collisions or missing mandatory writes, including RAISE(IGNORE); no
account, entitlement, provider, mail or network effect is introduced.

The second focused gate passed both typechecks, 261 unit and 55 actual local D1
cases. Iteration one is retained: its one remaining failure exposed a test helper
that replaced explicit undefined config with its valid default. CHECK-MODIFIED:
the parent corrected and re-froze only that argument selection, preserving every
case/assertion, after directly proving undefined config refuses with no DB call.
The original unit red had 74 meaningful failures plus this helper defect.
Two of the maximum five iterations were used. Parent full verification, full-diff
acceptance, independent review and publication remain required; the unchanged
synthetic/provider/remote/privacy/financial/release boundaries above still apply.

### PAT-2646 B23 local Phase B source, 12 October 2026

The released source bodies implement validated closed lifecycle inputs, paid
period/grace/financial derivation, durable reconcile claims, exact request replay,
once-only renewal-stop dispatch and reviewed chargeback remainder restoration.
Private account-fenced batches assert every required final row, record canonical
request/manifest receipts and reserve bounded completion capacity. Source-owned
snapshots feed existing issuers without changing A2/S1b signing or granting-only
maximum semantics; native summaries remain identifier-free display data.

Targeted unit, native and actual local D1 checks are retained in the parent
evidence directory, including failed and diagnostic invocations. They do not
replace the parent-owned official gate, full-diff acceptance, independent review
or required portable/native CI jobs. Two official rounds had been used at source handback. Round three then exposed
positive-setup defects, and rounds four and five passed after the documented corrections.
Five of five official rounds are consumed; none remains. The selected frozen-check
prerequisite corrections are parent-owned evidence, not source authority to
weaken checks. Default and missing/mixed synthetic composition refuse. No real
provider/payment/mail operation, production key/store, app launch, installation,
hosting, deployment or customer release is included.


CHECK-MODIFIED PAT-2646, parent prerequisite corrections, 12 October 2026.
The parent retained every official output and corrected four check files only
where direct evidence contradicted their positive setup. Expired non-grant
issuance preserves a NULL maximum; provider-log checks use per-case deltas;
B1 positive envelopes use the existing closed detail shape; cancellation uses
the fresh descriptor revision. Round three additionally exposed a bridge DB
handle captured before runtime restart and a two-row assumption against a
literal one-period B fixture. Dependencies now use the restarted binding and
the full-loss case uses that one literal period. All mandatory fault stages,
exact rollback, lease/grace, sequence, signing and maximum assertions remain.
The one-period case does not prove two touching B components; a separate actual
source probe passed with both touching B periods refunded and the original
A grace anchor and previously issued maximum preserved. Source, parser, fixture and DDL
contracts are unchanged by these corrections. No skipped cases or cap reset:
five of five official attempts are consumed; none remains. These corrections
are finding candidates for the independent review, not review exemptions.

The corrected B full-loss setup also explicitly seeds the existing mapped B
subscription's unclaimed reconciliation queue and uses a disjoint increasing
synthetic nonce stream. The original fixture has only A's queue, and each new
fake dependency instance restarts its entropy counter. No source-created claim,
result, receipt or history is fabricated by this setup. The twelve bridge
rollback cases and corrected one-component full-loss case pass focused checks;
these focused results are supplemental. The subsequent fourth and fifth official attempts
passed all 440 unit, 55 existing billing D1, 289 new D1 and 155 licensing cases
with no failures or skips. Actual-source receipt probes also independently
recomputed all twelve commit manifests and both request hashes. Full project
gates, fresh whole-diff independent review and required portable/native CI remain acceptance gates.


CHECK-MODIFIED PAT-2646, private bridge scheduling repair, 12 October 2026.
Two macOS CI runs failed with read ECONNRESET before different large host D1
batches. An actual pinned-runtime control reproduced stale private connection
reuse after synchronous host blockage; an explicit event-loop yield cleared
expired sockets before the identical atomic batch. The test-owned lifecycle
harness now awaits setImmediate after complete statement preparation and before
one original batch call. All four lifecycle check files, transaction sizes,
SQL, bindings, ordering and rollback assertions are unchanged by this repair.
No retry, split transaction, skip or cap reset is added. The repaired control
committed all 1024 rows, and the final fifth official gate passed. Historical CI
socket timing was not instrumented; new exact-head and exact-main CI are required.
