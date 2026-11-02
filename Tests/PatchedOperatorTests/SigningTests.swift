import Foundation
import CryptoKit
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// The sign step. The library builds the payload, hands the exact message to the test
// target's signer and must verify the answer against the root's public fixture trust.
// Signing advances the durable high-water mark and writes no published file.

func expectUnsigned(_ layout: Layout, sequence: UInt64 = 0, digest: String = Sample.zeroDigest) throws {
    let checkpoint = try checkpointFields(layout)
    try expect(checkpoint.sequence == sequence && checkpoint.payloadSHA256 == digest,
               "High-water mark moved to \(checkpoint.sequence) without an accepted signature")
    try expect(try names(layout.publications).isEmpty, "A refused or unpublished signature left an entry in publications")
    try expect(try names(layout.root) == ["namespace.json", "checkpoint.json", "lock", "input", "publications"],
               "Root holds unexpected entries: \(try names(layout.root).sorted())")
}
let signBoundaries: [OperatorBoundary] = [.checkpointTemporaryWritten, .checkpointFileSynced, .beforeCheckpointRename, .checkpointRenamed, .rootSynced]
let signSyncs: [OperatorSyncOperation] = [.checkpointFileSync, .checkpointFileFullSync, .rootDirectorySync, .committedCheckpointFullSync]

