# Native Activity storage contract

Source implementation, 23 October 2026. The parent accepted a compiled initial
RED of 299 cases: all original 240 passed, with 46 failures among 59 new checks.
The harness reported 23 setup controls with no failures. Focused candidate
verification then passed all 299 cases with 0 failures; all original 240 remained
passing and all 59 new checks passed. The 23 setup controls also passed with 0
failures. The additive checks and registration remain frozen. The focused result
covers fixture filesystem reopen, retention and fault behaviour; it does not
exercise native account discovery, guest behaviour or provider actions. Full
repository verification, independent whole-source delivery review, CI and the
private journal remain required acceptance gates.

The 21 October remaining integration allowance is one shared maximum of five
substantive failed repair rounds across ALL remaining PAT-2663 integration,
0/5 at implementation release. The original fixture foundation's 3/5 is sealed,
not reset. Native sessions retain their separate shared 0/2 allowance; these
filesystem checks consume no native session. Parent records raw executions,
substantive failures and prerequisite recovery separately. Unknown provider cost
is unknown, never zero. The component stays within its 16 MiB source allowance.
The implementation leaf runs no Swift, compiler, native, VM or provider operations.
The parent owns any later execution admission, serial build/VM ownership, jobs 2, 1800-second check bound, 4 GiB
aggregate cap and 5 GiB workspace/SSD floors.

## Fixed primitive interface and wire

The Testing SPI is `FixtureActivityRoot(checkOwnedDirectory:)`, the closed
`FixtureActivityFault` enum, and `@MainActor FileActivityStore(fixtureRoot:
principal:storeID:fault:) : ActivityStore`. `read()` returns missing or exact
`ActivityStoredBytes`, and throws on unsafe or malformed state. CAS returns only
`committed`, `knownNotCommitted` or `uncertain`; refusals before rename return
`knownNotCommitted`. An unreadable record is never absence. `exercisedFaults`
records only a fault branch actually reached, never constructor selection.
No native account or factory input is exposed through this seam.

`record.json` contains the exact canonical `ActivityWire` payload, with no
base64 wrapper or separate revision metadata. Its decoded revision is the
returned revision. The configured principal and storeID must match the payload.
The existing closed schema, strict canonical bytes, maximum 2 MiB and maximum
2000 events apply before both disclosure and replacement. Fresh absent CAS
requires nil expected and revision 0; subsequent CAS compares the complete exact
previous bytes AND revision and accepts only the exact successor. Stale/absent
expectations, duplicate/skipped revisions, mismatch between metadata and wire,
overflow, corrupt state, wrong binding and quota exhaustion refuse unchanged.
`createFresh` never repairs or overwrites an existing corrupt record.

The implementation uses physical descriptor-relative traversal and no-follow,
nonblocking bounded reads, including EOF and stable descriptor/name identity
checks. Root is private 0700, record/lock/temp are current-owner 0600 single-link
regular files on the same device. Symlinks, hardlinks, FIFOs, directories in file
positions, permissive or special modes, and any private-entry ACL refuse. Never
chmod or adopt existing unsafe state. Retained root identity must remain named
by its physical parent; a renamed root must fail even if its descriptor survives.

CAS retains and revalidates the lock inode, acquires a cooperative nonblocking
lock, validates current complete bytes while locked, exclusively creates its own
temp, handles short writes/EINTR, fsyncs and F_FULLFSYNCs the file, atomically
renames and syncs the directory. It independently reopens the installed inode
and reads back exact bytes before acknowledging committed. A failure after a
rename attempt is uncertain, including readback failure. Known pre-rename failure leaves
the previous bytes. Cleanup may unlink only the current operation's unrenamed,
identity-matching temp; never scan away another operation's lookalike temp.

## Independent fixture acceptance

The harness independently seeds and reads literal canonical JSON through its own
descriptors. The candidate must validate the raw selector physically: actual
`patched-activity-checks` executable, unique `pat2663-native-store-<lowercaseUUID>`
0700 root immediately below that executable's actual `.build`. Names and caller
URLs are untrusted. The harness touches only its exclusively created roots,
owned aliases and exact declared children; unknown leftovers prevent cleanup.
It never opens a real home, invokes native composition, starts a subprocess,
uses Keychain or performs network operations.

