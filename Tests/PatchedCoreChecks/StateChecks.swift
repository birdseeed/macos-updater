import Foundation
import Darwin
@_spi(Testing) import PatchedCore

@MainActor func registerStateChecks() {
    check("explicit bootstrap creates private durable fixture namespace") {
        try withWorkspace { root in
            let result = try Fixture.verifier(root).bootstrapFreshProofNamespace(envelope: Fixture.envelope(), now: Fixture.now)
            try expect(result.sequence == 7, "Bootstrap did not return validated sequence")
            try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload()))
            var info = stat()
            try expect(lstat(root.appendingPathComponent("state").path, &info) == 0 && info.st_mode & 0o777 == 0o700, "Namespace is not private")
            let namespace = try object(Data(contentsOf: root.appendingPathComponent("state/namespace.json")))
            try expect(namespace["namespace"] as? String == "patched-fixture-state-v1", "Missing explicit fixture namespace marker")
        }
    }
    check("ordinary verification refuses absent namespace") {
        try withWorkspace { root in try refuses(.missingState) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) } }
    }
    check("bootstrap invalid signature creates no namespace") {
        try withWorkspace { root in
            try refuses(.invalidSignature) {
                _ = try Fixture.verifier(root).bootstrapFreshProofNamespace(envelope: Fixture.signed(json(Fixture.payload()), alternateKey: true), now: Fixture.now)
            }
            try expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("state").path), "Invalid input consumed namespace")
        }
    }
    for existing in ["valid", "empty", "corrupt"] {
        check("bootstrap never heals existing \(existing) namespace") {
            try withWorkspace { root in
                if existing == "empty" {
                    try FileManager.default.createDirectory(at: root.appendingPathComponent("state"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                } else {
                    try seedState(root)
                    if existing == "corrupt" { try writePrivate(Data("bad".utf8), root.appendingPathComponent("state/checkpoint.json")) }
                }
                try refuses(.existingNamespace) { _ = try Fixture.verifier(root).bootstrapFreshProofNamespace(envelope: Fixture.envelope(), now: Fixture.now) }
            }
        }
    }
    for file in ["checkpoint.json", "namespace.json", "lock"] {
        check("ordinary verification refuses removed \(file)") {
            try withWorkspace { root in
                try seedState(root); try FileManager.default.removeItem(at: root.appendingPathComponent("state/" + file))
                try refuses(.missingState) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
            }
        }
    }
    check("same sequence identical exact payload is idempotent") {
        try withWorkspace { root in
            try seedState(root, sequence: 7)
            let result = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
            try expect(result.sequence == 7, "Idempotent candidate changed")
            try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload()))
        }
    }
    check("lower signed sequence refused without mutation") {
        try withWorkspace { root in
            try seedState(root, sequence: 8)
            try refuses(.replay) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
            try assertCheckpoint(root, sequence: 8, payload: json(Fixture.payload(sequence: 8)))
        }
    }
    for altered in ["field", "serialization"] {
        check("same sequence changed \(altered) refused") {
            try withWorkspace { root in
                try seedState(root, sequence: 7)
                let data: Data
                if altered == "field" { data = try mutatePayload { $0["expiresAt"] = Int64(Fixture.now + 7200) } }
                else { data = try Fixture.signed(Data(" \n".utf8) + json(Fixture.payload())) }
                try refuses(.replay) { _ = try Fixture.verifier(root).verify(envelope: data, now: Fixture.now) }
                try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload()))
            }
        }
    }
    check("reconstructed verifier retains accepted high-water mark") {
        try withWorkspace { root in
            try seedState(root)
            _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now)
            let reconstructed = try Fixture.verifier(root)
            try refuses(.replay) { _ = try reconstructed.verify(envelope: Fixture.envelope(sequence: 6), now: Fixture.now) }
            try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload()))
        }
    }
    check("independent process restart uses physical durable state") {
        try withWorkspace { root in
            _ = try Fixture.verifier(root).bootstrapFreshProofNamespace(envelope: Fixture.envelope(), now: Fixture.now)
            let (status, output) = try boundedChild(["--restart-probe", root.path])
            try expect(status == 0 && output.contains("fixture restart accepted sequence 7"), "Restart failed: \(output)")
        }
    }
    let corruptions: [(String, (inout [String: Any]) -> Void)] = [
        ("reset zero", { $0["sequence"] = 0 }), ("negative", { $0["sequence"] = -1 }),
        ("fraction", { $0["sequence"] = 6.5 }), ("boolean", { $0["sequence"] = true }),
        ("missing hash", { $0.removeValue(forKey: "payloadSHA256") }), ("invalid hash", { $0["payloadSHA256"] = "0" }),
        ("changed catalogue", { $0["catalogueID"] = "other" }), ("changed key", { $0["keyID"] = "other" }),
        ("extra reset flag", { $0["resetAllowed"] = true }), ("changed schema", { $0["schemaVersion"] = 2 })
    ]
    for (name, change) in corruptions {
        check("corrupt checkpoint \(name)") {
            try withWorkspace { root in
                try seedState(root)
                var value = try checkpoint(root); change(&value)
                try writePrivate(json(value), root.appendingPathComponent("state/checkpoint.json"))
                try refuses(.corruptState) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
            }
        }
    }
    for kind in ["empty", "garbage", "duplicate", "escaped duplicate", "BOM", "UTF16", "trailing", "oversize", "overflow"] {
        check("physical checkpoint encoding \(kind)") {
            try withWorkspace { root in
                try seedState(root)
                let file = root.appendingPathComponent("state/checkpoint.json")
                let raw = String(decoding: try Data(contentsOf: file), as: UTF8.self)
                let bytes: Data
                switch kind {
                case "empty": bytes = Data()
                case "garbage": bytes = Data("{oops}".utf8)
                case "duplicate": bytes = Data(("{\"sequence\":1," + raw.dropFirst()).utf8)
                case "escaped duplicate": bytes = Data(("{\"sequen\\u0063e\":1," + raw.dropFirst()).utf8)
                case "BOM": bytes = Data([0xef,0xbb,0xbf]) + Data(raw.utf8)
                case "UTF16": bytes = raw.data(using: .utf16)!
                case "trailing": bytes = Data((raw + "{}").utf8)
                case "overflow": bytes = Data(raw.replacingOccurrences(of: "\"sequence\":6", with: "\"sequence\":18446744073709551616").utf8)
                default: bytes = Data(repeating: 0x20, count: 8193)
                }
                try writePrivate(bytes, file)
                try refuses(.corruptState) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
                try expect(try Data(contentsOf: file) == bytes, "Corrupt checkpoint was silently healed")
            }
        }
    }
    check("namespace marker identity cannot be changed") {
        try withWorkspace { root in
            try seedState(root)
            try writePrivate(json(["schemaVersion": 1, "namespace": "patched-fixture-state-v1", "keyID": "other", "catalogueID": Fixture.catalogueID]), root.appendingPathComponent("state/namespace.json"))
            try refuses(.corruptState) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
        }
    }
    for target in ["checkpoint.json", "namespace.json", "lock", "directory", "ancestor"] {
        check("state symlink \(target)") {
            try withWorkspace { root in
                try seedState(root)
                if target == "directory" {
                    try FileManager.default.moveItem(at: root.appendingPathComponent("state"), to: root.appendingPathComponent("real-state"))
                    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("state").path, withDestinationPath: root.appendingPathComponent("real-state").path)
                } else if target == "ancestor" {
                    let alias = root.appendingPathComponent("alias")
                    try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: root.path)
                    let verifier = CatalogueVerifier(trust: try Fixture.trust(), policy: Fixture.policy(), stateDirectory: alias.appendingPathComponent("state").path)
                    try refuses(.unsafePath) { _ = try verifier.verify(envelope: Fixture.envelope(), now: Fixture.now) }
                    return
                } else {
                    let file = root.appendingPathComponent("state/" + target), real = root.appendingPathComponent("real-file")
                    try FileManager.default.moveItem(at: file, to: real)
                    try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: real.path)
                }
                try refuses(.unsafePath) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
            }
        }
    }
    for target in ["checkpoint.json", "namespace.json", "lock"] {
        for kind in ["fifo", "directory", "hardlink", "wide mode"] {
            check("unsafe state \(target) \(kind)") {
                try withWorkspace { root in
                    try seedState(root); let file = root.appendingPathComponent("state/" + target)
                    if kind == "wide mode" { try expect(chmod(file.path, 0o644) == 0, "Fixture chmod failed") }
                    else if kind == "hardlink" { try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("linked")) }
                    else {
                        try FileManager.default.removeItem(at: file)
                        if kind == "fifo" { try expect(mkfifo(file.path, 0o600) == 0, "Fixture FIFO failed") }
                        else { try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                    }
                    try refuses(.unsafePath) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
                }
            }
        }
    }
    check("state directory must remain private") {
        try withWorkspace { root in
            try seedState(root); try expect(chmod(root.appendingPathComponent("state").path, 0o755) == 0, "Fixture chmod failed")
            try refuses(.unsafePath) { _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(), now: Fixture.now) }
        }
    }
    for path in ["relative/state", "/", "/tmp/../state", "/tmp//state", "/tmp/./state", "/tmp/state\0suffix"] {
        check("unsafe state path spelling \(String(reflecting: path))") {
            let verifier = CatalogueVerifier(trust: try Fixture.trust(), policy: Fixture.policy(), stateDirectory: path)
            try refuses(.unsafePath) { _ = try verifier.verify(envelope: Fixture.envelope(), now: Fixture.now) }
        }
    }
    check("concurrent process lock refuses promptly") {
        try withWorkspace { root in
            try seedState(root)
            let descriptor = open(root.appendingPathComponent("state/lock").path, O_RDWR | O_CLOEXEC)
            try expect(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Fixture lock failed")
            defer { close(descriptor) }
            let (status, output) = try boundedChild(["--locked-probe", root.path])
            try expect(status == 0 && output.contains("fixture concurrent state writer refused"), "Lock exclusion failed: \(output)")
        }
    }
    registerPersistenceChecks()
}

