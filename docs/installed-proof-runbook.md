# PAT-2584 installed proof runbook

Historical proof scope and current boundary, 27 October 2026: the dated target selectors, commands, hashes and observations below are retained evidence for the PAT-2584/PAT-2636 proof, not fresh target or execution authority. Current native consumer-journey status belongs to PAT-2673; the full native/installed journey remains unfinished. Under PAT-2724, this runbook is not a mandate to centrally download and VM-test every release. New/materially changed routes and credible risks still need representative success, refusal and recovery evidence. Patched must verify safe installation and the installed result; vendors own functional behaviour/data migration, and restoring an app bundle does not reverse a vendor data migration. No proof run is authorised or claimed here.

**PAT-2636 replacement-target addendum, 10 October 2026.** Andy accepted the
replacement Parallels staging target, existing-key SSH route and the exact
isolated PAT-2584 run scope. The sole current harness selector is
`parallels-0A0A0A0A-0000-4000-8000-000000000001`, bound to macOS 27.0.1,
build 26A434, arm64, hostname mac-staging.local and the measured guest platform
UUID digest in the runtime contract. Account/home remain andy, uid 501,
/Users/andy; real/effective uid, console ownership and hypervisor 1 are still
mandatory. The former UTM selector and all dated UTM observations below are
historical, not current execution instructions.

The parent verified the accepted existing-key SSH route to 10.211.55.3 as
andy, uid 501, using `ssh -F <private-parent-config> mac-staging-parallels`.
The task-specific private config pins the replacement host key independently
observed through Parallels guest execution, with strict host-key verification.
Remote Login is enabled and console uid 501 was verified. Root proof execution,
new credentials
and passwordless sudo remain excluded. Fresh guest Command Line Tools/stapler
are absent, so native validation prerequisites remain unresolved; no tool
installation or successful native proof is claimed. Parent acceptance,
independent full-diff OpenCode/NVIDIA review, full verification, exact PR/main
CI and source/binary-bound guest preparation precede proof execution.

Only /Users/andy/PatchedProof/<run-id> and its independently created case
destinations/profile are accepted, with retained baselines and evidence and
reversible recovery. Personal host, /Applications, unrelated data/profiles,
helper/scheduler, reset/deletion and production release remain excluded.
Case 8 retains its person-controlled launch and isolation precondition.
Use the current runtime contract's exact selector/examples; the dated
preparation material below is preserved for evidence, not reused as authority.

**10 October 2026 implementation addendum.** Andy accepted building and independently
reviewing the harness, followed by the exact isolated guest run. The parent
accepted compiling Phase A red and explicitly released Phase B. The separate
source implementation and synthetic checks now exist; parent acceptance,
independent review, publication and actual guest cases remain pending evidence.
No guest installation or live proof is claimed by this addendum.

Read [the runtime contract](disposable-proof-runtime.md) for exact executable
arguments, fixed Incoming filenames, builder receipt, pause witnesses, independent
mtree validation, space refusal and evidence paths. It refines transfer with an
exclusive private /Users/andy/PatchedProof/.bootstrap-<run-id> for measured tools
including the native harness, wrapper, independently measured artifact-inspector
and builder receipt. The native harness still exclusively creates the actual run
root; no externally created run/case is adopted. The toolchain-free wrapper is
packaged beside the measured native executable.

The runtime uses a retained new Source bundle only in the four stage cases and
detaches its image before interruptible in-process copying. Old target and
baseline copies are prepared directly from the old read-only mount. Every
planned guest action remains parent-owned after the acceptance/review gates.

The dated material below preserves the preparation observations and accepted
case matrix. Statements that the harness does not exist or scope is unaccepted
describe the earlier 9 October checkpoint and are superseded only by this
addendum and the 10 October owner instruction.

## Historical preparation checkpoint

**Status: preparation only, updated 9 October 2026.** The parent captured a read-only host observation on 8 October and a read-only guest preflight over the existing `mac-staging` SSH route on 9 October. A usable login was reached and the guest identity and baseline facts below were captured. Under already-recorded owner approval, the parent also verified and normally terminated one exact legacy Self Service process; all five legacy jobs remained disabled. This is point-in-time evidence, not a guarantee against relaunch. No harness exists, no proof case has run, and this file is not evidence of an installed update. The future run scope and guest writes remain proposed and unaccepted.

Authority, as it stands:

- **Already authorised and completed:** identifying the existing guest, read-only preparation, and closure of the exact legacy Self Service process under the existing owner-approved authority. No new authority is inferred.
- **Not granted by this file:** installation, guest file transfer, profile creation or launch, settings changes, keys, purchases, guest reset or deletion.
- **One acceptance, not many.** The future proposal is one exact run scope. Once accepted, routine commands, transfers, mounts and cases inside that scope need no separate request each. Case 8's launch remains subject to its isolation precondition.
- **Still unresolved:** acceptance of exact run/case roots, app destinations and new profile; transfer; restorable baseline; and the reviewed harness scope.

Command labels record the 8 October historical proposal and the observed 9 October subset. The 8 October command blocks remain historical proposals. The exact 9 October subset is recorded in the table below; do not infer that all guest commands were either run or unrun.

Every command block is labelled with one of:

