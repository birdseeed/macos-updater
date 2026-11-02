# Private coverage wire fixtures, Phase A

PAT-2655 first pure codec source attempt. These synthetic literals and checks
exercise only closed report/deletion validation. Phase A exports four refusing
stubs; no implementation is released until the parent observes meaningful red,
accepts this interface and freezes every check/fixture. The parent owns the one
Node gate registration, actual verification, review and commits. No tests were
run during preparation.

The frozen API consists solely of synchronous functions:

- `encodeCoverageReport(value)` and `encodeCoverageDeletion(value)`
- `decodeCoverageReport(bytes)` and `decodeCoverageDeletion(bytes)`

Every call returns exactly `status`, `reason`, `value`, `bytes`, `sha256`,
`scope`, `requestSent`, `userConsentVerified`, `inventoryVerified`,
`sourceApproved`, `deletionPerformed`, `cataloguePublished`. Successful encoders
use `status: 'encoded'`; decoders use `status: 'validated'`. Successful `reason`
is null, `value` is a fresh primitive-data copy, `bytes` is a fresh Uint8Array
snapshot, and `sha256` is its lowercase SHA-256. Refusals always use
`status: 'refused', reason: 'invalid-coverage'` and null value/bytes/hash, without
throwing, logging or echoing data. Scope is always `fixture-only` and all six
flags are always false. Phase A always returns this refusal for every input.
A bytes/hash pair describes the initial returned snapshot; callers must
independently revalidate any future handoff after mutation.

Report records contain exactly schema `coverage-report-v1`, canonical lowercase
UUIDv4 reportID, disclosureVersion integer 1, and dense ordinary apps array of
1 through 10 exact records. App fields are bundleID, displayName, version.
Bundle IDs are 3 through 255 ASCII bytes with at least two nonempty dot-separated
components of letters, digits or hyphens. Identity is exact case-sensitive ID;
duplicates refuse even with different names/versions. Encode sorts a copy by
ASCII bundleID. Decode requires canonical order. Name and non-null version are
1 through 128 well-formed Unicode scalars, at most 256 UTF16 units and 512 UTF8
bytes. Version may be null. No normalisation or interpretation occurs.
C0/C1 controls, slash/backslash, nonspace tokens containing `@`, and any
`[A-Za-z][A-Za-z0-9+.-]*:` scheme-shaped substring refuse. These conservative
technical screens may falsely refuse valid text and cannot prove privacy.
Allowed markup, quotes, combining text and braces remain inert exact strings.

Deletion contains exactly canonical lowercase UUIDv4 reportID and 64 lowercase
hex deletionSecret. Its syntax confers no actual capability/authentication,
existence, consent or deletion proof. No secret generation/hashing protocol,
header, admission, service response or constant-time authorisation is included.

Canonical bytes use recursively sorted keys, compact JSON and no newline.
Report input is bounded to 16,384 bytes; deletion to 512 bytes. Unknown/missing
fields, duplicate decoded keys, noncanonical numbers/key order/escapes/spacing,
BOM, malformed UTF8/Unicode and depth over four refuse. Reuse the unchanged
strict-json parser with maximumDepth **16**, the only value it accepts. A
separate bounded, quote/escape-aware byte preflight must reject container depth
over four before calling it. This preflight counts braces/brackets only outside
strings and is not an alternative parser. Never weaken the old parser.

Encoders accept only ordinary or null-prototype records with exact own
enumerable data descriptors; arrays must be ordinary, dense, undecorated and
bounded before traversal. Proxies (including revoked), getters, symbols,
inherited extras, class instances, boxed primitives, toJSON/coercion hooks,
sparse/decorated/subclass arrays refuse without invoking user code. Decoders
accept genuine Uint8Array/Buffer views using intrinsic bounds and copying before
parse. Proxies, shared backing, non-byte views, detached buffers, subclasses
with hooks and decorated getter/coercion views refuse without invoking hooks.
No arbitrary callback may reach JSON stringification.

`report-minimal.json`, `report-unicode.json`, `report-ten.json`, and
`deletion.json` are literal canonical bytes, independently authored, without a
trailing newline. `literal-digests.json` records their independently computed
lengths/SHA256 plus the unchanged strict parser's SHA256. Tests never obtain
expected bytes from the implementation. Boundary positives construct bytes
from a fixed independent field layout and test-owned primitive strings.

The setup control checks literal hashes/lengths/parser acceptance and parser
refusals independently of stubs. Positive encode/decode, detachment, sorting,
null-prototype and string/ID boundaries must meaningfully fail against Phase A.
Refusal checks cover closed shapes/privacy/types/counts/identity, canonical
wire/UTF8/depth/numbers, and hostile records/arrays/byte views with zero hook
calls. Synthetic global sink controls exercise no-send/log/timer/random paths.
These observations establish no transport, native inventory/gesture,
consent/retention policy, service/provider/customer operation, catalogue
publication, deployment or release. Existing support codecs/fixtures and every
other baseline byte/mode remain outside this change.