@MainActor func registerPersistenceChecks() {
    for stage in PersistenceStage.allCases {
        check("persist failure at \(stage.rawValue) returns no candidate; physical old or new state") {
            try withWorkspace { root in
                try seedState(root)
                var observed = false
                let verifier = CatalogueVerifier(trust: try Fixture.trust(), policy: Fixture.policy(), stateDirectory: root.appendingPathComponent("state").path) { point in
                    if point == stage { observed = true; throw CoreFailure.persistenceFailed }
                }
                try refuses(.persistenceFailed) { _ = try verifier.verify(envelope: Fixture.envelope(), now: Fixture.now) }
                try expect(observed, "Failure injection never reached actual persistence boundary")
                let state = try checkpoint(root)
                guard let sequence = (state["sequence"] as? NSNumber)?.uint64Value else { throw CheckFailure(description: "Physical checkpoint torn") }
                try expect(sequence == 6 || sequence == 7, "Failed write left neither old nor new checkpoint")
                try assertCheckpoint(root, sequence: sequence, payload: json(Fixture.payload(sequence: sequence)))
                _ = try Fixture.verifier(root).verify(envelope: Fixture.envelope(sequence: sequence), now: Fixture.now)
            }
        }
    }
    check("acceptance occurs after physical file sync rename and directory sync") {
        try withWorkspace { root in
            try seedState(root)
            var stages: [PersistenceStage] = []
            let verifier = CatalogueVerifier(trust: try Fixture.trust(), policy: Fixture.policy(), stateDirectory: root.appendingPathComponent("state").path) { point in
                stages.append(point)
                if point == .directorySynced { try assertCheckpoint(root, sequence: 7, payload: json(Fixture.payload())) }
            }
            _ = try verifier.verify(envelope: Fixture.envelope(), now: Fixture.now)
            try expect(stages == PersistenceStage.allCases, "Returned candidate before complete durable commit sequence")
        }
    }
    check("namespace replacement during commit refuses uncertain state") {
        try withWorkspace { root in
            try seedState(root)
            var moved = false
            let verifier = CatalogueVerifier(trust: try Fixture.trust(), policy: Fixture.policy(), stateDirectory: root.appendingPathComponent("state").path) { point in
                if point == .temporaryWritten {
                    try FileManager.default.moveItem(at: root.appendingPathComponent("state"), to: root.appendingPathComponent("detached-state"))
                    try seedState(root)
                    moved = true
                }
            }
            try refuses(.persistenceFailed) { _ = try verifier.verify(envelope: Fixture.envelope(), now: Fixture.now) }
            try expect(moved, "Replacement did not exercise commit window")
            try assertCheckpoint(root, sequence: 6, payload: json(Fixture.payload(sequence: 6)))
        }
    }
}
