# Installed bundle signature observation

`InstalledBundleObserver.collect` accepts an exact compiled Firefox pin, a caller-held
bundle and executable, and bounded Info.plist bytes. It checks metadata, binds the
borrowed descriptors and current paths through the existing signature bundle binding,
collects once through the existing internal Security collector, then confirms the
binding and validates every returned signature field. It never closes borrowed
descriptors. There is no retry, path discovery, override or installation capability.
The mandatory injected collector is available only through Testing SPI and supplies
synthetic observations with no native authority. The diagnostic Testing overload
also requires an explicit diagnostic callback; the legacy overload supplies a fixed
refusing diagnostic. Neither adapter falls back to native Security collection.

The disposable native app observer now records a nonoptional structured signature
observation and keeps its single Gatekeeper command, affirmative Notarized Developer
ID assessment, held-file Mach-O inspection and before/after manifests. Native report
acceptance requires the current nine-field app observation and the exact structured
signature, including nonboolean numeric flags/statuses and ordered valid timestamps.
The pure synthetic report projection alone retains historical eight-field app
observations and empty arrays; productive validation refuses those legacy shapes.
A signature does not establish Gatekeeper acceptance or installation authority.

These checks detect observed metadata, identity and tree changes. They do not lock out
another process with the same UID, prevent transient changes restored between reads,
or make the Security API path lookup atomic with held descriptors. Timestamp ordering
is consistency, not freshness or a recency bound. A synthetic pass is not installed or
guest native proof. Native execution, independent review and full verification remain
separate acceptance gates.

The unchanged collector checks the pinned requirement before reading signer identity.
Only when that collector invocation throws `signatureRejected`, the installed
observer confirms the held binding and runs a separate refusal-only Security
diagnostic. It uses the same strict, all-architecture and nested-code flags with a
nil requirement, reading signing information only after generic validity succeeds.
It confirms the binding again after either a diagnostic result or error, before
classifying anything. Changed bindings refuse as `unsafePath`.

Diagnostics require the exact path, flags, successful statuses and the same identifier
and present-team grammar as the pinned requirement. A missing team is valid diagnostic
data; a malformed present team or missing/malformed identifier refuses generically.
A valid missing/different team becomes `wrongTeam`, and a matching team with a valid
different identifier becomes `wrongBundle`. Matching identities, malformed data and
diagnostic errors remain `signatureRejected`. This path cannot return an accepted
observation, retry pinned validation or confer authority. Returned observations and
unrelated collector errors retain their existing handling.

This source repair leaves the pinned collector, frozen checks and guest cases
unchanged. Real ad hoc native refusal remains unverified; synthetic classification
checks cannot establish that native contract. Full verification and independent
correctness/security review remain separate acceptance gates.
