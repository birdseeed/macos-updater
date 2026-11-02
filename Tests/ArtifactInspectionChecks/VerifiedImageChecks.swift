import Foundation
import CryptoKit
import Darwin
@_spi(Testing) import ArtifactInspection

private let viBytes = Data("abc".utf8)
private let viDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
private func viPin(length: Int64 = 3, digest: String = viDigest) -> TargetPin {
    .init(version: "synthetic-held-image-only", url: FirefoxTargets.pins[0].url,
          sha256: digest, byteLength: length)
}
private func viExecutable() -> String {
    URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
}
private func viIdentity(_ fd: Int32) throws -> [String: String] {
    var value = stat()
    guard fstat(fd, &value) == 0 else { throw CheckFailure(description: "Cannot fstat real descriptor") }
    return ["device": String(value.st_dev), "inode": String(value.st_ino), "length": String(value.st_size)]
}
private func viCountDescriptors() -> Int {
    // Fixed small upper bound covers the runner's reviewed slot and temporary fds.
    (0..<512).reduce(0) { $0 + (fcntl(Int32($1), F_GETFD) >= 0 ? 1 : 0) }
}

// This child executes only its own inert test binary. It really opens/reads/fstats
// the inherited object; printing a supplied descriptor number cannot pass checks.
func runVerifiedImageChild(_ arguments: [String]) -> Never {
    guard arguments.count == 3, arguments[0] == "--verified-image-child" else { exit(90) }
    let mode = arguments[1], operand = arguments[2]
    guard ["read", "fail", "flood", "sleep"].contains(mode) else { exit(91) }
    let fd = open(operand, O_RDONLY)
    guard fd >= 0 else { exit(92) }
    defer { close(fd) }
    do {
        var observed = try viIdentity(fd)
        var buffer = [UInt8](repeating: 0, count: 65)
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count >= 0, count <= 64 else { exit(93) }
        observed["bytes"] = Data(buffer.prefix(count)).base64EncodedString()
        observed["access"] = String(fcntl(fd, F_GETFL) & O_ACCMODE)
        observed["sentinel199Open"] = fcntl(199, F_GETFD) >= 0 ? "yes" : "no"
        let data = try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        if mode == "fail" { exit(7) }
        if mode == "flood" {
            let chunk = Data(repeating: 65, count: 4096)
            while true { FileHandle.standardOutput.write(chunk) }
        }
        if mode == "sleep" { sleep(10) }
        exit(0)
    } catch { exit(94) }
}

private func viRead(_ handle: VerifiedImageFixtureHandle, mode: String = "read",
                    limits: InspectionLimits = .init()) throws -> CommandResult {
    try handle.run(executable: viExecutable(),
                   arguments: ["--verified-image-child", mode, handle.operand], limits: limits)
}
private func viAssertChild(_ result: CommandResult, identity: [String: String], bytes: Data = viBytes) throws {
    try expect(result.exitCode == 0 && !result.timedOut && !result.outputExceeded, "Real inherited child did not complete")
    let decoded = try JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8))
    for key in ["device", "inode", "length"] {
        try expect(decoded[key] == identity[key], "Child fstat did not bind exact retained \(key)")
    }
    try expect(decoded["bytes"] == bytes.base64EncodedString(), "Child read substituted or offset bytes")
    try expect(decoded["access"] == String(O_RDONLY), "Child image descriptor must be read-only")
    try expect(result.executable == viExecutable() && result.arguments == ["--verified-image-child", "read", "/dev/fd/198"],
               "Recorded executable/argv must be actual descriptor invocation")
}
private func viWorkspace(_ body: (URL, URL, URL) throws -> Void) throws {
    try withWorkspace { root in
        let source = root.appendingPathComponent("source.dmg")
        let stage = root.appendingPathComponent("stage")
        try viBytes.write(to: source)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try body(root, source, stage)
    }
}
private func viEvidence() throws -> AppEvidence {
    let pin = FirefoxTargets.pins[0], app = "/fixture/private/Firefox.app", dmg = "/dev/fd/198"
    return AppEvidence(appPath: app, dmgPath: dmg, infoPlist: try plist([
        "CFBundleIdentifier": pin.bundleID, "CFBundleShortVersionString": pin.version,
        "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]), commands: [
        "imageVerify": .init(executable: "/usr/bin/hdiutil", arguments: ["verify", dmg]),
        "gatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--verbose=4", app],
                            stderr: app + ": accepted\nsource=Notarized Developer ID\n"),
        "containerSignature": .init(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", dmg], exitCode: 1),
        "containerGatekeeper": .init(executable: "/usr/sbin/spctl", arguments: ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg], exitCode: 3)
    ], schemaVersion: 3, architectureObservation: .init(executablePath: app + "/Contents/MacOS/firefox", architectures: pin.architectures.sorted()),
       signatureObservation: .init(appPath: app, requirement: try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID),
           validationFlags: PinnedSignatureRequirement.validationFlags, validationStatus: 0, signingInformationStatus: 0,
           teamID: pin.teamID, identifier: pin.bundleID,
           startedAt: "2026-10-07T14:35:32Z", finishedAt: "2026-10-07T14:35:33Z"))
}

