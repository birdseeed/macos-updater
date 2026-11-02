# PAT-2672 inert vendor-discovery Phase A contract

Preparation only. All application metadata, route policies, source observations,
artifact bytes and verdicts are injected fixture data. Nothing fetches a feed,
scans an installed app, runs updater/recipe/script, verifies native trust or
publishes/installs. The zero-filled Sparkle signature is intentionally a claim,
not a valid signature or production key. The artifact is literal inert text.

Primary format references checked 14 October 2026:
- https://sparkle-project.org/documentation/publishing/
- https://www.electron.build/v26/docs/features/auto-update/

The current main electron-builder documentation describes unreleased v27.
This subset intentionally uses v26 generic-provider metadata. Dynamic/custom,
private, legacy JSON-only, staged, signed-manifest and other unsupported forms
hold. This is no universal Sparkle/Electron parser or framework support claim.

## Closed interfaces

`parseSparkle({feedURL,bytes,parserVersion})` and
`parseElectron({configBytes,feedBytes,parserVersion})` return exactly
`{status,reason,metadata,sourceDigests}`. Status is extracted or held; held has
null metadata/sourceDigests and a nonempty reason. Successful metadata is exactly
`{parserVersion,feedURL,version,displayVersion,artifactURL,artifactLength,
integrityClaim,channel,architecture,minOS,maxOS}`. Source digests are exactly
`{configSha256,feedSha256}`; Sparkle configSha256 is null. Missing optional
feed compatibility/channel fields are null, never invented observations.
Integrity is `{algorithm,value}`: ed25519 claim for Sparkle, sha512 for Electron.

Sparkle accepts the fixed RSS/channel/item shape in sparkle.xml, optional title,
display version/channel/hardware/min/max OS, one full ZIP/DMG enclosure, and the
canonical XML declaration only at the start. Whitespace and LF/CRLF are inert;
only five predefined XML entities may decode. Unknown namespaces/attributes,
DTD/custom entities, instructions other than the initial declaration, CDATA,
multiple items/enclosures, duplicate fields, delta/informational/paid-upgrade
forms, mixed content and malformed encoding hold. Sparkle machine version,
not display text, orders releases. SUFeedURL is an injected value only.

Electron accepts fixed literal YAML scalar keys and two-space indentation:
provider generic, HTTPS base url, optional channel latest; version; files with
one url/sha512/size entry; optional releaseDate and matching legacy path/sha512.
Feed URL is the base URL resolved to latest-mac.yml, without arbitrary query or
credential inheritance. ReleaseDate is inert ISO UTC text. Other scalars,
keys, multiple providers/files, aliases/anchors/tags, multiline values, comments,
staging, dynamic expressions and minimumSystemVersion hold. Electron's latter
field is a Darwin kernel version; this subset does not compare it to macOS.

`compareVendorVersions({comparator,left,right})` returns
`{status,order,reason}`. Compared order is -1/0/1; held order null. Sparkle
1–4 canonical integer components zero-pad for comparison. Electron stable
semver requires exactly three. Components <=2147483647; leading zeroes,
prerelease/build suffixes and unknown semantics hold.

`discoverVendorCandidate({adapter,metadata,context,route,redirects,previous})`
returns `{status,reason,candidate,scope,verificationAllowed,installationAllowed,
publicationAllowed}`. Metadata is the complete extracted parser result above.
Context exactly `{productId,bundleId,developerTeamId,channel,edition,architecture,
osVersion,baselineVersion}`. Route exactly `{routeId,policyVersion,identity,
comparator,feedURL,allowedRedirectURLs,artifactURLs,minOS,maxOS}`. Identity exactly
`{productId,bundleId,developerTeamId,channel,edition,architecture}`. All required
bindings are nonempty and exact; developer is ten uppercase ASCII alphanumerics.
Stable only; arm64 or universal; no x86/Rosetta inference. Route and context
architecture must agree. Numeric macOS triples compare within route bounds;
feed constraints, when present, must be consistent and satisfied as well.
Absent feed constraints use explicit independent route bindings, which remain
fixture policy and do not prove actual architecture, publisher or compatibility.
Missing/unknown route OS bounds hold. Baseline version is injected test context,
never uploaded real inventory. Equal/older releases hold, avoiding downgrades.

Candidate exactly `{candidateId,scope,routeId,policyVersion,adapter,parserVersion,
identity,version,displayVersion,artifactURL,artifactLength,integrityClaim,
sourceDigests,redirects}`. candidateId hashes canonical JSON of every remaining
field. Candidate scope is permanently fixture-only and hash-bound, including when
serialised independently of its result. Route/artifact URL matching is exact. All URLs absolute HTTPS, no
credentials/fragments/ambiguous authority/IP/private-shaped destinations.
Redirects exactly `{from,to}` form a contiguous <=3-hop chain from route.feedURL
to metadata.feedURL, each to listed in allowedRedirectURLs. String checking
proves neither DNS nor actual connected destination safety. No network occurs.

Status candidate has candidate/non-null, reason null. Unchanged returns exact
previous candidate with reason null. Held/unknown/vendor-updater return null
candidate and nonempty reason. Null metadata means unknown; adapter squirrel
means vendor-updater. Extracted malformed input means held. Previous candidate
is fully structurally/hash/route validated; same version with any changed
candidate/source binding holds. A later release may create a fresh candidate.
No persistence, authenticated continuity or anti-rollback is established.

`checkVendorArtifact({candidate,artifactBytes,observation})` returns exactly
`{status,reason,bindingSha256,scope,verificationAllowed,installationAllowed,
publicationAllowed}`. Observation exactly `{identity,version,signature,
notarisation,container,compatibility}`; verdicts passed/failed/unknown/unavailable.
Only all passed with matching identity/version and length, valid candidate
binding, and Electron recomputed sha512 yields fixture-consistent. Binding hash
covers candidateId, recomputed artifact SHA256/length and full observation.
Sparkle signature bytes are syntax-checked claims: no public key or actual
Ed25519/native signature verification occurs. Tampered bytes plus forged
injected verdicts cannot be detected as native trust by this fixture model.
Held has null binding/nonempty reason. All results permanently scope fixture-only
and all three authority flags false. This function advertises consistency only.

Bounds: 64KiB each config/feed, total128KiB, 512 lines, XML depth8/items16
(the admitted subset allows one unambiguous item), 3 redirects, URLs2048 UTF8
bytes, identity128 bytes, versions64 bytes, artifact1MiB. Validate ordinary
closed data records without invoking getters; no shared byte buffers. Detached
outputs cannot mutate inputs. Arbitrary in-process hostile Proxy code is not a
sandbox promise. No dependency, native target or existing check is changed.

No tests have run during preparation. Parent owns initial meaningful runnable
red, exact freeze, fresh implementation release, full verification, independent
NVIDIA review, CI and publication. Five official rounds including initial red;
no reset. Actual tool cost unknown; no purchase is made.
