import Darwin
import Foundation
@_spi(Testing) import ArtifactInspection

// One stop caller on one owned thread. Only this box crosses that thread's
// boundary; its result is lock-confined, and the wrapped source synchronises
// its own operations. The product SPI wrapper gains no Sendable conformance.
private final class ArtifactShutdownStopBox: @unchecked Sendable {
    enum Outcome { case pending, success, failure(String) }
    private let lock = NSLock()
    private let source: LoopbackImageFixtureSource
    private var outcome: Outcome = .pending
    init(_ source: LoopbackImageFixtureSource) { self.source = source }
    func run() {
        let result: Outcome
        do { try source.stop(); result = .success }
        catch { result = .failure(String(describing: error)) }
        lock.lock(); outcome = result; lock.unlock()
    }
    func result() -> Outcome {
        lock.lock(); defer { lock.unlock() }
        return outcome
    }
}

@MainActor func registerArtifactLoopbackShutdownRaceChecks() {
    check("PAT-2710 artifact shutdown after actual accept before configuration joins cleanly") {
        try artifactShutdownRaceCheck()
    }
}

// Synchronous helper keeps bounded sleeps out of the async check closure.
@MainActor private func artifactShutdownRaceCheck() throws {
        let baseline = artifactShutdownDescriptorCount()
        let end = DispatchTime.now().uptimeNanoseconds + 5_500_000_000
        let root = try newDirectory("artifact-shutdown-race")
        var failure: Error?
        do {
            let input = root.appendingPathComponent("synthetic-held-image")
            let stage = root.appendingPathComponent("stage")
            try expect(mkdir(stage.path, 0o700) == 0, "artifact shutdown setup: exclusive private stage failed")
            try Data("abc".utf8).write(to: input, options: .withoutOverwriting)
            let pin = TargetPin(version: "synthetic-held-image-only", url: FirefoxTargets.pins[0].url,
                sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", byteLength: 3)
            try VerifiedImageFixtures.withLocalImage(path: input.path, pin: pin, workspace: stage.path) { handle in
                let gate = LoopbackImageFixtureConfigurationGate()
                defer { gate.release() }
                try handle.withLoopbackSource(configurationGate: gate) { source in
                    defer { gate.release() }
                    let sourceReader = source.readerDescriptor
                    let listener = source.listenerDescriptor
                    let connectStarted = DispatchTime.now().uptimeNanoseconds
                    let peer = try artifactShutdownConnect(source, until: min(end, connectStarted + 1_000_000_000))
                    defer { close(peer) }
                    try expect(gate.waitUntilAccepted(), "artifact shutdown setup: fixed gate did not observe actual accept")
                    try expect(source.metrics.running, "artifact shutdown setup: source stopped before stop caller")
                    print("ARTIFACT-SHUTDOWN-RACE fixed-gate-accepted")

                    let box = ArtifactShutdownStopBox(source)
                    let joined = DispatchGroup()
                    joined.enter()
                    let thread = Thread { box.run(); joined.leave() }
                    thread.start()
                    var didJoin = false
                    var cleanupJoined = true
                    var bodyFailure: Error?
                    do {
                        // Always release and join before the fixture wrapper's
                        // own cleanup, even when a setup assertion throws.
                        defer {
                            gate.release()
                            if !didJoin {
                                cleanupJoined = joined.wait(timeout: DispatchTime(uptimeNanoseconds: end)) == .success
                            }
                        }
                        // The earliest possible gate arrival is after connectStarted.
                        // Releasing inside 800ms proves its fixed one-second timeout
                        // cannot be the cause of an expected behavioural failure.
                        let releaseBy = min(end, connectStarted + 800_000_000)
                        while source.metrics.running && DispatchTime.now().uptimeNanoseconds < releaseBy {
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        try expect(!source.metrics.running && DispatchTime.now().uptimeNanoseconds < releaseBy,
                                   "artifact shutdown setup: stop transition not latched within gate allowance")
                        print("ARTIFACT-SHUTDOWN-RACE stopping-latched")
                        gate.release()
                        print("ARTIFACT-SHUTDOWN-RACE fixed-gate-released-before-timeout")
                        didJoin = joined.wait(timeout: .now() + 2) == .success
                        try expect(didJoin, "artifact shutdown: owned stop thread did not join within two seconds")
                        try expect(!source.metrics.running && source.readerDescriptor == -1 && source.listenerDescriptor == -1,
                                   "artifact shutdown: stopped source retained published reader/listener")
                        try expect(artifactShutdownClosed(sourceReader) && artifactShutdownClosed(listener),
                                   "artifact shutdown: source reader/listener descriptors remain open")
                        try expect(fcntl(handle.descriptor, F_GETFD) >= 0,
                                   "artifact shutdown: factory-owned verified image reader was closed")
                        try artifactShutdownPoll(peer, events: Int16(POLLIN), until: min(end, DispatchTime.now().uptimeNanoseconds + 500_000_000))
                        var byte: UInt8 = 0
                        let count = recv(peer, &byte, 1, 0)
                        let readErrno = errno
                        try expect(count == 0 || (count < 0 && readErrno == ECONNRESET),
                                   "artifact shutdown: zero-byte peer survived or received bytes")
                        try expect(source.metrics.servedBytes == 0, "artifact shutdown: zero-byte peer received image payload")
                        switch box.result() {
                        case .success: break
                        case .failure(let reason):
                            print("ARTIFACT-SHUTDOWN-RACE first-stop-failed \(reason)")
                            throw CheckFailure(description: "normal stop after accepted configuration race must succeed; got \(reason)")
                        case .pending: throw CheckFailure(description: "artifact shutdown: joined thread has no result")
                        }
                    } catch { bodyFailure = error }
                    try expect(cleanupJoined, "artifact shutdown cleanup: owned stop thread remains unjoined")
                    if let bodyFailure { throw bodyFailure }
                }
            }
        } catch { failure = error }
        // Only our exclusively created UUID tree is removed. No existing fixture
        // or repository input is repaired or recursively inspected.
        try FileManager.default.removeItem(at: root)
        try expect(artifactShutdownDescriptorCount() == baseline, "artifact shutdown: fixture/worker descriptor leak")
        try expect(DispatchTime.now().uptimeNanoseconds < end, "artifact shutdown: whole-case 5.5-second allowance exceeded")
        if let failure { throw failure }
}

private func artifactShutdownDescriptorCount() -> Int {
    (0..<512).reduce(0) { $0 + (fcntl(Int32($1), F_GETFD) >= 0 ? 1 : 0) }
}
private func artifactShutdownClosed(_ descriptor: Int32) -> Bool {
    descriptor >= 0 && fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
}
private func artifactShutdownPoll(_ descriptor: Int32, events: Int16, until end: UInt64) throws {
    for _ in 0..<64 {
        let now = DispatchTime.now().uptimeNanoseconds
        try expect(now < end, "artifact shutdown setup: numeric-peer readiness deadline")
        let milliseconds = Int32(min(50, max(1, (end - now) / 1_000_000)))
        var item = pollfd(fd: descriptor, events: events, revents: 0)
        let result = poll(&item, 1, milliseconds)
        let savedErrno = errno
        if result < 0 && savedErrno == EINTR { continue }
        if result == 0 { continue }
        try expect(result > 0 && item.revents & Int16(POLLNVAL) == 0 &&
                   item.revents & (events | Int16(POLLHUP) | Int16(POLLERR)) != 0,
                   "artifact shutdown setup: numeric-peer poll failed")
        return
    }
    throw CheckFailure(description: "artifact shutdown setup: finite poll allowance exhausted")
}
private func artifactShutdownConnect(_ source: LoopbackImageFixtureSource, until end: UInt64) throws -> Int32 {
    guard let parts = URLComponents(string: source.url), parts.scheme == "http", parts.host == "127.0.0.1",
          let port = parts.port, (1...65535).contains(port), parts.user == nil, parts.password == nil,
          parts.query == nil, parts.fragment == nil else {
        throw CheckFailure(description: "artifact shutdown setup: source is not numeric IPv4 loopback")
    }
    let peer = socket(AF_INET, SOCK_STREAM, 0)
    try expect(peer >= 0, "artifact shutdown setup: peer socket failed")
    do {
        let flags = fcntl(peer, F_GETFL)
        try expect(flags >= 0 && fcntl(peer, F_SETFD, FD_CLOEXEC) == 0 &&
                   fcntl(peer, F_SETFL, flags | O_NONBLOCK) == 0, "artifact shutdown setup: peer flags failed")
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)
        address.sin_port = UInt16(port).bigEndian
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(peer, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let savedErrno = errno
        try expect(result == 0 || (result < 0 && [EINPROGRESS, EINTR].contains(savedErrno)),
                   "artifact shutdown setup: numeric-peer connect failed")
        if result != 0 { try artifactShutdownPoll(peer, events: Int16(POLLOUT), until: end) }
        var socketError: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        try expect(getsockopt(peer, SOL_SOCKET, SO_ERROR, &socketError, &size) == 0 &&
                   size == socklen_t(MemoryLayout<Int32>.size) && socketError == 0 &&
                   DispatchTime.now().uptimeNanoseconds < end,
                   "artifact shutdown setup: numeric-peer connection did not complete")
        return peer
    } catch { close(peer); throw error }
}
