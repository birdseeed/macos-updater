# Licence support contract: operator authorisation, lookup, support actions and recovery (PAT-2590)

**Latest owner-policy refresh, 9 October 2026.** Launch targets macOS 15+ on Apple silicon, subject to named compatibility proof; the source snapshot's macOS 13 deployment target is implementation history, not launch coverage. Downloading/dragging Patched into Applications, local scan, public signed-catalogue fetch/matching and honest update viewing require no household account or activation before first sign-in. Valid beta, trial or paid access is required at each new third-party installation start. The explicit trial requires verified email sign-in. A securely bound app-originated purchase automatically activates only the purchasing Mac after authoritative payment confirmation, without a separate verified-email-first step. Website purchases use a purchase-email one-time code plus confirmed entitlement and installation proof, without a licence key. Verified ownership remains required for more Macs, recovery, sensitive account actions and private support requests; checkout email is not verified ownership and never authorises merging with or accessing an existing household. Sign-in and purchase alone never start a trial. The proposed [payment activation contract](payment-activation-contract.md) now defines the pending-owner and protected claim design; joint technical acceptance/provider proof remains open under billing section 5. Patched self-updates remain independent. Optional helper approval, App Management consent and ordinary route permissions are separate; none grants the other or installer trust. Current source/build targets were not changed by this refresh.

**Reconciled source, 9 October 2026 (PAT-2605).** Existing-source statements below refer to `33c23cd9bf04df04c28aec59a5a52aa8495f19d6` (`HEAD` and `origin/main` matched in this isolated worktree). Owner decisions come from the complete 9 October issue snapshots for PAT-2587/2588/2589/2590/2592 and the later PAT-2605/2606/2607/2608/2609 decisions. These supersede earlier proposal gates. This remains a proposed technical contract, not implementation or release evidence. [Implementation briefs](licensing-implementation-plan.md) own dependency order, commands and proof boundaries.

**Status: PROPOSED technical contract. Not accepted, not implemented, not cc-ready.** This is a docs-only preparation stage. No implementation was built, tested, deployed, provisioned or purchased for this contract, and no message or provider mutation was made. Document checks and the parent’s separate read-only observations are stated below. The leaf runs that wrote and repaired this document made no provider, sandbox or account observation; the parent's separate, limited read-only observations are quoted in section 8 and gate H11 and prove no capability. The settled owner policies below are recorded policy, not authority to act. The parent owns architecture judgement, acceptance and publication.

Labels:

- **[OWNER]** a policy Andy recorded on PAT-2590 on 8 October 2026, or in the 7 October commercial ruling. Not open for redesign here.
- **[PROPOSED]** a technical default, new path or recommendation of this document. It does not exist yet and is not owner policy.
- **[EXISTS]** a fact read from this worktree at `main` `3ce6e268abd28a42b54620a98370debe8c85a6e3`.
- **[GATE]** an unresolved decision or readiness condition, collected in section 14.

Companion contracts, all **UNACCEPTED** proposals:

- `docs/licensing-contract.md` (PAT-2587), merged here as a proposal. "L§n" points into it.
- `docs/device-allocation-contract.md` (PAT-2588), published through PR #8 and merged to `main` at `82d308fb574dfdc67e05c7816ba3f8c46bab9dc3`. "D§n" points into it.
- `docs/billing-lifecycle-contract.md` (PAT-2589), prepared for PR #9 at commit `c0a85ae8b2ffa0e5fa378ecf7818c6643b0f0186`. The parent verified PR #9 merged at `17d266b1a09c7521cac1ade8a410b68808df8c37`, successful PR/main CI and its byte-identical published file. "B§n" points into it.

**Current source.** The reconciled baseline is recorded above and in licensing section 1. Earlier drafting SHAs and quoted historical test counts are provenance only; current source includes read-only client and catalogue operator prototypes. No native launch, real licence interaction or provider lifecycle proof is claimed here.

Naming: a bare "D1" is the Cloudflare database. The device contract's owner policies are written "PAT-2588 policy D5", and the billing contract's decisions "billing gate D2".

## 1. Existing source boundaries [EXISTS]

