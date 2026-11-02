import Foundation
import CryptoKit
import Darwin
import ArtifactInspection
@_spi(Testing) import PatchedCore
@_spi(Testing) import PatchedOperator

// Regressions for the exclusive-operation contract of one operator root. A signer or a hook
// is untrusted code that runs while its operation holds the root lock, and it can reach the
// same authority. An operation entered that way must refuse as busy before it reads, signs or
// writes anything, and the outer operation must still hold the lock when it returns.
//
// Everything is judged from real fixture operations and the physical root: no thread, no
// wait and no substituted result. The second process is the existing `--busy-probe`.

let rootLockPrefix = "root lock: "

/// How one attempt ended: accepted, a typed refusal, or anything else. Never thrown, because
/// whatever a signer or a hook throws would replace the outcome being recorded.
func rootLockOutcome(_ action: () throws -> Void) -> String {
    do { try action(); return "accepted" } catch let error as OperatorFailure { return error.rawValue } catch { return "failed (\(error))" }
}
/// Whether the root lock is held, asked of the kernel through a new open file description of
/// this check's own. A lock it obtains was free, and is released again at once.
func rootLockHeld(_ layout: Layout) throws -> Bool {
    let descriptor = open(layout.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw CheckFailure(description: "Fixture could not open the lock: errno \(errno)") }
    defer { close(descriptor) }
    if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
        guard flock(descriptor, LOCK_UN) == 0 else { throw CheckFailure(description: "Fixture could not release the lock") }
        return false
    }
    guard errno == EWOULDBLOCK else { throw CheckFailure(description: "Fixture lock probe failed: errno \(errno)") }
    return true
}
/// The same question from inside a signer or a hook, where nothing may be thrown.
func rootLockState(_ layout: Layout) -> String {
    do { return try rootLockHeld(layout) ? "held" : "FREE" } catch { return "unknown (\(error))" }
}
/// The high-water mark as physically recorded, or why it could not be read.
func rootLockCheckpoint(_ layout: Layout) -> String {
    do { let mark = try checkpointFields(layout); return "sequence \(mark.sequence) payload \(mark.payloadSHA256)" }
    catch { return "unreadable (\(error))" }
}

