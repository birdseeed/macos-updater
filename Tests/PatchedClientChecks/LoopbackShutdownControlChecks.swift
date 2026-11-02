import Darwin
import Foundation

// Platform control only: no HTTP bytes, product object, app, or installed target.
// Each scenario owns one listener, one connecting peer, and one accepted socket.
@MainActor func registerLoopbackShutdownControlChecks() {
    check("loopback shutdown control: measure configureSocket before and after accepted shutdown") {
        var report: [String] = []
        defer {
            let output = report.joined(separator: "\n")
            // Entries contain fixed operation names and bounded integer results only.
            print(String(output.prefix(2_048)))
        }
        try loopbackShutdownScenario(shutdownFirst: false, report: &report)
        try loopbackShutdownScenario(shutdownFirst: true, report: &report)
    }
}

private func loopbackShutdownScenario(shutdownFirst: Bool, report: inout [String]) throws {
    let tag = shutdownFirst ? "after-shutdown" : "before-shutdown"
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    var listener: Int32 = -1
    var peer: Int32 = -1
    var accepted: Int32 = -1
    var cleanupOK = true
    var failure: Error?
    let loopback = inet_addr("127.0.0.1")

    func bounded() throws {
        try expect(DispatchTime.now().uptimeNanoseconds < deadline, "shutdown control \(tag): absolute two-second deadline")
    }
    func require(_ result: Int32, _ operation: String) throws {
        let savedErrno = errno
        try expect(result == 0, "shutdown control \(tag): \(operation) result=\(result) errno=\(savedErrno)")
        try bounded()
    }
    func nonblocking(_ descriptor: Int32) throws {
        try bounded()
        errno = 0
        let flags = fcntl(descriptor, F_GETFL)
        let savedErrno = errno
        try expect(flags >= 0, "shutdown control \(tag): setup F_GETFL errno=\(savedErrno)")
        errno = 0
        try require(fcntl(descriptor, F_SETFL, flags | O_NONBLOCK), "setup F_SETFL")
    }
    func waitReady(_ descriptor: Int32, _ events: Int16) throws {
        // A finite EINTR/readiness allowance within the single absolute deadline.
        for _ in 0..<64 {
            let now = DispatchTime.now().uptimeNanoseconds
            try expect(now < deadline, "shutdown control \(tag): absolute two-second deadline")
            let remaining = deadline - now
            let milliseconds = Int32(min(2_000, (remaining + 999_999) / 1_000_000))
            var item = pollfd(fd: descriptor, events: events, revents: 0)
            errno = 0
            let result = poll(&item, 1, milliseconds)
            let savedErrno = errno
            if result < 0 && savedErrno == EINTR { continue }
            try expect(result > 0 && item.revents & Int16(POLLNVAL) == 0,
                       "shutdown control \(tag): poll result=\(result) errno=\(savedErrno)")
            try expect(item.revents & events != 0, "shutdown control \(tag): poll did not report requested readiness")
            try bounded()
            return
        }
        throw CheckFailure(description: "shutdown control \(tag): finite readiness allowance exhausted")
    }
    func address(_ descriptor: Int32, peerAddress: Bool = false) throws -> sockaddr_in {
        try bounded()
        var value = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        errno = 0
        let result = withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                peerAddress ? getpeername(descriptor, $0, &length) : getsockname(descriptor, $0, &length)
            }
        }
        try require(result, peerAddress ? "getpeername" : "getsockname")
        try expect(length == socklen_t(MemoryLayout<sockaddr_in>.size) &&
                   value.sin_family == sa_family_t(AF_INET) && value.sin_addr.s_addr == loopback && value.sin_port != 0,
                   "shutdown control \(tag): endpoint is not numeric IPv4 loopback with an assigned port")
        return value
    }
    func measure(_ operation: String, _ call: () -> Int32) throws -> Int32 {
        try bounded()
        errno = 0
        let result = call()
        let savedErrno = errno
        report.append("SHUTDOWN-CONTROL \(tag) \(operation) result=\(result) errno=\(savedErrno)")
        try bounded()
        return result
    }
    func configure() throws {
        // Same calls, arguments and order as LoopbackImageSource.configureSocket.
        // Measure all four calls even if one fails; post-shutdown results are observations.
        let flags = try measure("F_GETFL") { fcntl(accepted, F_GETFL) }
        let cloexec = try measure("F_SETFD") { fcntl(accepted, F_SETFD, FD_CLOEXEC) }
        let nonblock = try measure("F_SETFL") { fcntl(accepted, F_SETFL, flags | O_NONBLOCK) }
        var noSignal: Int32 = 1
        let noSIGPIPE = try measure("SO_NOSIGPIPE") {
            setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        }
        if !shutdownFirst {
            try expect(flags >= 0 && cloexec == 0 && nonblock == 0 && noSIGPIPE == 0,
                       "shutdown control before-shutdown: positive configure control failed")
        }
    }

    do {
        // All owned descriptors are closed exactly once, including on setup failure.
        defer {
            for (operation, descriptor) in [("close-accepted", accepted), ("close-peer", peer), ("close-listener", listener)] where descriptor >= 0 {
                errno = 0
                let result = close(descriptor)
                let savedErrno = errno
                report.append("SHUTDOWN-CONTROL \(tag) \(operation) result=\(result) errno=\(savedErrno)")
                if result != 0 { cleanupOK = false }
            }
        }
        try bounded()
        errno = 0
        listener = socket(AF_INET, SOCK_STREAM, 0)
        let listenerErrno = errno
        try expect(listener >= 0, "shutdown control \(tag): listener socket errno=\(listenerErrno)")
        try nonblocking(listener)
        var requested = sockaddr_in()
        requested.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        requested.sin_family = sa_family_t(AF_INET)
        requested.sin_addr = in_addr(s_addr: loopback)
        requested.sin_port = 0
        errno = 0
        let bindResult = withUnsafePointer(to: &requested) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try require(bindResult, "bind")
        let bound = try address(listener)
        errno = 0
        try require(listen(listener, 1), "listen")
        errno = 0
        peer = socket(AF_INET, SOCK_STREAM, 0)
        let peerErrno = errno
        try expect(peer >= 0, "shutdown control \(tag): peer socket errno=\(peerErrno)")
        try nonblocking(peer)
        var target = bound
        errno = 0
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(peer, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let connectErrno = errno
        try expect(connected == 0 || (connected == -1 && [EINPROGRESS, EINTR].contains(connectErrno)),
                   "shutdown control \(tag): connect result=\(connected) errno=\(connectErrno)")
        if connected != 0 { try waitReady(peer, Int16(POLLOUT)) }
        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        errno = 0
        try require(getsockopt(peer, SOL_SOCKET, SO_ERROR, &socketError, &errorLength), "connect SO_ERROR")
        try expect(errorLength == socklen_t(MemoryLayout<Int32>.size) && socketError == 0,
                   "shutdown control \(tag): connection did not complete errno=\(socketError)")
        let peerLocal = try address(peer)
        var acceptedPeer = sockaddr_in()
        var acceptedLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        for _ in 0..<64 {
            try waitReady(listener, Int16(POLLIN))
            errno = 0
            accepted = withUnsafeMutablePointer(to: &acceptedPeer) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(listener, $0, &acceptedLength) }
            }
            let acceptErrno = errno
            if accepted >= 0 { break }
            try expect([EINTR, EAGAIN, EWOULDBLOCK].contains(acceptErrno),
                       "shutdown control \(tag): accept errno=\(acceptErrno)")
        }
        try expect(accepted >= 0, "shutdown control \(tag): no actual accepted descriptor")
        try expect(acceptedLength == socklen_t(MemoryLayout<sockaddr_in>.size) &&
                   acceptedPeer.sin_family == sa_family_t(AF_INET) && acceptedPeer.sin_addr.s_addr == loopback &&
                   acceptedPeer.sin_port == peerLocal.sin_port,
                   "shutdown control \(tag): accepted peer identity differs from the owned connection")
        let acceptedRemote = try address(accepted, peerAddress: true)
        let acceptedLocal = try address(accepted)
        try expect(acceptedRemote.sin_port == peerLocal.sin_port && acceptedLocal.sin_port == bound.sin_port,
                   "shutdown control \(tag): accepted endpoints differ from owned peer and listener")
        report.append("SHUTDOWN-CONTROL \(tag) actual-accept-and-peer-identity verified")
        if shutdownFirst {
            try expect(try measure("SHUT_RDWR") { shutdown(accepted, SHUT_RDWR) } == 0,
                       "shutdown control \(tag): shutdown failed")
            try configure()
        } else {
            try configure()
            try expect(try measure("SHUT_RDWR") { shutdown(accepted, SHUT_RDWR) } == 0,
                       "shutdown control \(tag): shutdown failed")
        }
        // No operation closes the peer until the deferred cleanup; it stays owned/open.
        errno = 0
        let peerFlags = fcntl(peer, F_GETFD)
        let peerFlagsErrno = errno
        try expect(peerFlags >= 0, "shutdown control \(tag): original peer no longer open errno=\(peerFlagsErrno)")
        try bounded()
    } catch { failure = error }
    try expect(cleanupOK, "shutdown control \(tag): owned descriptor close failed")
    try bounded()
    if let failure { throw failure }
}
