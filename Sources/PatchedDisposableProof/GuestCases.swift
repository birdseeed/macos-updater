import Foundation
import Darwin
import ArtifactInspection
import PatchedCore

extension RuntimeContext {
    func reconcileMounts() throws {
        let work = self.work!
        for markerName in try work.names(maximum: 1000) where markerName.hasPrefix("Mount-") && markerName.hasSuffix(".json") {
            let marker = try StrictObject.decode(PhysicalIO.read(work, markerName, maximum: 4096), failure: .cleanupFailed)
            let mountName = String(markerName.dropLast(5)), path = work.path + "/" + mountName
            guard Set(marker.keys) == ["schemaVersion", "kind", "guestUUIDSHA256", "path", "image", "parentDevice", "parentInode", "mountInode"],
                  unsigned(marker["schemaVersion"]) == 1, marker["kind"] as? String == "patched-owned-mount-v1",
                  marker["guestUUIDSHA256"] as? String == profile.guestUUIDSHA256,
                  marker["path"] as? String == path, unsigned(marker["parentDevice"]) == identity(work.captured).0,
                  unsigned(marker["parentInode"]) == work.captured.st_ino,
                  let inode = unsigned(marker["mountInode"]), let image = marker["image"] as? String,
                  image.hasPrefix(work.path + "/held-"), !String(image.dropFirst(work.path.count + 1)).contains("/") else { throw DisposableFailure.cleanupFailed }
            if try mountedPaths().contains(path) {
                let raw = try commands.success("/usr/bin/hdiutil", ["info", "-plist"], output: 1_048_576, failure: .cleanupFailed)
                guard let info = try PropertyListSerialization.propertyList(from: Data(raw.stdout.utf8), options: [], format: nil) as? [String: Any],
                      let images = info["images"] as? [[String: Any]],
                      images.filter({ row in row["image-path"] as? String == image &&
                          ((row["system-entities"] as? [[String: Any]]) ?? []).contains { $0["mount-point"] as? String == path } }).count == 1 else {
                    throw DisposableFailure.cleanupFailed
                }
                let mounted = try work.child(mountName); var status = statfs()
                guard fstatfs(mounted.fd, &status) == 0, status.f_flags & UInt32(MNT_RDONLY) != 0 else { mounted.closeDescriptor(); throw DisposableFailure.cleanupFailed }
                mounted.closeDescriptor()
                _ = try commands.success("/usr/bin/hdiutil", ["detach", path], failure: .cleanupFailed)
                guard !(try mountedPaths()).contains(path) else { throw DisposableFailure.cleanupFailed }
            }
            let empty = try work.child(mountName)
            guard empty.captured.st_ino == inode, try empty.names(maximum: 1).isEmpty else { throw DisposableFailure.cleanupFailed }
        }
    }
    func image(_ version: String, input: String) throws -> OwnedImage {
        let pin = try fixedPin(version)
        let held = try OwnedImage(incoming: incoming, input: input, work: work!, version: version, profile: profile, space: { try self.space(pin.byteLength) })
        artefacts.append(["version": version, "sha256": pin.sha256, "byteLength": String(pin.byteLength), "heldPath": held.path])
        return held
    }
    func containerChecks(_ image: OwnedImage) throws {
        try image.confirm()
        containerResults.append(try commands.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", image.path]))
        containerResults.append(try commands.run("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", image.path]))
        try image.confirm()
        // Their non-zero exits remain raw failures in nativeCommands. No overall container pass exists.
    }
    func ditto(_ source: HeldDirectory, parent: HeldDirectory, name: String, expected: ProofManifest) throws -> HeldDirectory {
        try space(expected.totalBytes)
        return try nativeDittoBundle(source, parent: parent, name: name, expected: expected, commands: commands)
    }
    func mtreeValidate() throws {
        let probe = try work!.mkdir("MtreeProbe")
        try PhysicalIO.write(probe, "probe", data: Data("first bytes\n".utf8))
        let captured = try commands.success("/usr/sbin/mtree", ["-c", "-n", "-k", "type,mode,size,link,sha256digest", "-p", probe.path], output: 1_048_576)
        guard captured.stdout.contains("sha256digest") else { throw DisposableFailure.manifestMismatch }
        try PhysicalIO.write(work!, "mtree-probe.txt", data: Data(captured.stdout.utf8))
        _ = try commands.success("/usr/sbin/mtree", ["-f", work!.path + "/mtree-probe.txt", "-p", probe.path], output: 1_048_576)
        let file = try HeldFile(parent: probe, name: "probe", writable: true)
        let changed = Data("other bytes\n".utf8)
        guard ftruncate(file.fd, 0) == 0 else { throw DisposableFailure.persistenceFailed }
        try PhysicalIO.writeAll(file.fd, changed); try PhysicalIO.syncFile(file.fd); try probe.syncDirectory()
        let mismatch = try commands.run("/usr/sbin/mtree", ["-f", work!.path + "/mtree-probe.txt", "-p", probe.path], output: 1_048_576)
        guard mismatch.exitCode == 2, !(mismatch.stdout + mismatch.stderr).isEmpty else { throw DisposableFailure.manifestMismatch }
    }
    func mtreeCapture(_ app: HeldDirectory, name: String) throws -> String {
        try app.confirm()
        let captured = try commands.success("/usr/sbin/mtree", ["-c", "-n", "-k", "type,mode,size,link,sha256digest", "-p", app.path], output: 1_048_576)
        try app.confirm()
        let data = Data(captured.stdout.utf8); try PhysicalIO.write(baseline!, name, data: data)
        mtreeFiles[baseline!.path + "/" + name] = digest(data)
        return digest(data)
    }
    func mtreeVerify(_ app: HeldDirectory, name: String, hash: String) throws {
        let file = try HeldFile(parent: baseline!, name: name), data = try file.data(maximum: 8_388_608)
        guard digest(data) == hash else { throw DisposableFailure.manifestMismatch }
        try app.confirm()
        _ = try commands.success("/usr/sbin/mtree", ["-f", baseline!.path + "/" + name, "-p", app.path], output: 1_048_576, failure: .manifestMismatch)
        try app.confirm(); try file.confirm(); mtreeFiles[baseline!.path + "/" + name] = hash
    }
    func prepare() throws {
        let image = try image("157.0", input: "Firefox 157.0.dmg")
        try containerChecks(image); try mtreeValidate()
        try image.withMount(commands: commands) { mount in
            guard try mount.names(maximum: 100).filter({ $0.hasSuffix(".app") }) == ["Firefox.app"] else { throw DisposableFailure.wrongBundle }
            let source = try mount.child("Firefox.app"), mounted = try observe(source, version: "157.0", owner: nil)
            let target = try ditto(source, parent: applications!, name: "Firefox.app", expected: mounted.manifest)
            let targetObserved = try observe(target, version: "157.0")
            let copy = try ditto(source, parent: baseline!, name: "Firefox-157.0.app", expected: mounted.manifest)
            let baselineObserved = try observe(copy, version: "157.0")
            guard targetObserved.manifest == baselineObserved.manifest else { throw DisposableFailure.manifestMismatch }
            let mtree = try mtreeCapture(target, name: "target-157.0.mtree")
            try mtreeVerify(copy, name: "target-157.0.mtree", hash: mtree)
            try mtreeVerify(target, name: "target-157.0.mtree", hash: mtree)
            let marker: [String: Any] = ["schemaVersion": 1, "kind": "patched-disposable-baseline-v1",
                "runID": request.runID, "caseRoot": request.caseRoot!, "device": identity(caseDirectory!.captured).0,
                "caseInode": caseDirectory!.captured.st_ino, "targetInode": target.captured.st_ino,
                "baselineInode": copy.captured.st_ino, "manifestSHA256": targetObserved.manifest.digest, "mtreeSHA256": mtree]
            try PhysicalIO.write(baseline!, "baseline.json", data: encodeJSON(marker))
            manifests["preparedTarget"] = targetObserved.manifest; manifests["baseline"] = baselineObserved.manifest
        }
        guard !(try mountedPaths()).contains(where: { $0.hasPrefix(work!.path + "/") }) else { throw DisposableFailure.cleanupFailed }
        state = "prepared"
    }
    func baselineRecord() throws -> [String: Any] {
        let object = try StrictObject.decode(PhysicalIO.read(baseline!, "baseline.json", maximum: 4096), failure: .journalMismatch)
        guard Set(object.keys) == ["schemaVersion", "kind", "runID", "caseRoot", "device", "caseInode", "targetInode", "baselineInode", "manifestSHA256", "mtreeSHA256"],
              unsigned(object["schemaVersion"]) == 1, object["kind"] as? String == "patched-disposable-baseline-v1",
              object["runID"] as? String == request.runID, object["caseRoot"] as? String == request.caseRoot,
              unsigned(object["device"]) == identity(caseDirectory!.captured).0, unsigned(object["caseInode"]) == caseDirectory!.captured.st_ino,
              unsigned(object["targetInode"]) != nil, unsigned(object["baselineInode"]) != nil,
              (object["manifestSHA256"] as? String).map(validDigest) == true, (object["mtreeSHA256"] as? String).map(validDigest) == true else {
            throw DisposableFailure.journalMismatch
        }
        return object
    }
    func verifyBaseline(includeTarget: Bool) throws -> ProofManifest {
        let marker = try baselineRecord(), copy = try baseline!.child("Firefox-157.0.app")
        let checked = try observe(copy, version: "157.0")
        guard unsigned(marker["baselineInode"]) == copy.captured.st_ino,
              marker["manifestSHA256"] as? String == checked.manifest.digest else { throw DisposableFailure.manifestMismatch }
        try mtreeVerify(copy, name: "target-157.0.mtree", hash: marker["mtreeSHA256"] as! String)
        manifests["baseline"] = checked.manifest
        if includeTarget {
            let target = try applications!.child("Firefox.app"), observed = try observe(target, version: "157.0")
            guard target.captured.st_ino == unsigned(marker["targetInode"]), observed.manifest == checked.manifest else { throw DisposableFailure.manifestMismatch }
            try mtreeVerify(target, name: "target-157.0.mtree", hash: marker["mtreeSHA256"] as! String)
        }
        return checked.manifest
    }
    func catalogue(_ name: String, bootstrap: Bool) throws -> CatalogueCandidate {
        let bytes = try PhysicalIO.read(incoming, name, maximum: 131_072)
        let target = try applications!.child("Firefox.app")
        let plist = try PhysicalIO.read(target, "Contents/Info.plist", maximum: 1_048_576)
        guard let object = try PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Any],
              let installed = object["CFBundleShortVersionString"] as? String, installed == "157.0" else { throw DisposableFailure.wrongVersion }
        let candidate = try TestCatalogue.accept(root: caseDirectory!, envelope: bytes, now: Date().timeIntervalSince1970,
                                        os: GuestGuard.observe(profile: profile).osVersion, installed: installed, bootstrap: bootstrap)
        catalogueResults.append(["keyID": TestCatalogue.trust.keyID, "catalogueID": candidate.catalogueID,
            "sequence": String(candidate.sequence), "payloadSHA256": candidate.payloadSHA256, "envelopeSHA256": digest(bytes),
            "testCatalogueTrust": "true", "productionTrust": "false"])
        return candidate
    }
    func pause(_ point: DisposablePause, details: [String: Any], journal: ProofJournal) throws {
        try confirm()
        let id = journal.object["transactionID"] as! String
        let token = point.rawValue + "-" + id
        var witness = details
        witness["pause"] = point.rawValue; witness["transactionID"] = id; witness["state"] = journal.state.rawValue
        witness["pid"] = getpid(); witness["runID"] = request.runID; witness["caseRoot"] = request.caseRoot!
        witness["completed"] = false
        try PhysicalIO.write(transaction!, "pause-" + token + ".json", data: encodeJSON(witness))
        let deadline = ProcessInfo.processInfo.systemUptime + 900
        while ProcessInfo.processInfo.systemUptime < deadline {
            try confirm()
            let resume = "resume-" + token + ".txt"
            if try transaction!.named(resume) != nil {
                guard try PhysicalIO.read(transaction!, resume, maximum: 16) == Data("resume\n".utf8) else { throw DisposableFailure.notAuthorized }
                return // Merely continues. All physical/native checks are repeated before any exchange.
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw DisposableFailure.commandTimedOut
    }
    func persist(_ journal: ProofJournal) throws {
        try JournalStore.write(transaction!, data: journal.encoded, binding: binding(), locked: true)
        reached.append(journal.state.rawValue); state = journal.state.rawValue
    }
    func perform() throws {
        let target = try applications!.child("Firefox.app")
        guard try transaction!.named("journal.json") == nil else { throw DisposableFailure.existingRoot }
        // The altered-target case must reach its real signer check before comparing old baseline bytes.
        if request.action == .wrongSignerTarget {
            let manifest = try ManifestReader.read(target)
            manifests["afterIntentionalMutation"] = manifest
            _ = try mtreeCapture(target, name: "target-mutated.mtree")
            _ = try observe(target, version: "157.0")
            throw DisposableFailure.caseConditionMissing // An unaltered target cannot prove a signer refusal.
        }
        _ = try verifyBaseline(includeTarget: true)
        if request.action == .recordedEvidence {
            guard request.recordedEvidencePath == incoming.path + "/inspection-157.0.1.json" else { throw DisposableFailure.caseConditionMissing }
            let offered = try HeldFile(parent: incoming, name: "inspection-157.0.1.json")
            let bytes = try offered.data(maximum: 1_048_576)
            try writeEvidence("recorded-input", ["path": request.recordedEvidencePath!, "sha256": digest(bytes),
                "byteLength": bytes.count, "freshOSValidation": false, "installationAuthorized": false])
            try offered.confirm()
            try DisposableProof.rejectRecordedEvidence(bytes)
        }
        try requireAppClosed(target)
        if request.action == .openApp { throw DisposableFailure.caseConditionMissing }
        if request.action == .invalidCatalogue || request.action == .replayedCatalogue {
            _ = try catalogue("catalogue-valid.json", bootstrap: true)
            let checkpoint = try caseDirectory!.descend("Catalogue")
            let before = try PhysicalIO.read(checkpoint, "checkpoint.json", maximum: 65_536)
            do {
                _ = try catalogue("catalogue-" + request.caseRoot! + ".json", bootstrap: false)
            } catch {
                guard try PhysicalIO.read(checkpoint, "checkpoint.json", maximum: 65_536) == before else { throw DisposableFailure.persistenceFailed }
                throw error
            }
            throw DisposableFailure.caseConditionMissing
        }
        let input = request.action == .tamperedArtifact ? "tampered.dmg" :
            request.action == .truncatedArtifact ? "truncated.dmg" : "Firefox 157.0.1.dmg"
        let image = try image("157.0.1", input: input)
        if request.action == .tamperedArtifact || request.action == .truncatedArtifact { throw DisposableFailure.caseConditionMissing }
        let candidate = try catalogue("catalogue-valid.json", bootstrap: true)
        try containerChecks(image)
        let source: HeldDirectory = try image.withMount(commands: commands) { mount in
            guard try mount.names(maximum: 100).filter({ $0.hasSuffix(".app") }) == ["Firefox.app"] else { throw DisposableFailure.wrongBundle }
            let app = try mount.child("Firefox.app"), mounted = try observe(app, version: "157.0.1", owner: nil)
            let source = try ditto(app, parent: work!, name: "Source.app", expected: mounted.manifest)
            _ = try observe(source, version: "157.0.1")
            return source
        }
        guard !(try mountedPaths()).contains(where: { $0.hasPrefix(work!.path + "/") }) else { throw DisposableFailure.cleanupFailed }
        let verifiedSource = try observe(source, version: "157.0.1")
        let before = try observe(target, version: "157.0"); manifests["before"] = before.manifest
        let lock = try ExclusiveLock(transaction!, name: "journal.lock"); defer { withExtendedLifetime(lock) {} }
        let exchange = try transaction!.mkdir("Exchange")
        try requirePrivateACL(exchange)
        var journal = ProofJournal(object: [
            "schemaVersion": 1, "kind": "patched-disposable-journal-v1", "origin": "disposableGuest",
            "guestUUIDSHA256": guest.platformUUIDSHA256, "uid": getuid(), "runID": request.runID, "caseRoot": request.caseRoot!,
            "device": identity(caseDirectory!.captured).0, "inode": caseDirectory!.captured.st_ino,
            "state": "prepared", "transactionID": UUID().uuidString,
            "oldInode": target.captured.st_ino, "newInode": 0,
            "beforeManifestSHA256": before.manifest.digest, "afterManifestSHA256": verifiedSource.manifest.digest,
            "cataloguePayloadSHA256": candidate.payloadSHA256, "artifactSHA256": candidate.artifact.sha256])
        try persist(journal); try journal.transition(.staging); try persist(journal)
        try space(verifiedSource.manifest.totalBytes)
        let stage = try copyBundle(source, into: exchange, name: "Firefox.app", witness: { path, copied, total, inode in
            if self.request.action == .stagingFailure {
                try self.pause(.stageCopy, details: ["file": path, "copiedBytes": copied, "expectedBytes": total, "fileInode": inode], journal: journal)
            }
        })
        _ = try observe(stage, version: "157.0.1")
        if request.action == .stagingFailure { throw DisposableFailure.caseConditionMissing }
        journal.object["newInode"] = stage.captured.st_ino
        try journal.transition(.staged); try persist(journal)
        if request.action == .wrongSignerStaged { try pause(.beforeSwap, details: ["stagePath": stage.path], journal: journal) }
        // A resumed pause cannot supply acceptance. Ask macOS again and compare every byte.
        let afterPause = try observe(stage, version: "157.0.1")
        guard afterPause.manifest == verifiedSource.manifest else { throw DisposableFailure.manifestMismatch }
        if request.action == .wrongSignerStaged { throw DisposableFailure.caseConditionMissing }
        _ = try verifyBaseline(includeTarget: true); try requireAppClosed(target)
        try image.confirm(); _ = try catalogue("catalogue-valid.json", bootstrap: false)
        guard try ManifestReader.read(source) == verifiedSource.manifest else { throw DisposableFailure.manifestMismatch }
        // Last native stage assessment is immediately before the durable exchange intent and syscall.
        _ = try observe(stage, version: "157.0.1"); try requireAppClosed(target)
        try journal.transition(.swapIntended); try persist(journal)
        try PhysicalIO.exchange(caseDirectory!, "Applications/Firefox.app", "Transaction/Exchange/Firefox.app")
        try journal.transition(.swapped); try persist(journal)
        if request.action == .interruptedSwap {
            try pause(.beforeCommit, details: ["targetPath": target.path, "retainedPath": stage.path], journal: journal)
            throw DisposableFailure.caseConditionMissing
        }
        let installed = try applications!.child("Firefox.app"), retained = try exchange.child("Firefox.app")
        guard installed.captured.st_ino == journal.newInode, retained.captured.st_ino == journal.oldInode,
              try ManifestReader.read(retained).digest == before.manifest.digest else { throw DisposableFailure.ambiguousState }
        let accepted = try observe(installed, version: "157.0.1")
        guard accepted.manifest == verifiedSource.manifest else { throw DisposableFailure.manifestMismatch }
        manifests["after"] = accepted.manifest; manifests["retainedOld"] = try ManifestReader.read(retained)
        try journal.transition(.committed); try persist(journal); installedProof = true
    }
    func recover() throws {
        _ = try verifyBaseline(includeTarget: false)
        let target = try applications!.child("Firefox.app"); try requireAppClosed(target)
        recovery = try SharedRecovery.recover(caseDirectory!, binding: binding(), target: "Applications/Firefox.app",
            retained: "Transaction/Exchange/Firefox.app", journalDirectory: transaction!) { old in
                try self.requireAppClosed(old); _ = try self.observe(old, version: "157.0")
            }.rawValue
        let record = try JournalStore.read(transaction!, binding: binding()); state = record.state.rawValue; reached.append(state)
        if record.state == .rolledBack { _ = try verifyBaseline(includeTarget: true) }
    }
    func restore() throws {
        _ = try verifyBaseline(includeTarget: false)
        let target = try applications!.child("Firefox.app"), retained = try transaction!.descend("Exchange/Firefox.app")
        try requireAppClosed(target)
        let targetObserved = try observe(target, version: "157.0.1"), oldObserved = try observe(retained, version: "157.0")
        do {
            let lock = try ExclusiveLock(transaction!, name: "journal.lock"); defer { withExtendedLifetime(lock) {} }
            var journal = try JournalStore.read(transaction!, binding: binding())
            guard journal.state == .committed, journal.oldInode == retained.captured.st_ino, journal.newInode == target.captured.st_ino,
                  journal.oldDigest == oldObserved.manifest.digest, journal.newDigest == targetObserved.manifest.digest else { throw DisposableFailure.ambiguousState }
            try journal.transition(.swapIntended); try persist(journal)
        }
        try recover()
    }
}

// Shared native copy boundary. The guest caller retains its space/authority checks;
// the Testing SPI reaches this same helper only inside its exclusive synthetic root.
func nativeDittoBundle(_ source: HeldDirectory, parent: HeldDirectory, name: String,
                       expected: ProofManifest, commands: NativeCommands) throws -> HeldDirectory {
    let fresh = try parent.mkdir(name), inode = fresh.captured.st_ino
    guard try fresh.names(maximum: 1).isEmpty else { throw DisposableFailure.existingRoot }
    try source.confirm(); try fresh.confirm()
    _ = try commands.success("/usr/bin/ditto", [source.path, fresh.path], seconds: 180)
    try source.confirm(); try fresh.confirm()
    // ditto preserves an existing root's metadata. Restore it through the original
    // exclusive descriptor, then reopen after this intentional captured-mode change.
    guard fcopyfile(source.fd, fresh.fd, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0,
          fchmod(fresh.fd, permissions(source.captured)) == 0,
          fsync(fresh.fd) == 0 else { throw DisposableFailure.persistenceFailed }
    try parent.syncDirectory()
    let result = try parent.child(name)
    guard result.captured.st_ino == inode, try ManifestReader.read(result) == expected else { throw DisposableFailure.manifestMismatch }
    return result
}