@MainActor func addVerifiedImageChecks() {
    check("PAT-2710 pathname-only positive control reads replacement bytes") {
        try viWorkspace { _, source, _ in
            let retained = open(source.path, O_RDONLY | O_CLOEXEC); guard retained >= 0 else { throw CheckFailure(description: "Open failed") }
            defer { close(retained) }
            let before = try viIdentity(retained)
            try FileManager.default.moveItem(at: source, to: source.appendingPathExtension("old"))
            try Data("xyz".utf8).write(to: source)
            let result = try BoundedCommandRunner().run(executable: viExecutable(), arguments: ["--verified-image-child", "read", source.path], limits: .init())
            let output = try JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8))
            try expect(result.exitCode == 0 && output["bytes"] == Data("xyz".utf8).base64EncodedString(), "Path-only control did not observe substitution")
            try expect(output["inode"] != before["inode"], "Control replacement must use a different inode")
        }
    }
    check("PAT-2710 CLOEXEC negative control does not inherit slot") {
        let result = try BoundedCommandRunner().run(executable: viExecutable(), arguments: ["--verified-image-child", "read", "/dev/fd/198"], limits: .init())
        try expect(result.exitCode == 92 && result.stdout.isEmpty, "Unmapped child slot unexpectedly readable")
    }
    for replacement in ["file", "symlink", "directory", "absent"] {
        check("PAT-2710 staged pathname \(replacement) substitution cannot replace child bytes") {
            try viWorkspace { root, source, stage in
                try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                    let identity = try viIdentity(handle.descriptor)
                    try expect(handle.operand == "/dev/fd/198", "Child operand must be fixed")
                    try expect(fcntl(handle.descriptor, F_GETFD) & FD_CLOEXEC != 0, "Parent descriptor lost CLOEXEC")
                    try expect(fcntl(handle.descriptor, F_GETFL) & O_ACCMODE == O_RDONLY, "Retained image is writable")
                    let staged = stage.appendingPathComponent("artifact.dmg")
                    try expect(!FileManager.default.fileExists(atPath: staged.path), "Final verified snapshot must be unlinked")
                    let other = root.appendingPathComponent("replacement"); try Data("xyz".utf8).write(to: other)
                    if replacement == "file" { try Data("xyz".utf8).write(to: staged) }
                    if replacement == "symlink" { try FileManager.default.createSymbolicLink(at: staged, withDestinationURL: other) }
                    if replacement == "directory" { try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false) }
                    try viAssertChild(viRead(handle), identity: identity)
                }
            }
        }
    }
    check("PAT-2710 ancestor replacement cannot redirect held image") {
        try viWorkspace { _, source, stage in
            try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                let identity = try viIdentity(handle.descriptor)
                try FileManager.default.moveItem(at: stage, to: stage.appendingPathExtension("old"))
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try Data("xyz".utf8).write(to: stage.appendingPathComponent("artifact.dmg"))
                try viAssertChild(viRead(handle), identity: identity)
            }
        }
    }
    check("PAT-2710 sequential children bind same inode and rewind consumed offset") {
        try viWorkspace { _, source, stage in
            try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                let identity = try viIdentity(handle.descriptor)
                try viAssertChild(viRead(handle), identity: identity)
                try viAssertChild(viRead(handle), identity: identity)
            }
        }
    }
    check("PAT-2710 local copy isolates later source mutation and closes on success") {
        try viWorkspace { _, source, stage in
            let baseline = viCountDescriptors(); var owned: Int32 = -1
            try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                owned = handle.descriptor
                try Data("xyz".utf8).write(to: source)
                try viAssertChild(viRead(handle), identity: viIdentity(handle.descriptor))
            }
            try expect(fcntl(owned, F_GETFD) == -1 && errno == EBADF, "Owned reader leaked after return")
            try expect(viCountDescriptors() == baseline, "Local stage/runner descriptors leaked")
        }
    }
    check("PAT-2710 download receiver finalises exact retained bytes without network") {
        try viWorkspace { _, _, stage in
            let baseline = viCountDescriptors()
            try VerifiedImageFixtures.withDownloadedImage(pin: viPin(), chunks: [Data("a".utf8), Data("bc".utf8)], workspace: stage.path) { handle in
                try expect(!FileManager.default.fileExists(atPath: stage.appendingPathComponent("artifact.dmg").path), "Download staged name still exposed")
                try viAssertChild(viRead(handle), identity: viIdentity(handle.descriptor))
            }
            try expect(viCountDescriptors() == baseline, "Receiver writer/reader ownership leaked")
        }
    }
    for (label, pin, reason) in [("digest", viPin(digest: String(repeating: "0", count: 64)), InspectionFailure.digestMismatch),
                                 ("length", viPin(length: 4), .lengthMismatch)] {
        check("PAT-2710 local \(label) mismatch refuses before callback and closes descriptors") {
            try viWorkspace { _, source, stage in
                let baseline = viCountDescriptors(); var called = false
                try refuses(reason) { try VerifiedImageFixtures.withLocalImage(path: source.path, pin: pin, workspace: stage.path) { _ in called = true } }
                try expect(!called && viCountDescriptors() == baseline, "Refused staging ran callback or leaked descriptor")
            }
        }
    }
    check("PAT-2710 downloaded bad digest refuses before callback") {
        try viWorkspace { _, _, stage in
            var called = false
            try refuses(.digestMismatch) { try VerifiedImageFixtures.withDownloadedImage(pin: viPin(), chunks: [Data("xyz".utf8)], workspace: stage.path) { _ in called = true } }
            try expect(!called, "Unverified download reached callback")
        }
    }
    for mode in ["closed", "write-only", "directory"] {
        check("PAT-2710 borrowed \(mode) descriptor refuses without ownership transfer") {
            try viWorkspace { _, source, stage in
                let fd = open(mode == "directory" ? stage.path : source.path, (mode == "write-only" ? O_WRONLY : O_RDONLY) | O_CLOEXEC)
                guard fd >= 0 else { throw CheckFailure(description: "Invalid control setup") }
                if mode == "closed" { close(fd) }
                defer { if mode != "closed" { close(fd) } }
                var called = false
                do {
                    try VerifiedImageFixtures.withDescriptor(descriptor: fd, pin: viPin()) { _ in called = true }
                    throw CheckFailure(description: "Invalid borrowed descriptor admitted")
                } catch is InspectionFailure {}
                try expect(!called, "Invalid borrowed input reached callback")
                if mode != "closed" { try expect(fcntl(fd, F_GETFD) >= 0, "Borrowed descriptor was closed") }
            }
        }
    }
    check("PAT-2710 borrowed read-only descriptor remains owned by caller") {
        try viWorkspace { _, source, _ in
            let fd = open(source.path, O_RDONLY | O_CLOEXEC); guard fd >= 0 else { throw CheckFailure(description: "Open failed") }
            defer { close(fd) }
            let identity = try viIdentity(fd), baseline = viCountDescriptors()
            try VerifiedImageFixtures.withDescriptor(descriptor: fd, pin: viPin()) { handle in try viAssertChild(viRead(handle), identity: identity) }
            try expect(fcntl(fd, F_GETFD) >= 0 && viCountDescriptors() == baseline, "Borrowed ownership changed or dup leaked")
        }
    }
    check("PAT-2710 source already at child slot survives spawn and remains caller-owned") {
        try viWorkspace { _, source, _ in
            try expect(fcntl(198, F_GETFD) == -1 && errno == EBADF, "Cannot safely reserve collision control slot")
            let input = open(source.path, O_RDONLY | O_CLOEXEC)
            guard input >= 0 else { throw CheckFailure(description: "Open collision control failed") }
            defer { close(input) }
            guard dup2(input, 198) == 198 else { throw CheckFailure(description: "Reserve collision slot failed") }
            defer { close(198) }
            try expect(fcntl(198, F_SETFD, FD_CLOEXEC) == 0, "Cannot protect collision slot")
            let identity = try viIdentity(198)
            try VerifiedImageFixtures.withDescriptor(descriptor: 198, pin: viPin()) { handle in
                try viAssertChild(viRead(handle), identity: identity)
            }
            try expect(fcntl(198, F_GETFD) & FD_CLOEXEC != 0, "Caller collision slot closed or flags mutated")
        }
    }
    check("PAT-2710 unrelated CLOEXEC sentinel never exposed to child or closed in parent") {
        try viWorkspace { _, source, stage in
            try expect(fcntl(199, F_GETFD) == -1 && errno == EBADF, "Cannot safely reserve sentinel slot")
            let input = open(source.path, O_RDONLY | O_CLOEXEC)
            guard input >= 0 else { throw CheckFailure(description: "Open sentinel failed") }
            defer { close(input) }
            guard dup2(input, 199) == 199 else { throw CheckFailure(description: "Reserve sentinel failed") }
            defer { close(199) }
            try expect(fcntl(199, F_SETFD, FD_CLOEXEC) == 0, "Cannot set sentinel CLOEXEC")
            try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                let result = try viRead(handle)
                try viAssertChild(result, identity: viIdentity(handle.descriptor))
                let output = try JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8))
                try expect(output["sentinel199Open"] == "no", "Runner leaked unrelated descriptor")
            }
            try expect(fcntl(199, F_GETFD) & FD_CLOEXEC != 0, "Runner closed or changed foreign parent descriptor")
        }
    }
    check("PAT-2710 substituted child operand refuses before spawning") {
        try viWorkspace { _, source, stage in
            try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                try refuses(.invalidMetadata) {
                    _ = try handle.run(executable: viExecutable(), arguments: ["--verified-image-child", "read", "/dev/fd/197"])
                }
            }
        }
    }
    for mode in ["fail", "flood", "sleep", "spawn-failure", "callback-throw"] {
        check("PAT-2710 \(mode) preserves refusal limits and closes owned descriptors") {
            try viWorkspace { _, source, stage in
                let baseline = viCountDescriptors(); var owned: Int32 = -1; var reached = false
                do {
                    try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                        reached = true; owned = handle.descriptor
                        if mode == "callback-throw" { throw InspectionFailure.wrongTeam }
                        if mode == "spawn-failure" {
                            try refuses(.commandFailed) { _ = try handle.run(executable: "/nonexistent/pat-2710-child", arguments: [handle.operand]) }
                            return
                        }
                        var limits = InspectionLimits(); limits.commandSeconds = mode == "sleep" ? 0.1 : 2; limits.outputBytes = 1024
                        let result = try viRead(handle, mode: mode, limits: limits)
                        if mode == "fail" { try expect(result.exitCode == 7 && !result.timedOut, "Child exit was hidden") }
                        if mode == "flood" { try expect(result.outputExceeded && result.stdout.utf8.count + result.stderr.utf8.count <= 1024, "Output bound lost") }
                        if mode == "sleep" { try expect(result.timedOut && result.exitCode != 0, "Timeout did not kill image child") }
                    }
                    try expect(mode != "callback-throw", "Throwing callback was swallowed")
                } catch let error as InspectionFailure {
                    try expect(mode == "callback-throw" && error == .wrongTeam, "Unexpected factory/runner refusal \(error)")
                }
                try expect(reached && owned >= 0, "Failure test never exercised the held image")
                try expect(fcntl(owned, F_GETFD) == -1 && viCountDescriptors() == baseline, "Error path leaked owned descriptors")
            }
        }
    }
    check("PAT-2710 held writable alias explicitly demonstrates in-place mutation limitation") {
        try viWorkspace { _, source, _ in
            let writer = open(source.path, O_RDWR | O_CLOEXEC), reader = open(source.path, O_RDONLY | O_CLOEXEC)
            guard writer >= 0 && reader >= 0 else { throw CheckFailure(description: "Alias control setup failed") }
            defer { close(writer); close(reader) }
            try VerifiedImageFixtures.withDescriptor(descriptor: reader, pin: viPin()) { handle in
                let identity = try viIdentity(handle.descriptor)
                try expect(fchmod(writer, 0o400) == 0, "Cannot set control permissions")
                let changed = Data("xyz".utf8).withUnsafeBytes { pwrite(writer, $0.baseAddress, $0.count, 0) }
                try expect(changed == 3, "A pre-held writer must demonstrate chmod is not an immutable seal")
                // The primitive may detect/refuse mutation; if it invokes a child,
                // it must truthfully expose mutated bytes, never assert immutability.
                do { try viAssertChild(viRead(handle), identity: identity, bytes: Data("xyz".utf8)) }
                catch is InspectionFailure { return }
            }
        }
    }
    check("PAT-2710 schema3 descriptor record replays without fresh or installation authority") {
        let value = try viEvidence(), pin = FirefoxTargets.pins[0]
        let encoded = try JSONEncoder().encode(value), replay = try EvidenceEvaluator.replay(encoded, pin: pin)
        try expect(replay.appChecksPassed && replay.origin == .replayed && !replay.freshOSValidation && !replay.installationAuthorized,
                   "Descriptor record replay manufactured current authority")
        let decoded = try JSONDecoder().decode(AppEvidence.self, from: encoded)
        try expect(decoded.dmgPath == "/dev/fd/198" && decoded.commands["imageVerify"]?.arguments == ["verify", "/dev/fd/198"], "Record rewrote actual descriptor argv")
    }
    for key in ["imageVerify", "containerSignature", "containerGatekeeper"] {
        check("PAT-2710 schema3 refuses substituted \(key) operand") {
            var value = try viEvidence()
            var command = value.commands[key]!
            command.arguments[command.arguments.count - 1] = "/fixture/substituted.dmg"
            value.commands[key] = command
            try refuses(.invalidMetadata) { _ = try EvidenceEvaluator.replay(JSONEncoder().encode(value), pin: FirefoxTargets.pins[0]) }
        }
    }
    check("PAT-2710 native attach builder uses exact retained-image kernel command") {
        let arguments = try VerifiedImageFixtures.nativeAttachArguments(mountPath: "/private/tmp/pat-2710/mount")
        try expect(arguments == ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                                 "/private/tmp/pat-2710/mount", "/dev/fd/198"],
                   "Native attach builder changed the required kernel-only retained-image command")
    }
    check("PAT-2710 native attach policy admits the canonical kernel command") {
        let arguments = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        try expect(VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy refused the canonical retained-image kernel command")
    }
    check("PAT-2710 native attach policy refuses the default helper command") {
        let arguments = ["attach", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy permitted attach without kernel mode")
    }
    check("PAT-2710 native attach policy refuses a different descriptor") {
        var arguments = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        arguments[7] = "/dev/fd/197"
        try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy permitted a substituted retained-image descriptor")
    }
    check("PAT-2710 native attach policy refuses executable substitution") {
        let arguments = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        for executable in ["hdiutil", "/tmp/hdiutil", "/usr/bin/true", "/usr/bin/hdiutil "] {
            try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: executable, arguments: arguments),
                       "Native attach policy permitted executable substitution")
        }
    }
    check("PAT-2710 native attach policy requires read-only mode") {
        let arguments = ["attach", "-kernel", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy permitted writable default mode")
    }
    check("PAT-2710 native attach policy requires no-browse mode") {
        let arguments = ["attach", "-kernel", "-readonly", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy permitted Finder browsing")
    }
    check("PAT-2710 native attach policy refuses duplicate and unknown flags") {
        let canonical = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        for flag in ["-kernel", "-helper", "-noverify", "-shadow"] {
            var arguments = canonical
            arguments.insert(flag, at: 2)
            try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                       "Native attach policy permitted an additional flag")
        }
    }
    check("PAT-2710 native attach policy refuses reordered flags") {
        let arguments = ["attach", "-readonly", "-kernel", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy accepted a noncanonical command order")
    }
    check("PAT-2710 native attach policy refuses extra operands") {
        let arguments = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198", "/tmp/substituted.dmg"]
        try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                   "Native attach policy permitted a second image operand")
    }
    check("PAT-2710 native attach builder and policy refuse unsafe mount paths") {
        for mountPath in ["relative/mount", "", "/tmp/../mount", "/tmp/./mount", "/tmp//mount", "/tmp/mount\n"] {
            try refuses(.unsafePath) { _ = try VerifiedImageFixtures.nativeAttachArguments(mountPath: mountPath) }
            let arguments = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint", mountPath, "/dev/fd/198"]
            try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                       "Native attach policy permitted an unsafe mount path")
        }
    }
    check("PAT-2710 native attach policy refuses command and image-source substitution") {
        let canonical = ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint",
                         "/private/tmp/pat-2710/mount", "/dev/fd/198"]
        for command in ["verify", "detach"] {
            var arguments = canonical
            arguments[0] = command
            try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                       "Native attach policy permitted command substitution")
        }
        for operand in ["/tmp/artifact.dmg", "https://example.invalid/artifact.dmg", "http://127.0.0.1/artifact.dmg", "/dev/fd/198/../197"] {
            var arguments = canonical
            arguments[7] = operand
            try expect(!VerifiedImageFixtures.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments),
                       "Native attach policy permitted a pathname, URL or noncanonical descriptor operand")
        }
    }
    addLoopbackImageChecks()
}

