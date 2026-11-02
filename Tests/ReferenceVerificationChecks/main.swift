import Foundation
import Darwin
import ReferenceVerification

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func requireValue<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(description: "Required fixture value missing") }
    return value
}

private func requireEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw CheckFailure(description: "Expected \(expected), received \(actual)")
    }
}

private func requireThrows<T>(_ expression: @autoclosure () throws -> T,
                              _ reason: String = "Expected verification failure") throws {
    do { _ = try expression() } catch { return }
    throw CheckFailure(description: reason)
}

private final class ReferenceVerifierChecks {
    private let destinations = [
        "ThirdParty/Installomator/LICENSE", "References/Legacy/firefox.recipe.json"
    ]
    private var root: URL!
    private var workspace: URL!
    private let fm = FileManager.default

    func setUpWithError() throws {
        // CHECK-MODIFIED: Foundation retained /var; POSIX resolves /private/var.
        // A physical baseline keeps explicit symlink rejection cases meaningful.
        guard let physical = realpath(fm.temporaryDirectory.path, nil) else {
            throw CheckFailure(description: "Cannot resolve temporary fixture directory")
        }
        defer { free(physical) }
        workspace = URL(fileURLWithPath: String(cString: physical))
            .appendingPathComponent("patched-reference-tests-\(UUID().uuidString)")
        root = workspace.appendingPathComponent("checkout")
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["source-provenance.json"] + destinations {
            let target = root.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: checkout.appendingPathComponent(path), to: target)
        }
    }

    func tearDownWithError() throws {
        if let workspace { try fm.removeItem(at: workspace) }
    }

    private func manifest() throws -> [String: Any] {
        try requireValue(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("source-provenance.json"))) as? [String: Any])
    }

    private func write(_ document: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("source-provenance.json"))
    }

    private func rejects(_ document: [String: Any], _ reason: String) throws {
        try write(document)
        try requireThrows(try ReferenceVerifier.verify(root: root), reason)
    }

    func testPreservedReferenceBytesPassWithoutModifyingInputs() throws {
        let paths = ["source-provenance.json"] + destinations
        let before = try paths.map { try Data(contentsOf: root.appendingPathComponent($0)) }
        try requireEqual(try ReferenceVerifier.verify(root: root), destinations.sorted())
        try requireEqual(try paths.map { try Data(contentsOf: root.appendingPathComponent($0)) }, before)
    }

    func testChangedBytesFailEvenAtSameLength() throws {
        for path in destinations {
            let url = root.appendingPathComponent(path)
            let original = try Data(contentsOf: url)
            var changed = original
            changed[changed.startIndex] ^= 1
            try changed.write(to: url)
            try requireThrows(try ReferenceVerifier.verify(root: root), path)
            try original.write(to: url)
        }
    }

    func testTruncatedAndMissingReferencesFail() throws {
        for path in destinations {
            let url = root.appendingPathComponent(path)
            let original = try Data(contentsOf: url)
            try original.dropLast().write(to: url)
            try requireThrows(try ReferenceVerifier.verify(root: root), "Truncated: \(path)")
            try fm.removeItem(at: url)
            try requireThrows(try ReferenceVerifier.verify(root: root), "Missing: \(path)")
            try original.write(to: url)
        }
    }

    func testMalformedManifestAndSchemaFail() throws {
        for text in ["{", "null", "[]", "{}", "{\"schema_version\":1,\"files\":null}"] {
            try Data(text.utf8).write(to: root.appendingPathComponent("source-provenance.json"))
            try requireThrows(try ReferenceVerifier.verify(root: root), text)
        }
    }

    func testUnsupportedOrWronglyTypedSchemaFails() throws {
        let original = try manifest()
        for version: Any in [2, "1", true, NSNull()] {
            var document = original
            document["schema_version"] = version
            try rejects(document, "Schema: \(version)")
        }
    }

    func testExactlyTwoDistinctKnownDestinationsRequired() throws {
        let original = try manifest()
        let records = try requireValue(original["files"] as? [[String: Any]])
        for badRecords in [[], [records[0]], [records[0], records[0]], records + [records[1]]] {
            var document = original
            document["files"] = badRecords
            try rejects(document, "Missing, duplicate or extra record")
        }
    }

    func testInvalidRecordValuesFail() throws {
        let original = try manifest()
        let records = try requireValue(original["files"] as? [[String: Any]])
        let invalid: [String: [Any]] = [
            "sha256": [NSNull(), "", String(repeating: "g", count: 64), String(repeating: "0", count: 64), 123],
            "byte_length": [NSNull(), -1, 0, 1.5, true, "11359"],
            "actionable": [NSNull(), true, 0, "false"],
            "read_only_reference": [NSNull(), false, 1, "true"],
            "extracted": [NSNull(), false, 1, "true"]
        ]
        for (key, values) in invalid {
            for value in values {
                var changed = records
                changed[0][key] = value
                var document = original
                document["files"] = changed
                try rejects(document, "Invalid \(key): \(value)")
            }
            var changed = records
            changed[0].removeValue(forKey: key)
            var document = original
            document["files"] = changed
            try rejects(document, "Missing \(key)")
        }
    }

    func testUnexpectedExecutableFlagsFail() throws {
        let original = try manifest()
        for key in ["executable", "executable_recipe"] {
            var records = try requireValue(original["files"] as? [[String: Any]])
            records[1][key] = true
            var document = original
            document["files"] = records
            try rejects(document, "Unexpected \(key)")
        }
    }

    func testUnsafeAndUnknownDestinationsFail() throws {
        let original = try manifest()
        for path in ["", "/etc/hosts", "../outside", "References/../outside", "./ThirdParty/Installomator/LICENSE",
                     "ThirdParty//Installomator/LICENSE", "Other/LICENSE", "ThirdParty/Installomator/LICENSE\u{0}"] {
            var records = try requireValue(original["files"] as? [[String: Any]])
            records[0]["destination"] = path
            var document = original
            document["files"] = records
            try rejects(document, "Destination: \(path)")
        }
    }

    func testSymlinkFilesAndManifestFail() throws {
        for path in ["source-provenance.json"] + destinations {
            let url = root.appendingPathComponent(path)
            let outside = workspace.appendingPathComponent("original")
            try fm.moveItem(at: url, to: outside)
            try fm.createSymbolicLink(at: url, withDestinationURL: outside)
            try requireThrows(try ReferenceVerifier.verify(root: root), path)
            try fm.removeItem(at: url)
            try fm.moveItem(at: outside, to: url)
        }
    }

    func testSymlinkDirectoryRootAndAncestorFail() throws {
        let directory = root.appendingPathComponent("References")
        let moved = workspace.appendingPathComponent("references")
        try fm.moveItem(at: directory, to: moved)
        try fm.createSymbolicLink(at: directory, withDestinationURL: moved)
        try requireThrows(try ReferenceVerifier.verify(root: root))
        try fm.removeItem(at: directory)
        try fm.moveItem(at: moved, to: directory)
        let alias = workspace.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: root)
        try requireThrows(try ReferenceVerifier.verify(root: alias))
        try fm.removeItem(at: alias)
        try fm.createSymbolicLink(at: alias, withDestinationURL: workspace)
        try requireThrows(try ReferenceVerifier.verify(root: alias.appendingPathComponent("checkout")))
    }

    func testDirectoryInsteadOfRegularFileFails() throws {
        let url = root.appendingPathComponent(destinations[0])
        try fm.removeItem(at: url)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        try requireThrows(try ReferenceVerifier.verify(root: root))
    }
}