`Package.swift` contains `PatchedOperator`, `PatchedOperatorApp`, `PatchedClient` and their checks. The existing operator configuration has optional verify/sign/publish closures and no licence authentication/client. `PatchedApp` composes the read-only client. `scripts/verify.sh` includes client and operator gates. No licensing/support/service modules exist. [Licensing section 1](licensing-contract.md#1-existing-source-boundaries-exists) records the exact source snapshot. Support composition is future work and never reuses catalogue signing/publication authority.

## 2. Recorded owner policy [OWNER]

| # | Policy |
| --- | --- |
| S1 | Andy is the only authorised operator initially. More operators or wider permissions need a future explicit decision. Authorisation is enforced on the service, not by hiding consumer UI. |
| S2 | The console defaults to read-only licence lookup. Each change needs explicit confirmation showing the exact customer or activation target and the consequence. |
| S3 | Every support action records operator identity, timestamp, reason, target and verified outcome. Sign-in codes, secrets and payment-card details are never logged. |
| S4 | Permitted actions: confirmed and audited Mac deactivation; rate-limited resend of sign-in emails; reconciliation against authoritative provider state; provider cancellation and refund initiation under the agreed policies. |
| S5 | Resend goes only to the registered account email, uses the ordinary one-time-code controls and never exposes a code to the operator. A resend cannot authenticate the requester or authorise an email change. |
| S6 | No routine paid-entitlement grants, trial resets or device-limit overrides. A failed payment is never overridden on an unverified screenshot or claim. |
| S7 | PAT-2589's cancellation, refund and grace rules apply. A requested provider action is distinguished from its confirmed result; ambiguous or failing outcomes are reconciled without duplicate charges or refunds. |
| S8 | Recovery without the registered email is manually led by Andy and needs independently verified purchase or account evidence plus verification of the new email. Knowledge of the old email, or a receipt screenshot, is insufficient alone. Trial and beta accounts get a separate evidence-based procedure. Access is never transferred automatically when ownership cannot be established. |
| S9 | Recovery audits the exact account and email change and revokes old account sessions. The design must state the effect on existing Mac credentials and cached entitlements rather than assume instant offline removal. Evidence is minimal, with retention rules. Nothing is disclosed to an unverified requester. |
| S10 | Least privilege and minimal customer data. No privileged provider credential in a consumer app, no exposed activation secret, no customer or licence detail in Slack. |

**Future SME boundary review.** Consumer recovery evidence, email-code account workflow and Andy-only operator authorization stay in the consumer support/service boundary. The console uses opaque account/activation/provider targets; it cannot treat a company name or new product mode as authority. Later self-service business roles, admin delegation or recovery need separately accepted evidence, access-control and audit/migration contracts; no enterprise administration or customer-specific assurance workflow is launch scope, and no household data is silently transferred. Reuse pure confirmation/audit mechanics only where their trust assumptions still hold.

## 3. Domain: `PatchedLicenceSupport` [PROPOSED]

A new dependency-free Swift target, isolated from `PatchedCore`, from the proposed `PatchedLicensing`, and from every catalogue key, root and publication type. It holds no key, makes no request and stores nothing.

- **Typed targets.** `AccountTarget` (opaque 32-hex `accountID`, `accountRevision`, `entitlementRevision`), `ActivationTarget` (account, the full `activationID`, slot, `activationRevision`, the recorded cached-lease bounds), `ProviderTarget` (account, provider subscription and transaction references, the transaction's own interval and the current interval), `RecoveryTarget` (account, `caseID`, case digest). No target is built from an email or a display name.
- **Closed action set.** `deactivateActivation`, `resendSignInCode`, `reconcileProviderState`, `initiateCancellation`, `initiateRefund`, `changeAccountEmail` (recovery only). There is no case for a grant, trial reset, slot-limit change, paid-period edit, key or lease minting, or hold clearing, so no caller can express one.
- **Prepared confirmation.** `SupportConfirmation` holds the server's exact descriptor bytes (section 7), parses them under the closed schema and recomputes the digest over those same bytes. Every value shown to the operator comes from those bytes and from compiled-in words keyed by closed codes. It reads nothing else, so what is confirmed is what is committed.
- **Client.** `SupportClient` is a protocol. The ordinary default `RefusingSupportClient` refuses every lookup and action with `notConfigured`. Fixture clients exist only in the check target. No provider key, service secret or endpoint is compiled in.
- **Presentation.** `SupportPresentation` is a pure display model: masked email, opaque identifiers, entitlement facts, slots, provider references, operation history, and mutation buttons that are disabled unless a prepared confirmation is held.

## 4. Operator authorisation [PROPOSED]

**Rules, independent of provider.**

- Operator identity is an opaque `operatorID` in a server-side allowlist. It is unrelated to consumer email sign-in: no consumer session, account, cookie or one-time code can obtain or be upgraded to an operator role, and the consumer account page has no operator tab.
- No string comparison of an email grants the role. The service accepts a caller only when a cryptographically validated identity assertion matches an explicit deployment allowlist entry on **both** its stable subject identifier and its email, for an audience dedicated to operator use.
- Every operator route validates the assertion on every call: signature against the issuer's published keys, exact issuer, exact operator audience, expiry and not-before. Forwarded identity headers that are not the signed assertion are ignored. A request reaching the Worker by a path that bypasses the identity layer fails the same validation.
- The retiring portal JWT, tenant model and hosts are not reused.
- The client never chooses authority: the operator is taken from the validated assertion, and the account in a commit is taken from the prepared server record, not from the request.

**Candidate provider: an existing Cloudflare Access identity.** Proposed only if all of the following are verified against the real account: that an Access application can front the operator routes; the issuer, audience tag, signing keys and token lifetime it actually presents; that the token carries a stable subject and email for Andy's identity; and that secrets and bindings can be scoped to the operator Worker. None of this is verified, and the Cloudflare account's current bindings are unknown to this run. If it cannot be verified, **no operator authentication is implemented** and the operator routes stay unreachable; no substitute is improvised [GATE H1].

**Native sign-in.** The proposal is a system-browser flow with PKCE, `state` and `nonce`, or a device-code flow, ending in a short-lived token scoped to the operator audience. Whether the provider supports either for a native app is **not verified**, and no custom protocol is claimed to be supported. The token is not assumed non-exportable. A Keychain adapter is gated on separately approved real key and item creation. Until then only a fixture fake exists; no real single sign-on is configured [GATE H2].

**Sensitive actions [PROPOSED].** Operator sessions are limited to 8 hours. A commit additionally requires **fresh human authentication evidence**:

- The evidence is a provider-supported, signature-verified statement that the operator personally completed an interactive authentication between zero and 600 seconds before the commit, by the service clock; future authentication times refuse.
- It is bound to the same allowlisted subject, to the same operator session that prepared the request, and to the purpose of a sensitive support action. Evidence for another subject, session or purpose refuses.
- **An assertion's `iat` is not this evidence.** A provider can issue or refresh a token from an existing session with no person present, so a recent issue time, a refreshed or re-issued token, a client-reported time and a local timer all prove nothing and are never accepted. This contract does not claim that any token refresh qualifies.
- Whether the candidate provider can supply such evidence at all (a verifiable authentication time, a forced re-authentication, or an equivalent) is **unverified**. Until it is shown against the real account, the commit route refuses every request and only read-only lookup can be considered. No substitute is improvised [GATE H1].
- The audit records the verified authentication time and the evidence type, never the token.

## 5. Read-only lookup [PROPOSED]

Initial app-purchase activation is distinct from verified household ownership (billing section 5). A checkout contact email, restricted purchase credential or matching receipt address must never authenticate a support requester, trigger auto-merge, reveal an existing household or authorise email change. Website activation requires verified purchase-email possession plus confirmed entitlement/device linkage. The accepted initial seamless paid experience does not weaken recovery S8/S9; pending purchase ownership and exceptional lost-installation recovery need the unresolved binding contract. Private app-support requests are catalogue support, require verified household sign-in and no paid gate, and do not confer operator authority.

- **Exact identifier only.** `POST /v1/operator/lookup` takes one of: an opaque `accountID`; an exact email, normalised by the PAT-2587 rule; or an exact provider reference resolved only through the server-stored mapping PAT-2589 defines. No prefix, wildcard, autocomplete, listing, export or search by name. The identifier travels in the body, never the URL.
- **Bounded and audited.** Proposed limits are 30 lookups per hour and 200 per day per operator. An audit event is written before any data is returned; if it cannot be written, nothing is returned. The event stores a keyed HMAC of an email identifier, never the address.
- **Returned view.** `accountID`; masked email (first character of the local part, `***`, `@`, the domain); authoritative service-ledger state, `paidThrough`, trial start and expiry, grace deadline, beta flag and `entitlementRevision`; `accountRevision`; each occupied slot with its number, full opaque `activationID`, state, `activationRevision`, last successful refresh and the recorded bounds of its last granting lease (section 7); provider subscription and latest transaction references, status and any scheduled change; any PAT-2589 hold; open support operations; the last bounded refusal reasons recorded for sign-in, activation and refresh, for diagnosis.
- **Never returned.** Codes, challenge identifiers, session or refresh tokens or their digests, device keys, lease bytes, raw provider or webhook payloads, card or billing-address data. The user-chosen Mac label is untrusted text: shown here escaped and inserted as text, never as markup, never logged, and never part of a confirmation (section 7).
- **Unauthorised callers** get one identical refusal whether or not the identifier exists.
- **Requester trust is separate from operator trust.** The operator may read this view for diagnosis under the operator role. Nothing from it, including whether an account exists, is told to a requester who has not signed in to that account or passed section 10. The operator asks the customer for the exact identifier and never offers candidates.

## 6. Permitted actions [PROPOSED mechanics for OWNER S4 to S7]

| Action | Target | Service effect | Limits and consequence shown |
| --- | --- | --- | --- |
| `deactivateActivation` | One active activation of the looked-up account, named by its full `activationID` | The release of D§6: state `released`, slot row deleted, `activationRevision` advanced, in the section 7 batch. Creates no device credential and activates nothing. | The recorded `permittedUntil` of that Mac's last granting lease, shown as an exact time: new update starts may continue until its next successful licence check or that time, whichever is first (PAT-2588 policy D5). An update underway finishes or recovers. The customer may activate again within five slots, with no wait. |
| `resendSignInCode` | The account's registered email | Re-issues a code for the customer's own live pending challenge under the ordinary limits (see below). | No code, challenge identifier or delivery content reaches the operator. Not exactly-once: a repeat may send a second email within the limits. Proves nothing about the requester. |
| `reconcileProviderState` | One account's provider subscription | Marks the subject for B§7 reconciliation, which reads the provider with the service's own credentials. Entitlement changes come only from that rule code; the operator supplies no value. | States that entitlement may rise or fall to match the provider. |
| `initiateCancellation` | One subscription | Requests cancellation effective at the next billing period. `paidThrough` is preserved by the service's own period row (B§8). | Requested is not confirmed. Immediate cancellation is not offered. Access continues to the displayed `paidThrough`. |
| `initiateRefund` | One qualifying transaction and its own paid interval | Records **two separate intents** in one commit: a full refund of the first purchase within the 30-day policy, and the renewal stop that billing policy B5 requires after an approved full refund (section 8). | Eligibility is shown as facts; Andy decides, the service does not auto-approve. Both consequences are shown before confirmation: that interval's access ends only when the provider's approval is read, and future renewal is stopped as a separately confirmed outcome. |

Not available by any route: paid grant, trial reset or extension, slot-limit change, paid-period edit, lease or key minting, clearing a PAT-2589 hold outside its recorded rule, partial refunds, dispute handling, changing the provider's billing identity, activating a Mac on a customer's behalf.

**Operator deactivation is a shared proposed interface.** D§6's deactivate statement is written for the owner: it requires the customer session's `RECENT` guard and records `release_reason = 'ownerDeactivated'`. The operator path needs the same statement and invariants with the section 7 guards in place of the customer session and a distinct `operatorDeactivated` reason. D§6 and the implementation plan now require that operator variant under the same shared guard; its local/remote proof remains H3.

**Resend mechanics.** Under PAT-2587 a code is bound to a challenge the customer's own client holds, and a new request invalidates earlier challenges. An operator-created challenge would therefore be unusable by the customer and would cancel theirs. The proposal is that resend conditionally replaces the stored code digest of the account's live, unexpired pending challenge, keeping its expiry and attempt count, and counts against the ordinary per-email send limits in the same batch, plus a proposed three operator resends per account per day. With no live challenge it sends nothing and tells the operator to ask the customer to request a code. This matches the shared L§9 resend proposal; conditional challenge replacement, limits, expiry/attempt preservation and delivery-outcome handling still require local/runtime proof [GATE H4].

**Provider-side exceptions.** Statutory refunds outside the 30-day policy, partial refunds, disputes and chargebacks are Andy's responsibility, handled directly with the provider under billing gates D1 to D4, never through this console. Afterwards `reconcileProviderState` brings the service into line, including any hold B§8 places. The console never clears a hold.

## 7. Prepare, confirm, commit [PROPOSED]

The SQL conditions below are a contract of state, in the manner of D§6 and B§7. They are not executable code and have not been run.

**Prepare** (`POST /v1/operator/actions/prepare`). In one statement set on the D1 primary the service reads the exact target and its current revisions, checks the action is permitted for that state, builds the descriptor and stores it as a one-use request. Prepare changes no licence state and makes no provider call.

**Descriptor bytes.** A strict UTF-8 JSON object of at most 4,096 bytes with no BOM, no NUL, no insignificant whitespace and nesting depth at most 5 (including the root, recovery target, activation array, each activation object and its cached-lease object). It holds exactly the fields below, in this order. The schema is closed: an unknown, missing, duplicate (including escaped spellings) or reordered field refuses, as do trailing bytes. Integers follow the L§4 integer rule and every string has a fixed bound. The service creates these bytes once, stores them and never reserialises them. The client parses and displays those received bytes and nothing else.

| Field | Content |
| --- | --- |
| `schemaVersion`, `requestID`, `nonce` | `1`; opaque 32 hexadecimal characters; canonical base64 of 32 random bytes. |
| `operatorID`, `action` | The preparing operator; one value of the closed action set. |
| `accountID`, `accountRevision`, `entitlementRevision` | The exact account and its revisions as read. `accountRevision` is the shared account revision of B§7. |
| `maskedEmail` | The exact masked string of section 5, as it will be shown. Never the clear address. |
| `target` | A closed object per action, carrying full opaque identifiers, never a suffix. Deactivation: `activationID`, `slot`, `activationRevision`, `createdAt`, `lastRefreshAt` and `cachedLease`. Cancellation and reconciliation: the provider subscription reference, the subscription revision, the current interval (`currentPeriodStart`, `currentPeriodEnd`) and `paidThrough`. Refund: those, plus the transaction reference and that transaction's own interval (`periodStart`, `periodEnd`). Resend: empty. Recovery: `caseID`, `caseDigest`, `newMaskedEmail` and one deactivation target for every occupied slot. |
| `evidence` | A closed object per action of boolean check results and opaque evidence references. Refund: `firstPurchase`, `withinThirtyDays`, `noPriorRefundAdjustment`. Recovery: the checks of section 10, each with its reference. Empty where the action has none. |
| `consequences` | An ordered array of closed codes. The words for a code are compiled into the console and take their values only from descriptor fields. |
| `reasonCode`, `reasonNote`, `reasonNoteSHA256` | A closed code; the full note text under the section 9 rules (an empty string where none); and the SHA-256 of the note's UTF-8 bytes, which is what the audit can be matched against. |
| `preparedAt`, `expiresAt` | Service time, and proposed `preparedAt + 300` seconds. |

`cachedLease` is the recorded `state`, `issuedAt`, `permittedUntil` and `hardEnd` of the last granting lease the service signed for that activation, or `null` where it never signed one. These are the actual bounds, not a policy maximum. L§9/D§6 now persist those inputs plus `maxGrantPermittedUntil`, the maximum bound across every issued grant, including lost responses. The confirmation displays both last-grant facts and the maximum outstanding cached-use bound; it never understates an older signed grant by displaying only the newest shorter one. Without that record the service cannot state the bound, and prepare refuses deactivation and recovery rather than display an estimate.

The digest is SHA-256 over `im.patched.support.confirm.v1`, one NUL byte, then the exact descriptor bytes.

**Shared account revision.** B§7 requires every writer that changes an entitlement source for an account to increment one account revision in its own batch. This contract depends on the same revision also covering what a confirmation displays: a change of the account's registered email, and the creation or change of any provider mapping (purchase intent, subscription or transaction to account), must increment it too. This is now the shared L§9/B§7 proposal, with a single guard table. With it, a descriptor's `maskedEmail` and provider target cannot go stale unnoticed: any such change makes the commit `targetChanged`. Activation facts are guarded by `activationRevision`. An unrelated reconciliation commit inside the 300 seconds also spends the request; the operator looks up again.

**Confirm.** The console shows the masked email, the full opaque identifiers, slot, the exact cached-lease bounds or the exact intervals, each evidence fact, each consequence in plain words, the reason code and the full reason note. All of it comes from the descriptor bytes; there is no second lookup, cache or live field between prepare and commit, and the Mac label is not shown because it is not in the descriptor. The reason note is user-typed text: it is escaped for its context and inserted as text, never as markup. A person confirms that exact display. Nothing in this design confirms automatically, and a changed target, revision, evidence fact or reason needs a new prepare.

**Commit** (`POST /v1/operator/actions/commit`, carrying `requestID` and the digest). Before the batch the Worker validates the assertion and the fresh authentication evidence of section 4, then reads the request row: a terminal row with the same operator and digest answers with its stored outcome and the current state, and changes nothing. Otherwise one D1 `batch()` on the primary, with a random `attempt` identifier. No statement relies on the affected-row count of an earlier statement, which SQL in the same batch cannot see and the Worker cannot act on mid-batch; each condition is evaluated against stored rows.

1. **Claim.** Set the request row to `outcome = 'pending'` and `attempt_id = :attempt`, only where it is still `prepared`, unexpired, prepared by this same `operatorID`, and its stored digest equals the one presented. `CLAIM` below means the row holds this `attempt_id` and `pending`.
2. **Operate.** The one mutating statement, under `CLAIM` and under the live `accountRevision`, `entitlementRevision` and target revision still equalling the descriptor's. It stamps the row it writes with `:attempt`. That stamp is the **effect marker**: for deactivation, `activations.changed_by` as in D§6; for an email change, the guard row's compare-and-swap setting `account_revision + 1` and `commit_nonce = :attempt` as in B§7; for a provider intent, the inserted operation row; for resend, the re-issued challenge row; for reconciliation, the subject's `wanted` increment. Each companion write now carries the shared attempt stamp and account guard; local and remote tests must prove the dependent effects.
3. **Complete.** `UPDATE ... SET outcome = CASE ... END WHERE CLAIM`. Completion depends on the claim alone, so a false guard is recorded and not left pending. The `CASE` tests, in order: this attempt's effect marker is present, giving `committed`; a revision or state differs from the descriptor, giving `targetChanged`; an explicit `ELSE 'pending'`. A claim alone therefore never yields success, and an operate statement that affected nothing can never be recorded as `committed`.
4. **Depend.** Every further write (slot removal, session revocation, the remaining recovery effects, the single-flight row) runs only where the request row holds this attempt and `committed`. None relies on the presence or absence of some other row.
5. **Audit.** The events are selected from this attempt's completed request row, for `committed` and `targetChanged` alike.
6. **Assert, then read back.** A final statement sets `outcome = NULL` where the row is still `CLAIM`, where `committed` is recorded without each of its dependent rows, or where no audit event for this attempt exists. That violates `NOT NULL`, the statement errors and the whole batch rolls back, the claim included. The last statement reads the request row, and **the response is built only from that row**.

Outcomes. `committed` and `targetChanged` are terminal and spend the request; after `targetChanged` nothing was mutated and the operator looks up again. A claim that matched nothing (expired, already terminal, another operator, another digest) writes nothing and is no success. A batch that errors or rolls back, an audit failure included, leaves the request `prepared` until it expires, and is reported as not done, never as committed. A timeout or ambiguous batch result is reported as unknown and resolved by reading the request row. A repeat from another operator identity or with another digest is refused and never replays the stored result.

Conditioned multi-statement behaviour and rollback on a constraint error are unproven on remote D1, as D§13 and B§7 also record.

## 8. Provider actions and ambiguous outcomes [PROPOSED]

Cancellation and refund cannot be atomic with D1. Commit therefore records only a durable **intent**; a separate dispatch phase calls the provider through the service, with a provider credential limited to the needed permissions and never present in the native app.

| Operation state | Meaning |
| --- | --- |
| `intent` | Committed and audited. No provider call yet. |
| `dispatching` | Durably committed **before** any external call: one conditional transition from `intent`, recording the dispatcher's fence token and the dispatch time. This state is itself the marker that a call may have been made. |
| `refused` | A complete, authenticated provider response definitely rejected it. Nothing changed remotely. |
| `failed` | Definitely not sent, with proof (below). |
| `accepted` | The provider acknowledged it; the effect is pending (for example a refund awaiting approval). |
| `unknown` | The effect may or may not exist. |
| `confirmed` | A later read of the provider's own subscription, transaction or adjustment shows the exact effect, mapped to this account by B§5's stored mapping. |
| `needsOperator` | Unresolved after the proposed 24 hours. Waits for Andy. |

- **Requested is never shown as done.** Only `confirmed` reads as complete, and partial results stay separate.
- **Dispatch once, then only read.** An operation leaves `intent` at most once. A dispatcher that crashes, loses its fence or lets its dispatch lease expire leaves the row in `dispatching`; that row is treated as `unknown` and resolved **only by read-back** of the exact subscription, transaction and adjustments. No dispatcher reclaims such a row to make the remote call, and nothing resends automatically.
- **Local fencing does not cancel a call.** The fence stops a superseded dispatcher from recording a result. It cannot recall a request already in flight, which may still reach the provider and take effect. That is why an expired lease means `unknown` and never `failed`.
- **`failed` needs proof.** It is recorded only where the service holds proof that no request left it: the `dispatching` transition never committed, or a local refusal (configuration or environment mismatch, rate bound) was recorded before any network call. An error, timeout or reset at any point after the call started is `unknown`; no transport error class is assumed to prove non-delivery.
- **A result that cannot be recorded stays unresolved.** If the provider answers but the result write fails or is ambiguous, the operation keeps its durable `dispatching` marker and is handled as `unknown`. It is never completed from memory and never dispatched again.
- **No blind retry.** A provider idempotency mechanism is **unverified**, so none is assumed or invented, and a refund is never re-sent while one may exist. After `needsOperator` nothing escalates or retries by itself; a new attempt is a new prepare and confirmation by Andy after read-back shows no effect.
- **Local single flight.** At most one unresolved operation per account, provider subject and action kind, enforced by a unique condition inside the commit batch. This prevents a local double queue. It does not make the remote call exactly-once, and the console says so.
- **Refusal makes no call.** A refused prepare or commit never reaches the provider.
- **No new charge.** No operator action, dispatch, retry or reconciliation path creates a transaction, a charge or a renewal.
- Dispatch is rate-bounded. Entitlement changes follow only from B§7 reconciliation of confirmed provider state, never from the operator's request.

**Refund with renewal stop [OWNER B5, mechanics PROPOSED].** Billing policy B5 has a provider-confirmed full refund end the refunded paid entitlement **and** stop future renewal, with the two outcomes confirmed independently. A refund is therefore never offered without its renewal stop:

- **One confirmation, two consequences.** The `initiateRefund` descriptor lists both up front, as separate consequence codes with their own targets: the refund of the named transaction, and the renewal stop of its subscription. Where a cancellation is already scheduled or an unresolved cancellation operation exists, the descriptor says so and no second cancellation intent is created.
- **Two intents, independent statuses.** The commit records a `refund` intent and a `renewalStop` intent as separate operations, each with its own state from the table above. Neither state is inferred from the other: refund success is not evidence that renewal stopped.
- **Order.** The refund is dispatched first. The renewal-stop request is the one B§8 makes when reconciliation reads the approved full refund; this intent and B§8's `renewalStop` must be one record, not two requests (shared `billing_renewal_stop`, B§8). If the provider rejects the refund, that refund cause closes as `notRequired`; an independent cancellation/chargeback cause in the shared row is preserved. No refund rejection undoes another authorised renewal stop. A renewal charged while approval is pending is not prevented by this console; whether that can happen is part of E10.
- **Access.** The paid interval is preserved through `intent`, `dispatching`, `accepted`, `unknown` and a `pending_approval` or `rejected` adjustment. Only reconciliation reading the adjustment as an approved refund of the whole transaction ends that transaction's period (B§8). Cancellation alone, requested or confirmed, never shortens `paidThrough`. Unrelated periods and sources are untouched.
- **Overall result.** The refund action is shown complete only when the refund is `confirmed` **and** the renewal stop is `confirmed` by read-back. An approved refund whose renewal stop is missing, `unknown` or `needsOperator` is shown as **incomplete**, with both statuses, and raises the operator alert B§8 requires.

**Provider evidence, stated narrowly.** Provider capability is known from the public documentation the parent read for PAT-2589 (B§3). Separately, the parent observed the authenticated sandbox read-only in a browser on 8 October 2026 (B§13 B). That observation establishes account access and catalogue contents only: the account, shown as Patched Limited, in Test mode; one product with four legacy SaaS prices; and a default payment link of `https://app.patched.im/signup/billing`, the retired SaaS route. No household 19.99 price was visible. Nothing was adopted or changed. **Not verified**: any purchase, renewal, cancellation or refund lifecycle, adjustment read-back, idempotency, webhook delivery, API access, existing keys and credential scopes. No leaf run of this document observed anything [GATE H8].

## 9. Audit [PROPOSED]

- **Events.** `lookup`, `prepare`, `commit`, `providerIntent`, `providerDispatch`, `providerResult`, `readback`, `refusal`, and the recovery events of section 10.
- **Fields.** Event identifier, service time, `operatorID`, the verified authentication time of section 4, action, `accountID`, opaque target identifiers, revisions before and after, descriptor digest, `reasonCode`, an optional reason note with its SHA-256, operation state and verified outcome.
- **Never recorded.** Email addresses in clear, codes, tokens, device keys, card data, raw provider payloads, Mac labels, evidence attachments. An audit event identifies an address only by keyed HMAC. The descriptor's `maskedEmail` stays in the prepared request row and is not copied into audit events.
- **Reason note.** At most 200 UTF-8 bytes of printable text, NFC-normalised, refused if it contains a control character, line break or bidirectional override, `@`, or six or more consecutive digits. This is a cheap guard against pasted addresses and codes, not a guarantee. It is escaped on every output. Refusal records use closed codes only.
- **Fail closed.** A local mutation, its audit events and its outcome are one batch, and the final assertion of section 7 rolls all of it back when the audit event is missing: no audit, no change. A provider intent, and then its `dispatching` marker, are durable before the call. A result that cannot be recorded leaves the operation unresolved, never silently complete.
- Audit rows are append-only to the operator role. Nothing customer-related is sent to Slack; this design sends no notification at all.

## 10. Recovery without access to the registered email [PROPOSED procedure for OWNER S8, S9]

[OWNER] Old-address notice, 72-hour wait, new-email code on the account web page, all-session revocation, all-activation release and preservation of entitlement/trial history were accepted 8 October at 20:15 BST. The evidentiary checks below remain proposals; adequate independent ownership evidence and the exceptional no-device route are unresolved H7.

**Never sufficient, alone or together:** knowing the old email, a receipt or its screenshot, card last four digits, a name, a transaction identifier quoted by the requester, a copied token, or anything publicly knowable. No government identity document is collected as routine.

**Necessary, not sufficient.** Every check below is required, and no set of them establishes who the requester is. Passing all of them yields no acceptance, automatic or presumed: the service only refuses when one is missing. Andy must separately and independently establish that the claimant is the purchaser, or the person he invited, and record that as his own judgement. What evidence is adequate for that link is **not specified here** and stays open [GATE H7]; until Andy decides it, a case with all checks passed is still his to refuse.

**Paid account. All three required:**

1. **Purchase mapping.** Andy independently looks up the purchase at the provider and the service resolves it, through B§5's stored mapping, to this exact account with a live subscription or qualifying transaction. Evidence supplied by the requester only tells Andy where to look. This binds the claim to the right account; it does not show the requester is the purchaser.
2. **Possession.** A currently active activation of that account signs a recovery challenge bound to the case digest with its device key, from a live authenticated app session. A copied token without the device key fails. D§4 now proposes operation `5`, bound to case ID/digest, active activation and live user session; it records possession only and creates no grant. As D§4 states, this proves a key holder signed; it does not prove hardware binding or who is at the keyboard.
3. **New email.** A one-time code sent to the new address, with purpose `email-recovery`, bound to the account, case and case digest, is verified. It creates no session. L§9 now defines the purpose and case/session isolation. It shows control of the new address and nothing about the old account.

**Trial or beta account. All required:** possession as in 2; service history verified from the ledger by the operator (the trial timestamps, or the beta invitation, on that account); for beta, a match with Andy's own independent record of whom he invited; and the new email as in 3. No trial is reset and no account is recreated.

**Stated limit.** A person holding a stolen Mac that is unlocked, signed in and still active passes possession. They can supply a new email address of their own, and the purchase mapping is true of the account whoever asks. So the three checks together can be passed by someone who is not the owner, and they are **not** proof of personal ownership. If no active activation is available (email and Mac both lost), there is **no routine recovery**: the case stays with Andy for further independent verification [GATE H7].

**Case record.** `caseID`, `accountID`, the `accountRevision` and `entitlementRevision` at opening, keyed HMACs of the old and new normalised emails, evidence references with boolean check results (including Andy's recorded ownership judgement and its reference), `operatorID` and `reasonCode`. The case digest is SHA-256 over `im.patched.support.recovery.v1`, one NUL byte and those fields in deterministic order. A new email that already belongs to an account is rejected at case opening and again atomically at commit; accounts are never merged and no alias rule is applied.

**Effects of the confirmed change [PROPOSED].** One batch, through section 7, conditioned on the case digest and the live revisions:

- replace the account email and increment the shared account revision (section 7). `accountID`, the entitlement ledger, `entitlementRevision`, the trial timestamps, any beta invitation and the paid interval are unchanged. No entitlement source is written, so nothing is granted, reset or removed;
- revoke **all** existing sessions of the account [OWNER S9];
- release **all** existing activations and free every slot, each by the D§6 release with its `activationRevision` advanced, so a lost or sold Mac holds no registered slot. No cooldown; the customer activates again, up to five. Releasing every slot is OWNER-settled 8 October;
- write the audit events. The customer's first new session comes only from an ordinary sign-in with the new email after this batch succeeds. The operator's commit mints no customer session, activation, key or lease.

**What an old Mac learns.** Recovery revokes every old session outright, not terminal-only. It may therefore receive an authenticated TLS refusal without a signed `revoked` lease. L§6 persists `verificationBlocked` on that refusal; subsequent outage cannot return to a surviving cached grant. A Mac which has not yet checked can retain only its recorded same-boot cached bound. Ordinary activation release keeps a terminal-only session capable of retrieving a signed denial, as D§9 specifies. No fresh sign-in, payment or optional attestation rebind restores the old released activation ID; explicit reactivation obtains a new ID.

**What is not instant.** A released Mac that stays offline, or cannot reach the service, may keep starting updates on its cached lease until the recorded `permittedUntil` shown in the confirmation, under L§5 (paid up to 30 days and never past `paidThrough`, trial to its expiry, beta the owner-agreed 7 days), and only within the boot that verified it (L§8). The device keys still exist on the old Macs and remain cryptographically valid; nothing can destroy them remotely. They are no longer useful for obtaining any authenticated grant from the service, and they do not extend an offline cache past its bound. A surviving key is never restored automatically. An update underway finishes or recovers.

**Not done.** The provider's customer email and billing identity are not rewritten; that is a separate future action needing its own authority. Nothing is disclosed to the requester before the evidence is complete, including whether the account exists. This phase sends no email, and the parent's PAT-2592 evidence of one basic delivered email is not authority or readiness to send any. OWNER requires a security notice to the old address and at least 72 hours before commit. Proposed `noticeAcceptedAt` starts the wait only after explicit transport acceptance; lost/ambiguous send acknowledgement blocks commit pending evidence, never implies delivery. Bounce, objection or disputed ownership holds the case for Andy. The customer enters the new-email code on the account web origin, never gives it to support; a fresh verification/challenge is required at final commit if earlier proof expired. Notice wording/transport authority and actual received-notice proof remain H6 runtime gates. Changing case email/target/digest voids old proof and notice and restarts a newly approved case; waiting alone never supplies ownership evidence.

**Checklist for Andy.**

1. Take the request through the support mailbox. Ask for the exact account identifier and the new address. Offer no candidates and confirm nothing.
2. Look up read-only. Open a case with a reason code.
3. Paid: find the purchase at the provider yourself; record the mapping check. Trial or beta: record the ledger history check and, for beta, your invitation record.
4. Have the customer complete the possession proof from an active Mac. Record the result.
5. Start the new-address challenge. Confirm it was verified for this case.
6. Independently establish that the claimant is the purchaser or invitee. Steps 3 to 5 do not do this for you. Record your judgement and an evidence reference.
7. If any check is missing or doubtful, or step 6 is not established, refuse with a closed reason and disclose nothing. Record the refusal.
8. Verify the old-email notice acceptance time plus 259,200 seconds has passed, no objection/hold exists, and new-email verification is current. Prepare the change, read the exact display, each Mac's cached-lease bound and the consequences, confirm, then look up again and check sessions, slots and revisions changed as stated.
9. Tell the customer to sign in with the new address and activate each Mac again.

## 11. Data and retention

**Minimal data [PROPOSED].** The support surface adds: the operator allowlist, prepared requests, operations, audit events and recovery cases. It stores references and boolean check results, never a raw receipt, identity document, full card number or attachment.

**No cleanup runs in this scope.** OWNER routine baseline is L§10: 24h challenges/counters, 30d ordinary retries/expired sessions, 90d released Macs, 24 calendar months minimal audit. Additional support-case payload lifetimes below are proposed and require privacy review; they are not a reason to keep a deleted profile.

| Category | Recommended retention |
| --- | --- |
| Prepared, unconsumed requests | Proposed 24 hours from prepare (validity only 300 seconds); strip masked addresses at cleanup |
| Recovery case evidence references | Proposed 30 days from first terminal close; no reset on viewing; ongoing cases require explicit reviewed hold |
| Minimal audit events, including lookups and refusals | OWNER 24 calendar months from immutable event time, restricted and stripped of contact/evidence payloads; provider operation records use billing R7 |
| Operator allowlist entries | While authorised, then kept as audit reference |

## 12. Paths and slices [PROPOSED]

None of these paths exists. Nothing here amends `AGENTS.md`.

**Swift domain, new dependency-free target `PatchedLicenceSupport`:**

- `Sources/PatchedLicenceSupport/SupportTarget.swift`, `SupportAction.swift`, `SupportConfirmation.swift`, `SupportClient.swift`, `RecoveryCase.swift`, `SupportPresentation.swift`
- `Tests/PatchedLicenceSupportChecks/` (`main.swift` and case files), the only place fixture clients and fixture identities exist
- `Fixtures/LicenceSupport/README.md`, `Fixtures/LicenceSupport/vectors/*.json`: descriptor and case digest vectors
- `scripts/verify-licence-support.sh`: `swift build`, then `swift run --skip-build patched-licence-support-checks`
- `Package.swift` (existing file): add the library, target and check executable. `scripts/verify.sh` (existing file): append the script only once the target exists.

**Native surface, separate target `PatchedLicenceSupportUI`** (depends on `PatchedLicenceSupport` only): `Sources/PatchedLicenceSupportUI/LicenceSupportController.swift`, `LicenceSupportView.swift`, `LicenceSupportViewText.swift`; `Tests/PatchedLicenceSupportUIChecks/`; `scripts/verify-licence-support-ui.sh` running `patched-licence-support-ui-checks`, painting offscreen beneath `.build`.

**Composition after the pure support/UI gates.** The support controller and view are a standalone child placed beside `OperatorView` in `Sources/PatchedOperatorApp/PatchedOperatorApp.swift` behind a toolbar switch. `OperatorController`, `OperatorConfiguration`, the catalogue root, trust, signing and publication code are not extended or overloaded.

**Service, inside PAT-2587's proposed `service/licensing/`** (itself gated): `src/operator/auth.ts`, `lookup.ts`, `prepare.ts`, `actions.ts`, `recovery.ts`, `audit.ts`; `migrations/0004_support.sql` (after PAT-2588's proposed `0002_activations.sql` and PAT-2589's proposed `0003_billing.sql`, as those texts number them); `tests/operator/` with fixtures, run by PAT-2587's proposed `scripts/verify-service.sh`. Routes: `POST /v1/operator/lookup`, `POST /v1/operator/actions/prepare`, `POST /v1/operator/actions/commit`, `GET /v1/operator/operations/{operationID}`, `POST /v1/operator/recovery/cases`, `POST /v1/operator/recovery/cases/{caseID}/challenge`. The customer web account page gains no operator route or role.

| Slice | Content | May start after acceptance without live resources? |
| --- | --- | --- |
| **P1** | The six domain sources, checks, vectors, script, `Package.swift` and `verify.sh` additions. Fixture only. | **Yes.** |
| **P2** | `PatchedLicenceSupportUI` with painted checks: read-only default, masked display, confirmation words. | Yes, after P1. |
| **P3** | Service operator routes and migration `0004`, with fakes for identity and provider. | Yes after local companions/contract acceptance; real auth, recovery mutation, provider dispatch and live data remain behind H1/H6/H7/H8/H10/H11. |
| **P4** | Native operator sign-in adapter and token storage. | No. Needs H1 and H2. |
| **P5** | Composition into the operator app; real identity wrapper and provisioning. | No. Last, after companion/interface acceptance and every applicable native/runtime gate above. |

Every logic diff needs red-then-green evidence and an independent full-diff correctness/security review under the canonical policy. A blocked review is not a pass. Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required.

## 13. Acceptance checks [PROPOSED]

Proposed support checks are not written or run; `scripts/verify.sh` exists, while new support commands do not. Each case must first be shown failing against a stub or the reintroduced defect.

| Area | Exact case | Slice |
| --- | --- | --- |
| Default | `RefusingSupportClient` refuses every lookup and action. The painted default view is read-only with every mutation disabled. | P1, P2 |
| Closed actions | No value of the action type expresses a paid grant, trial reset, slot-limit override, period edit or hold clear; the service refuses unknown actions. | P1, P3 |
| Descriptor | Digest vectors match byte for byte. Any changed, reordered, duplicated, unknown or missing field, whitespace, a descriptor of 4,097 bytes, an expired descriptor or a foreign `operatorID` fails. Every displayed value, including masked email, evidence facts, full identifiers, lease bounds, intervals and the reason note, comes from the descriptor bytes; a note containing markup renders as text. | P1, P2 |
| Authorisation | No assertion; consumer session; valid assertion for a subject not on the allowlist; right email with wrong subject; bad signature, issuer, audience, expiry; spoofed identity headers: all refused identically, with no lookup result and no provider call. | P3 |
| Fresh authentication | Commit with no evidence; evidence older than 600 seconds; evidence for another subject, session or purpose; a recent `iat` alone; a refreshed token: all refused with no mutation and the request unspent. | P3 |
| Lookup | Prefix, wildcard and empty identifiers refuse. Unknown and known identifiers are indistinguishable to an unauthorised caller. Rate limits hold. A failed audit write returns no data. | P3 |
| Wrong target | Commit naming another account's activation; target or revision changed between prepare and commit; registered email or provider mapping changed between prepare and commit; re-authentication as another operator between prepare and commit: no mutation. | P3 |
| One use | Expired confirmation; replayed nonce; parallel commits of one request yield exactly one mutation; same-digest repeat returns the stored outcome; different-digest repeat is refused. | P3 |
| Effect marker | A claimed request whose operate statement affects nothing is recorded `targetChanged`, never `committed`. A `committed` outcome without its dependent rows, or an unmatched `CASE`, rolls the batch back with the claim. No row is left `pending`. The response equals the read-back row. | P1 (model), P3 |
| Deactivation | Frees exactly the named slot, mints no device credential, and races correctly with a customer taking the final slot. Where the released Mac can still refresh, it receives a non-granting `revoked` lease; where it cannot, it is refused with no grant. Cached use stays within the displayed `permittedUntil`. With no recorded lease bounds, prepare refuses. In-flight recovery is not gated. | P3, with PAT-2588 |
| Audit | An injected audit failure, and an audit insert that writes no row, each roll back the mutation and the claim. Every action has intent, outcome, operator, time, reason and target. No clear code, token, email, label or card data in any support audit, diagnostic log or retained evidence fixture. Ordinary authentication tables keep only their separately specified opaque challenge identifiers and keyed digests. | P3 |
| Resend | Only the registered address; ordinary and operator limits enforced; no clear code or challenge identifier in any operator response or support audit record; a resend never yields a session or an email change; no live challenge sends nothing. | P3, with PAT-2587 |
| Provider dispatch | Refused commit makes no provider call. `dispatching` is committed before the fake provider is called. Dispatcher crash after sending, expired lease, lost response and failed result write each end as `unknown`, are resolved by read-back and never call the provider again. `failed` is recorded only when no call was started. A fenced-out dispatcher's late call is still found by read-back. Two refund commits for one transaction queue once. No path creates a charge. | P3, with PAT-2589 |
| Refund and renewal stop | The confirmation lists both consequences. Refund `accepted` or `pending_approval` leaves the interval and `paidThrough` unchanged. Refund approved with renewal stop unconfirmed shows both statuses, reads incomplete and alerts. Refund rejected closes only that refund cause; independent cancellation/chargeback causes remain. If no other cause requires renewal stop, the shared row becomes `notRequired` without a call. Cancellation alone keeps `paidThrough`. An existing scheduled cancellation creates no second intent. | P3, with PAT-2589 |
| Purchase/contact isolation | Same checkout email, restricted purchasing-Mac credential and provider-confirmed payment alone cannot access an existing household, private requests or recovery. Verified household session plus bound evidence is required; no operator claim/code exposure or auto-merge. | P1 model/P3, with billing R8 |
| Recovery | Refused for: screenshot alone; old email alone; device proof alone on a paid account; copied token without the device key; new-address code with the wrong purpose, case or digest; purchase mapped to a different account; new address already owned; all three checks passed with the operator's ownership judgement absent. | P3 |
| Recovery effects | After commit every old session is revoked, every activation released and all slots free, activation revisions and the account revision advanced, `accountID`, `entitlementRevision`, trial, beta and paid interval unchanged, no session minted by the commit, old-address notice accepted at least 259,200 seconds earlier, current new-email proof and sufficient independent evidence required. An old Mac's refresh is refused as an invalid session with no grant; signing in afresh does not restore the released activation; cached leases are bounded as displayed and an auth refusal then outage never restores a blocked cache. | P3 |

Fixture and emulator passes are not remote proof. Real D1 concurrency, the real identity provider and the real provider sandbox are separate evidence under the gates below.

**Checks for this reconciliation:** current existing paths and source snapshot read, proposed paths distinguished, and `git diff --check` (result in parent acceptance record). Historical document checks are not a fresh runtime run. No app test, build or launch.

## 14. Gates

This is a proposed contract. Parameters such as limits, lifetimes and file layout are parent and review decisions. A decided gate unblocks its named path; routine later steps already covered by standing authority need no further approval.

| Gate | Blocker | Recommendation and why | Unblocks |
| --- | --- | --- | --- |
| **H1** Operator identity and fresh authentication | Cloudflare Access suitability, issuer, audience, subject and scoping are unverified; account bindings unknown. Whether the provider can supply verified evidence of a human authentication within 600 seconds, bound to subject, session and purpose, is unverified; assertion `iat` and token refresh do not count. | Verify read-only against the real account before any design depends on it. If identity is unsuitable, implement no operator authentication rather than a weaker one. If fresh-authentication evidence cannot be shown, no commit route is enabled; there is no substitute. | P3, P4 |
| **H2** Native sign-in and storage | Provider support for a native browser or device flow is unverified; Keychain item creation is unauthorised. | Keep fakes until a supported path is shown; approve Keychain use as its own scope. | P4 |
| **H3** Companion contracts and interface requests | PAT-2587, PAT-2588 and PAT-2589 (both published as proposals) are unaccepted; the catalogue operator target exists at the recorded source; historical run counts are not current native operating evidence and do not implement support. These contracts now share concrete proposals for: the shared account revision covering email and provider-mapping changes; recorded bounds of each activation's last granting lease; an operator release reason and attempt stamps; a recovery possession operation and an `email-recovery` purpose; and one `renewalStop` record shared with B§8. Native/API proof is still required; no second guard or dispatcher may be introduced. | Re-check every interface here against the accepted texts before P3, and settle the requests with those contracts rather than working around them. | P3, P5 |
| **H4** Resend mechanics | L§9 and section 6 now define the same resend proposal; no implementation or runtime proof exists. | Prove conditional replacement preserves challenge expiry/attempt count, ordinary/operator ceilings and code secrecy; this keeps the customer-held challenge usable without exposing a code to support. | Resend in P3 after local tests; actual sending additionally needs approved transport/content and runtime evidence. |
| **H5** Recovery checks and effects | Owner settled all-session revocation and all-slot release, preserving entitlement/trial history; adequate evidence is H7. | Accept section 10's proposed necessary checks without treating them as sufficient evidence. Releasing removes a lost Mac's registered slot; the cost is re-activating each Mac, and an offline Mac retains its bounded cache until learning a denial, which latches a local verification block. | Recovery in P3 |
| **H6** Recovery notices and code entry | Notice to old address, 72-hour wait and customer web code entry are OWNER-settled. Wording, binding and runtime evidence remain missing. Sending needs its own authority. | Notify the old address and wait 72 hours before commit; have the customer enter the code on the account web origin, never read it to support. Cost: slower recovery and one small web route. | Recovery in P3 |
| **H7** Ownership evidence and unresolved recovery | The required checks do not establish that the claimant is the purchaser or invitee, and what evidence is adequate for that link is unspecified. Also: email and every active Mac lost. | No automatic acceptance and no routine path. Andy establishes the link independently in each case, records it, and may refuse; define adequate evidence before recovery is offered. No new category of personal data is collected by default. | Recovery in P3; runbook completeness |
| **H8** Provider capability | The parent's read-only sandbox observation covers access and catalogue only (section 8): Test mode, legacy SaaS prices, the retired default link, no household 19.99 price. Cancel, refund, adjustment read-back, renewal after refund, idempotency, API access and least-privilege credential scopes are unverified. | Verify in the sandbox with a fixture customer under PAT-2589's evidence run (E5, E10, E11) before P3 dispatch is accepted. | Provider actions in P3 |
| **H9** Manual overrides and wider refunds | Partial refunds, disputes, statutory cases and hold clearing are open in PAT-2589. | Build no override path. An exception is a recorded owner decision handled at the provider, then reconciled. This keeps S6 enforceable in code. | Runbook; no code |
| **H10** Retention | Routine baseline is OWNER-settled; additional recovery payload lifetime and privacy/financial review remain unresolved. | Use L§10 exact clocks and review only the added support categories and exceptions. | P3 going live |
| **H11** Service, secrets, readiness | Service placement and toolchain, the HMAC and provider secrets, and Cloudflare readiness (PAT-2592) are PAT-2587's G4, G6 and G7. PAT-2592 now records the development D1 database `patched-licensing-dev` (EU), Workers Paid Active, `notify.patched.im` sending Enabled/configured, and the one owner-confirmed basic email delivery. These are the setup task’s recorded observations, not a licence-service deployment or proof of application bindings, signing keys, backup/restore or runtime integration. Latest PAT-2592 snapshot records sending reads restored; subscription API error 10000 still leaves actual bills/usage unverified. This documentation performed no account API read. Do not recreate the recorded database or repeat setup owned by that active task. | Follow those gates; create nothing here. | P3 deploy |

**Live use** additionally needs all three companion contracts accepted, PAT-2583 merged, explicit authority for native credentials and keys, actual Paddle sandbox evidence and live approval, legal terms, approved public copy, the £500 cap respected and the independent review passed. This document authorises none of it.

**Fixture-only subset that can be scoped once this contract is accepted:** P1, then P2. Neither needs a service, identity provider, provider account, key, credential, network request, installation or app launch.

## Final paid-activation owner reconciliation, 9 October 2026

[Payment activation contract](payment-activation-contract.md) supersedes blanket verified-email-before-paid-access/session-only checkout assumptions: securely bound app-originated purchase grants only the purchasing Mac after authoritative confirmation and unique guarded claim/slot allocation. Pending purchase ownership is distinct from verified household control; checkout email never finds/merges/reveals an account. Website purchase uses an expiring one-time email code plus confirmed payment, installation possession and ordinary guarded household/cap checks, without licence-key copy. Trial/beta, source/refund/revocation, shared-Mac/session isolation and exceptional-recovery controls remain. Support requests require verified household sign-in, no active paid entitlement. Existing management routes still require verified sessions; the new restricted purchase session cannot operate them. Proposed P1-P3 paths/tests and pending-owner schema compatibility need joint review before code; none is implemented.
