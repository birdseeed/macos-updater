# Native preference storage

`NativePreferenceContext.open()` is the explicit storage entry point. Ordinary
`PreferenceSession()` still refuses and does no IO. Opening a context observes
the nonroot real/effective kernel UID and exactly one user record in the fixed
OpenDirectory `/Local/Default` node. That local record supplies its account name,
home and GeneratedUID. Search nodes, environment variables, caller paths and
`mbr_uid_to_uuid` are not identity sources. Missing, ambiguous, nonlocal, nil or
UID-derived GeneratedUID values refuse. The account binding is reobserved on
every store operation, so a changed account incarnation cannot reuse the owner.

The only native container is the observed account home's
`Library/Application Support/Patched`. Existing Library and Application Support
directories must be safe and current-user-owned. Explicit open may create the
missing Patched container with mode 0700; it never repairs an existing directory.
All ancestry is opened without following symlinks and retained through directory
descriptors. Ancestors must be root/current-user-owned and not group/other
writable, with no allowing ACL entries. The container must be current-user-owned,
0700 and have no extended ACL. Retained parent/name/device/inode identities are
checked again at use. Files must be same-volume regular current-user-owned 0600
files with one link and no extended ACL. Unsafe data is refused in place, never
adopted, chmodded, quarantined or reset.

The context returns the existing `PreferenceSession`. Its internal factory and
explicit missing-only bootstrap share the same record codec, exact-byte CAS,
accepted revision, projection, queue and scheduling policy as fixtures. The
process generation is generated once and is stable across contexts in that
process; the local GeneratedUID binds the durable principal and scope. `reload()`
loads existing state, including malformed-state refusal. `createFresh()` only
creates genuinely absent state, and conflicts with existing bytes. Neither open
nor reload creates a preference record. No UI or app composition uses this
factory yet. The legacy `bootstrapFreshFixture` remains available only for
Testing-injected session composition; native bootstrap goes through the context.

The adapter bounds reads before allocating to at most 1 MiB. Reads check file
identity, length, modification/change timestamps and an extra EOF byte.
Cooperating writers hold a retained stable `lock` inode under nonblocking
exclusive `flock`, then compare the exact prior bytes (nil means actual absence).
A write creates one exclusive random 0600 temporary and handles short writes
and EINTR, synchronises the file, requests `F_FULLFSYNC`, rechecks the root,
lock, temporary and prior bytes, atomically renames, synchronises the directory,
and reads back the exact proposed bytes. The session separately decodes and
reads back before publishing its accepted revision. Known failures before
rename report not committed. Once rename is attempted, failures or missing
acknowledgement report uncertain. No uncertain result publishes an edit.

Temporary cleanup only considers the current operation's retained inode and
exact name beneath its validated root. It never scans or recursively cleans a
directory. Failed or interrupted operations can leave a temporary for a future
explicit recovery policy; no broad automatic cleanup is provided.

The Testing SPI uses the same adapter with a confined selector: the root must
be an immediate `pat2662-native-store-<lowercase UUID>` directory under the
actual kernel executable's `.build`, current-user-owned 0700, without symlink
ancestry or an extended ACL. This is checked on every operation, including
against the retained root identity. A raw URL does not mint a native context,
account or capability. Write/sync/rename/readback faults exist only on that
fixture constructor, with observations only when the selected stage is reached.
Native construction supplies no hook.

These are cooperative same-user durability checks, not authentication against a
malicious process with the same UID. Such a process can ignore locks, race names,
rewrite bytes or interfere after a read. No userspace check eliminates those
races. Atomic rename avoids partial record publication, but full power-loss
guarantees depend on the filesystem, kernel and storage hardware honouring sync
requests. Root replacement, ACL changes, oversized data and ambiguous persistence
fail closed; they are not repaired automatically. Local OpenDirectory errors
also refuse rather than falling back to a synthesized identity.

Storage does not authenticate the app/release strings in a record or establish
installed identity. It adds no helper, update start, scheduler, network,
installation, production trust or release authority. Fixture process relaunch
evidence is separate from actual native account/storage and installed proof.
Build/link compatibility, repository checks, independent review and separately
admitted native execution remain verification gates.