@MainActor func registerSigningChecks() {
    check("sign: the envelope verifies independently and carries exactly the documented schema") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request()
            let catalogue = try authority.sign(receipt: receipt, request: request, now: Sample.now, signer: Sample.signer)
            let decoded = try verifyIndependently(catalogue.envelope, request: request)
            try expect(catalogue.payloadSHA256 == sha(decoded.payload) && catalogue.envelopeSHA256 == sha(catalogue.envelope),
                       "Reported digests are not those of the signed bytes")
            try expect(catalogue.sequence == 7 && catalogue.keyID == Sample.keyID && catalogue.catalogueID == Sample.catalogueID,
                       "Signed result identity differs from the request")
            try expect(catalogue.origin == "fixture" && catalogue.receiptOrigin == .fixture && !catalogue.freshOSValidation &&
                       !catalogue.installationAuthorized && !catalogue.published, "Signed result asserted trust or publication")
            try expect(catalogue.inspectionRecordSHA256 == receipt.inspectionRecordSHA256, "Signed result is not linked to the receipt's inspection record")
            let encoded = try object(JSONEncoder().encode(catalogue))
            try expect(encoded["origin"] as? String == "fixture" && flag(encoded["freshOSValidation"]) == false &&
                       flag(encoded["installationAuthorized"]) == false && flag(encoded["published"]) == false,
                       "Encoded signed result lost its explicit no-trust fields")
        }
    }
    check("sign: the signer is asked once, for exactly the documented frame and the payload that is then enveloped") {
        try withRoot { authority, layout in
            var messages: [Data] = []
            let catalogue = try authority.sign(receipt: fixtureReceipt(authority, layout), request: Sample.request(), now: Sample.now) {
                messages.append($0); return try Sample.signer($0)
            }
            let decoded = try verifyIndependently(catalogue.envelope, request: Sample.request())
            try expect(messages == [Data((Sample.domain + "\0").utf8) + decoded.payload], "Signer saw \(messages.count) messages or a different message")
        }
    }
    check("sign: signing alone records the high-water mark durably and writes no published file") {
        try withRoot { authority, layout in
            let inputBefore = try snapshot(layout.input), scratchBefore = try snapshot(layout.scratch)
            let catalogue = try signed(authority, layout)
            try expectUnsigned(layout, sequence: 7, digest: catalogue.payloadSHA256)
            try expect(try snapshot(layout.input) == inputBefore && snapshot(layout.scratch) == scratchBefore, "Signing changed the artifact or wrote outside the root")
            let everything = try snapshot(layout.root)
            try expect(!everything.values.contains { $0.hasSuffix(sha(catalogue.envelope)) }, "Signing wrote the envelope bytes to disk")
        }
    }
    check("sign: the real consumer accepts the signed bytes as a fixture candidate only") {
        try withRoot { authority, layout in
            let catalogue = try signed(authority, layout)
            let decoded = try verifyIndependently(catalogue.envelope, request: Sample.request())
            let candidate = try consumer(layout).bootstrapFreshProofNamespace(envelope: catalogue.envelope, now: Sample.now)
            try expectFixtureCandidate(candidate, sequence: 7, payload: decoded.payload)
        }
    }

    let answers: [(String, @Sendable (Data) throws -> Data)] = [
        ("a signature from an unrelated key", { try Sample.key(true).signature(for: $0) }),
        ("a signature over the payload without the frame", { try Sample.key().signature(for: $0.dropFirst(Sample.domain.utf8.count + 1)) }),
        ("a signature over a different frame", { try Sample.key().signature(for: Data("im.patched.catalogue.v2\0".utf8) + $0.dropFirst(Sample.domain.utf8.count + 1)) }),
        ("a signature with one flipped bit", { var s = try Sample.signer($0); s[10] ^= 1; return s }),
        ("a 63-byte answer", { try Sample.signer($0).prefix(63) }),
        ("a 65-byte answer", { try Sample.signer($0) + Data([0]) }),
        ("an empty answer", { _ in Data() }),
        ("the message itself", { $0 }),
        ("64 zero bytes", { _ in Data(repeating: 0, count: 64) })]
    for (name, answer) in answers {
        check("sign: \(name) is refused as invalidSignature and nothing is recorded") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                var calls = 0
                try refuses(.invalidSignature) {
                    _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now) { calls += 1; return try answer($0) }
                }
                try expect(calls == 1, "Signer was asked \(calls) times")
                try expectUnsigned(layout)
                // The refusal burned nothing: the same sequence can still be signed correctly.
                let catalogue = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
                _ = try verifyIndependently(catalogue.envelope, request: Sample.request())
            }
        }
    }
    check("sign: a signer that throws is refused as signerFailed and nothing is recorded") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            try refuses(.signerFailed) {
                _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now) { _ in throw Injected() }
            }
            try expectUnsigned(layout)
        }
    }

    let maximumSecond: UInt64 = 9_007_199_254_740_991
    let requests: [(String, OperatorFailure, CatalogueRequest, Double)] = [
        ("another key identifier", .untrustedKey, Sample.request(keyID: "another-key"), Sample.now),
        ("another catalogue", .wrongCatalogue, Sample.request(catalogueID: "another.catalogue"), Sample.now),
        ("sequence zero", .invalidConfiguration, Sample.request(sequence: 0), Sample.now),
        ("an issue time above 2^53 minus 1", .invalidConfiguration, Sample.request(issuedAt: maximumSecond + 1, expiresAt: maximumSecond + 2), Sample.now),
        ("an expiry above 2^53 minus 1", .invalidConfiguration, Sample.request(issuedAt: maximumSecond, expiresAt: maximumSecond + 1), Double(maximumSecond)),
        ("the largest unsigned times", .invalidConfiguration, Sample.request(issuedAt: .max - 1, expiresAt: .max), Sample.now),
        ("an expiry equal to the issue time", .invalidLifetime, Sample.request(expiresAt: Sample.issued), Sample.now),
        ("an expiry before the issue time", .invalidLifetime, Sample.request(expiresAt: Sample.issued - 1), Sample.now),
        ("a lifetime one second over three days", .invalidLifetime, Sample.request(expiresAt: Sample.issued + 259_201), Sample.now),
        ("an issue time 301 seconds ahead", .futureIssued, Sample.request(issuedAt: Sample.issued + 301, expiresAt: Sample.issued + 3_600), Sample.now),
        ("an expiry equal to the clock", .expired, Sample.request(issuedAt: Sample.issued - 3_600, expiresAt: Sample.issued), Sample.now),
        ("an expiry in the past", .expired, Sample.request(issuedAt: Sample.issued - 7_200, expiresAt: Sample.issued - 3_600), Sample.now),
        ("a clock that is not a number", .invalidClock, Sample.request(), .nan),
        ("an infinite clock", .invalidClock, Sample.request(), .infinity),
        ("a negative clock", .invalidClock, Sample.request(), -1),
        ("a clock of 2^53", .invalidClock, Sample.request(), 9_007_199_254_740_992),
        ("a clock of 2^62", .invalidClock, Sample.request(), 4_611_686_018_427_387_904),
        ("the largest finite clock", .invalidClock, Sample.request(), .greatestFiniteMagnitude),
        ("an empty minimum OS", .invalidConfiguration, Sample.request(minimumOS: ""), Sample.now),
        ("a minimum OS with a leading zero", .invalidConfiguration, Sample.request(minimumOS: "013.0"), Sample.now),
        ("a maximum OS with letters", .invalidConfiguration, Sample.request(maximumOS: "27.x"), Sample.now),
        ("a maximum OS with nine components", .invalidConfiguration, Sample.request(maximumOS: "27.0.0.0.0.0.0.0.1"), Sample.now),
        ("an OS component above UInt32", .invalidConfiguration, Sample.request(maximumOS: "4294967296.0"), Sample.now),
        ("a reversed OS range", .invalidConfiguration, Sample.request(minimumOS: "28.0", maximumOS: "27.9"), Sample.now),
        ("a key identifier with a newline", .untrustedKey, Sample.request(keyID: Sample.keyID + "\n"), Sample.now)]
    for (name, reason, request, now) in requests {
        check("sign: \(name) is refused as \(reason.rawValue) before the signer is asked") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                var calls = 0
                try refuses(reason) { _ = try authority.sign(receipt: receipt, request: request, now: now) { calls += 1; return try Sample.signer($0) } }
                try expect(calls == 0, "Signer was asked to sign a refused request")
                try expectUnsigned(layout)
            }
        }
    }
    let accepted: [(String, CatalogueRequest, Double)] = [
        ("a lifetime of exactly three days", Sample.request(expiresAt: Sample.issued + 259_200), Sample.now),
        ("an issue time exactly 300 seconds ahead", Sample.request(issuedAt: Sample.issued + 300, expiresAt: Sample.issued + 3_600), Sample.now),
        ("an expiry one second after the clock", Sample.request(issuedAt: Sample.issued - 60, expiresAt: Sample.issued + 1), Sample.now),
        ("equal minimum and maximum OS", Sample.request(minimumOS: "27.0.1", maximumOS: "27.0.1"), Sample.now),
        ("the largest exact second", Sample.request(issuedAt: maximumSecond - 10, expiresAt: maximumSecond), Double(maximumSecond - 5))]
    for (name, request, now) in accepted {
        check("sign: \(name) is accepted by the operator and by the real consumer") {
            try withRoot { authority, layout in
                let catalogue = try authority.sign(receipt: fixtureReceipt(authority, layout), request: request, now: now, signer: Sample.signer)
                let decoded = try verifyIndependently(catalogue.envelope, request: request)
                try expectFixtureCandidate(try consumer(layout).bootstrapFreshProofNamespace(envelope: catalogue.envelope, now: now),
                                           sequence: 7, payload: decoded.payload)
            }
        }
    }
    check("sign: the largest sequence is written as an exact integer token") {
        try withRoot { authority, layout in
            let request = Sample.request(sequence: .max)
            let catalogue = try authority.sign(receipt: fixtureReceipt(authority, layout), request: request, now: Sample.now, signer: Sample.signer)
            let decoded = try verifyIndependently(catalogue.envelope, request: request)
            try expect(String(decoding: decoded.payload, as: UTF8.self).contains("18446744073709551615") && catalogue.sequence == .max,
                       "Largest sequence was rounded or reformatted")
            try expect(try consumer(layout).bootstrapFreshProofNamespace(envelope: catalogue.envelope, now: Sample.now).sequence == .max,
                       "Consumer read a different sequence")
            try expect(try checkpointFields(layout).sequence == .max, "High-water mark lost the exact sequence")
        }
    }

    check("sign: a lower sequence, or the same sequence with any other payload, is refused as replay") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            let first = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7), now: Sample.now, signer: Sample.signer)
            var calls = 0
            let counting: (Data) throws -> Data = { calls += 1; return try Sample.signer($0) }
            try refuses(.replay) { _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 6), now: Sample.now, signer: counting) }
            try refuses(.replay) { _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 1), now: Sample.now, signer: counting) }
            try refuses(.replay) {
                _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7, expiresAt: Sample.issued + 3_601), now: Sample.now, signer: counting)
            }
            try refuses(.replay) {
                _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7, maximumOS: "28.0"), now: Sample.now, signer: counting)
            }
            let older = try authority.fixtureReceipt(version: "157.0", artifactPath: layout.artifact.path)
            try refuses(.replay) { _ = try authority.sign(receipt: older, request: Sample.request(sequence: 7), now: Sample.now, signer: counting) }
            try expect(calls == 0, "Signer was asked to sign a replayed sequence")
            try expectUnsigned(layout, sequence: 7, digest: first.payloadSHA256)
        }
    }
    check("sign: the same sequence with the identical payload is accepted again, then a higher sequence advances") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            let first = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7), now: Sample.now, signer: Sample.signer)
            let again = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7), now: Sample.now + 10, signer: Sample.signer)
            try expect(again.payloadSHA256 == first.payloadSHA256, "Identical request and receipt produced different payload bytes")
            _ = try verifyIndependently(again.envelope, request: Sample.request(sequence: 7))
            let next = try authority.sign(receipt: receipt, request: Sample.request(sequence: 8), now: Sample.now, signer: Sample.signer)
            try expectUnsigned(layout, sequence: 8, digest: next.payloadSHA256)
            try refuses(.replay) { _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 7), now: Sample.now, signer: Sample.signer) }
        }
    }

    for (name, reason, mutate) in evidenceMutations {
        check("sign: an artifact \(name) after verification is refused as \(reason.rawValue)") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                try mutate(layout)
                var calls = 0
                try refuses(reason) { _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now) { calls += 1; return try Sample.signer($0) } }
                try expect(calls == 0, "Signer was asked to sign changed evidence")
                let checkpoint = try checkpointFields(layout)
                try expect(checkpoint.sequence == 0 && (try names(layout.publications)).isEmpty, "Changed evidence was recorded as signed")
            }
        }
    }
    check("sign: a receipt verified in one root cannot be signed by the authority of another root") {
        try withRoot { first, firstLayout in
            try withRoot { second, secondLayout in
                let receipt = try fixtureReceipt(first, firstLayout)
                try refuses(.unsafePath) { _ = try second.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer) }
                try expectUnsigned(secondLayout)
            }
        }
    }

    for boundary in signBoundaries {
        check("sign fault at \(boundary.rawValue): no signed result, and the physical high-water mark is the complete old or new record") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                var seen = 0
                try refuses(.persistenceFailed) {
                    _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer,
                                           hooks: OperatorHooks(boundary: { if $0 == boundary { seen += 1; throw Injected() } }))
                }
                try expect(seen == 1, "Signing continued past a refused \(boundary.rawValue)")
                let checkpoint = try checkpointFields(layout)
                let renamed = boundary == .checkpointRenamed || boundary == .rootSynced
                try expect(checkpoint.sequence == (renamed ? 7 : 0), "Checkpoint does not match the interrupted boundary: \(checkpoint.sequence)")
                try expect(try names(layout.publications).isEmpty, "An interrupted signature published something")
                // A fresh process state reads whichever complete record is on disk and still refuses a rollback.
                let reopened = try FixtureOperatorAuthority.reopenRoot(path: layout.root.path, trust: Sample.trust())
                if renamed {
                    try refuses(.replay) { _ = try reopened.sign(receipt: reopened.fixtureReceipt(version: Sample.version, artifactPath: layout.artifact.path),
                                                                  request: Sample.request(sequence: 6), now: Sample.now, signer: Sample.signer) }
                }
                let catalogue = try reopened.sign(receipt: reopened.fixtureReceipt(version: Sample.version, artifactPath: layout.artifact.path),
                                                  request: Sample.request(sequence: 7), now: Sample.now, signer: Sample.signer)
                _ = try verifyIndependently(catalogue.envelope, request: Sample.request(sequence: 7))
            }
        }
    }
    for operation in signSyncs {
        check("sign refused \(operation.rawValue): no weaker flush and no signed result") {
            try withRoot { authority, layout in
                let receipt = try fixtureReceipt(authority, layout)
                var refused = 0
                try refuses(.persistenceFailed) {
                    _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer,
                                           hooks: OperatorHooks(sync: { if $0 == operation { refused += 1; throw Injected() } }))
                }
                try expect(refused == 1, "Signing continued after a refused \(operation.rawValue)")
                let sequence = try checkpointFields(layout).sequence
                try expect(sequence == 0 || sequence == 7, "Checkpoint is neither the old nor the new record")
                try expect(try names(layout.publications).isEmpty, "An interrupted signature published something")
            }
        }
    }
    check("sign: a hook that only observes sees every signing boundary and flush once, in order, and changes nothing") {
        try withRoot { authority, layout in
            var boundaries: [OperatorBoundary] = [], syncs: [OperatorSyncOperation] = []
            let catalogue = try authority.sign(receipt: fixtureReceipt(authority, layout), request: Sample.request(), now: Sample.now, signer: Sample.signer,
                                               hooks: OperatorHooks(boundary: { boundaries.append($0) }, sync: { syncs.append($0) }))
            try expect(boundaries == signBoundaries && syncs == signSyncs, "Signing steps differ: \(boundaries.map(\.rawValue)) \(syncs.map(\.rawValue))")
            _ = try verifyIndependently(catalogue.envelope, request: Sample.request())
        }
    }
    check("sign: another process holding the root lock makes signing refuse as busy") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout)
            let descriptor = open(layout.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            try expect(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Fixture could not hold the lock")
            let (code, output) = try boundedChild(["--busy-probe", layout.root.path])
            try expect(code == 0 && output.contains("refused=busy"), "A second process was not refused as busy: \(output)")
            try refuses(.busy) { _ = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer) }
            try expectUnsigned(layout)
            try expect(flock(descriptor, LOCK_UN) == 0 && close(descriptor) == 0, "Fixture could not release the lock")
            let catalogue = try authority.sign(receipt: receipt, request: Sample.request(), now: Sample.now, signer: Sample.signer)
            _ = try verifyIndependently(catalogue.envelope, request: Sample.request())
        }
    }
}