- **RUN ON HOST BY PARENT**: historical host-side commands run by the parent on 8 October 2026.
- **EXISTS, UNRUN HERE**: the command was proposed on 8 October and is not included in the explicitly recorded 9 October subset.
- **PROPOSED, DOES NOT EXIST**: the command names a tool this ticket would introduce. It cannot be run today.
- **8 OCTOBER HISTORICAL PROPOSAL — PARTIALLY OBSERVED 9 OCTOBER**: the block records the earlier proposal; only the exact subset listed in the dated evidence table was observed.

## What is known and what is not

The host-side UTM observation was recorded on 8 October 2026 and the named guest was confirmed started by list/status on 9 October. The following guest subset was captured over SSH on 9 October 2026; the guest UTC string matched the host-captured time, but no clock-trust guarantee is claimed. The UTM UUID below identifies the named UTM guest and is not the guest platform UUID.

| Fact | Value | Standing |
| --- | --- | --- |
| Staging environment | UTM guest `macOS - Staging` | Positively identified by name and UTM UUID |
| UTM UUID | `9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246` | Host list/status observation, 9 October |
| Guest route and hostname | SSH alias `mac-staging`; `mac-staging.local` | Used for the dated read-only preflight |
| Guest OS, build, architecture | macOS 26.6.2, build 25G83, arm64 | Observed 9 October |
| Hypervisor and login | `kern.hv_vmm_present=1`; user `andy`, uid 501; console user `andy` | Observed 9 October |
| Guest platform UUID / serial | Platform UUID captured in a private parent receipt; serial not collected | UUID privately recorded; independent console-to-SSH cross-check not performed. UTM UUID is not proof of equality with guest UUID |
| SIP / Gatekeeper assessment | enabled / assessments enabled | Observed 9 October |
| Filesystem / available space | APFS; 24,991,296 KiB available on `/Users` (about 24 GiB) | Observed 9 October |
| Developer tools | `xcode-select -p` is `/Library/Developer/CommandLineTools`; Swift executable symlink exists | Observed; Swift version and build were not run |
| Firefox | `org.mozilla.firefox` version 151.0.4 exists at the selected existing path; no `firefox` process match | Observed 9 October; left untouched |
| Proposed run and Firefox support/cache roots | `/Users/andy/PatchedProof` and both Firefox support/cache roots were absent | Only directory metadata/existence checked; contents not read |
| Five legacy jobs | `com.patched.collect`, `config-poll`, `posture-poll`, `update`, `upload` disabled | Observed 9 October |
| Legacy Self Service | Exact uid 501, PID 4148 and executable path independently checked; one normal `SIGTERM`; process absent on readback | Completed under existing owner approval on 9 October; point-in-time only |
| Preserved host images | Both preserved DMGs match their pinned SHA-256 and byte lengths in the parent receipt | Verified on the host; no guest transfer has occurred |

The 8 October console observation (black console and no usable login) is historical and superseded by the 9 October SSH preflight. The host's personal macOS installation is never the target. Its 7 October configuration (27.0.1, build 26A434, arm64) is not the guest, an approval or marketed support.

The owner clarification of 8 October 2026 settles the staging location. It does not authorise changing the host, resetting the guest, touching unrelated apps or profiles, or installing a privileged helper or scheduler.

## Evidence that exists, and what it is not

| Evidence | What it shows | What it does not show |
| --- | --- | --- |
| `./scripts/verify.sh` (reference, artifact, core, transaction, view and operator checks; PAT-2583 was accepted with 1,012 cases) | The fixture behaviour of each library on disposable roots beneath `.build` | Any installed app, any real Firefox bundle, any macOS assessment of a staged or installed bundle |
| PAT-2583 live catalogue proof (13 physical steps, five painted PNGs, merged at `4590d37`) | The pinned 157.0.1 image passed the inspector's app checks on the host on that run, and a test-key catalogue for it was signed, published locally and consumed | An installation, an old-to-new update, a refusal on an installed target, a recovery |
| `docs/firefox-artifact-evidence.json` | Dated host observations of both pinned images | Fresh OS validation, anything about the guest |

None of these is installed-update evidence. A fixture pass, a painted view, a process list or a CI run must not be substituted for any case in this runbook.

## Why the current code is not an installed proof harness

Read from the source at this revision. These are the guards a harness must respect, not obstacles to route around. This runbook leaves every fixture guard and default unchanged.