// Independent client and parser: no productive HTTP parsing or URL authority is
// reused. Every connect/read/write has one absolute three-second deadline.
private struct VILoopResponse {
    let status: Int
    let headers: [String: String]
    let body: Data
}
private func viLoopEndpoint(_ source: LoopbackImageFixtureSource) throws -> (UInt16, String, String) {
    guard let parts = URLComponents(string: source.url), parts.scheme == "http", parts.host == "127.0.0.1",
          let port = parts.port, port > 0 && port <= 65535, parts.user == nil, parts.password == nil,
          parts.query == nil, parts.fragment == nil else { throw CheckFailure(description: "Non-numeric loopback source URL") }
    let segments = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 3, segments[0].isEmpty, segments[1].count >= 32,
          segments[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
          segments[2] == "artifact.dmg" else { throw CheckFailure(description: "Missing opaque loopback capability path") }
    return (UInt16(port), parts.percentEncodedPath, "127.0.0.1:\(port)")
}
private func viLoopConnect(_ source: LoopbackImageFixtureSource) throws -> Int32 {
    let (port, _, _) = try viLoopEndpoint(source)
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CheckFailure(description: "Client socket failed") }
    do {
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw CheckFailure(description: "Client flags failed") }
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw CheckFailure(description: "Client SIGPIPE protection failed") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian; address.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw CheckFailure(description: "Loopback connect refused") }
            try viLoopPoll(fd, Int16(POLLOUT), deadline: Date.timeIntervalSinceReferenceDate + 3)
            var error: Int32 = 0; var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw CheckFailure(description: "Loopback connect completion failed") }
        }
        return fd
    } catch { close(fd); throw error }
}
private func viLoopPoll(_ fd: Int32, _ events: Int16, deadline: Double) throws {
    while true {
        let remaining = deadline - Date.timeIntervalSinceReferenceDate
        guard remaining > 0 else { throw CheckFailure(description: "Raw client deadline exceeded") }
        var item = pollfd(fd: fd, events: events, revents: 0)
        let result = poll(&item, 1, Int32(min(remaining * 1000 + 1, 3000)))
        if result < 0 && errno == EINTR { continue }
        guard result > 0, item.revents & (events | Int16(POLLHUP) | Int16(POLLERR)) != 0 else { throw CheckFailure(description: "Raw client poll failed") }
        return
    }
}
private func viLoopExchange(_ source: LoopbackImageFixtureSource, raw: String, waitBeforeRead: Double = 0) throws -> VILoopResponse? {
    let fd = try viLoopConnect(source); defer { close(fd) }
    let deadline = Date.timeIntervalSinceReferenceDate + 3
    let outbound = Array(raw.utf8); var sent = 0
    while sent < outbound.count {
        try viLoopPoll(fd, Int16(POLLOUT), deadline: deadline)
        let count = outbound.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: sent), outbound.count - sent, 0) }
        if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
        if count <= 0 { break }; sent += count
    }
    if waitBeforeRead > 0 { Thread.sleep(forTimeInterval: waitBeforeRead) }
    var received = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        try viLoopPoll(fd, Int16(POLLIN), deadline: deadline)
        let count = Darwin.recv(fd, &buffer, buffer.count, 0)
        if count == 0 { break }
        if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
        if count < 0 && (errno == ECONNRESET || errno == EPIPE) { break }
        guard count > 0, received.count + count <= 512 * 1024 else { throw CheckFailure(description: "Raw client response exceeded bound") }
        received.append(contentsOf: buffer.prefix(count))
    }
    if received.isEmpty { return nil }
    guard let separator = received.range(of: Data([13, 10, 13, 10])), separator.lowerBound <= 8192,
          let text = String(data: received[..<separator.lowerBound], encoding: .utf8) else { throw CheckFailure(description: "Invalid HTTP response framing") }
    let lines = text.components(separatedBy: "\r\n"), statusParts = lines[0].split(separator: " ")
    guard statusParts.count >= 2, statusParts[0] == "HTTP/1.1", let status = Int(statusParts[1]) else { throw CheckFailure(description: "Invalid HTTP status") }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else { throw CheckFailure(description: "Malformed response header") }
        let name = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard headers[name] == nil else { throw CheckFailure(description: "Duplicate response header") }; headers[name] = value
    }
    return .init(status: status, headers: headers, body: Data(received[separator.upperBound...]))
}
private func viLoopRequest(_ source: LoopbackImageFixtureSource, method: String = "GET", range: String? = nil) throws -> String {
    let (_, path, host) = try viLoopEndpoint(source)
    return "\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\n" + (range.map { "Range: \($0)\r\n" } ?? "") + "Connection: close\r\n\r\n"
}
private func viLoopRefusal(_ response: VILoopResponse?) throws {
    if let response {
        try expect(response.status >= 400 && response.status <= 599, "Unsafe request received success/redirect")
        try expect(response.body.isEmpty, "Refusal disclosed a body")
        try expect(response.headers["location"] == nil, "Refusal redirected")
    }
}
private func viLoop(_ limits: LoopbackImageFixtureLimits = .init(), _ body: (VerifiedImageFixtureHandle, LoopbackImageFixtureSource) throws -> Void) throws {
    try viWorkspace { _, source, stage in
        try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
            try handle.withLoopbackSource(limits: limits) { try body(handle, $0) }
        }
    }
}
private func viLoopClosed(_ fd: Int32) -> Bool { fcntl(fd, F_GETFD) == -1 && errno == EBADF }
private func viLoopObserveStopped(_ source: LoopbackImageFixtureSource, closedDescriptor: Int32? = nil) throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + 1_500_000_000
    while source.metrics.running || (closedDescriptor.map { !viLoopClosed($0) } ?? false) {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw CheckFailure(description: "Bridge stop was not observable within bounded join allowance")
        }
        Thread.sleep(forTimeInterval: 0.005)
    }
}

