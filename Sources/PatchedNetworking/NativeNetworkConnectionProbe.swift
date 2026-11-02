import Combine
import Foundation
import CFNetwork
import Darwin

public enum NativeConnectionProbeRefusal: String, Equatable, Sendable {
    case notApplied, unsupportedEndpoint, unsupportedProxy, offline, busy, cancelled
    case changedSettings, authenticationRequired, transportFailed, responseTooLarge
}
public enum NativeConnectionProbeOutcome: Equatable, Sendable {
    case response(statusCode: Int, bytes: Int)
    case refused(NativeConnectionProbeRefusal)
}

/// An explicit, session-only controlled HTTP probe, not updater transport.
/// Construction and settings changes never start a request. Manual proxy support
/// is restricted to an unauthenticated literal IPv4 loopback HTTP proxy.
@MainActor public final class NativeNetworkConnectionProbe {
    public private(set) var isRunning = false
    private let settings: NativeNetworkSettingsController
    private var subscriptions: Set<AnyCancellable> = []
    private var active: Operation?
    private var worker: ProbeWorker?
    private var publishedRevision: UInt64
    private var publishedChoice: NativeNetworkChoice?
    private var publishedSnapshot: NativeNetworkSettingsSnapshot?
    private var publishedRefreshing: Bool

    private struct Operation {
        let id: UUID
        let revision: UInt64
        let choice: NativeNetworkChoice
        let completion: @MainActor (NativeConnectionProbeOutcome) -> Void
    }

    public init(settings: NativeNetworkSettingsController) {
        self.settings = settings
        publishedRevision = settings.revision
        publishedChoice = settings.choice
        publishedSnapshot = settings.snapshot
        publishedRefreshing = settings.isRefreshing
        // Published emits before assignment. Inspect incoming invalidation values now,
        // then validate actual retained state after the synchronous mutation completes.
        settings.$revision.dropFirst().sink { [weak self] revision in
            guard let self else { return }
            self.publishedRevision = revision
            if let active = self.active, revision != active.revision { self.invalidate() }
            self.validateAfterChange()
        }.store(in: &subscriptions)
        settings.$choice.dropFirst().sink { [weak self] choice in
            guard let self else { return }
            self.publishedChoice = choice
            if let active = self.active, choice != active.choice { self.invalidate() }
            self.validateAfterChange()
        }.store(in: &subscriptions)
        settings.$isRefreshing.dropFirst().sink { [weak self] refreshing in
            guard let self else { return }
            self.publishedRefreshing = refreshing
            if refreshing { self.invalidate() }
            self.validateAfterChange()
        }.store(in: &subscriptions)
        settings.$snapshot.dropFirst().sink { [weak self] snapshot in
            guard let self else { return }
            self.publishedSnapshot = snapshot
            self.invalidate()
            self.validateAfterChange()
        }.store(in: &subscriptions)
    }

    public func start(url: URL, completion: @escaping @MainActor (NativeConnectionProbeOutcome) -> Void) {
        guard active == nil else { completion(.refused(.busy)); return }
        guard publicationSettled, let choice = settings.choice, !settings.isRefreshing else {
            completion(.refused(.notApplied)); return
        }
        guard Self.supported(url) else { completion(.refused(.unsupportedEndpoint)); return }
        guard settings.snapshot?.observation.path != .offline else {
            completion(.refused(.offline)); return
        }
        let manualProxyPort: Int?
        if choice.mode == .manualHTTP {
            // Apply validates a broader descriptive draft. Transport authority is
            // narrower: never resolve aliases or attempt a non-loopback proxy.
            guard choice.host == "127.0.0.1", let port = choice.port,
                  (1...65535).contains(port) else {
                completion(.refused(.unsupportedProxy)); return
            }
            guard #available(macOS 14.0, *) else {
                completion(.refused(.unsupportedProxy)); return
            }
            manualProxyPort = port
        } else { manualProxyPort = nil }
        let id = UUID()
        active = Operation(id: id, revision: settings.revision, choice: choice, completion: completion)
        isRunning = true
        let worker = ProbeWorker(url: url, system: choice.mode == .system,
                                 manualProxyPort: manualProxyPort) { [weak self] outcome in
            Task { @MainActor [weak self] in self?.receive(outcome, id: id) }
        }
        self.worker = worker
        worker.start()
    }

    public func cancel() { finish(.refused(.cancelled)) }

    private static func supported(_ url: URL) -> Bool {
        // Match original serialized authority/path, avoiding URL host normalization,
        // decoded paths, aliases, user info, empty query/fragment and default ports.
        let raw = url.absoluteString
        guard raw.utf8.count <= 128, raw.hasSuffix("/probe") else { return false }
        let prefixes = ["http://127.0.0.1:", "http://[::1]:"]
        guard let prefix = prefixes.first(where: { raw.hasPrefix($0) }) else { return false }
        let port = raw.dropFirst(prefix.count).dropLast(6)
        guard (1...5).contains(port.count), port.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(port), (1...65535).contains(number) else { return false }
        return true
    }

    private func validateAfterChange() {
        guard let id = active?.id else { return }
        Task { @MainActor [weak self] in
            guard let self, self.active?.id == id else { return }
            if !self.isCurrent { self.invalidate() }
        }
    }
    // A completion may reenter start from inside a willSet subscriber. Comparing
    // incoming published values with stored state refuses that half-mutated state,
    // while allowing an immediate explicit start after edit/apply returns.
    private var publicationSettled: Bool {
        settings.revision == publishedRevision && settings.choice == publishedChoice &&
        settings.snapshot == publishedSnapshot && settings.isRefreshing == publishedRefreshing
    }
    private var isCurrent: Bool {
        guard let active else { return false }
        return publicationSettled && settings.revision == active.revision && settings.choice == active.choice && !settings.isRefreshing
    }
    private func invalidate() { finish(.refused(.changedSettings)) }
    private func receive(_ outcome: NativeConnectionProbeOutcome, id: UUID) {
        guard active?.id == id else { return }
        finish(isCurrent ? outcome : .refused(.changedSettings))
    }
    private func finish(_ outcome: NativeConnectionProbeOutcome) {
        guard let previous = active else { return }
        // Release all authority before cancellation or arbitrary caller reentrancy.
        active = nil; isRunning = false
        let previousWorker = worker; worker = nil
        previousWorker?.cancel()
        previous.completion(outcome)
    }
    deinit { worker?.cancel() }
}

