# Fixture bundle transaction and recovery

PAT-2582. This document defines the interfaces and behaviour that `Tests/PatchedTransactionChecks` and `Tests/PatchedUIChecks` assert. The fixture authority and the fixture transaction (`perform`, `recover`, `decide`) are implemented in `Sources/PatchedCore`, with the pure presentation `UpdatePresentation.make`. The visible words (`UpdateViewText`) and the one shared view (`UpdateView`) are implemented in `Sources/PatchedUI`. The default entry points always refuse. Everything here is fixture behaviour: it is not an installed update, a released app or evidence about Firefox.

## Authority and scope

The transaction replaces one app bundle directory with a verified staged copy, keeps the old bundle, and can put it back. In this proof it runs only inside a disposable fixture root. It never names the installed Firefox, `/Applications`, a home directory or a browser profile, and it launches nothing.

There are two entry points.

- `UpdateTransaction.perform` and `UpdateTransaction.recover` are the default entries. No production authority exists in this proof, so both always refuse with `notAuthorized` before reading any path. A fixture `CatalogueCandidate`, a caller-supplied report and a well-formed request are all insufficient.
- `FixtureAuthority` is test-only (`@_spi(Testing)`). `createFreshRoot(path:)` exclusively creates one directory named `patched-transaction-fixture-<suffix>` with mode 0700, directly beneath the physical `.build` directory that is an ancestor of the running check executable, and writes `fixture-root.json` (`schemaVersion` 1, `kind` `patched-transaction-fixture-root-v1`, the root's `device` and `inode`; mode 0600). It never adopts an existing directory (`existingRoot`). A root elsewhere is `notAuthorized`; a relative, traversing or wrongly named path is `unsafePath`; a symlinked component is `symlink`. `reopenRoot(path:)` lets a fresh process resume the same root only when the marker's recorded identity matches the directory physically observed.

Every fixture result says `origin: fixture`, `freshOSValidation: false`, `installationAuthorized: false`, `installedFirefoxProof: false`. `TransactionReport` and `BundleManifest` have no public constructor and are not decodable. Verification of a real artifact by macOS, and authority over a real target, are a separate future trust boundary (PAT-2584). They must not be built by accepting a caller-made inspection report.

## Fixture layout and request

A request names every path exactly. Inside an authority root the only accepted positions are:

- target: `<root>/Applications/<name>.app`
- source bundle: `<root>/Incoming/<name>.app`, the same `<name>.app`
- artifact: a regular file directly inside `<root>/Incoming`
- transaction directory: `<root>/Transaction`

Any other position is `notAuthorized`. A relative path, an empty, `.` or `..` component or a trailing slash is `unsafePath`. A source equal to the target is `aliasedPath`. A trigger other than `explicitUserAction` is `userTriggerRequired`. These request checks use only the strings and precede all filesystem access. One root supports one transaction for its lifetime; an existing transaction directory in any state is `existingTransaction`.

The artifact is the pinned bundle manifest. Its exact bytes must match the signed catalogue candidate's `sha256` and `byteLength` (`artifactMismatch` otherwise). It is a strict UTF-8 JSON object of at most 262,144 bytes with exactly `schemaVersion` 1, `kind` `patched-fixture-bundle-manifest-v1`, `bundleName`, `bundleID`, `version` and `entries`. Entries start with the bundle root `.`; every other entry follows in ascending path byte order without duplicates, beneath a directory entry of the same document. A directory entry has exactly `path`, `type: directory` and `mode`; a file entry adds `byteLength` and lowercase `sha256`. `mode` is the decimal value of the permission bits, 0 to 4095. Paths are relative with no empty, `.` or `..` component and no ASCII control scalar (0 to 31 or 127). Anything else is `invalidManifest`. A manifest for another bundle name or identifier is `wrongBundle`, and for another version `wrongVersion`.

The tree digest is SHA-256 over one line per entry in that order: type, path, four-digit octal mode, byte length and digest (`-` for a directory, with length 0), separated by tabs and ended by a newline.

The digest encoding is line based and embeds tab and line feed, so it is ambiguous for names containing them: one empty directory named `a<TAB>0755<TAB>0<TAB>-<LF>directory<TAB>b` and two empty directories `a` and `b` produce identical line bytes. This is an encoding ambiguity, not a SHA-256 collision. The digest format is unchanged; the narrower relative-entry-path contract above removes the ambiguity. A control character in a manifest entry path is `invalidManifest`. A physical source or target entry with such a name is `unsafePath`, before any transaction state. NUL can appear only in the signed manifest document, never in a physical name.

Fixture bounds apply to the manifest and to every tree read: 512 entries, depth 16, 8 MiB in total (`treeLimit`). Production bounds are a later decision.

## Checks before any transaction state

All of the following happen before the transaction directory is created. A refusal here leaves the whole root physically unchanged.

1. Request shape and authority, as above.
2. The root, `Applications` and `Incoming` are walked by descriptor without following links. Each must be an owned directory with mode 0700 (`symlink`, `unsafeOwner`, `unsafeMode`).
3. The artifact is an owned single-link regular file with mode 0600 or 0644. Its bytes are read and compared with the candidate, then parsed. A missing artifact or source bundle is `missingSource`; a source that is not a directory is `notDirectory`.
4. The source tree is read physically. Every entry must be an owned directory with mode 0700 or 0755, or an owned single-link regular file with mode 0600 or 0644. A symlink is `symlink`, a FIFO, socket or device `specialFile`, a second link `hardlink`, any other mode (including any execute bit on a file) `unsafeMode`. Physical safety is judged before comparison with the manifest.
5. The source tree must equal the manifest entry for entry (`manifestMismatch`).
6. `Contents/Info.plist` of the source is read (at most 64 KiB). Package type must be `APPL` (`invalidBundle`); identifier and short version must equal the candidate (`wrongBundle`, `wrongVersion`).
7. The target is read the same way: `missingTarget`, `notDirectory`, then the same entry rules. Its identifier must equal the candidate (`wrongBundle`) and its numeric version must be strictly older (`notNewer`; unreadable or non-numeric is `invalidBundle`). The old tree's manifest and the first journal record are built here and must read back through the strict parsers before any state exists.
8. The fixture running declaration is consulted for the exact bundle identifier. If it says the app is open the transaction refuses with `appRunning`. Nothing is quit. This declaration is a test hook and is reported as `runningCheck: fixtureProbe`; it is never an OS observation.

Owner mismatch and a different filesystem (`crossVolume`) are part of the contract but cannot be produced in an unprivileged single-volume fixture. They have no acceptance case.

## Transaction

The transaction directory is created exclusively with mode 0700 and its parent synchronised. It holds `lock` (empty, mode 0600, held with an exclusive non-blocking `flock`; contention is `busy`), `journal.json`, `before-manifest.json`, `after-manifest.json` and `exchange/` (mode 0700). All files are owned, single-link and mode 0600.

`journal.json` is a strict JSON object of at most 16 KiB with exactly: `schemaVersion` 1, `kind` `patched-fixture-transaction-journal-v1`, `transactionID`, `state`, `bundleName`, `bundleID`, `fromVersion`, `toVersion`, `cataloguePayloadSHA256`, `artifactSHA256`, `targetPath`, `exchangePath`, `device`, `oldInode`, `newInode`, `beforeManifestSHA256`, `afterManifestSHA256`, `beforeTreeSHA256`, `afterTreeSHA256` and `origin: fixture`. `after-manifest.json` is a byte copy of the verified artifact. `before-manifest.json` is the old tree in the same manifest schema. Both are created exclusively under their final names before any journal exists, and flushed with `fsync` and `F_FULLFSYNC` (`journalFileFullSync`). Each journal state is written to a new private file, flushed with `fsync` and `F_FULLFSYNC` (`journalFileFullSync`), renamed over `journal.json`, and the directory synchronised (`journalDirectorySync`), followed by a second `F_FULLFSYNC` through the retained descriptor, which has no probe. A failed flush has no weaker fallback. If a step fails after the rename, the new record is visible but was never reported: the caller gets `persistenceFailed` and `recover` decides from what is physically present. A private journal file left by a refused write is never removed. The names in brackets here and below are the test-only synchronisation probes, each called before its syscall.

Steps, with the test boundary reached after each:

1. Create the transaction directory and synchronise its parent (`transactionParentSync`, then `transactionDirectoryCreated`); take the lock (`lockAcquired`).
2. Create `exchange/`, freeze both manifests and write journal state `prepared` (`journalPrepared`).
3. Exclusively create `exchange/<name>.app` (`stageCreated`) and write into it, through held descriptors, the source bytes that were read and matched to the manifest before any state existed (`stageCopied`); the source is not read a second time. Then `F_FULLFSYNC` every staged file (`stagedFileFullSync`, once per file), `fsync` every staged directory including the bundle root (`stagedDirectorySync`, once per directory) and the exchange directory (`exchangeDirectorySync`), before `stageSynced`.
4. Read the staged bytes again from the held stage and compare them with the manifest (`stagedBytesMismatch`); write state `staged` with the staged identity (`stageVerified`).
5. Write state `swapIntended` (`swapIntended`). Consult the running declaration a second time and confirm every held directory is still the entry at its name (`identityChanged`).
6. Exchange target and staged bundle with one `renameatx_np(RENAME_SWAP)` on the held parent descriptors (`swapped`). The old bundle is now `exchange/<name>.app` with its original identity.
7. Synchronise the target's parent (`targetParentSync`) and the exchange directory (`exchangeDirectorySync`), then `targetParentSynced` and `beforeCommitRecord`, read both bundles again in full and confirm their identities and bytes, then write state `committed` and return the report. The swapped bytes are on disk before this record; only the record makes them the accepted state.

The root, its marker (identity and contents) and every held directory are confirmed after each test hook and before each write. So are `Incoming`, the source bundle and the artifact as first captured: each name must still show the same owned entry with a permitted mode, and the bytes verified before any state existed stay the bytes that are staged, so a substitute is never read. A renamed or substituted target, ancestor, incoming directory, source bundle, artifact, transaction directory or exchange directory is `identityChanged`, and nothing is written into the substitute. A same-user process that substitutes the named target between the last confirmation and the swap cannot be prevented; the identities checked after the swap then match no recorded state and the transaction fails closed.

A test probe can observe or refuse at a boundary or before a synchronisation call. A refusal there, or any failed write, flush or rename, is `persistenceFailed` with no report. The transaction does not undo itself in place. Before the swap the old bundle is untouched; after it the old bundle is whole in the exchange directory.

The old bundle is kept until an explicit decision, and afterwards. `decide(.keepNew)` records `finalized`. `decide(.restoreOld)` first withdraws the commit by recording `swapIntended`, then swaps the bundles back (boundaries `beforeSwapBack`, `swappedBack`) and records `rolledBack`; an interruption on either side of that exchange is therefore an uncommitted swap that `recover` resolves to the old bundle. Both decisions need an explicit trigger, a `committed` journal (`invalidState` otherwise) and both bundles matching their recorded identity and tree digest (`ambiguousState` otherwise); a restore also needs the app declared closed, checked before anything is recorded. This proof never deletes a bundle. The owner removes the disposable root.

## Recovery

`recover` runs in any process with a reopened authority. Its transaction directory must be the authority's own (`notAuthorized`, `unsafePath`). It takes the lock, reads the journal and both frozen manifests, and reads both bundles physically.

- No transaction directory or no `journal.json`: `journalMissing`.
- Unparseable, truncated, oversized, unknown field, state, schema or origin: `journalCorrupt`.
- A journal that disagrees with the authority's layout or with the frozen manifests (paths, bundle, versions, manifest digests, tree digests, missing manifest): `journalMismatch`.
- Evidence that breaks the physical rules: `symlink`, `hardlink`, `specialFile`, `unsafeMode`.
- `committed`, with the new bundle at the target and the old one in the exchange directory, each matching its recorded identity and tree digest: reported unchanged, `recoveryAction: none`.
- An uncommitted state with the old bundle still at the target, matching identity and digest: state becomes `rolledBack`, `oldAlreadyInPlace`. The stage may be absent, partial or complete; `exchangeNow` reports it as physically read, and is empty when it is absent.
- `finalized` with both bundles matching, or `rolledBack` with the old bundle at the target matching: reported unchanged, `recoveryAction: none`.
- `swapIntended` with the new bundle at the target and the old one in the exchange directory, both matching: the app must be declared closed, the bundles are swapped back, and the state becomes `rolledBack`, `restoredOldBySwap`.
- Anything else, including a changed byte, an extra file, a missing bundle or an identity that matches neither record: `ambiguousState`.

A refusal while the evidence is being validated leaves all paths as found. An operational failure after recovery has begun to act is different: a failure after the exchange or during a journal write can leave the two bundle names exchanged, a newer journal record visible, and a private journal file retained as evidence. That state is not repaired in place; guarded recovery must be run again and decides from what is physically present. Recovery holds no incoming descriptors and does not check the incoming side. Recovery never deletes a path, never repairs a journal from outside information and never chooses between bundles it cannot identify. An interrupted recovery can be run again.

The journal lives in a trusted same-user directory. A same-user process that substitutes an entry before it is first captured, or rewrites the journal and the bundles consistently, is not detected. Successful flush calls are not a guarantee against hardware failure, and no power-loss test is claimed.

## Presentation

`UpdatePresentation.make` is a pure function from plain display input to strings. It reads no path, schedules nothing and grants nothing. Its refusal strings carry the raw code and are diagnostic data, not visible product text; the visible words are defined under Visible text below. `Sources/PatchedUI/UpdateView.swift` is the one shared view, laid out with system text styles and used by both the app target and the checks. It converts the presentation with `UpdateViewText` when it is created and lays out only those words, so no diagnostic string reaches the screen. The app target is compiled by the gate and never launched.

- Notice, always: `Fixture preview. No installed app is checked or changed.`
- Heading: `<app> <candidate version>`, or `No update candidate`. Then `Installed: <version>` or `Installed: unknown`, and `Checked: YYYY-MM-DD HH:MM UTC`, `Checked: never`, or `Checked: unknown` for a clock that is not finite, is negative or is later than 9999-12-31 23:59 UTC. That range is checked before any numeric conversion. A valid clock is shown as its whole UTC minute in the Gregorian calendar, independent of the Mac's locale and time zone. No time is ever invented for an invalid clock, and the same rule applies to a deferral time.
- Four rows in fixed order: `Catalogue signature` and `Staged bytes` (`Not run`, `Passed`, `Refused: <reason>`); `macOS signature and notarisation` (`Not run in this fixture preview`); `App closed` (`Not checked`, `Closed`, `Open. Patched will not quit it`).
- A refusal is shown as `Refused: <reason>`. A deferral is shown as `Deferred until <time>. Nothing runs on its own.` (`Deferred. Nothing runs on its own.` for an invalid time) and does not disable the action.
- The action is `Update <app>`. It is enabled only with a candidate, no refusal, both fixture checks passed, the app declared closed and an approved fixture target. Its note explains the first unmet condition in that order: `No update candidate.`, `Refused. Nothing runs until you choose Update again.`, `Checks have not passed.`, `App state not checked.` or `<app> is open. Close it yourself, then choose Update.`, `No approved target.` When enabled the note is `Fixture target: <path>. Runs only when you choose Update.`

The compiled app's default state has no candidate and no approved target, so its action is disabled. It has no timer, network request or background work.

## Visible text

This section is the reviewed copy that `UpdateViewText` in `Sources/PatchedUI` implements and `Tests/PatchedUIChecks` asserts.

`UpdateViewText(presentation)` is a pure conversion from one prepared `UpdatePresentation` to the words the view shows. It is display only. It stores ten values (the notice, heading, installed line, checked line, rows, refusal line, deferral line, action title, enabled flag and note) and nothing else: no callback, path authority or operation. Its enabled flag is the presentation's flag, so it can never enable an action the presentation disabled. `UpdateView` lays out only these values.

- The notice, heading, installed line, checked line, deferral line, action title and action note are the presentation's own strings, unchanged. Every state keeps `Fixture preview. No installed app is checked or changed.` and the row `macOS signature and notarisation`: `Not run in this fixture preview`.
- A row status beginning `Refused` is shown as `Did not pass`. The code that follows `Refused:` is never shown. The known statuses are shown unchanged (`Not run`, `Passed`, `Not run in this fixture preview`, `Not checked`, `Closed`, `Open. Patched will not quit it`). Any other row status is shown as `Not checked`, so no unreviewed diagnostic text can appear in a row.
- A refusal line `Refused: <code>` is shown as the reason for that code alone, without the word `Refused:`. A code that is not exactly one of the names below, including an empty one, a different case or surrounding spaces, is shown as `The update was refused.`
- Every reason is one or two brief ASCII sentences of at most 90 characters, with no colon, underscore, raw code or camel-case word, and none of the health, background or dash wording the presentation already bans.
- No reason says that nothing changed, that the app is unchanged, intact, restored or rolled back, or uses the word safe. A refusal can follow the exchange or a failed record, so the visible text never promises the state of the app. `identityChanged`, `existingTransaction` and `persistenceFailed` end with `Recovery may be needed.`

| Code | Visible reason |
| --- | --- |
| `notImplemented` | This step is not available in this preview. |
| `notAuthorized` | Patched is not authorised to make this change. |
| `userTriggerRequired` | An update starts only when you choose Update. |
| `unsafePath` | That location cannot be used for an update. |
| `aliasedPath` | The update and the app are in the same place. |
| `existingRoot` | The preview folder already exists. |
| `missingTarget` | The app to update was not found. |
| `missingSource` | The update files were not found. |
| `notDirectory` | Something that should be a folder is not a folder. |
| `symlink` | A link was found where a real file or folder is required. |
| `hardlink` | A file with more than one name was found. |
| `specialFile` | An unsupported kind of file was found. |
| `unsafeOwner` | A file or folder belongs to a different user. |
| `unsafeMode` | A file or folder has permissions Patched does not accept. |
| `crossVolume` | The update and the app are on different disks. |
| `treeLimit` | The app is too large for this preview. |
| `artifactMismatch` | The update file does not match the catalogue. |
| `invalidManifest` | The update's list of files could not be read. |
| `manifestMismatch` | The update files do not match their list. |
| `stagedBytesMismatch` | The copied update files do not match their list. |
| `invalidBundle` | The app's details could not be read. |
| `wrongBundle` | The update is for a different app. |
| `wrongVersion` | The update is not the expected version. |
| `notNewer` | The update is not newer than the app. |
| `appRunning` | The app is open. Close it yourself, then choose Update. |
| `identityChanged` | Something changed on disk during the update. Recovery may be needed. |
| `existingTransaction` | An earlier update attempt is on record. Recovery may be needed. |
| `busy` | Another update is in progress. |
| `persistenceFailed` | Patched could not save its progress. Recovery may be needed. |
| `journalMissing` | No record of an update was found. |
| `journalCorrupt` | The update record could not be read. |
| `journalMismatch` | The update record does not match what is on disk. |
| `ambiguousState` | Patched cannot tell which version is in place and will not guess. |
| `invalidState` | That step is not available at this stage. |
| anything else | The update was refused. |

The checks also give the clock rule above extreme values for both the checked time and the deferral time: the greatest finite magnitude and its negative, the first second of year 10000, values beyond the 64-bit integer range, both kinds of not-a-number, both infinities and small negative values. Each must produce `Checked: unknown` and `Deferred. Nothing runs on its own.` with no digit shown and no trap, and must leave every other part of the state as it was. The last minute of year 9999 is still shown as `9999-12-31 23:59 UTC`.

## Painted states

`Tests/PatchedUIChecks` paints the actual `PatchedUI.UpdateView` offscreen with SwiftUI `ImageRenderer` at 480 points wide and scale 2, for four states built by `UpdatePresentation.make`: `default`, `ready`, `running` (app open) and `refused-deferred` (`persistenceFailed` with a deferral). No app is launched or activated. Each run exclusively creates one directory `patched-ui-fixture-<UUID>` (mode 0700) directly beneath the `.build` that holds the check executable, and writes `default.png`, `ready.png`, `running.png`, `refused-deferred.png` and `metadata.json` (the display input, the diagnostic presentation, the visible text, pixel size and PNG digest for each state). No caller chooses the path. The directory is kept for inspection and is not removed by the check; `.build` is ignored by Git.

The checks require each image to be 960 pixels wide, between 100 and 4,000 pixels high, not blank and a readable PNG; the four states to paint different pixels; and each state to have been laid out from the expected presentation with the fixture notice. They also require that no state contains the renderer's yellow stand-in for a control it could not paint. SwiftPM stamps the executable with the package's macOS 13 platform as its SDK version, and with that stamp the default, bordered and borderless button styles are drawn by AppKit and are not painted offscreen. The view therefore uses its own SwiftUI button style, which is painted: a filled accent shape with white text when enabled, the same shape dimmed while pressed, and a grey outlined shape with grey text when disabled. Every text wraps onto further lines within the 480 point width instead of being clipped. The button calls only the callback its caller passed, on a click, and is disabled whenever the presentation's action is disabled.

Run `./scripts/verify-ui.sh` to build and paint the four states; it prints the directory it created. The full `./scripts/verify.sh` includes it after the transaction checks.

Painted output supports visual review of the layout only. It is not evidence of macOS trust, of an installed update or of anything about Firefox. It is an offscreen picture of four prepared states in the light appearance at one width. It does not show a window, the dark appearance, other text sizes, keyboard focus or VoiceOver, and the pressed appearance and a real click are not exercised by any check.
