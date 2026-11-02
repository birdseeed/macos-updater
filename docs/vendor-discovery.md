# Bounded Sparkle and Electron discovery

PAT-2672 adds offline backend adapters under `services/catalogue/discovery/vendor`.
The accepted input contract and inert examples are in
[the fixture contract](../Fixtures/VendorDiscovery/README.md).

Sparkle accepts a deliberately small appcast subset and injected SUFeedURL.
Electron accepts literal generic-provider app-update.yml and latest-mac.yml.
Unsupported formats, ambiguous identity, unknown version ordering, unexpected
redirects and changed bytes for the same release hold. Absent metadata remains
unknown; Squirrel routes require app-specific evidence. The offline adapters
perform no installed-app scan, vendor lookup, scheduled retrieval or
vendor-setting change.

Candidates match explicit injected product, bundle, developer, channel, edition,
architecture and OS policy. They carry hash-bound fixture-only scope and cannot
authorise verification, publication or installation. Artifact checking compares
injected consistency only. Sparkle signature syntax is not signature validation;
native signature, notarisation, signed catalogue and installation trust gates
remain independently required. Same-size tampering plus forged injected verdicts
cannot establish native trust. Existing Installomator-specific contracts remain
unchanged. Official Cask metadata is permitted as data-only discovery under PAT-2654, with no customer Homebrew dependency. PAT-2674 separately owns optional explicit manual per-app actions through an existing Homebrew installation as its owning user, preserving ownership and excluding Update all, unattended scheduling and privileged-helper execution. This is the 12 October owner boundary, not implemented vendor-adapter behaviour.

The PAT-2693 acquisition decision records the accepted PR #82 design direction for URL, identity, architecture and comparator handling; exact versioned contracts and vectors still require engineering acceptance and review. The future acquisition benchmark is unmeasured and supplies no execution authority.

Run `./scripts/verify-vendor-discovery.sh` for the independent parser, candidate,
mutation and refusal checks. The full sequential `./scripts/verify.sh` includes
this gate. Parent-observed refusing-stub RED preceded implementation; the frozen
62-case gate passed round 2 with no failures, cancellations or skips. Local checks
do not establish independent review, merged/main CI, operating discovery or native
app integration. Those states must be read from the ticket's delivery evidence.