Checks cover successful bootstrap/CAS/reopen, strict expected bytes and revisions,
malformed/cross-bound/quota proposals and stored records, unsafe types/links/modes/
allow ACLs, lock contention, moved roots, non-UUID and symlink selectors, actual
short-write/EINTR fault reachability, each pre/post-rename fault outcome, exact
old/new bytes, and preservation of an unrelated lookalike temporary. Separate
roots/principals and cross-copied records exercise primitive isolation. Existing
Testing SPI owner binding exercises synthetic correlation/replay and 30-day
retention after reopening a separately constructed store. Whole attempts with
unresolved recovery remain protected and unrelated journal/backup sentinels stay
exact. Default `ActivityHistoryOwner()` remains permanently unavailable.
These are process-local fixture reopen checks, not process relaunch or installed
native-event proof. The three additive setup controls independently validate
fixture IO, the wire oracle and physical allow ACL construction; the parent
observed them passing with the refusing stub.

## Native context: manual source acceptance until guest admission

The implementation exposes an explicit `@MainActor NativeActivityContext`
with static `open() throws -> NativeActivityContext`, `createFresh() throws`,
`reload() throws`, `selectRetained() throws` and descriptive `snapshot`.
The explicit factory necessarily observes the account and opens or prepares
fixed storage. It is not composed into app construction, rendering or navigation.
The snapshot property reads only cached descriptive state and performs no IO.
The context internally binds the existing owner and shares existing bootstrap and retention logic; no new native append/success API is permitted.
Real clock observation belongs inside those explicit methods. No timer or
automatic cleanup is added. Unknown/rollback time conservatively retains history.
Resolved history expires at 30 days; unresolved whole-attempt protection and
all quotas remain exact. Activity never deletes transaction journals or backups.

`open` observes actual non-root equal real/effective UID and exactly one user
record in fixed OpenDirectory `/Local/Default`; no search-policy/getpwuid network
lookup, environment HOME, caller identity or UID-derived fallback. It requires a
nonzero actual GeneratedUID outside the reserved fallback namespace and a
canonical physical owned home. Existing safe `Library/Application Support`
parents lead to fixed private `Patched/Activity`, not caller-selected storage.
Principal binds to the local account incarnation; storeID is the canonical
uppercase actual GeneratedUID required by ActivityWire. Reobserve account and
physical roots on operations. `open` may prepare only absent safe private
containers; only explicit `createFresh` creates an absent history record.

The fixture seam proves none of that account discovery or native composition.
Account/root binding, relaunch and per-user isolation require actual guest
evidence; tests must not inject an account descriptor and call that native
proof. No power-loss guarantee, malicious same-UID exclusion, real event
producer, installed-state success, report transport, transaction authority or
release readiness follows from passing these checks. Help integration displays
selected context locally and does not send a message or report.
The accepted preference adapter is design context only and remains byte-exact;
there is no generic-framework refactor or second preference identity authority.

Parent prospective execution, only after current CI is terminal and admission,
registry, live authority/controller, observer and resource facts are refreshed:
`swift build --product patched-activity-checks --jobs 2`, then
`swift run --skip-build patched-activity-checks`, through the trusted fixed-argv
registry. Freeze actual argv and source pins before execution. After focused
GREEN, run the full `./scripts/verify.sh` gate within its admitted limits. Whole
independent correctness/security delivery review, exact-head/main CI, source
mapping and the owner-private journal remain parent gates. Productive event
integration continues to depend on PAT-2710's separately accepted mechanism.

## Explicit Activity navigation slice, 24 October 2026

The shared client now retains an inert Activity controller. A private adapter
opens `NativeActivityContext` only for explicit Load local history or Create
empty history actions. Successful actions retain the same context; retention
requires a loaded active context and calls its existing selection policy once.
Loads accept only available snapshots with a revision and unique event IDs.
Fresh creation additionally requires revision zero and no events. Any operation
error or invalid result clears displayed history and drops the active context,
without retry, fallback creation or reuse by retention. A later explicit load
may reopen. A previously selected support handoff remains unchanged.

The concrete policy remains 30 days, 2000 events and 2 MiB, with unresolved whole
attempts protected by the existing owner. Activity selection has no journal or
backup deletion API. The navigation layer does not add an event producer,
installed-success authority or send transport. Source and fixture checks can
establish local behavior but cannot establish native account discovery, per-user
isolation, relaunch or installed-event production. Those outcomes require guest
evidence. The injected Test double seam does not provide that proof, and this
feature does not send a message or report.