@MainActor func registerRootLockReentrancyChecks() {
    check(rootLockPrefix + "control: an ordinary sign and publish hold the lock through the signer and every hook, and release it afterwards") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request()
            try expect(try !rootLockHeld(layout), "The lock was held before any operation")
            var duringSigner = "never asked", duringHooks: [String] = [], probe = "never run"
            let catalogue = try authority.sign(receipt: receipt, request: request, now: Sample.now, signer: {
                duringSigner = rootLockState(layout); return try Sample.signer($0)
            }, hooks: OperatorHooks(boundary: { _ in duringHooks.append(rootLockState(layout)) }))
            try expect(duringSigner == "held" && duringHooks == signBoundaries.map { _ in "held" },
                       "Signing did not hold the lock throughout: signer \(duringSigner), boundaries \(duringHooks)")
            try expect(try !rootLockHeld(layout), "Signing returned with the lock still held")
            try expectUnsigned(layout, sequence: 7, digest: catalogue.payloadSHA256)
            duringHooks = []
            _ = try authority.publish(catalogue, now: Sample.now, hooks: OperatorHooks(boundary: { boundary in
                duringHooks.append(rootLockState(layout))
                guard boundary == .pendingCreated else { return }
                // A second operator process, with nothing nested in this one: it must find the root busy.
                do { let (code, output) = try boundedChild(["--busy-probe", layout.root.path]); probe = "exit \(code): \(output)" }
                catch { probe = "not run (\(error))" }
            }))
            try expect(duringHooks == publishBoundaries.map { _ in "held" }, "Publishing did not hold the lock throughout: \(duringHooks)")
            try expect(probe.hasPrefix("exit 0: ") && probe.contains("refused=busy") && !probe.contains("IMPROPER ACCEPTANCE"),
                       "A second process was not refused as busy during an ordinary publish: \(probe)")
            try expect(try !rootLockHeld(layout), "Publishing returned with the lock still held")
            try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: request, receipt: receipt)
            try expect(try names(layout.publications) == ["sequence-7"] && checkpointFields(layout) == (7, catalogue.payloadSHA256),
                       "Physical state after an ordinary sign and publish differs")
        }
    }
    check(rootLockPrefix + "control: a signer that refuses leaves the lock released, and a later fresh sign and publish succeed") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request()
            var asked = 0, during = "never asked"
            try refuses(.signerFailed) {
                _ = try authority.sign(receipt: receipt, request: request, now: Sample.now) { _ in
                    asked += 1; during = rootLockState(layout); throw Injected()
                }
            }
            try expect(asked == 1 && during == "held", "The refusing signer was asked \(asked) times with the lock \(during)")
            try expectUnsigned(layout)
            try expect(try !rootLockHeld(layout), "A refused signature left the lock held")
            let catalogue = try authority.sign(receipt: receipt, request: request, now: Sample.now, signer: Sample.signer)
            let decoded = try verifyIndependently(catalogue.envelope, request: request)
            try expectUnsigned(layout, sequence: 7, digest: sha(decoded.payload))
            _ = try authority.publish(catalogue, now: Sample.now)
            try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: request, receipt: receipt)
            try expect(try !rootLockHeld(layout) && names(layout.publications) == ["sequence-7"], "State after the later sign and publish differs")
        }
    }

    check(rootLockPrefix + "a sign entered from inside the signer of the same authority is refused as busy before its own signer is asked or the high-water mark moves") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request(sequence: 7)
            var messages: [Data] = [], innerAsked = 0
            var nested = "never attempted", markInside = "never read", lockInside = "never read"
            var outer: SignedCatalogue?
            let outcome = rootLockOutcome {
                outer = try authority.sign(receipt: receipt, request: request, now: Sample.now) { message in
                    messages.append(message)
                    if messages.count == 1 {
                        nested = rootLockOutcome {
                            _ = try authority.sign(receipt: receipt, request: Sample.request(sequence: 8), now: Sample.now) {
                                innerAsked += 1; return try Sample.signer($0)
                            }
                        }
                        markInside = rootLockCheckpoint(layout); lockInside = rootLockState(layout)
                    }
                    // The outer signer itself answers honestly, for exactly the message it was given.
                    return try Sample.signer(message)
                }
            }
            // The evidence is read before anything is judged.
            let frame = Data((Sample.domain + "\0").utf8)
            guard let message = messages.first, message.starts(with: frame) else {
                throw CheckFailure(description: "The outer signer was never asked for the documented frame: outer sign ended \(outcome)")
            }
            let expected = sha(Data(message.dropFirst(frame.count)))
            let markAfter = rootLockCheckpoint(layout), published = try names(layout.publications).sorted()
            let entries = try names(layout.root), lockAfter = rootLockState(layout)
            var findings: [String] = []
            if nested != "busy" {
                findings.append(nested == "accepted" ? "IMPROPER ACCEPTANCE: a sign of sequence 8 nested inside the signer of sequence 7 was accepted on the same authority"
                                                     : "the nested sign ended \(nested), not busy")
            }
            if innerAsked != 0 { findings.append("the nested operation asked its own signer \(innerAsked) time(s)") }
            if markInside != "sequence 0 payload \(Sample.zeroDigest)" {
                findings.append("HIGH-WATER MARK MOVED inside the outer signer: \(markInside)")
            }
            if lockInside != "held" { findings.append("the outer operation's lock was \(lockInside) after the nested attempt") }
            if outcome != "accepted" { findings.append("the outer sign of sequence 7 ended \(outcome)") }
            if messages.count != 1 { findings.append("the outer signer was asked \(messages.count) times") }
            if let outer {
                if outer.sequence != 7 || outer.payloadSHA256 != expected { findings.append("the outer result is sequence \(outer.sequence) payload \(outer.payloadSHA256)") }
                do { _ = try verifyIndependently(outer.envelope, request: request) } catch { findings.append("the outer envelope does not verify: \(error)") }
            }
            if markAfter != "sequence 7 payload \(expected)" {
                findings.append("the high-water mark ended as \(markAfter), expected sequence 7 payload \(expected)")
            }
            if !published.isEmpty { findings.append("signing left publications \(published)") }
            if entries != ["namespace.json", "checkpoint.json", "lock", "input", "publications"] { findings.append("the root holds \(entries.sorted())") }
            if lockAfter != "FREE" { findings.append("the lock was \(lockAfter) after the outer sign returned") }
            if !findings.isEmpty { throw CheckFailure(description: findings.joined(separator: "; ")) }
        }
    }
    check(rootLockPrefix + "a publish entered from inside the pendingCreated hook of the same authority is refused as busy, and the outer publication completes") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request()
            let catalogue = try authority.sign(receipt: receipt, request: request, now: Sample.now, signer: Sample.signer)
            let checkpointBefore = try bytes(layout.checkpoint), inputBefore = try snapshot(layout.input)
            var boundaries: [OperatorBoundary] = []
            var nested = "never attempted", lockInside = "never read", pendingInside = "never read", pendingAfterNested = "never read"
            func pendingState() -> String { (try? snapshot(layout.publications)).map { "\($0.sorted { $0.key < $1.key })" } ?? "unreadable" }
            let outcome = rootLockOutcome {
                _ = try authority.publish(catalogue, now: Sample.now, hooks: OperatorHooks(boundary: { boundary in
                    boundaries.append(boundary)
                    guard boundary == .pendingCreated else { return }
                    pendingInside = pendingState()
                    // Caught here: a hook that throws would end the outer publish as persistenceFailed.
                    nested = rootLockOutcome { _ = try authority.publish(catalogue, now: Sample.now) }
                    pendingAfterNested = pendingState(); lockInside = rootLockState(layout)
                }))
            }
            var findings: [String] = []
            if nested != "busy" {
                findings.append(nested == "accepted" ? "IMPROPER ACCEPTANCE: a publish nested inside a publishing hook was accepted on the same authority"
                                                     : "the nested publish ended \(nested), not busy: it took the lock its caller holds and ran its body")
            }
            if lockInside != "held" { findings.append("LOCK RELEASED: the outer publish's lock was \(lockInside) after the nested attempt, with its pending directory open") }
            if pendingAfterNested != pendingInside { findings.append("the nested attempt changed the pending output: \(pendingInside) became \(pendingAfterNested)") }
            if outcome != "accepted" { findings.append("the outer publish ended \(outcome)") }
            if boundaries != publishBoundaries { findings.append("the outer publish reported \(boundaries.map(\.rawValue))") }
            do { try expectCompletePublication(layout, sequence: 7, envelope: catalogue.envelope, request: request, receipt: receipt) }
            catch { findings.append("the outer publication is not physically complete: \(error)") }
            let published = try names(layout.publications).sorted()
            if published != ["sequence-7"] { findings.append("publications holds \(published)") }
            if try bytes(layout.checkpoint) != checkpointBefore || snapshot(layout.input) != inputBefore {
                findings.append("the high-water mark or the artifact changed: \(rootLockCheckpoint(layout))")
            }
            let lockAfter = rootLockState(layout)
            if lockAfter != "FREE" { findings.append("the lock was \(lockAfter) after the outer publish returned") }
            if !findings.isEmpty { throw CheckFailure(description: findings.joined(separator: "; ")) }
        }
    }
    check(rootLockPrefix + "a second operator process is still refused as busy after a publish was attempted from inside the pendingCreated hook") {
        try withRoot { authority, layout in
            let receipt = try fixtureReceipt(authority, layout), request = Sample.request()
            let catalogue = try authority.sign(receipt: receipt, request: request, now: Sample.now, signer: Sample.signer)
            let checkpointBefore = try bytes(layout.checkpoint)
            var nested = "never attempted", probe: (code: Int32, output: String)?, probeFailure = "never run"
            let outcome = rootLockOutcome {
                _ = try authority.publish(catalogue, now: Sample.now, hooks: OperatorHooks(boundary: { boundary in
                    guard boundary == .pendingCreated else { return }
                    nested = rootLockOutcome { _ = try authority.publish(catalogue, now: Sample.now) }
                    // Before this hook returns the outer publish is still between its own writes. The
                    // probe reopens this root only, signs nothing new and is bounded by the helper.
                    do { probe = try boundedChild(["--busy-probe", layout.root.path]) } catch { probeFailure = "\(error)" }
                }))
            }
            guard let probe else { throw CheckFailure(description: "The second process was not run: \(probeFailure); nested publish ended \(nested), outer \(outcome)") }
            let output = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
            var findings: [String] = []
            if probe.code != 0 || !output.contains("refused=busy") || output.contains("IMPROPER ACCEPTANCE") {
                findings.append("LOCK RELEASED TO ANOTHER PROCESS inside an unfinished publish: the second operator process exited \(probe.code) with \"\(output)\"")
            }
            if try bytes(layout.checkpoint) != checkpointBefore { findings.append("the high-water mark changed: \(rootLockCheckpoint(layout))") }
            if !findings.isEmpty {
                throw CheckFailure(description: findings.joined(separator: "; ") + "; the nested publish ended \(nested) and the outer publish \(outcome), " +
                                   "leaving publications \(try names(layout.publications).sorted())")
            }
        }
    }
}

/// The explicit `--root-lock-regressions` command: only the cases registered above.
@MainActor func runRootLockRegressions(_ registered: [(String, @MainActor () throws -> Void)]) -> Int32 {
    let selected = registered.filter { $0.0.hasPrefix(rootLockPrefix) }
    var failures = 0
    for (name, action) in selected {
        do { try action(); print("PASS operator: \(name)") }
        catch { failures += 1; print("FAIL operator: \(name): \(error)") }
    }
    print("Root lock reentrancy regressions: \(selected.count) cases, \(failures) failures. Fixture trust only. No production key, publication, fresh OS trust or installation authority.")
    return failures == 0 ? 0 : 1
}
