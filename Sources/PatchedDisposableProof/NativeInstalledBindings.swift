import Foundation
import Darwin
import ArtifactInspection

/// Actor-owned descriptors. Construction never accepts an observation or a
/// decoded report as authority and does not use GuestRuntime.
final class NativeInstalledBindings {
    let profile: DisposableTargetProfile
    let runID: String, caseRoot: String
    let runParent: HeldDirectory
    let nativeBootstrap: HeldDirectory, childBootstrap: HeldDirectory, run: HeldDirectory, root: HeldDirectory
    let incoming: HeldDirectory, evidence: HeldDirectory, applications: HeldDirectory, transaction: HeldDirectory
    let baseline: HeldDirectory, work: HeldDirectory, target: HeldDirectory, old: HeldDirectory
    let nativeBinary: HeldFile, childBinary: HeldFile, nativeReceipt: HeldFile, childReceipt: HeldFile
    let targetBefore: ProofManifest, oldManifest: ProofManifest, binaryHash: String, nativeHash: String, receiptBytes: Data
    let stableFiles: [HeldFile], fileHashes: [String], nativeReceiptBytes: Data
    let journalBefore: Data?
    var nativeLock: ExclusiveLock?
    let commands = NativeCommands()
    init(runID: String, caseRoot: String, profile: DisposableTargetProfile = .legacy) throws {
        guard validRun(runID), DisposableScope.caseRoots.contains(caseRoot) else { throw DisposableFailure.notAuthorized }
        self.runID = runID; self.caseRoot = caseRoot; self.profile = profile
        let nativePath = profile.runParent + "/.native-bootstrap-" + runID
        guard try kernelExecutable() == nativePath + "/PatchedDisposableClientApp.app/Contents/MacOS/PatchedDisposableClientApp" else { throw DisposableFailure.notAuthorized }
        runParent = try HeldDirectory.absolute(profile.runParent)
        try requireTrustedAncestry(runParent); try runParent.owned(privateMode: true); try requirePrivateACL(runParent)
        nativeBootstrap = try runParent.child(".native-bootstrap-" + runID)
        childBootstrap = try runParent.child(".bootstrap-" + runID)
        run = try runParent.child(runID)
        for directory in [nativeBootstrap, childBootstrap, run] {
            try requireTrustedAncestry(directory); try directory.owned(privateMode: true); try requirePrivateACL(directory)
        }
        nativeBinary = try HeldFile(parent: nativeBootstrap.descend("PatchedDisposableClientApp.app/Contents/MacOS"), name: "PatchedDisposableClientApp")
        try requireTrustedAncestry(nativeBinary.parent)
        childBinary = try HeldFile(parent: childBootstrap, name: "patched-disposable-proof")
        nativeReceipt = try HeldFile(parent: nativeBootstrap, name: "native-builder-receipt.json")
        childReceipt = try HeldFile(parent: childBootstrap, name: "builder-receipt.json")
        nativeHash = try nativeBinary.stream(maximum: 268_435_456).1; binaryHash = try childBinary.stream(maximum: 268_435_456).1
        receiptBytes = try childReceipt.data(maximum: 65_536); nativeReceiptBytes = try nativeReceipt.data(maximum: 65_536)
        let child = try StrictObject.decode(receiptBytes, failure: .notAuthorized), native = try StrictObject.decode(nativeReceiptBytes, failure: .notAuthorized)
        guard Set(child.keys) == ["binarySHA256", "sourceRevision"],
              Set(native.keys) == ["nativeBinarySHA256", "childBinarySHA256", "sourceRevision"],
              native["nativeBinarySHA256"] as? String == nativeHash, native["childBinarySHA256"] as? String == binaryHash,
              native["sourceRevision"] as? String == child["sourceRevision"] as? String else { throw DisposableFailure.notAuthorized }
        try GatewayReportProjection.receipt(.init(binarySHA256: binaryHash, receiptBytes: receiptBytes,
            artifactSHA256: String(repeating: "0", count: 64), artifactLength: 1, profile: profile))
        incoming = try run.child("Incoming"); evidence = try run.child("Evidence"); root = try run.descend("Cases/" + caseRoot)
        applications = try root.child("Applications"); transaction = try root.child("Transaction")
        baseline = try root.child("Baseline"); work = try root.child("Work")
        for directory in [incoming, evidence, root, applications, transaction, baseline, work] {
            try directory.owned(privateMode: true); try requirePrivateACL(directory)
            try sameVolume(identity(run.captured).0, identity(directory.captured).0)
        }
        nativeLock = try ExclusiveLock(run, name: ".native-client.lock")
        let runLock = try ExclusiveLock(run, name: "run.lock"); defer { withExtendedLifetime(runLock) {} }
        let runMarker = try Self.marker(run, name: "run.json", runID: runID, caseRoot: nil, binaryHash: binaryHash, profile: profile)
        let caseMarker = try Self.marker(root, name: "case.json", runID: runID, caseRoot: caseRoot, binaryHash: binaryHash, profile: profile)
        target = try applications.child("Firefox.app"); old = try baseline.child("Firefox-157.0.app")
        targetBefore = try ManifestReader.read(target); oldManifest = try ManifestReader.read(old)
        let baselineRecord = try HeldFile(parent: baseline, name: "baseline.json")
        let marker = try StrictObject.decode(baselineRecord.data(maximum: 4096), failure: .journalMismatch)
        guard Set(marker.keys) == ["schemaVersion", "kind", "runID", "caseRoot", "device", "caseInode", "targetInode", "baselineInode", "manifestSHA256", "mtreeSHA256"],
              unsigned(marker["schemaVersion"]) == 1, marker["kind"] as? String == "patched-disposable-baseline-v1",
              marker["runID"] as? String == runID, marker["caseRoot"] as? String == caseRoot,
              unsigned(marker["device"]) == identity(root.captured).0, unsigned(marker["caseInode"]) == root.captured.st_ino,
              unsigned(marker["baselineInode"]) == old.captured.st_ino, marker["manifestSHA256"] as? String == oldManifest.digest,
              (marker["mtreeSHA256"] as? String).map(validDigest) == true else { throw DisposableFailure.journalMismatch }
        let mtree = try HeldFile(parent: baseline, name: "target-157.0.mtree")
        guard try mtree.stream(maximum: 8_388_608).1 == marker["mtreeSHA256"] as? String else { throw DisposableFailure.manifestMismatch }
        let image = try HeldFile(parent: incoming, name: "Firefox 157.0.1.dmg"), pin = try fixedPin("157.0.1")
        try image.verify(length: pin.byteLength, hash: pin.sha256)
        var files = [runMarker, caseMarker, baselineRecord, mtree, image], names = ["catalogue-valid.json"]
        if ["invalid-signature", "untrusted-key", "replayed-sequence", "expired-catalogue"].contains(caseRoot) { names.append("catalogue-" + caseRoot + ".json") }
        if caseRoot == "tampered-artifact" { names.append("tampered.dmg") }
        if caseRoot == "truncated-artifact" { names.append("truncated.dmg") }
        if caseRoot == "recorded-evidence" { names.append("inspection-157.0.1.json") }
        for name in names { files.append(try HeldFile(parent: incoming, name: name)) }
        if try transaction.named("journal.json") != nil {
            let journal = try HeldFile(parent: transaction, name: "journal.json")
            journalBefore = try journal.data(maximum: 65_536)
            _ = try ProofJournal.decode(journalBefore!, binding: JournalBinding(root: root, run: runID, caseRoot: caseRoot, origin: "disposableGuest", profile: profile)); files.append(journal)
        } else {
            journalBefore = nil
            guard unsigned(marker["targetInode"]) == target.captured.st_ino || caseRoot == "wrong-signer-target" else { throw DisposableFailure.manifestMismatch }
        }
        stableFiles = files; fileHashes = try files.map { try $0.stream(maximum: DisposableScope.maximumTotalBytes).1 }
    }
    static func marker(_ directory: HeldDirectory, name: String, runID: String, caseRoot: String?, binaryHash: String, profile: DisposableTargetProfile = .legacy) throws -> HeldFile {
        let file = try HeldFile(parent: directory, name: name)
        try ProfileMarker.authenticate(file.data(maximum: 4096), profile: profile, runID: runID, caseRoot: caseRoot,
            uid: getuid(), device: identity(directory.captured).0, inode: directory.captured.st_ino, binarySHA256: binaryHash)
        return file
    }
    func anchors() throws {
        _ = try GuestGuard.observe(profile: profile)
        try nativeLock?.file.confirm()
        for directory in [runParent, nativeBootstrap, childBootstrap, run, root, incoming, evidence, applications, transaction, baseline, work] {
            try directory.confirm(); try directory.owned(privateMode: true); try requirePrivateACL(directory)
        }
        try requireTrustedAncestry(nativeBinary.parent); try requireTrustedAncestry(childBootstrap); try requireTrustedAncestry(run)
        for file in [nativeBinary, childBinary, nativeReceipt, childReceipt] { try file.confirm() }
        guard try nativeBinary.stream(maximum: 268_435_456).1 == nativeHash,
              try childBinary.stream(maximum: 268_435_456).1 == binaryHash,
              try childReceipt.data(maximum: 65_536) == receiptBytes, try nativeReceipt.data(maximum: 65_536) == nativeReceiptBytes else { throw DisposableFailure.identityChanged }
    }
    func revalidate() throws {
        try anchors(); try target.confirm(); try old.confirm()
        for (index, file) in stableFiles.enumerated() {
            try file.confirm(); guard try file.stream(maximum: DisposableScope.maximumTotalBytes).1 == fileHashes[index] else { throw DisposableFailure.identityChanged }
        }
        guard try ManifestReader.read(target) == targetBefore, try ManifestReader.read(old) == oldManifest else { throw DisposableFailure.manifestMismatch }
    }
    func confirmRetainedInputsAfterChild() throws {
        for (index, file) in stableFiles.enumerated() where !(file.name == "journal.json" && file.parent.path == transaction.path) {
            try file.confirm(); guard try file.stream(maximum: DisposableScope.maximumTotalBytes).1 == fileHashes[index] else { throw DisposableFailure.identityChanged }
        }
    }
    func journal() throws -> ProofJournal? {
        guard try transaction.named("journal.json") != nil else { return nil }
        return try JournalStore.read(transaction, binding: JournalBinding(root: root, run: runID, caseRoot: caseRoot, origin: "disposableGuest", profile: profile))
    }
    func validatePreparation() throws {
        try revalidate(); commands.anchorCheck = { [unowned self] in try self.anchors() }
        _ = try commands.app(old, version: "157.0")
        if let record = try journal() { try verifyJournalTrees(record, action: nil) }
        else { _ = try commands.app(target, version: "157.0"); guard targetBefore == oldManifest else { throw DisposableFailure.manifestMismatch } }
    }
    func command(_ action: DisposableAction) throws -> NativeInstalledChildCommand {
        guard ![.initializeRun, .prepareRoot, .report].contains(action) else { throw DisposableFailure.notAuthorized }
        var args = ["--target-id", profile.targetID, "--run-id", runID, "--case-root", caseRoot, "--case", action.rawValue, "--explicit-trigger"]
        let pauses: [DisposableAction: DisposablePause] = [.stagingFailure: .stageCopy, .wrongSignerStaged: .beforeSwap, .interruptedSwap: .beforeCommit]
        if let pause = pauses[action] { args += ["--pause", pause.rawValue] }
        if action == .recordedEvidence { args += ["--recorded-evidence", incoming.path + "/inspection-157.0.1.json"] }
        _ = try DisposableArguments.parse(args)
        let record = try journal()
        switch action {
        case .restoreOld: guard record?.state == .committed else { throw DisposableFailure.invalidState }
        case .recoverAfterStaging: guard record?.state == .staging else { throw DisposableFailure.invalidState }
        case .recoverAfterSwap: guard record?.state == .swapped else { throw DisposableFailure.invalidState }
        default: guard record == nil else { throw DisposableFailure.existingRoot }
        }
        return .init(executable: childBootstrap.path + "/patched-disposable-proof", arguments: args)
    }
    func write(_ prefix: String, _ object: [String: Any]) throws -> String {
        try anchors(); let name = prefix + "-" + UUID().uuidString + ".json"
        try PhysicalIO.write(evidence, name, data: encodeJSON(object)); return evidence.path + "/" + name
    }
    func recordRefusal(_ error: Error) throws -> String {
        let reopened = try applications.child("Firefox.app"), after = try ManifestReader.read(reopened)
        return try write("native-preflight-refusal", ["runID": runID, "caseRoot": caseRoot,
            "reason": (error as? DisposableFailure)?.rawValue ?? "nativeOperationFailed", "targetPath": target.path,
            "beforeManifest": targetBefore.digest, "afterManifest": after.digest,
            "beforeTargetInode": target.captured.st_ino, "afterTargetInode": reopened.captured.st_ino,
            "unchangedTarget": after == targetBefore && sameIdentity(target.captured, reopened.captured),
            "installedFirefoxProof": false, "productionTrust": false,
            "nativeBinarySHA256": nativeHash, "childBinarySHA256": binaryHash,
            "nativeReceiptSHA256": digest(nativeReceiptBytes), "nativeReceipt": nativeReceiptBytes.base64EncodedString(),
            "childReceiptSHA256": digest(receiptBytes), "childReceipt": receiptBytes.base64EncodedString(),
            "freshOSValidation": false,
            "nativeCommands": try JSONSerialization.jsonObject(with: JSONEncoder().encode(commands.results))])
    }
    func verifyJournalTrees(_ journal: ProofJournal, action: DisposableAction?) throws {
        let current = try applications.child("Firefox.app"), manifest = try ManifestReader.read(current)
        guard journal.oldDigest == oldManifest.digest, journal.object["artifactSHA256"] as? String == (try fixedPin("157.0.1")).sha256 else { throw DisposableFailure.journalMismatch }
        if current.captured.st_ino == journal.oldInode && manifest.digest == journal.oldDigest {
            _ = try commands.app(current, version: "157.0"); guard journal.state != .committed else { throw DisposableFailure.ambiguousState }
        } else {
            guard current.captured.st_ino == journal.newInode, manifest.digest == journal.newDigest,
                  [.swapped, .committed, .swapIntended].contains(journal.state) else { throw DisposableFailure.ambiguousState }
            _ = try commands.app(current, version: "157.0.1")
            let retained = try transaction.descend("Exchange/Firefox.app")
            guard retained.captured.st_ino == journal.oldInode, try ManifestReader.read(retained).digest == journal.oldDigest else { throw DisposableFailure.ambiguousState }
            _ = try commands.app(retained, version: "157.0")
        }
        if action == .update { guard journal.state == .committed else { throw DisposableFailure.invalidState } }
        if [.recoverAfterStaging, .recoverAfterSwap, .restoreOld].contains(action) {
            guard journal.state == .rolledBack, current.captured.st_ino == journal.oldInode else { throw DisposableFailure.invalidState }
        }
    }
    func execute(_ action: DisposableAction) throws -> NativeInstalledActionOutcome {
        let command = try command(action)
        try revalidate()
        let invocationID = UUID(), beforeEvidence = Set(try evidence.names(maximum: 100_000))
        let raw = try InstalledChildRunner.capture(.init(executable: command.executable, arguments: command.arguments, origin: .nativeScope, profile: profile), outputLimit: 8_388_608) { pid in
            // Observe only the exact Process-owned PID, never enumerate or signal.
            var info = proc_bsdinfo(), path = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                  info.pbi_pid == UInt32(pid), info.pbi_uid == self.profile.guestUID, info.pbi_ruid == self.profile.guestUID,
                  info.pbi_start_tvsec > 0 else { throw DisposableFailure.notAuthorized }
            let count = proc_pidpath(pid, &path, UInt32(path.count))
            guard count > 0, String(decoding: path.prefix(Int(count)), as: UTF8.self) == command.executable else { throw DisposableFailure.notAuthorized }
            _ = try self.write("native-child-start", ["invocationID": invocationID.uuidString, "pid": pid,
                "executable": command.executable, "arguments": command.arguments, "binarySHA256": self.binaryHash,
                "nativeBinarySHA256": self.nativeHash, "runID": self.runID, "caseRoot": self.caseRoot, "action": action.rawValue,
                "observedAt": ISO8601DateFormatter().string(from: Date()), "kernelStartSeconds": info.pbi_start_tvsec,
                "kernelStartMicroseconds": info.pbi_start_tvusec, "uid": info.pbi_uid, "realUID": info.pbi_ruid,
                "kernelExecutable": command.executable, "targetInode": self.target.captured.st_ino,
                "beforeManifestSHA256": self.targetBefore.digest,
                "transactionID": (try self.journal()?.object["transactionID"] as? String) ?? "not-yet-created"])
        }
        let lock = try ExclusiveLock(run, name: "run.lock"); defer { withExtendedLifetime(lock) {} }
        try anchors()
        let fresh = Set(try evidence.names(maximum: 100_000)).subtracting(beforeEvidence)
        let rawPath = try write("native-child-exit", ["invocationID": invocationID.uuidString, "runID": runID,
            "caseRoot": caseRoot, "action": action.rawValue, "terminationStatus": raw.exitCode,
            "terminationReason": raw.exitedNormally ? "exit" : "uncaughtSignal", "streamsComplete": raw.streamsComplete,
            "evidenceRecorded": raw.evidenceRecorded, "outputExceeded": raw.outputExceeded,
            "evidenceFailure": raw.evidenceFailure ?? "none",
            "stdout": raw.stdout.base64EncodedString(), "stderr": raw.stderr.base64EncodedString()])
        guard raw.childExited, raw.streamsComplete else { throw DisposableFailure.commandFailed }
        guard raw.evidenceRecorded else { throw DisposableFailure(rawValue: raw.evidenceFailure ?? "") ?? .persistenceFailed }
        guard !raw.outputExceeded else { throw DisposableFailure.outputLimit }
        try confirmRetainedInputsAfterChild()
        if !raw.exitedNormally {
            if let journal = try journal() { try verifyJournalTrees(journal, action: nil) }
            return .init(kind: .needsRecovery, reason: "childSignalled:\(raw.exitCode)", evidencePath: rawPath,
                         transactionID: try journal()?.object["transactionID"] as? String)
        }
        if raw.exitCode != 0 { return try refusal(action, raw: raw, fresh: fresh, invocationID: invocationID) }
        guard [.update, .recoverAfterStaging, .recoverAfterSwap, .restoreOld].contains(action) else { throw DisposableFailure.caseConditionMissing }
        let names = fresh.filter { $0.hasPrefix("report-" + caseRoot + "-" + action.rawValue + "-") && $0.hasSuffix(".json") }
        guard names.count == 1, let name = names.first else { throw DisposableFailure.notAuthorized }
        let durable = try HeldFile(parent: evidence, name: name), bytes = try durable.data(maximum: 16_777_216)
        try raw.requireAccepted(expectedStdout: bytes + Data([10]))
        guard let journal = try journal() else { throw DisposableFailure.journalMissing }
        try verifyJournalTrees(journal, action: action)
        let current = try applications.child("Firefox.app"), manifest = try ManifestReader.read(current)
        let report = try StrictObject.decode(bytes, maximum: 16_777_216, failure: .notAuthorized), pin = try fixedPin("157.0.1")
        // The pure projection is shared, but every fact supplied here originates
        // from this issuer's own held descriptors/native readback, never SPI input.
        try GatewayReportProjection.compare(report, action: action, runID: runID, caseRoot: caseRoot,
            expected: .init(binarySHA256: binaryHash, receiptBytes: receiptBytes, artifactSHA256: pin.sha256, artifactLength: pin.byteLength, profile: profile),
            readback: .init(targetPath: current.path, version: action == .update ? "157.0.1" : "157.0",
                transactionID: journal.object["transactionID"] as! String, manifestSHA256: manifest.digest,
                retainedOldSHA256: oldManifest.digest, fresh: true))
        try validateNativeReport(report, action: action)
        _ = try commands.app(old, version: "157.0")
        guard try ManifestReader.read(old) == oldManifest, !(try mountedPaths()).contains(where: { $0.hasPrefix(run.path + "/") }) else { throw DisposableFailure.cleanupFailed }
        try durable.confirm(); try anchors()
        let path = try write("native-verified-completion", ["invocationID": invocationID.uuidString, "action": action.rawValue,
            "runID": runID, "caseRoot": caseRoot, "targetPath": current.path, "targetInode": current.captured.st_ino,
            "manifestSHA256": manifest.digest, "journal": journal.object, "durableReport": evidence.path + "/" + name,
            "durableReportSHA256": digest(bytes), "freshOSValidation": true, "installedFirefoxProof": action == .update,
            "productionTrust": false, "nativeReadback": try JSONSerialization.jsonObject(with: JSONEncoder().encode(commands.results))])
        return .init(kind: action == .update ? .verifiedUpdate : .verifiedRestored, reason: "verified",
                     evidencePath: path, transactionID: journal.object["transactionID"] as? String)
    }
    func validateNativeReport(_ report: [String: Any], action: DisposableAction) throws {
        guard let observations = report["appObservations"] as? [[String: Any]], observations.count >= 3 else { throw DisposableFailure.notAuthorized }
        // Child observations include historical staged/unmounted paths. Bind
        // those records below, but independently read only current held trees.
        for app in [try applications.child("Firefox.app"), old] {
            let executable = try HeldFile(parent: app.child("Contents").child("MacOS"), name: "firefox")
            try app.confirm(); try executable.confirm()
            let actual: [String]
            do { actual = try MachOArchitectures.inspect(fileDescriptor: executable.fd) }
            catch { throw DisposableFailure.wrongArchitecture }
            try executable.confirm(); try app.confirm()
            guard actual == ["arm64", "x86_64"] else { throw DisposableFailure.wrongArchitecture }
        }
        for observation in observations {
            guard observation["bundleID"] as? String == "org.mozilla.firefox", observation["teamID"] as? String == "43AQ936H96",
                  ["157.0", "157.0.1"].contains(observation["version"] as? String ?? ""), let path = observation["path"] as? String,
                  path.hasPrefix(root.path + "/"),
                  Set(observation.keys) == GatewayReportProjection.observationKeys.union(["signatureObservation"]),
                  let checks = observation["commands"] as? [[String: Any]], checks.count == 1 else { throw DisposableFailure.notAuthorized }
            try GatewayReportProjection.signature(observation["signatureObservation"], path: path,
                                                  version: observation["version"] as? String ?? "")
            let expected: [(String, [String])] = [("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", path])]
            guard let architecture = observation["architectureObservation"] as? [String: Any],
                  Set(architecture.keys) == ["executablePath", "architectures"],
                  architecture["executablePath"] as? String == path + "/Contents/MacOS/firefox",
                  architecture["architectures"] as? [String] == ["arm64", "x86_64"] else { throw DisposableFailure.notAuthorized }
            for (index, check) in checks.enumerated() {
                guard check["executable"] as? String == expected[index].0, check["arguments"] as? [String] == expected[index].1,
                      unsigned(check["exitCode"]) == 0, GatewayReportProjection.flag(check["timedOut"], false),
                      GatewayReportProjection.flag(check["outputExceeded"], false) else { throw DisposableFailure.notAuthorized }
            }
        }
        let wanted = action == .update ? ["prepared", "staging", "staged", "swapIntended", "swapped", "committed"] :
            (action == .restoreOld ? ["swapIntended", "rolledBack"] : ["rolledBack"])
        guard report["journalStatesReached"] as? [String] == wanted else { throw DisposableFailure.invalidState }
    }
    func refusal(_ action: DisposableAction, raw: SyntheticChildCompletion, fresh: Set<String>, invocationID: UUID) throws -> NativeInstalledActionOutcome {
        let wanted: String
        switch action {
        case .tamperedArtifact: wanted = "digestMismatch"
        case .truncatedArtifact: wanted = "lengthMismatch"
        case .recordedEvidence: wanted = "recordedEvidenceRefused"
        case .wrongSignerTarget, .wrongSignerStaged: wanted = "wrongTeam"
        case .invalidCatalogue: wanted = caseRoot == "untrusted-key" ? "untrustedKey" : "invalidSignature"
        case .replayedCatalogue: wanted = caseRoot == "expired-catalogue" ? "expired" : "replay"
        case .openApp: wanted = "appRunning"
        default: throw DisposableFailure.caseConditionMissing
        }
        guard raw.exitCode == 1, raw.stdout == Data(("{\"refusal\":\"" + wanted + "\",\"installedFirefoxProof\":false}\n").utf8) else { throw DisposableFailure.notAuthorized }
        let names = fresh.filter { $0.hasPrefix("refusal-") && $0.hasSuffix(".json") }
        guard names.count == 1, let name = names.first else { throw DisposableFailure.notAuthorized }
        let file = try HeldFile(parent: evidence, name: name), bytes = try file.data(maximum: 65_536)
        let record = try StrictObject.decode(bytes, failure: .notAuthorized)
        try target.confirm(); try old.confirm()
        let states = action == .wrongSignerStaged ? ["prepared", "staging", "staged"] : []
        guard Set(record.keys) == ["action", "caseRoot", "reason", "journalStatesReached", "completed", "installedFirefoxProof"],
              record["action"] as? String == action.rawValue, record["caseRoot"] as? String == caseRoot,
              record["reason"] as? String == wanted, record["journalStatesReached"] as? [String] == states,
              GatewayReportProjection.flag(record["completed"], false), GatewayReportProjection.flag(record["installedFirefoxProof"], false),
              try ManifestReader.read(applications.child("Firefox.app")) == targetBefore,
              try ManifestReader.read(old) == oldManifest else { throw DisposableFailure.notAuthorized }
        if action == .wrongSignerStaged {
            guard let record = try journal(), record.state == .staged, record.oldInode == target.captured.st_ino,
                  record.oldDigest == targetBefore.digest else { throw DisposableFailure.journalMismatch }
        } else { guard try journal() == nil else { throw DisposableFailure.invalidState } }
        guard !(try mountedPaths()).contains(where: { $0.hasPrefix(run.path + "/") }) else { throw DisposableFailure.cleanupFailed }
        try file.confirm()
        let path = try write("native-verified-refusal", ["invocationID": invocationID.uuidString, "runID": runID, "caseRoot": caseRoot,
            "action": action.rawValue, "reason": wanted, "targetPath": target.path, "targetInode": target.captured.st_ino,
            "unchangedManifestSHA256": targetBefore.digest, "durableRefusal": evidence.path + "/" + name,
            "durableRefusalSHA256": digest(bytes), "installedFirefoxProof": false, "productionTrust": false])
        return .init(kind: .verifiedRefusal, reason: wanted, evidencePath: path, transactionID: try journal()?.object["transactionID"] as? String)
    }
}
