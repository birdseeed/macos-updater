import Foundation
import ArtifactInspection

// CHECK-ADDED: parent acceptance found an encoding bypass in the duplicate-key
// scanner. These cases were run against the vulnerable code before the fix.
@MainActor func addEncodingChecks() {
    let formats: [(String, (String) -> Data)] = [
        ("UTF8 BOM", { Data([0xef, 0xbb, 0xbf]) + Data($0.utf8) }),
        ("UTF16 LE BOM", { Data([0xff, 0xfe]) + $0.data(using: .utf16LittleEndian)! }),
        ("UTF16 BE without BOM", { $0.data(using: .utf16BigEndian)! })
    ]
    for (name, encode) in formats {
        check("\(name) duplicate pin schema refused even when identical") {
            let text = String(decoding: try Data(contentsOf: recordPath), as: UTF8.self)
                .replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 1, \"schemaVersion\": 1")
            try refuses(.invalidRecord) { _ = try FirefoxTargets.verifyRecord(encode(text)) }
        }
        check("\(name) duplicate raw evidence refused even when identical") {
            let text = String(decoding: try JSONEncoder().encode(evidence()), as: UTF8.self)
                .replacingOccurrences(of: "\"exitCode\":0", with: "\"exitCode\":0,\"exitCode\":0")
            try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(encode(text), pin: old) }
        }
    }
    check("BOM pin record refused without any duplicates") {
        let data = Data([0xef, 0xbb, 0xbf]) + (try Data(contentsOf: recordPath))
        try refuses(.invalidRecord) { _ = try FirefoxTargets.verifyRecord(data) }
    }
    check("BOM raw evidence refused without any duplicates") {
        let data = Data([0xef, 0xbb, 0xbf]) + (try JSONEncoder().encode(evidence()))
        try refuses(.invalidRecord) { _ = try EvidenceEvaluator.replay(data, pin: old) }
    }
    check("ordinary UTF8 record trailing whitespace remains valid") {
        let data = (try Data(contentsOf: recordPath)) + Data(" \t\r\n".utf8)
        let pins = try FirefoxTargets.verifyRecord(data)
        try expect(pins == FirefoxTargets.pins, "UTF8 whitespace is valid")
    }
    check("record trailing non-whitespace refused") {
        let data = (try Data(contentsOf: recordPath)) + Data(" false".utf8)
        try refuses(.invalidRecord) { _ = try FirefoxTargets.verifyRecord(data) }
    }
}
