# T0 local licensing fixture harness

PAT-2639 implements only the T0 local fixture harness after the parent independently
observed the compiling Phase A red and froze its tests, SQL, verifier and tooling.
The focused gate passes locally; parent full-gate acceptance, independent review
and publication remain separate requirements.
This directory is not a deployed licensing service and grants no entitlement,
account, session, installation, release or signing authority.

Use Node **24.21.0** and its bundled npm **11.19.0** on PATH. The verifier checks
both exact versions and never switches or installs tooling. This host currently
has Node 26 on its ordinary PATH; the task's separately downloaded official,
SHA256-verified Node 24 archive lives only under the ignored repository `.build`.
For this worktree, invoke:

```sh
PATH="$PWD/.build/toolchain/node-v24.21.0-darwin-arm64/bin:$PATH" ./scripts/verify-service.sh
```

Other hosts must provide the same pinned Node/npm versions themselves. The
path above is the current Mac's local tool path, not a portable prerequisite.
`npm ci --ignore-scripts` uses the committed exact dependency lockfile; no
production dependency, SDK, global installation or credential is required.
The registry metadata was refreshed 11 October 2026: TypeScript 7.0.2,
Wrangler 4.149.0, Vitest 5.0.3, workers-types 5.20261011.1 and Node24 types
24.19.2. Installation audit reported zero advisories; that is advisory data,
not a security certification.

The unit harness substitutes a denying global fetch and explicit fake transport,
clock and byte adapters. Its canary calls an invalid host through the substituted
fetch without issuing a network request. It does not claim OS-wide network
isolation. Valid and wrong/mixed environment cases are separate; refusals must
happen before adapter or D1 use.

`wrangler.jsonc` uses today's explicit compatibility date (2026-10-11), a zero
fixture database ID, no account ID or route, disabled workers.dev/preview URLs
and an explicit local marker. There is no deploy script or workflow. Deploying
this config is outside scope. The D1 runner validates the fixture configuration,
copies it into an exclusively created `.build/licensing-d1-*` directory and runs
only project-local `wrangler d1 execute --local` / `wrangler dev --local`.
Inherited credentials are excluded, dotenv loading and metrics are disabled,
and development listens only on loopback. State and Wrangler logs are retained
in that disposable directory. No existing persistence directory is reused.

The SQL is a two-table toy fixture, not an account/licence migration. Its baseline
is revision 0 and one seed event. The fixture-only POST operation
`/__fixture/rollback` must batch a revision increment, an event write and a
constraint-failing duplicate seed insert. It returns fixture-labelled 409 and
both tables must match the pre-request snapshot. The positive control
`/__fixture/commit` batches revision 1 and the `committed` event together;
another failed batch must preserve that prior commit. These routes accept no
caller SQL, target, account or provider input. Ordinary routes return 404.
The smoke test independently reads persisted tables through local Wrangler,
rather than trusting the HTTP outcome. Local emulator rollback does not prove
remote D1 concurrency, disaster recovery or service readiness.

