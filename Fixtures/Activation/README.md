# Activation reference fixtures (PAT-2615)

This is the locally implemented ordinary A1 reference model. The parent observed
Phase A compiling red (130 checks, 128 failures), then explicitly released
implementation. The six `Sources/PatchedActivation` files implement parsing,
P-256 possession and atomic in-memory allocation. The default key provider
still always refuses. Parent acceptance, independent review and publication
remain separate; no production or native adapter is enabled.

Run `./scripts/verify-activation.sh`; `scripts/verify.sh` includes this gate.
The original 130 checks are retained. Additive checks cover direct proof-context
shape, action/public-key binding, counter/sequence rollback, display-only rename,
cross-account refusal, terminal sessions and escaped Unicode. None replaces a
frozen case.
Local Phase B verification on 9 October passed all 159 activation cases and the
full `./scripts/verify.sh` gate. Removing the consumed-challenge guard produced
one meaningful compiled failure; exact source bytes were restored and
hash-verified before the final green full gate. Private evidence is under
`.build/pat-2615-evidence`. This is model verification, pending parent review.

The executable uses independent test-only action and message producers. Its
fixed `vectors/operation-1.json` through `operation-5.json` pin exact action,
SHA-256 digest and 164-byte proof message, together with one valid public key
and raw 64-byte P-256 signature per vector. The corpus check independently
verifies these signatures. Fresh ECDSA signatures may vary and are never
compared for deterministic signature bytes. This is not Worker interoperability
proof. `final-slot.json` drives all six orderings of a three-way final-slot race.

Private scalar fixtures exist only in `Tests/PatchedActivationChecks`; they are
obvious, public low-entropy test material and are unrelated to any production
key. No generated private key is stored. `--emit-fixture-vectors` writes public
fixture vectors only under `.build/pat-2615-evidence/generated-vectors`; ordinary
gate runs do not rewrite the checked-in corpus. Evidence logs also stay beneath
`.build/pat-2615-evidence`.

The model uses fake verified household sessions and caller-injected service
time, expected revisions, challenge rows, optional fixture validation and grant
bounds. These inputs are test-only assumptions, not authentication, entitlement,
Apple chain validation, session custody or remote authority. Its keyed challenge
nonce digest convention is HMAC-SHA256 over decoded 16-byte challenge ID,
decoded 16-byte account ID, one operation byte and 32 nonce bytes, using a
fixture key. This local storage convention is not a service wire format.

Activation-revision `stale` follows allocation section 6: it is a terminal
stored/audited outcome and may consume its challenge, but changes no slot or
activation history. Its equal-action replay only reads. Audit failure rolls
back even that stale claim and nonce. The shared account CAS guard is modelled
as a whole-snapshot refusal. Transient guard refusals have no persisted retry
row in this reference subset; a new valid proof may retry the same action.
This explicit local simplification does not establish service SQL behaviour.

A completed active refresh always replays as `superseded` with no allowance,
even if still current, as allocation section 6 explicitly requires. Refreshing
again needs a new request ID and proof. Section 9's identical retry inputs apply
to the non-granting revoked response only. Terminal-only sessions cannot replay
another user's request or regain an earlier active grant. `ModelGrant` holds
unsigned fixture lease inputs; no signed licence or entitlement is minted.
Granting windows are injected test assumptions, not L1 verification results.
The historical maximum of all issued granting windows is retained across later
shorter/non-granting responses and release.

Optional validation is explicitly `FixtureAttestationValidating`. Supplied
evidence with no adapter or failed fake validation refuses; absent evidence
uses `secureStorageFallback`, even where a fixture attestation was stored.
Availability flags alone cannot produce an attested label. A validated fake is
labelled `fixtureAttested`, never hardware-bound. A rebind may reset the counter
only for a different fixture attestation key and never changes the slot.

Recovery case ID (32 lowercase hex) and case digest (64 lowercase hex SHA-256)
are the parent-approved local reference encoding choice. Existing proposals do
not settle those wire encodings. Later service/support interoperability remains
a gate. Recovery possession records only case-bound proof, with no slot,
entitlement, account revision or session mutation. The case is an injected fake;
no real recovery evidence standard is accepted by these fixtures.

Names are plain text: raw forbidden controls, line breaks and bidi overrides
must be rejected before trimming, then names are NFC-normalised and bounded by
Unicode scalars and UTF-8 bytes. Markup is retained as untrusted text. Names
never establish identity, membership or slot reuse, and audit types omit them.
Exact original action bytes remain signed even when their decoded text agrees.

Atomic value transitions and deterministic orderings are not proof of actual
D1 transactions, remote concurrency, native multi-user behaviour or hardware
security. Possession proves a key holder, never a unique physical Mac. Reusing
an injected fallback key across fake local users models one occupied household
slot; a determined user can copy fallback identity. Real key storage, broker,
helper, Apple adapter, provider, network, app composition and installed-target
work remain out of scope. L1/L2, Core and all real installation entry points
are unchanged.

