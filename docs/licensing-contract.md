# Licensing contract: account, entitlement, cached lease and sign-in (PAT-2587)

**Latest owner-policy refresh, 9 October 2026.** Launch targets macOS 15+ on Apple silicon, subject to named compatibility proof; the source snapshot's macOS 13 deployment target is implementation history, not launch coverage. Downloading/dragging Patched into Applications, local scan, public signed-catalogue fetch/matching and honest update viewing require no household account or activation before first sign-in. Valid beta, trial or paid access is required at each new third-party installation start. The explicit trial requires verified email sign-in. A securely bound app-originated purchase automatically activates only the purchasing Mac after authoritative payment confirmation, without a separate verified-email-first step. Website purchases use a purchase-email one-time code plus confirmed entitlement and installation proof, without a licence key. Verified ownership remains required for more Macs, recovery, sensitive account actions and private support requests; checkout email is not verified ownership and never authorises merging with or accessing an existing household. Sign-in and purchase alone never start a trial. The proposed [payment activation contract](payment-activation-contract.md) now defines the pending-owner and protected claim design; joint technical acceptance/provider proof remains open under billing section 5. Patched self-updates remain independent. Optional helper approval, App Management consent and ordinary route permissions are separate; none grants the other or installer trust. Current source/build targets were not changed by this refresh.

**Reconciled source, 9 October 2026 (PAT-2605).** Existing-source statements below refer to `33c23cd9bf04df04c28aec59a5a52aa8495f19d6` (`HEAD` and `origin/main` matched in this isolated worktree). Owner decisions come from the complete 9 October issue snapshots for PAT-2587/2588/2589/2590/2592 and the later PAT-2605/2606/2607/2608/2609 decisions. These supersede earlier proposal gates. This remains a proposed technical contract, not implementation or release evidence. [Implementation briefs](licensing-implementation-plan.md) own dependency order, commands and proof boundaries.

**Status: PROPOSED technical contract. Not accepted, not implemented, not cc-ready.** This is a docs-only preparation stage. Nothing was built, run, tested, deployed, provisioned, purchased or sent to produce it, and no test result is claimed. The parent owns architecture judgement, acceptance and publication.

Owner decisions G1 (beta lease and notice) and G2 (trial during beta), recorded on PAT-2587 on 8 October 2026 at 19:58 BST, are reconciled throughout as [OWNER] O11 and O12. Further 9 October owner decisions settle repository placement, routine retention and the fixed trial-used marker. Technical acceptance, privacy/financial review and runtime/release evidence remain open.

Labels used throughout:

- **[OWNER]** a policy Andy recorded on PAT-2587 or PAT-2589 on 8–9 October 2026, or in the 7 October commercial ruling. Not open for redesign here.
- **[PROPOSED]** a technical default or new path recommended by this document. It is a parent decision, not owner policy, and does not exist yet.
- **[EXISTS]** a fact read from this worktree at `main` `33c23cd9bf04df04c28aec59a5a52aa8495f19d6`.
- **[GATE]** an unresolved owner decision or readiness condition, collected in section 13.

Scope of this contract: account identity, sign-in, sessions, entitlement states, the signed lease, the local cache, time, and the boundary to updates. Companion contracts own the rest: Mac slot allocation and the device key (PAT-2588), Paddle purchase and billing events (PAT-2589), operator lookup and support actions (PAT-2590). Where this document names something they own, it states only the interface this contract needs.

## 1. Existing source boundaries [EXISTS]

At `33c23cd9bf04df04c28aec59a5a52aa8495f19d6`, `Package.swift` declares dependency-free Swift 6/macOS 13+ proof, client and operator targets, but no licensing, activation, support or service target. macOS 13 is the recorded source build target only; accepted launch policy is macOS 15+ Apple silicon and remains subject to operating proof. `Sources/PatchedApp/PatchedApp.swift` composes `PatchedClient.ClientController` and `ClientView`: explicit read-only inspection of one chosen local DMG and compiled Firefox pin, not discovery or installation. `Sources/PatchedOperator/OperatorController.swift` has optional verify/sign/publish closures and a refusing default; it has no licence client or operator authentication. `UpdateTransaction.perform` and `recover` in `Sources/PatchedCore/UpdateTransaction.swift` refuse by default; fixture authority stays separate. `CatalogueVerifier.swift` uses CryptoKit and `StrictJSON.swift` is internal to PatchedCore.

The existing full gate `scripts/verify.sh` builds and chains reference, artifact, core, transaction, UI, client-flow and operator checks. There is no `service/` directory or proposed licence check script. No test/build was run for these documentation changes. The real third-party install command is still a separate scope; a licence may never enable the existing fixture authority.

## 2. Recorded owner policy [OWNER]

| # | Policy |
| --- | --- |
| O1 | Household control uses passwordless verified-email one-time codes; one household owns its subscription and slots. Secure app-originated confirmed purchase auto-activates the purchasing Mac without email-first sign-in. Website purchase activation uses a purchase-email code plus confirmed entitlement and device proof. Neither flow uses a customer-held licence key; checkout contact email never grants existing-household access. |
| O2 | The 14-day full trial starts only on an explicit Start trial action after verified sign-in. Once per account, shared across its Macs, stored authoritatively on the service. No reset on reinstall. No card, no subscription, no automatic conversion. |
| O3 | Private beta is separate: specific invited verified email accounts, unlimited in total duration until Andy ends it with at least seven days' advance notice (O11). Beta never consumes the trial; at beta end a participant may start the unused trial or purchase. |
| O4 | Five active Mac slots apply to beta, trial and paid. PAT-2588 is the authority for allocation. |
| O5 | Paid outage allowance: a valid cached lease may be used until `min(last successful licence check + 30 days, paidThrough)`. A known revocation is never an outage. |
| O6 | Failed-renewal grace exists only when the service confirms a failed annual renewal. Its deadline is fixed at the original `paidThrough + 7 days`. Retries never reset it. Cancellation, refund and revocation do not qualify. Cached grace is bounded by `min(last successful licence check + 30 days, grace deadline)`. An offline client must not infer grace. |
| O7 | A trial lease can never outlive the 14-day expiry. The 30-day allowance is not applied to it. |
| O8 | After access expires: viewing, settings and history stay. New manual, scheduled and queued third-party installations are refused. Discovery, signed-catalogue download, local matching and accurate update visibility remain available. Patched self-updates remain available independently under PAT-2609, including after trial/paid expiry, subject to opt-out, trust, timing and permission/restart consent. An update already underway finishes or is safely recovered without a licence. Verification is never weakened. |
| O9 | Hosting is Cloudflare Workers and D1; sign-in email is Cloudflare Email Sending behind a replaceable adapter. This is a design selection, not provisioning, spending or deployment authority. |
| O10 | Offer: GBP 19.99 / USD 19.99 annually, tax-inclusive, five active Macs for one person or household, automatic renewal with reminders and easy cancellation, 30-day first-purchase refund subject to statutory rights and provider rules. |
| O11 | Beta lease and notice (G1, settled 8 October 2026, 19:58 BST). A beta access lease is valid for seven days, is refreshed quietly, and is capped at the scheduled beta end once Andy sets one. This is a renewable verification interval, not a seven-day beta duration. Beta participants get at least seven days' advance notice before access ends. |
| O12 | Trial during beta (G2, settled 8 October 2026, 19:58 BST). Start trial is refused while free beta access is active, which preserves the customer's unused full 14-day trial for after beta ends. Beta never consumes the trial and never converts to paid automatically. |