1. **The default entries refuse.** `UpdateTransaction.perform` and `UpdateTransaction.recover` (`Sources/PatchedCore/UpdateTransaction.swift`) throw `notAuthorized` before reading any path. `CataloguePublisher.sign` and `CataloguePublisher.publish` (`Sources/PatchedOperator/CataloguePublisher.swift`) do the same. No production authority exists.
2. **The only working authority is test-only and confined.** `FixtureAuthority` is `@_spi(Testing)`. `FixtureRootHandle` (`Sources/PatchedCore/FixtureRoot.swift`) finds the nearest `.build` ancestor of the running executable from the kernel's record of the executable, and creates only `patched-transaction-fixture-<suffix>` directly beneath it. The working directory, `argv[0]` and the caller's path play no part. `FixtureOperatorAuthority` is confined the same way to `patched-operator-fixture-<suffix>`.
3. **The fixture transaction cannot hold a real Firefox bundle.** `TransactionLimits` allows 512 entries, depth 16 and 8 MiB in total. Every file must be mode 0600 or 0644 with one link, so any execute bit is `unsafeMode`, and a symlink is `symlink`. A real app bundle has executables and framework symlinks and is far larger. The fixture "artifact" is a JSON bundle manifest, not a disk image.
4. **Nothing asks macOS about the staged or installed bundle.** The fixture transaction runs no `codesign`, `spctl` or `stapler`. The view row reads `macOS signature and notarisation: Not run in this fixture preview`.
5. **The running check is a declaration.** `FixtureHooks.applicationRunning` is a test hook reported as `runningCheck: fixtureProbe`. It is never an OS observation.
6. **Every result says so.** Fixture reports carry `origin: fixture`, `freshOSValidation: false`, `installationAuthorized: false`, `installedFirefoxProof: false`. The journal carries `origin: fixture`.
7. **The catalogue consumer is fixture trust.** `CatalogueVerifier` takes an explicit `FixtureTrust` key. `patched-core-proof` takes its clock, OS version and installed version as arguments, so its `installedVersion` is a policy input, not an observation. Fixture catalogues live at most 259,200 seconds, so one issued for PAT-2583 is not valid for a later run.
8. **The live inspection is pinned, read-only and closed before it returns.** `ArtifactInspector` and `OperatorVerification.verifyPinnedArtifact` accept only the two compiled pins and install nothing. The inspector copies or downloads the image into a private `patched-artifact-XXXXXXXX` workspace in the system temporary directory, attaches it read-only at a mount it owns, runs its checks, detaches, and removes its staged `artifact.dmg` and the workspace before it returns (`Sources/ArtifactInspection/Inspector.swift`, `Mount.swift`). The caller receives a report. It never receives a live mount, and after `download-inspect` it holds no image either. `--live-catalogue-proof` accepts one host path and exits 2 for anything else.

Pointing the test authority at a real target, widening `TransactionLimits` in place, running a check executable from a `.build` directory placed to capture a real path, or accepting a recorded inspection as verification would each bypass a guard. None is proposed. `docs/transaction-recovery.md` already states that real artifact verification and authority over a real target are a separate trust boundary that "must not be built by accepting a caller-made inspection report".

## Future narrow paths

The ticket names exactly these paths. Only this file exists today. This document authorises no new code and no new ticket.

| Path | Exists | Proposed role |
| --- | --- | --- |
| `docs/installed-proof-runbook.md` | Yes, this file | Procedure and acceptance matrix |
| `tools/run-disposable-proof.swift` | **No** | The single proof entry: one approved target identifier, one run root, live checks, the reversible transaction, evidence writer |
| `scripts/prove-disposable.sh` | **No** | Thin wrapper that refuses to run without `--target-id <approved-id>`, an explicit case and a case root name from the fixed table |
| `evidence/first-proof/<run-id>/report.json` | **No** | One report per run, copied out of the guest unchanged with its SHA-256 |

What a harness would have to decide, with a recommendation for each. These are proposals for its acceptance checks and review, not decisions made here. Every outcome named in this runbook stays proposed until the new harness's semantics are validated.

- **Authority.** A new, separately reviewed proof authority bound to one compiled target identifier and one exclusively created run root. Recommended: it never adopts an existing directory, never accepts `/Applications`, a home directory root or a browser profile as a root, and cannot be reached through the default entries, which keep refusing.
- **Bundle rules for a real app.** Recommended: a separate rule set for the proof authority that permits executables and in-bundle relative symlinks that resolve inside the bundle, with new measured bounds, leaving `TransactionLimits` and the fixture checks unchanged.
- **Artifact route.** The existing inspector's mount is closed and its report is a record, so the stage cannot reuse either. Recommended: the harness holds the pinned image itself, re-verifies the SHA-256 and byte length of the bytes it holds against the compiled pin, attaches its own fresh read-only mount, and runs the app checks fresh on that mount. It copies the app into the stage, asks macOS about the staged bundle before the swap and about the target after it, and records the real detach outcome. A Phase 4 report may be compared with these results. It is never consumed in place of them.
- **Running check.** Recommended: a real OS observation of the exact bundle at the exact target path. Nothing is quit.
- **Clock and versions.** Recommended: the harness reads the system clock, `sw_vers` and the target's `Info.plist` itself. None is a caller argument.
- **Trust.** Test catalogue and test key only. Reports must keep saying the catalogue trust is fixture and never production.
- **Pause points.** Interruption cases need a way to stop at a named step. Recommended: probes that can only wait or refuse, never accept, as the existing probes do. After any pause the staged bundle is checked by macOS again immediately before the swap.

## Proposed scope, requiring one exact acceptance

One guest, one app, one version step, one user-owned run root.

- **Guest:** `macOS - Staging`, UTM UUID `9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246`, and no other machine.
- **Update:** Firefox 157.0 to 157.0.1, the two images pinned in `docs/firefox-artifact-evidence.json`:
  - 157.0: SHA-256 `df6d8c79b6126bcf24cb70ebab9371916a662028e2d706e462d432e78fdf396c`, 161,304,638 bytes
  - 157.0.1: SHA-256 `40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982`, 161,550,118 bytes
  - bundle `org.mozilla.firefox`, Team ID `43AQ936H96`
