# Offline catalogue v2 fixture protocol

PAT-2623 C1a implements catalogue-only preparation: a dependency-free Node reference verifier, deterministic fixture encoder and bounded comparator, with an independent Swift CryptoKit check. It is a local fixture protocol, not a deployed Worker, production signer, app consumer, job/evidence/support schema or installed updater. Every verification result explicitly denies installation, publication and fresh OS validation authority.

Run `./scripts/verify-catalogue-protocol.sh` with installed Node22+ and Swift/CryptoKit. The gate prints actual versions, verifies four cryptographic vectors with Swift, then runs the Node suite, including reverse verification of Swift-generated signatures. No package or tool installation is required. The full `./scripts/verify.sh` now runs this frozen gate and the separate additive hostname-boundary checks. Parent acceptance and independent review remain separate steps.

## Wire bytes and strict parsing

The envelope is a closed object with exactly `{schema,algorithm,keyID,payload,signature}`. Its schema is `fixture-catalogue-envelope-v2`, algorithm `Ed25519`, and keyID uses the opaque ID grammar below. Payload is canonical padded base64 of the exact payload bytes. Signature is canonical padded base64 of exactly64 Ed25519 signature bytes. Padding bits must also be canonical. There is no compression or algorithm negotiation.

The signed message is UTF8 `im.patched.catalogue.v2`, one NUL byte, then the exact decoded payload bytes. Verification and replay hashing never reparse/reserialise these bytes. The envelope is at most2097152 bytes (2MiB) and decoded payload at most1048576 bytes (1MiB), inclusive. Inputs use fatal UTF8 decoding. BOM, duplicate decoded keys including escaped aliases, malformed Unicode/lone surrogates, trailing data and container depth above16 refuse. The root container is depth1. Ordinary JSON whitespace is permitted, but binds the signature and replay identity exactly.

The protocol intentionally uses an integer subset of JSON. Every raw numeric token must match `0|[1-9][0-9]*` and fit a safe integer before conversion. Signs, negative zero, fractions and exponents refuse, including forms which JavaScript would round to an integer. All schema integer limits are inclusive. Maximum safe integer is9007199254740991.

`strict-json.mjs` is an internal bounded parser, not a schema verifier. `parseStrictJSON(bytes,{maximumBytes,maximumDepth:16})` accepts Uint8Array/Buffer and returns parsed data or throws SyntaxError. maximumBytes is1..2097152. Bounds are a closed ordinary data record. Decoded object keys are defined as data properties, including `__proto__`, so parsing cannot mutate an object's prototype.

`catalogue-v2.schema.json` is a descriptive draft2020-12 contract. No third-party JSON Schema engine executes it. Runtime code separately checks byte bounds, strict number tokens, Unicode, sorting, cross-field relationships, time, trust, signatures and continuity.

## Closed payload and entry records

The payload has exactly `{schema,domain,catalogueID,keyID,sequence,issuedAt,expiresAt,minimumClientProtocol,minimumClientBuild,policyDigest,entries,withdrawals}`. Schema is `fixture-catalogue-v2`; domain is `im.patched.catalogue.v2`. Catalogue/key IDs are opaque IDs. Sequence and minimumClientBuild are positive safe integers; minimumClientProtocol is exactly2. Times are nonnegative safe Unix seconds. policyDigest is64 lowercase hexadecimal characters. No entitlement or installAllowed field is accepted.

Opaque IDs are1..64 ASCII bytes: an alphanumeric first character followed by alphanumeric, dot, underscore or hyphen. Digests always mean64 lowercase hexadecimal characters. Entries and withdrawals each contain at most1000 records, strictly sorted by ASCII releaseID and unique within/across the two arrays. Empty and withdrawal-only catalogues may verify. Multiple releases of one product are permitted; choosing an update is future consumer policy.

Each entry has exactly `{identity,release,compatibility,source,artifact,evidence,installer}`:

