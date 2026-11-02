import Foundation
import Darwin
@_spi(Testing) import PatchedActivity

let principal = "fixture-owner-A"
let storeID = "AAAAAAAA-0000-4000-8000-000000000001"
let eventID = "BBBBBBBB-0000-4000-8000-000000000001"
let attemptID = "CCCCCCCC-0000-4000-8000-000000000001"
let transactionID = "DDDDDDDD-0000-4000-8000-000000000001"
let reportID = "EEEEEEEE-0000-4000-8000-000000000001"
let runID = "FFFFFFFF-0000-4000-8000-000000000001"
let requestID = "AAAAAAAA-0000-4000-8000-000000000002"
let otherID = "BBBBBBBB-0000-4000-8000-000000000002"
let epoch: UInt64 = 10_000_000
let thirtyDays: UInt64 = 2_592_000
let literalName = "<b>**Fixture 日本語**</b> & name"
let privateText = "/Users/secret-owner/Library/token=SECRET profile inventory"

func event(id: String = eventID, attempt: String = attemptID, target: String = "opaque-target-A",
           name: String = "Fixture app", origin: ActivityOrigin = .manualIndividual,
           status: ActivityStatus = .failed, reason: ActivityReason = .verificationFailed,
           sequence: UInt64 = 1, observed: UInt64? = epoch, resolved: UInt64? = epoch,
           before: String? = nil, after: String? = nil, beforeBuild: String? = nil, afterBuild: String? = nil,
           run: String? = nil, request: String? = nil, transaction: String? = nil,
           parent: String? = nil, report: String? = reportID) -> ActivityEvent {
    ActivityEvent(eventID: id, attemptID: attempt, targetKey: target, appName: name,
                  origin: origin, status: status, reason: reason, sequence: sequence,
                  observedAt: observed, resolvedAt: resolved, beforeVersion: before, afterVersion: after,
                  beforeBuild: beforeBuild, afterBuild: afterBuild, runID: run, requestID: request,
                  transactionID: transaction, parentUpdateID: parent, reportID: report)
}
// Independently specified JSON shape. Never calls ActivityWire.encode or Codable on product types.
func eventObject(_ e: ActivityEvent) -> [String: Any] {
    var value: [String: Any] = ["eventID": e.eventID, "attemptID": e.attemptID, "targetKey": e.targetKey,
        "appName": e.appName, "origin": e.origin.rawValue, "status": e.status.rawValue,
        "reason": e.reason.rawValue, "sequence": NSNumber(value: e.sequence)]
    for (key, text) in [("beforeVersion",e.beforeVersion),("afterVersion",e.afterVersion),
                        ("beforeBuild",e.beforeBuild),("afterBuild",e.afterBuild),("runID",e.runID),
                        ("requestID",e.requestID),("transactionID",e.transactionID),
                        ("parentUpdateID",e.parentUpdateID),("reportID",e.reportID)] { if let text { value[key] = text } }
    if let time = e.observedAt { value["observedAt"] = NSNumber(value: time) }
    if let time = e.resolvedAt { value["resolvedAt"] = NSNumber(value: time) }
    return value
}
func rawRecord(_ events: [ActivityEvent] = [], revision: UInt64 = 0,
               owner: String = principal, store: String = storeID) -> [String: Any] {
    ["schema": 1, "principal": owner, "storeID": store, "revision": NSNumber(value: revision),
     "events": events.map(eventObject)]
}
func canonical(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
}
func bytes(_ events: [ActivityEvent] = [], revision: UInt64 = 0,
           owner: String = principal, store: String = storeID) throws -> ActivityStoredBytes {
    ActivityStoredBytes(revision: revision, bytes: try canonical(rawRecord(events, revision: revision, owner: owner, store: store)))
}
func readback(_ e: ActivityEvent) -> ActivitySyntheticReadback {
    ActivitySyntheticReadback(eventID: e.eventID, attemptID: e.attemptID,
                              transactionID: e.transactionID ?? transactionID,
                              afterVersion: e.afterVersion, afterBuild: e.afterBuild)
}
@MainActor func fixtureOwner(_ store: OwnedStore, owner: String = principal, storeID id: String = storeID) -> ActivityHistoryOwner {
    ActivityHistoryOwner(store: store, principal: owner, storeID: id)
}
@MainActor func loaded(_ events: [ActivityEvent], revision: UInt64 = 1,
                       now: UInt64? = epoch) throws -> (OwnedStore, ActivityHistoryOwner) {
    let store = try OwnedStore(); try store.seed(bytes(events, revision: revision))
    let owner = fixtureOwner(store); try owner.reload(now: now)
    return (store, owner)
}
func fixtureFile() throws -> Data {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Fixtures/Activity/events.json")
    return try Data(contentsOf: url)
}