- **Run root (proposed):** `/Users/andy/PatchedProof/<run-id>`, mode 0700, exclusively created, owned by uid 501. The parent path `/Users/andy/PatchedProof` was absent in the 9 October preflight. The run root itself remains proposed and uncreated. It holds `Incoming` (the held images and the case inputs made from them), `Evidence` and `Cases`.
- **Case root (proposed):** `<run-root>/Cases/<case-root>`, exclusively created, one per independent case, with names from the table in [Phase 6](#phase-6-acceptance-matrix). Each holds its own `Applications`, `Transaction` and `Baseline`.
- **App destination (proposed):** `<case-root>/Applications/Firefox.app`. These are the only bundles the proof may replace.
- **Test profile (proposed):** `<run-root>/Cases/open-app/Profile`, new and empty, used only by case 8.

Not in scope, and not assumed:

- A Firefox already in the guest, at `/Applications/Firefox.app` or anywhere else, is **not** assumed disposable. It is never the target, never launched and never modified. If one exists it is recorded and left alone.
- Any existing browser profile. It is never enumerated, read or copied. See [Profile privacy](#profile-privacy).
- `/Applications`, any other app, system settings, login items, Homebrew, new software, new keys, a privileged helper, a LaunchDaemon, a scheduler or root.
- Stopping, suspending, cloning, snapshotting, resetting or deleting the guest.
- The host's personal installation.

## Phase order

Each phase stops on its first unexpected result. A later phase never starts on an earlier phase's unverified output. Phases 0 to 2 contain historical proposals and the explicitly recorded read-only subset; Phase 3 onwards changes the guest and waits for the exact run scope to be accepted.

### Phase 0: host-side identity (read-only, parent only)

Performed on 8 October 2026; host list/status were observed again on 9 October. The guest preflight below used the existing SSH route on 9 October.

**RUN ON HOST BY PARENT**

```sh
/Applications/UTM.app/Contents/MacOS/utmctl version
/Applications/UTM.app/Contents/MacOS/utmctl list
/Applications/UTM.app/Contents/MacOS/utmctl status 9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246
/Applications/UTM.app/Contents/MacOS/utmctl ip-address 9AAEFEB3-4D36-4ED2-AD13-D2BAADD63246
```

`ip-address` was refused as unsupported by this backend in the 8 October observation. Do not run `start`, `stop`, `suspend`, `delete`, `clone` or `exec`. A usable SSH route was observed on 9 October; no reboot or reset is proposed.

Stop if the name, UUID or state differs from the table above.

### Phase 1: access validation (read-only, inside the guest)

The read-only subset below was run over the existing `mac-staging` SSH route on 9 October. A separate parent receipt captured the guest platform UUID privately; its raw value is not reproduced here. No serial was collected, and an independent console-to-SSH cross-check was not performed. The UTM UUID is not evidence that the guest platform UUID matches it.

**8 OCTOBER HISTORICAL PROPOSAL — PARTIALLY OBSERVED 9 OCTOBER**

```sh
sysctl -n kern.hv_vmm_present
ioreg -rd1 -c IOPlatformExpertDevice | grep -E 'IOPlatformUUID|IOPlatformSerialNumber|"model"'
id -un; id -u
stat -f '%Su' /dev/console
netstat -an -p tcp | grep -E '\.22 .*LISTEN'
```

- `kern.hv_vmm_present` must print `1`. If it prints `0` the terminal is on a physical Mac, which may be the personal host. **Stop and change nothing.**
- Record the platform UUID and serial once at the console of the identified UTM window. Any later session over another route must print the same values before it does anything else.
- The console user must be the user that will own the run root.
- A listening port 22 only reports whether Remote Login is already on. Turning it on is a setting change and is not proposed.

### Phase 2: guest baseline (read-only, inside the guest)

**8 OCTOBER HISTORICAL PROPOSAL — PARTIALLY OBSERVED 9 OCTOBER**

```sh
sw_vers
uname -m
csrutil status
spctl --status
df -h /Users
diskutil info / | grep -E 'File System Personality|Volume Name|Device Identifier'
xcode-select -p
ls -ld /Library/Developer/CommandLineTools/usr/bin/swift
ls -ld /Applications/Firefox.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Firefox.app/Contents/Info.plist
pgrep -lx firefox
ls -ld "$HOME/PatchedProof"
```

Notes:

- Do not run `swift`, `git` or `xcrun` to test for a toolchain. On a Mac without Command Line Tools those names open an install prompt. `xcode-select -p` and the `ls` do not.
- A missing `/Applications/Firefox.app` or `$HOME/PatchedProof` is an expected answer, not a failure.
- If Firefox is running, record it and stop. Whose session it is and whether it may be closed is the owner's decision. The proof quits nothing.

Unrelated apps and any existing Firefox profile are recorded by top-level and root-directory metadata only.

**8 OCTOBER HISTORICAL PROPOSAL — PARTIALLY OBSERVED 9 OCTOBER**

```sh
stat -f '%N%t%i%t%m%t%z' /Applications/*.app | LC_ALL=C sort
stat -f '%i%t%m%t%Sp%t%Su' "$HOME/Library/Application Support/Firefox"
stat -f '%i%t%m%t%Sp%t%Su' "$HOME/Library/Caches/Firefox"
```

Record for the baseline: OS version and build, architecture, user, console session, SIP and Gatekeeper state, free space, toolchain presence, the `/Applications` top-level listing, and for each of the two Firefox directories only whether it exists and its own inode, modification time, mode and owner.

#### Profile privacy

No existing profile tree is walked, counted or hashed, in this phase or in Phase 8. No file inside it is opened, no name inside it is read or written to evidence, and nothing is copied out of the guest. If a directory does not exist, record that.

This has a cost that must be stated with the result. Root-directory metadata **cannot prove that an existing profile, or an unrelated app, was preserved byte for byte**. A directory's modification time moves only when an entry is added to or removed from that directory itself, so a change deeper in the tree leaves it untouched. An unchanged line in Phase 8 is consistent with preservation and is reported as exactly that.

Whether a Firefox started with `-profile "<run-root>/Cases/open-app/Profile" -no-remote` writes outside its case root is **unverified**. Those flags select a profile; they have not been shown here to stop writes elsewhere in the user's Library. Case 8 therefore stays gated until the owner accepts an isolation proof or precondition as part of the run scope, for example that Phase 2 found no existing Firefox directories for the guest user. Without one, case 8 is not run and is reported as gated.

The new, empty proof profile is the only profile that may be hashed in full. It holds no personal data.

### Phase 3: source and binary identity

This phase needs the accepted run scope, including a route for the harness binary and both images. The proposed route is to copy the exact preserved host images and a host-built harness for a reviewed matching revision; no transfer has occurred or been approved. Do not use a new network download or install a guest toolchain as a workaround. The run root and `Incoming` remain uncreated.

| Need | Option | Gate |
| --- | --- | --- |
| Harness binary | Build in the guest from the reviewed revision | A Swift 6 toolchain must already be there. Installing one is not proposed |
| Harness binary | Build on the host from the reviewed revision and copy it in | A transfer route, matching architecture and OS floor, and the unknown signing state below |
| Pinned images | Download from `archive.mozilla.org` in guest | Historical option only; not selected. It would require guest network authority and the harness must independently hold and verify the bytes |
| Pinned images | Copy the exact preserved host files in | Proposed route; needs acceptance of transfer and receipt-backed digest verification |

Whether a Developer ID consumer build, signing identity or notarisation service is available is **unknown**. An unsigned or ad hoc proof binary is a recorded limitation of the run, never a reason to create a key or credential. A binary copied in may be blocked by Gatekeeper; changing a Gatekeeper setting to allow it is not proposed.

After authorised transfer, and before any proof case or installation, record:

**EXISTS, UNRUN HERE** (on the building machine, then the digest and signature lines repeated on the guest for a copied binary)

```sh
git rev-parse HEAD
git status --porcelain
swift --version
swift build --show-bin-path
shasum -a 256 "<bin-path>/<harness-binary>"
codesign -dvvv "<bin-path>/<harness-binary>"
```

The revision must be a reviewed, merged commit with a clean tree. `<bin-path>` is what `swift build --show-bin-path` prints for the configuration the gate actually built. `scripts/verify.sh` runs a plain `swift build` today, so a `release` directory and a binary on `PATH` are not assumed. Record the builder digest before transfer, then repeat the digest and signature checks in the guest after authorised transfer and before any proof case. The digests must match. This does not authorise transfer or target writes.

### Phase 4: artifact inspection in the guest

Needs: the Phase 3 route, and the developer tools found present in Phase 2. The inspector calls `/usr/bin/lipo` and `/usr/bin/xcrun stapler validate` itself, so on a guest without those tools it must not be run.

**EXISTS, UNRUN HERE** (per version, the form that matches the accepted route; usage read from `Sources/ArtifactInspectionCommand/main.swift`)

```sh
"<bin-path>/artifact-inspector" download-inspect 157.0
"<bin-path>/artifact-inspector" download-inspect 157.0.1
"<bin-path>/artifact-inspector" inspect-local 157.0 "<run-root>/Incoming/Firefox 157.0.dmg"
"<bin-path>/artifact-inspector" inspect-local 157.0.1 "<run-root>/Incoming/Firefox 157.0.1.dmg"
```

The image path must be absolute. The command exits 1 with a `refusal` in the report, and 2 on a usage error. Each run writes only inside its private workspace in the system temporary directory, which is outside the run root, and removes it when cleanup is verified. On `cleanupFailed` the workspace is preserved and named in `workspacePreserved`.

Record each report whole. Keep two results apart, as `docs/first-proof-target.md` requires:

- **App payload:** deep strict `codesign`, signing identifier, Team ID `43AQ936H96`, `spctl --assess --type execute` accepted as `Notarized Developer ID`, `stapler validate`.
- **Disk image container:** on the host both images were unsigned, with `codesign` exit 1, Gatekeeper open exit 3 and `stapler` exit 65. Expect the same in the guest and record what is actually observed. A container failure stays a failure. It is never folded into an overall pass and never hidden by a passing app.

This is the first fresh OS validation on the guest. It installs and launches nothing, and it leaves nothing mounted. Its report is a record from this point on: no later phase copies from its mount or treats it as verification of the stage.

### Phase 5: baseline of each case root

Needs the accepted run scope. Placing 157.0 at an app destination is itself an installation into that case root. It is recorded as setup, not as the update under test.

**PROPOSED, DOES NOT EXIST**

```sh
./scripts/prove-disposable.sh --target-id <approved-id> --run-id <run-id> --case-root <case-root> --case prepare-root
```

The case must exclusively create the case root and refuse an existing one. It places 157.0 from a fresh read-only mount that the harness owns, after re-verifying the held image against the pin and running the app checks on that mount, as described under [Future narrow paths](#future-narrow-paths). Every independent case starts from its own freshly verified 157.0 baseline. No root is reused and no target is carried from one case root to another.

The baseline, with commands the parent can repeat by hand:

**EXISTS, UNRUN HERE** (the `mtree` keyword set is a proposal still to be validated)

```sh
mtree -c -n -k type,mode,size,link,sha256digest -p "<case-root>/Applications/Firefox.app" > "<case-root>/Baseline/target-157.0.mtree"
shasum -a 256 "<case-root>/Baseline/target-157.0.mtree"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "<case-root>/Applications/Firefox.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "<case-root>/Applications/Firefox.app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "<case-root>/Applications/Firefox.app"
codesign -dvvv "<case-root>/Applications/Firefox.app"
spctl --assess --type execute --verbose=4 "<case-root>/Applications/Firefox.app"
xcrun stapler validate "<case-root>/Applications/Firefox.app"
ditto "<case-root>/Applications/Firefox.app" "<case-root>/Baseline/Firefox-157.0.app"
mtree -f "<case-root>/Baseline/target-157.0.mtree" -p "<case-root>/Baseline/Firefox-157.0.app"
codesign --verify --deep --strict --verbose=2 "<case-root>/Baseline/Firefox-157.0.app"
spctl --assess --type execute --verbose=4 "<case-root>/Baseline/Firefox-157.0.app"
xcrun stapler validate "<case-root>/Baseline/Firefox-157.0.app"
```

What this does and does not establish:

- **The manifest is a proposal.** `/usr/sbin/mtree` is present on the host. Its acceptance of these keywords, its handling of symlinks and its exit status on a mismatch have not been validated on the guest's macOS. Validate them first on a throwaway directory inside the case root, including one deliberate mismatch. Until then no manifest result is a recovery proof.
- **The manifest is partial.** These keywords cover type, mode, size, symbolic-link target and content digest. They omit extended attributes, ACLs, resource forks and quarantine state. A matching manifest shows those listed properties match and nothing more. `mtree` alone never establishes that a bundle is recoverable.
- **The recovery contract.** The preserved copy counts as a recovery basis only when it matches the manifest and also passes its own signature, Gatekeeper and ticket checks above, and only once the copy method has been validated to carry the metadata those checks depend on. `ditto` is proposed for that and is unvalidated here.
- **The copy is a held reference.** No case restores a target from it. Recovery in cases 10, 13 and 14 is the transaction's own exchange. Using the copy for a manual restore would need the owner's exact authority.
- `xcrun` needs the developer tools recorded in Phase 2. Without them this phase is not run.
- Two bundles per case root is a large space demand. It is unmeasured until Phase 2 records free space.

The proof profile is created empty and its manifest recorded the same way. Stop if any line fails.

### Phase 6: acceptance matrix

Needs: the harness accepted and reviewed, and the accepted run scope, which covers every case here including the launch for case 8 once its isolation precondition is met.

Every command in this section is **PROPOSED, DOES NOT EXIST**. Case names, case roots and expected outcomes are proposals until the harness's semantics are validated. A refusal must be the named one, not any error.

Common form:

```sh
./scripts/prove-disposable.sh --target-id <approved-id> --run-id <run-id> --case-root <case-root> --case <case>
```

Case roots. Each independent case has its own exclusively created root. Three linked pairs share the root that holds their one transaction, because the second case acts on what the first left there.

| Case root | Cases |
| --- | --- |
| One each, named after the case | 1 to 5, 8 |
| `invalid-signature`, `untrusted-key` | The two independent variants of 6 |
| `replayed-sequence`, `expired-catalogue` | The two independent variants of 7 |
| `staging` | 9, then 10 |
| `update` | 11, then 14 |
| `swap` | 12, then 13 |

| # | Case | Real condition, not a fixture | Expected (proposed) |
| --- | --- | --- | --- |
| 1 | `tampered-artifact` | A copy of the 157.0.1 image with one byte changed at a recorded offset | Refused on digest before any mount. Target matches its baseline manifest |
| 2 | `truncated-artifact` | The first 80,000,000 bytes of the 157.0.1 image, as an interrupted download leaves | Refused on length. Target matches its baseline manifest |
| 3 | `recorded-evidence` | The Phase 4 report for 157.0.1 offered in place of a live inspection | Refused (`recordedEvidenceRefused`). Target matches its baseline manifest |
| 4 | `wrong-signer-target` | The target in this root is re-signed ad hoc after its baseline, so it has no Team ID | Refused on the target's signer. Target matches its after-mutation manifest |
| 5 | `wrong-signer-staged` | The staged 157.0.1 bundle is re-signed ad hoc at a declared pause before the swap | Refused by the macOS check of the stage made after the pause. No swap. Target matches its baseline manifest |
| 6 | `invalid-catalogue` | A test catalogue with one signature byte changed, and separately one signed by an unrelated test key | `invalidSignature`, `untrustedKey`. Checkpoint unchanged. Target matches its baseline manifest |
| 7 | `replayed-catalogue` | A lower sequence presented after a higher one was accepted, and an expired one | `replay`, `expired`. Checkpoint unchanged. Target matches its baseline manifest |
| 8 | `open-app` **launch** | Firefox 157.0 running from this root's app destination with the proof profile | Deferred (`appRunning`). Nothing quit. Target matches its baseline manifest. The case ends at the deferral |
| 9 | `staging-failure` | The harness process is killed during the stage copy | No completed report. Partial journal and witness evidence retained. Target matches its baseline manifest |
| 10 | `recover-after-staging` | `recover` in the `staging` root after case 9 | `rolledBack`, `oldAlreadyInPlace`. Target matches its baseline manifest |
| 11 | `update` | The actual 157.0 to 157.0.1 update on an explicit trigger | `committed`. See [Phase 7](#phase-7-the-actual-update-record) |
| 12 | `interrupted-swap` | The harness is killed after the swap and before the commit record | No completed report. Partial journal and witness evidence retained. New bundle at the target, old bundle whole in the exchange directory |
| 13 | `recover-after-swap` | `recover` in the `swap` root after case 12 | `rolledBack`, `restoredOldBySwap`. Target matches its baseline manifest and passes the macOS checks |
| 14 | `restore-old` | `decide restoreOld` in the `update` root after case 11 | `rolledBack`. Target matches its baseline manifest and passes the macOS checks |

"Matches its manifest" means the Phase 5 `mtree` check exits 0 for the listed keywords. Where the row says so the macOS checks are run as well. It is not a claim about metadata the manifest omits.

Preparing the real conditions. These are ordinary macOS commands, each acting only inside the run root.

**EXISTS, UNRUN HERE**

```sh
cp "<run-root>/Incoming/Firefox 157.0.1.dmg" "<run-root>/Incoming/tampered.dmg"
printf '\000' | dd of="<run-root>/Incoming/tampered.dmg" bs=1 seek=<recorded-offset> conv=notrunc
shasum -a 256 "<run-root>/Incoming/tampered.dmg"
head -c 80000000 "<run-root>/Incoming/Firefox 157.0.1.dmg" > "<run-root>/Incoming/truncated.dmg"
codesign --force --deep --sign - "<bundle-inside-its-case-root>"
codesign -dvvv "<bundle-inside-its-case-root>"
mtree -c -n -k type,mode,size,link,sha256digest -p "<run-root>/Cases/wrong-signer-target/Applications/Firefox.app" > "<run-root>/Cases/wrong-signer-target/Baseline/target-mutated.mtree"
```

The byte at the recorded offset must be read first and must not already be zero; the tampered digest must differ from the pin. Ad hoc signing uses no key and creates none. It is applied only to the target of the `wrong-signer-target` root and to the stage of the `wrong-signer-staged` root, never to a baseline copy.

Notes on individual cases:

- **Case 4** changes its own target on purpose, so its baseline manifest no longer describes that target and is never compared with it. The order is: baseline, ad hoc re-sign, then the after-mutation manifest in the last line above, captured before the harness is asked to refuse. The proof is that the target still matches that after-mutation manifest once the refusal is recorded. The re-signed bundle is kept as evidence. Nothing recovers it: restoring an arbitrarily altered target is not a capability this proof has or claims. The next case uses its own root and its own fresh baseline.
- **Case 5** depends on the harness asking macOS about the staged bundle immediately before the swap, after the pause in which the stage is re-signed. A check made only before the pause would not see the change. Whether the pause point is acceptable is for the harness review.
- **Cases 4 and 5** are the two honest ways to reach the signer check without widening the compiled pins. A re-signed app inside a new disk image has a different digest and is refused as a tampered artifact first, so that route shows case 1 again, not a signer refusal.
- **Cases 6 and 7** need test catalogues issued for this run: the fixture lifetime limit is 259,200 seconds and the fixed fixtures from `--emit-fixed-fixture` use a fixed clock. They are signed with the deterministic test key in the test targets. That key is test trust. It is never production and no result may read otherwise. Each variant owns the checkpoint in its root; the replay variant seeds the higher accepted sequence before presenting the lower one. No transaction root is reused between independent variants.
- **Case 8** is the only case that needs Firefox running. It is started by a person in the guest, from that root's app destination, with `-profile "<run-root>/Cases/open-app/Profile" -no-remote`, and closed by that person. The harness quits nothing and the check is an OS observation of that exact bundle, not a process-list match on a name.
- **Cases 9 and 12** are real process deaths, not injected refusals. They need the pause points described under [Future narrow paths](#future-narrow-paths). A killed harness writes no completed report, and a missing report is never read as success or as a clean stop. The evidence is what the process durably left: the journal bytes and their digest, any witness record, the signal and exit status the wrapper saw, and manifests of the target, stage and exchange directory read afterwards. Cases 10 and 13 then run in the same root against that state. A volume too small to hold the stage is a possible second staging failure; it needs a disk image created in the guest and is not proposed for the first run.
- **Order.** Refusals first, then the update, then recovery, so that a harness fault is found before any target is replaced. The fixture contract allows one transaction per root for its lifetime, and the root table above keeps that rule for the proof authority.

### Phase 7: the actual update record

For case 11 the report must record, before and after, from physical reads and fresh macOS commands at the app destination:

- version and bundle identifier from `Info.plist`
- Team ID and signing identifier from `codesign -dvvv`
- `codesign --verify --deep --strict` exit and output
- `spctl --assess --type execute --verbose=4` exit and output
- `stapler validate` exit and output
- the installed bundle manifest and its SHA-256, before and after
- the artifact digest and byte length as re-verified by the harness on the bytes it held
- the harness's own mount: attach result, the checks run on it, and the detach outcome as observed
- the Phase 4 report digest for that image, as a comparison only
- the test catalogue's key ID, catalogue ID, sequence and payload SHA-256
- the harness source revision and binary SHA-256 from Phase 3
- guest OS version, build and architecture, and the UTM UUID
- the trigger, the transaction ID, the journal states reached and the exchange path
- the container results from Phase 4, still separate and still failures if they failed

The report must state its own limits in fields, not prose: test catalogue trust, case-root target, no production key, the keywords its manifests cover, and the signing state of the harness binary.

### Phase 8: after the run

**EXISTS, UNRUN HERE**

```sh
stat -f '%N%t%i%t%m%t%z' /Applications/*.app | LC_ALL=C sort
stat -f '%i%t%m%t%Sp%t%Su' "$HOME/Library/Application Support/Firefox"
stat -f '%i%t%m%t%Sp%t%Su' "$HOME/Library/Caches/Firefox"
mtree -f "<case-root>/Baseline/target-157.0.mtree" -p "<case-root>/Baseline/Firefox-157.0.app"
pgrep -lx firefox
shasum -a 256 "<run-root>/Evidence/report.json"
```

The `mtree` line is repeated for every case root. The `/Applications` listing and the two directory lines are compared with Phase 2, and any difference is reported as found, including a directory that exists now and did not before. Equal lines are reported as unchanged root metadata. They are not reported as proof that unrelated apps or an existing profile were preserved in full, for the reason given under [Profile privacy](#profile-privacy).

Nothing is cleaned up. The run root, every case root, the exchange directories, the baseline copies, the journals, the re-signed bundles and every failed case's leftovers stay in the guest. Removing the run root, or restoring the guest to its pre-run state, happens only after the guest is positively identified again by the Phase 1 values and the owner gives explicit authority for that exact deletion. No reset and no guest deletion is part of this proof.

The report is copied out unchanged to `evidence/first-proof/<run-id>/report.json` with its SHA-256 recorded on both sides. Committing it is the parent's decision.

## Stop conditions

Stop, change nothing further and report, if any of these is observed:

- `kern.hv_vmm_present` is not `1`, or the platform UUID differs from the one recorded at the console.
- The guest name, UTM UUID or state differs from the recorded observation.
- The run root or a case root already exists, or an app destination is anything other than the accepted path.
- Firefox is running when the case does not call for it.
- A baseline command fails, or a preserved copy does not match its manifest or fails its macOS checks.
- A refusal case passes, a refusal has the wrong name, or a target differs after a refusal from the manifest that case names.
- The held image no longer matches its pin when the harness re-verifies it.
- A step would need `sudo`, a setting change, new software, a new key, a credential or the network beyond the accepted host.
- A detach fails (`cleanupFailed`), in the inspector or in the harness's own mount. The workspace is left as it is for the owner.

## Cost and credentials

The cost-reconciliation gate is waived for this bounded work until further notice. The £500 incremental cap remains. The actual cost of this preparation and of any later run is unknown and must be recorded as unknown, never as zero. No purchase is proposed. No key, certificate, Developer ID identity, notarisation credential or account is created or requested by this runbook.

## Owner gates

**Single remaining gate before any guest writes:** accept one exact scope covering the exclusively created run root, case roots, app destinations and new profile; the transfer route and images; the restorable baseline/recovery contract; and the reviewed harness scope. Routine operations within that accepted scope do not need repeated prompts.

Case 8 remains conditional on a reviewed isolation proof or precondition that confines launch writes. The observed absence of Firefox support/cache roots is only a current precondition observation; it does not prove that launch cannot write elsewhere or establish restoration. The existing `/Applications/Firefox.app` is present and is never disposable.

The already-approved legacy quiescence is complete and separate from the still-required harness implementation/review gate. The harness tools do not exist; acceptance requires meaningful acceptance checks demonstrated failing before and passing after the change, the full verification gate, and fresh independent OpenCode/NVIDIA review of the complete diff. Supported signing identity, notarisation and production keys remain outside this proof.

## Recommended UNBLOCKS-WHEN

The previously recorded guest-reachability condition is now met by the 9 October SSH preflight and is no longer the blocker. Recommended replacement is the single remaining gate:

> UNBLOCKS-WHEN: one exact isolated run scope, transfer route, restorable baseline/recovery contract and reviewed harness scope are accepted before any guest writes.

Guest reachability and the dated read-only subset are now recorded; they no longer describe the blocker. The case 8 isolation precondition remains part of the exact-scope review.

A possible split, as a proposal only: keep PAT-2584 as the execution and evidence ticket and build the harness under a separate implementation ticket that blocks it, because the harness is real trust-boundary logic and should not be reviewed inside an execution run. This document raises no ticket and authorises no code.