| Record | Exact fields and constraints |
| --- | --- |
| identity | `{productID,releaseID,bundleID,teamID,edition,generation,channel}`. Product/release/edition/generation are opaque IDs. bundleID is1..255 ASCII letters/digits/dot/hyphen with at least two nonempty dot-separated components. teamID is exactly10 uppercase ASCII alphanumeric characters. channel is `stable`. |
| release | `{version,comparator}`. comparator is `numeric-dotted-u32-v1`. Version has1..8 decimal UInt32 components (0..4294967295), no leading zero except zero itself, signs, empty components or Unicode digits. |
| compatibility | `{platform,minimumOS,maximumOS,architectures}`. platform is `macOS`; OS versions use the same grammar. maximumOS is null or compares at least minimumOS. architectures is a nonempty, unique ASCII-sorted subset of `arm64`,`x86_64`. |
| source | `{routeID,routeVersion,url,redirectHosts,observedAt}`. Route ID/version are opaque IDs. URL/redirect constraints appear below. observedAt is a nonnegative safe Unix timestamp. |
| artifact | `{sha256,byteLength}`. Digest and positive integer byteLength at most8589934592 (8GiB). This is an inert metadata ceiling, not download policy. |
| evidence | `{sha256,byteLength,policyVersion,checkerVersion,environmentVersion,verifiedAt,validUntil}`. Digest, positive integer byteLength at most4194304 (4MiB), three opaque version IDs and nonnegative safe Unix timestamps. Evidence is a digest descriptor; its contents are never opened or trusted as an OS assessment here. |
| installer | `{method,version,interaction,restart,coordination}`. method is `dmg-app`,`pkg` or `zip-app`; version is an opaque ID; interaction is `ask` or `defer`; restart is `none` or `ask`; coordination is `exclusive-app`. These describe claimed policy, not execution approval. |

A withdrawal has exactly `{productID,releaseID,artifactSHA256,reason,effectiveAt}`. Product/release/reason are opaque IDs; artifactSHA256 is a digest; effectiveAt is a nonnegative safe Unix timestamp no later than issuedAt. Withdrawal fixtures never mutate installed state or cause a downgrade.

## URLs and time relationships

URLs retain the exact input text and are at most2048 UTF8 bytes. Require literal lowercase `https://`, explicit authority and a lowercase ASCII DNS hostname. Reject raw whitespace/control/backslash, percent-encoded or uppercase hostname, authority userinfo and every raw `#`, including an empty fragment. `@` in path/query is permitted. Optional URL port must be canonical decimal1..65535; empty colon, leading zeros and parser repair refuse. Redirect hosts are a separate strictly sorted unique array of at most16 bare DNS names, without ports. URL hostname need not occur in redirectHosts.

A DNS hostname is1..253 bytes, with1..63-byte lowercase ASCII alphanumeric/hyphen labels and no edge hyphen, empty label, wildcard, trailing dot or IP literal. Parser-normalised numeric IP spellings also refuse. The fixture protocol applies the same conservative, exact WHATWG URL-compatible hostname ceiling to source URLs and redirectHosts. DNS-shaped names with numeric final labels such as `example.123` are unsupported here because URL parsing treats them as IPv4 candidates; this does not mean they are globally invalid DNS names. These checks establish syntax only. No DNS lookup, fetch, redirect following, SSRF protection or route-policy safety is claimed.

Time validation requires all of the following:

- expiresAt > issuedAt; lifetime at most172800 seconds (48h).
- issuedAt <= injected now +300 seconds; expiresAt > now, so equality is expired.
- source.observedAt <= issuedAt and age at most86400 seconds (24h).
- evidence.verifiedAt <= issuedAt; evidence.validUntil > issuedAt.
- evidence.validUntil <= verifiedAt +259200 seconds (72h); expiresAt <= every evidence.validUntil.
- withdrawal.effectiveAt <= issuedAt.

Arithmetic comparisons avoid adding tolerances to maximum safe timestamps. Injected time and descriptors do not prove real native freshness.

## Public APIs and result keys