A direct consequence of O6, stated so it is not mistaken for a defect: a Mac that is offline across `paidThrough` holds no grace lease and stops starting updates at `paidThrough`, up to seven days before a Mac that refreshed. Likewise a Mac that stays offline holds a beta lease for at most seven days after its last successful check, or less if a scheduled beta end falls sooner; it then stops starting updates until a refresh succeeds.

## 3. Entitlement model

**Authority [PROPOSED].** The licence service's entitlement ledger in D1 is the only source of access. The app never creates access from a display state, a checkout redirect, a local setting or the wall clock. The ledger records each source separately: account and activation revocation, paid subscription, confirmed failed-renewal grace, the explicit trial timestamps, and beta invitation. Recording a source does not by itself make the UI grant anything; only a verified lease evaluated by the gate does.

**Strength.** Account revocation and activation revocation override every grant source. Otherwise select the first currently granting source in proposed order `paid`, `grace`, `beta`, `trial`, as defined in the billing contract. Full refund/chargeback removes only its paid period, never unrelated sources. This shared proposal closes the former G5 interface gap; provider evidence remains separate. The app is unaffected by that choice because it consumes one signed `state`.

**Signed states [PROPOSED].** A lease carries exactly one of: `beta`, `trial`, `paid`, `grace` (granting) or `none`, `expired`, `revoked` (non-granting). Any change to an entitlement source increments the account's `entitlementRevision`.

**App status [PROPOSED]**, derived from the lease, the local clock state and the last refresh outcome:

| Status | Meaning | New third-party installation start | Action offered |
| --- | --- | --- | --- |
| `signedOut` | Anonymous viewing; no account/session or activation needed for discovery/catalogue matching. | Refused | Choose verified sign-in for explicit trial, website-paid activation or household actions; app purchase uses secure confirmed-payment activation |
| `noEntitlement` | Verified `none`. | Refused | Start trial (if unused), or buy |
| `beta`, `trial`, `paid`, `grace` | Verified granting lease, `effectiveNow < permittedUntil`. | Allowed | `grace`: update payment. `trial`: buy. `beta`: buy; Start trial is not offered while beta is active [OWNER O12] |
| `cachedDuringOutage` | Same as above, still within the boot identity that verified the lease (section 8), but the last refresh hit an eligible outage (section 6). | Allowed until `permittedUntil` | Quiet retry; warning before the end |
| `expired` | Verified `expired`, or a granting lease whose `permittedUntil` equals `hardEnd` and has passed. | Refused | Buy or renew as appropriate |
| `verificationRequired` | Cached lease passed `permittedUntil` before `hardEnd`; or state missing, corrupt, rolled back or uncertain; or the boot identity changed or is unknown and no fresh verified refresh has succeeded since; or a non-outage refresh failure. | Refused | Check again, or sign in |
| `revoked` | Verified `revoked` or a held revocation marker. | Refused | Contact support |
| `slotUnavailable` | This Mac has no active activation. Owned by PAT-2588. | Refused | Manage Macs |

Discovery/checking, catalogue download, local matching, accurate update visibility, settings and history are account-free before first sign-in and remain available after entitlement expiry [OWNER, PAT-2605 9 October]. Display freshness/unknown state honestly; a cached or invalid catalogue cannot claim current confirmed availability. Inventory, versions, paths and usage remain local and must not enter licence payloads, URLs, logs or analytics. Vendor updaters keep their own settings. Patched self-update check/download/apply uses independent release trust, never this licence gate; revoked/malicious credential and withdrawn-release policy is not newly settled by that expiry exception. The warning thresholds before cached access ends are [PROPOSED] seven days and one day remaining. A beta lease lasts at most seven days, so for beta the seven-day threshold would fire at issue and only the one-day threshold applies; beta-end notice (at least seven days, O11) is communicated separately from lease warnings.

**Anonymous entry and transition [OWNER, proposed UI/API shape].** Entry opens local scan/update list without calling licence/auth endpoints or generating a device key. Public read-only catalogue bytes and the newly supported-apps feed cannot require a household session. On a third-party Install action, offer verified email sign-in then explicit Start trial (if available), valid private-beta access, or app-originated purchase with securely bound automatic activation after confirmed payment under [payment activation](payment-activation-contract.md). Website-purchase activation instead requires the purchase-email code and confirmed entitlement/device binding. Do not start the trial on app install, anonymous scan or successful code entry. Revalidate local version, candidate freshness, exact native/universal eligibility, user consent, permission and entitlement at the eventual new-install boundary; stale anonymous scan results grant nothing. Private support-request submission/tracking requires verified email sign-in, with no paid-entitlement gate and no automatic trial start. It must not become a scan wall.

**Future SME boundary review [OWNER constraint, proposed separation].** Consumer household account/session, five-slot allocation, beta/trial and commercial policy live in PatchedLicensing/service policy modules, not catalogue verification, local discovery, transaction/recovery or helper trust code. Keep opaque owner/account/activation IDs and explicit caller authorization separate from email and product UI. A later self-service small-business offer could add organisation membership/roles, managed settings and business entitlement adapters at these boundaries, after separate requirements, migration/privacy and trust review. Consumer release and installed proof come first. No current tenants, remote inventory/commands, enterprise billing, speculative policy framework, fork or automatic household migration. Account schema and ownership/session semantics may still require later migration; do not promise zero rework or treat business mode as installer authority.

## 4. Signed lease [PROPOSED]

**Signed bytes.** The Ed25519 message is the UTF-8 bytes of `im.patched.licence.v1`, one NUL byte, then the exact decoded payload bytes. This domain differs from the catalogue domain, so a signature made for one can never verify as the other even if a key were wrongly shared.

