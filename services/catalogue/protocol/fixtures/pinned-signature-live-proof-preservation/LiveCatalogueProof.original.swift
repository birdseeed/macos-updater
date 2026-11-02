import Foundation
import CryptoKit
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// Explicitly invoked, never part of the unit gate: one end-to-end proof that the actual pinned
// vendor verification happens BEFORE the exact verified artifact's catalogue is signed. It
// copies the one approved preserved disk image into a new operator root beneath this
// worktree's .build, runs the actual inspector there (a read-only mount, nothing launched),
// signs with the test-only fixture key, publishes, and has the real consumer read the
// physical output in this process and in a separate process. Passing is an operating proof
// of a local test-key catalogue only: not an installation, a product release or a production key.

enum LiveProof {
    static let version = "157.0.1"
    /// The only input this command reads. It is copied and hashed, never changed, moved or removed.
    static let approvedSource = "/Users/andybridson/Documents/Patched/proofs/firefox-inspection-20261007/Firefox 157.0.1.dmg"
    static let artifactName = "Firefox 157.0.1.dmg"
    static let sequence: UInt64 = 1
    static let lifetime: UInt64 = 3_600
    static let childSeconds = 60.0
    static let childOutputBytes = 65_536
    static let reportFields: Set<String> = ["schemaVersion", "pin", "mode", "sourcePath", "sourceURL", "redirectChain", "transportObservedThisRun",
                                            "byteIntegrityVerified", "commands", "evidence", "assessment", "refusal", "workspacePreserved",
                                            "cleanupVerified", "installationAuthorized", "providerActualCost"]
}

/// What happened, in order. Written beside the proof whether it is accepted or not.
final class ProofLog {
    var steps: [String] = []
    var children: [[String: Any]] = []
    func step(_ name: String) { steps.append(name); print("STEP live catalogue proof \(steps.count): \(name)") }
}

struct PhysicalIdentity: Equatable {
    let device: UInt64, inode: UInt64, byteLength: Int64, mode: UInt16, links: UInt16, modifiedSeconds: Int, modifiedNanoseconds: Int
}
func physicalIdentity(_ path: String) throws -> PhysicalIdentity {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw CheckFailure(description: "Not an existing regular file: \(path)") }
    return PhysicalIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino), byteLength: Int64(info.st_size),
                            mode: UInt16(info.st_mode & 0o7777), links: UInt16(info.st_nlink),
                            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec)
}