`verifyCatalogue({envelopeBytes,trust,context,previous,bootstrap})` is pure synchronous fixture verification. The argument is a closed record with exactly those five own enumerable data keys. envelopeBytes is Uint8Array, including Buffer, never a string. Records must have Object.prototype or null prototype; accessors, hidden fields, symbols, functions and custom prototypes refuse. Arrays are ordinary dense arrays without extra fields or accessor elements. Records, strings and array counts are checked before the fixture encoder copies them. Verification bounds and copies input bytes before parsing. No caller getter, iterator or toJSON hook is intentionally invoked. Arbitrary Proxy isolation and a modified JavaScript host environment are outside this API's contract; this is not a JS sandbox.

Trust has exactly `{catalogueID,keyID,publicKeyBase64,firstSequence,lastSequence,retired}`. IDs follow the opaque grammar; publicKeyBase64 is canonical padded base64 of exactly32 Ed25519 public-key bytes. Sequence bounds are positive safe integers with lastSequence >= firstSequence. retired must be a boolean and true refuses. Caller-injected trust is test authority only, not authenticated app-distributed trust.

Context has exactly `{now,clientProtocol,clientBuild}`. now is a nonnegative safe integer. Protocol/build are positive safe integers; clientProtocol must be2 and clientBuild must meet the payload minimum. Unknown supported-shape protocol values refuse as unsupported-client.

Every result has exactly these ten keys:

`{status,reason,scope,installationAuthorized,publicationAuthority,freshOSValidation,payloadSHA256,sequence,catalogue,checkpoint}`

scope is always `fixture-only`; installationAuthorized, publicationAuthority and freshOSValidation are always false. A refusal has status `refused`, a reason below, and null for payloadSHA256, sequence, catalogue and checkpoint. Success has status `verified` or `duplicate`, reason null, exact-byte lowercase SHA256, payload sequence, a copied validated payload in catalogue and `{catalogueID,sequence,payloadSHA256}` in checkpoint. Returned data is mutable but never aliases mutable caller data or another result. No input is changed or replaced.

| Refusal reason | Meaning |
| --- | --- |
| invalid-input | Top-level argument/type/key/descriptor or bootstrap type is invalid. |
| invalid-envelope | Envelope byte limit, strict parsing, shape/schema/algorithm, canonical base64 or decoded byte/signature size is invalid. |
| invalid-payload | Payload parsing, shape, field type/range, ID/version/URL/ordering or structural relationship is invalid. |
| invalid-trust | Injected trust shape, public key encoding, IDs or sequence bounds are invalid. |
| invalid-context | Injected context shape or integer values are invalid. |
| invalid-history | Previous checkpoint shape, namespace, sequence or digest is invalid. |
| unsupported-client | Unknown protocol or insufficient client build. |
| invalid-time | Expiry, issue tolerance, lifetime, observation, evidence or withdrawal time relationships fail. |
| invalid-signature | Ed25519 signature does not verify over the exact domain-separated message, including unusable key material. |
| untrusted-key | Payload/envelope/trust key or catalogue namespaces disagree. |
| sequence-out-of-range | Sequence is outside the injected key's inclusive range. |
| retired-key | Injected trust marks the key retired. |
| rollback | Payload sequence is below the previous checkpoint. |
| equivocation | Equal sequence has a different exact payload-byte digest. |
| bootstrap-required | previous is null and bootstrap is false. |
| bootstrap-conflict | bootstrap is true while previous is non-null. |

Refusals return rather than throw. Multi-defect reason precedence is not a public contract. No partial payload/checkpoint is returned on refusal.

Previous null requires explicit bootstrap true. Subsequent calls require bootstrap false and previous exactly `{catalogueID,sequence,payloadSHA256}` with valid matching namespace, positive safe sequence and digest. Lower sequence refuses; equal sequence/different bytes refuses; equal sequence/identical bytes is duplicate with the same checkpoint value. Higher sequence advances only after every signature, trust, schema, client and time check. Duplicates must pass all those checks too. Checkpoints are values only: no persistence, authenticated recovery, concurrency/CAS or durable anti-rollback exists. Replacing caller history and trust/bootstrap can forge continuity.

