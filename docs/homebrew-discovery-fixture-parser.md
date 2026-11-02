# Inert Homebrew discovery parser

`services/catalogue/discovery/homebrew/metadata.mjs` exports
`parseHomebrewMetadata({bytes, receipt})`. It copies a full-span unshared
Uint8Array, parses exact response bytes with the unchanged strict JSON parser,
and validates the closed single-cask fixture projection. The returned source
contains the exact bytes, digest, retrieval receipt and unverified source claims.

`candidates.mjs` exports `deriveHomebrewCandidate({parsed, policy, variant,
clock, history, artifactObservation})`. It revalidates raw bytes and every parsed
field, independently supplied policy and explicit platform selection, and the
complete previous discovery result. Equal releases retain their first observation;
refetching cannot refresh a stale release. Changed bytes or bindings at equal
release hold. A greater numeric release links the prior source digest. History is
injected fixture continuity, without durable rollback protection or authenticated
policy. Receipt validators and declared generation remain claims.

Inputs are closed own-data trees. Proxies, accessors, aliases, cycles, exotic
prototypes, shared/detached/subarray/Buffer bytes and extra fields refuse. Limits
and the exact wire contract are in `Fixtures/HomebrewDiscovery/README.md`.
Unknown API fields, recipe semantics, dependencies, packages, query URLs,
redirects and universal architecture remain held. No Ruby, brew, filesystem,
network, process or clock-source operation is performed.

All results have synthetic-fixture-only scope. Source authentication, acquisition,
independent verification, publication, installation and ownership flags remain
false. Optional artifact observations compare injected digest claims only; artifact
SHA256 and byte length remain null. The parser does not attest acquisition or
native behaviour. No catalogue/job mapping, native consumer, installed ownership,
helper action or product release is provided. Common-contract acceptance under
PAT-2693 and separately scoped native/acquisition/installation proof remain holds.

Run `./scripts/verify-homebrew-discovery.sh` for the independent fixture checks.
A passing local gate establishes only this bounded pure model's behaviour.