**Envelope.** A strict UTF-8 JSON object with exactly `keyID` (string), `payload` (standard padded base64) and `signature` (standard padded base64 of 64 bytes). Maximum envelope 16 KiB, maximum decoded payload 8 KiB, maximum nesting depth 4. Refuse BOMs, NUL bytes, other encodings, malformed JSON, duplicate decoded keys including escaped spellings, trailing non-whitespace bytes, unknown fields and non-canonical base64. `keyID` only selects among explicitly configured keys; an unconfigured `keyID` refuses.

**Payload schema 1.** A strict object with exactly the required fields, plus exactly the one evidence object its `state` requires and no other:

| Field | Rule |
| --- | --- |
| `schemaVersion` | Integer `1`. |
| `issuer`, `audience` | Exact configured strings. Proposed `im.patched.licence` and `im.patched.mac`. |
| `accountID`, `activationID` | Opaque identifiers, exactly 32 lowercase hexadecimal characters. Never an email. |
| `deviceKeySHA256` | 64 lowercase hexadecimal characters: SHA-256 of the activation public key bytes. Key type, storage and possession proof are PAT-2588. |
| `state` | One of the seven states in section 3. |
| `entitlementRevision`, `activationRevision` | Positive integers. Never decrease for an account or activation. |
| `sequence` | Positive integer, strictly increasing per activation for each newly issued lease. |
| `issuedAt` | Service Unix seconds when issued. This is the "last successful licence check" of O5 and O6. |
| `permittedUntil` | Exclusive deadline for new update starts under this lease. |
| `hardEnd` | The authoritative end of the present source that no refresh of that source can exceed. |
| `paid` | Required when `state` is `paid`: exactly `{ "paidThrough" }`. |
| `grace` | Required when `state` is `grace`: exactly `{ "paidThrough", "graceDeadline" }`. |
| `trial` | Required when `state` is `trial`: exactly `{ "startedAt", "expiresAt" }`, the service's authoritative trial timestamps. |

Integers are unsigned decimal tokens without sign, fraction, exponent or leading zero, in the range 0 through 9,007,199,254,740,991 (`maximumExactSecond`). Every time, including each evidence time, is within that range, and every sum the client forms is checked integer arithmetic that refuses on exceeding it: no wrapping and no floating point. Booleans, floats and numeric strings are refused. Strings are bounded printable ASCII. For granting states `issuedAt < permittedUntil <= hardEnd`; for non-granting states `permittedUntil` and `hardEnd` both equal `issuedAt`. No email, name, payment, receipt or hardware data appears in a lease. `paid`, `grace` and `trial` each require their own evidence object and forbid the other two. `beta` (which in schema 1 has no evidence object, since the 7-day interval is fixed by O11 and the scheduled end is applied by the service as a cap on `permittedUntil`) and the three non-granting states forbid all three.

**Producer.** Deterministic bytes: fields in the table order above, with the single evidence object, when present, last and its members in the order shown; no insignificant whitespace, no escapes. The same input must give byte-identical payload and signature from the Swift fixture producer and the Worker.

**Consumer order.** Bound the size, strictly decode the envelope, select the configured key, decode base64, verify the signature over the exact payload bytes, and only then decode the payload. The payload is never reserialised for verification. After decoding: schema, issuer and audience; expected account, activation and device key hash for this Mac; field invariants; policy bounds re-derived locally (section 5); replay state (section 7); then time (section 8). Any failure refuses with a named reason and grants nothing.

**Keys.** Licence signing keys are independent of catalogue keys and of any release signing identity. The app holds verification keys only. `PatchedLicensing` exposes trust as an explicit value; the ordinary default has no keys and refuses every lease. There is no key discovery, download or provisioning path. Deterministic fixture private keys live only in test targets and are derived from unmistakable fixture bytes. Passing fixture verification grants no production trust. Real key generation, custody, rotation and the compiled key set are [GATE G6].

## 5. Lease bounds by state

All values are Unix seconds. 30 days is 2,592,000; 14 days is 1,209,600; 7 days is 604,800.

| State | `hardEnd` | `permittedUntil` | Authority |
| --- | --- | --- | --- |
| `paid` | `paidThrough` | `min(issuedAt + 30 days, paidThrough)` | [OWNER O5] |
| `grace` | `graceDeadline`, which must equal `paidThrough + 7 days` exactly | `min(issuedAt + 30 days, graceDeadline)` | [OWNER O6] |
| `trial` | `trial.expiresAt`, which must equal `trial.startedAt + 14 days` exactly | `trial.expiresAt`. Never extended by the 30-day rule. | [OWNER O7]; the choice to run the lease to expiry rather than shorter is [PROPOSED] |
| `beta` | Equal to `permittedUntil` in schema 1 | `min(issuedAt + 7 days, scheduled beta end)`; the cap applies once a scheduled end is set | [OWNER O11]; the encoding in schema 1 is [PROPOSED] |

The client re-checks these bounds itself and refuses a lease that exceeds them: a paid or grace lease longer than 30 days, a grace deadline that is not `paidThrough + 7 days`, a trial lease that fails the checks below, or a beta lease longer than seven days. A service fault therefore cannot widen cached access beyond policy.

**Beta checks.** A `beta` lease is accepted only when `hardEnd == permittedUntil` and `issuedAt < permittedUntil <= issuedAt + 604,800`, with the sum checked against `maximumExactSecond`. The service sets `permittedUntil` to `issuedAt + 7 days`, or to the scheduled beta end when that is sooner; a shorter value is tolerated, a longer one never. The client cannot see the scheduled end, so it proves only the seven-day bound; applying the scheduled cap is the service's duty, and a lease that ignored it is bounded by seven days regardless. The service must not set a scheduled end less than seven days after the notice to participants. Beta ends for a Mac when the lease is not renewed: the next refresh returns `none` (or another verified state), and an offline Mac stops new starts at `permittedUntil`. Beta does not create or consume trial timestamps.

**Trial checks.** A `trial` lease is accepted only when all of these hold: `expiresAt == startedAt + 1,209,600`; `hardEnd == expiresAt`; `startedAt <= issuedAt < expiresAt`; and `issuedAt < permittedUntil <= expiresAt`. The producer emits `permittedUntil == expiresAt`; a shorter value is tolerated, a longer one never. Without the signed `startedAt` the 14-day end could not be re-derived from a lease issued late in the trial. The pair is trusted only as far as the signature under a configured key: the client can prove the pair is internally consistent and bounds the lease, not that it matches the ledger, which stays the service's authority.

A cached lease is never minted, extended or re-dated locally. Reinstalling, deleting local state or changing the clock can only remove access until the next successful verification.

**Refresh cadence [PROPOSED].** Refresh at launch, then at most once every 24 hours while running, and before a new update start when the lease is older than 24 hours. A failed attempt backs off and never blocks an in-flight transaction.

