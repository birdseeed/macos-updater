import Foundation

// Foundation accepts duplicate JSON keys. Reject them before decoding any trust
// record, including escaped duplicate names and duplicates in nested objects.
enum StrictJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        // Both parsers must see the same encoding and complete document. Foundation
        // otherwise accepts BOM/UTF16 inputs that a byte scanner can misread.
        guard data.count <= 1_048_576, !data.starts(with: [0xef, 0xbb, 0xbf]),
              !data.contains(0), String(data: data, encoding: .utf8) != nil else {
            throw InspectionFailure.invalidRecord
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw InspectionFailure.invalidRecord }
            var scanner = Scanner(bytes: Array(data)); try scanner.value(depth: 0)
            scanner.space()
            guard scanner.index == scanner.bytes.count else { throw InspectionFailure.invalidRecord }
            return object
        } catch { throw InspectionFailure.invalidRecord }
    }
    static func keys(_ object: [String: Any], _ expected: Set<String>) throws {
        guard Set(object.keys) == expected else { throw InspectionFailure.invalidRecord }
    }
    private struct Scanner {
        let bytes: [UInt8]; var index = 0
        var current: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func space() {
            while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 }
        }
        mutating func consume(_ byte: UInt8) throws {
            guard current == byte else { throw InspectionFailure.invalidRecord }
            index += 1
        }
        mutating func string() throws -> String {
            let start = index; try consume(34)
            while let byte = current {
                index += 1
                if byte == 92 {
                    guard current != nil else { throw InspectionFailure.invalidRecord }
                    index += 1
                } else if byte == 34 {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                }
            }
            throw InspectionFailure.invalidRecord
        }
        mutating func value(depth: Int) throws {
            guard depth < 40 else { throw InspectionFailure.invalidRecord }; space()
            guard let byte = current else { throw InspectionFailure.invalidRecord }
            switch byte {
            case 123:
                index += 1; space(); var keys: Set<String> = []
                if current == 125 { index += 1; return }
                while true {
                    space(); let key = try string()
                    guard keys.insert(key).inserted else { throw InspectionFailure.invalidRecord }
                    space(); try consume(58); try value(depth: depth + 1); space()
                    if current == 125 { index += 1; return }
                    try consume(44)
                }
            case 91:
                index += 1; space()
                if current == 93 { index += 1; return }
                while true {
                    try value(depth: depth + 1); space()
                    if current == 93 { index += 1; return }
                    try consume(44)
                }
            case 34:
                _ = try string()
            case 116, 102, 110:
                let token = byte == 116 ? "true" : byte == 102 ? "false" : "null"
                for expected in token.utf8 { try consume(expected) }
            case 45, 48...57:
                // Foundation has already validated number grammar. Only numeric
                // bytes may be skipped here, never braces, quotes or BOM bytes.
                while let next = current, (48...57).contains(next) || [43, 45, 46, 69, 101].contains(next) { index += 1 }
            default:
                throw InspectionFailure.invalidRecord
            }
        }
    }
}

struct PinRecord: Decodable { let schemaVersion: Int; let targets: [TargetPin]; let purpose: String }
func verifyPinRecord(_ data: Data) throws -> [TargetPin] {
    do {
        let object = try StrictJSON.object(data)
        try StrictJSON.keys(object, ["schemaVersion", "purpose", "targets", "historicalEvidence"])
        guard let rows = object["targets"] as? [[String: Any]] else { throw InspectionFailure.invalidRecord }
        for row in rows { try StrictJSON.keys(row, ["version", "url", "sha256", "byteLength", "bundleID", "teamID", "architectures"]) }
        let decoded = try JSONDecoder().decode(PinRecord.self, from: data)
        guard decoded.schemaVersion == 1, !decoded.purpose.isEmpty, decoded.targets == FirefoxTargets.pins,
              object["historicalEvidence"] is [String: Any] else { throw InspectionFailure.invalidRecord }
        return decoded.targets
    } catch { throw InspectionFailure.invalidRecord }
}

func decodeEvidence(_ data: Data) throws -> AppEvidence {
    do {
        let object = try StrictJSON.object(data)
        let legacy: Set<String> = ["appPath", "dmgPath", "infoPlist", "commands", "observedAt", "osVersion", "osBuild"]
        if object["schemaVersion"] == nil {
            try StrictJSON.keys(object, legacy)
        } else {
            let structured = (object["schemaVersion"] as? NSNumber)?.intValue == 3
            let extra: Set<String> = structured ? ["schemaVersion", "architectureObservation", "signatureObservation"] :
                ["schemaVersion", "architectureObservation"]
            try StrictJSON.keys(object, legacy.union(extra))
            if structured {
                guard let signature = object["signatureObservation"] as? [String: Any] else { throw InspectionFailure.invalidRecord }
                try StrictJSON.keys(signature, ["appPath", "requirement", "validationFlags", "validationStatus",
                    "signingInformationStatus", "teamID", "identifier", "startedAt", "finishedAt"])
            }
            guard let observation = object["architectureObservation"] as? [String: Any] else { throw InspectionFailure.invalidRecord }
            try StrictJSON.keys(observation, ["executablePath", "architectures"])
        }
        guard let commands = object["commands"] as? [String: [String: Any]] else { throw InspectionFailure.invalidRecord }
        for command in commands.values {
            try StrictJSON.keys(command, ["executable", "arguments", "exitCode", "stdout", "stderr", "timedOut", "outputExceeded", "startedAt", "finishedAt"])
        }
        let decoded = try JSONDecoder().decode(AppEvidence.self, from: data)
        if object["schemaVersion"] == nil {
            guard decoded.schemaVersion == nil, decoded.architectureObservation == nil else { throw InspectionFailure.invalidRecord }
        } else {
            guard decoded.architectureObservation != nil else { throw InspectionFailure.invalidRecord }
            if decoded.schemaVersion == 3 {
                guard decoded.signatureObservation != nil else { throw InspectionFailure.invalidRecord }
            } else {
                guard decoded.schemaVersion == 2, decoded.signatureObservation == nil else { throw InspectionFailure.invalidRecord }
            }
        }
        return decoded
    } catch { throw InspectionFailure.invalidRecord }
}