`compareVersions(left,right)` returns exactly `{status:'compared',order:-1|0|1}` for valid version strings, or `{status:'refused',reason:'invalid-version'}`. Missing trailing components compare as zero, so `1` and `1.0` compare equal while remaining separate signed strings. Invalid inputs never compare equal, even to themselves. There is no coercion or universal vendor-version claim.

`encodePayload(payload)` is fixture-only: validate closed shape, integer values, ordering and intrinsic temporal relationships, then return Uint8Array-compatible bytes with recursively lexicographically sorted keys, stable array order, compact UTF8 and no whitespace. Invalid data throws TypeError. It never signs, chooses now, supplies trust/history or sorts release arrays to repair them. Deterministic encoding is not required of every valid signed input. An encoded payload does not confer authority.

## Verification evidence and limits

Four immutable Node-generated golden vectors cover empty, one-entry, withdrawal-only and signed-whitespace payloads. Fixed private test material exists only under the fixture directory and is read by test code. Production modules contain no private-key signing, I/O, eval, process execution, network or installer path. Swift reproduces the exact key, message and hash and verifies deterministic Node golden signatures. Node independently verifies Swift-generated signatures. Both directions check wrong key/domain/tamper refusals.

[Apple documents CryptoKit signature randomisation](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/signature(for:)) for side-channel protection. Signature-byte equality between Swift and Node is not asserted. The initial failed equality assumption and bounded probe are retained in private Phase A evidence. Swift is a crypto-vector check only, not an independent full-schema verifier or consumer.

The parent observed runnable Phase A assertion red and froze the checks/vectors before implementation. CHECK-MODIFIED: during Phase B one test-harness defect required explicit parent correction and re-freeze: structuredClone converts Buffer to Uint8Array, so comparing an unchanged input directly to its clone falsely reported mutation. The corrected check retains the original byte-object identity and compares two cloned value snapshots. No signature, schema, positive/refusal expectation or golden vector changed in that correction.

The frozen v1 manifest checks24 original source, fixture, check and build files. Passing the local focused suite is not parent final acceptance, full-gate/CI success, release readiness or installed proof. Real signing custody, app-distributed trust, authenticated persistence, hosted integration, native inspection, installation, public support and publication remain separate work and authority.

Separate additive hostname-boundary checks run with `node --test services/catalogue/tests/catalogue-protocol-boundaries.test.mjs`. They exercise both source URL and redirectHosts refusal for `example.123` and successful fixture verification for a conventional DNS hostname. They do not alter the frozen focused gate or its647 cases.

PAT-2621 remains active for unexplained activation proof refusals. The inherited main revision `27be57fec44920afba0a0ea2238c236442eeb908` had merged-main CI fail in the unchanged 173-case activation suite with two `proofRefused` cases and retained diagnostics; PAT-2622 was then In Review. Catalogue focused success or a subsequent local full-gate pass does not resolve the activation incident or prove main CI green. Shared gate wiring preserves fail-fast behavior: if activation fails, later catalogue commands are not reached, and the failure must be retained rather than rerun until green.

## Fixture-only support request v1 (PAT-2624 C1b)

`support-request-v1.mjs` separately validates one bounded offline support-request record and deterministically encodes inert fixtures. The parent observed meaningful Phase A assertion failures, accepted the exact API and froze the six schema/check/fixture/gate files before releasing implementation. Parent final acceptance, full-gate verification and independent review remain required. Run `./scripts/verify-support-request-protocol.sh` with existing Node >=22; its 740 checks are Node validation, not an independent Swift schema implementation.

Both APIs are pure synchronous functions and return refusals rather than throw for invalid caller input. Every result has exactly `status`, `reason`, `scope`, `requestSent`, `ownershipVerified`, `userConsentVerified`, `sourceApproved`, `requestSHA256` and one operation-specific data field:

