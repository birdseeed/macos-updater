import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

private let storageLegacyHash = "d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959"
private let storageSSDHash = "a44c836bfbda0c6beb1df7b3b3178a171479d362ecfacd534a62b09890dde705"
private func storageHash(_ profile: DisposableTargetProfile) -> String { profile == .legacy ? storageLegacyHash : storageSSDHash }

// Real exclusive synthetic .build root, never an actual guest/home path.
private struct ProfileJournalFixture {
    let held: SyntheticRoot
    let binding: SyntheticJournalBinding
    let owner: UInt32
    var root: String { held.path }
    init(profile: DisposableTargetProfile) throws {
        held = try SyntheticProofFiles.createRoot(path: physicalBuild() + "/patched-disposable-check-" + UUID().uuidString)
        let info = try statOf(held.path)
        owner = info.st_uid
        binding = .init(runID: "profile-storage", caseRoot: "update", device: UInt64(UInt32(bitPattern: info.st_dev)),
                        inode: info.st_ino, profile: profile)
    }
    func record(hash: String) -> [String: Any] {
        ["schemaVersion": 1, "kind": "patched-disposable-journal-v1", "origin": "synthetic",
         "guestUUIDSHA256": hash, "uid": owner, "runID": "profile-storage", "caseRoot": "update",
         "device": binding.device, "inode": binding.inode, "state": "prepared",
         "transactionID": "01234567-89AB-CDEF-0123-456789ABCDEF", "oldInode": 10, "newInode": 11,
         "beforeManifestSHA256": String(repeating: "a", count: 64), "afterManifestSHA256": String(repeating: "b", count: 64),
         "cataloguePayloadSHA256": String(repeating: "c", count: 64),
         "artifactSHA256": "40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982"]
    }
    func install(_ data: Data) throws {
        try expect(data.count <= 4096, "Bounded literal journal fixture exceeded 4096 bytes")
        try SyntheticProofFiles.writeExclusive(root: root, relativePath: "journal.json", data: data)
    }
    func readBytes() throws -> Data { try SyntheticProofFiles.readRegular(root: root, relativePath: "journal.json", maximumBytes: 4096) }
    func requireRefusal(_ reason: DisposableFailure, binding override: SyntheticJournalBinding? = nil) throws {
        let before = try readBytes()
        var actual: DisposableFailure?
        do { _ = try SyntheticProofFiles.readJournal(root: root, binding: override ?? binding) }
        catch let e as DisposableFailure { actual = e }
        // Compare even when a refusal was incorrectly accepted.
        try expect(try readBytes() == before, "Read-only journal refusal changed exact evidence bytes")
        try held.revalidate()
        try expect(actual == reason, "Expected \(reason.rawValue), observed \(actual?.rawValue ?? "accepted")")
    }
}

// Expected marker fields are scalar declared test data only. No path/capability.
private struct MarkerBinding: Sendable {
    var profile: DisposableTargetProfile
    var runID = "profile-storage"
    var caseRoot: String?
    var uid: UInt32 = 501
    var device: UInt64 = 17
    var inode: UInt64 = 23
    var binarySHA256 = String(repeating: "d", count: 64)
    func matches(_ data: Data) -> Bool {
        SyntheticProfileMarkers.matches(bytes: data, profile: profile, runID: runID, caseRoot: caseRoot,
            uid: uid, device: device, inode: inode, binarySHA256: binarySHA256)
    }
    func literal() -> [String: Any] {
        ["schemaVersion": 1, "kind": caseRoot == nil ? "patched-disposable-run-v1" : "patched-disposable-case-v1",
         "guestUUIDSHA256": storageHash(profile), "uid": 501, "runID": "profile-storage", "caseRoot": caseRoot == nil ? "" : "update",
         "device": 17, "inode": 23, "binarySHA256": String(repeating: "d", count: 64)]
    }
}

