# Device allocation contract: Mac slots, activation identity and management (PAT-2588)

**Latest owner-policy refresh, 9 October 2026.** Launch targets macOS 15+ on Apple silicon, subject to named compatibility proof; the source snapshot's macOS 13 deployment target is implementation history, not launch coverage. Downloading/dragging Patched into Applications, local scan, public signed-catalogue fetch/matching and honest update viewing require no household account or activation before first sign-in. Valid beta, trial or paid access is required at each new third-party installation start. The explicit trial requires verified email sign-in. A securely bound app-originated purchase automatically activates only the purchasing Mac after authoritative payment confirmation, without a separate verified-email-first step. Website purchases use a purchase-email one-time code plus confirmed entitlement and installation proof, without a licence key. Verified ownership remains required for more Macs, recovery, sensitive account actions and private support requests; checkout email is not verified ownership and never authorises merging with or accessing an existing household. Sign-in and purchase alone never start a trial. The proposed [payment activation contract](payment-activation-contract.md) now defines the pending-owner and protected claim design; joint technical acceptance/provider proof remains open under billing section 5. Patched self-updates remain independent. Optional helper approval, App Management consent and ordinary route permissions are separate; none grants the other or installer trust. Current source/build targets were not changed by this refresh.

**Reconciled source, 9 October 2026 (PAT-2605).** Existing-source statements below refer to `33c23cd9bf04df04c28aec59a5a52aa8495f19d6` (`HEAD` and `origin/main` matched in this isolated worktree). Owner decisions come from the complete 9 October issue snapshots for PAT-2587/2588/2589/2590/2592 and the later PAT-2605/2606/2607/2608/2609 decisions. These supersede earlier proposal gates. This remains a proposed technical contract, not implementation or release evidence. [Implementation briefs](licensing-implementation-plan.md) own dependency order, commands and proof boundaries.

**Status: PROPOSED technical contract. Not accepted, not implemented, not cc-ready.** This is a docs-only preparation stage. Nothing was built, run, tested, deployed, provisioned, purchased or sent to produce it. No Keychain item, key, credential or device state was read or changed, and no test result is claimed. The parent owns architecture judgement, acceptance and publication.

It is the companion to `docs/licensing-contract.md` (PAT-2587), which is merged as a proposal and is itself **not accepted or implemented**. That document is used here only for its recommended technical shape (routes, sessions, lease, cache, time). Section references written "L§n" point into it. Nothing here treats it as approved product policy.

Labels:

- **[OWNER]** a policy Andy recorded on PAT-2588 on 8–9 October 2026, or in the 7 October commercial ruling. Not open for redesign here.
- **[PROPOSED]** a technical default or new path recommended by this document. A parent decision, not owner policy. It does not exist yet. Every parameter, bound, layout and name introduced here is of this kind unless it carries [OWNER].
- **[EXISTS]** a fact read from this worktree at `33c23cd9bf04df04c28aec59a5a52aa8495f19d6`.
- **[EVIDENCE]** what a named external reference supports, and what it does not.
- **[GATE]** an unresolved decision or readiness condition, collected in section 14.

Scope: slot allocation, the activation key and its proof, attestation binding, listing and owner mutations on both surfaces, revocation against the cached lease, device data and audit. Account identity, sign-in, sessions, the signed lease, the cache and time remain PAT-2587's. Paddle is PAT-2589. Operator actions are PAT-2590.

## 1. Existing source boundaries [EXISTS]

