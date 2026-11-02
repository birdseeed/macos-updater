# Phase A exact proposed pure model contract

This document specifies frozen-interface candidates for parent inspection, not
an implemented policy or current native behaviour. Only the four source files
named in the accepted brief are added. No existing app/helper/source is wired.

NetworkConfiguration contains a finite fixture principal, positive UInt64 revision
and system/default, direct or manualHTTP mode. System/direct must have no host,
port or credential reference. Manual requires host and integer port 1..65535.
An optional opaque credential reference is 1..64 ASCII letters, digits, underscore
or hyphen. It is never a password, username, Keychain identifier or output field.
Revision UInt64.max is a valid positive revision when matched exactly; no addition
or implicit advancement occurs here. Configuration.validate returns syntheticValid
or the finite invalidConfiguration refusal after implementation; Phase A refuses.

Host grammar, no normalisation or resolution:

* ASCII DNS name at most 253 bytes, labels 1..63 ASCII letters/digits/hyphen,
  label ends alphanumeric, no trailing root dot, whitespace, controls, Unicode,
  percent encoding, underscore, URL syntax, option prefix or empty labels.
* A host containing only digits and dots must be exactly four IPv4 decimal
  octets 0..255, no leading zero except the single digit zero. Short numeric
  forms are refused rather than interpreted by an OS resolver.
* Bracketed IPv6 only: ASCII hexadecimal groups 1..4 digits; exactly eight
  groups without compression; at most one :: which replaces at least one
  group and leaves fewer than eight explicit groups. [::] and [::1] supported.
  No zone identifiers, dotted IPv4 tail, extra brackets/port or other suffix.
  Hex letter case is allowed. A route host matches configuration bytes exactly.

NetworkAdmission is an untrusted value containing exact principal/revision,
purpose, destination, method, optional submitted and frozen body digests, injected now/expiry, route,
path, automatic/explicit transfer, optional artifact, limited override and separate
consent observation/generation. All four purpose/destination/method triples must
match an immutable syntheticEndpoint allowlist provided only through Testing SPI.
The ordinary policy has no allowlist. There is no URL acceptance API.

For catalogue/artifact, method is GET and both body digests are absent. Manual
support and failure report are POST with exactly 64 lowercase ASCII hexadecimal
submitted and frozen digests, both present and equal. The frozen digest is a
separately supplied observation for the exact previously frozen submission bytes.
This slice validates a digest binding, never computes it or submits bytes. Consent
for both submissions must be allowed, purpose/principal exact, generation positive
and equal to the request generation. These observations prove model binding only;
they are not evidence of a person's actual consent or existing report queues.

Time is an injected integer, not a clock read. now must be present and both now
and expires in 0..9,007,199,254,740,991. Expiry is exclusive, expires > now, maximum
remaining lifetime 300 ticks. Validate bounds before subtraction to prevent overflow.
A stale or equal expiry is expired; unknown/negative/overflow/too-long is invalidTime.

System mode accepts only resolved systemDirect/systemProxy. Direct accepts only
direct. Manual requires manualProxy with exact host, port and optional credential
reference. Unavailable, PACfailure, authenticationNeeded and unsupported routes
refuse finitely, never falling back. No resolver or credential lookup happens.
Route is an observation, not a proxy-authentication implementation. Offline and
unknown paths refuse all new admissions. On limited path only catalogue metadata
is allowed by default. Artifact transfer requires explicit action plus an exact
principal/revision/purpose/destination/app/version/digest override. Automatic
transfer refuses even with override. Override expiry uses the same bounds and
300-tick limit and is exclusive. App/version are nonempty ASCII tokens of 1..64
letters/digits/dot/underscore/hyphen, digest exactly 64 lowercase hex. Invalid or
missing artifact and invalid/mismatched/expired override all return limitedData.
Support/report on limited path refuse; this is a conservative model boundary.

Deterministic refusal order: invalid configuration; unavailable empty allowlist
or unavailable route; principal/revision mismatch; time bounds/lifetime/expiry;
destination+purpose then method; body digest; route errors/mismatch; path;
limited transfer override; submission consent. Most tests isolate one guard.
Missing everything yields unavailable because the route is absent. Empty fixture
allowlist also refuses unavailable. A malformed configuration wins over missing route.

NetworkDecision is refused(NetworkRefusal) or syntheticPermitted(model).
NetworkSyntheticModel has an internal constructor, constant SYNTHETIC MODEL ONLY
marker, finite principal, revision and purpose only. It contains no host, credential
reference, body/artifact digest, arbitrary string, raw adapter error or URL. Both
native and installation authority properties are always false. dispatch always
returns unavailable, even for a synthetic positive. No admission is a reusable
native token. Redirect, config replacement, retry and consent withdrawal require
new model admission with fresh observations; there is no worker, queue, callback,
resumption, persistent draft or actual in-flight transfer machinery in this slice.

NetworkAdapters declares store/resolver/credential/path/transport and effect sink
interfaces with ordinary refusing implementations. Testing-only policy composition
accepts NetworkBoundaries to capture forbidden injected boundary calls. Pure policy
must never call any of them, even on synthetic positives. EffectSpy captures every
provided store/resolver/credentials/path/dispatch boundary and session, DNS, PAC,
persistence, process, environment, log, diagnostics and callback sink. These spies
prove absence of calls to supplied seams only; whole-source inspection must also
confirm no direct OS/network API bypass. No native adapter is implemented.

Checks are independent literals, not candidate-derived truth. Initial red must
compile, fail positive model/configuration cases and fail candidate Package
acceptance against the unchanged preservation helper. Reason assertions can also
fail against the universal unavailable stub. Parent freezes exact source interface,
checks, fixtures and registrations before separate implementation. No check is to
be weakened to follow later candidate behaviour.
