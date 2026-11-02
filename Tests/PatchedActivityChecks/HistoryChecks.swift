import Foundation
import Darwin
@_spi(Testing) import PatchedActivity

@MainActor func registerHistoryChecks() {
    check("setup: independent literal empty wire", setup: true) {
        let expected = "{\"events\":[],\"principal\":\"fixture-owner-A\",\"revision\":0,\"schema\":1,\"storeID\":\"AAAAAAAA-0000-4000-8000-000000000001\"}"
        try expect(try bytes().bytes == Data(expected.utf8), "Independent canonical constructor changed")
    }
    check("setup: literal retained fixture is independently canonical", setup: true) {
        let data = try fixtureFile()
        let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try expect(try canonical(value) == data, "Literal fixture is not canonical bytes")
        let events = value["events"] as! [[String: Any]]
        try expect(events.count == 1 && events[0]["eventID"] as? String == eventID && value["revision"] as? Int == 1,
                   "Wrong independent fixture identity")
    }
    check("setup: actual private bytes independently readable", setup: true) {
        let store = try OwnedStore(); let value = try bytes([event()], revision: 1)
        try store.seed(value)
        try expect(try store.actual() == value, "Independent disk read differs")
        var directoryInfo = stat(); var fileInfo = stat()
        try expect(lstat(store.directory.path, &directoryInfo) == 0 && directoryInfo.st_mode & 0o777 == 0o700,
                   "Directory not private")
        try expect(lstat(store.file.path, &fileInfo) == 0 && fileInfo.st_mode & 0o777 == 0o600 && fileInfo.st_nlink == 1,
                   "Record not private single-link")
        try expect(try Data(contentsOf: store.file).count > value.bytes.count, "No actual retained wrapper bytes")
    }
    check("setup: CAS exact-byte and revision fence", setup: true) {
        let store = try OwnedStore(); let first = try bytes([], revision: 1); try store.seed(first)
        let wrong = try bytes([event()], revision: 1)
        if case .knownNotCommitted = try store.compareAndSwap(expected: wrong, replacement: bytes([], revision: 2)) {} else {
            throw Failure(description: "Different expected bytes accepted")
        }
        try expect(try store.actual() == first, "Failed CAS changed bytes")
    }
    check("setup: symlink record refuses without following", setup: true) {
        let store = try OwnedStore(); let victim = store.directory.appendingPathComponent("victim")
        try Data("do not follow".utf8).write(to: victim)
        try expect(symlink(victim.path, store.file.path) == 0, "Cannot prepare symlink")
        try refused { _ = try store.read() }
        try expect(try Data(contentsOf: victim) == Data("do not follow".utf8), "Victim altered")
    }
    check("setup: hardlinked record refuses", setup: true) {
        let store = try OwnedStore(); try store.seed(bytes())
        try expect(link(store.file.path, store.directory.appendingPathComponent("alias").path) == 0, "Cannot prepare hardlink")
        try refused { _ = try store.read() }
    }
    check("setup: changed owner-directory mode refuses", setup: true) {
        let store = try OwnedStore(); try expect(chmod(store.directory.path, 0o755) == 0, "Cannot prepare mode fault")
        try refused { _ = try store.read() }
    }
    check("setup: fault commit before ack physically persists", setup: true) {
        let store = try OwnedStore(); store.fault = .afterCommit
        let value = try bytes([event()], revision: 1)
        if case .uncertain = try store.compareAndSwap(expected: nil, replacement: value) {} else { throw Failure(description: "Wrong fault state") }
        try expect(try store.actual() == value, "Fault did not retain committed bytes")
    }
    check("setup: overlarge regular record refuses before allocation", setup: true) {
        let store = try OwnedStore()
        let fd = open(store.file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure(description: "Cannot create oversized setup record") }
        defer { close(fd) }
        try expect(ftruncate(fd, 3 * 1024 * 1024 + 1) == 0, "Cannot size oversized record")
        try refused { _ = try store.actual() }
        try expect(store.allocatedReadBytes == 0, "Oversized record allocated read buffer")
    }
    check("setup: same-inode growth after lstat refuses opened FD before allocation", setup: true) {
        let store = try OwnedStore(); try store.seed(bytes())
        store.afterPreopenCheck = {
            let fd = open(store.file.path, O_WRONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure(description: "Cannot open growth setup record") }
            defer { close(fd) }
            try expect(ftruncate(fd, 3 * 1024 * 1024 + 1) == 0, "Cannot grow same inode")
        }
        try refused { _ = try store.actual() }
        try expect(store.allocatedReadBytes == 0, "Opened oversized inode allocated read buffer")
    }
    check("setup: opened FD wrong mode after lstat refuses before allocation", setup: true) {
        let store = try OwnedStore(); try store.seed(bytes())
        store.afterPreopenCheck = { try expect(chmod(store.file.path, 0o644) == 0, "Cannot change setup mode") }
        try refused { _ = try store.actual() }
        try expect(store.allocatedReadBytes == 0, "Wrong-mode opened inode allocated read buffer")
    }
    check("setup: append after bounded fstat is rejected by exact EOF guard", setup: true) {
        let store = try OwnedStore(); try store.seed(bytes())
        store.afterOpenedCheck = {
            let fd = open(store.file.path, O_WRONLY | O_APPEND | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure(description: "Cannot open EOF setup record") }
            defer { close(fd) }
            var byte: UInt8 = 32
            try expect(Darwin.write(fd, &byte, 1) == 1, "Cannot append EOF setup byte")
        }
        do { _ = try store.actual(); throw Failure(description: "EOF mutation unexpectedly read") }
        catch let error as Failure { try expect(error.description.contains("EOF guard"), "Mutation did not reach independent EOF refusal") }
        try expect(store.allocatedReadBytes > 0 && store.allocatedReadBytes <= 3 * 1024 * 1024, "Read allocation escaped actual FD bound")
    }
    check("setup: truncation after bounded fstat is rejected by exact read", setup: true) {
        let store = try OwnedStore(); try store.seed(bytes())
        store.afterOpenedCheck = {
            let fd = open(store.file.path, O_WRONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure(description: "Cannot open short-read setup record") }
            defer { close(fd) }
            try expect(ftruncate(fd, 0) == 0, "Cannot truncate setup record")
        }
        do { _ = try store.actual(); throw Failure(description: "Short mutation unexpectedly read") }
        catch let error as Failure { try expect(error.description == "Short fixture read", "Mutation did not reach independent exact-read refusal") }
    }
    check("setup: record replaced by FIFO refuses without blocking", setup: true) {
        let store = try OwnedStore(); try store.seed(bytes())
        store.afterPreopenCheck = {
            try expect(unlink(store.file.path) == 0 && mkfifo(store.file.path, 0o600) == 0, "Cannot prepare FIFO replacement")
        }
        try refused { _ = try store.actual() }
        try expect(store.allocatedReadBytes == 0, "FIFO descriptor allocated read buffer")
    }
    check("setup: successful rename acknowledges only after actual owned directory sync", setup: true) {
        let store = try OwnedStore(); let first = try bytes([], revision: 1); try store.seed(first)
        try expect(store.directorySyncs == 1, "Initial rename omitted directory sync")
        let second = try bytes([event()], revision: 2)
        if case .committed = try store.compareAndSwap(expected: first, replacement: second) {} else {
            throw Failure(description: "Owned synchronized CAS not committed")
        }
        try expect(store.directorySyncs == 2, "Committed rename omitted actual directory sync")
        try expect(try store.actual() == second, "Synchronized CAS bytes differ")
    }
    check("setup: post-rename owned directory failure is explicitly uncertain", setup: true) {
        let store = try OwnedStore(); let value = try bytes([event()], revision: 1)
        store.beforeDirectorySync = { try expect(chmod(store.directory.path, 0o755) == 0, "Cannot inject sync ownership failure") }
        var uncertain = false
        do { _ = try store.compareAndSwap(expected: nil, replacement: value) }
        catch let error as ActivityRefusal { uncertain = error == .uncertain }
        try expect(chmod(store.directory.path, 0o700) == 0, "Cannot restore owned setup mode")
        try expect(uncertain && store.directorySyncs == 0, "Post-rename failure claimed committed/durable")
        try expect(try store.actual() == value, "Uncertain rename did not retain actual bytes")
    }
    check("default: every operation refuses permanently with unavailable snapshot", setup: true) {
        let owner = ActivityHistoryOwner()
        try refused { try owner.reload(now: epoch) }
        try refused { try owner.bootstrapFreshFixture() }
        try refused { try owner.appendSynthetic(event(), now: epoch) }
        try refused { try owner.selectRetained(now: epoch) }
        try expect(!owner.snapshot.available && owner.snapshot.events.isEmpty, "Ordinary owner invents state")
    }
    check("wire: literal known record decodes and exact-reencodes") {
        let data = try fixtureFile()
        let record = try ActivityWire.decode(data, principal: principal, storeID: storeID)
        try expect(record.events == [event()] && record.revision == 1, "Literal record differs")
        try expect(try ActivityWire.encode(record) == data, "Encoding differs from independent canonical fixture")
    }
    check("wire: UInt64 exact maximum revision and sequence") {
        let e = event(sequence: UInt64.max)
        let data = try bytes([e], revision: UInt64.max).bytes
        let decoded = try ActivityWire.decode(data, principal: principal, storeID: storeID)
        try expect(decoded.revision == UInt64.max && decoded.events[0].sequence == UInt64.max, "Integer precision lost")
    }
    check("wire: identity and literal version byte boundaries accepted") {
        let e = event(target: String(repeating: "x", count: 256), name: String(repeating: "a", count: 256),
                      before: String(repeating: "é", count: 64), after: "<b>unknown</b>")
        let decoded = try ActivityWire.decode(bytes([e]).bytes, principal: principal, storeID: storeID)
        try expect(decoded.events == [e], "Valid literal text changed")
    }
    let invalidEnvelopes: [(String, (inout [String: Any]) -> Void)] = [
        ("unknown schema", { $0["schema"] = 2 }), ("string schema", { $0["schema"] = "1" }),
        ("bool schema", { $0["schema"] = true }), ("unknown envelope field", { $0["secret"] = "x" }),
        ("missing revision", { $0.removeValue(forKey: "revision") }), ("negative revision", { $0["revision"] = -1 }),
        ("fractional revision", { $0["revision"] = 1.5 }), ("boolean revision", { $0["revision"] = false }),
        ("wrong principal", { $0["principal"] = "fixture-owner-B" }), ("wrong store", { $0["storeID"] = otherID }),
        ("lowercase UUID store", { $0["storeID"] = storeID.lowercased() }), ("events object", { $0["events"] = [String: Any]() }),
        ("null events", { $0["events"] = NSNull() }), ("NUL principal", { $0["principal"] = "a\u{0}b" })
    ]
    for (name, mutate) in invalidEnvelopes {
        check("wire rejects: " + name) {
            var raw = rawRecord([event()]); mutate(&raw)
            try refused { _ = try ActivityWire.decode(canonical(raw), principal: principal, storeID: storeID) }
        }
    }
    let invalidEvents: [(String, (inout [String: Any]) -> Void)] = [
        ("unknown event field", { $0["rawJournal"] = privateText }), ("unknown origin", { $0["origin"] = "auto" }),
        ("unknown status", { $0["status"] = "installed" }), ("unknown reason", { $0["reason"] = privateText }),
        ("missing target", { $0.removeValue(forKey: "targetKey") }), ("numeric ID", { $0["eventID"] = 1 }),
        ("nonUUID attempt", { $0["attemptID"] = "attempt" }), ("lowercase event UUID", { $0["eventID"] = eventID.lowercased() }),
        ("invalid run UUID", { $0["runID"] = "bad" }), ("invalid request UUID", { $0["requestID"] = "bad" }),
        ("invalid transaction UUID", { $0["transactionID"] = "bad" }), ("invalid parent UUID", { $0["parentUpdateID"] = "bad" }),
        ("invalid report UUID", { $0["reportID"] = "bad" }), ("boolean sequence", { $0["sequence"] = true }),
        ("fractional sequence", { $0["sequence"] = 1.5 }), ("negative timestamp", { $0["observedAt"] = -1 }),
        ("string timestamp", { $0["resolvedAt"] = "100" }), ("null optional", { $0["beforeVersion"] = NSNull() }),
        ("version over UTF8 limit", { $0["afterVersion"] = String(repeating: "é", count: 65) }),
        ("target over limit", { $0["targetKey"] = String(repeating: "x", count: 257) }),
        ("target control", { $0["targetKey"] = "a\nb" }), ("name NUL", { $0["appName"] = "a\u{0}b" }),
        ("build control", { $0["afterBuild"] = "a\tb" })
    ]
    for (name, mutate) in invalidEvents {
        check("wire rejects: " + name) {
            var raw = rawRecord(); var item = eventObject(event()); mutate(&item); raw["events"] = [item]
            try refused { _ = try ActivityWire.decode(canonical(raw), principal: principal, storeID: storeID) }
        }
    }
    for (name, raw) in [
        ("duplicate envelope key", "{\"schema\":1,\"schema\":1,\"events\":[],\"principal\":\"fixture-owner-A\",\"revision\":0,\"storeID\":\"\(storeID)\"}"),
        ("overflow integer", "{\"events\":[],\"principal\":\"fixture-owner-A\",\"revision\":18446744073709551616,\"schema\":1,\"storeID\":\"\(storeID)\"}")
    ] {
        check("wire rejects: " + name) { try refused { _ = try ActivityWire.decode(Data(raw.utf8), principal: principal, storeID: storeID) } }
    }
    check("wire rejects: duplicate field in otherwise complete valid event") {
        let valid = String(decoding: try bytes([event()]).bytes, as: UTF8.self)
        let field = "\"eventID\":\"\(eventID)\""
        let repeated = valid.replacingOccurrences(of: field, with: field + "," + field)
        try expect(repeated != valid, "Duplicate-field setup did not mutate complete record")
        try refused { _ = try ActivityWire.decode(Data(repeated.utf8), principal: principal, storeID: storeID) }
    }
    for token in ["1.0", "1e0", "18446744073709551616"] {
        check("wire rejects: noncanonical integral token " + token) {
            let valid = String(decoding: try bytes([event()], revision: 1).bytes, as: UTF8.self)
            let altered = valid.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":" + token)
            try expect(altered != valid, "Number-token setup failed")
            try refused { _ = try ActivityWire.decode(Data(altered.utf8), principal: principal, storeID: storeID) }
        }
    }
    check("wire rejects: valid record with trailing newline") {
        var data = try bytes().bytes; data.append(10)
        try refused { _ = try ActivityWire.decode(data, principal: principal, storeID: storeID) }
    }
    check("wire rejects: over 2 MiB before parsing") {
        try refused { _ = try ActivityWire.decode(Data(repeating: 32, count: 2_097_153), principal: principal, storeID: storeID) }
    }
    check("wire rejects: over 2000 events") {
        try refused { _ = try ActivityWire.decode(bytes(Array(repeating: event(), count: 2001)).bytes, principal: principal, storeID: storeID) }
    }
    check("history: explicit fresh bootstrap writes readback then becomes available") {
        let store = try OwnedStore(); let owner = fixtureOwner(store)
        try owner.bootstrapFreshFixture()
        try expect(owner.snapshot.available && owner.snapshot.events.isEmpty && store.writes == 1 && store.reads >= 2,
                   "Bootstrap lacks write/readback")
        try expect(try store.actual() != nil, "Bootstrap only in memory")
        try refused { try owner.bootstrapFreshFixture() }
    }
    for (name, raw) in [("missing", Optional<ActivityStoredBytes>.none),
                        ("corrupt", ActivityStoredBytes(revision: 1, bytes: Data("bad".utf8))),
                        ("unknown schema", ActivityStoredBytes(revision: 1, bytes: Data("{\"schema\":2}".utf8)))] {
        check("history unavailable: " + name) {
            let store = try OwnedStore(); if let raw { try store.seed(raw) }
            let owner = fixtureOwner(store); try refused { try owner.reload(now: epoch) }
            try expect(!owner.snapshot.available && owner.snapshot.events.isEmpty && store.writes == 0, "Unavailable store fabricated or replaced")
            try expect(try store.actual() == raw, "Unavailable bytes overwritten")
        }
    }
    for origin in ActivityOrigin.allCases {
        for status in ActivityStatus.allCases {
            check("history synthetic observation: \(origin.rawValue)/\(status.rawValue)") {
                let e = event(origin: origin, status: status, before: "1.2", after: "1.3", run: runID,
                              request: requestID, transaction: transactionID, parent: otherID)
                let (store, owner) = try loaded([])
                try owner.appendSynthetic(e, readback: readback(e), now: epoch)
                try expect(owner.snapshot.events == [e], "Observation/correlation rewritten")
                let reopened = fixtureOwner(store); try reopened.reload(now: epoch)
                try expect(reopened.snapshot.events == [e], "New owner lost actual retained bytes")
                try expect(ActivityPresentation.make(reopened.snapshot).provenance == "Synthetic fixture only", "Synthetic observation represented as native proof")
            }
        }
    }
    check("history: retry preserves failure and same target is not dedup key") {
        let failure = event(); let retry = event(id: otherID, attempt: otherID, status: .succeeded, sequence: 2,
                                                 before: nil, after: "2", transaction: transactionID)
        let (_, owner) = try loaded([failure])
        try owner.appendSynthetic(retry, readback: readback(retry), now: epoch)
        try expect(owner.snapshot.events == [failure, retry] && owner.snapshot.events[1].beforeVersion == nil,
                   "Retry replaced failure or invented before version")
    }
    check("history: equal timestamps order by sequence rather than input/display tuple") {
        let first = event(sequence: 1); let second = event(id: otherID, attempt: otherID, sequence: 2)
        let (_, owner) = try loaded([second, first])
        try expect(owner.snapshot.events == [first, second], "Sequence order is unstable")
    }
    check("history: partial manual batch remains mixed") {
        let success = event(status: .succeeded, sequence: 1, after: "2", run: runID, transaction: transactionID)
        let failed = event(id: otherID, attempt: otherID, origin: .manualBatch, sequence: 2, run: runID)
        let (_, owner) = try loaded([success, failed])
        let text = ActivityPresentation.make(owner.snapshot).rows.map(\.text).joined(separator: " ")
        try expect(owner.snapshot.events.map(\.status) == [.succeeded, .failed] && text.contains("Failed") && text.contains("Succeeded"),
                   "Partial batch portrayed as whole success")
    }
    check("history: identical replay is idempotent without extra write") {
        let e = event(); let (store, owner) = try loaded([e]); let original = try store.actual()
        try owner.appendSynthetic(e, now: epoch)
        let retained = try store.actual()
        try expect(owner.snapshot.events == [e] && store.writes == 0 && retained == original, "Replay wrote or duplicated")
    }
    check("history: conflicting replay visibly refuses without overwriting") {
        let e = event(); let (store, owner) = try loaded([e]); let original = try store.actual()
        try refused { try owner.appendSynthetic(event(status: .skipped), now: epoch) }
        let retained = try store.actual()
        try expect(owner.snapshot.events == [e] && store.writes == 0 && retained == original, "Conflict overwrote evidence")
    }
    for fault in [OwnedStore.Fault.beforeWrite, .knownNotCommitted, .uncertainWithoutWrite, .afterCommit, .readbackMismatch, .readError] {
        check("history: fault \(fault) never acknowledges saved; reload/replay exactly once") {
            let store = try OwnedStore(); try store.seed(bytes([], revision: 1))
            let owner = fixtureOwner(store); try owner.reload(now: epoch); store.fault = fault
            try refused { try owner.appendSynthetic(event(), now: epoch) }
            try expect(!owner.snapshot.available || owner.snapshot.events.isEmpty, "Fault acknowledged saved event")
            store.clearFault(); let fresh = fixtureOwner(store); try fresh.reload(now: epoch)
            try fresh.appendSynthetic(event(), now: epoch)
            try expect(fresh.snapshot.events == [event()], "Crash replay lost or duplicated event")
        }
    }
    check("history: reentrant store callback refuses inner mutation") {
        let (store, owner) = try loaded([]); var innerRefused = false
        store.reenter = {
            do { try owner.appendSynthetic(event(id: otherID, attempt: otherID, sequence: 2), now: epoch) }
            catch { innerRefused = true }
        }
        try owner.appendSynthetic(event(), now: epoch)
        try expect(innerRefused && owner.snapshot.events == [event()] && store.writes == 1, "Reentry mutated or raced owner")
    }
    check("history: two owners stale CAS refuses then reload preserves both attempts") {
        let store = try OwnedStore(); try store.seed(bytes([], revision: 1))
        let a = fixtureOwner(store); let b = fixtureOwner(store); try a.reload(now: epoch); try b.reload(now: epoch)
        let second = event(id: otherID, attempt: otherID, sequence: 2)
        try a.appendSynthetic(event(), now: epoch)
        try refused { try b.appendSynthetic(second, now: epoch) }
        try b.reload(now: epoch); try b.appendSynthetic(second, now: epoch)
        try expect(b.snapshot.events == [event(), second], "Stale owner lost first event")
    }
    check("history: cross-principal and store binding refuse without data disclosure") {
        let store = try OwnedStore(); try store.seed(bytes([event()], revision: 1))
        let stranger = fixtureOwner(store, owner: "fixture-owner-B")
        try refused { try stranger.reload(now: epoch) }
        try expect(!stranger.snapshot.available && stranger.snapshot.events.isEmpty && store.writes == 0, "Cross-principal disclosure")
        let wrongStore = fixtureOwner(store, storeID: otherID)
        try refused { try wrongStore.reload(now: epoch) }
        try expect(wrongStore.snapshot.events.isEmpty, "Cross-store disclosure")
    }
    check("history: two separately retained principals reconstruct independently") {
        let a = try OwnedStore(); let b = try OwnedStore()
        let second = event(id: otherID, attempt: otherID)
        try a.seed(bytes([event()], revision: 1)); try b.seed(bytes([second], revision: 1, owner: "fixture-owner-B"))
        let oa = fixtureOwner(a); let ob = fixtureOwner(b, owner: "fixture-owner-B")
        try oa.reload(now: epoch); try ob.reload(now: epoch)
        try expect(oa.snapshot.events == [event()] && ob.snapshot.events == [second] && a.directory != b.directory, "Principal histories mixed")
    }
    for status in [ActivityStatus.succeeded, .restored] {
        for mismatch in ["missing", "event", "attempt", "transaction", "version", "build"] {
            check("false installed success rejected: \(status)/\(mismatch)") {
                let e = event(status: status, after: "2", afterBuild: "22", transaction: transactionID)
                let (store, owner) = try loaded([])
                let proof = mismatch == "missing" ? nil : ActivitySyntheticReadback(
                    eventID: mismatch == "event" ? otherID : eventID,
                    attemptID: mismatch == "attempt" ? otherID : attemptID,
                    transactionID: mismatch == "transaction" ? otherID : transactionID,
                    afterVersion: mismatch == "version" ? "3" : "2", afterBuild: mismatch == "build" ? "23" : "22")
                try refused { try owner.appendSynthetic(e, readback: proof, now: epoch) }
                try expect(owner.snapshot.events.isEmpty && store.writes == 0, "Unmatched readback became success")
            }
        }
    }
    for status in [ActivityStatus.succeeded, .restored] {
        check("false installed success rejected: missing after observation " + status.rawValue) {
            let e = event(status: status, after: nil, afterBuild: nil, transaction: transactionID)
            let (store, owner) = try loaded([])
            try refused { try owner.appendSynthetic(e, readback: readback(e), now: epoch) }
            try expect(owner.snapshot.events.isEmpty && store.writes == 0, "Unknown after observation became success")
        }
    }
    check("history: unknown observations stay unknown in local view") {
        let (_, owner) = try loaded([event(observed: nil, resolved: nil)])
        let p = ActivityPresentation.make(owner.snapshot)
        try expect(p.rows.count == 1 && p.rows[0].text.contains("Unknown") && p.retainedRange.contains("unknown"), "Unknown values invented")
    }
    for delta in [thirtyDays - 1, thirtyDays, thirtyDays + 1] {
        check("retention resolved exact elapsed boundary: \(delta)") {
            let (store, owner) = try loaded([event()]); let original = try store.actual()
            try owner.selectRetained(now: epoch + delta)
            let expected = delta < thirtyDays ? [event()] : []
            try expect(owner.snapshot.events == expected, "Wrong 30-day boundary")
            let reopened = fixtureOwner(store); try reopened.reload(now: epoch + delta)
            try expect(reopened.snapshot.events == expected, "Retention not retained in actual fixture bytes")
            if delta < thirtyDays { try expect(try store.actual() == original, "Read extended retention anchor") }
        }
    }
    for clock in [Optional<UInt64>.none, epoch - 1] {
        check("retention unknown/rollback clock holds and discloses unavailable age: \(String(describing: clock))") {
            let (store, owner) = try loaded([event()]); let before = try store.actual()
            try owner.selectRetained(now: clock)
            let retained = try store.actual()
            try expect(owner.snapshot.events == [event()] && !owner.snapshot.ageAvailable && retained == before,
                       "Unprovable elapsed age deleted evidence")
        }
    }
    for status in [ActivityStatus.queued, .started, .downloaded, .incomplete, .needsRecovery] {
        check("retention protects unresolved state: \(status)") {
            let e = event(status: status, resolved: nil)
            let (_, owner) = try loaded([e]); try owner.selectRetained(now: epoch + thirtyDays * 2)
            try expect(owner.snapshot.events == [e], "Unresolved recovery evidence expired")
        }
    }
    check("retention: resolved failure correlated to unresolved attempt held") {
        let failure = event(); let active = event(id: otherID, status: .needsRecovery, sequence: 2, resolved: nil)
        let (_, owner) = try loaded([failure, active]); try owner.selectRetained(now: epoch + thirtyDays * 2)
        try expect(owner.snapshot.events == [failure, active], "Correlated unresolved attempt lost history")
    }
    check("retention: partial expiry gives actual retained range and limits") {
        let fresh = event(id: otherID, attempt: otherID, sequence: 2, observed: epoch + thirtyDays, resolved: epoch + thirtyDays)
        let (_, owner) = try loaded([event(), fresh]); try owner.selectRetained(now: epoch + thirtyDays)
        let p = ActivityPresentation.make(owner.snapshot)
        try expect(owner.snapshot.events == [fresh] && p.retainedRange.contains(String(epoch + thirtyDays)) &&
                   !p.retainedRange.contains("10000000") && p.policy.contains("30") && p.policy.contains("2000") && p.policy.contains("2 MiB"),
                   "Retained range/policy fabricated")
    }
    check("retention: unrelated retry never extends original resolution") {
        let newer = event(id: otherID, attempt: otherID, sequence: 2, observed: epoch + thirtyDays, resolved: epoch + thirtyDays)
        let (_, owner) = try loaded([event(), newer]); try owner.selectRetained(now: epoch + thirtyDays)
        try expect(owner.snapshot.events == [newer], "Retry renewed old resolution")
    }
    check("quota: protected count exhaustion refuses visibly without dropping") {
        let protected = (1...2000).map { index in
            event(id: String(format: "BBBBBBBB-0000-4000-8000-%012d", index), attempt: attemptID,
                  status: .needsRecovery, sequence: UInt64(index), resolved: nil)
        }
        let (store, owner) = try loaded(protected); let before = try store.actual()
        try refused { try owner.appendSynthetic(event(id: "BBBBBBBB-0000-4000-8000-000000002001", sequence: 2001), now: epoch + thirtyDays) }
        let retained = try store.actual()
        try expect(owner.snapshot.events == protected && retained == before, "Protected quota silently evicted events")
    }
    check("quota: protected byte exhaustion refuses without eviction") {
        let protected = (1...2000).map { index in
            event(id: String(format: "BBBBBBBB-0000-4000-8000-%012d", index),
                  target: String(repeating: "t", count: 256), name: String(repeating: "n", count: 256),
                  status: .needsRecovery, sequence: UInt64(index), resolved: nil,
                  before: String(repeating: "b", count: 128), after: String(repeating: "a", count: 128),
                  beforeBuild: String(repeating: "c", count: 128), afterBuild: String(repeating: "d", count: 128),
                  run: runID, request: requestID, transaction: transactionID, parent: otherID)
        }
        var lower = 0; var upper = protected.count
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if try bytes(Array(protected.prefix(middle)), revision: 1).bytes.count <= 2_097_152 { lower = middle }
            else { upper = middle - 1 }
        }
        try expect(lower > 0 && lower < 2000, "Independent byte-quota setup failed")
        let retained = Array(protected.prefix(lower))
        let next = protected[lower]
        try expect(try bytes(retained + [next], revision: 2).bytes.count > 2_097_152, "New append does not exhaust byte quota")
        let (store, owner) = try loaded(retained); let before = try store.actual()
        try refused { try owner.appendSynthetic(next, now: epoch) }
        let after = try store.actual()
        try expect(owner.snapshot.events == retained && before == after, "Protected byte quota evicted history")
    }
    let localStatuses: [(ActivityStatus, String)] = [(.queued, "Queued"), (.started, "Started"), (.downloaded, "Downloaded"),
        (.succeeded, "Succeeded"), (.failed, "Failed"), (.deferred, "Deferred"), (.skipped, "Skipped"),
        (.incomplete, "Incomplete"), (.needsRecovery, "Needs recovery"), (.restored, "Restored")]
    for (status, label) in localStatuses {
        check("presentation: independently specified finite status " + label) {
            let e = event(name: literalName, status: status, before: "<b>1</b>", after: nil)
            let p = ActivityPresentation.make(ActivitySnapshot(available: true, revision: 1, events: [e]))
            try expect(p.rows.count == 1 && p.rows[0].eventID == eventID && p.rows[0].attemptID == attemptID,
                       "Presentation lost immutable row identity")
            try expect(p.rows[0].text.contains(label) && p.rows[0].text.contains(literalName) &&
                       p.rows[0].text.contains("<b>1</b>") && p.rows[0].text.contains("Unknown"), "Literal observations or finite status label missing")
            try expect(p.provenance == "Synthetic fixture only", "Presentation implied native provenance")
        }
    }
    check("overflow: maximum revision refuses append with exact retained bytes") {
        let (store, owner) = try loaded([], revision: UInt64.max); let before = try store.actual()
        try refused { try owner.appendSynthetic(event(), now: epoch) }
        try expect(try store.actual() == before && owner.snapshot.events.isEmpty, "Revision overflow wrapped")
    }
    check("overflow: maximum sequence refuses new event") {
        let old = event(sequence: UInt64.max); let (store, owner) = try loaded([old]); let before = try store.actual()
        try refused { try owner.appendSynthetic(event(id: otherID, attempt: otherID, sequence: 0), now: epoch) }
        try expect(try store.actual() == before && owner.snapshot.events == [old], "Ordering overflow wrapped")
    }
    check("cleanup scope: unrelated journal and backup sentinel stay byte exact") {
        let (store, owner) = try loaded([event()])
        let journal = store.directory.appendingPathComponent("journal-sentinel")
        let backup = store.directory.appendingPathComponent("backup-sentinel")
        let sentinel = Data("recovery authority is outside Activity".utf8)
        try sentinel.write(to: journal); try sentinel.write(to: backup)
        try owner.selectRetained(now: epoch + thirtyDays)
        try expect(try Data(contentsOf: journal) == sentinel && Data(contentsOf: backup) == sentinel, "History touched unrelated recovery material")
    }
}