## Failure diagnostics (PAT-2620)

The parent independently observed Phase A compiling red: 170 cases with exactly
11 new diagnostic failures, and all original 159 cases passing. After explicit
release, capture was implemented locally without changing those frozen checks,
assertion bodies or vector bytes. Parent acceptance, independent review, CI and
publication remain separate gates. Run `./scripts/verify-activation.sh`.

An unexpected top-level case failure emits one JSON diagnostic for the last
fixture prepared in that case. It includes exact public attempt/body, reference
action/context/message, signature and challenge ID, plus independent parse,
production-message comparison, direct CryptoKit signature verification and
production proof verification results. All byte/text values use base64 through
Codable Data. OS/version and architecture are captured without launching tools.
Successful and expected-refusal paths emit no diagnostic. Capture resets per
case; failed capture replaces earlier evidence with an unavailable marker.

The report describes prepared input, which may differ from a subsequently
mutated attempt or ledger. Apply guards are not observed, current ledger state
is not captured and model-state replay is not performed. Parse and proof results
are fresh independent checks on captured input, not the original failing stage.
To replay the signature, decode publicKey/signature/referenceMessage base64 and
verify the raw P-256 signature with the x963 public key. To reconstruct the
independent message, use action, accountID/activationID UTF-8 values, operation,
nonce and expiresAt with ReferenceProducer's documented byte convention.

Input fields and encoded output are bounded. Maximum report size is 65,536 UTF-8
bytes. Oversized or invalid reference context signals unavailable; exact bytes
are never silently truncated. Diagnostic errors preserve the original error and
failing process exit. Reports contain no private scalar, MAC key or whole ledger.
The check-only `--diagnostic-force-proof-refusal` flag registers an additional
unexpected synthetic proof refusal, emits its public diagnostic and exits 1.
It intentionally does not call model apply and proves no internal failing guard.

The two original CI proof refusals remain unexplained. Passing local checks or a
CI rerun is not remediation or reproduction of the original affected platform.

### Forced-refusal check correction (PAT-2629)

CHECK-MODIFIED: the parent explicitly accepted an exception for only the forced
proof-refusal diagnostic check before editing, retaining its original bytes and
the tracked-file hashes. Main `e4b7a392cc5e7819a67d5a7d9acbfe14fe42674e` full
verification run 38015670464/job 114105249100 failed that check on macOS 15.7.9,
Swift 6.1.2: the report truthfully recorded raw signature refusal and production
proof acceptance, while the assertion incorrectly required raw acceptance.

The corrected check retains the freshly generated signature and original
`proofRefused` error. It binds the single diagnostic to the exact prepared body,
action, key, signature, context and independent reference message, then compares
the reported raw status with direct CryptoKit verification of those same bytes.
Actual production proof verification and its reported acceptance remain required;
apply stays not observed and no ledger evidence is invented. All other checks,
fixed vectors, reporters and production sources remain unchanged. The exact CI
signature and its n-S companion both verify on the local macOS 27 host; the
internal Apple cause remains unknown. Local green alone does not close this
incident: independent review and exact affected-platform PR and merged-main full
verification remain required. No installed proof follows from this correction.

## Fixed public proof replay (PAT-2621)

`ci-refused-20261009.json` preserves the first complete public diagnostic from
main CI run 37982634197, including its original macOS 15.7.9 refusal. Its full
JSON and decoded proof bytes are pinned by additive checks. It is never
regenerated, re-signed or replaced. The second last-prepared diagnostic from
that run is not treated as the actual failing input.

`FixedProofReplay` is check-target-only. It records 21 independent stages for
body parsing and byte equality, reference/production message equality,
CryptoKit key/signature construction, raw/DER round trips, message/digest
verification, Security public-key import and algorithm support, Security
message/digest verification, and production proof verification. Security uses
independently encoded canonical DER from the unchanged raw signature.
Constructor errors use fixed categories without platform error descriptions.
A complete report means all stages are recorded, not that the proof accepted.
Unavailable dependencies are distinguished from observed refusals.

The known-vector check prints one bounded JSON report before its acceptance
assertions, retaining all stages if the affected platform refuses again. The
report carries exact bounded public input, both DER representations, current
OS and architecture. Input and report field sizes are checked before encoding;
the final output limit is 65,536 UTF-8 bytes, with no truncation. No ledger,
current state, apply-guard or model replay is performed. There is no signing,
Keychain, network, production logging or installation path.

Parent observed Phase A compilation with all original 173 cases passing and
14 new reporter-capability assertions failing. The original diagnostic, new
checks and registration were frozen before Phase B. Local focused verification
now passes 188 cases on macOS 27.0.1 arm64, with all 21 stages accepting the
unchanged vector. This is reporter-capability evidence, not a root cause or fix
for the macOS 15 incident. Parent acceptance, independent review and affected
platform PR CI replay remain required; a passing replay does not resolve the
original incident.

