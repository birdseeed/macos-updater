import Foundation
import CryptoKit
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// The publish step. Acceptance is judged from the bytes physically on disk: the exact
// signed envelope, its separate digest-linked evidence, and what the real consumer and
// an independent CryptoKit check make of them. Nothing here trusts a returned report alone.

let publishBoundaries: [OperatorBoundary] = [
    .pendingCreated, .inspectionRecordWritten, .evidenceWritten, .catalogueWritten, .publicationRecordWritten,
    .pendingFilesSynced, .pendingDirectorySynced, .beforePublicationRename, .publicationRenamed, .publicationsSynced]
let publishSyncs: [OperatorSyncOperation] = [.publicationFileSync, .publicationFileFullSync, .pendingDirectorySync, .publicationsDirectorySync]
let committedBoundaries: Set<OperatorBoundary> = [.publicationRenamed, .publicationsSynced]

/// Reads one publication directory independently and checks every documented file, mode and digest link.
func expectCompletePublication(_ layout: Layout, sequence: UInt64, envelope: Data, request: CatalogueRequest,
                               receipt: VerifiedArtifactReceipt) throws {
    let directory = layout.publication(sequence)
    try expectPrivateDirectory(directory, "Publication directory")
    try expect(try names(directory) == publicationFiles, "Publication entries differ: \(try names(directory).sorted())")
    for name in publicationFiles { try expectPrivateFile(directory.appendingPathComponent(name), name) }
    let catalogue = try bytes(directory.appendingPathComponent("catalogue.json"))
    try expect(catalogue == envelope, "Published catalogue is not the exact signed bytes")
    let decoded = try verifyIndependently(catalogue, request: request, version: receipt.version)

    let record = try bytes(directory.appendingPathComponent("inspection-record.json"))
    try expect(sha(record) == receipt.inspectionRecordSHA256 && record.count == receipt.inspectionRecordByteLength,
               "Published inspection record is not the record the receipt bound")
    let inspection = try object(record)
    try expect(inspection["kind"] as? String == "patched-operator-fixture-inspection-v1" && inspection["origin"] as? String == "fixture" &&
               flag(inspection["freshOSValidation"]) == false && flag(inspection["installationAuthorized"]) == false &&
               inspection["sha256"] as? String == sha(Sample.artifact) && unsigned(inspection["byteLength"]) == UInt64(Sample.artifact.count) &&
               inspection["version"] as? String == receipt.version, "Fixture inspection record is not honestly labelled: \(inspection)")

    let evidenceBytes = try bytes(directory.appendingPathComponent("evidence.json"))
    try expect(evidenceBytes.count <= OperatorLimits.maximumEvidenceBytes, "Evidence exceeds its bound")
    let evidence = try object(evidenceBytes)
    try expect(Set(evidence.keys) == ["schemaVersion", "kind", "receiptOrigin", "catalogueOrigin", "version", "bundleID", "teamID", "sha256", "byteLength",
                                      "byteIntegrityVerified", "appChecksPassed", "containerSignaturePassed", "containerGatekeeperPassed",
                                      "containerTicketPassed", "cleanupVerified", "freshOSValidation", "inspectionRecordSHA256",
                                      "inspectionRecordByteLength", "installationAuthorized", "productionPublication"],
               "Evidence fields differ: \(evidence.keys.sorted())")
    try expect(unsigned(evidence["schemaVersion"]) == 1 && evidence["kind"] as? String == "patched-operator-evidence-v1" &&
               evidence["receiptOrigin"] as? String == "fixture" && evidence["catalogueOrigin"] as? String == "fixture", "Evidence origin is not fixture")
    try expect(evidence["version"] as? String == receipt.version && evidence["bundleID"] as? String == Sample.bundleID &&
               evidence["teamID"] as? String == Sample.teamID && evidence["sha256"] as? String == sha(Sample.artifact) &&
               unsigned(evidence["byteLength"]) == UInt64(Sample.artifact.count), "Evidence identity differs from the verified artifact")
    try expect(flag(evidence["byteIntegrityVerified"]) == true && flag(evidence["appChecksPassed"]) == false &&
               flag(evidence["containerSignaturePassed"]) == false && flag(evidence["containerGatekeeperPassed"]) == false &&
               flag(evidence["containerTicketPassed"]) == false && flag(evidence["cleanupVerified"]) == false &&
               flag(evidence["freshOSValidation"]) == false && flag(evidence["installationAuthorized"]) == false &&
               flag(evidence["productionPublication"]) == false, "Fixture evidence asserted a macOS check, installation authority or production")
    try expect(evidence["inspectionRecordSHA256"] as? String == sha(record) && unsigned(evidence["inspectionRecordByteLength"]) == UInt64(record.count),
               "Evidence is not digest-linked to the inspection record")

    let publication = try object(bytes(directory.appendingPathComponent("publication.json")))
    try expect(Set(publication.keys) == ["schemaVersion", "kind", "keyID", "catalogueID", "sequence", "catalogueSHA256", "catalogueByteLength",
                                         "payloadSHA256", "evidenceSHA256", "inspectionRecordSHA256", "origin", "installationAuthorized",
                                         "productionPublication"], "Publication record fields differ: \(publication.keys.sorted())")
    try expect(unsigned(publication["schemaVersion"]) == 1 && publication["kind"] as? String == "patched-operator-publication-v1" &&
               publication["keyID"] as? String == Sample.keyID && publication["catalogueID"] as? String == Sample.catalogueID &&
               unsigned(publication["sequence"]) == sequence && publication["origin"] as? String == "fixture" &&
               flag(publication["installationAuthorized"]) == false && flag(publication["productionPublication"]) == false,
               "Publication record identity or scope differs: \(publication)")
    try expect(publication["catalogueSHA256"] as? String == sha(catalogue) && unsigned(publication["catalogueByteLength"]) == UInt64(catalogue.count) &&
               publication["payloadSHA256"] as? String == sha(decoded.payload) && publication["evidenceSHA256"] as? String == sha(evidenceBytes) &&
               publication["inspectionRecordSHA256"] as? String == sha(record), "Publication record is not digest-linked to the files beside it")
    try expect(!exists(layout.pending(sequence)), "A pending directory remains beside an accepted publication")
}
func expectFixtureOnly(_ published: PublishedCatalogue) throws {
    try expect(published.origin == "fixture" && published.receiptOrigin == .fixture && !published.freshOSValidation &&
               !published.installationAuthorized && !published.productionPublication, "Published result asserted trust, installation or production")
    let encoded = try object(JSONEncoder().encode(published))
    try expect(encoded["origin"] as? String == "fixture" && flag(encoded["freshOSValidation"]) == false &&
               flag(encoded["installationAuthorized"]) == false && flag(encoded["productionPublication"]) == false,
               "Encoded published result lost its explicit no-trust fields")
}