Official preflight references: [Wrangler config](https://developers.cloudflare.com/workers/wrangler/configuration/),
[D1 CLI](https://developers.cloudflare.com/workers/wrangler/commands/d1/),
[D1 API](https://developers.cloudflare.com/d1/worker-api/d1-database/),
[Worker testing](https://developers.cloudflare.com/workers/testing/),
[Node release metadata](https://nodejs.org/dist/index.json), and the official
npm registry metadata. Installed Wrangler help confirmed the local, persistence,
loopback and dynamic-port flags before the smoke runner was written.

## PAT-2640 pure retention policy

The parent observed 79 meaningful Phase A behavioural failures, accepted the typed
APIs and froze the 251 additive unit checks before releasing implementation. The
pure module now passes those checks locally. Parent final acceptance, independent
review and publication remain required. This is a retention-only subset of S1;
the wider proposed licensing contract remains a proposal outside accepted slices.

All timestamps are injected integer UTC Unix seconds in `0..253402300799`
(1970 through 9999). A duration day is 86,400 seconds. Calendar additions preserve
UTC time-of-day and clamp the original day to the target month's final day;
overflow refuses. No ambient clock or random source is read. Inputs use closed
category shapes, explicit nullable anchors and required booleans. Unknown or
malformed shapes, unsupported numbers and inconsistent marker histories refuse.

Challenge creation and fixed counter-bucket end anchor 24 hours; the earlier
first session expiry/revocation anchors 30 days. Ordinary retry terminal results
anchor 30 days, or creation does so for an abandoned request. Terminal and
abandoned states cannot coexist. Released Mac records use 90 days from terminal
release; audit events use 24 calendar months from immutable event time. Active
accounts have no automatic TTL; billing dedup and financial ledgers require a
separate schedule. Replay and access supply no replacement anchor. Callers must
preserve and authenticate original facts; this module cannot establish that
injected timestamps or trial history are truthful or immutable.

Trial-marker proposals use 12 calendar months from original used-account
deletion, which must not be in the future. Existing unexpired markers win,
including for an unused account, and their exact original expiry is preserved.
Markers must carry consistent original-deletion and expiry values. At expiry a
fresh account can be eligible, while an existing account's used history still
blocks it. Expired markers have no effect on fresh eligibility; the pure API
neither erases them nor creates a real marker. HMAC/key custody is absent.

Cleanup eligibility requires `now >= deadline` and no unexpired maximum grant
(`now < maxGrantPermittedUntil`), pending provider intent, reconciliation
reference or approved hold requiring the row. Each protection is explicitly
supplied and malformed inputs refuse even behind another protection. No-schedule
categories remain ineligible. Results grant no deletion or approval authority.
There are no adapters, account/authentication routes, SQL, storage, real deletion,
provider actions or native composition changes. Local policy checks do not prove
D1 cleanup races, privacy basis, restore safety or live operating readiness.

## S1a synthetic accounts and sessions (PAT-2642)

The parent observed and froze the Phase A unit and actual local D1 checks before
releasing five implementation modules. S1a now models passwordless challenges,
app/web sessions, reauthentication, refresh replay revocation and a fixture-only
account writer in this isolated local harness. These are synthetic credentials;
they grant no productive account, installation, entitlement or release authority.
Parent acceptance, independent review and publication remain separate gates.

Only `/__fixture/accounts/{request,consume,refresh,authenticate,logout,mutate}`
exists. Each POST requires all explicit controls: `x-fixture-key` exactly
`PAT-2642-synthetic`, `x-fixture-now` canonical UTC seconds 0..253402300799,
`x-fixture-seed` exactly 32 lowercase hex characters and `x-fixture-delivery`
`capture` or `refuse`. The marker selects the synthetic HMAC key [7 x 32],
and authenticates nobody. The seed byte at stream offset i is
`seedBytes[i % 16] XOR (i % 256) XOR floor(i / 16)`, bounded at 4096 bytes.
The code stream separately samples 0..7, yielding `01234567`. This predictable
fixture entropy is deliberately unsuitable for real credentials. No ambient
clock, key, entropy, mail transport or remote database is supplied.

Bodies are closed strict JSON, bounded at 2048 streamed UTF-8 bytes; duplicate
keys, malformed UTF-8, BOMs and nesting beyond 32 are refused. Only exact
`example.invalid` synthetic recipients reach the injected fake delivery callback.
Delivery failure leaves its challenge unusable. The ordinary outbound adapter
always throws and owns no network transport. Non-enumerating request responses
stay 202, including email ceilings and database/delivery failure; malformed input
and independent source-IP ceilings have distinct refusals. IDs/tokens are opaque
synthetic bytes; only domain-separated HMACs persist for codes, email/IP and tokens.

D1 batches reserve send quotas against live primary rows, supersede old challenges
and insert pending challenges atomically. Delivery can activate only the still
current pending row. Consume/rotation/account CAS writes are followed immediately
by a SQL `changes()` assertion: zero changed rows abort the batch before any
required dependent write. Every dependent write also checks the exact successful
nonce. Account/session creation occurs only for sign-in; reauth binds the current
account/session and preserves tokens and expiry. All writers share `account_guard`
and mandatory audit, with rollback assertions for missing required dependencies.
The `mutate` operation is an internal fake writer seam, never session authorization.

App access lasts 15 minutes and refresh is rotated with a 90-day idle deadline.
Every historical refresh HMAC remains replay-detectable; proven replay revokes
only the matching session atomically with audit. A domain-bound deterministic
replay-revocation audit nonce avoids relying on new credential entropy to revoke.
A lost rotation response therefore requires sign-in again. Web sessions have a
fixed 12-hour deadline and no refresh. No cookies, public web origin, paid claims,
trial/lease/activation or email recovery is implemented here.

`verify-service.sh` retains the unchanged T0 proof and adds 81 unit cases and 31
actual local D1 scenarios. Emulator concurrency/rollback is not remote D1 proof,
real email ownership, provider readiness, operational recovery or product security.

The explicit fake entropy-collision exception returns identifier-free 503,
independent of the email/account. Exact local D1 primary-key collision errors
abort the request batch, preserving the old challenge and quota reservation;
no prior usable challenge ID is returned. Ordinary database and delivery failures
still return generic 202. This is not a production RNG or authentication claim.

CHECK-MODIFIED: the parent observed two additive sequential/concurrent request
entropy cases fail on 202 versus required 503, then re-froze that D1 file before
releasing this fix. All original 29 assertions remain exact. The same accepted
change adds `Connection: close` solely to local test fetch headers, without retry,
status or timeout relaxation. Earlier ECONNRESET receipts remain retained; their
socket-close cause was not established. The focused gate now has 31 D1 scenarios.

Collision recognition relies on the observed local workerd `Error` and matching
`cause` primary-key constraint shape. This is an explicit emulator-adapter
assumption, not portable runtime evidence or productive collision security.

## S1b local trial, lease and cleanup proof (PAT-2643)

`entitlements.ts` uses the unchanged S1a session authenticator and keyed access
HMAC, then rechecks the session inside the shared account CAS transaction.
Trial start is explicit, lasts exactly 1,209,600 seconds and records immutable
request/hash/response evidence. Active beta refuses without consuming the trial.
Source, account and synthetic lease-head snapshots fence dependent mutations;
each required write is followed by a constraint assertion so an ignored write or
failed audit aborts the complete local D1 batch. Minimal S1b nonce history remains
when retry payloads expire; retained S1a nonce evidence also prevents collision.

The fixture adapter accepts only the five POST routes beneath
`/__fixture/licensing/`. It requires the existing environment/seed/clock/delivery
controls, `x-fixture-key: PAT-2643-synthetic`, and the canonical padded base64
32-byte public TEST-only L1 seed supplied explicitly in
`x-fixture-signing-seed`. Source contains only that fixture's public key, used to
verify the supplied signing identity. No seed default, real key, entropy, mail,
provider, ambient clock or network adapter is supplied. Missing controls refuse
503. Bodies are bounded at 2,048 streamed bytes and use strict UTF-8, duplicate
key rejection and a depth limit. Every response is `Cache-Control: no-store`.

The pure L1 producer closes all seven wire states, field ordering, evidence,
integer bounds and policy windows. Paid/grace wire compatibility creates no paid
source or ownership. Service issuance derives only stored trial/beta facts and
an existing synthetic pre-A2 lease head; it does not allocate or authorise a Mac.
Signing precedes commit privately, but bytes return only after the winning audit
and grant maximum have committed. Released IDs refuse and their maxima survive.

Local deletion changes the live email HMAC to `deleted:<accountID>` and revokes
sessions while preserving account/trial identity. Marker deadlines come from the
unchanged retention policy and an existing unexpired marker never extends.
Cleanup uses original challenge, session and trial retry anchors; refresh replay
rows are removed only with an eligible expired/revoked session in the same batch.
Unknown, financial, intent, reconciliation, approved-hold and outstanding grant
facts hold actual histories. Active accounts, sources, lease heads, nonce history,
and S1a account request/audit evidence are conservatively retained. In particular,
a missing TTL anchor or unproved S1a replay dependency never implies permission
to prune. The bounded dry run writes nothing. This is exclusive disposable local
D1 proof, not a productive privacy schedule or hosted-service guarantee.

The parent-added fault regressions cover silently ignored session revocation,
and future/invalid retention-row grant bounds. Deletion snapshots and counts all
sessions, requires the exact revocation write count, and aborts on any skipped
session. Stored lease grant history must be absent together or form a known
ordered granting interval with a historical maximum at least as large; malformed
history holds cleanup/deletion and refuses issuance/release. No-op cleanup and
dry runs recheck the current guard before returning without writes.

[D1 limits](https://developers.cloudflare.com/d1/platform/limits/) allow at most
100 bound parameters per individual batch statement. The nonce and session
predicate remain inside the winning CAS. Other closed snapshots are asserted
individually after that winner and before dependent effects, in the same batch;
false or NULL predicates force rollback. Each snapshot assertion binds at most 13
schema columns; the authenticated CAS binds 15 values. Head, retention and session collections read at most
101 rows; more than 100 conservatively holds cleanup or refuses deletion.
Candidate cleanup remains capped at 100 rows. This is a bounded local fixture
implementation, not remote scalability or a productive cleanup promise.

## PAT-2645 B1 Phase A synthetic inbox preparation

The five `src/billing` modules currently contain compiling refusing stubs.
`./scripts/verify-billing.sh` intentionally fails behavioural positive checks
until the parent observes red, freezes the exact contract and releases a fresh
Phase B implementer. Existing service/native checks remain unchanged.
CHECK-MODIFIED registrations are the optional explicit billing composition in
`src/index.ts`, the billing-only tsconfig include, appended service gate and
billing fixture/script paths in the existing read-only licensing CI.

`fixtureApplicationFetch(request, env, billingComposition?)` preserves the
existing handler. Ordinary default fetch supplies no billing composition.
Only the dedicated test wrapper supplies explicit fake config, seconds, attempt
IDs and key. There are no header, ambient clock, credential or default-key
adapters. The synthetic route is `/__fixture/billing/webhook`; no Paddle route
or compatibility claim is introduced. The signature is explicitly
`X-Patched-Fixture-Signature`, over `PAT-2645\n<seconds>\n` and exact raw bytes.
Fixtures and their independently computed literals are in `Fixtures/Billing/events`.

The additive 0003 migration creates only seven append-only billing evidence
categories: raw bodies, events, deliveries, conflicts, quarantine, audit and
completeness receipts. Account/lease/auth/source tables remain exact. The
intended atomic design includes an aborting fresh-attempt assertion before any
writes and an unconditional aborting complete-receipt assertion after the
receipt insert, including silently ignored writes. Missing/failed writes never
acknowledge success. The parent evidence folder owns the exact expanded SQL
proposal and per-statement binding order, pending freeze.

The dedicated tests use one actual pinned Miniflare 5/workerd runtime, bundled
actual application dispatch, an exclusive realpath-checked `.build/billing-owned-*`
root, sanitized launch environment, a stable worker name and
`resourcePersistencePath`. Migration allowlist is fixture SQL, 0001 and 0003;
0002 is absent. Productive account/session/trial/source/lease tables contain
sentinel rows and must remain unchanged. There is no accepted A2/activation
schema in this baseline, so this suite makes no slot-table assertion. Test
inspection, fault triggers and snapshots use the same D1 binding outside the
application; no SQL/debug route is exposed. Runtime log and metadata remain in
the exclusive run root. Console and network capture controls must pass before
billing behaviour is assessed. Local emulator results establish no remote D1,
provider, deployment, financial/privacy retention or release proof.

### PAT-2645 local Phase B implementation, 11 October 2026

This later note supersedes the refusing-stub status above. After parent-observed
red and the exact interface/SQL freeze, the five billing modules implement the
bounded synthetic stream, strict JSON/envelope parsing, exact-byte Web Crypto
HMAC verification and whole-event canonical projection. The ordinary application
still supplies no billing composition and refuses. Explicit fake configuration,
key, clock and attempt ID are required; no transport is called.

One D1 batch owns each attempt: the fresh-attempt assertion precedes writes;
immutable body/event evidence, delivery, conditional conflict/quarantine and
mandatory audit precede the completeness receipt and independent unconditional
assertion. Both raw and canonical comparisons include bytes and hashes. Required
writes suppressed by RAISE(IGNORE), storage errors and attempt collisions refuse
with 503 and rollback. Verified invalid data and semantic conflicts are
acknowledged only after their quarantine evidence commits, with 400 and 409.
Responses contain only the fixture marker and closed outcome, with no-store.

CHECK-MODIFIED: the parent corrected only the unit refusal helper's argument
selection to distinguish an omitted config from explicitly supplied undefined.
The default parameter had replaced the undefined-config test input with the valid
config. Every case and assertion stays present; parent direct probing confirmed
actual undefined configuration returns 503 with zero database calls, then the
parent re-froze the helper. The initial 75 unit failures therefore comprise 74
meaningful implementation failures and this one helper defect. No implementation
special case or assertion relaxation was added.

The second full focused verification passed both typechecks, all 261 unit cases
and all 55 actual local workerd/D1 cases, including the eight setup controls.
The first iteration and its helper failure remain retained; two of the maximum
five permitted iterations were used. Parent full-service/native verification,
whole-diff acceptance, independent NVIDIA review and publication remain separate.
This synthetic schema/signature is unverified against Paddle; it proves no real
provider authenticity, remote D1 semantics, timeout enforcement, account mapping,
entitlement, payment, custody, financial/privacy retention or release readiness.

### PAT-2652 local account harness

`tests/d1-local/account-runtime.ts` runs the actual fixture HTTP handler and
inspection queries through one pinned, test-owned Miniflare/workerd D1 binding.
Each run owns an exclusive `.build/account-owned-*` root, boots without
migrating, uses sanitized launch environment and bounded logs, and serves only
local loopback HTTP. Restart disposes the native owner before reopening the
same persisted state. A separate native outbound canary makes an actual fetch,
checks denial, then restores the source worker. No SQL/debug HTTP endpoint is
exposed, and the harness supplies no productive account, credential or service
authority.

All 31 original cases, their assertions and the seven-table snapshot mapping
are preserved. The six frozen checker paths permit only await/async/parentheses,
`Promise.all` around the original snapshot mapping, and async count/snapshot
`Promise<T>` conversions. Migration 0001 and trigger SQL remain exact. The
observed meaningful red was an actual owner-launch overlap with cleanup, not a
reproduction or attribution of historical `SQLITE_BUSY`. Independent review,
exact PR checks and main CI remain required acceptance conditions. Local
emulator results do not establish remote D1 or productive service readiness.

## PAT-2644 A2 synthetic activation slice

A2 is a bounded synthetic fixture path under `/__fixture/activations/*`. An
`ActivationService` constructed without explicit synthetic dependencies refuses;
the fixture transport requires explicit synthetic controls. No productive adapter
is provided. It models one shared
lease head and shared account concurrency guard. App-session possession is
required to allocate, reuse, replace, refresh or rebind. Web sessions may list,
rename and remove. Lists and replays read complete bounded coherent snapshots
in one D1 batch. Mutations fence their snapshots and required writes in the
shared CAS batch; conflicts return 409. Every mutation refuses an unsafe
shared-guard successor before dependent writes. Entitlement revision zero permits
allocation but refuses lease issuance. Synthetic attestation and operator
confirmation adapters use purpose-bound fixture MACs, not request booleans.

Activation generations, tombstones and lifetime ID retention prevent reuse.
Ordinary terminal sessions remain bound: they may rotate/logout or prove their
own key for refresh of their own revoked activation only. A2 runtime checks are
separate from B1 runtime checks; A2 runtime 0001/0002 and B1 runtime 0001/0003
provide no combined integration proof. This local fixture does not prove Apple
attestation, real key custody, remote D1 behaviour, hosted deployment or client
readiness. The full service and activation gate passed on fresh round 3,
including the four independent operator boundary cases. Round 2 passed its
frozen checks, but a subsequent independent operator overflow red blocked
acceptance until the shared guard repair. Earlier failures remain preserved.
Local green remains separate from parent acceptance, independent review and
required publication CI.

Run `./scripts/verify-service.sh` and `./scripts/verify-activation.sh` for the
focused service checks, and `./scripts/verify.sh` for the full native gate.

## PAT-2649 local account web implementation (local verification complete; review pending)

The parent accepted the fifth full local verification round on 12 October 2026.
`./scripts/verify-service.sh` exited 0 after 855.68 seconds: 1,087 Vitest and
725 Node tests, with no failures, cancellations, skips or TODOs; 179 new A45
local D1 tests passed. Chrome 154 completed all normal browser assertions,
including preservation of the original deadline and expiry. All 521 candidate
paths were unchanged. Four earlier attempts remain recorded as failures: the
first found and fixed a genuine atomic-logout audit issue and a snapshot-checker
column issue; the second passed unit checks but hit browser-navigation
infrastructure failure; the third exposed weak browser coverage and a checker
bug; the fourth passed normal browser checks but failed on ENOSPC. No hidden
reset was used.

Four compiled-copy negative controls were also accepted. Each deliberate
missing-Origin, CSRF, HTML-text or optimistic-removal mutation caused its
corresponding property assertion to fail with exit 1 while setup passed. Each
used exactly one compiled transform; source and the 521 frozen paths were unchanged.

The fifth `fixtureApplicationFetch` argument retains exactly eight server-owned
fields. The source copies validated keys, origin and asset bytes and captures
time once per operation; all internally created services use that captured time.
The finite synthetic entropy closure survives worker requests. No caller auth,
SQL, source-selection, provider, delivery, signing or paid-status callback is
accepted. The ordinary application supplies no web composition.

Constructor-only `requiredSessionKind:'web'` is captured immutably by Auth,
Trial and Activation services. The narrowed source principal validates the
original 43,200-second web session and pins all thirteen session columns in
source-owned SQL. Trial/deactivation use that principal in their existing
writers; narrowed logout obtains it again and includes it in the existing
atomic revoke/audit batch. Omitted/default auth and historical app-refresh
replay semantics are preserved.

Only the closed account page/assets/state, trial, own-Mac deactivation and logout
routes exist. A consumed, matching live web source credential can issue the
Secure/HttpOnly/host-only/SameSiteStrict cookie with original expiry and remaining
Max-Age. Reads never reissue it. Mutations require exact configured HTTPS Origin,
standard WebCrypto HMAC verification of the six length-prefixed CSRF fields,
exact application/json and a bounded 2048-byte strict body. Original trial
request revisions and exact A2 operation6 action bytes remain replay identities.

State combines the private-provenance entitlement snapshot with actual A2.list
rows. A private source-local observer retains the exact four-table rows validated
by list; all account/guard/session/source/marker/activation and billing predicates
then validate in one bounded read-only D1.batch. Incoherent or unknown facts
refuse. Beta display uses the invitation end (including null), while trial
availability follows existing source trial policy independently of paid/grace.
The page renders literal DOM text, confirms the exact target, preserves its last
confirmed list through pending/error states and waits for fresh source state
after confirmed mutations. A response-generation fence protects signed-out DOM.
No activation/key/lease/purchase/rename or browser sign-in endpoint is added.

The test-owner exception selects a fixed source entry and local assets inside
the existing exclusive runtime. Default ownership, D1 persistence, environment
scrubbing and outbound controls remain protected. Host-only setup consumes real
synthetic S1 challenges and delivers the actual issuer Response once through
owned HTTPS; browser credentials are never fabricated with CDP. Paid/grace
fixtures use actual B23 reconciliation and private source readback.

Browser verification requires existing Google Chrome major >=150 and the tested
CDP capabilities, plus pinned Node 24 WebSocket CDP. Chrome154 was observed during
local preparation; it is evidence, not an exact portability requirement. The
runner owns ephemeral TLS/SPKI and an exclusive .build profile, restricts child
environment, uses mock-keychain/password-store flags, disables background/sync
networking and verifies outbound denial. Missing browser/capabilities fail setup;
there is no install/download/fallback. Owned TLS/profile material is disposed.

The accepted verification required four CHECK-MODIFIED exceptions, all approved
by the parent and confined to checker or test-owned setup behavior: the stored
operation6 digest reads `device_requests.action_sha256` (the expected exact SHA
is unchanged); the canonical JSON snapshot sorts every row to support a
one-column unknown schema without removing tables or rows; the test-owned HTTPS
relay uses `Accept-Encoding: identity` on its internal fetch hop and corrects decoded-body headers with stale
encoded content length while preserving the exact queued response and source
Set-Cookie; and three occupied-slot predicates expect exactly five of five in
setup and two pending-state assertions. These four exceptions are candidates
for NVIDIA review. All other 511 protected paths remain exact at the current v5
freeze.

Local verification does not complete acceptance or establish release readiness.
The independent canonical top NVIDIA review, exact PR/main required CI and
publication remain pending. Windows native-browser behavior remains unverified;
required CI covers configured Linux and macOS only. No productive origin, provider, mail,
remote D1, keys, app installation or client release was used or established.

PAT-2657 adds bounded startup diagnostics, not a selected startup repair. The
independent builtin fake-child controls in
`tests/browser/chrome-startup-controls.mjs` exercise observation and draining
without launching Chrome. The observer retains a valid UTF8 stderr prefix of
at most 65,536 bytes, counts all drained bytes, records up to 64 ordered
lifecycle events and recognises exit, signal, error and close termination.

The existing native helper writes `chrome-startup-metadata.json` beneath its
exclusive `.build/account-browser-*` run before profile cleanup and emits the
bounded JSON to raw output. It records Chrome/platform/Node version, startup
time, owned directory metadata and path byte lengths, safe DevToolsActivePort
read-error categories, and SingletonSocket link type/byte length without
following its target. No environment dump, arbitrary profile contents,
cookies/tokens or TLS key bytes are recorded. `startupProcess` records status
before cleanup; `cleanupKillRequested` distinguishes the helper's forced kill.
Cleanup waits for close within the existing 3000ms races, with an already-closed
guard, to retain final drained stderr; the forced-kill status guards remain.
If close is not observed within those budgets, the helper destroys only its
owned stderr stream to avoid an inherited pipe keeping Node alive. Metadata
labels capture incomplete and records whether close was observed; complete
drain is never claimed for that bounded fallback. Profile metadata errors are
retained under the canonical owned run before the original cleanup guard can
refuse a missing or changed profile.

Linux CI runs the controls and `tests/browser/chrome-startup-preflight.mjs`
once before the unchanged `./scripts/verify-service.sh`. The preflight uses
actual owned TLS/native Chrome helpers, identical checkout/run/profile/TMPDIR
geometry, flags, sandbox, SPKI-only certificate allowance and deadlines. It
verifies actual version-checked CDP and initial about:blank, disposes owned
browser/TLS in finally, and fails nonzero when setup fails. It imports no
application/D1/product/session fixture and installs nothing. Diagnostic success
cannot replace the full service/native gate or prove product behaviour.

The Linux startup cause remains unknown until actual retained diagnostics are
judged. No TMPDIR, retry, timeout, sandbox, TLS or egress repair is selected;
A45's five source attempts remain exhausted. Local syntax/fake-child results
do not establish Linux startup success, Windows parity, accepted main or a
release. Parent acceptance, independent TOP NVIDIA full-diff review, full
relevant gates, exact PR/main CI and merged-source readback remain required.
