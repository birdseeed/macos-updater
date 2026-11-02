import Foundation
import CoreFoundation
import Darwin
import CryptoKit
import ArtifactInspection

func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func hex(_ hash: SHA256.Digest) -> String { hash.map { String(format: "%02x", $0) }.joined() }
func encodeJSON(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
func validDigest(_ s: String) -> Bool { s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
func validRun(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return (1...64).contains(b.count) && b.first.map { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) } == true &&
        b.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
}
func parseArguments(_ arguments: [String]) throws -> DisposableRequest {
    var fields: [String: String] = [:], trigger = false, i = 0
    let keys: Set<String> = ["--target-id", "--run-id", "--case-root", "--case", "--pause", "--recorded-evidence"]
    while i < arguments.count {
        let key = arguments[i]; i += 1
        if key == "--explicit-trigger" { guard !trigger else { throw DisposableFailure.invalidArguments }; trigger = true; continue }
        guard keys.contains(key), fields[key] == nil, i < arguments.count else { throw DisposableFailure.invalidArguments }
        fields[key] = arguments[i]; i += 1
    }
    guard let target = fields["--target-id"], let run = fields["--run-id"],
          let raw = fields["--case"], let action = DisposableAction(rawValue: raw) else { throw DisposableFailure.invalidArguments }
    let profile = try DisposableTargetProfile.resolve(targetID: target)
    guard validRun(run) else { throw DisposableFailure.unsafePath }
    guard trigger else { throw DisposableFailure.userTriggerRequired }
    let root = fields["--case-root"]
    if let root { guard DisposableScope.caseRoots.contains(root) else { throw DisposableFailure.unknownCase } }
    if action == .initializeRun { guard root == nil else { throw DisposableFailure.caseMismatch } }
    else { guard root != nil else { throw DisposableFailure.invalidArguments } }
    let allowed: [DisposableAction: Set<String>] = [
        .tamperedArtifact: ["tampered-artifact"], .truncatedArtifact: ["truncated-artifact"],
        .recordedEvidence: ["recorded-evidence"], .wrongSignerTarget: ["wrong-signer-target"],
        .wrongSignerStaged: ["wrong-signer-staged"], .invalidCatalogue: ["invalid-signature", "untrusted-key"],
        .replayedCatalogue: ["replayed-sequence", "expired-catalogue"], .openApp: ["open-app"],
        .stagingFailure: ["staging"], .recoverAfterStaging: ["staging"], .update: ["update"],
        .interruptedSwap: ["swap"], .recoverAfterSwap: ["swap"], .restoreOld: ["update"]]
    if let selected = allowed[action] { guard let root, selected.contains(root) else { throw DisposableFailure.caseMismatch } }
    var pause: DisposablePause?
    if let raw = fields["--pause"] {
        guard let parsed = DisposablePause(rawValue: raw) else { throw DisposableFailure.invalidArguments }
        let pair = (action, parsed)
        guard pair == (.stagingFailure, .stageCopy) || pair == (.wrongSignerStaged, .beforeSwap) ||
                pair == (.interruptedSwap, .beforeCommit) else { throw DisposableFailure.invalidArguments }
        pause = parsed
    }
    let runPath = profile.runParent + "/" + run
    let recorded = fields["--recorded-evidence"]
    if let recorded {
        guard action == .recordedEvidence, recorded == runPath + "/Incoming/inspection-157.0.1.json" else { throw DisposableFailure.unsafePath }
    }
    return DisposableRequest(profile: profile, targetID: target, runID: run, caseRoot: root, action: action, explicitTrigger: true,
        pause: pause, recordedEvidencePath: recorded, runPath: runPath,
        targetPath: root.map { runPath + "/Cases/" + $0 + "/Applications/Firefox.app" })
}
func requireTransition(_ from: ProofState, _ to: ProofState) throws {
    let allowed: Set<String> = ["prepared:staging", "staging:staged", "staged:swapIntended", "swapIntended:swapped", "swapped:committed",
        "prepared:rolledBack", "staging:rolledBack", "staged:rolledBack", "swapIntended:rolledBack", "swapped:rolledBack", "committed:swapIntended"]
    guard allowed.contains(from.rawValue + ":" + to.rawValue) else { throw DisposableFailure.invalidState }
}
func recoveryDecision(_ state: ProofState, _ old: Bool, _ new: Bool, _ retained: Bool, _ stage: Bool) throws -> ProofRecovery {
    guard !(old && new) else { throw DisposableFailure.ambiguousState }
    if old && !new && !retained {
        if state == .rolledBack { return .none }
        if state != .committed { return .oldAlreadyInPlace }
    }
    if new && !old && retained && stage {
        if state == .committed { return .none }
        if state == .swapIntended || state == .swapped { return .restoredOldBySwap }
    }
    throw DisposableFailure.ambiguousState
}
func fixedPin(_ version: String) throws -> TargetPin {
    guard version == "157.0" || version == "157.0.1" else { throw DisposableFailure.unapprovedArtifact }
    return try FirefoxTargets.select(version: version)
}
func requirePin(_ pin: TargetPin, _ version: String) throws {
    guard pin == (try fixedPin(version)) else { throw DisposableFailure.unapprovedArtifact }
}
func requireArtifact(_ version: String, _ length: Int64, _ hash: String) throws {
    let pin = try fixedPin(version)
    guard length == pin.byteLength else { throw DisposableFailure.lengthMismatch }
    guard hash == pin.sha256 else { throw DisposableFailure.digestMismatch }
}
func sameVolume(_ root: UInt64, _ entry: UInt64) throws { guard root == entry else { throw DisposableFailure.crossVolume } }

/// Strict bounded UTF-8 JSON grammar before Foundation decoding. Duplicate object keys are refused.
enum StrictObject {
    static func decode(_ data: Data, maximum: Int = 65_536, failure: DisposableFailure = .journalCorrupt) throws -> [String: Any] {
        guard data.count <= maximum, String(data: data, encoding: .utf8) != nil else { throw failure }
        var parser = Parser(bytes: Array(data), failure: failure)
        try parser.value(depth: 0); parser.space()
        guard parser.index == data.count, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure }
        return object
    }
    private struct Parser {
        let bytes: [UInt8]; let failure: DisposableFailure; var index = 0
        mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ b: UInt8) throws { space(); guard index < bytes.count, bytes[index] == b else { throw failure }; index += 1 }
        mutating func string() throws -> String {
            space(); let start = index; try take(34)
            while index < bytes.count {
                let c = bytes[index]; index += 1
                if c == 34 {
                    var slice = Data([91]); slice.append(contentsOf: bytes[start..<index]); slice.append(93)
                    guard let strings = try? JSONSerialization.jsonObject(with: slice) as? [String], strings.count == 1 else { throw failure }
                    return strings[0]
                }
                if c == 92 { guard index < bytes.count else { throw failure }; index += 1 }
                else if c < 32 { throw failure }
            }
            throw failure
        }
        mutating func value(depth: Int) throws {
            guard depth < 32 else { throw failure }; space(); guard index < bytes.count else { throw failure }
            if bytes[index] == 123 {
                index += 1; space(); if index < bytes.count && bytes[index] == 125 { index += 1; return }
                var keys: Set<String> = []
                while true {
                    let key = try string(); guard keys.insert(key).inserted else { throw failure }
                    try take(58); try value(depth: depth + 1); space()
                    guard index < bytes.count else { throw failure }
                    if bytes[index] == 125 { index += 1; return }; try take(44)
                }
            } else if bytes[index] == 91 {
                index += 1; space(); if index < bytes.count && bytes[index] == 93 { index += 1; return }
                while true { try value(depth: depth + 1); space(); guard index < bytes.count else { throw failure }
                    if bytes[index] == 93 { index += 1; return }; try take(44) }
            } else if bytes[index] == 34 { _ = try string() }
            else {
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw failure }
                let token = Data(bytes[start..<index])
                guard (try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed])) != nil else { throw failure }
            }
        }
    }
}
func unsigned(_ value: Any?) -> UInt64? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
    let text = value.stringValue
    guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    return UInt64(text)
}