// All mutable worker fields and delegate callbacks belong to one serial queue.
// unchecked Sendable expresses only this private queue confinement.
private final class ProbeWorker: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "im.patched.controlled-network-probe")
    private let url: URL
    private let system: Bool
    private let manualProxyPort: Int?
    private var completion: (@Sendable (NativeConnectionProbeOutcome) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var timer: DispatchSourceTimer?
    private var finished = false
    private var status: Int?
    private var bytes = 0
    private var deadline: DispatchTime?
    private var descriptor: Int32?
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var readSourceResumed = false
    private var sourceOwners = 0
    private var connecting = false
    private var requestBytes: [UInt8] = []
    private var written = 0
    private var manualResponse = ManualProxyProbeResponseParser()

    init(url: URL, system: Bool, manualProxyPort: Int?,
         completion: @escaping @Sendable (NativeConnectionProbeOutcome) -> Void) {
        self.url = url; self.system = system; self.manualProxyPort = manualProxyPort
        self.completion = completion
    }
    func start() {
        queue.async { [self] in
            guard !finished else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            let deadline = DispatchTime.now() + .seconds(5)
            self.deadline = deadline
            timer.schedule(deadline: deadline)
            timer.setEventHandler { [weak self] in self?.finish(.refused(.transportFailed)) }
            timer.resume()
            if system {
                // Copy may block inside the OS. It cannot block the main actor or
                // delay the deadline, and a late copy never starts a session.
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let raw = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
                    let current = NativeNetworkProxySnapshot.classify(raw)
                    self?.systemResult(current)
                }
            } else { connect() }
        }
    }
    private func systemResult(_ current: NativeNetworkProxy) {
        queue.async { [self] in
            guard !finished else { return }
            // Conservatively support only a current, unscoped, proxy-free system
            // configuration. Never evaluate PAC or silently bypass a selected proxy.
            guard current == .noConfiguredProxy else { finish(.refused(.unsupportedProxy)); return }
            connect()
        }
    }
    private func connect() {
        guard !finished else { return }
        if let manualProxyPort {
            connectManual(port: manualProxyPort)
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0
        ]
        let delegates = OperationQueue()
        delegates.maxConcurrentOperationCount = 1
        delegates.underlyingQueue = queue
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegates)
        self.session = session
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }
    private func connectManual(port: Int) {
        guard #available(macOS 14.0, *), let port = UInt16(exactly: port), port > 0 else {
            finish(.refused(.unsupportedProxy)); return
        }
        // The accepted origin is request text only. This is the sole connect call
        // in the manual branch: numeric AF_INET 127.0.0.1, no resolver or retry.
        let raw = url.absoluteString
        let authority = raw.dropFirst("http://".count).dropLast("/probe".count)
        requestBytes = Array(("GET \(raw) HTTP/1.1\r\nHost: \(authority)\r\n" +
            "Connection: close\r\nAccept-Encoding: identity\r\n\r\n").utf8)
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { finish(.refused(.transportFailed)); return }
        descriptor = fd
        let descriptorFlags = fcntl(fd, F_GETFD)
        let statusFlags = fcntl(fd, F_GETFL)
        var noSignal: Int32 = 1
        guard descriptorFlags >= 0, statusFlags >= 0,
              fcntl(fd, F_SETFD, descriptorFlags | FD_CLOEXEC) == 0,
              fcntl(fd, F_SETFL, statusFlags | O_NONBLOCK) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                         socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            finish(.refused(.transportFailed)); return
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: UInt32(0x7f000001).bigEndian)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 || (result == -1 && errno == EINPROGRESS) else {
            finish(.refused(.transportFailed)); return
        }
        connecting = result != 0
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let writer = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        readSource = reader; writeSource = writer; sourceOwners = 2
        reader.setEventHandler { [weak self] in self?.readManual() }
        writer.setEventHandler { [weak self] in self?.writeManual() }
        // Both cancel handlers retain this owner until they have quiesced. Neither
        // closes independently, so no delayed handler can touch a recycled fd.
        reader.setCancelHandler { [self] in sourceQuiesced() }
        writer.setCancelHandler { [self] in sourceQuiesced() }
        // Read starts only after the complete request; write is cancelled then,
        // avoiding writable hot loops and an early-response read hot loop.
        writer.resume()
    }
    private func manualWithinDeadline() -> Bool {
        guard !finished, let deadline else { return false }
        guard DispatchTime.now() < deadline else { finish(.refused(.transportFailed)); return false }
        return true
    }
    private func writeManual() {
        guard manualWithinDeadline(), let fd = descriptor, writeSource != nil else { return }
        if connecting {
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0,
                  size == MemoryLayout<Int32>.size, error == 0 else {
                finish(.refused(.transportFailed)); return
            }
            connecting = false
        }
        // Every syscall attempt, including EINTR, consumes this event's budget.
        for _ in 0..<4 {
            guard manualWithinDeadline() else { return }
            let count = requestBytes.withUnsafeBytes { buffer in
                Darwin.send(fd, buffer.baseAddress!.advanced(by: written), buffer.count - written, 0)
            }
            if count > 0 { written += count }
            else if count < 0 {
                let error = errno
                if error == EAGAIN || error == EWOULDBLOCK { return }
                if error == EINTR { continue }
                finish(.refused(.transportFailed)); return
            } else { finish(.refused(.transportFailed)); return }
            if written == requestBytes.count {
                requestBytes.removeAll(); written = 0
                let writer = writeSource; writeSource = nil; writer?.cancel()
                readSourceResumed = true; readSource?.resume()
                return
            }
        }
    }
    private func readManual() {
        guard manualWithinDeadline(), let fd = descriptor, readSourceResumed else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        // At most 16 KiB and four syscall attempts per readiness callback. Parser
        // work is linear in those bytes, yielding to cancellation and the timer.
        for _ in 0..<4 {
            guard manualWithinDeadline() else { return }
            let count = buffer.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress!, $0.count, 0) }
            if count > 0 {
                if let outcome = manualResponse.consume(buffer.prefix(count)) {
                    guard manualWithinDeadline() else { return }
                    finish(outcome); return
                }
            } else if count == 0 {
                guard manualWithinDeadline() else { return }
                finish(manualResponse.endOfStream()); return
            }
            else {
                let error = errno
                if error == EAGAIN || error == EWOULDBLOCK { return }
                if error == EINTR { continue }
                finish(.refused(.transportFailed)); return
            }
        }
    }
    private func sourceQuiesced() {
        sourceOwners -= 1
        closeManualIfQuiescent()
    }
    private func closeManualIfQuiescent() {
        guard finished, sourceOwners == 0, let fd = descriptor else { return }
        descriptor = nil
        // Darwin close is attempted once, including EINTR. Retrying could close
        // an unrelated descriptor that has reused this number.
        _ = Darwin.close(fd)
    }
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            completion = nil
            finish(.refused(.cancelled))
        }
    }
    private func finish(_ outcome: NativeConnectionProbeOutcome) {
        guard !finished else { return }
        finished = true
        let callback = completion; completion = nil
        timer?.cancel(); timer = nil
        let reader = readSource; readSource = nil
        if let reader {
            if !readSourceResumed { readSourceResumed = true; reader.resume() }
            reader.cancel()
        }
        let writer = writeSource; writeSource = nil; writer?.cancel()
        requestBytes.removeAll()
        closeManualIfQuiescent()
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        callback?(outcome)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished else { completionHandler(.cancel); return }
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.refused(.transportFailed)); return
        }
        let code = response.statusCode
        if code == 401 || code == 407 {
            completionHandler(.cancel); finish(.refused(.authenticationRequired)); return
        }
        if (300...399).contains(code) {
            completionHandler(.cancel); finish(.refused(.unsupportedEndpoint)); return
        }
        guard response.expectedContentLength <= 65536 else {
            completionHandler(.cancel); finish(.refused(.responseTooLarge)); return
        }
        status = code
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard data.count <= 65536 - bytes else { finish(.refused(.responseTooLarge)); return }
        bytes += data.count
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        guard error == nil, let status else { finish(.refused(.transportFailed)); return }
        finish(.response(statusCode: status, bytes: bytes))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.refused(.unsupportedEndpoint))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
        finish(.refused(.authenticationRequired))
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.cancelAuthenticationChallenge, nil)
        finish(.refused(.authenticationRequired))
    }
}