## 6. Refresh outcomes: outage versus everything else

Only an eligible outage may fall back to an existing, still valid cached lease with no persisted `verificationBlocked` or revocation marker [OWNER O5, proposed latch]. Every non-outage failure latches the block across retries/restart; only an authenticated, valid newer lease for an active binding clears an ordinary block. A block is not a signed statement of revocation, but prevents auth refusal followed by outage from reviving access. Classification is [PROPOSED]:

| Outcome of the client's own refresh | Class | Effect |
| --- | --- | --- |
| Verified lease with a higher `sequence` | Success | Replace the cache and re-anchor time. |
| No route, DNS failure, connect or read timeout, connection reset after a valid TLS session or before one starts; HTTP 500, 502, 503, 504; HTTP 429 | Eligible outage | Keep using the existing lease until `permittedUntil`, only within the boot identity that verified it (section 8); otherwise `verificationRequired`. Nothing is minted. |
| TLS certificate or hostname validation failure | Not an outage | `verificationRequired`. |
| HTTP 401 or 403, expired or revoked session | Not an outage | Persist `verificationBlocked`; `signedOut` or `verificationRequired`; sign in again and successfully refresh before clearing the block. |
| Malformed body, oversized body, wrong content type, envelope or payload refusal, bad signature, unknown key | Not an outage | `verificationRequired`. The cached lease is not used; persist `verificationBlocked` before returning. |
| Wrong account, activation or device key hash; lower revision or sequence | Not an outage | `verificationRequired`. |
| Verified lease with state `revoked`, `expired` or `none` | Authoritative | Replace the cache and advance replay state atomically. Only `revoked` persists a terminal revocation marker; `expired`/`none` suppress the old grant but can later transition after a valid newer service lease. |

## 7. Local cache and replay state [PROPOSED]

The cache holds the exact envelope bytes of the latest accepted lease, its SHA-256, the highest accepted `entitlementRevision`, `activationRevision` and `sequence`, any revocation marker, the persistent `verificationBlocked` latch, and the time anchor of section 8. It never holds an email or a code. Session tokens are stored separately (section 9).

- A lease is accepted from the network only with a `sequence` above the highest accepted one and revisions not below the highest accepted. A lease read back from disk is accepted only at the equal `sequence` with an identical byte hash.
- Replay state is read and checked **before** any grant is evaluated. Identifier lengths, sizes and times are bounded before use.
- A revocation marker records the revoking revisions and affected account/activation. Released activation IDs are terminal and never cleared into granting state: fresh explicit activation obtains a new ID. An account-level policy revocation can be cleared only by a later authorised service decision, never sign-in or billing alone. A subsequent outage cannot resurrect older grants.
- Missing, truncated, corrupt or mismatched state fails closed to `verificationRequired`. It is re-established only by a successful authenticated refresh, never healed silently from defaults.

**Stated limit.** Ordinary same-user storage cannot detect a complete restore of an earlier valid state snapshot, and nothing here resists an owner with administrative control of the OS or a modified client. This contract claims fail-closed behaviour for missing, corrupt and inconsistent state, not tamper-proofing. Whether Keychain placement narrows the restore case is unverified and belongs to slice L2.

## 8. Time [PROPOSED]

Server time is authoritative; the wall clock is only ever a lower bound. `max(wall, serverTime)` alone is insufficient, because a wall clock frozen or set back to the last issue time would stop the lease ageing.

**Anchor.** On accepting a lease from a live refresh the client persists: `issuedAt` as the anchor server time, the monotonic reading at that moment, the boot identity, and the highest wall clock ever observed. The highest observed wall is also persisted at each gate evaluation and periodically while running.

**Effective time within one boot.** `effectiveNow = max(anchorServerTime + monotonicElapsed, wall, highestObservedWall)`. Changing the wall clock backwards has no effect; moving it forwards only shortens access.

**After a changed or unknown boot identity.** The monotonic reading has restarted and the wall clock cannot show how long the Mac was powered off, so elapsed time since the anchor is unknown. No hidden powered-off time is accepted: the cached lease permits no new update start, even when `wall >= highestObservedWall`, until a fresh lease is received from the client's own authenticated refresh over validated TLS and verified. That lease re-anchors. The client attempts this refresh at launch. If it ends in an eligible outage the status is `verificationRequired`: new manual and scheduled starts are refused, while viewing, history, settings and recovery of an in-flight update keep working [OWNER O8]. A wall clock below the highest observed value is additionally a rollback and fails closed the same way.

**Availability trade-off, disclosed.** The O5 and O6 bounds are therefore a technical maximum allowance, not a guarantee of 30 days without trustworthy time. Cached use during an outage is available only within the boot in which the lease was verified, with sleep counted. A Mac restarted during a licence-service outage cannot start new updates until one refresh succeeds. This cost is unavoidable under the no-extension rule: no OS secure-time proof is assumed or fabricated here that could measure powered-off time.

**Other rules.**

- Re-anchoring, and the only way the highest observed wall may be lowered (recovery from a mistakenly advanced clock), happens solely from a lease received in the response to the client's own authenticated refresh over validated TLS. A lease read from disk never re-anchors.
- A newly accepted lease must not have `issuedAt` below the previous anchor server time.
- Missing or corrupt anchor, an unreadable boot identity, a non-finite or out-of-range clock, or a monotonic reading below the anchored one within the same boot identity is uncertainty and fails closed.
- Deadlines are exclusive: `effectiveNow == permittedUntil` is past.
- The concrete monotonic source (it must keep counting during sleep) and the boot identity source are slice L2 decisions and are not verified here. In slice L1 the clock is an injected value.

## 9. Sign-in, sessions and service API [PROPOSED]

Parameters in this section are technical recommendations. They are not owner facts and do not all need owner approval; they need parent acceptance and review.

### Routes

| Route | Auth | Purpose |
| --- | --- | --- |
| `POST /v1/auth/code/request` | None | Create a challenge and, when permitted, send a code. |
| `POST /v1/auth/code/consume` | Challenge | Consume a code; create the account if new; issue a session. |
| `POST /v1/auth/session/refresh` | Refresh token | Rotate session tokens. |
| `POST /v1/auth/logout` | Session | Revoke the session. |
| `POST /v1/trial/start` | Session | Idempotent explicit trial start. |
| `GET /v1/licence` | Session | Account entitlement summary for display. Grants nothing by itself. |
| `POST /v1/activations/{id}/refresh` | Session plus device-key possession (PAT-2588) | Issue the next signed lease for this activation. |