The full activation gate also emits the same fixed report in a fresh check
process, before any suite case runs, then runs all 188 cases unchanged. The
emission mode requires a complete reporter but records underlying crypto
refusals as data; the ordinary known-vector assertions still fail on refusal.
This isolates suite/process-state interference without turning a failed proof
into accepted evidence. The exact signature is independently valid under
OpenSSL and direct P-256 arithmetic; the macOS 15 cause remains unresolved.
The fresh process also reports a separately labelled, independently Node-verified
`n-S` signature companion. The captured input file and original report remain
unchanged; the companion intentionally reports a body/signature mismatch.
Its results are diagnostic data, never a replacement for the original proof or
an accepted production workaround.


## Representation compatibility repair (PAT-2621, subsequent scope)

The earlier diagnostic-only restrictions above describe that stage. The accepted
repair changes only the pure possession verifier delegation and a package-internal
helper. Both R and S must be unsigned, nonzero 32-byte scalars below P-256 order.
The helper converts low S to the mathematically equivalent n-S, retains high S
and R, and verifies that representation with ordinary CryptoKit. It neither
changes the original request/proof bytes nor implements an EC verifier. Existing
context, action, key, nonce, expiry and replay checks remain unchanged.

Affected macOS 15 PR run 37988905421 recorded the original raw signature refusing
in CryptoKit and Security before and after the original suite. Its independently
valid n-S companion accepted all four raw framework verification stages and
productionProof. Original bytes remain pinned; the original S is already low.
Independent OpenSSL and direct P-256 arithmetic validate it. The evidence shows
representation-sensitive false rejection, not the internal Apple cause.

The diagnostic reporter remains exact and records raw framework results without
normalisation. Three mistaken reporter-capability expectations were explicitly
corrected and re-frozen: raw framework stages must record accepted/refused on
the original and equal that baseline for body-only changes. ProductionProof
must still accept; changed-message, tamper, bounds and constructor checks remain.
A separate companion-positive case requires every raw framework stage to accept.
The prior frozen test bytes/hash and exact correction diff are retained privately.
All original 173 assertion bodies/helpers/vectors remain unchanged.

The 43 new compatibility cases cover both scalar representations, fixed and
generated signatures, literal complement arithmetic boundaries, invalid scalars
and lengths, tampered signatures, changed message/key/context and sliced Data.
Parent Phase A compiled and failed 59 of 231 cases meaningfully before helper
implementation. All 231 cases and the local full gate subsequently passed;
bypassing actual cryptographic verification caused 21 frozen failures before
exact restoration. These are local checks. Independent review and exact affected
macOS 15 PR/main CI remain acceptance gates. No service, installed target, native
key storage, release or custom cryptographic authority follows from this repair.

## Additional bidirectional captures (PAT-2621, Phase A)

`ci-37995438633-stale-first-apply.json` and
`ci-37995438633-race-last-prepared.json` preserve exact public JSON from run
37995438633, head `2c656dc7cacb9cb7608e2d4a3f1161e14e032d52`, log lines 1556
and 1550 respectively. The stale check prepares one request and passes it
unchanged to its failing first apply. The race check prepares two requests
before applying either: its record identifies only the last prepared request,
not the failing apply, permutation or index. Neither record captures ledger state.

The additive checks pin the raw capture hashes and public message/key/signature
bindings, and require production verification of each original and literal n-S
companion without replacing captured bytes. Node and the OpenSSL CLI independently
validate both forms; those two interfaces share the OpenSSL implementation.
Tamper, changed message/key/action/nonce and expiry controls must refuse.
The existing 231 checks and original captured fixture remain unchanged.
Local macOS 27 readiness can pass while the retained exact-head macOS 15 full
gate has two genuine failures. No test acceptance override or asserted raw
framework refusal substitutes for affected-platform verification.

## Generated-pair check correction (PAT-2631)

CHECK-MODIFIED: the parent accepted a bounded exception for only the generated
pair block in `P256CompatibilityChecks.swift` before editing. Merged-main full
verification run 38018331134 at `70a65289a03a3b81595a6118d72d441b7579cac9`
failed key 17's raw high-S positive assertion before either production verifier
ran. That failure does not establish a production verification failure.

The check now independently evaluates raw CryptoKit verification of both exact
generated members and requires at least one to accept. It does not retry signing,
normalise either input or use production verification as its raw positive anchor.
Both original and independently computed n-S signatures must still separately
pass `P256SignatureVerification.verify` and `PossessionProof.verify` with the
original message, action, key and trusted context. Scalar convergence, literal
complement goldens, fixed captures and all refusal checks remain unchanged.

This corrects an unsupported universal raw high-S acceptance assumption; it
does not establish an internal Apple cause or universal raw low-S acceptance.
Local success remains distinct from independent review and exact affected-platform
PR and merged-main full verification. This check change grants no installed proof.