Supplemental independent Electron checks exercise both metadata byte paths and
literal root/subdirectory feed addresses with or without a terminal slash. The
parent observed two address-resolution failures before releasing their repair.
Generic directory resolution follows pinned upstream v26.0.12
[newBaseUrl](https://github.com/electron-userland/electron-builder/blob/v26.0.12/packages/electron-updater/src/util.ts)
and [GenericProvider](https://github.com/electron-userland/electron-builder/blob/v26.0.12/packages/electron-updater/src/providers/GenericProvider.ts).
Unsupported XML entities and non-triple OS versions remain held under the
accepted fixed subset; this is limited discovery coverage. Review outcomes and
the supplemental/full-gate results must be recorded separately from native proof.
After the address repair, the full local gate passed round 4, including the
original 62 cases and all eight supplemental cases, with no failures or skips.

The read-only `LocalApplicationInventory` source now observes installed vendor
claims within its existing descriptor-bound inventory window. It retains a
literal HTTPS `SUFeedURL` string of at most 2048 UTF8 bytes, rejecting missing
hosts, credentials, fragments, controls and invalid syntax without changing
independent application identity. It reads only
`Contents/Resources/app-update.yml`: a no-follow, singly linked regular file
of at most 65,536 bytes. Valid UTF8 bytes, including comments and line endings,
are retained exactly; NUL, invalid UTF8, oversized and unsafe files are refused
or malformed. Optional absence remains unavailable without an extra issue.
Config read reservations share the inventory's 16 MiB metadata budget even
when a reserved read fails or is partial. File and directory descriptor/name
identity, size, mode, link count and timestamps are confirmed around reads.

Config-only refusal preserves valid independent feed and application claims;
a changed plist or enclosing inventory namespace invalidates all observed
claims. These observations grant no verification, publication or installation
authority. They do not connect the offline candidate adapters or fetch feeds.
This source description alone establishes no passing verification or native
system-owned application parity; reported local check results appear below
and remain separate from guest extraction proof.

The separate `discoverInstalledVendorCandidate(input)` seam now hands an
explicitly injected `installed-vendor-fixture-v1` projection to the unchanged
offline parsers and candidate policy. Its closed ordinary record contains
`schemaVersion`, `adapter`, `observation`, `source`, `context`, `route`,
`redirects` and `previous`. Observation contains only application disposition,
nullable claimed bundle/short/build strings and the four vendor fields
`sparkleFeedURL`, `electronConfigBytes`, `sparkleDisposition` and
`electronDisposition`. Source contains only final `feedURL`, raw `feedBytes`
and `configSha256`. Unknown/missing/symbol/accessor fields and custom record
prototypes refuse before field access. This is a caller-built fixture contract,
not a Swift serialisation format or a live scanner bridge.

Honest unavailable application or selected adapter metadata returns `unknown`
with no candidate. Malformed/refused dispositions, contradictory observed null
claims and invalid inputs hold. Observed bundle identity must equal independently
supplied context. Sparkle compares the claimed machine build exactly with the
context baseline; Electron compares the claimed short stable semver. Neither
substitutes the other version claim. Product, developer, channel, edition,
architecture and OS remain independently supplied candidate-policy inputs.

Sparkle's observed feed URL must exactly equal the route start. Its parser hashes
the raw injected feed and records the final source URL. Electron requires the
SHA256 of the exact observed config bytes to equal the explicit source digest;
its existing generic-provider parser derives the original feed route. Only after
that route matches does the handoff set the detached parser result's feed
location to the injected final source URL. The unchanged candidate machinery
validates the approved contiguous redirect chain from the original route to
that final location, artifact policy, identity, versions and any previous
candidate. No redirect performs a fetch or grants network authority.

Raw inputs accept ordinary unshared Uint8Array/Buffer values with byte indices
only, detached before parsing; paths, text pointers, shared buffers, custom byte
prototypes/properties and shadowed byte accessors refuse. Existing bounds remain:
65,536 bytes per metadata value, 512 text lines, XML depth 8, at most 16 appcast
items and three redirect hops, 2048 UTF8 bytes per URL, 128 per identity claim
and 64 per version claim. The existing parsers retain their fixed XML/literal
generic YAML subsets, HTTPS DNS-only URL restrictions and unsupported-format
refusals; this seam does not broaden them. Results retain exactly the existing
detached candidate/result shape, `fixture-only` scope and false verification,
installation and publication flags on every path.

The parent observed all 52 handoff checks and all 114 vendor checks passing
locally with pinned Node 24, after the earlier extraction gate passed 133 checks
with zero failures. The portable vendor command is
`./scripts/verify-vendor-discovery.sh`. These local results establish no actual
native application, system/home-owned parity, account/service behaviour,
installed update or trust acceptance. The full integration gate, final
independent correctness/security review and required CI remain pending.
Historical failed rounds remain sealed; this addition resets no repair cap.
Publication and any native, installation or release proof remain separate
evidence and authority gates.


PAT-2732 extends that same native inventory record with optional
`productJSONBytes` and `productJSONDisposition`. Only the fixed relative path
`Contents/Resources/app/product.json` is read. Its unparsed bytes use the existing
no-follow descriptor/name/ancestor confirmations, regular single-link requirement,
65,536-byte bound and shared 16 MiB plist/config/product reservation budget.
Failed reserved reads retain their budget charge. Missing optional metadata stays
unavailable; unsafe or changed files refuse, and oversized, invalid UTF8 or NUL
bytes are malformed. Product-only failures preserve independent plist and Sparkle
claims. The Testing SPI `beforeProductMetadataRead(applicationPath:)` notification
occurs after opening/capturing the actual product descriptor and before reading
bytes; it supplies no outcome and is absent when no product file is opened.

`discoverInstalledVSCodeSource(input)` is a separate inert caller-built
`installed-vscode-source-fixture-v1` seam in the existing adapter module. It accepts
only closed own-data-property records and detached ordinary unshared byte views.
Independent context and source policy bind the synthetic `microsoft-vscode`,
`com.microsoft.VSCode`, `code`, stable, arm64 fixture subset to the exact literal
`https://update.code.visualstudio.com` endpoint. Required JSON fields are
`applicationName`, `darwinBundleIdentifier`, `updateUrl` and `quality`; optional
`channel` must equal stable. The `darwinUniversalAssetId` routing override is
unsupported whenever present, including null. Unrelated inert fields are allowed.
The existing bounded strict JSON parser rejects duplicate decoded keys at every
depth, BOM, malformed UTF8, lone surrogates and numeric forms outside nonnegative
safe integers, with maximum depth 16. The existing metadata text bound is 512 lines.
Decoded control characters in keys or strings refuse. Unsupported syntax remains
unsupported rather than being normalised into an accepted source.

Success returns only a detached `source-claim` with the SHA256 of the exact raw
metadata bytes. Unavailable observation returns `unknown`; malformed, refused,
unsupported or incoherent inputs return `unsupported` with an explicit reason.
Every result retains `candidate: null`, `fixture-only` scope and false verification,
installation and publication flags. This does not extend the existing four-field
`installed-vendor-fixture-v1` schema or change Sparkle/Electron candidates. Squirrel
still requires `app-specific-vendor-route-required`; no universal Squirrel support
is inferred.

The native architecture here is an injected expected fixture context, not verified
artifact compatibility. These synthetic bytes are no real branded vendor corpus,
installed metadata parity or productive app bridge. No feed fetch, updater/script
execution, vendor-state change, upload, installation or trust promotion is added.
PAT-2693 continues to own source-to-job/catalogue mapping. Source implementation
alone is no check pass, independent review, native proof, publication or release.