For the verified-email session routes above, the account is always taken from the authenticated session. No route accepts an account identifier from the request as authority. App purchase claim creation/consumption needs a separate installation-bound credential and restricted initial activation authority under billing section 5; it must not impersonate these household sessions. An activation that does not belong to the session's account answers exactly as an unknown one. Activation creation, listing, release and replacement are PAT-2588. Checkout creation and the opaque account link carried through Paddle are PAT-2589; a client redirect or return URL never grants an entitlement. Operator routes are PAT-2590.

All bodies are bounded strict JSON over HTTPS. No code, token or session identifier appears in a URL, a log line, an audit event or an operator view.

### One-time codes

- **Email normalisation, declared exactly.** Trim surrounding ASCII whitespace; require exactly one `@`, at most 254 bytes, ASCII only in schema 1; lowercase ASCII letters in the whole address. No dot removal, no plus-suffix removal, no provider-specific alias rules. Two addresses that differ after this are different accounts. An alias is never treated as proof of owning another account. Refusing non-ASCII addresses is a known limitation to revisit before general release.
- **Code.** Eight decimal digits from a cryptographic random source with rejection sampling so no digit is biased. Expires 10 minutes after creation. Five wrong attempts end the challenge.
- **Send limits.** Per normalised email: 1 per minute, 5 per hour, 20 per day. Per source IP: 30 per hour, 100 per day.
- **Non-enumeration.** Every well-formed request returns the same `202` status and body shape with a fresh random `challengeID`, whether the address is known, unknown, invited, over its per-email limit, or undeliverable. Delivery outcomes and internal errors are never reflected. Only malformed input (`400`) and the per-IP limit (`429`) differ, and neither depends on the address.
- **Storage.** Only `HMAC-SHA-256(serverSecret, "im.patched.otp.v1" || NUL || challengeID || NUL || purpose || NUL || code)` is stored. Comparison is constant time. A code is bound to its challenge and its purpose (`app-sign-in`, `web-sign-in`, `app-reauth`, `web-reauth`, or `email-recovery`). Requesting a new code for the same address and purpose invalidates earlier unconsumed challenges.
- **Consume by purpose.** One primary transactional batch conditionally consumes the unexpired/unexhausted challenge under this attempt and its exact purpose/target binding. Every dependent statement requires that same consume stamp; zero rows never succeeds. `app-sign-in`/`web-sign-in` alone may create an absent verified account and insert the corresponding new session. `app-reauth`/`web-reauth` require the existing live session/account binding and update only that session's `authenticated_at`; they create no account/session or slot. `email-recovery` requires the live case ID/digest/new-address binding and records only the case's current new-email verification timestamp; it creates no account/session, changes no registered email and grants nothing. Wrong, expired, consumed, superseded, exhausted, wrong-purpose and unknown challenges return one identical failure. Audit and the purpose-specific dependent write are required or the batch rolls back.
- **Account creation.** These verified-email routes create an account only by valid sign-in-purpose consume. Requesting a code creates no account or pre-verified record. App-originated purchase may need pending ownership records before email verification; its distinct schema, collision and later verified-household binding remain unresolved in billing section 5. Never mark checkout contact email verified or look up/grant an existing account from it.

The server secret is not provisioned [GATE G6].

### Sessions

**Shared service interfaces.** Migration `0001_accounts.sql` owns one `account_guard(account_id, account_revision, commit_nonce)` used by every account writer. Email/provider mappings, trial/beta/source changes, account revocation and slot/label changes advance `accountRevision` in their own batch. Source changes additionally advance `entitlementRevision`; activation changes advance `activationRevision`. No support/billing module creates a second account guard. CAS uses a unique attempt nonce and every dependent write requires that nonce, not merely the target revision. Missing audit/dependent writes abort the batch. Lease issuance advances the per-activation sequence and records `lastGrantState`, `lastGrantIssuedAt`, `lastGrantPermittedUntil`, `lastGrantHardEnd` and `maxGrantPermittedUntil` atomically with the snapshot inputs; the maximum covers all previously signed grants, including lost responses.

Verified-email household sessions hold nullable `activation_id`, `authenticated_at`, `revoked_at` and `expires_at`. Re-auth codes bind the existing session and update only its authentication time, never allocate a new slot. Ordinary activation release makes bound sessions terminal-only (rotation/logout/challenge/refresh of that activation only). Approved recovery/deletion revokes all sessions outright. Email recovery codes bind account/case/digest/new address, create no session and are entered only by the customer on the account web origin. Operator resend replaces a live challenge's code digest under the same expiry/attempt count and ordinary send ceilings plus three operator resends/account/day; it exposes no code/challenge to support and sends nothing when no live challenge exists.

- Tokens are opaque 256-bit values from a cryptographic random source. The service stores only a keyed HMAC of each.
- **App.** Access token valid 15 minutes; refresh token valid 90 days idle, rotated on every use, revocable. Proposed storage is the login Keychain; the actual Keychain API behaviour is unverified until slice L2.
- **Rotation.** One conditional update consumes the old refresh token. If the response is lost, the retry with the old token is refused and the session is revoked: the user signs in again. The service never leaves two valid refresh tokens for one session. Because an authentication failure is not an outage (section 6), new updates wait for sign-in in that case.
- **Web account page.** A `Secure`, `HttpOnly`, `SameSite=Strict`, host-only cookie with a 12-hour absolute expiry from sign-in, enforced by the service; there is no sliding refresh, so the user signs in again after it. Every authenticated `POST` requires a CSRF token and an exact `Origin` match. No token in a URL or in `localStorage`.
- Logout and revocation take effect on the next request. Already issued leases run to `permittedUntil` unless the entitlement or activation revision changes.

### Trial start

`POST /v1/trial/start` carries a client-generated idempotency key. The service reads its clock once, then issues one conditional statement that sets `trial_started_at` and `trial_ends_at = trial_started_at + 14 days` only where `trial_started_at IS NULL` and no unexpired same-email trial-used marker exists (section 10), in the same transactional batch as the audit event and the idempotency record (account, route, key, request hash, stored response). The same key with the same request hash returns the stored response. The same key with a different hash is refused. A different key after the trial has started returns the existing authoritative timestamps with a not-started-now result, never a second start. Zero rows changed never produces a fresh grant. The decision is not made by reading a row in Worker code and then writing.

**Refused while beta is active [OWNER O12].** The same conditional statement also requires that the account has no active beta source (an invitation that is neither ended nor past its scheduled end), evaluated at the service's single clock reading and in the same statement, not in a prior read. While beta is active the request returns a distinct `trial-unavailable-during-beta` refusal, sets no timestamps, writes no idempotency record that would later replay a start, and leaves the full unused 14 days intact. The client does not offer Start trial while its verified status is `beta`. After beta ends, a Start trial from a verified signed-in account proceeds as above. A trial already running when an invitation is added is not covered by O12 and follows source precedence under G5.

