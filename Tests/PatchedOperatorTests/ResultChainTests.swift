import Foundation
import CryptoKit
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// Regressions for the result chain of the operator surface. A configured callback is untrusted
// code: it can ignore its argument and hand back a result that is real and valid but belongs
// to another root or to an earlier verification. The controller must hold a signed result only
// when it came from the receipt it currently holds, and a published result only when it
// matches the signed catalogue it currently holds.
//
// Every receipt, signed catalogue and publication here is the output of a real fixture step
// on a real root beneath .build. Nothing is constructed, decoded or simulated, and no root
// other than the controller's own is written after its results were taken.

let resultChainPrefix = "result chain: "
let invalidStateReason = "That step is not available at this stage."
let fixtureArtifactLine = "Artifact: \(Sample.artifactName)"

/// The public record of one receipt, as the library itself encodes it.
func encodedReceipt(_ receipt: VerifiedArtifactReceipt) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(receipt)
}

@MainActor func registerResultChainChecks() {
    check(resultChainPrefix + "control: results that follow from one another are held, each callback runs once and the publication is complete") {
        try withRoot { authority, layout in
            let counts = Counts()
            var receipts: [VerifiedArtifactReceipt] = [], catalogues: [SignedCatalogue] = [], publications: [PublishedCatalogue] = []
            var configuration = wired(authority, layout, counts)
            configuration.verify = { counts.verify += 1; let receipt = try fixtureReceipt(authority, layout); receipts.append(receipt); return receipt }
            configuration.sign = {
                counts.sign += 1
                let catalogue = try authority.sign(receipt: $0, request: Sample.request(), now: Sample.now, signer: Sample.signer)
                catalogues.append(catalogue); return catalogue
            }
            configuration.publish = { counts.publish += 1; let result = try authority.publish($0, now: Sample.now); publications.append(result); return result }
            let controller = OperatorController(configuration)
            try expect(counts.all == [0, 0, 0], "A step ran when the controller was created: \(counts.all)")
            controller.choose(.verify); controller.choose(.sign); controller.choose(.publish)
            try expect(counts.all == [1, 1, 1], "Each step should run once on its own choice: \(counts.all)")
            try expectFrame(controller.text, artifact: fixtureArtifactLine)
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, signedStatus, enabled: true),
                                                  row(.publish, publishedStatus, enabled: true)], "Chained steps differ: \(lines(controller.text))")
            try expect(receipts.count == 1 && catalogues.count == 1 && publications.count == 1, "A callback returned more than one result")
            try expect(try names(layout.publications) == ["sequence-7"] && publications[0].publicationPath == layout.publication(7).path,
                       "The publication is not the one physical directory of this root")
            try expectCompletePublication(layout, sequence: 7, envelope: catalogues[0].envelope, request: Sample.request(), receipt: receipts[0])
            let physical = try bytes(layout.catalogue(7))
            try expect(sha(physical) == publications[0].envelopeSHA256 && publications[0].inspectionRecordSHA256 == receipts[0].inspectionRecordSHA256,
                       "The reported publication is not linked to the held catalogue and receipt")
            let decoded = try verifyIndependently(physical, request: Sample.request())
            try expectFixtureCandidate(try consumer(layout).bootstrapFreshProofNamespace(envelope: physical, now: Sample.now), sequence: 7, payload: decoded.payload)
        }
    }
    check(resultChainPrefix + "a signed result from another root's receipt is refused at Sign and Publish stays locked") {
        try withRoot { otherAuthority, otherLayout in
            // A real receipt and a real signed catalogue of a second root, for the same bytes, version and request.
            let otherReceipt = try fixtureReceipt(otherAuthority, otherLayout)
            let foreign = try otherAuthority.sign(receipt: otherReceipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
            let otherBefore = try snapshot(otherLayout.root)
            try withRoot { authority, layout in
                let counts = Counts()
                var receipts: [VerifiedArtifactReceipt] = []
                var configuration = wired(authority, layout, counts)
                configuration.verify = { counts.verify += 1; let receipt = try fixtureReceipt(authority, layout); receipts.append(receipt); return receipt }
                configuration.sign = { _ in counts.sign += 1; return foreign }
                let controller = OperatorController(configuration)
                controller.choose(.verify)
                try expect(counts.all == [1, 0, 0] && receipts.count == 1, "Choosing Verify ran \(counts.all)")
                let verified = controller.text
                try expectFrame(verified, artifact: fixtureArtifactLine)
                // The two results differ only in the root and the verification record they came from.
                try expect(receipts[0].sha256 == otherReceipt.sha256 && receipts[0].version == otherReceipt.version &&
                           receipts[0].artifactPath == layout.artifact.path && otherReceipt.artifactPath == otherLayout.artifact.path &&
                           receipts[0].artifactPath != otherReceipt.artifactPath, "The two receipts are not the same bytes verified in two roots")
                try expect(foreign.inspectionRecordSHA256 == otherReceipt.inspectionRecordSHA256 &&
                           foreign.inspectionRecordSHA256 != receipts[0].inspectionRecordSHA256, "The signed result is not linked to the other root's record alone")
                let before = try snapshot(layout.root)
                controller.choose(.sign)
                let afterSign = lines(controller.text)
                controller.choose(.publish)
                try expect(afterSign == [row(.verify, verifiedStatus, enabled: true), row(.sign, refusedStatus, enabled: true, invalidStateReason),
                                         row(.publish, notRun, enabled: false, signFirst)],
                           "IMPROPER ACCEPTANCE: a signed result from another root's receipt completed Sign: \(afterSign)")
                try expect(counts.all == [1, 1, 0], "Steps ran \(counts.all) after the unrelated signed result")
                try expect(lines(controller.text) == afterSign && controller.text.artifactLine == verified.artifactLine &&
                           controller.text.rows.first == verified.rows.first, "Choosing the locked Publish changed the surface: \(lines(controller.text))")
                try expect(!words(controller.text).contains(signedStatus) && !words(controller.text).contains(publishedStatus), "A later step reads as done")
                try expect(try snapshot(layout.root) == before && checkpointFields(layout).sequence == 0 && names(layout.publications).isEmpty,
                           "The controller's own root was signed, published or changed")
            }
            try expect(try snapshot(otherLayout.root) == otherBefore, "The other root was changed")
        }
    }
    check(resultChainPrefix + "a published result from another root is refused at Publish and the signed catalogue stays unpublished") {
        try withRoot { otherAuthority, otherLayout in
            // A real publication of a second root, for the same bytes, version and request.
            let otherReceipt = try fixtureReceipt(otherAuthority, otherLayout)
            let otherSigned = try otherAuthority.sign(receipt: otherReceipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
            let foreign = try otherAuthority.publish(otherSigned, now: Sample.now)
            let otherBefore = try snapshot(otherLayout.root)
            try withRoot { authority, layout in
                let counts = Counts()
                var receipts: [VerifiedArtifactReceipt] = [], catalogues: [SignedCatalogue] = []
                var configuration = wired(authority, layout, counts)
                configuration.verify = { counts.verify += 1; let receipt = try fixtureReceipt(authority, layout); receipts.append(receipt); return receipt }
                configuration.sign = {
                    counts.sign += 1
                    let catalogue = try authority.sign(receipt: $0, request: Sample.request(), now: Sample.now, signer: Sample.signer)
                    catalogues.append(catalogue); return catalogue
                }
                configuration.publish = { _ in counts.publish += 1; return foreign }
                let controller = OperatorController(configuration)
                controller.choose(.verify); controller.choose(.sign)
                try expect(counts.all == [1, 1, 0] && receipts.count == 1 && catalogues.count == 1, "Verify and Sign ran \(counts.all)")
                let signedLines = [row(.verify, verifiedStatus, enabled: true), row(.sign, signedStatus, enabled: true), row(.publish, notRun, enabled: true)]
                try expect(lines(controller.text) == signedLines, "Signed steps differ: \(lines(controller.text))")
                // The same request over the same artifact gives the same payload in both roots, so the payload
                // digest cannot tell the two apart. The path and the inspection record link can.
                try expect(foreign.payloadSHA256 == catalogues[0].payloadSHA256 && foreign.sequence == catalogues[0].sequence &&
                           foreign.keyID == catalogues[0].keyID && foreign.catalogueID == catalogues[0].catalogueID,
                           "The other root's publication is not for the same payload")
                try expect(foreign.publicationPath == otherLayout.publication(7).path && foreign.publicationPath != layout.publication(7).path &&
                           foreign.inspectionRecordSHA256 == otherReceipt.inspectionRecordSHA256 &&
                           foreign.inspectionRecordSHA256 != catalogues[0].inspectionRecordSHA256 &&
                           catalogues[0].inspectionRecordSHA256 == receipts[0].inspectionRecordSHA256,
                           "The other root's publication is not told apart by its path and inspection record link")
                let before = try snapshot(layout.root)
                controller.choose(.publish)
                try expect(counts.all == [1, 1, 1], "Steps ran \(counts.all) for one Publish choice")
                try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, signedStatus, enabled: true),
                                                      row(.publish, refusedStatus, enabled: true, invalidStateReason)],
                           "IMPROPER ACCEPTANCE: a published result from another root completed Publish: \(lines(controller.text))")
                try expectFrame(controller.text, artifact: fixtureArtifactLine)
                try expect(!words(controller.text).contains(publishedStatus), "Publish reads as done")
                try expect(try snapshot(layout.root) == before && names(layout.publications).isEmpty && checkpointFields(layout).sequence == 7,
                           "The controller's own root was published or changed")
            }
            try expect(try snapshot(otherLayout.root) == otherBefore, "The other root was changed")
        }
    }
    check(resultChainPrefix + "a signed result of an earlier verification is refused after verifying again and is not revived") {
        try withRoot { authority, layout in
            let counts = Counts()
            var receipts: [VerifiedArtifactReceipt] = [], earlier: SignedCatalogue?
            var configuration = wired(authority, layout, counts)
            configuration.verify = { counts.verify += 1; let receipt = try fixtureReceipt(authority, layout); receipts.append(receipt); return receipt }
            configuration.sign = {
                counts.sign += 1
                // The first choice really signs the receipt it is given. Every later one hands back that first result.
                if let earlier { return earlier }
                let catalogue = try authority.sign(receipt: $0, request: Sample.request(), now: Sample.now, signer: Sample.signer)
                earlier = catalogue
                return catalogue
            }
            let controller = OperatorController(configuration)
            controller.choose(.verify); controller.choose(.sign)
            try expect(counts.all == [1, 1, 0] && earlier != nil, "First Verify and Sign ran \(counts.all)")
            try expect(lines(controller.text) == [row(.verify, verifiedStatus, enabled: true), row(.sign, signedStatus, enabled: true),
                                                  row(.publish, notRun, enabled: true)], "First signed steps differ: \(lines(controller.text))")
            controller.choose(.verify)
            try expect(counts.all == [2, 1, 0] && receipts.count == 2, "Verifying again ran \(counts.all)")
            let reverified = [row(.verify, verifiedStatus, enabled: true), row(.sign, notRun, enabled: true), row(.publish, notRun, enabled: false, signFirst)]
            try expect(lines(controller.text) == reverified, "Verifying again did not clear the later steps: \(lines(controller.text))")
            // Nothing on disk changed, so the two real receipts carry the same public record. Only which
            // verification issued each one tells them apart.
            try expect(try encodedReceipt(receipts[0]) == encodedReceipt(receipts[1]) && receipts[1].artifactPath == layout.artifact.path,
                       "The second receipt does not carry the same record as the first")
            let before = try snapshot(layout.root)
            controller.choose(.sign)
            let afterSign = lines(controller.text)
            controller.choose(.publish)
            try expect(afterSign == [row(.verify, verifiedStatus, enabled: true), row(.sign, refusedStatus, enabled: true, invalidStateReason),
                                     row(.publish, notRun, enabled: false, signFirst)],
                       "IMPROPER ACCEPTANCE: the signed result of an earlier verification completed Sign again: \(afterSign)")
            try expect(counts.all == [2, 2, 0], "Steps ran \(counts.all) after the earlier signed result")
            try expect(lines(controller.text) == afterSign, "Choosing the locked Publish changed the surface: \(lines(controller.text))")
            try expectFrame(controller.text, artifact: fixtureArtifactLine)
            try expect(!words(controller.text).contains(signedStatus) && !words(controller.text).contains(publishedStatus), "A later step reads as done")
            try expect(try snapshot(layout.root) == before && checkpointFields(layout).sequence == 7 && names(layout.publications).isEmpty,
                       "The root was signed again, published or changed")
            // The second receipt is a real one: the authority itself signs it at the next number.
            let next = try authority.sign(receipt: receipts[1], request: Sample.request(sequence: 8), now: Sample.now, signer: Sample.signer)
            try expect(next.sequence == 8 && next.inspectionRecordSHA256 == receipts[1].inspectionRecordSHA256, "The second receipt was not signed by its own root")
        }
    }
}

@MainActor func runResultChainRegressions(_ registered: [(String, @MainActor () throws -> Void)]) -> Int32 {
    let selected = registered.filter { $0.0.hasPrefix(resultChainPrefix) }
    var failures = 0
    for (name, action) in selected {
        do { try action(); print("PASS operator: \(name)") }
        catch { failures += 1; print("FAIL operator: \(name): \(error)") }
    }
    print("Result chain regressions: \(selected.count) cases, \(failures) failures. Fixture trust only. No production key, publication, fresh OS trust or installation authority.")
    return failures == 0 ? 0 : 1
}
