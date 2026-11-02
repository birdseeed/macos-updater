import Foundation
import Darwin

// A bounded byte bridge for the OS image reader. No pathname, URL, JSON value
// or SPI boolean constructs image authority; the constructor retains the actual
// VerifiedImage and duplicates its already verified, unlinked read-only reader.
final class LoopbackImageSource: @unchecked Sendable {
    private struct Limits {
        let requests: Int
        let bytes: Int64
        let lifetime: Double
        let header: Double
        init(length: Int64, requests: Int = 8192, bytes: Int64? = nil,
             lifetime: Double = 180, header: Double = 2) throws {
            let (cap, overflow) = length.multipliedReportingOverflow(by: 8)
            guard length > 0, !overflow, requests > 0, requests <= 8192,
                  lifetime.isFinite, lifetime > 0, lifetime <= 180,
                  header.isFinite, header > 0, header <= 2,
                  (bytes ?? cap) > 0, (bytes ?? cap) <= cap else { throw InspectionFailure.invalidMetadata }
            self.requests = requests; self.bytes = bytes ?? cap
            self.lifetime = lifetime; self.header = header
        }
    }
    private enum ClientFailure: Error { case closed }
    private struct Request {
        let head: Bool
        let start: Int64
        let count: Int64
        let ranged: Bool
    }
    private let owner: VerifiedImage
    private let reader: VerifiedImageReader
    private let limits: Limits
    private let configurationGate: LoopbackImageFixtureConfigurationGate?
    private let path: String
    private let host: String
    let url: String
    private let deadline: UInt64
    // All mutable state and descriptor publication/invalidation use this lock.
    // The one worker alone reads, polls, accepts, sends and actually closes fds.
    // stop() only sets the flag and shutdowns currently published sockets while
    // holding the same lock, so it can never act on a recycled descriptor.
    private let lock = NSLock()
    private let completion = DispatchGroup()
    private var listener: Int32
    private var client: Int32 = -1
    private var publishedReader: Int32
    private var stopping = false
    private var running = true
    private var failed = false
    private var requests = 0
    private var servedBytes: Int64 = 0

