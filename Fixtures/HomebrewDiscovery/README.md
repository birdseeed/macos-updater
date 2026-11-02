# Synthetic Homebrew discovery contract, Phase A

All identities, hashes, URLs, clock values and JSON here are invented fixture data.
No artifact bytes were acquired. No real app, Homebrew receipt, developer identity,
source authentication, installed state, native result or publication is proved.
The [official API documentation](https://formulae.brew.sh/docs/api/) was consulted
for field names only. No live response is a test input. This is a versioned narrow
projection, not a claim to support every current Cask API record.

The Phase A sources are compiling, always-refusing stubs. Positive tests must fail
with assertion failures before the parent freezes checks and releases implementation.
Only the new Node group is run. Existing strict JSON, schemas, adapters, tests,
dependencies and full gate stay unchanged. Reuse the unchanged strict JSON parser
if compatible; its nonnegative safe-integer subset is deliberately conservative.

## Closed input contracts

Both APIs accept one argument, a plain own-data record, and return a fresh plain
data tree. All nested input records/arrays must use ordinary or null prototypes,
enumerable own data descriptors, no symbols, extra keys, cycles, shared references,
accessors, Proxy objects or exotic prototypes. Inspect descriptors before reading
values; never invoke input getters, coercion, callbacks or proxy traps. Node's
`util.types.isProxy` may identify proxies before descriptor/prototype inspection.
Arrays have ordinary Array prototype and dense data elements. Input bytes must
be a genuine unshared full-span Uint8Array, copied on entry; reject pooled Buffers,
subarrays, detached/shared buffers, byte-object extra properties and proxies.
This is a conservative ownership limitation, not general Buffer support. A caller
can still mutate its own full-span bytes later; output must never alias them.

`parseHomebrewMetadata({bytes, receipt})`: receipt's exact keys are `locator`,
`startedAt`, `finishedAt`, `statusCode`, `etag`, `lastModified`, `generationTime`.
Times are nonnegative safe integer Unix seconds, start <= finish, status is 200;
304 is held. Validators are bounded strings or null, generationTime is integer or
null and cannot exceed finish. Locator must be the exact canonical HTTPS official
single-token endpoint (no query, fragment, userinfo, alternate port or escaping).
No injected locator/validator authenticates source or supplies generation time.

Parser success: `status:'parsed'`, `projectionVersion:'homebrew-single-cask-fixture-v1'`,
`record` (lossless parsed metadata), `source` and the common false flags below.
Source exact fields: `rawBytes` (fresh dense integer array), `sha256`, `byteLength`,
`locator`, `retrievalStartedAt`, `retrievalFinishedAt`, `etag`, `lastModified`,
`generationTime`, `tap`, `tapGitHead`, `rubySourcePath`, `rubySourceChecksum`.
Hash and length bind exact response bytes, not reserialised JSON. Preserve claims
and null generation honestly; no upstream authenticity is inferred.

Recognised top-level fields are those in simple-cask.json; checksum may be absent
or null. Optional name/desc/homepage/caveats are inert descriptions. Unknown keys
hold rather than silently extend installation support. Token/full_token agree;
tap is homebrew/cask. Source head is 40 lowercase hex; source path is exactly
`Casks/<first token letter>/<token>.rb`; source checksum has one lowercase SHA256.
Projection supports exactly one app artifact with one safe `.app` basename, no
target/move/options; all other artifact semantics hold. Dependencies must be empty,
conflicts absent/null, disabled/deprecated false. url_specs must be empty. A cask
may have variations with keys `[arm64|x86_64]_[sequoia|sonoma|ventura|tahoe]`, each
overriding only `url` and/or `sha256`. Selection is always explicit; never infer
an architecture/OS from a download name. Unknown variations/override fields hold.
No recipe hooks, package/suite/script/language/generated semantics are supported.

Bounds: 262144 response bytes, depth16, one object (no bulk arrays/wrappers),
64 total artifact/dependency records across base and all variants, 2048 UTF8
bytes per URL, 128 UTF8 bytes per identity/token. Reject duplicate JSON keys,
invalid Unicode/UTF8, malformed/noninteger/unsafe numeric tokens before projection.

`deriveHomebrewCandidate({parsed, policy, variant, clock, history, artifactObservation})`:
context.json defines exact keys. Policy independently binds source, product,
bundle, expected Team ID, stable channel, edition, paid generation, comparator,
exact URLs and redirect list, OS bounds, architectures, app path and supported
installer. Policy/route digests are injected fixture bindings, not signed policy.
Variant includes the requested independent identity and comparator; every value
must agree with policy. Only `numeric-dotted-v1` and canonical 1-4 numeric version
components are admitted; raw comma/build/latest versions are retained by parsing
but held by candidate derivation. No suffix stripping or guessed bundle mapping.
OS is a canonical numeric version in the independently admitted inclusive range.
Nonempty variations require an existing explicit variant key matching architecture
and OS family; base requires no variations. Universal claims remain held without
independent executable-slice evidence (not implemented here).

Candidate revalidates parsed raw/projection/source binding and complete previous
candidate, not trusting a caller-supplied status or digest. `clock:{now}` must be
injected; no Date.now. Future or >86400-second observations hold. History is
`{previous:null|discoveryResult}`. Same release identity with any source bytes,
revision/checksum/URL/variant/policy binding change holds; previous state is never
overwritten. Duplicate bytes preserve firstObservedAt and generationTime even
after a later receipt. A stale original observation cannot be refreshed by refetch.
Malformed, future, foreign or newer-version history holds. New greater canonical
versions may produce discovery with linked prior digest. Injected history is
fixture continuity only, never durable anti-rollback.

Success: `status:'discovery'`, `projectionVersion`, `source` copied from parsed,
`identity` copied from policy, `release:{version,comparator}`, `selection` copied
from variant, `checksum:{state:'digest'|'no-check'|'absent',value:string|null}`,
`artifact:{url,sha256:null,byteLength:null}`,
`continuity:{firstObservedAt,previousSourceSHA256:null|string}`,
`policyBinding:{policySha256,routeSha256}`,
`requiresIndependentArtifactValidation:true`,
`artifactConsistency:'unchecked'|'injected-claim-consistent'` plus false flags.
No independent artifact or job/catalogue fields are fabricated.

artifactObservation is null or exact `{sha256,byteLength}` (positive safe length).
It is only an untrusted injected comparison claim, never actual artifact bytes or
native verification. A digest mismatch holds with reason `artifact-digest-mismatch`;
matching digest yields injected-claim-consistent. Absent/no_check remains unchecked
even with a claim. Independently computed exact bytes/length/native checks remain
required in every case; artifact SHA/length above remain null.

All results include `scope:'synthetic-fixture-only'`, `sourceAuthenticated:false`,
`artifactAcquired:false`, `independentlyVerified:false`, `publicationAllowed:false`,
`installationAllowed:false`, `ownershipEstablished:false`. Held results have
`status:'held'` and a nonempty reason; no successful candidate or authority payload.
No process, network, filesystem scan, Ruby evaluation or existing Homebrew call is
allowed in source modules. Static import checks and runtime spies cover this
boundary. Reading synthetic fixtures happens only in tests.
