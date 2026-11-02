# Schedule preference record Phase A contract

PAT-2668, 16 October 2026. Preparation only: the three new codec methods throw
`PreferenceRefusal.unimplemented`. No build or check was run by this preparation
leaf. The parent must accept this interface, observe meaningful compiling RED,
freeze checks/interfaces/fixtures and release a different fresh implementation
leaf before either source file implements a codec.

This is a pure version-2 wire prerequisite. It neither persists nor acknowledges
settings, supplies clock/permission/eligibility evidence, executes a receipt,
changes policy, nor creates a store/session/queue. The existing sole
`PreferenceSession`/CAS/queue owner remains untouched. App/helper/native/timezone
lookup, effects, production composition and installed proof are outside scope.

## Proposed immutable interface

All value properties are public `let`, `Equatable` and `Sendable`. Value
initialisers are `@_spi(Testing)` unvalidated declarations, including deliberately
invalid values for adversarial checks. Enum cases also declare inert changes.
They grant no authority. No public validated-record constructor or persistence
acknowledgement is introduced.

```swift
SchedulePauseChoice(resumeUTC: Int64, displayZone: String)
ScheduleSettings(dailyChecks: Bool = true, notifications: Bool = true,
                 automaticUpdates: Bool = false, pause: SchedulePauseChoice? = nil)
enum ScheduleSettingsChange {
    case dailyChecks(Bool), notifications(Bool), automaticUpdates(Bool)
    case pause(SchedulePauseChoice?)
}
ScheduleSettingsMutationReceipt(id: String, change: ScheduleSettingsChange)
SchedulePreferenceRecord(schema: UInt64 = 2, preferences: PreferenceRecord,
                         settings: ScheduleSettings,
                         settingsMutations: [ScheduleSettingsMutationReceipt] = [])
SchedulePreferenceMigrationProposal(originalV1Bytes: Data, proposedV2Bytes: Data,
                                    record: SchedulePreferenceRecord)

SchedulePreferenceRecordCodec.encode(_ record: SchedulePreferenceRecord) throws -> Data
SchedulePreferenceRecordCodec.decodeV2(_ bytes: Data, principal: SchedulingPrincipal,
                                       storeScope: String) throws -> SchedulePreferenceRecord
SchedulePreferenceRecordCodec.proposeV1Migration(_ bytes: Data, principal: SchedulingPrincipal,
                                                 storeScope: String) throws -> SchedulePreferenceMigrationProposal
```

The migration proposal has exactly the three named immutable properties. It is
an inert deterministic value, not an accepted state or CAS result. Its record
contains the decoded schema-1 preferences, default settings and zero new receipts.
The original bytes and proposed bytes remain separate so a later existing CAS
owner can compare the unchanged input and independently validate any write.

## Exact wire

Root has exactly `preferences`, `schema`, `settings`, `settingsMutations`.
`schema` is the exact integer 2. `preferences` is a transparent JSON **string**
containing unchanged canonical schema-1 JSON, never base64, compressed, encrypted
or a second schema parser. Encode validates/reuses unchanged
`PreferenceRecordCodec.encode`; decode and migration validate/reuse unchanged
`PreferenceRecordCodec.decode` with the exact caller principal and store scope.
Inner revision, exclusions, skips and old operation strings/history are retained.
The outer adds no second revision, authentication status, clock or ownership claim.

The default literal v1/v2 files have no trailing newline. Canonical JSON uses
sorted keys and unescaped slashes, matching the existing Foundation JSON style.
Typed decode followed by exact canonical re-encode must refuse unknown/duplicate
fields at every level, noncanonical key order/escapes/numbers/whitespace, BOM and
invalid UTF8. UInt64 revision including max stays exact in the inner string,
without any floating-point round trip.

`settings` has exactly Bool `dailyChecks`, Bool `notifications`, Bool
`automaticUpdates`, and `pause` (required null or object). Defaults are true,
true, false, nil. A pause object has exactly `displayZone` (String) and
`resumeUTC` (nonnegative Int64). Its zone is 1...128 UTF8 bytes of ASCII segments
matching `[A-Za-z0-9_+-]+`, separated by single `/`. Empty segments, dots, control
characters and Unicode refuse. This syntactic label need not exist in an OS zone
database. It is display intent only. Retain zero, past and future instants exactly;
there is no clock sampling, rounding, conversion, expiry autoclear or deadline
extension. A saved pause does not construct the existing anchored `AutomaticPause`.

`settingsMutations` is an ordered array of exactly `{id, change}` receipts.
`change` is a closed object with `action` plus exactly `enabled` Bool for
`dailyChecks`, `notifications` or `automaticUpdates`; action `pause` has exactly
`pause` null or the same closed pause object. No embedded new operation strings.
IDs use existing preference bounds: 1...256 UTF8 bytes, no Unicode control scalar.
IDs are globally unique across old and new histories. Combined old/new count is
at most 128, without eviction/reset. Receipts declare history without executing
changes or claiming audit authenticity; current settings need not equal a replay
of history, because this slice defines no action engine.

The outer ceiling is 4,194,304 bytes; the unchanged inner ceiling is 1,048,576.
All existing v1 limits remain. Tests cover valid maximal canonical inner bytes
inside the transparent outer, and malformed outer bytes at and above its ceiling.
No valid 4 MiB payload is fabricated: closed fields and existing inner/history
limits impose smaller reachable canonical sizes. Invalid encode/decode/migration
inputs must throw closed `PreferenceRefusal.malformed` or `.limit`, not succeed,
reset state or expose unrelated errors. During Phase A the intentional
`.unimplemented` stub also fails these strict refusal expectations.

## Independent checks and preservation

`ScheduleRecordChecks.swift` owns literal/test-owned canonical expectations.
Positive encode, decode and migration cases cannot pass the refusing stubs;
setup independently verifies literal fixture bytes, the unchanged old codec and
ordinary store/session refusal. Cases cover toggle independence, pause choices
and cancellation, deadline/zone invariance, complete old identities/history and
UInt64 precision, combined 128/129 boundaries, ordered closed receipts, global
ID uniqueness, UTF8 ID bounds, malformed wire, nested canonical checks, caller
principal/scope and limits. The checks call no new store or execution adapter.

`main.original.swift` is an inert exact copy of Git HEAD
`79deb652581d2b8110d21d67c36076688ccc76ff` at
`Tests/PatchedUpdatePreferencesChecks/main.swift`, SHA256
`be36b102eff738f71f005d6bd4d8acc6fb7345f6ae0fc6c7ed0acf0f426a44a6`.
The original main receives exactly one separate
`    scheduleRecordChecks(checks)` line immediately before its unchanged summary.
The new Node preservation check reads inert bytes, pins the original SHA256 and
mode, reconstructs that original from the actual candidate and refuses virtual
old assertion/helper/order/exit mutations, duplicate/removed/moved registrations,
argument/spacing changes, BOM and line-ending drift. It never evaluates Swift.
The full gate receives exactly one additional Node invocation. Existing Package,
all other sources/checks/assets and original gate lines remain unchanged. Parent
accepted-base map inspection owns the complete old tracked-blob/mode preservation
check; the runtime control does not impose a permanent unrelated-file freeze.

The parent alone owns prospective verification groups (five total including RED),
whole-diff acceptance/freeze, implementation release, canonical independent TOP
NVIDIA review, Git/Linear and all future operating/release evidence. Preparation
and synthetic wire checks cannot establish persisted consent or a working scheduler.
