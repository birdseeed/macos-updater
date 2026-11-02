# Pinned signature validation source slice (PAT-2708)

Current artifact inspection uses schema 3. The internal collector constructs an
Apple generic anchor requirement with the exact catalogue Team ID in the leaf
certificate's subject OU and the exact signing identifier. Team IDs must be ten
uppercase ASCII letters or digits. Identifiers must be 1–255 ASCII bytes, use
only letters, digits, hyphens and periods, and have at least two nonempty
components. This grammar prevents requirement-language injection.

The collector creates a static code object for the app, compiles the requirement,
validates that object against it, then copies structured signing information from
the validated object. It requires successful OSStatus returns and nonnil outputs,
including typed Team ID and identifier fields matching the pin. Named Security
flags require strict validation, all main-executable architectures and nested
code (combined value 25). Executable and resource validation remain enabled.
The top-level identity requirement applies to main-executable slices; nested
components retain their own signed requirements. The observation records actual
validation and signing-information statuses, rather than inferred command text.

These calls occur while the existing inspector holds the bundle and executable
descriptors inside its private read-only mount of the digest- and length-verified
staged image. Held executable architecture parsing, exact bundle metadata,
version, pin, path, read-only mount and cleanup checks remain required. Signature
validation remains valid only while those bytes remain unchanged. Before and
after native signature collection, and after the subsequent command loop before
evidence construction, the inspector rechecks the captured bundle and executable
bindings, exact bounded plist bytes, held-descriptor read-only state and current
mount membership. Binding checks compare device, inode, mode, owner, group, link
count, size and modification/change timestamps including nanoseconds, using
nofollow path walks and the original borrowed descriptors. These repeated checks
detect observed changes; they do not provide atomic exclusion of hostile
same-user changes or prove that a path was never changed and restored between
checks. The identity-only Testing SPI supplies no signature validation authority.

Schema 3 requires the historical seven root fields plus schemaVersion,
architectureObservation and signatureObservation. The signature object has
exactly appPath, requirement, validationFlags, validationStatus,
signingInformationStatus, teamID, identifier, startedAt and finishedAt. Replay
rejects duplicate, unknown, missing, null and wrongly typed fields. Assessment
binds the observation's app path, independently rebuilt requirement, flags,
statuses, identity and ordered timestamps to the selected pin and evidence.

The only four current command observations are imageVerify, gatekeeper,
containerSignature and containerGatekeeper. App signature and signing identity
are obtained through Security APIs. App acceptance still requires affirmative
Gatekeeper output with source=Notarized Developer ID, independently of the
signature requirement; there is no additional notarized requirement term or
mandatory stapled-ticket check. Container signature and Gatekeeper results stay
independent, including raw nonzero failures. containerTicketPassed stays false.

Unversioned schema 1 and schema 2 remain fixture/replay imports with their
historical command tables and acceptance semantics. Both refuse internal live
origin and reject a signatureObservation. Schema 3 fixture/replay positives also
remain imported evidence: they grant neither fresh OS validation nor installation
authority. Only the internal actual collector supplies the live inspection path;
there is no public caller-selected live origin or successful OS test seam.

## Verification and remaining proof

The focused source gate is scripts/verify-pinned-signature.sh and the complete
gate is scripts/verify.sh. Synthetic checks exercise assessment and strict replay;
the source guard supplements them with lexical native-call bindings. Neither is
native execution proof. The exact additive LiveCatalogueProof assertions require
schema 3 and the structured observation when that separately authorised proof is
run; changing those assertions does not execute the proof.

The collected development headers are from macOS SDK 27.0. A successful build
using that SDK with the package's macOS 13 deployment target would demonstrate
Swift importer and compilation compatibility, not runtime validation on macOS 13
or any other supported OS. This source document claims no build or test result.
Actual API behavior, genuine unchanged vendor acceptance and refusals, clean-Mac
behavior and supported runtime versions require separately authorised evidence.

The dormant native installed/helper observer is not migrated in this slice.
Future installed work must reuse this exact pinned requirement, full validation
flags and structured signing-information policy while preserving its existing
current/retained-old held-tree, manifest, journal, architecture and recovery
bindings. It must supply exact source/binary/target/OS provenance and genuine
native acceptance and refusal evidence before claiming installed equivalence.
No app/helper installation, launch, signing, vendor mutation, productive authority
or client release is implemented or established here.