// CHECK-MODIFIED: XCTest is unavailable; all twelve acceptance cases are mechanically converted;
// their values, paths, symlink checks and input preservation requirements are unchanged.
private let cases: [(String, (ReferenceVerifierChecks) throws -> Void)] = [
    ("testPreservedReferenceBytesPassWithoutModifyingInputs", { try $0.testPreservedReferenceBytesPassWithoutModifyingInputs() }),
    ("testChangedBytesFailEvenAtSameLength", { try $0.testChangedBytesFailEvenAtSameLength() }),
    ("testTruncatedAndMissingReferencesFail", { try $0.testTruncatedAndMissingReferencesFail() }),
    ("testMalformedManifestAndSchemaFail", { try $0.testMalformedManifestAndSchemaFail() }),
    ("testUnsupportedOrWronglyTypedSchemaFails", { try $0.testUnsupportedOrWronglyTypedSchemaFails() }),
    ("testExactlyTwoDistinctKnownDestinationsRequired", { try $0.testExactlyTwoDistinctKnownDestinationsRequired() }),
    ("testInvalidRecordValuesFail", { try $0.testInvalidRecordValuesFail() }),
    ("testUnexpectedExecutableFlagsFail", { try $0.testUnexpectedExecutableFlagsFail() }),
    ("testUnsafeAndUnknownDestinationsFail", { try $0.testUnsafeAndUnknownDestinationsFail() }),
    ("testSymlinkFilesAndManifestFail", { try $0.testSymlinkFilesAndManifestFail() }),
    ("testSymlinkDirectoryRootAndAncestorFail", { try $0.testSymlinkDirectoryRootAndAncestorFail() }),
    ("testDirectoryInsteadOfRegularFileFails", { try $0.testDirectoryInsteadOfRegularFileFails() })
]

var failures: [String] = []
for (name, body) in cases {
    let checks = ReferenceVerifierChecks()
    do {
        try checks.setUpWithError()
        try body(checks)
    } catch {
        failures.append("\(name): \(error)")
    }
    do {
        try checks.tearDownWithError()
    } catch {
        failures.append("\(name) cleanup: \(error)")
    }
}
for failure in failures { print("FAIL \(failure)") }
print("\(cases.count) cases; \(failures.count) failures")
if !failures.isEmpty { exit(1) }
