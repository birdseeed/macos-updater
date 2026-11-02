import Foundation
import Darwin
import ArtifactInspection

enum GuestRuntime {
    static func execute(_ request: DisposableRequest) throws -> DisposableReport {
        let guest = try GuestGuard.observe(profile: request.profile) // First operation. No output or filesystem writes precede this.
        guard request.explicitTrigger, request.targetID == request.profile.targetID, validRun(request.runID),
              request.runPath == request.profile.runParent + "/" + request.runID else { throw DisposableFailure.notAuthorized }
        let requiredPauses: [DisposableAction: DisposablePause] = [
            .stagingFailure: .stageCopy, .wrongSignerStaged: .beforeSwap, .interruptedSwap: .beforeCommit]
        guard request.pause == requiredPauses[request.action] else { throw DisposableFailure.invalidArguments }
        let context = try RuntimeContext(request, guest: guest)
        return try context.execute()
    }
}
final class RuntimeContext {
    let profile: DisposableTargetProfile
    let request: DisposableRequest, guest: GuestObservation
    let run: HeldDirectory, incoming: HeldDirectory, evidence: HeldDirectory, cases: HeldDirectory
    let binary: HeldFile, receipt: HeldFile, binarySHA: String, receiptBytes: Data
    let runMarker: HeldFile
    let commands = NativeCommands()
    var caseDirectory: HeldDirectory?, caseMarker: HeldFile?, transaction: HeldDirectory?, baseline: HeldDirectory?, work: HeldDirectory?
    var applications: HeldDirectory?
    var observations: [NativeAppObservation] = [], manifests: [String: ProofManifest] = [:]
    var spaces: [[String: Int64]] = [], reached: [String] = [], artefacts: [[String: String]] = []
    var mtreeFiles: [String: String] = [:]
    var containerResults: [CommandResult] = [], catalogueResults: [[String: String]] = []
    var state = "prepared", recovery = "none", installedProof = false
    var runLock: ExclusiveLock?
    init(_ request: DisposableRequest, guest: GuestObservation) throws {
        self.request = request; self.guest = guest; profile = request.profile
        let executable = try kernelExecutable(), names = try components(executable, absolute: true)
        let bootstrapPath = request.profile.runParent + "/.bootstrap-" + request.runID
        guard executable == bootstrapPath + "/patched-disposable-proof", names.last == "patched-disposable-proof" else { throw DisposableFailure.notAuthorized }
        let bootstrap = try HeldDirectory.absolute(bootstrapPath)
        try requireTrustedAncestry(bootstrap); try bootstrap.owned(privateMode: true); try requirePrivateACL(bootstrap)
        binary = try HeldFile(parent: bootstrap, name: "patched-disposable-proof")
        binarySHA = try binary.stream(maximum: 268_435_456).1
        receipt = try HeldFile(parent: bootstrap, name: "builder-receipt.json")
        receiptBytes = try receipt.data(maximum: 65_536)
        let provenance = try StrictObject.decode(receiptBytes, failure: .notAuthorized)
        guard provenance["binarySHA256"] as? String == binarySHA,
              let revision = provenance["sourceRevision"] as? String, revision.utf8.count == 40,
              revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw DisposableFailure.notAuthorized }
        let parent = try HeldDirectory.absolute(request.profile.runParent)
        try requireTrustedAncestry(parent); try parent.owned(privateMode: true); try requirePrivateACL(parent)
        if request.action == .initializeRun {
            run = try parent.mkdir(request.runID); try requirePrivateACL(run)
            try Self.seal(run, name: "run.json", runID: request.runID, caseRoot: nil, binarySHA: binarySHA, profile: request.profile)
            incoming = try run.mkdir("Incoming"); evidence = try run.mkdir("Evidence"); cases = try run.mkdir("Cases")
            for directory in [incoming, evidence, cases] {
                try sameVolume(identity(run.captured).0, identity(try directory.status()).0)
                try requirePrivateACL(directory)
            }
        } else {
            run = try parent.child(request.runID); try run.owned(privateMode: true); try requirePrivateACL(run)
            incoming = try run.child("Incoming"); evidence = try run.child("Evidence"); cases = try run.child("Cases")
            for directory in [incoming, evidence, cases] {
                try sameVolume(identity(run.captured).0, identity(try directory.status()).0)
                try directory.owned(privateMode: true); try requirePrivateACL(directory)
            }
        }
        runMarker = try Self.authenticate(run, name: "run.json", runID: request.runID, caseRoot: nil, binarySHA: binarySHA, profile: request.profile)
        runLock = try ExclusiveLock(run, name: "run.lock")
        commands.anchorCheck = { [unowned self] in try self.confirm() }
        commands.event = { [unowned self] observation in
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try PhysicalIO.write(self.evidence, "command-" + UUID().uuidString + ".json", data: encoder.encode(observation))
        }
    }
    static func seal(_ root: HeldDirectory, name: String, runID: String, caseRoot: String?, binarySHA: String, profile: DisposableTargetProfile = .legacy) throws {
        let object: [String: Any] = ["schemaVersion": 1, "kind": caseRoot == nil ? "patched-disposable-run-v1" : "patched-disposable-case-v1",
            "guestUUIDSHA256": profile.guestUUIDSHA256, "uid": getuid(), "runID": runID,
            "caseRoot": caseRoot ?? "", "device": identity(root.captured).0, "inode": root.captured.st_ino, "binarySHA256": binarySHA]
        try PhysicalIO.write(root, name, data: encodeJSON(object))
    }
    static func authenticate(_ root: HeldDirectory, name: String, runID: String, caseRoot: String?, binarySHA: String, profile: DisposableTargetProfile = .legacy) throws -> HeldFile {
        let file = try HeldFile(parent: root, name: name)
        try ProfileMarker.authenticate(file.data(maximum: 4096), profile: profile, runID: runID, caseRoot: caseRoot,
            uid: getuid(), device: identity(root.captured).0, inode: root.captured.st_ino, binarySHA256: binarySHA)
        return file
    }
    func confirm() throws {
        _ = try GuestGuard.observe(profile: profile)
        try binary.confirm(); try receipt.confirm(); try run.confirm(); try runMarker.confirm()
        try incoming.confirm(); try evidence.confirm(); try cases.confirm()
        try caseDirectory?.confirm(); try caseMarker?.confirm(); try transaction?.confirm(); try baseline?.confirm(); try work?.confirm()
        try applications?.confirm()
    }
    func writeEvidence(_ name: String, _ object: Any) throws {
        try confirm(); try PhysicalIO.write(evidence, name + "-" + UUID().uuidString + ".json", data: encodeJSON(object))
    }
    func requireAppClosed(_ held: HeldDirectory) throws {
        try observeAppClosed(held) { failure in
            try self.confirm()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let name = "process-observation-" + (self.request.caseRoot ?? "run") + "-" + self.request.action.rawValue
            try PhysicalIO.write(self.evidence, name + "-" + UUID().uuidString + ".json", data: encoder.encode(failure))
        }
    }
    func space(_ count: Int64) throws {
        do { let value = try requireSpace(run, nextBytes: count); spaces.append(value); try writeEvidence("space", value) }
        catch { try? writeEvidence("space-refusal", ["reason": String(describing: error)]); throw error }
    }
    func observe(_ directory: HeldDirectory, version: String, owner: uid_t? = getuid()) throws -> NativeAppObservation {
        let observation = try commands.app(directory, version: version, owner: owner)
        observations.append(observation); return observation
    }
    func openCase(fresh: Bool) throws {
        guard let name = request.caseRoot, DisposableScope.caseRoots.contains(name) else { throw DisposableFailure.unknownCase }
        let root: HeldDirectory
        if fresh {
            root = try cases.mkdir(name)
            try sameVolume(identity(run.captured).0, identity(try root.status()).0)
            try requirePrivateACL(root)
            try Self.seal(root, name: "case.json", runID: request.runID, caseRoot: name, binarySHA: binarySHA, profile: profile)
            for child in ["Applications", "Transaction", "Baseline", "Work"] {
                let directory = try root.mkdir(child)
                try sameVolume(identity(run.captured).0, identity(try directory.status()).0)
                try requirePrivateACL(directory)
            }
        } else { root = try cases.child(name) }
        try sameVolume(identity(run.captured).0, identity(try root.status()).0)
        try root.owned(privateMode: true); try requirePrivateACL(root)
        caseDirectory = root
        caseMarker = try Self.authenticate(root, name: "case.json", runID: request.runID, caseRoot: name, binarySHA: binarySHA, profile: profile)
        applications = try root.child("Applications"); transaction = try root.child("Transaction")
        baseline = try root.child("Baseline"); work = try root.child("Work")
        for held in [applications!, transaction!, baseline!, work!] {
            try sameVolume(identity(run.captured).0, identity(try held.status()).0)
            try held.owned(privateMode: true); try requirePrivateACL(held)
        }
        try reconcileMounts()
    }
    func execute() throws -> DisposableReport {
        do {
            if request.action == .initializeRun {
                try space(0); state = "initialized"; return try finish()
            }
            try openCase(fresh: request.action == .prepareRoot)
            switch request.action {
            case .prepareRoot: try prepare()
            case .recoverAfterStaging, .recoverAfterSwap: try recover()
            case .restoreOld: try restore()
            case .report:
                if try transaction!.named("journal.json") != nil { state = try JournalStore.read(transaction!, binding: binding()).state.rawValue }
                else { state = "prepared" }
            default: try perform()
            }
            return try finish()
        } catch {
            try? writeEvidence("refusal", ["action": request.action.rawValue, "caseRoot": request.caseRoot ?? "",
                "reason": (error as? DisposableFailure)?.rawValue ?? "operationFailed", "journalStatesReached": reached,
                "completed": false, "installedFirefoxProof": false])
            throw error
        }
    }
    func binding() throws -> JournalBinding {
        try JournalBinding(root: caseDirectory!, run: request.runID, caseRoot: request.caseRoot!, origin: "disposableGuest", profile: profile)
    }
    func finish() throws -> DisposableReport {
        try confirm()
        let report = DisposableReport(action: request.action.rawValue, runID: request.runID, caseRoot: request.caseRoot,
            state: state, recoveryAction: recovery, testCatalogueTrust: true, productionTrust: false,
            installedFirefoxProof: installedProof, freshOSValidation: !observations.isEmpty, binarySHA256: binarySHA,
            sourceRevisionObservedByHarness: false, builderProvenanceReceiptSHA256: digest(receiptBytes), builderProvenanceReceipt: receiptBytes,
            manifestCoverage: ["type", "mode", "size", "link", "sha256digest"],
            limitations: ["Test catalogue trust only; no production key.", "Scoped case-root Firefox proof only; no product readiness claim.",
                "Same-user consistent rewriting before capture is not prevented.", "Flush success is not hardware or power-loss proof.",
                "Manifest omits ACLs, xattrs, resource forks and quarantine.", "Parent builder receipt is a claim, not executable source attestation.",
                "Existing profiles are not inspected; unrelated root metadata cannot prove byte preservation.", "Harness does not launch or quit applications."],
            guest: guest, nativeCommands: commands.results, appObservations: observations, bundleManifests: manifests,
            imageObservations: artefacts, journalStatesReached: reached, independentMtreeFiles: mtreeFiles,
            spaceObservations: spaces, targetPath: request.targetPath,
            exchangePath: caseDirectory.map { $0.path + "/Transaction/Exchange/Firefox.app" },
            harnessSigningObservation: try commands.run("/usr/bin/codesign", ["-dv", "--verbose=4", binary.parent.path + "/" + binary.name]),
            targetID: profile.targetID, trigger: "explicitUserAction",
            transactionID: try transaction.flatMap { storage in
                if try storage.named("journal.json") == nil { return nil }
                return try JournalStore.read(storage, binding: binding()).object["transactionID"] as? String
            },
            containerObservations: containerResults, catalogueObservations: catalogueResults,
            recordedInspectionSHA256: try incoming.named("inspection-157.0.1.json") == nil ? nil :
                digest(PhysicalIO.read(incoming, "inspection-157.0.1.json", maximum: 1_048_576)),
            ownedMountsAbsent: try !mountedPaths().contains { $0.hasPrefix(run.path + "/") },
            globalProductReadiness: false)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try PhysicalIO.write(evidence, "report-" + (request.caseRoot ?? "run") + "-" + request.action.rawValue + "-" + UUID().uuidString + ".json",
                             data: encoder.encode(report))
        return report
    }
}