@MainActor func registerProfileStorageChecks() {
    let prefix = "PAT-2710 profile storage: "
    check(prefix + "journal binding constructor retains profile and legacy default [control]") {
        let legacy = SyntheticJournalBinding(runID: "r", caseRoot: "update", device: 1, inode: 2)
        let ssd = SyntheticJournalBinding(runID: "r", caseRoot: "update", device: 1, inode: 2, profile: .ssdTesting)
        try expect(legacy.profile == .legacy && ssd.profile == .ssdTesting, "Typed immutable binding/default lost")
    }
    check(prefix + "marker omitted profile remains legacy [expect RED]") {
        let binding = MarkerBinding(profile: .legacy, caseRoot: nil), data = try json(binding.literal())
        try expect(SyntheticProfileMarkers.matches(bytes: data, runID: "profile-storage", caseRoot: nil,
            uid: 501, device: 17, inode: 23, binarySHA256: String(repeating: "d", count: 64)), "Omitted profile must validate the exact legacy marker")
    }
    for profile in [DisposableTargetProfile.legacy, .ssdTesting] {
        let other: DisposableTargetProfile = profile == .legacy ? .ssdTesting : .legacy
        check(prefix + "literal journal positive \(profile) [SSD expect RED]") {
            let f = try ProfileJournalFixture(profile: profile), data = try json(f.record(hash: storageHash(profile)))
            try f.install(data)
            let observed = try SyntheticProofFiles.readJournal(root: f.root, binding: f.binding)
            let after = try f.readBytes()
            try expect(observed == .prepared && after == data, "Read-only exact prepared journal")
            try f.held.revalidate()
        }
        check(prefix + "complete other-profile journal \(profile) [SSD expect RED]") {
            let f = try ProfileJournalFixture(profile: profile)
            try f.install(json(f.record(hash: storageHash(other))))
            try f.requireRefusal(.journalMismatch)
        }
        for field in ["uid", "runID", "caseRoot", "device", "inode", "origin", "schema", "extra", "missing", "duplicate", "booleanUID", "stringDevice"] {
            check(prefix + "journal \(profile) refuses changed \(field), preserves bytes [control]") {
                let f = try ProfileJournalFixture(profile: profile)
                var o = f.record(hash: storageHash(profile))
                let malformed = ["origin", "schema", "extra", "missing", "duplicate", "booleanUID", "stringDevice"].contains(field)
                switch field {
                case "uid": o["uid"] = UInt64(f.owner) + 1
                case "runID": o["runID"] = "another-run"
                case "caseRoot": o["caseRoot"] = "swap"
                case "device": o["device"] = f.binding.device + 1
                case "inode": o["inode"] = f.binding.inode + 1
                case "origin": o["origin"] = "disposableGuest"
                case "schema": o["schemaVersion"] = 2
                case "extra": o["targetID"] = "invented"
                case "missing": o.removeValue(forKey: "guestUUIDSHA256")
                case "booleanUID": o["uid"] = true
                case "stringDevice": o["device"] = String(f.binding.device)
                default: break
                }
                var data = try json(o)
                if field == "duplicate" { data = Data("{\"runID\":\"profile-storage\",".utf8) + data.dropFirst() }
                try f.install(data)
                try f.requireRefusal(malformed ? .journalCorrupt : .journalMismatch)
            }
        }
        for field in ["runID", "caseRoot", "device", "inode"] {
            check(prefix + "journal \(profile) refuses wrong expected binding \(field) [control]") {
                let f = try ProfileJournalFixture(profile: profile)
                try f.install(json(f.record(hash: storageHash(profile))))
                let b = SyntheticJournalBinding(runID: field == "runID" ? "other" : "profile-storage",
                    caseRoot: field == "caseRoot" ? "swap" : "update",
                    device: f.binding.device + (field == "device" ? 1 : 0),
                    inode: f.binding.inode + (field == "inode" ? 1 : 0), profile: profile)
                try f.requireRefusal(.journalMismatch, binding: b)
            }
        }
        for root: String? in [nil, "update"] {
            let kind = root == nil ? "run" : "case", binding = MarkerBinding(profile: profile, caseRoot: root)
            check(prefix + "literal nine-key \(profile) \(kind) marker positive [expect RED]") {
                let o = binding.literal(), data = try json(o)
                try expect(Set(o.keys) == ["schemaVersion", "kind", "guestUUIDSHA256", "uid", "runID", "caseRoot", "device", "inode", "binarySHA256"], "Literal exact nine-key schema")
                try expect(binding.matches(data), "Exact literal marker must match pure declared binding")
            }
            for field in ["guestHash", "schema", "kind", "uid", "runID", "caseRoot", "device", "inode", "binarySHA256", "extra", "missing", "duplicate", "booleanUID", "stringDevice", "booleanSchema", "floatInode", "nullRoot"] {
                check(prefix + "\(profile) \(kind) marker refuses changed \(field) [control]") {
                    var o = binding.literal()
                    switch field {
                    case "guestHash": o["guestUUIDSHA256"] = storageHash(other)
                    case "schema": o["schemaVersion"] = 2
                    case "kind": o["kind"] = root == nil ? "patched-disposable-case-v1" : "patched-disposable-run-v1"
                    case "uid": o["uid"] = 502
                    case "runID": o["runID"] = "another-run"
                    case "caseRoot": o["caseRoot"] = root == nil ? "update" : "swap"
                    case "device": o["device"] = 18
                    case "inode": o["inode"] = 24
                    case "binarySHA256": o["binarySHA256"] = String(repeating: "e", count: 64)
                    case "extra": o["ignored"] = true
                    case "missing": o.removeValue(forKey: "guestUUIDSHA256")
                    case "booleanUID": o["uid"] = true
                    case "stringDevice": o["device"] = "17"
                    case "booleanSchema": o["schemaVersion"] = true
                    case "floatInode": o["inode"] = 23.5
                    case "nullRoot": o["caseRoot"] = NSNull()
                    default: break
                    }
                    var data = try json(o)
                    if field == "duplicate" { data = Data("{\"guestUUIDSHA256\":\"".utf8) + Data(storageHash(profile).utf8) + Data("\",".utf8) + data.dropFirst() }
                    let before = data
                    try expect(!binding.matches(data), "Malformed/mixed marker accepted: \(field)")
                    try expect(data == before, "Read-only marker predicate changed input bytes")
                }
            }
            for field in ["profile", "runID", "caseRoot", "uid", "device", "inode", "binarySHA256"] {
                check(prefix + "\(profile) \(kind) marker refuses wrong expected \(field) [control]") {
                    let data = try json(binding.literal()); var wrong = binding
                    switch field {
                    case "profile": wrong.profile = other
                    case "runID": wrong.runID = "another-run"
                    case "caseRoot": wrong.caseRoot = root == nil ? "update" : nil
                    case "uid": wrong.uid = 502
                    case "device": wrong.device = 18
                    case "inode": wrong.inode = 24
                    default: wrong.binarySHA256 = String(repeating: "e", count: 64)
                    }
                    try expect(!wrong.matches(data), "Independent expected binding mutation accepted: \(field)")
                }
            }
        }
    }
}
