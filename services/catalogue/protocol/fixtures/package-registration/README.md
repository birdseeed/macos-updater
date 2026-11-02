# Package registration preservation controls

PAT-2660 Phase A preparation, 14 October 2026. No checks were executed by
this preparation leaf. Parent observed two meaningful API failures with 52 fixture/refusal passes, froze
all 54 controls, then released the pure guard. All 54 controls now pass. The
guard accepts only the exact two literal pins and reconstructs historical bytes.
Parent serially integrated that equivalence into the existing Package assertion;
all other historical assertions and the original manifest remain exact. Review,
complete verification and native capture acceptance remain separate gates.

`Package.original.swift` is the literal accepted `Package.swift` obtained with
read-only `git show 6f30b6712003f5b80720715413412fdb13ccbb91:Package.swift`.
Its independently pinned SHA-256 is
`8e309b1474a2b20608154e3f293c44a1946c85fe7e9e57321b2933b9286b8699`.
`Package.shell.swift` copies the parent's exact four-line registration.
Its independently pinned SHA-256 is
`6f69e14efb17c845fc194149d8248500ca6efb49416ebeba9a28030362bff447`.
Neither fixture is generated from the guard or its output.

The independent controls require exact bytes and exactly one occurrence of
each approved two-line insertion, directly after the products and targets
headers. Removing only those four lines must reproduce the literal original
fixture and its historical digest. No other addition or alteration is allowed.
The original frozen-v1 manifest and all prior source, checks and fixtures remain
unchanged. The historical manifest's Package digest remains the original one.

Future Phase B is limited to a closed two-approved-hash allowlist and exact
historical reconstruction using these literal insertion blocks. The original
bytes and exact shell-registered bytes return the original historical digest;
all other Buffer bytes and every non-Buffer input throw. No regular-expression
stripping, arbitrary registration parsing, partial stripping, environment
configuration or caller-supplied authority may expand acceptance. This is a
narrow preservation equivalence, not package validation or execution authority.

Prospective independent command, executed only by the parent:

```sh
node --test services/catalogue/tests/package-registration-preservation.test.mjs
```

The two positive API controls must fail meaningfully against the Phase A stub.
Fixture pin/reconstruction and negative refusal controls should pass. Setup or
import failures do not establish meaningful red. Freeze all five new paths
before implementation; the parent serialises any existing-test integration.