/// A bounded streaming copy into one exclusively created mode-0600 file. The source is opened read-only.
func copyPrivately(from source: String, to destination: URL, maximum: Int64) throws {
    let input = open(source, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard input >= 0 else { throw CheckFailure(description: "Could not open the approved source read-only") }
    defer { close(input) }
    let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { throw CheckFailure(description: "Could not exclusively create the private copy: errno \(errno)") }
    defer { close(output) }
    var buffer = [UInt8](repeating: 0, count: 1_048_576), total: Int64 = 0
    while true {
        let count = read(input, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw CheckFailure(description: "Reading the approved source failed: errno \(errno)") }
        if count == 0 { break }
        total += Int64(count)
        guard total <= maximum else { throw CheckFailure(description: "The source exceeds the pinned length") }
        var offset = 0
        while offset < count {
            let written = buffer.withUnsafeBytes { write(output, $0.baseAddress!.advanced(by: offset), count - offset) }
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { throw CheckFailure(description: "Writing the private copy failed: errno \(errno)") }
            offset += written
        }
    }
    guard fchmod(output, 0o600) == 0, fsync(output) == 0 else { throw CheckFailure(description: "Could not finish the private copy") }
}

/// The documented envelope, frame, signature and exact payload schema, checked with CryptoKit and
/// JSONSerialization only. The digest and length are compared with the compiled pin; the
/// artifact is not read here.
func verifyLiveEnvelope(_ envelope: Data, request: CatalogueRequest, pin: TargetPin) throws -> Decoded {
    try expect(envelope.count <= 131_072 && String(data: envelope, encoding: .utf8) != nil && !envelope.starts(with: [0xef, 0xbb, 0xbf]),
               "Envelope is not bounded UTF-8 without a BOM")
    let outer = try object(envelope)
    try expect(Set(outer.keys) == ["keyID", "payload", "signature"], "Envelope fields differ: \(outer.keys.sorted())")
    guard outer["keyID"] as? String == request.keyID, let encodedPayload = outer["payload"] as? String,
          let encodedSignature = outer["signature"] as? String, let payload = Data(base64Encoded: encodedPayload),
          let signature = Data(base64Encoded: encodedSignature) else { throw CheckFailure(description: "Envelope is not the documented record") }
    try expect(payload.base64EncodedString() == encodedPayload && signature.base64EncodedString() == encodedSignature && signature.count == 64,
               "Envelope base64 is not canonical or the signature is not 64 bytes")
    try expect(payload.count <= 65_536, "Payload exceeds 64 KiB")
    try expect(try Sample.key().publicKey.isValidSignature(signature, for: Data((Sample.domain + "\0").utf8) + payload),
               "Signature does not verify over the documented frame with the test public key")
    try expect(!(try Sample.key(true).publicKey.isValidSignature(signature, for: Data((Sample.domain + "\0").utf8) + payload)),
               "Signature verifies under an unrelated key")
    let fields = try object(payload)
    try expect(Set(fields.keys) == ["schemaVersion", "domain", "keyID", "catalogueID", "sequence", "issuedAt", "expiresAt", "artifact"],
               "Payload fields differ: \(fields.keys.sorted())")
    try expect(unsigned(fields["schemaVersion"]) == 1 && fields["domain"] as? String == Sample.domain &&
               fields["keyID"] as? String == request.keyID && fields["catalogueID"] as? String == request.catalogueID,
               "Payload identity differs from the request")
    try expect(unsigned(fields["sequence"]) == request.sequence && unsigned(fields["issuedAt"]) == request.issuedAt &&
               unsigned(fields["expiresAt"]) == request.expiresAt, "Payload sequence or times differ from the request")
    guard let signedArtifact = fields["artifact"] as? [String: Any] else { throw CheckFailure(description: "Payload has no artifact object") }
    try expect(Set(signedArtifact.keys) == ["bundleID", "teamID", "platform", "minimumOS", "maximumOS", "version", "sha256", "byteLength"],
               "Artifact fields differ: \(signedArtifact.keys.sorted())")
    try expect(signedArtifact["bundleID"] as? String == pin.bundleID && signedArtifact["teamID"] as? String == pin.teamID &&
               signedArtifact["platform"] as? String == "macOS" && signedArtifact["version"] as? String == pin.version,
               "Signed artifact identity is not the pinned identity")
    try expect(signedArtifact["minimumOS"] as? String == request.minimumOS && signedArtifact["maximumOS"] as? String == request.maximumOS,
               "Signed OS range differs from the request")
    try expect(signedArtifact["sha256"] as? String == pin.sha256 && unsigned(signedArtifact["byteLength"]) == UInt64(pin.byteLength),
               "Signed digest or length is not the compiled pin")
    return Decoded(payload: payload, fields: fields, artifact: signedArtifact)
}

/// The operator's durable files other than the 161 MB artifact, which is checked by identity and streamed digest instead.
func operatorRecords(_ layout: Layout) throws -> [String: String] {
    var result = try snapshot(layout.publications)
    result["namespace.json"] = sha(try bytes(layout.namespace)); result["checkpoint.json"] = sha(try bytes(layout.checkpoint))
    return result
}

/// The existing consumer command in a separate process, with its output kept in the proof directory.
func consumerChild(_ name: String, _ arguments: [String], _ layout: Layout, _ log: ProofLog) throws -> (code: Int32, stdout: String, stderr: String) {
    guard let checks = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw CheckFailure(description: "Executable path unknown") }
    let command = checks.deletingLastPathComponent().appendingPathComponent("patched-core-proof")
    try expect(exists(command), "The consumer command is not built beside this executable: \(command.path)")
    let out = layout.scratch.appendingPathComponent("child-\(name).stdout"), err = layout.scratch.appendingPathComponent("child-\(name).stderr")
    try writeFile(Data(), out); try writeFile(Data(), err)
    let process = Process()
    process.executableURL = command; process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = try FileHandle(forWritingTo: out); process.standardError = try FileHandle(forWritingTo: err)
    try process.run()
    let deadline = Date().addingTimeInterval(LiveProof.childSeconds)
    while process.isRunning && Date() < deadline { usleep(10_000) }
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL); process.waitUntilExit()
        throw CheckFailure(description: "Consumer child \(name) exceeded its \(Int(LiveProof.childSeconds))-second bound")
    }
    process.waitUntilExit()
    try expect(try physicalIdentity(out.path).byteLength <= Int64(LiveProof.childOutputBytes) &&
               physicalIdentity(err.path).byteLength <= Int64(LiveProof.childOutputBytes), "Consumer child \(name) exceeded its output bound")
    let result = (process.terminationStatus, String(decoding: try bytes(out), as: UTF8.self), String(decoding: try bytes(err), as: UTF8.self))
    log.children.append(["name": name, "executable": command.path, "arguments": arguments, "exitCode": Int(result.0),
                         "stdout": result.1, "stderr": result.2, "stdoutPath": out.path, "stderrPath": err.path])
    return result
}

