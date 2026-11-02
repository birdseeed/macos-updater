# Unstapled notarisation policy source slice (PAT-2707)

Historical PAT-2707 source slice: the schema 2 and native observer descriptions below
record that slice. Current artifact inspection uses schema 3 and structured pinned
signature validation; see [pinned signature validation](pinned-signature-validation.md).
The dormant installed observer still requires its separately authorised migration.

Current inspection no longer requires a stapled ticket or invokes the ticket
validation tool. Notarisation remains mandatory: the app must pass strict
signature verification, match the pinned signing team and bundle identity, and
receive an affirmative Gatekeeper result with `source=Notarized Developer ID`.
An exit code of zero without that affirmative output is insufficient. Bundle
metadata, version, pinned architectures and held-file identity checks remain
required. This change does not add installation authority.

## Current and imported evidence

Schema 2 has exactly six required observations: imageVerify, signature,
identity, gatekeeper, containerSignature and containerGatekeeper. Container
signature and Gatekeeper nonzero exits remain recorded as raw failures; app
acceptance does not turn them into container success. Architecture inspection
continues to read the held executable descriptor without a command-line tool.
The dormant native app observer now records three app commands: strict
signature verification, signing identity and Gatekeeper assessment. Its exact
report binding requires those three commands and retains architecture,
manifest, journal and current/retained-old held-tree readback checks.

The live collector uses only the current required table. Its closed key set
rejects ticket and containerTicket extras. There is no public arbitrary-evidence
constructor that grants a live origin. Imported records retain fixture/replayed
origins and cannot become fresh OS validation or installation authority.

For imported schema 2 records only, ticket and containerTicket are independently
optional historical snapshots. If present, each must match the exact executable,
arguments and evidence path in the separate data-only replay table. Timestamp,
timeout, truncation and output bounds still apply. Neither exit status nor
success text supplies acceptance: validation uses requireSuccess=false, while
the six mandatory observations keep their existing validation. A historical
ticket success cannot override rejected Gatekeeper evidence.

For every schema 2 assessment, containerTicketPassed is false, including when
an optional imported snapshot reports success. Here false means no current
ticket assessment was performed. The existing field and report schema remain
stable; it is not a new claim that a ticket validation failed.

Unversioned schema 1 retains its exact nine required command observations and
historical acceptance semantics, including app ticket acceptance and the
historical containerTicketPassed result. Schema 1 remains fixture/replay-only;
the existing live legacy refusal is unchanged.

## Verification boundaries

The focused command is `/bin/sh scripts/verify-unstapled-evidence.sh`; the full
repository gate is `./scripts/verify.sh`. The parent run executes them through
its fixed-argv registry and owns acceptance, independent whole-change review,
exact-head/main CI and publication. This document records no unperformed pass.

The focused source guard checks exact historical data tables, the explicit
import-only binding and closed optional-key validation contract, and scans Swift
sources for command references outside those tables. It is a lexical safeguard;
it cannot prove control-flow reachability, exclude dynamically assembled command
names, or establish live origin isolation or clean-Mac behaviour. Whole-change
review and separately authorised native evidence remain necessary.

The named LiveCatalogueProof source amendment requires live evidence to omit
both ticket keys, retain conservative containerTicketPassed=false and omit the
ticket tool from every actually recorded command. It preserves the raw nonzero
container signature/Gatekeeper assertions and all other original proof bytes.
The inert preservation checks establish only that exact source exception;
they do not execute the live proof.

## Held native acceptance

Genuine notarised-but-unstapled vendor acceptance, clean-Mac/no-CLT behaviour,
SSD-backed disposable target proof, native app/helper operation, installation,
update/recovery, signing and client release remain separately held. Fixture
acceptance and source delivery do not close those requirements.

When the exact target and native actions are authorised, record the genuine
vendor download URL, exact version, independently pinned SHA-256/length and
signing identity before execution. Preserve the vendor bytes unchanged; do not
remove a ticket, re-sign or otherwise manufacture an unstapled input. Establish
the input's actual unstapled condition with separately authorised independent
evidence and retain the observation method and raw results. Any diagnostic tool
used for that preparation is outside current collection and cannot stand in for
proof on a clean target without that tool.

On the authorised clean target, bind the exact source revision, binaries,
receipts, OS/build, target identity and unchanged vendor bytes. Retain actual
signature and affirmative Gatekeeper output, architecture readback, complete
command records showing no mandatory ticket validation, and refusal controls
for rejected or malformed evidence. Native installed acceptance additionally
needs its existing held-tree, journal, manifest and recovery evidence. Record
each result and unresolved gap separately before claiming ticket completion or
any release readiness.