The reconciled source snapshot and current app/operator/gate paths are [licensing section 1](licensing-contract.md#1-existing-source-boundaries-exists). `Package.swift` has no activation or licence module and there is no service directory. The read-only `PatchedClient` and separate catalogue `PatchedOperator` targets exist; the client app is not an inert UpdateView shell. No source implements device Keychain, machine-wide identity or App Attest. The helper proposal was also read at PAT-2607: its `joinHousehold(verifiedMembership, challenge)` and `signDeviceChallenge(challengeEnvelope, purpose)` map to the capability below; licensing owns the signed membership schema and vectors, helper owns OS peer enforcement and private-key custody. This documentation runs no native check and grants no installation authority.

## 2. Recorded owner policy [OWNER]

| # | Policy |
| --- | --- |
| D1 | Five active Macs per household account in paid, trial and private beta alike. One authoritative, concurrency-safe slot limit across all three. |
| D2 | The trial is one shared account-level period. Adding a Mac never starts a new trial. |
| D3 | Customers may remotely deactivate Macs on their own household account, including a lost or unavailable Mac, and immediately activate a replacement. **No transfer cooldown.** Abuse handling must preserve this unless Andy explicitly changes it. |
| D4 | The slot is released atomically, and the limit holds under concurrent activation and deactivation. Retried activation and deactivation are idempotent. |
| D5 | A removed Mac loses update access at its next successful licence check. Previously cached access may continue until its existing allowance expires under PAT-2587. Deactivation therefore caps active registered slots, not necessarily simultaneously usable cached copies during an outage. |
| D6 | A successful check applies revocation and never refreshes the removed activation. An update already underway finishes or is safely recovered. |
| D7 | Management lives in the native app and a small web account page, both on the agreed passwordless email sign-in. Either surface can view and remotely deactivate the household's active Macs. The web page supports recovery when no usable Mac with Patched is available. It is a new minimal consumer surface, not a revival of the retired SaaS portal. |
| D8 | When secure local activation identity survives reinstalling Patched, the existing slot is reused. When it is lost, including after a wipe, the verified account owner explicitly replaces the old entry from the app or the web page. |
| D9 | No hardware fingerprinting. No routine support requirement. Identity is never inferred from a display name alone. Five registered slots remain enforced. OWNER 9 October explicitly accepts cloning of fallback identities by a determined user; possession is not hardware uniqueness. |
| D10 | Cross-customer lookup and changes are refused. An audit trail is recorded without secrets. Device data is minimal. |

## 3. Activation identity and shared Macs

**[OWNER, 9 October]** Prefer hardware-backed keys where available, with an explicit secure-storage fallback for broad compatibility. App Attest is optional and is not an activation prerequisite. The recorded macOS 13+ code target is historical implementation state; accepted launch policy is macOS 15+ on Apple silicon, with named OS/key/helper tests still required. One physical shared Mac on the same household account consumes one slot across macOS logins; different household accounts remain separate. A service cannot prove unique physical Macs from a random identity or signature. Fallback keys can be cloned by a determined user and that limitation is accepted.

**[PROPOSED] Smallest secure design.** Use one narrow machine-wide identity broker, co-hosted as an isolated capability in the optional administrator-approved helper proposed by PAT-2607, rather than a second root daemon or a world-readable private key. One app-generated random machine ID indexes local account bindings only and is never sent as a hardware fingerprint. One P-256 activation key per household binding produces a 65-byte uncompressed X9.63 public key; the lease hash is SHA-256 of those exact bytes. The helper owns a non-synchronising device-only key reference, restrictive root-owned state beneath `/Library/Application Support/Patched/Activation/`, atomic generation and one activation binding per account. Prefer Secure Enclave creation; explicit fallback uses a non-synchronising secure store with restrictive ACL. Real System Keychain ACL/accessibility and enclave support for this architecture require approved-target proof, not an assumed API guarantee.

For verified household joining, each user signs in separately with the household email. Initial app-purchase activation instead needs the restricted installation-bound claim authority described in billing section 5; it cannot issue a household-management session or let another UID join before verified membership. App access/refresh tokens stay in that user's login Keychain; broker never stores, returns or enumerates another user's session. The broker authenticates the actual signed caller and peer audit UID/session, accepts only typed `joinHousehold`, `signDeviceChallenge`, `releaseLocalBinding` and status operations, and has no arbitrary signing/path/command/URL method. For signing, a short-lived service-signed capability binds opaque account, activation/key digest, challenge/action digest, purpose, nonce and expiry. The broker verifies capability and its own account binding; server issues it only to the authenticated user's session and records challenge ownership. Never trust caller-supplied account/UID or a public-key hash as authority. No account names/labels are listed to another UID. Per-user participation receipts are scoped to the caller and are not bearer service sessions.

**Membership/capability bytes [PROPOSED].** Licence service signs domain `im.patched.activation-capability.v1` + NUL + exact strict payload bytes using the separately scoped licence authority; never catalogue/release keys. Envelope follows L§4 bounds/parser/signature rules, but this domain and `audience = im.patched.activation-broker` are mandatory and a capability is never a lease. Closed payload: `schemaVersion` (1), `issuer`, `audience`, opaque `accountID`, nullable `activationID` only for join, `deviceKeySHA256`, `purpose` (`joinHousehold`, `refresh`, `recovery-possession`), `challengeID`, `nonce` (32 bytes base64), `actionSHA256`, `brokerRequestNonce` (32 bytes base64), `issuedAt`, `expiresAt` (at most issue + 300 seconds). Recovery action digest binds case/digest as operation5. No email, UID, app inventory or session token. Broker creates `brokerRequestNonce` for the OS-authenticated peer UID/audit-session and expected key/purpose/action before server issuance; keeps it pending only for that peer, single-use. Service checks the caller's verified household session and active/terminal binding appropriate to purpose before issuing, and stores session/challenge relation; it does not trust a request UID. Broker verifies compiled trust, exact bytes/binding/deadline, its pending nonce and actual current peer, consumes locally atomically before signing. Cross-user forwarded/replayed capabilities and join for a released ID refuse. Client returns the resulting signature to the service, which independently consumes the bound server challenge and checks possession/ownership; broker signatures alone allocate nothing. A terminal-only session gets only a refresh denial capability, never join or recovery. Trust bootstrap/rotation is part of licence custody scope, not network key discovery. Tests include every field mismatch, concurrent nonce consumption and session switching.

Concurrency: the broker serialises creation per household binding; server uniqueness `(account_id, device_key_sha256)` makes simultaneous users reuse the same occupied activation. Lease/replay sequence state is serialised machine-wide per account/activation; each UID receives only its authenticated household's result and maintains its own session. Service refresh records the initiating session, sequence and stored grant bounds. A later sequence accepted by one user prevents another user accepting an older result. Different accounts get different keys/slots and cannot read or act on each other's local binding.

**Helper declined/disabled.** Discovery, catalogue matching, self-updates and account viewing stay available where their separate conditions allow. Explain that secure shared-Mac activation is unavailable until the broker is approved/re-enabled; do not silently create one slot per login or use a globally writable software-key file. Recommendation: use the existing optional helper for this capability, with an explicit product acceptance gate for activation availability without the helper. Reason: no proved supported unprivileged store shares a private identity safely across unrelated local users. This is a proposed limitation, not a new owner decision or authority to install a helper. PAT-2607 must accept the IPC/custody design before native implementation.

Reinstall reuses a surviving broker key and activation; wipe/key loss requires explicit verified-owner replacement, never a display-name match. Removing one local login/session removes only its participation; it does not release the household slot or other users' sessions. Helper disable/removal preserves an explained recovery path; secure local erasure is a separate explicit action and does not automatically cancel remote slots. Migration/copy may duplicate fallback state; service still caps registered keys, not physical machines. Key restoration never restores a released activation ID. No hardware UUID, serial, model, MAC or installed-app inventory is collected.

**Future SME boundary review.** The concrete five-row occupancy constraint is consumer allocation policy in service/licensing, not a constant the reusable installer or key broker interprets as authority. Broker accepts opaque authenticated ownership/membership and purpose-bound requests, never an email/household display label or caller-selected business mode. Later organisation ownership/roles and business allocation would need new accepted service schemas, authorization and explicit migration of ownership/key memberships; no fork, automatic household transfer or enterprise scope is built now. Consumer launch/proof remains priority.

## 4. Requests and possession proof [PROPOSED]

A request is split into an **action**, which is immutable for the life of one customer action, and a **proof envelope**, which is transport and may be renewed. A retry under a fresh challenge therefore never conflicts with the original.

**Body.** Strict UTF-8 JSON, parsed under the L§4 envelope rules: no BOM, NUL, duplicate key (including escaped spellings), unknown or missing field, trailing bytes or non-canonical base64, and nesting depth at most 2. A device-bound route takes exactly `{ "action", "proof" }`. Deactivate and rename take exactly `{ "action" }`.

**Action bytes.** `action` is the standard padded base64 of the action bytes: a strict JSON object of at most 1,024 bytes holding exactly the fields below, in this order, with no insignificant whitespace. The client creates these bytes once and resends them byte-identical on every retry. The service decodes them once, never reserialises them, and defines `request_digest = SHA-256(action bytes)`.

| Operation | Exact action fields |
| --- | --- |
| activate (`1`) | `requestID`, `devicePublicKey`, `displayName` |
| replace (`2`) | `requestID`, `devicePublicKey`, `displayName`, `releaseActivationID`, `expectedRevision` |
| refresh (`3`) | `requestID`, `activationID` |
| rebind (`4`) | `requestID`, `activationID`, `expectedRevision` |
| recovery-possession (`5`) | `requestID`, `activationID`, `caseID`, `caseDigest` |
| deactivate | `requestID`, `activationID`, `expectedRevision` |
| rename | `requestID`, `activationID`, `expectedRevision`, `displayName` |

`requestID` and every `activationID` are exactly 32 lowercase hexadecimal characters. `requestID` is generated once per customer action, so it is part of the signed action. `devicePublicKey` is the canonical base64 of exactly 65 bytes. `expectedRevision` is an integer under the L§4 integer rule. `displayName` follows section 11 and is at most 256 UTF-8 bytes. An `activationID` in the action must equal the one in the path.

**Proof envelope.** Exactly `challengeID` (32 hexadecimal characters), `nonce` (canonical base64 of exactly 32 bytes), `signature` (base64 of exactly 64 bytes) and at most one of `attestation` with `attestKeyID`, or `assertion`. Decoded bounds: attestation 8,192 bytes, assertion 1,024 bytes, key identifier 64 bytes. Nothing in the envelope enters `request_digest`. The challenge's `expiresAt` belongs to the proof, not the action.

**What strict parsing does and does not give.** The bounds and the parser fix the syntax and size of what is accepted and guarantee that the digest covers the exact action bytes received. They say nothing about whether an attestation or assertion is genuine: that comes only from the Apple-specified validation of section 5, which is unbuilt. The attestation and assertion bounds are untested against real objects [GATE H3].

**Challenge.** `POST /v1/device/challenges` returns a `challengeID`, a 32-byte random `nonce` and `expiresAt` (issue time plus 300 seconds). The service stores the account, operation, `deviceKeySHA256`, a keyed digest of the nonce, the expiry and `consumed_by`. A challenge is single use, bound to the session's account and to one operation. The client returns the nonce in the proof envelope. Before rebuilding the signed message, the service recomputes its keyed digest (bound to challenge ID, account and operation) and compares it in constant time with the stored digest. It uses that verified nonce and the stored expiry; a stored digest alone cannot reconstruct the random nonce.

**Signed message.** The concatenation, 164 bytes in total:

| Bytes | Content |
| --- | --- |
| 26 | UTF-8 `im.patched.device-proof.v1` |
| 1 | NUL |
| 1 | Operation code `1` to `5` as in the table above. Any other value refuses. |
| 16 | `accountID` |
| 16 | `activationID`, or sixteen zero bytes for activate and replace, where none exists yet |
| 32 | `deviceKeySHA256` |
| 32 | `nonce` |
| 32 | `request_digest`: SHA-256 of the exact action bytes |
| 8 | `expiresAt` of the challenge, unsigned big-endian Unix seconds |

The signature is ECDSA P-256 with SHA-256, sent as the fixed 64-byte `r || s`. Signature malleability is not relied on for uniqueness: single use comes from the nonce and the request record. The service rebuilds the message from the session's account, the route's operation, the stored challenge and the action bytes it received. It never accepts the account, the operation or the digest as supplied by the client. Recovery operation 5 additionally binds `caseID`/`caseDigest` through the signed action and the service challenge row; it only records possession for that existing case, issues no lease/session and touches no slot. Require a live per-user session, an active occupied activation, and fresh account-bound proof. A mismatch in any field, an expired or consumed challenge, a wrong length or an unknown key refuses with one `proofRefused` answer.

**What this proves, exactly.** The holder of the private key signed this action, for this account and operation, against a challenge issued within five minutes. **It does not prove the key is in a Secure Enclave or bound to any hardware.** A modified client can present a software key and the signature verifies identically. Server-side evidence of hardware binding comes only from section 5, and only where that is available.

## 5. Optional attestation [PROPOSED]

Ordinary household activation requires a verified session, challenge possession and the five-slot guards; initial paid activation instead uses the restricted purchase-installation session and signed provisional-account lease in [payment activation](payment-activation-contract.md), under those same cap/identity guards, using the explicit hardware-preferred or secure-storage-fallback mode. An unsupported, ineligible or unavailable App Attest path never makes launch-compatible activation fail solely for missing attestation. Mode is honest observed adapter/evidence state: a signed claim `hardwarePreferred` alone does not prove hardware binding. Never infer unique physical hardware from ordinary P-256 proof.

App Attest may later strengthen an app-instance signal after current primary Apple documentation, direct Developer ID eligibility, entitlements, real sizes and reset/reinstall behaviour are verified on the actual OS/hardware matrix. No supported-version assertion is made here from the older WWDC note. Keep the optional protocol behind a separate adapter; no existing stored assertion is a mandatory refresh guard until a separately accepted migration/recovery policy proves unavailable/reinstalled paths. Launch can omit it entirely. If enabled, independently validate Apple chain/relying party/nonce/key binding and atomically advance its counter under this request's attempt stamp. Rebind of a live activation is account-authenticated, possession-proved and revision-guarded, never restores a released activation, and grants no additional slot/trial. Malformed supplied evidence is refused; absent optional evidence selects the documented fallback without a false attested label.

## 6. Authoritative schema and algorithms [PROPOSED]

The SQL below is a contract of state and conditions. It is not executable code, has not been run, and its column list is not final. Session column names are PAT-2587's to fix. All decisions use the D1 primary and conditional statements inside one `batch()` (L§9). **No count in Worker code followed by an insert, and no decision from a replica or cached read.**

```sql
-- Occupancy. A row exists only while the slot is held. Five rows per account is the cap.
CREATE TABLE activation_slots (
  account_id        TEXT    NOT NULL,
  slot              INTEGER NOT NULL CHECK (slot BETWEEN 1 AND 5),
  activation_id     TEXT    NOT NULL UNIQUE,
  device_key_sha256 TEXT    NOT NULL,
  changed_by        TEXT    NOT NULL,          -- attempt_id of the batch that wrote the row
  PRIMARY KEY (account_id, slot),
  UNIQUE (account_id, device_key_sha256)
);

-- History. One row per activation, never reused, never returned to 'active'.
CREATE TABLE activations (
  activation_id       TEXT PRIMARY KEY,
  account_id          TEXT    NOT NULL,
  device_key_sha256   TEXT    NOT NULL,
  device_public_key   BLOB    NOT NULL,          -- 65 bytes
  generation          INTEGER NOT NULL,          -- 1 + prior activations of this key in this account
  state               TEXT    NOT NULL CHECK (state IN ('active', 'released')),
  activation_revision INTEGER NOT NULL,
  lease_sequence      INTEGER NOT NULL,
  last_grant_state TEXT, last_grant_issued_at INTEGER, last_grant_permitted_until INTEGER,
  last_grant_hard_end INTEGER, max_grant_permitted_until INTEGER,
  display_name        TEXT    NOT NULL,
  changed_by TEXT NOT NULL, sequence_by TEXT,    -- attempt stamps for state and sequence
  attest_key_id TEXT, attest_public_key BLOB, attest_counter INTEGER, counter_by TEXT,
  created_at INTEGER NOT NULL, last_refresh_at INTEGER, released_at INTEGER, release_reason TEXT
);

-- Idempotency. One row per customer action.
CREATE TABLE device_requests (
  account_id TEXT NOT NULL, operation TEXT NOT NULL, request_id TEXT NOT NULL,
  request_digest TEXT NOT NULL, attempt_id TEXT NOT NULL,
  outcome TEXT NOT NULL,                         -- 'pending' never survives a commit
  result_activation_id TEXT,
  result_sequence INTEGER, result_time INTEGER,  -- terminal lease inputs (section 9)
  result_entitlement_revision INTEGER, result_activation_revision INTEGER,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, operation, request_id)
);
```

The cap and key uniqueness rest on an ordinary primary key and an ordinary unique constraint, not on partial indexes, which L§9 records as untested on remote D1. `activation_id` is globally unique. The public key is unique among **occupied** slots of one account.

**Outcome classes.** *Terminal* outcomes decide the action and are never re-executed: `activated`, `reused`, `limitReached`, `replaced`, `released`, `alreadyReleased`, `renamed`, `rebound`, `leased`, `revokedLease`, `stale`, `notFound`, `notActive`. *Retriable* outcomes record that a guard was false and decide nothing: `reauthRequired`, `proofRefused`, `assertionStale`.

**Before the batch**, in this order, in Worker code:

1. Authenticate the session and derive the account from it. This is never skipped. A dead or foreign session answers as an invalid session and nothing below runs.
2. Bound and strictly parse the body, decode the action bytes and compute `request_digest`.
3. **Replay lookup**, one primary read of `device_requests` for this account, operation and `requestID`. A stored digest that differs answers `requestConflict`. A terminal row with an equal digest answers with the stored outcome and the result activation's **current** state. That answer needs no new challenge, proof or re-authentication, executes no mutation, and mints no key, session or granting lease. Terminal rows are immutable, so this read cannot be overtaken; the claim in step 1 of the batch repeats the decision in SQL.
4. Otherwise (no row, or a retriable row with an equal digest) the request is uncompleted. The Worker checks the proof and any attestation or assertion, which for a retry means a fresh challenge when the original has expired, and runs the batch. These are pure checks plus one primary read of the challenge; a stale read cannot double-spend because every condition is repeated in SQL.

**Guards.** Each is a named SQL condition, evaluated inside the statement that uses it:

- `LIVE`: the session row is unrevoked, unexpired and belongs to `:account`. For a terminal-only session (section 8), additionally the operation is refresh of the activation it is bound to.
- `CLAIM`: the `device_requests` row for this account, operation and `requestID` has `attempt_id = :attempt` (random per batch) and `outcome = 'pending'`.
- `RECENT`: the same session row has `authenticated_at > :now - 600`. Required only by activate, replace, deactivate and rebind. Refresh, rename and listing need `LIVE` only.
- `PROOF`: the challenge row has `consumed_by = :attempt`.
- `ASSERTED`: supplied optional evidence is absent (fallback) or was validated for this request and has `counter_by = :attempt`. A stored optional key alone never forces evidence or blocks terminal refresh.
- `EFFECT`: the row the operation statement writes carries this attempt's stamp (`changed_by`, or `sequence_by` for refresh).
- `DONE(x)`: the request row has `attempt_id = :attempt` and `outcome = x`.

**The batch**, the same eight steps for every mutating route (plus the shared account guard from L§9 for account-affecting writes):

1. **Claim.** Insert the request row as `pending` where `LIVE`. On conflict, take the row over (new `attempt_id`, `pending`) only where the stored digest is equal and the stored outcome is retriable. Otherwise nothing happens.
2. **Consume** (device-bound): `UPDATE device_challenges SET consumed_by = :attempt WHERE challenge_id = :c AND account_id = :account AND operation = :op AND device_key_sha256 = :key AND consumed_by IS NULL AND expires_at > :now AND CLAIM`, and `AND RECENT` where the operation requires it, so a stale session does not spend the challenge.
3. **Advance** (refresh with supplied, validated optional assertion): the counter statement of section 5, `AND CLAIM AND PROOF`.
4. **Operate.** The one statement in the table below, under `CLAIM` and that operation's guards, stamping the attempt.
5. **Complete.** `UPDATE device_requests SET outcome = CASE ... END WHERE CLAIM`. Completion depends on the claim alone, never on the operation guards, so a false guard is recorded and not left pending. The `CASE` tests in a fixed order: `EFFECT` first, then each false guard as its own refusal (`reauthRequired`, `proofRefused`, `assertionStale`), then the state outcomes. A success or `reused` can therefore never be recorded while the proof is unconsumed or the session is stale. An explicit `ELSE 'pending'` sends any unmatched case to the final defensive assertion. `EFFECT` selects the operation-specific outcome; for refresh it additionally distinguishes an active occupied activation (`leased`) from a released activation (`revokedLease`).
6. **Depend.** History rows, slot removal, session binding and lease inputs are written only under `DONE(success)`. They never rely on the presence or absence of some existing row.
7. **Audit.** One event selected from this attempt's completed request row.
8. **Assert, then read back.** A final statement sets `outcome = NULL` where the row is still `CLAIM`, or where a success is recorded without its dependent row. That violates `NOT NULL`, the statement errors and the whole batch rolls back. The last statement reads the request row, and **the response is built only from that row**.

| Operation | Guards | Operate statement | Dependent writes | `CASE` order after `EFFECT` and the false guards |
| --- | --- | --- | --- | --- |
| Activate | `RECENT`, `PROOF` | Allocate, below | Insert the `activations` row (`active`, revision 1, sequence 0, `generation` by subquery, attestation fields where validated); bind the session | `reused` where a slot of this account holds `:key`, with that `activation_id` as result; `limitReached` where five slots are held |
| Replace | `RECENT`, `PROOF` | Replace, below | Mark the old activation `released` (revision + 1, reason `replaced`); insert the new one; bind the session | `reused` (nothing released); `notFound` where the named entry is not this account's; `stale` where it is released or its revision moved |
| Deactivate | `RECENT` | `UPDATE activations SET state = 'released', activation_revision + 1, released_at, release_reason = 'ownerDeactivated', changed_by = :attempt` where it is this account's, `active` and at `:expected_revision` | `DELETE` its slot row | `notFound`; `alreadyReleased` (success for the caller, no change); `stale` |
| Rename | none beyond `LIVE` | Update `display_name`, revision + 1 and the stamp on an `active` activation at `:expected_revision` | none | `notFound`; `notActive`; `stale` |
| Rebind | `RECENT`, `PROOF` | The section 5 statement, also requiring `device_key_sha256 = :key` | none | `notFound`; `notActive`; `stale` |
| Refresh | `PROOF`, `ASSERTED` | `UPDATE activations SET lease_sequence = lease_sequence + 1, sequence_by = :attempt`, and `last_refresh_at = :now` only while `active` | Store result fields and last/max granting lease bounds under the same attempt; released refresh stores terminal inputs only | `leased` where a slot names the activation; `revokedLease` where it is `released`; without `EFFECT`, `notFound` |

```sql
-- Allocate (activate). The cap and the duplicate-key rule are in the statement.
INSERT INTO activation_slots (account_id, slot, activation_id, device_key_sha256, changed_by)
SELECT :account, MIN(c.slot), :new_activation, :key, :attempt
FROM (SELECT 1 AS slot UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5) AS c
WHERE c.slot NOT IN (SELECT slot FROM activation_slots WHERE account_id = :account)
  AND NOT EXISTS (SELECT 1 FROM activation_slots WHERE account_id = :account AND device_key_sha256 = :key)
  AND CLAIM AND RECENT AND PROOF
HAVING MIN(c.slot) IS NOT NULL;

-- Replace (native only). One statement, so release and allocation cannot be separated.
UPDATE activation_slots SET activation_id = :new_activation, device_key_sha256 = :key, changed_by = :attempt
WHERE account_id = :account AND activation_id = :old_activation
  AND EXISTS (SELECT 1 FROM activations WHERE activation_id = :old_activation AND account_id = :account
              AND state = 'active' AND activation_revision = :expected_revision)
  AND NOT EXISTS (SELECT 1 FROM activation_slots WHERE account_id = :account AND device_key_sha256 = :key)
  AND CLAIM AND RECENT AND PROOF;
```

The replace target is named by an `activationID` that is never reused, so a race cannot release a different occupant. Activate, replace and rebind responses carry no lease; a lease comes only from refresh.

**Operator deactivation variant.** The support prepare/confirm/commit path uses the same active-account/activation revision and single `account_guard` CAS with a unique attempt nonce. Replace customer `LIVE`/`RECENT` guards only with the verified allowlisted operator identity, purpose/session-bound fresh human authentication and one-use descriptor/target guards from support §7. Set `release_reason = 'operatorDeactivated'`, increment activation and account revisions, remove exactly that activation's slot, restrict its bound sessions to terminal-only, and insert required audit/outcome rows in the same batch. Every dependent write requires this successful attempt stamp; an absent effect/audit or stale target rolls back/refuses without freeing a different slot. No customer session is fabricated, no lease/key/grant is minted, and the same cached-use and safe-recovery rules apply. Ordinary owner deactivation retains its existing customer guards.

**Zero rows affected is never success.** If the claim inserts and takes over nothing, no later statement fires and the read-back returns the stored row, or none where the session was not live. If any statement errors, the whole batch rolls back, including the claim, and the retry starts clean. A thrown batch, a timeout or an ambiguous result is reported as retriable and is never reported as activated.

**Invariants.**

- At most five `activation_slots` rows per account at every commit, under any interleaving.
- An `activations` row is `active` if and only if a slot row names it.
- `released` is terminal. No route, replay, refresh, rebind, sign-in, payment, renewal, trial start or operator-free path sets it back to `active`.
- No `device_requests` row is `pending` at any commit.
- No statement writes trial/source columns or `entitlementRevision` [OWNER D2]; slot/label changes advance the shared `accountRevision` so prepared support views cannot go stale.
- The cap applies whatever the entitlement state, including `none` and `expired`: activation does not require a grant, and a grant does not create a slot.

**Idempotency rules.** A terminal outcome, including the refusals `limitReached` and `stale`, is replayed for every retry of the same action, so a new customer attempt uses a new `requestID`. A retriable outcome is not: the same action bytes are resubmitted after re-authentication or with a fresh proof envelope, and the row is taken over. A replay only reads. It cannot re-enable a released identity, and it reports that activation's current `released` state. A replayed `leased` answers `superseded` with no lease, because a granting lease is never stored and never minted from a stored outcome; the client refreshes again under a new `requestID`. After the request record is purged (L§10 recommends 30 days) the same action bytes are simply a new request: they need a live session, recent authentication and a fresh proof, and are decided against current state.

## 7. Lifecycle [PROPOSED unless marked]

| Situation | Result |
| --- | --- |
| New Mac, fewer than five slots held | `activated`. New `activationID`, lowest free slot. |
| New Mac, five held | `limitReached`. Nothing changes. The app shows the list with replace and deactivate [OWNER D3, D7]. |
| Activate with a key that already holds a slot in this account (reinstall, repeated activation) | `reused`. Same `activationID`, same slot, no revision change, no new trial [OWNER D8]. With App Attest in force, a rebind follows. |
| Same key, different account | Independent. Counts in each. |
| New macOS login on the same physical Mac, same household | Separate verified user session joins the surviving broker-held household identity and reuses its slot; no new key/slot merely because the login is new. |
| Broker identity/key lost (wipe, lost secure state, replacement hardware) | A newly created key is a new identity. The verified owner explicitly replaces the old entry in the app, or deactivates it on the web and activates [OWNER D8]. No fingerprint/name inference. |
| Owner deactivates this Mac or another one | Slot free at commit. A replacement may activate immediately; no interval is imposed [OWNER D3]. |
| Released Mac whose key survives, activated again | Requires recent owner authentication like any activation, and creates a **new** `activationID` with `generation + 1` in a free slot, subject to the cap. The old activation, its leases and its sessions stay revoked. |
| Second macOS user, same household | Authenticates separately and reuses the broker-held key/slot, section 3; no session sharing. |

Beta/trial, added-Mac and replacement activation remain explicit customer actions. The accepted exception is automatic initial activation of the purchasing Mac after securely bound app-originated confirmed payment. That purchase action is not consent to automatic third-party installs and never repairs an unrelated released activation. Website purchases require email-code ownership plus entitlement/device proof. The [payment activation contract](payment-activation-contract.md) proposes the claim adapter, account/pending-owner mapping and guarded allocation transaction; their joint technical acceptance/proof remains open; ordinary session-only SQL below does not implement that exception.

## 8. Authentication, sessions and surfaces

**Ownership [OWNER D10].** For ordinary household routes the account always comes from the verified session (L§9). App-originated initial activation must instead derive a restricted target from a consumed server-authorised purchase/installation claim, never checkout email or caller account ID; [payment activation](payment-activation-contract.md) and billing section 5 gate that separate proposed contract under the same shared guards/cap. Account/activation guards, stored last/max lease bounds and recovery purposes are now shared proposals in L§9; they are not unresolved interface requests. No route accepts an account identifier. An `activationID` that belongs to another account answers exactly as an unknown one: same status, same body, comparable timing, `notFound`. The audit trail may record the refusal; the response never distinguishes it.

**Re-authentication [PROPOSED technical control, not a cooldown].** For ordinary verified-household routes, activate, replace, deactivate and rebind require the session's `authenticated_at` to be within 600 seconds, checked inside the SQL of section 6. Otherwise the answer is `reauthRequired` and the surface asks for a fresh one-time code, which updates `authenticated_at` on the existing session; the same action is then retried. It imposes no wait and no limit on how soon or how often a Mac may be replaced. Listing, rename and refresh need only a live session. A replay of a completed request returns its stored outcome under a live session without it. L§9 defines `authenticated_at`, the two session-bound re-auth purposes, and the terminal-only binding shared by these contracts.

**Session binding [shared PROPOSED contract with L§9].** A session row gains a nullable `activation_id`, set when that session activates or is reused on a Mac. A session bound to a `released` activation is **terminal-only**: token rotation, logout, challenge issuance for that one released activation and `POST /v1/activations/{id}/refresh` for it still work, and that refresh, or the replay of one of its own completed refreshes, returns only a non-granting lease of section 9. Every other route, and any other request's replay, answers as an invalid session. A lost Mac therefore cannot list or change the household's Macs with its old session, yet can still learn that it was revoked. Signing in again with a code yields a new, unbound session and restores nothing.

**Native surface.** A Manage Macs view reached from the licence area: the list, "This Mac" marked by comparing the local `activationID`, rename, deactivate with confirmation, and the limit-reached state with replace. Native tokens are as L§9.

**Web surface.** One small account page served by the same Worker, at the same official origin as the API, using the `HttpOnly` host-only cookie, CSRF token and exact `Origin` match of L§9. It offers sign-in, the list, rename and deactivate. Static first-party assets only, no third-party script, no token in a URL or in web storage. **This phase provisions nothing.** The latest PAT-2592 source records an empty EU `patched-licensing-dev` database, Workers Paid active, `notify.patched.im` enabled/configured, restored sender reads and one owner-received basic email test. These are recorded setup observations, not independently refreshed here. No licence account-page/API hostname, application Worker/route/binding, initialized schema or signing key has runtime verification in this packet. Actual account-wide billing/usage, remote concurrency and backup/restore remain unverified. None of the retired hosts or the retired portal is reused or depended on [GATE H5].

**The web page cannot create a device credential.** It holds no activation key, so it cannot produce a possession proof or an attestation, and the service offers it no route that mints an activation, a lease or a device-bound session. Web "replacement" is a deactivation; the new Mac then activates itself from the app.

## 9. Revocation and the cached lease

**On the service, deactivation completes at commit.** The slot is free and a replacement can activate in the next request. Release issues no lease.

**Non-granting lease after release [PROPOSED].** Each distinct completed refresh request for a released activation allocates the next positive `lease_sequence` atomically (section 6) and returns a freshly signed lease: `state` `revoked`, the account's current `entitlementRevision`, the released `activationRevision`, the new sequence, and `issuedAt = permittedUntil = hardEnd =` the service time of that request. It carries no evidence object and touches no slot, trial, entitlement or `last_refresh_at`. It needs no lease schema change, and it satisfies L§7 (sequence strictly above the highest accepted, revisions not below) and L§8 (`issuedAt` not below the anchor) however many earlier leases that Mac accepted. It is a truthful signed statement of revocation at that moment, never an outage permit. The service signs a granting lease only where a slot row still names the activation, so a released credential cannot obtain one. **No entitlement state alters this.** A paid, renewed, trial or beta account does not restore a released activation, and neither does a new session.

**Retry of the same refresh.** The request row stores the lease inputs, and the L§4 producer and Ed25519 are deterministic, so a retry with the same action bytes returns the same signed bytes while the signing key is unchanged. On the client, a lease whose sequence is not above the highest accepted is never accepted as new (L§7, unchanged): with the marker already held it is an already-handled revocation, with no status change, no re-anchor and no grant. If the original response was lost, the retry is the first to arrive, its sequence is above the highest accepted, and it is accepted normally. A new refresh request advances the sequence.

**On the removed Mac.** The app accepts the lease under L§6 and L§7: it persists the revocation marker before anything else, and the marker suppresses every older cached lease, including one whose signature and times are still valid.

**Removed Mac and recovery limit.** Ordinary release retains a terminal-only bound session so possession-proved refresh can return a fresh non-granting lease. Recovery/deletion revokes sessions outright, so the old session is refused and may receive no signed revocation. Persist L§6's `verificationBlocked` on that refusal; a later outage cannot revive the cache. Offline Macs that have not learned anything still keep only their already agreed same-boot bounds. Sign-in never revives a released ID; explicit activation gets a new ID. Optional attestation loss never prevents fetching a terminal denial solely because the old app-instance key disappeared.

**Display reason proposal.** Lease schema 1 has no field separating "this activation was released" from "this account was revoked", and L§3 maps them to different statuses (`slotUnavailable` with Manage Macs, against `revoked` with Contact support). Proposed: the refresh response carries an unsigned `reason` of `activationReleased` beside the envelope, used only to choose wording. It grants nothing and changes no decision. The alternative is a signed field in a later lease schema.

**What stays possible until the next successful check [OWNER D5].**

| Removed Mac | New update starts |
| --- | --- |
| Online | Until its next refresh: at launch, within 24 hours while running, or before a start once the lease is 24 hours old (L§5). |
| Cannot reach the service, same boot as its last verified lease | Until that lease's `permittedUntil`: at most 30 days for `paid` or `grace`, the trial's expiry for `trial`, the owner-agreed 7 days for `beta` (L§5, L§8). |
| Restarted, service unreachable | None. A changed boot identity needs a fresh verified lease first (L§8). |
| Restarted, service reachable | None after the launch refresh applies the revocation. |

During those windows more than five Macs can hold usable cached access at once. That is the recorded policy, not a defect: the cap is on registered slots.

**In-flight updates [OWNER D6].** Recovery of a transaction already underway never passes through the licence gate (L§11), so revocation cannot strand one.

**Limits carried over from L§7, unchanged.** The cached lease is software state. Ordinary same-user storage cannot detect a complete restore of an earlier valid snapshot, which could hide a revocation marker until that lease's own `permittedUntil`. A lease copied to another Mac fails the device key check only in an unmodified client. Nothing here resists an owner with administrative control or a modified client. The claim is fail-closed handling of missing, corrupt and inconsistent state, not tamper-proofing.

## 10. Routes, payloads and limits [PROPOSED]

All bodies follow section 4 over HTTPS and are bounded at 4 KiB, except activate, replace and rebind, which may carry an attestation and are bounded at 16 KiB. The size is checked before parsing.

| Route | Surface and auth | Purpose |
| --- | --- | --- |
| `GET /v1/activations` | App or web session | At most five entries: `activationID`, `displayName`, `createdAt`, `lastRefreshAt`, `activationRevision`; plus `limit` (5) and `used`. |
| `POST /v1/device/challenges` | App session; terminal-only restricted to its own refresh | Issue a challenge for one operation and key digest. |
| `POST /v1/recovery/cases/{caseID}/possession` | Active app session plus operation5 proof | Record case/digest-bound possession only; no grant or account change. |
| `POST /v1/activations` | App session, re-auth, proof, optional attestation evidence | Activate. |
| `POST /v1/activations/replace` | App session, re-auth, proof, optional attestation evidence | Atomic replace of `releaseActivationID` at `expectedRevision`. |
| `POST /v1/activations/{id}/rebind` | App session, re-auth, proof, new attestation | Section 5. |
| `POST /v1/activations/{id}/deactivate` | App or web session, re-auth; CSRF and `Origin` on web | Release. |
| `POST /v1/activations/{id}/rename` | App or web session; CSRF and `Origin` on web | Change the display name. |
| `POST /v1/activations/{id}/refresh` | L§9, plus possession proof, optional attestation evidence | Next lease, or the non-granting lease of section 9. |

**Abuse ceilings.** Proposed per account: 60 challenges and 60 slot mutations per hour, answered `429` with `Retry-After`. Per source IP: the L§9 style of hourly and daily ceilings. These are set far above household use. They are **not** a cooldown: there is no minimum interval between release and activation, no per-Mac transfer count, no lock after replacement and no limit on lifetime replacements [OWNER D3]. A limit that a real household could plausibly reach would be a policy change and needs Andy [GATE H7]. A `429` is an outage class for refresh (L§6) and never revokes anything.

## 11. Device data, names and audit [PROPOSED]

**Held per activation:** the opaque `activationID`, the public key and its hash, `generation`, state, revisions, attempt stamps, the display name, three timestamps, a release reason, and the App Attest key identifier, public key and counter where used. **Not held:** serial, hardware UUID, model, OS version, hostname, IP address, user name, location. The list shows the name, the activation date and the last check date, with times rounded to the UTC day.

**Display name.** Plain text, 1 to 64 Unicode scalar values after trimming and at most 256 UTF-8 bytes, NFC-normalised. Control characters, line breaks and bidirectional override characters are refused. The app suggests the Mac's computer name and the customer can edit it before it is sent; nothing is sent without that step. Names need not be unique, and dates can coincide, so every entry also shows the last six characters of its opaque `activationID`, and the native list marks "This Mac". That suffix is random, already held and derived from nothing about the hardware or the person; no further data is collected to tell entries apart. A name is never identity, never a lookup key and never an authorisation input [OWNER D9]. It is escaped for its context on every output, and the web page inserts it as text, never as markup.

**Audit events.** `activation.created`, `.reused`, `.replaced`, `.released`, `.renamed`, `.rebound`, `.limit_refused`, `.proof_refused`, `.attestation_refused`, `.not_found_refused`. Each records an event ID, service time, `accountID`, the `activationID` values involved, the surface (`app`, `web`, `operator`), the opaque session row identifier, `requestID`, outcome and `deviceKeySHA256`. Events never contain a nonce, signature, attestation, assertion, token, code, cookie, email address or display name: a customer may put anything in a name, so it is treated as untrusted personal text and kept out of logs. Routine retention is OWNER-settled and exact cleanup/deletion follows L§10; privacy review and financial exceptions remain open.

## 12. Paths and slices [PROPOSED]

**Every path below is new and does not exist, except those marked existing.** Nothing here amends the scope in `AGENTS.md`. Every proposed command below is nonexistent and unrun, and `scripts/verify.sh` (existing) stays as it is until a slice that adds a target also appends its script.

**Swift, new dependency-free target `PatchedActivation`:**

- `Sources/PatchedActivation/ActivationIdentity.swift`: identifiers, key digest, display-name validation.
- `Sources/PatchedActivation/DeviceRequest.swift`: the strict action bytes, the proof envelope and their bounds.
- `Sources/PatchedActivation/PossessionProof.swift`: the 164-byte message, and verification against a P-256 public key.
- `Sources/PatchedActivation/AttestationBinding.swift`: the two client-data derivations and typed outcomes. No Apple validation.
- `Sources/PatchedActivation/SlotLedger.swift`: the pure reference model of section 6, including the request record, guards and every outcome.
- `Sources/PatchedActivation/ActivationKeyProviding.swift`: the key protocol and a refusing default. No Keychain or Secure Enclave call.
- `Tests/PatchedActivationChecks/` (`main.swift` and case files), the only home of fixture P-256 keys, with an in-memory key behind `@_spi(Testing)`.
- `Fixtures/Activation/README.md` and `Fixtures/Activation/vectors/*.json`: proof bytes and ledger transition vectors, beside the existing `Fixtures/Catalogue/`.
- `scripts/verify-activation.sh`: `swift build`, then `swift run --skip-build patched-activation-checks`.
- `Package.swift` (**existing, modified**): the library, target and check executable.

**Native key adapter, separate new target so it can be withheld:** `Sources/PatchedActivationKeychain/SecureEnclaveActivationKey.swift`, `SecureStorageActivationKey.swift`, and proposed broker `Sources/PatchedMachineIdentity/{MachineIdentityStore,MembershipVerifier,PurposeBoundSigning,MachineLeaseStore}.swift`, `Sources/PatchedPrivilegedHelper/ActivationDispatcher.swift`, `Sources/PatchedHelperProtocol/ActivationCapability.swift`. Optional `AppAttestBinding.swift` is a later separate slice. No helper/key code is authorised here.

**Native view:** new files `Sources/PatchedUI/ManageMacsView.swift` and `Sources/PatchedUI/ManageMacsText.swift` in the **existing** `PatchedUI` target, a pure `ManageMacsPresentation` in `PatchedActivation`, and a new file `Tests/PatchedUIChecks/ManageMacsChecks.swift` in the **existing** `PatchedUIChecks` target.

**Service, under the OWNER-selected `service/licensing/` placement; toolchain/scope acceptance remains required:** `src/activations.ts`, `src/deviceProof.ts`, `src/attestation.ts`, `migrations/0002_activations.sql`, `tests/activations.test.ts`, `tests/activations.d1.test.ts`. **Web:** `service/licensing/web/account/index.html`, `account.js`, `account.css`, and `tests/account.test.ts`. Proposed command: `./scripts/verify-service.sh`, which L§11 proposes and which does not exist.

| Slice | Content | Can start after acceptance without live resources? |
| --- | --- | --- |
| **A1** | `PatchedActivation` sources, vectors, checks, `verify-activation.sh`. Pure, fixture keys only. | **Yes.** No network, Keychain, Secure Enclave, service or app launch. |
| **A2** | Service store interface with a fake, the `0002` migration, service and schema tests driven by the A1 vectors. | Needs the service placement and toolchain decision (L gate G4). No remote resource for the fake. |
| **A3** | The native key adapter and App Attest calls. | **No.** Only after explicit authority to create a real key on a named Mac, and after H1 to H3. |
| **A4** | Manage Macs presentation and painted view checks. | Yes, after A1. Offscreen paint only. |
| **A5** | The web account page against the fake store. | With A2. No hosting. |
| **A6** | Integration: app, service, remote D1, real key. | **No.** Last, behind every gate in section 14. |

Every logic diff needs red-then-green evidence and an independent full-diff correctness/security review under the canonical policy. A blocked review is not a pass. Current selector: canonical root AGENTS.md, 19 October 2026, direct NVIDIA HTTPS primary with approved independent fallback; OpenCode is not required.

## 13. Acceptance checks [PROPOSED]

None has been written or run. Each must first be shown failing against a stub or a reintroduced defect. Races are made deterministic in A1 by treating each batch as atomic and checking every ordering of the competing requests; that models the contract and proves nothing about D1.

| Area | Exact case | Slice |
| --- | --- | --- |
| Five then six | Five activations succeed in slots 1 to 5; the sixth is `limitReached` and changes nothing. | A1, A2 |
| Final slot | Four held, N distinct keys compete: exactly one `activated`, the rest `limitReached`, in every ordering. | A1, A2 |
| Release races | Deactivate against activate at five held; two replaces of the same old entry by different keys (one `replaced`, one `stale`); replace against deactivate of the same entry. Never more than five, never a wrong occupant released. | A1, A2 |
| Guards | For each route, each guard false alone (stale session, consumed, expired or foreign challenge, stale counter): the exact refusal is stored, never `reused` or a success; no slot, history, session, lease or counter write; no row left `pending`. An unmatched `CASE` rolls the batch back. | A1, A2 |
| Idempotency | Same `requestID` and action bytes returns the stored terminal outcome with no second row or event, before any proof or re-authentication is asked for. Same `requestID`, different action: `requestConflict`. A stored `limitReached` replays after a slot frees. | A1, A2 |
| Uncompleted retry | After `reauthRequired`, `proofRefused` or an expired challenge, the same action bytes under a fresh challenge execute once and do not conflict. A changed proof envelope never changes `request_digest`. | A1, A2 |
| Lost response | Activate, replace and deactivate each commit, the response is dropped, the retry returns the identical outcome. A rolled-back batch leaves no claim and the retry executes once. | A1, A2 |
| Replay | A replayed activate after that activation was released reports `released` and allocates nothing. A replay under a dead or foreign session, or under a terminal-only session for anything but its own refresh, is refused as an invalid session. A replayed `leased` yields `superseded` and no lease. No replay alters a trial field. | A1, A2 |
| Request syntax | Duplicate, escaped-duplicate, unknown and missing fields; reordered or whitespace-padded action; action of 1,025 bytes; name of 257 bytes; oversized attestation or assertion; path and action `activationID` differing: all refused before any state is read. | A1, A2 |
| Proof bytes | Any single changed field (operation, account, activation, key digest, nonce, action byte, expiry), a wrong domain, a truncated signature, a signature by another key: all `proofRefused`. | A1 |
| Copied credential | A request record, lease or session copied without the key cannot refresh. The same key presented twice in one account yields one slot. A key from account A used in B takes B's slot and reveals nothing of A. | A1, A2 |
| Cross-account | List, rename, deactivate, replace, rebind and refresh on another account's `activationID` equal the unknown-identifier answer byte for byte. | A2 |
| Re-authentication | A session older than 600 seconds gets `reauthRequired` on activate, replace, deactivate and rebind with no state change and the challenge unspent; refresh, rename and list succeed. No route imposes a wait after release. | A2 |
| Web | Missing CSRF token, wrong `Origin`, cross-site request: refused. No web route yields an activation, lease or device session. A name containing markup renders as text. | A5 |
| Names | 0, 1, 64 and 65 scalars; control, newline and bidirectional override characters; non-NFC input; two entries with the same name and date differ by their identifier suffix. | A1, A4 |
| Attestation | Absent/unsupported optional attestation still allows possession-only fallback. Supplied malformed/wrong-challenge/wrong-relying-party/wrong-key evidence refuses without an attested label. Equal counter twice: one `leased`, one `assertionStale`. Rebind keeps the `activationID`, slot and trial fields, raises the revision, sets the counter to the new key's initial value even when lower than the old, loses a revision race as `stale`, and refuses a released activation. | A1 (fixture objects), A2 |
| Key modes/loss | Hardware unavailable explicitly selects secure-store fallback with accepted clone limitation; corrupt/missing existing identity requires explicit replacement and never silently creates an extra slot. | A1 with the fake provider |
| Revocation and cache | After release: each new refresh returns a `revoked` lease with a higher sequence, current revisions and three equal times, accepted over any earlier lease; the same refresh retried returns identical bytes; a duplicate changes nothing on the client; no released refresh ever yields a granting state. Known marker or `verificationBlocked` suppresses older grants across restart and never revives them on outage. A remote release not yet learned by this Mac permits only an otherwise eligible old same-boot lease until `permittedUntil`; outage after reboot grants nothing; a terminal-only session can do nothing but refresh and log out. | A1, A2, with PAT-2587 slice L1 |
| In-flight recovery | The existing transaction recovery cases pass unchanged with a revoked lease present. | Existing gate, unchanged |
| Hygiene | Logs and audit contain no nonce, signature, token, code, email or display name; private activation rows may hold the specified display name and public attestation key, and challenge rows hold only the keyed nonce digest. | A2 |

**Separate future evidence, never satisfied by a fixture:** real Secure Enclave key creation and reuse after an actual reinstall of the actually signed app; App Attest on directly distributed builds, including real object sizes; transactional behaviour, rollback on a constraint error, the conditional upsert and concurrent final-slot requests on remote D1. Fixture and emulator results must be labelled as such and never presented as that evidence.

## 14. Gates

All technical shapes remain proposed until parent acceptance. Every future logic diff needs independent full-diff correctness/security review under the canonical policy. The older trust-boundary tier selection is superseded by the current canonical pre-production routing; select implementation model/effort from that policy rather than this historical contract.

| Gate | Remaining fact | Recommendation/reason | UNBLOCKS-WHEN |
| --- | --- | --- | --- |
| H1 compatibility | Tested OS/hardware matrix and optional App Attest direct-distribution eligibility absent. | Prefer hardware, explicit fallback; never force macOS 27/attestation from an older proposal. | Named-target key/reinstall/OS evidence supports published requirements; fixture modes need none. |
| H2 shared broker | Smallest machine-wide implementation/ACL and declined-helper experience unaccepted. | Co-host narrow broker in optional PAT-2607 helper; avoid another daemon, session sharing or fingerprinting. | PAT-2607 accepts IPC/key custody, owner accepts honest no-broker limitation and approved-target permission exists. |
| H3 native proof | Real enclave/secure-store key lifecycle, signing identity, multi-user proof unrun. | Bound separate targets and cleanup-safe keys; test simultaneous UIDs and wrong signer/UID. | Key create/reinstall/removal and enabled/disabled helper proof passes on approved matrix. |
| H9 initial paid activation | Session-only allocation is insufficient for the accepted no-email-first purchasing-Mac path. | Specify restricted claim proof, one-use/five-slot atomicity, current verified-session reuse, pending ownership and collision handling with billing section 5; no second slot ledger. | Binding contract accepted and duplicate/delayed/foreign/installation-loss races pass before integration; A1 ordinary slot fixtures remain independent. |
| H4 shared contracts | L§9 revisions/session purposes/latch now concrete proposals, not implementation. | Accept the contracts together so no alternate guard/refresh semantics appear. | Cross-module vectors and SQL tests cover the shared rules. |
| H5 runtime | CF recorded setup exists; bindings, origin, remote D1 concurrency and restore unproved. | Use PAT-2592 readiness packet; do not recreate development database. | Named isolated deployment/bindings and remote evidence approved and verified. |
| H6 display | Unsigned `activationReleased` reason affects wording only. | Keep authorization solely signed; default unknown reason to generic refusal. | Refusal/tamper display fixtures pass. |
| H7 limits | High ceilings proposed, not transfer cooldown. | Validate against normal household retries; no lifetime replacement cap. | Limit/retry fixtures and prelaunch usage assessment accepted. |
| H8 privacy | Baseline settled; privacy basis/deletion exceptions remain. | Use L§10 clocks and minimal denial rows; no default financial TTL. | Review accepts policy and cleanup tests pass before live data. |



**Fixture-only subset that could be scoped once both contracts are accepted:** A1, then A4, with A2 and A5 against fakes once the service toolchain is decided. None of them needs a key, a Keychain item, a credential, a network request, an installation or an app launch. This document authorises none of it.

## Final paid-activation owner reconciliation, 9 October 2026

[Payment activation contract](payment-activation-contract.md) supersedes blanket verified-email-before-paid-access/session-only checkout assumptions: securely bound app-originated purchase grants only the purchasing Mac after authoritative confirmation and unique guarded claim/slot allocation. Pending purchase ownership is distinct from verified household control; checkout email never finds/merges/reveals an account. Website purchase uses an expiring one-time email code plus confirmed payment, installation possession and ordinary guarded household/cap checks, without licence-key copy. Trial/beta, source/refund/revocation, shared-Mac/session isolation and exceptional-recovery controls remain. Support requests require verified household sign-in, no active paid entitlement. Existing management routes still require verified sessions; the new restricted purchase session cannot operate them. Proposed P1-P3 paths/tests and pending-owner schema compatibility need joint review before code; none is implemented.