### D1, Workers and email: what the references support

These are API design references checked by the parent on 8 October 2026. They support the design only. Nothing has been deployed or tested remotely, and local emulation is not remote proof.

- [D1 Database API](https://developers.cloudflare.com/d1/worker-api/d1-database/): statements are prepared and bound with parameters; `batch()` runs its statements as a transaction and rolls the sequence back if one fails; reads go to the primary unless the Sessions API is used; `withSession('first-primary')` gives the freshest first read, but a session is not an arbitrary read-modify-write transaction.
- [D1 read replication](https://developers.cloudflare.com/d1/best-practices/read-replication/): replicas can be stale. Licence, sign-in, trial and slot decisions therefore use the primary and conditional SQL, never a replica or cached read followed by a write.
- [Workers Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/): documents standard Ed25519 and ECDSA support, which covers lease signing.
- Partial unique indexes are a candidate mechanism for single-active rows. They have not been tested against remote D1.

**Email.** Sending sits behind an adapter with one operation (recipient, template, parameters) so the provider is replaceable [OWNER O9]. Recorded status on 8 October 2026 (PAT-2592): exactly one basic test email was delivered and Andy confirmed receipt. That verifies basic delivery only. The Worker binding for this application, D1, keys, deployment and production sending eligibility are not verified. Earlier `Unauthorized` readings are stale. This run sent no mail. None of this is plan, bill or spend approval.

## 10. Data, retention and deletion

**[OWNER, 9 October] Routine baseline.** Keep minimal verified email/account/trial/beta/source records while the account exists, opaque activation key/label/state and bounded session/challenge digests. No hardware fingerprint or uploaded installed-app inventory. The trial marker is personal data, not anonymous. Privacy basis/disclosure review remains a launch gate; nothing here runs cleanup or deletes data.

**[PROPOSED] Exact clocks.** Use service UTC Unix seconds for durations. A day is 86,400 seconds. For calendar months, add months to the original UTC timestamp, preserve time-of-day and clamp the day to the target month's last day (29 February + 12 months becomes 28 February). Deadline is exclusive and cleanup is eligible at `now >= deadline`, with checked arithmetic. Retry, access and re-registration never move an original deadline.

| Category | Accepted duration; proposed anchor/minimal treatment |
| --- | --- |
| Challenges and counters | 24h from challenge creation or fixed counter-bucket end; discard digests and source/email HMACs then. A code expires after 10m even while the cleanup row remains. Device challenges use the same 24h cleanup bound. |
| Expired/revoked sessions | 30d from first effective expiry/revocation (earlier event); strip bearer digests then. No refreshing a revoked session. |
| Ordinary API retry/idempotency rows | 30d from terminal result/creation for an abandoned request; no extension on replay. Purging never restores a released activation or repeats a provider mutation. |
| Deactivated Mac records | 90d from terminal release; remove label/public key/history then. Keep only minimal opaque denial/revision/max-grant bounds longer if an outstanding grant or unresolved security case demonstrably needs it; gate any extension beyond the ordinary schedule for privacy review. |
| Minimal security/support audit | 24 calendar months from immutable event time; closed reason, opaque target/operator/revisions/outcome only. Strip direct contact, device labels, tokens and attachments. |
| Active account | While account exists, subject to explicit deletion below. |
| Trial-used marker | Exactly 12 calendar months from original deletion of the trial-used account, keyed HMAC(normalised email) + used flag + fixed deletion/expiry only. No Mac/history/account data. |
| Billing dedup/financial ledger | Separate schedule under billing R7; never use ordinary retry TTL or silently destroy reconciliation state. |

**Account deletion [PROPOSED mechanics].** Authenticate/re-authenticate, explain renewal/payment consequences, obtain the explicit deletion instruction and apply a single guarded batch: revoke all sessions/challenges, release all activations, deny new issuance, erase ordinary email/labels and active account profile, and retain only necessary restricted audit, bounded grant-denial records and separately justified billing records. Deletion is not cancellation or refund: an unresolved renewing subscription blocks completion and is resolved under the provider workflow; never promise financial deletion. No blanket retention of a deleted profile. Account IDs and activation IDs are never reused. Existing offline grants cannot be recalled; their maximum bounds are recorded and no new one is issued. Removing a user's login never deletes other local users' sessions or a shared household slot automatically.

**Trial marker [OWNER, proposed implementation].** On deletion of an account that used a trial, insert the protected email HMAC if no unexpired marker exists. Existing marker expiry wins; re-registration, rejected start or deletion of a re-registered account does not extend it. At expiry delete the marker before evaluating a fresh account's trial eligibility; an existing account's recorded used trial still remains used. After expiry a new same-email account may receive a trial. HMAC key custody/rotation must preserve matching across the remaining retention window without preserving plaintext; lost key/recovery cannot silently grant repeat trials. No marker for an unused trial. Delete ordinary challenge/request references on deletion except narrowly justified denial/audit/billing records.

**Cleanup invariant.** Each deletion query requires its deadline passed AND no unexpired `maxGrantPermittedUntil`, pending provider intent, reconciliation reference or approved hold needs that row. Reduce to a minimal denial/reference row when payload can be removed first. Financial/legal holds need documented purpose, owner, review date and release rule; no indefinite catch-all. Cleanup has dry-run counts and bounded batches, is idempotent, races under the shared guard, and must never erase state needed to refuse a still-valid grant. Restore stays fail-closed until revocation/trial-marker and provider reconciliation horizons are recovered; a database backup is not permission to reissue leases.

## 11. Paths and slices [PROPOSED]

None of these paths exists. Nothing here amends the scope in `AGENTS.md`.

**Swift, new dependency-free target `PatchedLicensing`** (depends on no other target, so catalogue trust stays separate and `PatchedCore` is untouched):

- `Sources/PatchedLicensing/Entitlement.swift`: states, status and typed refusals.
- `Sources/PatchedLicensing/LicenceStrictJSON.swift`: bounded strict parser, internal to this target.
- `Sources/PatchedLicensing/SignedLease.swift`: envelope, exact-byte verification, payload decoding, explicit trust.
- `Sources/PatchedLicensing/LicencePolicy.swift`: section 5 bounds and section 6 classification.
- `Sources/PatchedLicensing/LicenceClock.swift`: section 8 over injected readings.
- `Sources/PatchedLicensing/LicenceGate.swift`: the pure decision for a new manual, scheduled or queued third-party installation start. It has no recovery case, so it cannot refuse recovery.
- `Tests/PatchedLicensingChecks/` (`main.swift` and case files): fixture and security cases, the only place fixture signing keys exist.
- `Fixtures/Licensing/README.md` and `Fixtures/Licensing/vectors/*.json`: golden lease and transition vectors.
- `scripts/verify-licensing.sh`: `swift build`, then `swift run --skip-build patched-licensing-checks`.
- `Package.swift`: add the library, target and check executable. `scripts/verify.sh`: append `./scripts/verify-licensing.sh` after `./scripts/verify-ui.sh`, only once the target exists. All existing acceptance cases remain passing; no historical case count is asserted as a new run.

**Service, proposed placement `service/licensing/` in this same repository.** `AGENTS.md` currently scopes this repository to dependency-free Swift with no toolchain installation. Repository placement is OWNER-settled on 9 October; toolchain/config/workflow and the repository scope amendment remain proposals [GATE G4]. No retired SaaS host or tenant code is reused.

- `service/licensing/package.json`, `tsconfig.json`, `wrangler.toml`
- `service/licensing/src/index.ts`, `auth.ts`, `store.ts`, `entitlements.ts`, `leases.ts`, `email.ts`, `ratelimit.ts`, `audit.ts`
- `service/licensing/migrations/0001_accounts.sql`
- `service/licensing/tests/`
- `scripts/verify-service.sh`: `npm test` plus a type check. It requires a separately accepted toolchain; nothing is installed now.

**Slices, in order.** Every logic diff needs red-then-green evidence and an independent full-diff correctness/security review under the canonical policy. A blocked review is not a pass. Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required.

| Slice | Content | May it start after contract acceptance without live resources? |
| --- | --- | --- |
| **L1** | The six `PatchedLicensing` sources, checks, vectors, `verify-licensing.sh`, the `Package.swift` and `verify.sh` additions. Fixture only: no network, secure store, service, Keychain or app launch. | **Yes.** Needs no D1, mail, keys or credentials. Beta lease cases use the settled 7-day interval (O11). |
| **L2** | Client, session store, cache and activation identity behind injected transport, storage and clock, proven with fakes. | Yes with fakes. Real Keychain use needs its own approved scope. |
| **S1** | Sign-in/trial/service policy and migration `0001`, fake email/keys/store, local D1 checks. | Yes after toolchain/scope acceptance; no remote bindings or real secret. Deployment and operating acceptance need G6/G7 and privacy review. |
| **U1** | A separate licence presentation and view. `UpdateDisplayInput` is not extended. | Yes for painted fixture checks, after L1. |
| **C** | Composition at the product update command. | No. Only after an actual update command is separately scoped. |

`UpdateTransaction.perform` and `recover`, and everything in `Sources/PatchedCore/`, stay unchanged through L1, L2 and U1. Recovery of an in-flight transaction is never passed through the gate, in any slice.

## 12. Acceptance checks [PROPOSED]

None of these has been written or run. Each must be shown failing against a stub or the reintroduced defect before it is accepted as passing.

| Area | Exact case | Slice |
| --- | --- | --- |
| Tamper | One flipped payload byte, flipped signature byte, truncated signature, payload reformatted with the same fields: all refuse before decode. | L1 |
| Domain | A lease signed over `im.patched.catalogue.v1` plus NUL, and one with no domain prefix, refuse. | L1 |
| Strict decode | Duplicate key, escaped-spelling duplicate, unknown field, missing field, BOM, NUL, trailing bytes, oversize, excess depth, float, negative, leading zero, 2^53, boolean for integer, an integer with an exponent. Evidence objects: `trial` state without `trial`, with an extra or missing member, or with `paid` or `grace` as well; a `trial` object on each of the other six states; the same for `paid` and `grace`. All refuse. | L1 |
| Key | Unknown `keyID`, valid signature under a different fixture key, empty default trust: all refuse. | L1 |
| Account and device | Valid lease for another account, another activation, another device key hash: refuse. | L1 |
| Replay | Lower `sequence`; equal `sequence` with different bytes; lower revision; older lease after a higher one was accepted. Equal `sequence` with identical bytes from disk accepts. | L1 |
| Time borders | One second before, at, and after `permittedUntil` for each granting state; at is refused. `issuedAt + 30 days` against `paidThrough` on both sides of the minimum. For `beta`: one second before, at and after `permittedUntil`, and `issuedAt + 7 days` against a scheduled beta end on both sides of the minimum (fixture producer only). | L1 |
| Policy bounds | Paid or grace lease longer than 30 days; grace deadline not `paidThrough + 7 days`; `permittedUntil > hardEnd`: refuse. Beta: `permittedUntil` of `issuedAt + 604,801`, `hardEnd != permittedUntil`, a 30-day beta lease, and a sum exceeding `maximumExactSecond`: each refuses. Exactly `issuedAt + 604,800`, and a shorter capped value, accept. A beta lease carrying `paid`, `grace` or `trial` evidence refuses. | L1 |
| Trial end | A validly signed lease issued on day 13 with a short `permittedUntil` but `hardEnd` (and `expiresAt`) later than `startedAt + 14 days`: refuse. Mismatched pair (`expiresAt` one second either side of `startedAt + 1,209,600`), `hardEnd != expiresAt`, `issuedAt` before `startedAt` or at `expiresAt`, `permittedUntil` past `expiresAt`, and a `startedAt` whose sum exceeds `maximumExactSecond`: each refuses without wrapping. The exact pair with `permittedUntil == expiresAt` accepts. | L1 |
| Grace | Grace only from a `grace` lease. An expired paid lease with no grace lease never yields grace. A later grace lease keeps the same deadline. | L1 |
| Clock rollback | Wall set before the highest observed wall; wall frozen at `issuedAt` while monotonic time passes `permittedUntil`: refuse. | L1 |
| Reboot | New boot identity with `permittedUntil` still ahead and no fresh verified refresh: refuse new starts as `verificationRequired` with wall ahead of, equal to and behind the highest observed wall. An eligible outage after a new boot grants nothing. A fresh verified lease after a new boot re-anchors and allows; the same lease read from disk does not. Same boot across simulated sleep: continues and the slept time counts. Missing, corrupt or unreadable anchor or boot identity: refuse. | L1 |
| Outage versus auth | Each row of section 6 maps to its class. An outage with no cached lease grants nothing. A 401, a bad signature and a TLS failure never use the cache. | L1 (classifier), L2 (fake transport) |
| Known revocation | A verified `revoked` lease suppresses an older lease that is otherwise valid, across restart. An outage after revocation stays revoked. | L1, L2 |
| No local extension | Deleting state, restoring defaults or reinstalling yields `verificationRequired`, never a grant. | L1, L2 |
| Safe expiry and recovery | Expired, revoked and `verificationRequired` refuse new manual and scheduled starts. The gate exposes no recovery decision. The existing transaction recovery cases still pass unchanged with no licence present. | L1, plus the unchanged existing gate |
| Producer vectors | The Swift fixture producer and the Worker producer emit byte-identical payload and signature for every vector in `Fixtures/Licensing/vectors`. Any byte difference fails. | L1 (Swift), S1 (Worker) |
| Challenge consume | Concurrent consumes of one challenge yield exactly one session. Wrong, expired, superseded and exhausted challenges return the identical failure. A sixth attempt fails even with the right code. | S1, on the chosen runtime |
| Trial once | Concurrent starts yield one timestamp pair. Same key replays the stored response. Same key with a different body is refused. A start on a second Mac returns the same timestamps. | S1, on the chosen runtime |
| Trial during beta | With an active beta source, Start trial returns `trial-unavailable-during-beta`, sets no timestamps and stores no replayable start; concurrent beta-activation and trial-start requests never yield both an active beta and a started trial from a refused request. After beta ends the full 14 days start from the later explicit action, and a beta period never shortens or consumes them. A beta lease never contains trial evidence. | S1, on the chosen runtime |
| Non-enumeration | Known, unknown and rate-limited addresses receive the same status and body shape. | S1 |
| Cross-account | A session cannot read or refresh another account's activation, and the answer matches an unknown identifier. | S1 |
| Session rotation | A replayed refresh token is refused and revokes the session; two valid refresh tokens never coexist. | S1 |
| Secrets hygiene | Stored challenge and session rows, logs and audit events contain no code or token. | S1 |

Service checks need both unit tests and D1 integration tests with real concurrency under the actual chosen runtime. A local emulator pass does not prove remote D1 atomicity; the remote proof is part of PAT-2592 readiness and S1 acceptance.

## 13. Gates

This document is a proposed contract. It becomes the basis for implementation only when the parent accepts it. Not every technical parameter above needs owner approval: the code length, limits, token lifetimes, schema bounds and file layout are parent and review decisions. The items below are the ones that genuinely wait on Andy or on readiness. G1 and G2 were settled by Andy on 8 October 2026 and stay listed only as a record of the decision; they no longer block anything. G3 product defaults and G4 repository placement are also settled below; remaining technical/access/release conditions are explicit.

| Gate | Blocker | Recommendation and why | Unblocks |
| --- | --- | --- | --- |
| **G1** Beta lease and notice | **SETTLED [OWNER O11], 8 October 2026.** Nothing outstanding. | Seven-day renewable beta lease, capped at the scheduled beta end once set; at least seven days' advance notice. Not a seven-day total beta duration. | Beta lease vectors in L1; beta issuance in S1 (which still waits on its other gates). |
| **G2** Trial during beta | **SETTLED [OWNER O12], 8 October 2026.** Nothing outstanding. | Start trial is refused while beta is active, preserving the unused 14 days. | Trial start rule in S1 (which still waits on its other gates). |
| **G3** Retention and deletion | Routine retention and fixed trial marker are OWNER-settled 9 October; justified basis/disclosure/privacy review and financial schedule remain open. | Implement exact section 10 clocks in fixtures; obtain privacy/financial review before live collection. | S1 going live; not L1, L2 or U1. |
| **G4** Service placement and toolchain | `AGENTS.md` scopes this repository to dependency-free Swift with no toolchain installation. | Keep the service in this repository under `service/licensing/` so the shared vectors are one source, and amend `AGENTS.md` in the slice that first adds it. | S1 and `verify-service.sh`. |
| **G5** Source precedence, refunds, disputes | Shared precedence is proposed in section 3 and billing section 8. | Accept the shared proposal; provider shape evidence is billing E5/E6/E10, not a blocker to pure derivation fixtures. | S1 entitlement derivation. |
| **G6** Keys and runtime credentials | No licence-scoped signing key, OTP/session secret, application-bound initialized licence database, Worker or runtime binding has been verified/provided for this contract. PAT-2592 records an empty EU development D1 resource; that is not an initialized application binding. This ticket creates none, and nothing is assumed reusable from retired infrastructure or from resources another task may provision. | Scope generation, custody and rotation separately before S1 deploys. L1 needs fixture keys only. | S1 deploy and any live use. |
| **G7** Cloudflare readiness (PAT-2592) | PAT-2592 records Workers Paid active, notify.patched.im configured/enabled, successful email reads, one owner-received test and an empty EU patched-licensing-dev D1. Application binding, remote concurrency/restore and real billing remain unverified; do not recreate setup resources. | Complete the readiness ticket before S1 acceptance. Do not treat emulator results or the single test email as that proof. | S1 acceptance. |
| **G10** Purchase ownership/binding | Automatic initial paid activation and website email-code experience are OWNER-settled; secure pending ownership, installation claim, existing-account collision/reuse, restricted credential and later verified-household linkage are not accepted. | Prepare billing section 5 contract with pure adversarial vectors before changing auth/account/activation SQL; never turn contact email into ownership. | App/website purchase integration; does not block independent L1/L2/P1 fixtures. |
| **G8** Update command boundary | No product update command exists; every public transaction entry refuses. | Scope the update command separately, then compose the gate in front of new starts only. | Slice C. |
| **G9** Device key and Keychain | Keychain behaviour and any hardware-backed key proof are unverified, and the device key is PAT-2588's. | Keep L1 and L2 on injected storage; verify the real APIs in a separately approved scope. | Real storage in L2; activation in PAT-2588. |

**Fixture-only subset that can be scoped once this contract is accepted:** slice L1, then L2 with fakes and U1 painted checks. None of them needs D1, mail, keys, credentials, a network request, an installation or an app launch. Everything else stays behind the gates above. This document authorises none of it.

## Final paid-activation owner reconciliation, 9 October 2026

[Payment activation contract](payment-activation-contract.md) supersedes blanket verified-email-before-paid-access/session-only checkout assumptions: securely bound app-originated purchase grants only the purchasing Mac after authoritative confirmation and unique guarded claim/slot allocation. Pending purchase ownership is distinct from verified household control; checkout email never finds/merges/reveals an account. Website purchase uses an expiring one-time email code plus confirmed payment, installation possession and ordinary guarded household/cap checks, without licence-key copy. Trial/beta, source/refund/revocation, shared-Mac/session isolation and exceptional-recovery controls remain. Support requests require verified household sign-in, no active paid entitlement. Existing management routes still require verified sessions; the new restricted purchase session cannot operate them. Proposed P1-P3 paths/tests and pending-owner schema compatibility need joint review before code; none is implemented.