@MainActor func registerPublicationChecks() {
    check("publish: the committed directory holds the exact signed bytes and separate digest-linked fixture evidence") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request()
            let catalogue = try authority.sign(receipt: receipt, request: request, now: Sample.now, signer: Sample.signer)
            let inputBefore = try snapshot(layout.input), scratchBefore = try snapshot(layout.scratch), checkpointBefore = try bytes(layout.checkpoint)
            let published = try authority.publish(catalogue, now: Sample.now)
            try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: request, receipt: receipt)
            try expectFixtureOnly(published)
            let directory = layout.publication(7)
            try expect(published.publicationPath == directory.path && published.cataloguePath == directory.appendingPathComponent("catalogue.json").path &&
                       published.evidencePath == directory.appendingPathComponent("evidence.json").path &&
                       published.inspectionRecordPath == directory.appendingPathComponent("inspection-record.json").path &&
                       published.publicationRecordPath == directory.appendingPathComponent("publication.json").path, "Reported paths are not the physical files")
            try expect(published.envelopeSHA256 == sha(catalogue.envelope) && published.envelopeByteLength == catalogue.envelope.count &&
                       published.payloadSHA256 == catalogue.payloadSHA256 && published.sequence == 7 && published.keyID == Sample.keyID &&
                       published.catalogueID == Sample.catalogueID &&
                       published.evidenceSHA256 == sha(try bytes(directory.appendingPathComponent("evidence.json"))) &&
                       published.inspectionRecordSHA256 == receipt.inspectionRecordSHA256, "Reported digests are not those of the physical files")
            try expect(try names(layout.publications) == ["sequence-7"] &&
                       names(layout.root) == ["namespace.json", "checkpoint.json", "lock", "input", "publications"], "Publishing left unexpected entries")
            try expect(try snapshot(layout.input) == inputBefore && snapshot(layout.scratch) == scratchBefore && bytes(layout.checkpoint) == checkpointBefore,
                       "Publishing changed the artifact, the high-water mark or something outside the root")
        }
    }
    check("publish: the real consumer accepts the physically published bytes as a fixture candidate and matches the artifact") {
        try withRoot { authority, layout in
            let catalogue = try signed(authority, layout)
            let published = try authority.publish(catalogue, now: Sample.now)
            let physical = try bytes(URL(fileURLWithPath: published.cataloguePath))
            let decoded = try verifyIndependently(physical, request: Sample.request())
            let candidate = try consumer(layout).bootstrapFreshProofNamespace(envelope: physical, now: Sample.now)
            try expectFixtureCandidate(candidate, sequence: 7, payload: decoded.payload)
            let consistency = try ArtifactVerifier.verify(path: layout.artifact.path, candidate: candidate)
            try expect(consistency.origin == "fixture" && !consistency.freshOSValidation && !consistency.installationAuthorized,
                       "Artifact consistency asserted OS validation or installation authority")
            // The fixture digest is not a compiled Firefox pin, so it can never select an inspection target.
            try consumerRefuses(.unapprovedArtifact) { _ = try ArtifactVerifier.approvedInspectionTarget(candidate: candidate) }
        }
    }
    check("publish: a consumer in a separate process reads the published file and accepts it as fixture only") {
        try withRoot { authority, layout in
            let published = try authority.publish(try signed(authority, layout), now: Sample.now)
            let (code, output) = try boundedChild(["--consumer-probe", "bootstrap", published.cataloguePath, layout.consumerState.path, layout.artifact.path])
            try expect(code == 0 && output.contains("sequence=7 \(noTrustSuffix) payloadSHA256=\(published.payloadSHA256) artifact=matched"),
                       "Separate-process consumer differs: \(output)")
        }
    }
    check("publish: the consumer refuses the published file after one byte of it is changed") {
        try withRoot { authority, layout in
            let published = try authority.publish(try signed(authority, layout), now: Sample.now)
            let physical = try bytes(URL(fileURLWithPath: published.cataloguePath))
            var fields = try object(physical)
            guard var payload = Data(base64Encoded: fields["payload"] as? String ?? "") else { throw CheckFailure(description: "No payload") }
            let digit = payload.firstIndex(of: UInt8(ascii: "7"))!
            payload[digit] = UInt8(ascii: "8"); fields["payload"] = payload.base64EncodedString()
            try consumerRefuses(.invalidSignature) { _ = try consumer(layout).bootstrapFreshProofNamespace(envelope: json(fields), now: Sample.now) }
            try consumerRefuses(.invalidSignature) {
                let other = FixtureTrust(keyID: Sample.keyID, catalogueID: Sample.catalogueID, publicKey: try Sample.key(true).publicKey.rawRepresentation)
                _ = try CatalogueVerifier(trust: other, policy: Sample.policy(), stateDirectory: layout.consumerState.path)
                    .bootstrapFreshProofNamespace(envelope: physical, now: Sample.now)
            }
            try consumerRefuses(.notNewer) {
                _ = try CatalogueVerifier(trust: Sample.trust(), policy: Sample.policy(installed: Sample.version), stateDirectory: layout.consumerState.path)
                    .bootstrapFreshProofNamespace(envelope: physical, now: Sample.now)
            }
            try expect(!exists(layout.consumerState), "A refused consumer created state")
        }
    }
    check("publish: publishing the same signed catalogue twice is refused and the first publication is untouched") {
        try withRoot { authority, layout in
            let catalogue = try signed(authority, layout)
            _ = try authority.publish(catalogue, now: Sample.now)
            let before = try snapshot(layout.root)
            try refuses(.existingOutput) { _ = try authority.publish(catalogue, now: Sample.now) }
            try refuses(.existingOutput) {
                _ = try FixtureOperatorAuthority.reopenRoot(path: layout.root.path, trust: Sample.trust()).publish(catalogue, now: Sample.now)
            }
            try expect(try snapshot(layout.root) == before, "A refused second publish changed the root")
        }
    }
    check("publish: a signature superseded by a later signature is refused as replay and writes nothing") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            let stale = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7), now: Sample.now, signer: Sample.signer)
            let current = try authority.sign(receipt: receipt, request: Sample.request(sequence: 8), now: Sample.now, signer: Sample.signer)
            try refuses(.replay) { _ = try authority.publish(stale, now: Sample.now) }
            try expect(try names(layout.publications).isEmpty, "A superseded signature was published")
            _ = try authority.publish(current, now: Sample.now)
            try expectCompletePublication(layout, sequence: 8, envelope: current.envelope, request: Sample.request(sequence: 8), receipt: receipt)
            try refuses(.replay) { _ = try authority.publish(stale, now: Sample.now) }
            try expect(try names(layout.publications) == ["sequence-8"], "A superseded signature was published")
        }
    }
    let clocks: [(String, OperatorFailure, Double)] = [
        ("at the expiry", .expired, Sample.now + 3_600), ("after the expiry", .expired, Sample.now + 86_400),
        ("with a clock that is not a number", .invalidClock, .nan), ("with a negative clock", .invalidClock, -1),
        ("with a clock of 2^53", .invalidClock, 9_007_199_254_740_992), ("more than 300 seconds before issue", .futureIssued, Sample.now - 301)]
    for (name, reason, now) in clocks {
        check("publish: publishing \(name) is refused as \(reason.rawValue) and writes nothing") {
            try withRoot { authority, layout in
                let catalogue = try signed(authority, layout)
                try refuses(reason) { _ = try authority.publish(catalogue, now: now) }
                try expect(try names(layout.publications).isEmpty, "A refused publish wrote output")
            }
        }
    }
    for (name, reason, mutate) in evidenceMutations {
        check("publish: an artifact \(name) after signing is refused as \(reason.rawValue) and writes nothing") {
            try withRoot { authority, layout in
                let catalogue = try signed(authority, layout)
                try mutate(layout)
                try refuses(reason) { _ = try authority.publish(catalogue, now: Sample.now) }
                try expect(try names(layout.publications).isEmpty, "Changed evidence was published")
            }
        }
    }
    let disturbed: [(String, OperatorFailure, @Sendable (Layout) throws -> Void)] = [
        ("an existing empty publication directory", .existingOutput, { try makeDirectory($0.publication(7)) }),
        ("an existing pending directory", .existingOutput, { try makeDirectory($0.pending(7)) }),
        ("an existing file at the publication name", .existingOutput, { try writeFile(Data("x".utf8), $0.publication(7)) }),
        ("a symlink at the publication name", .existingOutput, { layout in
            let elsewhere = layout.scratch.appendingPathComponent("elsewhere"); try makeDirectory(elsewhere)
            try expect(symlink(elsewhere.path, layout.publication(7).path) == 0, "Fixture symlink failed") }),
        ("the publications directory replaced by a symlink", .unsafePath, { layout in
            let elsewhere = layout.scratch.appendingPathComponent("elsewhere"); try makeDirectory(elsewhere)
            try expect(rmdir(layout.publications.path) == 0 && symlink(elsewhere.path, layout.publications.path) == 0, "Fixture symlink failed") }),
        ("the publications directory replaced by a new directory", .identityChanged, { layout in
            try expect(rmdir(layout.publications.path) == 0, "Fixture rmdir failed"); try makeDirectory(layout.publications) }),
        ("a group-writable publications directory", .unsafeMode, { try expect(chmod($0.publications.path, 0o770) == 0, "Fixture chmod failed") }),
        ("the root renamed and an identical copy put at its name", .identityChanged, { layout in
            let moved = layout.scratch.appendingPathComponent("moved-root")
            try expect(rename(layout.root.path, moved.path) == 0, "Fixture rename failed")
            try FileManager.default.copyItem(at: moved, to: layout.root) }),
        ("the checkpoint removed", .missingState, { try FileManager.default.removeItem(at: $0.checkpoint) }),
        ("the checkpoint rewritten for another payload", .replay, { layout in
            var fields = try object(bytes(layout.checkpoint)); fields["payloadSHA256"] = String(repeating: "a", count: 64)
            try json(fields).write(to: layout.checkpoint) }),
        ("the checkpoint rewritten to a higher sequence", .replay, { layout in
            var fields = try object(bytes(layout.checkpoint)); fields["sequence"] = 8
            try json(fields).write(to: layout.checkpoint) }),
        ("the namespace record rewritten for another key", .untrustedKey, { layout in
            var fields = try object(bytes(layout.namespace)); fields["keyID"] = "another-key"
            try json(fields).write(to: layout.namespace) }),
        ("the namespace record rewritten for another catalogue", .wrongCatalogue, { layout in
            var fields = try object(bytes(layout.namespace)); fields["catalogueID"] = "another.catalogue"
            try json(fields).write(to: layout.namespace) })]
    for (name, reason, disturb) in disturbed {
        check("publish: \(name) is refused as \(reason.rawValue), with nothing overwritten, healed or written elsewhere") {
            try withRoot { authority, layout in
                let catalogue = try signed(authority, layout)
                try disturb(layout)
                let before = try snapshot(layout.root), outside = try snapshot(layout.scratch)
                try refuses(reason) { _ = try authority.publish(catalogue, now: Sample.now) }
                try expect(try snapshot(layout.root) == before && snapshot(layout.scratch) == outside, "A refused publish wrote, repaired or removed something")
            }
        }
    }
    check("publish: another process holding the root lock makes publishing refuse as busy") {
        try withRoot { authority, layout in
            let catalogue = try signed(authority, layout)
            let descriptor = open(layout.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            try expect(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Fixture could not hold the lock")
            try refuses(.busy) { _ = try authority.publish(catalogue, now: Sample.now) }
            try expect(try names(layout.publications).isEmpty, "A refused publish wrote output")
            try expect(flock(descriptor, LOCK_UN) == 0 && close(descriptor) == 0, "Fixture could not release the lock")
            _ = try authority.publish(catalogue, now: Sample.now)
            try expect(try names(layout.publications) == ["sequence-7"], "Publish after release differs")
        }
    }

    for boundary in publishBoundaries {
        check("publish fault at \(boundary.rawValue): no accepted result, partial files never under the accepted name, evidence kept") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                let catalogue = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
                var seen = 0
                try refuses(.persistenceFailed) {
                    _ = try authority.publish(catalogue, now: Sample.now, hooks: OperatorHooks(boundary: { if $0 == boundary { seen += 1; throw Injected() } }))
                }
                try expect(seen == 1, "Publishing continued past a refused \(boundary.rawValue)")
                if committedBoundaries.contains(boundary) {
                    // The rename already happened: whatever has the accepted name must be the complete publication.
                    try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: Sample.request(), receipt: receipt)
                } else {
                    try expect(!exists(layout.publication(7)), "An interrupted publish left files under the accepted name")
                    try expectPrivateDirectory(layout.pending(7), "Preserved pending directory")
                    try expect(try names(layout.pending(7)).isSubset(of: publicationFiles), "Pending directory holds unexpected entries")
                }
                // The outcome is uncertain evidence. It is never cleaned up, completed or overwritten by a retry.
                let before = try snapshot(layout.root)
                try refuses(.existingOutput) {
                    _ = try FixtureOperatorAuthority.reopenRoot(path: layout.root.path, trust: Sample.trust()).publish(catalogue, now: Sample.now)
                }
                try expect(try snapshot(layout.root) == before, "A retry changed the preserved evidence")
            }
        }
    }
    for operation in publishSyncs {
        check("publish refused \(operation.rawValue): no weaker flush and no accepted result") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                let catalogue = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
                var refused = 0
                try refuses(.persistenceFailed) {
                    _ = try authority.publish(catalogue, now: Sample.now, hooks: OperatorHooks(sync: { if $0 == operation { refused += 1; throw Injected() } }))
                }
                try expect(refused == 1, "Publishing continued after a refused \(operation.rawValue)")
                if exists(layout.publication(7)) {
                    try expect(operation == .publicationsDirectorySync, "A publication was committed before \(operation.rawValue) succeeded")
                    try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: Sample.request(), receipt: receipt)
                } else {
                    try expectPrivateDirectory(layout.pending(7), "Preserved pending directory")
                }
            }
        }
    }
    check("publish: a hook that only observes sees every publishing boundary once, in order, and each flush kind") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            let catalogue = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
            var boundaries: [OperatorBoundary] = [], syncs: [OperatorSyncOperation] = []
            _ = try authority.publish(catalogue, now: Sample.now, hooks: OperatorHooks(boundary: { boundaries.append($0) }, sync: { syncs.append($0) }))
            try expect(boundaries == publishBoundaries, "Publishing boundaries differ: \(boundaries.map(\.rawValue))")
            // One file sync and one full sync for each of the four files, then each directory once.
            try expect(syncs.filter { $0 == .publicationFileSync }.count == 4 && syncs.filter { $0 == .publicationFileFullSync }.count == 4 &&
                       syncs.filter { $0 == .pendingDirectorySync }.count == 1 && syncs.last == .publicationsDirectorySync && syncs.count == 10,
                       "Publishing flushes differ: \(syncs.map(\.rawValue))")
            try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: Sample.request(), receipt: receipt)
        }
    }

    check("restart: a separate operator process keeps the high-water mark, refuses rollback and publishes the next sequence") {
        try withRoot { authority, layout in
            let first = try authority.publish(try signed(authority, layout, sequence: 8), now: Sample.now)
            let firstBytes = try bytes(URL(fileURLWithPath: first.cataloguePath))
            _ = try consumer(layout).bootstrapFreshProofNamespace(envelope: firstBytes, now: Sample.now)
            let (code, output) = try boundedChild(["--restart-probe", layout.root.path])
            try expect(code == 0 && output.contains("rollback=replay equal=replay published=9 \(noTrustSuffix)"), "Separate-process operator differs: \(output)")
            try expect(try names(layout.publications) == ["sequence-8", "sequence-9"] && checkpointFields(layout).sequence == 9,
                       "Physical state after restart differs")
            try expect(try bytes(URL(fileURLWithPath: first.cataloguePath)) == firstBytes, "An earlier publication was rewritten")
            let second = try bytes(layout.catalogue(9))
            let decoded = try verifyIndependently(second, request: Sample.request(sequence: 9))
            try expect(try checkpointFields(layout).payloadSHA256 == sha(decoded.payload), "High-water mark does not hash the published payload")
            // The consumer's own durable state moves forward on the new file and refuses the old one.
            let (verified, consumerOutput) = try boundedChild(["--consumer-probe", "verify", layout.catalogue(9).path, layout.consumerState.path, layout.artifact.path])
            try expect(verified == 0 && consumerOutput.contains("sequence=9 \(noTrustSuffix)"), "Consumer did not advance on the next publication: \(consumerOutput)")
            try consumerRefuses(.replay) { _ = try consumer(layout).verify(envelope: firstBytes, now: Sample.now) }
            let (replayed, replayOutput) = try boundedChild(["--consumer-probe", "verify", first.cataloguePath, layout.consumerState.path, layout.artifact.path])
            try expect(replayed == 1 && replayOutput.contains("refused=replay"), "Separate-process consumer accepted a rollback: \(replayOutput)")
        }
    }
    check("restart: a fresh consumer namespace is needed once; ordinary verification never creates one") {
        try withRoot { authority, layout in
            let published = try authority.publish(try signed(authority, layout), now: Sample.now)
            let (code, output) = try boundedChild(["--consumer-probe", "verify", published.cataloguePath, layout.consumerState.path, layout.artifact.path])
            try expect(code == 1 && output.contains("refused=missingState") && !exists(layout.consumerState), "Ordinary consumer verification healed missing state: \(output)")
        }
    }
}
