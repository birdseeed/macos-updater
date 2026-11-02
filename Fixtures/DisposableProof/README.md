# Disposable proof Phase A check contract

These inputs and checks are synthetic. No real Firefox bundle is copied, launched,
installed or assessed. The gate does not run a proof case in the guest.
All operational APIs currently throw notImplemented. A successful compiler is
required; expected Phase A failure is a named assertion, never a missing symbol.

The check target creates tiny files in exclusive mode-0700
patched-disposable-check-<UUID> roots directly under the nearest physical
.build ancestor of the kernel-reported check executable. The Testing SPI must
independently enforce that boundary. Its root is never runtime guest authority.
An existing synthetic fixture directory can be read as input by the SPI; it
cannot be adopted as a runtime run or case. Existing root creation refuses.

Manifest rules: UTF-8 byte-sorted relative paths, "." included; directory/file/
symlink types; exact permission mode, regular-file length and SHA-256, link text.
Directory and symlink lengths are zero and their content digest is empty.
The canonical digest input is UTF-8 "patched-disposable-manifest-v1" plus NUL,
then the entry count as unsigned 64-bit big-endian. Each entry has six fields:
path, type, decimal mode, decimal length, link text, lowercase file digest.
Each field is its UTF-8 byte length as unsigned 64-bit big-endian then exact bytes.
No newline delimiters or silent entry/byte truncation.
Normal symlink mode 0777 is descriptive; unsafe write modes apply to files and
directories. Dangling links refuse escapingLink; cycles refuse cyclicLink.
The manifest does not cover ACLs, xattrs, resource forks or quarantine; fresh
native checks separately assess signed copies at runtime.

Synthetic journal filename is journal.json; lock is journal.lock.
The closed schema in Support.swift binds run/case, uid, root device/inode,
guest digest, transaction ID, state, old/new identities, before/after manifest
digests, catalogue digest and artifact digest. Synthetic origin is mandatory in
the SPI and never accepted by runtime. Unknown/duplicate fields and malformed
values refuse, bindings must match physical metadata. Writes preserve exact
validated bytes, hold an exclusive flock, atomically replace through descriptors,
and require fsync plus F_FULLFSYNC without fallback. Probes only observe/refuse.

Synthetic recovery uses exactly Target and Retained directories. Their full
independent manifests and physical identities bind the journal. It must exercise
real descriptor-relative atomic exchange, preserve both whole bundles, record
rolledBack and resume an interrupted recovery. These operations cannot access
the live harness authority or produce an installed proof report.

Catalogue private seeds exist only in the check target's CatalogueFixtures.swift.
They are publicly known test bytes, never production trust. The trusted TEST
public key is derived from 32 bytes of 0x11, key ID patched-disposable-test-v1,
catalogue ID patched-disposable-firefox. The unrelated test signer uses 32 bytes
of 0x22. Envelopes use the unchanged PatchedCore Ed25519 domain and schema.
Synthetic checkpoint is Catalogue/checkpoint.json. Refusals must preserve its
exact SHA-256, including a valid signature over an unapproved artifact pin, so
pin policy must precede checkpoint acceptance. Runtime observes its own
time/OS/installed version.

The check executable's explicit --emit-current-catalogue-fixtures mode prints a
JSON map of base64 envelopes issued against the actual host clock: valid,
invalid-signature, untrusted-key, replayed-sequence and expired-catalogue.
The gate does not invoke that mode or transfer anything.

CLI accepts --target-id, --run-id, --case-root, --case, --explicit-trigger,
optional bounded --pause, and explicit recorded evidence input. Unknown and
duplicate flags refuse. Run ID is 1–64 ASCII alphanumeric or hyphen, starts
alphanumeric; .bootstrap-* is excluded. All target paths are derived.
The host-only gate packages native executable and toolchain-free wrapper under
.build/disposable-runtime. Bootstrap transfer and every guest action remain
parent-owned after acceptance and independent review.

Parent build provenance is a receipt bound to an independently measured binary
hash. It is not executable-observed source identity or an attestation, and does
not create authority. Runtime reports distinguish these facts.

Limits: same-user malicious rewriting before capture or consistent rewriting
of state and bundles is not prevented. Successful flush calls are not hardware
or power-loss proof. Synthetic probes and layouts do not prove real process
death, live macOS validation, mount cleanup, or installed Firefox success.