@MainActor private func addLoopbackImageChecks() {
    check("PAT-2710 loopback GET returns exact identity bytes and fixed framing") {
        try viLoop { _, source in
            guard let response = try viLoopExchange(source, raw: viLoopRequest(source)) else { throw CheckFailure(description: "No GET response") }
            try expect(response.status == 200 && response.body == viBytes && response.headers["content-length"] == "3", "Full GET bytes/length differ")
            try expect(response.headers["content-type"] == "application/octet-stream" && response.headers["accept-ranges"] == "bytes", "Missing fixed image headers")
            try expect(response.headers["connection"]?.lowercased() == "close" && response.headers["transfer-encoding"] == nil && response.headers["content-encoding"] == nil && response.headers["location"] == nil, "Nonidentity or unbounded response")
        }
    }
    check("PAT-2710 loopback HEAD describes image without transmitting body") {
        try viLoop { _, source in
            guard let response = try viLoopExchange(source, raw: viLoopRequest(source, method: "HEAD")) else { throw CheckFailure(description: "No HEAD response") }
            try expect(response.status == 200 && response.body.isEmpty && response.headers["content-length"] == "3", "HEAD body/length wrong")
            try expect(source.metrics.servedBytes == 0 && source.metrics.requests == 1, "HEAD accounting wrong")
        }
    }
    check("PAT-2710 loopback single closed open suffix ranges return exact bytes") {
        try viLoop { _, source in
            for (range, bytes, contentRange) in [("bytes=0-0", "a", "bytes 0-0/3"), ("bytes=1-", "bc", "bytes 1-2/3"), ("bytes=-2", "bc", "bytes 1-2/3"), ("bytes=0-99", "abc", "bytes 0-2/3")] {
                guard let response = try viLoopExchange(source, raw: viLoopRequest(source, range: range)) else { throw CheckFailure(description: "No range response") }
                try expect(response.status == 206 && response.body == Data(bytes.utf8) && response.headers["content-range"] == contentRange && response.headers["content-length"] == String(bytes.utf8.count), "Incorrect independent range result")
            }
        }
    }
    check("PAT-2710 loopback refuses unsatisfiable multiple malformed overflow ranges") {
        for range in ["bytes=3-", "bytes=2-1", "bytes=-0", "bytes=0-0,2-2", "items=0-1", "bytes=a-b", "bytes=", "bytes=+0-1", "bytes=18446744073709551616-", "bytes=-18446744073709551616"] {
            try viLoop { _, source in try viLoopRefusal(viLoopExchange(source, raw: viLoopRequest(source, range: range))) }
        }
    }
    check("PAT-2710 loopback capability paths cannot read arbitrary files or traverse") {
        for target in ["/wrong/artifact.dmg", "/etc/passwd", "/../artifact.dmg", "/%2e%2e/artifact.dmg", "http://example.invalid/artifact.dmg"] {
            try viLoop { _, source in
                let (_, _, host) = try viLoopEndpoint(source)
                try viLoopRefusal(viLoopExchange(source, raw: "GET \(target) HTTP/1.1\r\nHost: \(host)\r\n\r\n"))
            }
        }
    }
    check("PAT-2710 loopback rejects wrong missing duplicate Host and folded headers") {
        for hostLine in ["Host: localhost", "Host: example.invalid", "", "Host: 127.0.0.1:1", "Host: HOST\r\nHost: HOST", "Host: HOST\r\n continuation", "Host HOST"] {
            try viLoop { _, source in
                let (_, path, host) = try viLoopEndpoint(source)
                let header = hostLine.replacingOccurrences(of: "HOST", with: host)
                try viLoopRefusal(viLoopExchange(source, raw: "GET \(path) HTTP/1.1\r\n\(header)\r\n\r\n"))
            }
        }
    }
    check("PAT-2710 loopback rejects methods bodies duplicate ranges and oversized headers") {
        for suffix in ["Content-Length: 1\r\n\r\nx", "Content-Length: 0\r\nContent-Length: 0\r\n\r\n", "Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n", "Range: bytes=0-0\r\nRange: bytes=1-1\r\n\r\n", "X-Fill: " + String(repeating: "x", count: 8193) + "\r\n\r\n"] {
            try viLoop { _, source in
                let (_, path, host) = try viLoopEndpoint(source)
                try viLoopRefusal(viLoopExchange(source, raw: "GET \(path) HTTP/1.1\r\nHost: \(host)\r\n\(suffix)"))
            }
        }
        for method in ["POST", "PUT", "CONNECT", "DELETE", "get"] {
            try viLoop { _, source in try viLoopRefusal(viLoopExchange(source, raw: viLoopRequest(source, method: method))) }
        }
    }
    check("PAT-2710 loopback listener is exclusively numeric127 and descriptors CLOEXEC") {
        try viLoop { handle, source in
            let (port, _, _) = try viLoopEndpoint(source)
            var address = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let status = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(source.listenerDescriptor, $0, &length) }
            }
            try expect(status == 0 && address.sin_family == sa_family_t(AF_INET) && address.sin_addr.s_addr == UInt32(0x7f000001).bigEndian && address.sin_port == port.bigEndian, "Listener bound wildcard/external address")
            for fd in [source.listenerDescriptor, source.readerDescriptor] { let flags = fcntl(fd, F_GETFD); try expect(fd >= 0 && flags >= 0 && flags & FD_CLOEXEC != 0, "Bridge fd missing CLOEXEC") }
            let readerIdentity = try viIdentity(source.readerDescriptor), heldIdentity = try viIdentity(handle.descriptor)
            try expect(fcntl(source.readerDescriptor, F_GETFL) & O_ACCMODE == O_RDONLY && readerIdentity == heldIdentity, "Bridge reader is not exact read-only verified object")
        }
    }
    check("PAT-2710 loopback capabilities differ across independent bridge scopes") {
        var firstURL = ""
        try viLoop { _, source in firstURL = source.url; _ = try viLoopEndpoint(source) }
        try viLoop { _, source in
            _ = try viLoopEndpoint(source)
            let firstPath = URLComponents(string: firstURL)?.percentEncodedPath
            let secondPath = URLComponents(string: source.url)?.percentEncodedPath
            try expect(firstPath != secondPath, "Capability token reused between bridges")
        }
    }
    check("PAT-2710 loopback request cap refuses excess requests and stops") {
        try viLoop(.init(maximumRequests: 1)) { _, source in
            let first = try viLoopExchange(source, raw: viLoopRequest(source))
            try expect(first?.body == viBytes, "First bounded request failed")
            do { try viLoopRefusal(viLoopExchange(source, raw: viLoopRequest(source))) }
            catch let error as CheckFailure {
                guard !source.metrics.running && error.description.hasPrefix("Loopback connect") else { throw error }
            }
            try viLoopObserveStopped(source)
            try expect(source.metrics.requests <= 1 && source.metrics.servedBytes == 3 && !source.metrics.running, "Request cap did not close bridge")
        }
    }
    check("PAT-2710 loopback hard default byte allowance is at most eight image lengths") {
        try viLoop { _, source in
            for _ in 0..<8 {
                let response = try viLoopExchange(source, raw: viLoopRequest(source))
                try expect(response?.body == viBytes, "Default byte allowance refused permitted image")
            }
            do { try viLoopRefusal(viLoopExchange(source, raw: viLoopRequest(source))) }
            catch let error as CheckFailure {
                guard !source.metrics.running && error.description.hasPrefix("Loopback connect") else { throw error }
            }
            try expect(source.metrics.servedBytes == 24, "Default bridge exceeded eight image lengths")
        }
    }
    check("PAT-2710 loopback byte cap refuses before transmitting excess image bytes") {
        try viLoop(.init(maximumBytes: 2)) { _, source in
            try viLoopRefusal(viLoopExchange(source, raw: viLoopRequest(source)))
            try expect(source.metrics.servedBytes == 0, "Over-budget response transmitted partial image")
        }
    }
    check("PAT-2710 loopback lifetime cap closes idle listener within bounded join") {
        try viLoop(.init(lifetimeSeconds: 0.05)) { _, source in
            let listener = source.listenerDescriptor
            try viLoopObserveStopped(source, closedDescriptor: listener)
            try expect(!source.metrics.running && viLoopClosed(listener), "Expired bridge still active")
        }
    }
    check("PAT-2710 loopback incomplete header deadline closes client without bytes") {
        try viLoop(.init(headerSeconds: 0.05)) { _, source in
            let (_, path, host) = try viLoopEndpoint(source)
            try viLoopRefusal(viLoopExchange(source, raw: "GET \(path) HTTP/1.1\r\nHost: \(host)\r\n", waitBeforeRead: 0.15))
            try expect(source.metrics.servedBytes == 0, "Incomplete request disclosed bytes")
        }
    }
    check("PAT-2710 loopback rejects invalid or raised fixture limits before callback") {
        let invalid: [LoopbackImageFixtureLimits] = [.init(maximumRequests: 0), .init(maximumRequests: -1), .init(maximumRequests: 8193), .init(maximumBytes: 0), .init(maximumBytes: -1), .init(maximumBytes: 25), .init(lifetimeSeconds: 0), .init(lifetimeSeconds: -1), .init(lifetimeSeconds: 181), .init(lifetimeSeconds: .infinity), .init(lifetimeSeconds: .nan), .init(headerSeconds: 0), .init(headerSeconds: -1), .init(headerSeconds: 3), .init(headerSeconds: .infinity), .init(headerSeconds: .nan)]
        try viWorkspace { _, source, stage in
            try VerifiedImageFixtures.withLocalImage(path: source.path, pin: viPin(), workspace: stage.path) { handle in
                for limits in invalid {
                    var called = false; let baseline = viCountDescriptors()
                    try refuses(.invalidMetadata) { try handle.withLoopbackSource(limits: limits) { _ in called = true } }
                    try expect(!called && baseline == viCountDescriptors(), "Invalid limits ran callback or leaked descriptors")
                }
            }
        }
    }
    check("PAT-2710 loopback explicit stop closes reader listener and is idempotent") {
        try viLoop { handle, source in
            let reader = source.readerDescriptor, listener = source.listenerDescriptor, start = Date.timeIntervalSinceReferenceDate
            try source.stop(); try source.stop()
            try expect(Date.timeIntervalSinceReferenceDate - start < 2 && !source.metrics.running && viLoopClosed(reader) && viLoopClosed(listener), "Stop did not close/join bounded bridge")
            try expect(fcntl(handle.descriptor, F_GETFD) >= 0, "Stop closed factory-owned image")
            try refuses(.invalidMetadata) { _ = try source.nativeAttachArguments(mountPath: "/private/tmp/pat-2710/mount") }
        }
    }
    check("PAT-2710 loopback callback throw closes bridge and preserves exact error") {
        let baseline = viCountDescriptors(); var escaped: LoopbackImageFixtureSource?
        do {
            try viLoop { _, source in escaped = source; throw InspectionFailure.wrongTeam }
            throw CheckFailure(description: "Callback throw swallowed")
        } catch let error as InspectionFailure { try expect(error == .wrongTeam, "Callback error changed") }
        try expect(escaped != nil && escaped?.metrics.running == false && viCountDescriptors() == baseline, "Throw leaked bridge ownership")
    }
    check("PAT-2710 loopback escaped fixture source loses authority after scope") {
        let baseline = viCountDescriptors(); var escaped: LoopbackImageFixtureSource?; var descriptors: [Int32] = []
        try viLoop { _, source in escaped = source; descriptors = [source.readerDescriptor, source.listenerDescriptor] }
        guard let escaped else { throw CheckFailure(description: "No escaped fixture control") }
        try escaped.stop()
        try expect(!escaped.metrics.running && descriptors.allSatisfy(viLoopClosed) && viCountDescriptors() == baseline, "Escaped source retained bridge authority/fds")
        try refuses(.invalidMetadata) { _ = try escaped.nativeAttachArguments(mountPath: "/private/tmp/pat-2710/mount") }
    }
    check("PAT-2710 loopback shutdown closes an accepted incomplete client and joins") {
        let baseline = viCountDescriptors()
        try viLoop { _, source in
            let fd = try viLoopConnect(source); defer { close(fd) }
            let start = Date.timeIntervalSinceReferenceDate
            try source.stop()
            try expect(Date.timeIntervalSinceReferenceDate - start < 2 && !source.metrics.running, "Stop hung on incomplete connection")
            var byte: UInt8 = 0
            try viLoopPoll(fd, Int16(POLLIN), deadline: Date.timeIntervalSinceReferenceDate + 1)
            let count = recv(fd, &byte, 1, 0)
            try expect(count == 0 || (count < 0 && errno == ECONNRESET), "Accepted client survived shutdown")
        }
        try expect(viCountDescriptors() == baseline, "Shutdown leaked accepted descriptor")
    }
    check("PAT-2710 loopback held bytes survive source and staging-name substitution") {
        try viWorkspace { _, path, stage in
            try VerifiedImageFixtures.withLocalImage(path: path.path, pin: viPin(), workspace: stage.path) { handle in
                let identity = try viIdentity(handle.descriptor)
                try handle.withLoopbackSource { source in
                    try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("old"))
                    try Data("xyz".utf8).write(to: path)
                    try Data("xyz".utf8).write(to: stage.appendingPathComponent("artifact.dmg"))
                    let bridgeIdentity = try viIdentity(source.readerDescriptor)
                    try expect(bridgeIdentity == identity, "Bridge reopened substituted inode")
                    try expect(lseek(handle.descriptor, 2, SEEK_SET) == 2, "Cannot set retained reader offset control")
                    let response = try viLoopExchange(source, raw: viLoopRequest(source))
                    try expect(response?.body == viBytes && lseek(handle.descriptor, 0, SEEK_CUR) == 2, "Bridge served replacement or consumed shared offset")
                }
            }
        }
    }
    check("PAT-2710 loopback binary image crossing two chunk boundaries is byte exact") {
        try withWorkspace { root in
            let bytes = Data((0..<131073).map { UInt8(($0 * 37 + 11) % 256) })
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let path = root.appendingPathComponent("large.dmg"), stage = root.appendingPathComponent("stage")
            try bytes.write(to: path); try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try VerifiedImageFixtures.withLocalImage(path: path.path, pin: viPin(length: Int64(bytes.count), digest: digest), workspace: stage.path) { handle in
                try handle.withLoopbackSource { source in
                    let response = try viLoopExchange(source, raw: viLoopRequest(source))
                    try expect(response?.body == bytes && response?.headers["content-length"] == String(bytes.count), "Chunked binary fixture differs")
                    guard let body = response?.body else { throw CheckFailure(description: "Missing binary response") }
                    try expect(SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined() == digest && source.metrics.servedBytes == Int64(bytes.count), "Independent binary digest/accounting differs")
                }
            }
        }
    }
    check("PAT-2710 loopback canonical typed attach uses held URL and exact read-only default helper") {
        try viLoop { _, source in
            let mount = "/private/tmp/pat-2710/mount"
            let arguments = try source.nativeAttachArguments(mountPath: mount)
            try expect(arguments == ["attach", "-readonly", "-nobrowse", "-plist", "-mountpoint", mount, source.url], "Bridge changed canonical attach argv")
            try expect(source.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: arguments), "Typed bridge denied canonical attach")
        }
    }
    check("PAT-2710 loopback typed attach rejects executable URL flags and mount substitutions") {
        try viLoop { _, source in
            let canonical = try source.nativeAttachArguments(mountPath: "/private/tmp/pat-2710/mount")
            for executable in ["hdiutil", "/tmp/hdiutil", "/usr/bin/true"] { try expect(!source.nativeAttachAllowed(executable: executable, arguments: canonical), "Bridge accepted executable substitution") }
            for operand in ["/tmp/artifact.dmg", "/dev/fd/198", source.url + "?x=1", source.url.replacingOccurrences(of: "127.0.0.1", with: "localhost"), "http://127.0.0.1:1/wrong/artifact.dmg"] {
                var args = canonical; args[6] = operand
                try expect(!source.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: args), "Bridge accepted raw/substituted URL")
            }
            for flag in ["-kernel", "-shadow", "-noverify", "-readonly"] {
                var args = canonical; args.insert(flag, at: 1)
                try expect(!source.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: args), "Bridge accepted extra flag")
            }
            for mount in ["", "relative", "/tmp/../mount", "/tmp/./mount", "/tmp//mount", "/tmp/mount\n"] {
                try refuses(.unsafePath) { _ = try source.nativeAttachArguments(mountPath: mount) }
                var args = canonical; args[5] = mount
                try expect(!source.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: args), "Bridge accepted unsafe mount substitution")
            }
            var reordered = canonical; reordered.swapAt(1, 2)
            try expect(!source.nativeAttachAllowed(executable: "/usr/bin/hdiutil", arguments: reordered), "Bridge accepted reordered flags")
        }
    }
    check("PAT-2710 close-default spawn excludes foreign nonCLOEXEC199 without mutating parent") {
        try viWorkspace { _, path, stage in
            try expect(viLoopClosed(199), "Cannot reserve foreign sentinel slot")
            try VerifiedImageFixtures.withLocalImage(path: path.path, pin: viPin(), workspace: stage.path) { handle in
                guard dup2(handle.descriptor, 199) == 199 else { throw CheckFailure(description: "Cannot duplicate held reader to sentinel") }
                defer { close(199) }
                try expect(fcntl(199, F_SETFD, 0) == 0, "Cannot clear sentinel CLOEXEC")
                let identity = try viIdentity(199)
                let result = try viRead(handle)
                try viAssertChild(result, identity: identity)
                let output = try JSONDecoder().decode([String: String].self, from: Data(result.stdout.utf8))
                try expect(output["sentinel199Open"] == "no", "Child inherited unrelated nonCLOEXEC descriptor")
                let afterIdentity = try viIdentity(199)
                try expect(fcntl(199, F_GETFD) == 0 && afterIdentity == identity, "Spawn closed/changed caller sentinel")
            }
        }
    }
}