    static func start(image: VerifiedImage) throws -> LoopbackImageSource {
        try create(image: image, limits: Limits(length: image.byteLength), configurationGate: nil)
    }
    static func fixture(image: VerifiedImage, limits: LoopbackImageFixtureLimits,
                        configurationGate: LoopbackImageFixtureConfigurationGate?) throws -> LoopbackImageSource {
        try create(image: image, limits: Limits(length: image.byteLength, requests: limits.maximumRequests,
            bytes: limits.maximumBytes, lifetime: limits.lifetimeSeconds, header: limits.headerSeconds),
            configurationGate: configurationGate)
    }
    private static func create(image: VerifiedImage, limits: Limits,
                               configurationGate: LoopbackImageFixtureConfigurationGate?) throws -> LoopbackImageSource {
        let reader = try image.duplicateLoopbackReader()
        var listener: Int32 = -1
        do {
            listener = socket(AF_INET, SOCK_STREAM, 0)
            guard listener >= 0 else { throw InspectionFailure.commandFailed }
            try configureSocket(listener)
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            // No reuse option, wildcard bind, name lookup or outbound connect.
            guard bound == 0, listen(listener, 8) == 0 else { throw InspectionFailure.commandFailed }
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) }
            }
            guard named == 0, size == MemoryLayout<sockaddr_in>.size,
                  address.sin_family == sa_family_t(AF_INET), address.sin_port != 0,
                  address.sin_addr.s_addr == UInt32(0x7f000001).bigEndian else { throw InspectionFailure.commandFailed }
            // arc4random_buf uses the OS random source and needs no file or key.
            var random = [UInt8](repeating: 0, count: 32)
            random.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
            let token = random.map { String(format: "%02x", $0) }.joined()
            let source = LoopbackImageSource(image: image, reader: reader, listener: listener,
                port: UInt16(bigEndian: address.sin_port), token: token, limits: limits,
                configurationGate: configurationGate)
            source.completion.enter()
            // No retained Thread or callback closes descriptors after this worker.
            Thread.detachNewThread { source.work() }
            return source
        } catch {
            if listener >= 0 { close(listener) }
            close(reader.descriptor)
            throw error
        }
    }
    private init(image: VerifiedImage, reader: VerifiedImageReader, listener: Int32,
                 port: UInt16, token: String, limits: Limits,
                 configurationGate: LoopbackImageFixtureConfigurationGate?) {
        owner = image; self.reader = reader; self.listener = listener
        self.configurationGate = configurationGate
        publishedReader = reader.descriptor; self.limits = limits
        host = "127.0.0.1:\(port)"; path = "/\(token)/artifact.dmg"
        url = "http://\(host)\(path)"
        deadline = Self.after(limits.lifetime)
    }
    private static func after(_ seconds: Double) -> UInt64 {
        DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1_000_000_000)
    }
    private static func configureSocket(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        var noSignal: Int32 = 1
        guard flags >= 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw InspectionFailure.commandFailed
        }
    }
    var listenerDescriptor: Int32 { lock.lock(); defer { lock.unlock() }; return listener }
    var readerDescriptor: Int32 { lock.lock(); defer { lock.unlock() }; return publishedReader }
    var metrics: LoopbackImageFixtureMetrics {
        lock.lock(); defer { lock.unlock() }
        return .init(requests: requests, servedBytes: servedBytes, running: running && !stopping && !failed)
    }
    private func active() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running && !stopping && !failed && DispatchTime.now().uptimeNanoseconds < deadline
    }
    func isOwned(by image: VerifiedImage) -> Bool { owner === image }
    func nativeAttachArguments(mountPath: String) throws -> [String] {
        guard active() else { throw InspectionFailure.invalidMetadata }
        guard mountPath.utf8.count < Int(MAXPATHLEN), safeEvidencePath(mountPath), mountPath != "/",
              !mountPath.hasSuffix("/") else { throw InspectionFailure.unsafePath }
        return ["attach", "-readonly", "-nobrowse", "-plist", "-mountpoint", mountPath, url]
    }
    func nativeAttachAllowed(executable: String, arguments: [String]) -> Bool {
        guard executable == "/usr/bin/hdiutil", arguments.count == 7,
              let canonical = try? nativeAttachArguments(mountPath: arguments[5]) else { return false }
        return arguments == canonical
    }
    func stop() throws {
        lock.lock()
        stopping = true
        if listener >= 0 { _ = shutdown(listener, SHUT_RDWR) }
        if client >= 0 { _ = shutdown(client, SHUT_RDWR) }
        lock.unlock()
        // Reusable completion state: repeated and concurrent stop calls all join
        // the same worker. The worker never calls stop(), avoiding self-join.
        guard completion.wait(timeout: .now() + 2) == .success else { throw InspectionFailure.cleanupFailed }
        lock.lock(); let bad = failed; lock.unlock()
        guard !bad else { throw InspectionFailure.cleanupFailed }
    }
    private func closeClient() {
        lock.lock(); defer { lock.unlock() }
        if client >= 0 { let fd = client; client = -1; close(fd) }
    }
    private func finish() {
        closeClient()
        lock.lock()
        if listener >= 0 { let fd = listener; listener = -1; close(fd) }
        if publishedReader >= 0 { let fd = publishedReader; publishedReader = -1; close(fd) }
        running = false
        lock.unlock()
        completion.leave()
    }
    private func work() {
        defer { finish() }
        while active() {
            lock.lock(); let capped = requests >= limits.requests; let fd = listener; lock.unlock()
            if capped { return }
            do { try wait(fd, events: Int16(POLLIN), until: deadline) }
            catch { return }
            let accepted = accept(fd, nil, nil)
            if accepted < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                return
            }
            lock.lock()
            requests += 1 // Includes malformed and incomplete connections.
            lock.unlock()
            // Keep setup private so stop() cannot shutdown the socket before
            // SO_NOSIGPIPE is configured. The worker still owns every close.
            do {
                try configurationGate?.pauseBeforeConfiguration()
                try Self.configureSocket(accepted)
            } catch {
                close(accepted)
                lock.lock(); failed = true; lock.unlock()
                return
            }
            lock.lock()
            client = accepted
            let cancelled = stopping
            lock.unlock()
            if cancelled { closeClient(); return }
            do {
                let connectionDeadline = min(deadline, Self.after(30))
                try serve(accepted, until: connectionDeadline)
            } catch is ClientFailure {
                // An aborted/malformed client cannot poison later requests.
            } catch {
                lock.lock(); failed = true; lock.unlock()
            }
            closeClient()
        }
    }
    private func wait(_ fd: Int32, events: Int16, until end: UInt64) throws {
        while active() {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < end else { throw ClientFailure.closed }
            var item = pollfd(fd: fd, events: events, revents: 0)
            let milliseconds = Int32(min(50, max(1, (end - now) / 1_000_000)))
            let result = poll(&item, 1, milliseconds)
            if result < 0 && errno == EINTR { continue }
            if result == 0 { continue }
            guard result > 0, item.revents & Int16(POLLNVAL) == 0 else { throw ClientFailure.closed }
            if item.revents & events != 0 { return }
            if item.revents & (Int16(POLLHUP) | Int16(POLLERR)) != 0 { throw ClientFailure.closed }
        }
        throw ClientFailure.closed
    }
    private func header(_ fd: Int32, until end: UInt64) throws -> Data? {
        var data = Data()
        let marker = Data([13, 10, 13, 10])
        var bytes = [UInt8](repeating: 0, count: 1024)
        while data.count < 8192 {
            try wait(fd, events: Int16(POLLIN), until: end)
            let n = recv(fd, &bytes, min(bytes.count, 8192 - data.count), 0)
            if n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard n > 0 else { throw ClientFailure.closed }
            data.append(contentsOf: bytes.prefix(n))
            if let delimiter = data.range(of: marker) {
                // Reject body bytes or a pipelined request already in the buffer.
                guard delimiter.upperBound == data.endIndex else { return nil }
                return Data(data[..<delimiter.lowerBound])
            }
        }
        return nil
    }
    private func parse(_ data: Data) -> Request? {
        guard data.allSatisfy({ $0 == 13 || $0 == 10 || (32...126).contains($0) }),
              let text = String(data: data, encoding: .ascii) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let words = first.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count == 3, words[0] == "GET" || words[0] == "HEAD",
              words[1] == Substring(path), words[2] == "HTTP/1.1" else { return nil }
        var fields: [String: String] = [:]
        let punctuation = Set("!#$%&'*+-.^_`|~".utf8)
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon]
            guard !name.isEmpty, name.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || punctuation.contains($0)
            }) else { return nil }
            let key = name.lowercased()
            guard fields[key] == nil else { return nil }
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: " "))
            guard value.utf8.allSatisfy({ (32...126).contains($0) }) else { return nil }
            fields[key] = value
        }
        guard fields["host"] == host else { return nil }
        for forbidden in ["content-length", "transfer-encoding", "content-encoding", "content-range",
                          "expect", "trailer", "te", "upgrade", "proxy-connection", "proxy-authorization"] {
            guard fields[forbidden] == nil else { return nil }
        }
        let length = Int64(reader.length)
        guard let range = fields["range"] else {
            return Request(head: words[0] == "HEAD", start: 0, count: length, ranged: false)
        }
        guard range.hasPrefix("bytes=") else { return nil }
        let bounds = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return nil }
        func number(_ value: Substring) -> Int64? {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int64(value)
        }
        let start: Int64, last: Int64
        if bounds[0].isEmpty {
            guard let suffix = number(bounds[1]), suffix > 0 else { return nil }
            start = max(0, length - suffix); last = length - 1
        } else {
            guard let lower = number(bounds[0]), lower < length else { return nil }
            start = lower
            if bounds[1].isEmpty { last = length - 1 }
            else {
                guard let upper = number(bounds[1]), upper >= start else { return nil }
                last = min(upper, length - 1)
            }
        }
        return Request(head: words[0] == "HEAD", start: start, count: last - start + 1, ranged: true)
    }
    private func send(_ data: Data, to fd: Int32, until end: UInt64, payload: Bool = false) throws {
        var offset = 0
        while offset < data.count {
            try wait(fd, events: Int16(POLLOUT), until: end)
            let n = data.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: offset), data.count - offset, 0) }
            if n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard n > 0 else { throw ClientFailure.closed }
            offset += n
            if payload { lock.lock(); servedBytes += Int64(n); lock.unlock() }
        }
    }
    private func refuse(_ fd: Int32, until end: UInt64) throws {
        try send(Data("HTTP/1.1 400 Bad Request\r\nContent-Type: application/octet-stream\r\nContent-Length: 0\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n".utf8), to: fd, until: end)
    }
    private func serve(_ fd: Int32, until end: UInt64) throws {
        guard let header = try header(fd, until: min(end, Self.after(limits.header))), let request = parse(header) else {
            try refuse(fd, until: end); return
        }
        // One worker serialises requests, so this checks the whole prospective
        // payload against actual sent bytes before any body or success header.
        lock.lock(); let remaining = limits.bytes - servedBytes; lock.unlock()
        guard request.head || request.count <= remaining else { try refuse(fd, until: end); return }
        try reader.validate()
        let status = request.ranged ? "206 Partial Content" : "200 OK"
        var response = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(request.count)\r\nAccept-Ranges: bytes\r\nConnection: close\r\n"
        if request.ranged { response += "Content-Range: bytes \(request.start)-\(request.start + request.count - 1)/\(reader.length)\r\n" }
        response += "\r\n"
        try send(Data(response.utf8), to: fd, until: end)
        if request.head { return }
        var offset = request.start
        let last = request.start + request.count
        while offset < last {
            guard active(), DispatchTime.now().uptimeNanoseconds < end else { throw ClientFailure.closed }
            let bytes = try reader.read(offset: offset, count: Int(min(65536, last - offset)))
            try send(bytes, to: fd, until: end, payload: true)
            offset += Int64(bytes.count)
        }
    }
}