- `decodeSupportRequest(requestBytes)` returns status `validated` or `refused` and `request`, a detached exact wire record or null. Success hashes the exact original bytes, including whitespace and escape spelling.
- `encodeSupportRequest(validatedRequest)` revalidates the exact wire record (for example, the decoder's `.request`, not its result wrapper), then returns status `encoded` or `refused` and `requestBytes`, detached Uint8Array bytes or null. Keys are recursively lexicographically sorted, strings preserved, JSON compact without whitespace and the hash binds those encoded bytes. No arrays are valid in this schema.

On success reason is null and data/hash are non-null. Every refusal has reason `invalid-request` and null data/hash, without echoing private input or exposing partial records. scope is always `fixture-only`; requestSent, ownershipVerified, userConsentVerified and sourceApproved are always false. Input and separate results never share mutable records or output bytes. A validated consent record, UUID or supplied provenance does not authenticate a user, session, ownership, native observation or actual consent. No request is sent and no privacy policy or service is activated.

Decode accepts Uint8Array/Buffer views up to 8192 bytes and copies intrinsic view bytes without reading caller byteLength/buffer/iterator/conversion hooks. Shared backing memory, detached views and Proxies refuse. The unchanged strict JSON parser uses depth 16 and rejects BOM, malformed UTF8/Unicode, duplicate decoded keys including escaped aliases, trailing data, signs/fractions/exponents and unsafe integers. Surrounding JSON whitespace is permitted within the byte ceiling. Encoding validates only exact own enumerable data fields on plain records (Object.prototype or null); accessors, symbols, hidden extras, custom prototypes, cycles, functions and Proxies refuse without invoking getters, Proxy traps, conversions or toJSON. Fixed schema traversal visits at most seven records at depth three, preflights bounded strings and never serialises arbitrary caller objects. This is not a sandbox against a modified JavaScript host environment.

The root has exactly `{schema,clientRequestID,submittedAt,app,notes,consent}`. Schema is `fixture-support-request-v1`; clientRequestID is canonical lowercase UUIDv4 with variant 8/9/a/b, used for correlation only. submittedAt and both consent times are nonnegative safe-integer Unix seconds. Negative zero also refuses on object input. Times satisfy presentedAt <= acceptedAt <= submittedAt; no real clock is consulted.

app has exactly `{displayName,bundleID,version,vendorURL}`. Each non-null observation has exactly `{value,provenance}`. displayName is required; the other observations must be present and may be explicit null. displayName/version values contain 1..128 Unicode scalars and at most 512 UTF8 bytes, without C0/C1 controls. Versions remain arbitrary descriptive strings, not supported comparators. bundleID has at least two nonempty dot-separated ASCII letter/digit/hyphen components, at most 255 bytes. Their provenance is `locallyObserved` or `userSupplied`. vendorURL allows only `userSupplied`; caller claims of `independentlyVerified` refuse everywhere.

vendorURL is at most 2048 UTF8 bytes, with literal lowercase `https://`, lowercase DNS authority and optional canonical decimal port 1..65535. DNS labels are 1..63 ASCII alphanumeric/hyphen characters without edge hyphens; the whole host is at most 253 characters. Exact WHATWG hostname preservation is required. IP literals, numeric-final-label IPv4 candidates, userinfo, query (even empty), fragment, whitespace, C0/C1 controls, backslash, encoded hostname, trailing-dot host and authority repair refuse. Literal/percent-encoded dot path segments (`.`, `..` and case-insensitive percent-dot combinations) refuse. Empty paths, explicit `:443`, ordinary Unicode/percent path text, repeated slashes and path `@` remain permitted and retain their exact spelling. The URL object's serialisation never becomes the outgoing record. This is an inert local grammar, not global URL validity, DNS resolution, fetch/SSRF protection or source approval.

notes is null or literal text of at most 1000 Unicode scalars and 2048 UTF8 bytes. Empty text, LF and tab are permitted; other C0/C1 controls including CR refuse. Markup and quotes remain unrendered text. consent has exactly `{schema,purpose,destination,presentedAt,acceptedAt}`, with `fixture-support-consent-v1`, `coverage-research` and `patched-catalogue-support` respectively. Unknown fields at every level refuse, including attachments, paths, username, inventory, licence/device/account/email IDs, logs and paid/trial fields. Allowed name, notes or URL path text can still contain personal information; validation does not claim anonymisation or rendering safety.

`support-request-v1.schema.json` is descriptive draft 2020-12 documentation; no schema engine is introduced. Code also enforces lexical JSON/number rules, byte/scalar limits, URL restrictions and ordered times. Fixed minimum/observed records and exact UTF8/SHA256 goldens live under `fixtures/support-request-v1`. Actual outgoing preview/redaction, retention disclosure, cancel/submit gesture, verified household session, retention/status/idempotency/abuse policy and real request submission remain future integrations. Proposed retention durations and Published status proof are not activated by this contract.

## Fixture-only inspection job and unsigned observations v2 (PAT-2626 C1c)

`job-v2.mjs` and `evidence-v2.mjs` implement standalone inert local formats. These records are caller claims, not an authenticated production job/report protocol. The parent observed Phase A's 2,757 runnable checks, including 163 meaningful positive assertion failures against refusing modules, accepted the exact refinements and froze seven schema/check/fixture/gate files before releasing Phase B. Run `bash scripts/verify-inspection-protocol.sh` using installed Node >=22. Parent final acceptance, integrated full native gate, independent review and CI remain separate requirements. This slice neither resolves the activation incident nor completes production C1 or C2–C10.

The synchronous APIs return typed refusals for invalid caller input. Every result, including refusal, has `scope:'fixture-only'` and `authenticated`, `policyAccepted`, `freshOSValidation`, `publicationAllowed`, `installationAllowed` permanently false. Exact additional result keys are:

- `decodeJobV2(bytes)`: `{status:'valid',job,byteDigest}` or `{status:'invalid',reason:'invalid-job'}`.
- `encodeJobV2(record)`: `{status:'encoded',bytes,byteDigest}` or `{status:'refused',reason:'invalid-job'}`.
- `decodeEvidenceV2(bytes)`: `{status:'valid',report,byteDigest}` or `{status:'invalid',reason:'invalid-evidence'}`.
- `encodeEvidenceV2(record)`: `{status:'encoded',bytes,byteDigest}` or `{status:'refused',reason:'invalid-evidence'}`.
- `compareEvidenceBinding(jobBytes,reportBytes)`: `{status:'matched'}` or `{status:'refused',reason:'binding-mismatch'}`.

Success omits reason; refusal omits data and digest. Returned records and byte arrays are fresh and do not alias caller data or another result. Decoder byteDigest is SHA-256 of the exact original input view, including whitespace and escape spelling. Encoder byteDigest hashes its compact UTF8 JSON, with the field order below, no trailing newline and no normalisation of strings.

Input bytes must be Uint8Array or Buffer, including Uint8Array subclasses. Intrinsic view access and copying bypass caller getters, iterators, species and conversion hooks. Proxies, revoked Proxies, SharedArrayBuffer backing, detached buffers and non-byte views refuse. The raw input limit is 65,536 bytes inclusive, including surrounding JSON whitespace. The unchanged strict JSON parser enforces UTF8 without BOM, depth 16, no duplicate decoded keys or lone surrogates, and nonnegative safe integer tokens without signs, fractions or exponents. Encoder negative zero also refuses. Encoder traversal accepts only exact own enumerable data-property plain/null-prototype records and ordinary dense arrays. Accessors, custom prototypes/classes, symbols, hidden/unknown keys, holes, Proxies and cycles refuse without callbacks or coercion. Bounded fixed-shape traversal constructs fresh primitive-only records before serialisation. This is not a sandbox against a modified JavaScript host environment.

Job fields, in encoder order, are `{schema:2,kind:'inspection-job',jobID,routeID,routeDigest,policyVersion,policyDigest,checkerVersion,checkerSourceSHA,architecture,sourceURL,artifact}`. jobID is lowercase hexadecimal UUID shape 8-4-4-4-12, without a version or variant requirement. routeID and version identifiers match `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`. Digests are 64 lowercase hexadecimal characters; checkerSourceSHA is 40. architecture is `arm64` or `x86_64`. artifact is exactly `{sha256,length}`, with length 1..1,099,511,627,776 bytes. All records are closed; commands, scripts, arguments, paths, buckets, keys, leases, credentials, approval fields and artifact blobs are absent. A route ID or pinned digest establishes no approved route or artifact receipt.

Evidence fields, in encoder order, are `{schema:2,kind:'inspection-observations',jobID,jobDescriptorSHA256,routeID,routeDigest,policyVersion,policyDigest,checkerVersion,checkerSourceSHA,architecture,artifact,finalSourceURL,osVersion,osBuild,startedAt,finishedAt,observations}`. Shared fields use the job rules; OS version/build use the same identifier grammar. Times are nonnegative safe-integer seconds, with finishedAt >= startedAt and duration <=86,400. No clock is consulted and no freshness is accepted. observations has exactly six records, once each in this order: `codesign-integrity`, `codesign-identity`, `gatekeeper`, `notarisation`, `container-integrity`, `cleanup`.

Each observation is exactly `{checkID,outcome,exitCode,signal,stdout,stderr}`. outcome is `completed` or `unavailable`; completed requires exactly one non-null exitCode (0..255) or signal (1..64). Unavailable requires both null and empty stdout/stderr descriptors. Every descriptor is exactly `{sha256,length}`, with length 0..1,048,576. Any zero length, including completed observations, requires the standard empty SHA-256. Nonzero output digests remain unverified claims. Failed exits, signals and unavailable observations remain valid typed data. Exit zero does not mean passed, approved or notarised. No command or output bytes are carried or executed.

Both URLs are literal `https://` ASCII strings of at most 2,048 bytes, preserving exact case, optional `:443`, ordinary percent paths and repeated slashes. Hostnames have alphanumeric label edges, labels 1..63 bytes, total <=253 and may have a single label. Refuse IP literals, including numeric spellings which the cached Node URL parser successfully interprets as IP addresses. The parser is only an IP-detection probe: otherwise permitted DNS-shaped strings such as `example.123` remain accepted when that probe throws. This grammar does not import the stricter C1a/C1b URL rules. Refuse userinfo, other ports, query, fragment, whitespace/control/non-ASCII characters, backslashes, malformed percent triplets, and path segments that become exactly `.` or `..` after case-insensitive `%2e` replacement. Other percent triplets remain literal, including encoded slash/control bytes; they are never decoded here. No global URL validity, DNS reachability, source approval, redirect approval, fetch or SSRF protection is established.

Binding decodes both inputs and compares the report's jobDescriptorSHA256 to the digest of the exact original job bytes, then compares jobID, routeID/digest, policyVersion/digest, checkerVersion/sourceSHA, architecture and artifact sha256/length individually. Whitespace-different job bytes require a different descriptor digest even when their decoded records are equal. Binding never re-encodes or mutates the inputs. Final URL may differ from the job URL; URL, OS, times and outcomes do not establish policy approval or actual runtime facts.

The two JSON Schemas are descriptive draft 2020-12 documents, with runtime-only byte/token/object/time/URL rules annotated; no schema engine or dependency is installed. Independent test-only producers supply literal byte/hash goldens under `fixtures/inspection-v2`. Schema validity, matching unsigned descriptors and passing local checks do not authenticate a worker or lease, verify artifact/output contents, establish command execution or current OS truth, provide fresh native validation, or allow installation or publication. No inspection, network access, signing, scheduling, service, authentication, storage, app composition or production integration is added.