/// Every step in order. Returns the proof record only when every assertion held.
func liveCatalogueProof(_ layout: Layout, _ log: ProofLog) throws -> [String: Any] {
    let pin = try FirefoxTargets.select(version: LiveProof.version)
    let source = LiveProof.approvedSource, copy = layout.input.appendingPathComponent(LiveProof.artifactName)

    // 1. A new operator root from the explicit authority. Nothing else names an output location.
    let authority = try FixtureOperatorAuthority.createFreshRoot(path: layout.root.path, trust: Sample.trust())
    try expectPrivateDirectory(layout.root, "Operator root"); try expectPrivateDirectory(layout.input, "Input directory")
    try expect(authority.root == layout.root.path && names(layout.input).isEmpty && names(layout.publications).isEmpty &&
               checkpointFields(layout).sequence == 0, "A fresh operator root is not empty at sequence 0")
    log.step("createFreshRoot")

    // 2. The approved source is the exact pin before and after it is copied, and is left as it was.
    let sourceBefore = try physicalIdentity(source)
    try ArtifactBytes.verify(path: source, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
    log.step("approved source verified as the compiled pin before copying")
    try copyPrivately(from: source, to: copy, maximum: pin.byteLength)
    try ArtifactBytes.verify(path: copy.path, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
    try expectPrivateFile(copy, "Copied artifact")
    try ArtifactBytes.verify(path: source, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
    let copied = try physicalIdentity(copy.path)
    try expect(try physicalIdentity(source) == sourceBefore, "Copying changed the approved source")
    try expect((copied.device, copied.inode) != (sourceBefore.device, sourceBefore.inode) && copied.byteLength == pin.byteLength &&
               names(layout.input) == [LiveProof.artifactName], "The private copy is not a separate file alone in the input directory")
    log.step("private mode-0600 copy verified as the compiled pin; source unchanged")

    // 3. Verify: the operator's live entry runs the actual inspector on the copied physical file.
    let receipt = try OperatorVerification.verifyPinnedArtifact(version: LiveProof.version, path: copy.path)
    try expect(receipt.origin == .live && receipt.freshOSValidation && receipt.byteIntegrityVerified && receipt.appChecksPassed &&
               receipt.cleanupVerified, "Live receipt does not record a fresh passing inspection with verified cleanup")
    try expect(!receipt.installationAuthorized, "Live receipt grants installation authority")
    try expect(receipt.version == pin.version && receipt.bundleID == pin.bundleID && receipt.teamID == pin.teamID &&
               receipt.sha256 == pin.sha256 && receipt.byteLength == pin.byteLength, "Live receipt identity is not the exact pin")
    try expect(receipt.artifactPath == copy.path && receipt.artifactInode == copied.inode && receipt.artifactDevice == copied.device,
               "Live receipt does not bind the copied physical file")
    try expect(!receipt.containerSignaturePassed && !receipt.containerGatekeeperPassed && !receipt.containerTicketPassed,
               "Unsigned container results were rewritten as passes")
    try expect(receipt.inspectionRecordSHA256.utf8.count == 64 && receipt.inspectionRecordSHA256 != Sample.zeroDigest &&
               (1...OperatorLimits.maximumInspectionRecordBytes).contains(receipt.inspectionRecordByteLength),
               "Live receipt does not bind a bounded inspection record")
    let encodedReceipt = try object(JSONEncoder().encode(receipt))
    try expect(encodedReceipt["origin"] as? String == "live" && flag(encodedReceipt["installationAuthorized"]) == false &&
               flag(encodedReceipt["containerSignaturePassed"]) == false && flag(encodedReceipt["containerGatekeeperPassed"]) == false &&
               flag(encodedReceipt["containerTicketPassed"]) == false, "Encoded live receipt differs")
    try expect(try physicalIdentity(copy.path) == copied && names(layout.publications).isEmpty && checkpointFields(layout).sequence == 0,
               "Verification changed the artifact, signed or published")
    log.step("verifyPinnedArtifact: live receipt for the copied file")

    // 4. Sign: an explicit current clock and request, answered by the test-only signer.
    let now = Date().timeIntervalSince1970.rounded(.down), issued = UInt64(now)
    let request = Sample.request(sequence: LiveProof.sequence, issuedAt: issued, expiresAt: issued + LiveProof.lifetime)
    let catalogue = try authority.sign(receipt: receipt, request: request, now: now, signer: Sample.signer)
    let decoded = try verifyLiveEnvelope(catalogue.envelope, request: request, pin: pin)
    try expect(catalogue.origin == "fixture" && !catalogue.freshOSValidation && !catalogue.installationAuthorized && !catalogue.published,
               "Signed catalogue asserted OS validation, installation authority or publication")
    try expect(catalogue.receiptOrigin == .live && catalogue.inspectionRecordSHA256 == receipt.inspectionRecordSHA256,
               "Signed catalogue does not record its live receipt separately")
    try expect(catalogue.envelopeSHA256 == sha(catalogue.envelope) && catalogue.payloadSHA256 == sha(decoded.payload) &&
               catalogue.keyID == Sample.keyID && catalogue.catalogueID == Sample.catalogueID && catalogue.sequence == LiveProof.sequence,
               "Signed catalogue identity or digests differ from its bytes")
    try expect(try names(layout.publications).isEmpty, "Signing wrote a published file")
    let mark = try checkpointFields(layout)
    try expect(mark.sequence == LiveProof.sequence && mark.payloadSHA256 == sha(decoded.payload), "High-water mark does not record the signed payload")
    log.step("sign: test-key signature over the exact pin, verified independently with CryptoKit")

    // 5. Publish, then judge only what is physically on disk.
    let published = try authority.publish(catalogue, now: now)
    let directory = layout.publication(LiveProof.sequence)
    try expect(published.origin == "fixture" && published.receiptOrigin == .live && !published.freshOSValidation &&
               !published.installationAuthorized && !published.productionPublication, "Published result asserted trust, installation or production")
    try expect(published.publicationPath == directory.path && published.cataloguePath == directory.appendingPathComponent("catalogue.json").path &&
               published.evidencePath == directory.appendingPathComponent("evidence.json").path &&
               published.inspectionRecordPath == directory.appendingPathComponent("inspection-record.json").path &&
               published.publicationRecordPath == directory.appendingPathComponent("publication.json").path, "Reported paths are not the physical files")
    log.step("publish")

    try expectPrivateDirectory(directory, "Publication directory")
    try expect(try names(directory) == publicationFiles && names(layout.publications) == ["sequence-\(LiveProof.sequence)"] &&
               names(layout.root) == ["namespace.json", "checkpoint.json", "lock", "input", "publications"] &&
               names(layout.input) == [LiveProof.artifactName], "Publishing left unexpected entries")
    for name in publicationFiles { try expectPrivateFile(directory.appendingPathComponent(name), name) }
    let physical = try bytes(URL(fileURLWithPath: published.cataloguePath))
    try expect(physical == catalogue.envelope && sha(physical) == published.envelopeSHA256 && physical.count == published.envelopeByteLength,
               "Published catalogue is not the exact signed bytes")
    let physicalDecoded = try verifyLiveEnvelope(physical, request: request, pin: pin)
    try expect(sha(physicalDecoded.payload) == published.payloadSHA256, "Published payload digest differs")

    // The raw inspection record: the actual inspector's own report, exactly as the receipt bound it.
    try expect(try physicalIdentity(published.inspectionRecordPath).byteLength <= Int64(OperatorLimits.maximumInspectionRecordBytes),
               "Inspection record exceeds its bound")
    let record = try bytes(URL(fileURLWithPath: published.inspectionRecordPath))
    try expect(sha(record) == receipt.inspectionRecordSHA256 && record.count == receipt.inspectionRecordByteLength &&
               sha(record) == published.inspectionRecordSHA256, "Published inspection record is not the record the receipt bound")
    let report = try object(record)
    try expect(Set(report.keys).isSubset(of: LiveProof.reportFields), "Inspection record is not the inspector's report: \(report.keys.sorted())")
    guard let reportPin = report["pin"] as? [String: Any], let assessment = report["assessment"] as? [String: Any],
          let evidence = report["evidence"] as? [String: Any], let observed = evidence["commands"] as? [String: Any],
          let ran = report["commands"] as? [Any], let osVersion = evidence["osVersion"] as? String else {
        throw CheckFailure(description: "Inspection record lacks its pin, assessment, evidence or commands")
    }
    try expect(unsigned(report["schemaVersion"]) == 1 && report["mode"] as? String == "inspect-local" && report["sourcePath"] as? String == copy.path &&
               flag(report["transportObservedThisRun"]) == false, "Inspection record is not a local inspection of the copied file")
    try expect(reportPin["version"] as? String == pin.version && reportPin["sha256"] as? String == pin.sha256 &&
               unsigned(reportPin["byteLength"]) == UInt64(pin.byteLength) && reportPin["bundleID"] as? String == pin.bundleID &&
               reportPin["teamID"] as? String == pin.teamID && reportPin["url"] as? String == pin.url, "Inspection record names another pin")
    try expect(flag(report["byteIntegrityVerified"]) == true && flag(report["cleanupVerified"]) == true &&
               (report["refusal"] == nil || report["refusal"] is NSNull) &&
               (report["workspacePreserved"] == nil || report["workspacePreserved"] is NSNull) &&
               flag(report["installationAuthorized"]) == false, "Inspection record holds a refusal, unverified cleanup or installation authority")
    try expect(assessment["origin"] as? String == "live" && flag(assessment["appChecksPassed"]) == true &&
               flag(assessment["freshOSValidation"]) == true && flag(assessment["installationAuthorized"]) == false,
               "Inspection record's assessment is not a live passing app assessment")
    try expect(flag(assessment["containerSignaturePassed"]) == false && flag(assessment["containerGatekeeperPassed"]) == false &&
               flag(assessment["containerTicketPassed"]) == false, "Inspection record rewrote the unsigned container results")
    try expect(observed["ticket"] == nil && observed["containerTicket"] == nil &&
               flag(assessment["containerTicketPassed"]) == false,
               "Live inspection retained ticket observations or claimed current ticket validation")
    try expect(ran.allSatisfy { value in
        guard let command = value as? [String: Any], let executable = command["executable"] as? String,
              let arguments = command["arguments"] as? [String] else { return false }
        return executable != "/usr/bin/xcrun" && !arguments.contains("stapler")
    }, "Live inspection ran a stapling command or has malformed command records")
    for key in ["containerSignature", "containerGatekeeper"] {
        guard let result = observed[key] as? [String: Any], let code = unsigned(result["exitCode"]) else {
            throw CheckFailure(description: "Inspection record omits the \(key) result")
        }
        try expect(code != 0, "Inspection record does not keep the failing \(key) result")
    }
    try expect(!ran.isEmpty && osVersion.range(of: "^(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*)){0,7}$", options: .regularExpression) != nil,
               "Inspection record has no commands or no observed OS version")

    // Evidence and the publication record: separate from the signed bytes, linked by digest.
    let evidenceBytes = try bytes(URL(fileURLWithPath: published.evidencePath))
    try expect(evidenceBytes.count <= OperatorLimits.maximumEvidenceBytes && sha(evidenceBytes) == published.evidenceSHA256, "Evidence differs from its bound or digest")
    let summary = try object(evidenceBytes)
    try expect(Set(summary.keys) == ["schemaVersion", "kind", "receiptOrigin", "catalogueOrigin", "version", "bundleID", "teamID", "sha256", "byteLength",
                                     "byteIntegrityVerified", "appChecksPassed", "containerSignaturePassed", "containerGatekeeperPassed",
                                     "containerTicketPassed", "cleanupVerified", "freshOSValidation", "inspectionRecordSHA256",
                                     "inspectionRecordByteLength", "installationAuthorized", "productionPublication"],
               "Evidence fields differ: \(summary.keys.sorted())")
    try expect(unsigned(summary["schemaVersion"]) == 1 && summary["kind"] as? String == "patched-operator-evidence-v1" &&
               summary["receiptOrigin"] as? String == "live" && summary["catalogueOrigin"] as? String == "fixture",
               "Evidence does not keep the live receipt origin separate from the fixture catalogue origin")
    try expect(summary["version"] as? String == pin.version && summary["bundleID"] as? String == pin.bundleID &&
               summary["teamID"] as? String == pin.teamID && summary["sha256"] as? String == pin.sha256 &&
               unsigned(summary["byteLength"]) == UInt64(pin.byteLength), "Evidence identity is not the compiled pin")
    try expect(flag(summary["byteIntegrityVerified"]) == true && flag(summary["appChecksPassed"]) == true && flag(summary["cleanupVerified"]) == true &&
               flag(summary["freshOSValidation"]) == true && flag(summary["containerSignaturePassed"]) == false &&
               flag(summary["containerGatekeeperPassed"]) == false && flag(summary["containerTicketPassed"]) == false &&
               flag(summary["installationAuthorized"]) == false && flag(summary["productionPublication"]) == false,
               "Evidence differs from the live receipt, or asserts installation authority or production")
    try expect(summary["inspectionRecordSHA256"] as? String == sha(record) && unsigned(summary["inspectionRecordByteLength"]) == UInt64(record.count),
               "Evidence is not digest-linked to the inspection record")
    let publicationBytes = try bytes(URL(fileURLWithPath: published.publicationRecordPath))
    let publication = try object(publicationBytes)
    try expect(Set(publication.keys) == ["schemaVersion", "kind", "keyID", "catalogueID", "sequence", "catalogueSHA256", "catalogueByteLength",
                                         "payloadSHA256", "evidenceSHA256", "inspectionRecordSHA256", "origin", "installationAuthorized",
                                         "productionPublication"], "Publication record fields differ: \(publication.keys.sorted())")
    try expect(unsigned(publication["schemaVersion"]) == 1 && publication["kind"] as? String == "patched-operator-publication-v1" &&
               publication["keyID"] as? String == Sample.keyID && publication["catalogueID"] as? String == Sample.catalogueID &&
               unsigned(publication["sequence"]) == LiveProof.sequence && publication["origin"] as? String == "fixture" &&
               flag(publication["installationAuthorized"]) == false && flag(publication["productionPublication"]) == false,
               "Publication record identity or scope differs: \(publication)")
    try expect(publication["catalogueSHA256"] as? String == sha(physical) && unsigned(publication["catalogueByteLength"]) == UInt64(physical.count) &&
               publication["payloadSHA256"] as? String == sha(physicalDecoded.payload) && publication["evidenceSHA256"] as? String == sha(evidenceBytes) &&
               publication["inspectionRecordSHA256"] as? String == sha(record), "Publication record is not digest-linked to the files beside it")
    try expect(try physicalIdentity(copy.path) == copied, "Signing or publishing changed the copied artifact")
    let recordsBefore = try operatorRecords(layout)
    log.step("physical envelope, inspection record, evidence and publication record read back and linked")

    // 6. The real consumer, in this process. The OS version is the one the inspector observed;
    // the installed version is a policy comparison input, not a statement about any installed Firefox.
    let state = layout.consumerState
    let policy = CandidatePolicy(bundleID: pin.bundleID, teamID: pin.teamID, osVersion: osVersion, installedVersion: Sample.installed)
    let candidate = try CatalogueVerifier(trust: try Sample.trust(), policy: policy, stateDirectory: state.path)
        .bootstrapFreshProofNamespace(envelope: physical, now: now)
    try expect(candidate.sequence == LiveProof.sequence && candidate.catalogueID == Sample.catalogueID &&
               candidate.payloadSHA256 == sha(physicalDecoded.payload), "Consumer accepted a different catalogue")
    try expect(candidate.origin == "fixture" && !candidate.freshOSValidation && !candidate.installationAuthorized,
               "Consumer result asserted OS validation or installation authority")
    try expect(candidate.artifact.sha256 == pin.sha256 && candidate.artifact.byteLength == pin.byteLength &&
               candidate.artifact.version == pin.version, "Consumer artifact is not the compiled pin")
    log.step("consumer bootstrapFreshProofNamespace on the published bytes")
    let consistency = try ArtifactVerifier.verify(path: copy.path, candidate: candidate)
    try expect(consistency.sha256 == pin.sha256 && consistency.byteLength == pin.byteLength && consistency.origin == "fixture" &&
               !consistency.freshOSValidation && !consistency.installationAuthorized, "Artifact consistency differs or asserted trust")
    try expect(try ArtifactVerifier.approvedInspectionTarget(candidate: candidate) == pin, "Candidate does not select the exact compiled pin")
    log.step("consumer ArtifactVerifier matched the copied bytes; candidate selects the compiled pin")
    let again = try CatalogueVerifier(trust: try Sample.trust(), policy: policy, stateDirectory: state.path).verify(envelope: physical, now: now)
    try expect(again.sequence == LiveProof.sequence && again.payloadSHA256 == candidate.payloadSHA256 && again.origin == "fixture" &&
               !again.freshOSValidation && !again.installationAuthorized, "A reconstructed consumer differs at the same sequence")
    log.step("reconstructed consumer verify at the same sequence")

    // 7. The existing consumer command in a separate process, given only public inputs.
    let publicKey = layout.scratch.appendingPathComponent("public-key.raw")
    try writeFile(try Sample.key().publicKey.rawRepresentation, publicKey)
    func childArguments(_ command: String, envelope: String, key: URL) -> [String] {
        [command, envelope, key.path, Sample.keyID, Sample.catalogueID, state.path, String(issued), osVersion, Sample.installed]
    }
    let accepted = try consumerChild("verify-artifact", childArguments("verify-artifact-fixture", envelope: published.cataloguePath, key: publicKey) + [copy.path],
                                     layout, log)
    try expect(accepted.code == 0, "Separate-process consumer refused: \(accepted.stderr)")
    let childResult = try object(Data(accepted.stdout.utf8))
    try expect(childResult["sha256"] as? String == pin.sha256 && unsigned(childResult["byteLength"]) == UInt64(pin.byteLength) &&
               childResult["origin"] as? String == "fixture" && flag(childResult["freshOSValidation"]) == false &&
               flag(childResult["installationAuthorized"]) == false, "Separate-process consumer output differs: \(accepted.stdout)")
    log.step("separate-process patched-core-proof verified the published file and the copied artifact")

    // 8. A changed envelope and an unrelated key are refused, and no refusal changes any state.
    let stateBefore = try snapshot(state)
    var fields = try object(physical)
    guard var payload = Data(base64Encoded: fields["payload"] as? String ?? ""), let digit = payload.firstIndex(of: UInt8(ascii: "1")) else {
        throw CheckFailure(description: "No payload byte to change")
    }
    payload[digit] = UInt8(ascii: "2"); fields["payload"] = payload.base64EncodedString()
    let tampered = layout.scratch.appendingPathComponent("tampered-catalogue.json"), otherKey = layout.scratch.appendingPathComponent("unrelated-public-key.raw")
    try writeFile(try json(fields), tampered); try writeFile(try Sample.key(true).publicKey.rawRepresentation, otherKey)
    try consumerRefuses(.invalidSignature) {
        _ = try CatalogueVerifier(trust: try Sample.trust(), policy: policy, stateDirectory: state.path).verify(envelope: try bytes(tampered), now: now)
    }
    try consumerRefuses(.invalidSignature) {
        let other = FixtureTrust(keyID: Sample.keyID, catalogueID: Sample.catalogueID, publicKey: try Sample.key(true).publicKey.rawRepresentation)
        _ = try CatalogueVerifier(trust: other, policy: policy, stateDirectory: state.path).verify(envelope: physical, now: now)
    }
    let changed = try consumerChild("tampered", childArguments("verify-fixture", envelope: tampered.path, key: publicKey), layout, log)
    try expect(changed.code == 1 && changed.stderr.contains("invalidSignature") && changed.stdout.isEmpty, "Separate-process consumer accepted changed bytes: \(changed)")
    let unrelated = try consumerChild("unrelated-key", childArguments("verify-fixture", envelope: published.cataloguePath, key: otherKey), layout, log)
    try expect(unrelated.code == 1 && unrelated.stderr.contains("invalidSignature") && unrelated.stdout.isEmpty,
               "Separate-process consumer accepted an unrelated key: \(unrelated)")
    try expect(try snapshot(state) == stateBefore, "A refused verification changed the consumer's state")
    log.step("changed envelope and unrelated key refused in this process and a separate process; consumer state unchanged")

    // 9. Nothing the operator wrote, the copy or the approved source changed while it was consumed.
    try expect(try operatorRecords(layout) == recordsBefore, "Consuming the publication changed the operator's files")
    try ArtifactBytes.verify(path: copy.path, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
    try ArtifactBytes.verify(path: source, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
    try expect(try physicalIdentity(copy.path) == copied && physicalIdentity(source) == sourceBefore, "The copied artifact or the approved source changed")
    log.step("operator files, copied artifact and approved source unchanged")

    func identity(_ value: PhysicalIdentity) -> [String: Any] { ["device": value.device, "inode": value.inode, "byteLength": value.byteLength] }
    return [
        "pin": ["version": pin.version, "sha256": pin.sha256, "byteLength": pin.byteLength, "bundleID": pin.bundleID, "teamID": pin.teamID],
        "source": ["path": source, "identity": identity(sourceBefore), "unchanged": true],
        "artifact": ["path": copy.path, "identity": identity(copied), "mode": "0600"],
        "receipt": ["origin": receipt.origin.rawValue, "freshOSValidation": receipt.freshOSValidation, "appChecksPassed": receipt.appChecksPassed,
                    "byteIntegrityVerified": receipt.byteIntegrityVerified, "cleanupVerified": receipt.cleanupVerified,
                    "containerSignaturePassed": receipt.containerSignaturePassed, "containerGatekeeperPassed": receipt.containerGatekeeperPassed,
                    "containerTicketPassed": receipt.containerTicketPassed, "installationAuthorized": receipt.installationAuthorized],
        "catalogue": ["keyID": published.keyID, "catalogueID": published.catalogueID, "sequence": published.sequence, "issuedAt": request.issuedAt,
                      "expiresAt": request.expiresAt, "minimumOS": request.minimumOS, "maximumOS": request.maximumOS, "origin": published.origin,
                      "receiptOrigin": published.receiptOrigin.rawValue, "freshOSValidation": published.freshOSValidation,
                      "installationAuthorized": published.installationAuthorized, "productionPublication": published.productionPublication],
        "paths": ["publication": published.publicationPath, "catalogue": published.cataloguePath, "evidence": published.evidencePath,
                  "inspectionRecord": published.inspectionRecordPath, "publicationRecord": published.publicationRecordPath,
                  "publicKey": publicKey.path, "consumerState": state.path],
        "sha256": ["catalogue": sha(physical), "payload": sha(physicalDecoded.payload), "evidence": sha(evidenceBytes), "inspectionRecord": sha(record),
                   "publicationRecord": sha(publicationBytes), "publicKey": sha(try bytes(publicKey))],
        "consumer": ["now": issued, "osVersion": osVersion, "osVersionSource": "inspection-record.json evidence.osVersion",
                     "installedVersionPolicyInput": Sample.installed, "installedFirefoxObserved": false, "sequence": candidate.sequence,
                     "origin": candidate.origin, "freshOSValidation": candidate.freshOSValidation,
                     "installationAuthorized": candidate.installationAuthorized, "selectsCompiledPin": true]]
}

func runLiveCatalogueProof(version: String, path: String) -> Int32 {
    guard version == LiveProof.version, path == LiveProof.approvedSource else {
        print("REFUSED live catalogue proof: only \(LiveProof.version) at the one approved preserved path is accepted. Nothing was read or written.")
        return 2
    }
    let layout: Layout
    do {
        let build = try buildDirectory(), id = UUID().uuidString
        layout = Layout(build: build, root: build.appendingPathComponent("patched-operator-fixture-\(id)"),
                        scratch: build.appendingPathComponent("patched-operator-live-proof-\(id)"))
        try makeDirectory(layout.scratch)
    } catch { print("FAIL live catalogue proof: no owned proof directory: \(error)"); return 1 }
    // Both directories are kept for the parent's inspection whatever happens. Nothing is cleaned up.
    let log = ProofLog()
    var record: [String: Any] = [
        "kind": "patched-operator-live-catalogue-proof-v1", "version": LiveProof.version, "operatorRoot": layout.root.path,
        "proofDirectory": layout.scratch.path,
        "scope": "Local test-key catalogue only. Not an installation, a product release, a production key or a production publication.",
        "testKeyOnly": true, "productionKey": false, "productionPublication": false, "installationAuthorized": false, "installedFirefoxProof": false]
    do {
        for (key, value) in try liveCatalogueProof(layout, log) { record[key] = value }
        record["accepted"] = true; record["orderedSteps"] = log.steps; record["children"] = log.children
        let proof = layout.scratch.appendingPathComponent("proof.json")
        try writeFile(try json(record), proof)
        print("PASS live catalogue proof \(LiveProof.version): verified before signing, test-key catalogue published and consumed. " +
              "No installation, release or production key. Retained: \(proof.path)")
        return 0
    } catch {
        record["accepted"] = false; record["failure"] = "\(error)"; record["orderedSteps"] = log.steps; record["children"] = log.children
        let failure = layout.scratch.appendingPathComponent("failure.json")
        let written = (try? writeFile(try json(record), failure)) != nil
        print("FAIL live catalogue proof \(LiveProof.version) after \(log.steps.count) steps: \(error). No proof accepted. " +
              "Retained: \(written ? failure.path : layout.scratch.path)")
        return 1
    }
}