// Fixed fixture-only interleaving, without callbacks, descriptor input or custom
// deadlines. Mutable flags are lock-confined; semaphore waits hold no source lock.
@_spi(Testing) public final class LoopbackImageFixtureConfigurationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let arrived = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private var didArrive = false
    private var didRelease = false
    public init() {}
    public func waitUntilAccepted() -> Bool {
        lock.lock(); let alreadyArrived = didArrive; lock.unlock()
        if alreadyArrived { return true }
        return arrived.wait(timeout: .now() + 1) == .success
    }
    public func release() {
        lock.lock()
        let signal = !didRelease
        didRelease = true
        lock.unlock()
        if signal { released.signal() }
    }
    public func resume() { release() }
    func pauseBeforeConfiguration() throws {
        lock.lock()
        let first = !didArrive
        didArrive = true
        lock.unlock()
        guard first else { return }
        arrived.signal()
        guard released.wait(timeout: .now() + 1) == .success else { throw InspectionFailure.commandFailed }
    }
}

// Testing SPI wraps that same live internal source. It cannot create a source,
// change its owner or turn the URL/command-shape predicate into command authority.
@_spi(Testing) public struct LoopbackImageFixtureLimits {
    public var maximumRequests: Int
    public var maximumBytes: Int64?
    public var lifetimeSeconds: Double
    public var headerSeconds: Double
    public init(maximumRequests: Int = 8192, maximumBytes: Int64? = nil,
                lifetimeSeconds: Double = 180, headerSeconds: Double = 2) {
        self.maximumRequests = maximumRequests; self.maximumBytes = maximumBytes
        self.lifetimeSeconds = lifetimeSeconds; self.headerSeconds = headerSeconds
    }
}
@_spi(Testing) public struct LoopbackImageFixtureMetrics {
    public let requests: Int
    public let servedBytes: Int64
    public let running: Bool
}
@_spi(Testing) public final class LoopbackImageFixtureSource {
    private let source: LoopbackImageSource
    init(_ source: LoopbackImageSource) { self.source = source }
    public var url: String { source.url }
    public var listenerDescriptor: Int32 { source.listenerDescriptor }
    public var readerDescriptor: Int32 { source.readerDescriptor }
    public var metrics: LoopbackImageFixtureMetrics { source.metrics }
    public func stop() throws { try source.stop() }
    public func nativeAttachArguments(mountPath: String) throws -> [String] { try source.nativeAttachArguments(mountPath: mountPath) }
    public func nativeAttachAllowed(executable: String, arguments: [String]) -> Bool {
        source.nativeAttachAllowed(executable: executable, arguments: arguments)
    }
}
