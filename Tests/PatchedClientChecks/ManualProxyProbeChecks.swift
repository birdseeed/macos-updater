import Foundation
import Network
@_spi(Testing) import PatchedNetworking

// PAT-2666 independent controlled-peer checks. Only literal 127.0.0.1 listeners
// are created. Neither a configuration dictionary nor a test transport proves routing.
// Queue confinement covers every peer field; snapshots synchronise with that queue.
private final class ManualProbePeer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "im.patched.check.manual-proxy-peer")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var held: [NWConnection] = []
    private var headers: [String] = []
    private var response: Data?
    private var readyPort: UInt16?
    private var failure: String?
    private var stopped = false
    struct Snapshot { let port: UInt16?; let headers: [String]; let connections: Int; let failure: String? }

    init(response: Data?) throws {
        self.response = response
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !self.stopped else { return }
            switch state {
            case .ready: self.readyPort = self.listener.port?.rawValue
            case .failed: self.failure = "Controlled loopback listener failed"
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, !self.stopped, self.connections.count < 8 else { connection.cancel(); return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, bytes: Data())
        }
        listener.start(queue: queue)
    }
    func snapshot() -> Snapshot {
        queue.sync { Snapshot(port: readyPort, headers: headers, connections: connections.count, failure: failure) }
    }
    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - bytes.count) { [weak self] data, _, done, error in
            guard let self, !self.stopped else { connection.cancel(); return }
            var bytes = bytes
            if let data { bytes.append(data) }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                self.headers.append(String(decoding: bytes[..<end.upperBound], as: UTF8.self))
                if let response = self.response { self.send(response, to: connection) }
                else { self.held.append(connection) }
            } else if done || error != nil || bytes.count >= 8192 { connection.cancel() }
            else { self.receive(connection, bytes: bytes) }
        }
    }
    private func send(_ response: Data, to connection: NWConnection) {
        connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
    func release(_ response: Data) {
        queue.async { [self] in
            guard !stopped else { return }
            self.response = response
            let pending = held; held = []
            for connection in pending { send(response, to: connection) }
        }
    }
    func stop() {
        queue.sync {
            guard !stopped else { return }
            stopped = true; listener.cancel()
            for connection in connections { connection.cancel() }
            connections = []; held = []
        }
    }
    deinit { listener.cancel(); for connection in connections { connection.cancel() } }
}

@MainActor private final class ManualProbeObservationRequest: NativeNetworkObservationRequest {
    func cancel() {}
}
@MainActor private final class ManualProbeObservation: NativeNetworkObservationProvider {
    var callback: (@MainActor (NativeNetworkObservation) -> Void)?
    var calls = 0
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        calls += 1; callback = completion; return ManualProbeObservationRequest()
    }
}
@MainActor private final class ManualProbeResult {
    var values: [NativeConnectionProbeOutcome] = []
    func receive(_ value: NativeConnectionProbeOutcome) { values.append(value) }
}
private func manualHTTP(_ body: Data = Data("proxy".utf8), status: String = "200 OK", extra: String = "") -> Data {
    var response = Data("HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\(extra)\r\n".utf8)
    response.append(body); return response
}
@MainActor private func manualWait(_ label: String, seconds: Double = 7, _ predicate: () -> Bool) async throws {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    while ProcessInfo.processInfo.systemUptime < end {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw CheckFailure(description: "Controlled local peer timed out: \(label)")
}
@MainActor private func manualPort(_ peer: ManualProbePeer) async throws -> UInt16 {
    try await manualWait("listener ready", seconds: 2) { peer.snapshot().port != nil || peer.snapshot().failure != nil }
    let snapshot = peer.snapshot()
    guard let port = snapshot.port, snapshot.failure == nil else {
        throw CheckFailure(description: snapshot.failure ?? "No controlled local listener port")
    }
    return port
}
@MainActor private func manualSettings(_ port: UInt16, mode: NetworkMode = .manualHTTP) throws -> NativeNetworkSettingsController {
    let settings = NativeNetworkSettingsController(provider: ManualProbeObservation())
    settings.edit(mode: mode, host: "127.0.0.1", port: String(port))
    try expect(settings.applyChoice(), "Controlled local choice did not apply")
    return settings
}
@MainActor private func manualDone(_ result: ManualProbeResult, _ expected: NativeConnectionProbeOutcome,
                                   probe: NativeNetworkConnectionProbe) async throws {
    try await manualWait("probe completion") { !result.values.isEmpty }
    try expect(result.values == [expected], "Expected \(expected), received \(result.values)")
    try expect(!probe.isRunning, "Completed probe retained pending authority")
}
@MainActor private func manualQuiet(_ origin: ManualProbePeer, proxy: ManualProbePeer? = nil,
                                    requests: Int = 1) async throws {
    try await Task.sleep(nanoseconds: 200_000_000)
    try expect(origin.snapshot().connections == 0 && origin.snapshot().headers.isEmpty,
               "Manual request bypassed proxy and connected to independent live origin")
    if let proxy {
        let snapshot = proxy.snapshot()
        try expect(snapshot.headers.count == requests && snapshot.connections == requests,
                   "Unexpected retry, redirect or connection: \(snapshot.connections) connections, \(snapshot.headers.count) requests")
        for header in snapshot.headers {
            let lower = header.lowercased()
            try expect(!lower.contains("authorization:") && !lower.contains("cookie:"), "Peer received credential or cookie header")
        }
    }
}
@MainActor private func manualPending(_ peer: ManualProbePeer, result: ManualProbeResult) async throws {
    try await manualWait("pending proxy request", seconds: 2) { !peer.snapshot().headers.isEmpty || !result.values.isEmpty }
    try expect(result.values.isEmpty && peer.snapshot().headers.count == 1, "Expected pending actual proxy request; received \(result.values)")
}

@MainActor func registerManualProxyProbeChecks() {
    check("PAT2666 manual probe control: direct real peer receives origin-form GET") {
        let origin = try ManualProbePeer(response: manualHTTP(Data("direct".utf8))); defer { origin.stop() }
        let port = try await manualPort(origin), settings = try manualSettings(port, mode: .direct)
        let probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
        probe.start(url: URL(string: "http://127.0.0.1:\(port)/probe")!, completion: result.receive)
        defer { probe.cancel() }
        try await manualDone(result, .response(statusCode: 200, bytes: 6), probe: probe)
        try expect(origin.snapshot().headers.count == 1 && origin.snapshot().headers[0].hasPrefix("GET /probe HTTP/1.1\r\n"), "Direct control did not reach real origin exactly once")
    }
    for size in [5, 65536] {
        check("PAT2666 manual probe routing: absolute-form GET and zero live-origin requests, body \(size)") {
            let origin = try ManualProbePeer(response: manualHTTP(Data("origin".utf8)))
            let proxy = try ManualProbePeer(response: manualHTTP(Data(repeating: 112, count: size)))
            defer { proxy.stop(); origin.stop() }
            let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
            let destination = "http://127.0.0.1:\(originPort)/probe"
            let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            probe.start(url: URL(string: destination)!, completion: result.receive); defer { probe.cancel() }
            try await manualDone(result, .response(statusCode: 200, bytes: size), probe: probe)
            try await manualQuiet(origin, proxy: proxy)
            try expect(proxy.snapshot().headers[0].hasPrefix("GET \(destination) HTTP/1.1\r\n"), "Proxy did not receive exact absolute-form destination")
        }
    }
    check("PAT2666 manual probe refusal: unreachable proxy never falls back to live origin") {
        let origin = try ManualProbePeer(response: manualHTTP()), proxy = try ManualProbePeer(response: nil)
        defer { origin.stop(); proxy.stop() }
        let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
        proxy.stop() // A locally allocated port, then a closed listener; no guessed external endpoint.
        let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
        probe.start(url: URL(string: "http://127.0.0.1:\(originPort)/probe")!, completion: result.receive); defer { probe.cancel() }
        try await manualDone(result, .refused(.transportFailed), probe: probe)
        try await manualQuiet(origin)
    }
    for scenario in ["407", "redirect", "declared overflow", "stream overflow", "deadline"] {
        check("PAT2666 manual probe refusal: \(scenario) with no direct fallback or second request") {
            let origin = try ManualProbePeer(response: manualHTTP()); defer { origin.stop() }
            let originPort = try await manualPort(origin)
            let response: Data?
            let expected: NativeConnectionProbeOutcome
            switch scenario {
            case "407":
                response = manualHTTP(Data(), status: "407 Proxy Authentication Required", extra: "Proxy-Authenticate: Basic realm=\"controlled-local-check\"\r\n")
                expected = .refused(.authenticationRequired)
            case "redirect":
                response = manualHTTP(Data(), status: "302 Found", extra: "Location: http://127.0.0.1:\(originPort)/probe\r\n")
                expected = .refused(.unsupportedEndpoint)
            case "declared overflow":
                response = Data("HTTP/1.1 200 OK\r\nContent-Length: 65537\r\nConnection: close\r\n\r\n".utf8)
                expected = .refused(.responseTooLarge)
            case "stream overflow":
                var wire = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n10001\r\n".utf8)
                wire.append(Data(repeating: 120, count: 65537)); wire.append(Data("\r\n0\r\n\r\n".utf8))
                response = wire; expected = .refused(.responseTooLarge)
            default: response = nil; expected = .refused(.transportFailed)
            }
            let proxy = try ManualProbePeer(response: response); defer { proxy.stop() }
            let proxyPort = try await manualPort(proxy), settings = try manualSettings(proxyPort)
            let probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            let started = ProcessInfo.processInfo.systemUptime
            probe.start(url: URL(string: "http://127.0.0.1:\(originPort)/probe")!, completion: result.receive); defer { probe.cancel() }
            try await manualDone(result, expected, probe: probe)
            if scenario == "deadline" {
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                try expect(elapsed >= 4 && elapsed < 6.5, "Five-second deadline outside bounded tolerance: \(elapsed)")
                proxy.release(manualHTTP())
            }
            try await manualQuiet(origin, proxy: proxy)
            try expect(result.values == [expected], "Late response delivered another completion")
        }
    }
    for mutation in ["cancel", "edit", "refresh"] {
        check("PAT2666 manual probe invalidation: \(mutation) settles once and ignores late proxy success") {
            let origin = try ManualProbePeer(response: manualHTTP()), proxy = try ManualProbePeer(response: nil)
            defer { proxy.stop(); origin.stop() }
            let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
            let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            probe.start(url: URL(string: "http://127.0.0.1:\(originPort)/probe")!, completion: result.receive); defer { probe.cancel() }
            try await manualPending(proxy, result: result)
            if mutation == "cancel" { probe.cancel(); probe.cancel() }
            if mutation == "edit" { settings.edit(mode: .direct) }
            if mutation == "refresh" { settings.refresh(); settings.cancelRefresh() }
            let expected: NativeConnectionProbeOutcome = .refused(mutation == "cancel" ? .cancelled : .changedSettings)
            try await manualDone(result, expected, probe: probe)
            proxy.release(manualHTTP())
            try await manualQuiet(origin, proxy: proxy)
            try expect(result.values == [expected], "Invalidated operation published late success or settled twice")
        }
    }
    check("PAT2666 manual probe concurrency: busy refuses without another proxy connection") {
        let origin = try ManualProbePeer(response: manualHTTP()), proxy = try ManualProbePeer(response: nil)
        defer { proxy.stop(); origin.stop() }
        let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
        let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings)
        let first = ManualProbeResult(), second = ManualProbeResult(), url = URL(string: "http://127.0.0.1:\(originPort)/probe")!
        probe.start(url: url, completion: first.receive); defer { probe.cancel() }
        try await manualPending(proxy, result: first)
        probe.start(url: url, completion: second.receive)
        try expect(second.values == [.refused(.busy)] && probe.isRunning, "Concurrent action did not refuse busy while retaining first")
        proxy.release(manualHTTP())
        try await manualDone(first, .response(statusCode: 200, bytes: 5), probe: probe)
        try await manualQuiet(origin, proxy: proxy)
        try expect(second.values == [.refused(.busy)], "Busy action received a later callback")
    }
    check("PAT2666 manual probe reentrancy: completion releases authority before fresh explicit action") {
        let origin = try ManualProbePeer(response: manualHTTP()), proxy = try ManualProbePeer(response: nil)
        defer { proxy.stop(); origin.stop() }
        let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
        let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings)
        let first = ManualProbeResult(), second = ManualProbeResult(), url = URL(string: "http://127.0.0.1:\(originPort)/probe")!
        probe.start(url: url) { value in first.receive(value); probe.start(url: url, completion: second.receive) }
        defer { probe.cancel() }
        try await manualPending(proxy, result: first)
        probe.cancel()
        try expect(first.values == [.refused(.cancelled)] && probe.isRunning, "Completion retained old authority or blocked explicit reentrant action")
        try await manualWait("second explicit proxy request", seconds: 2) { proxy.snapshot().headers.count == 2 || !second.values.isEmpty }
        try expect(second.values.isEmpty && proxy.snapshot().headers.count == 2, "Reentrant action never reached proxy")
        proxy.release(manualHTTP())
        try await manualDone(second, .response(statusCode: 200, bytes: 5), probe: probe)
        try await manualQuiet(origin, proxy: proxy, requests: 2)
        try expect(first.values == [.refused(.cancelled)], "Old callback acquired fresh operation authority")
    }
    check("PAT2666 manual probe control: construction reads edit and Apply remain inert; default refuses") {
        let peer = try ManualProbePeer(response: manualHTTP()); defer { peer.stop() }
        let port = try await manualPort(peer), provider = ManualProbeObservation()
        let settings = NativeNetworkSettingsController(provider: provider), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
        defer { probe.cancel() }
        let url = URL(string: "http://127.0.0.1:\(port)/probe")!
        probe.start(url: url, completion: result.receive)
        try expect(result.values == [.refused(.notApplied)], "Default settings acquired transport authority")
        settings.edit(mode: .manualHTTP, host: "127.0.0.1", port: String(port)); _ = settings.text
        try expect(settings.applyChoice(), "Valid manual choice failed Apply"); _ = settings.text
        try await Task.sleep(nanoseconds: 200_000_000)
        try expect(peer.snapshot().connections == 0 && provider.calls == 0 && !probe.isRunning, "Inert settings action performed transport or observation")
    }
    check("PAT2666 manual probe refusal: aliases nonloopback and IPv6 proxy hosts refuse before connection") {
        let peer = try ManualProbePeer(response: manualHTTP()); defer { peer.stop() }
        let port = try await manualPort(peer)
        for host in ["localhost", "proxy.invalid", "127.0.0.2", "192.0.2.1", "[::1]", "LOCALHOST", "127.0.0.1."] {
            let settings = NativeNetworkSettingsController(provider: ManualProbeObservation())
            settings.edit(mode: .manualHTTP, host: host, port: String(port))
            let applied = settings.applyChoice(), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            probe.start(url: URL(string: "http://127.0.0.1:\(port)/probe")!, completion: result.receive); defer { probe.cancel() }
            try expect(result.values == [.refused(applied ? .unsupportedProxy : .notApplied)], "Unsupported proxy spelling \(host) did not refuse synchronously")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        try expect(peer.snapshot().connections == 0, "Unsupported proxy reached controlled origin")
    }
    check("PAT2666 manual probe refusal: invalid manual ports never acquire an applied choice") {
        let peer = try ManualProbePeer(response: manualHTTP()); defer { peer.stop() }
        let port = try await manualPort(peer)
        for badPort in ["", "0", "65536", "-1", "80 ", "1x", "000001"] {
            let settings = NativeNetworkSettingsController(provider: ManualProbeObservation())
            settings.edit(mode: .manualHTTP, host: "127.0.0.1", port: badPort)
            try expect(!settings.applyChoice(), "Invalid port accepted: \(badPort)")
            let probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            defer { probe.cancel() }
            probe.start(url: URL(string: "http://127.0.0.1:\(port)/probe")!, completion: result.receive)
            try expect(result.values == [.refused(.notApplied)], "Invalid port acquired transport authority")
        }
        try expect(peer.snapshot().connections == 0, "Invalid choice reached peer")
    }
    check("PAT2666 manual probe refusal: unsupported endpoint forms stay inert") {
        let peer = try ManualProbePeer(response: manualHTTP()); defer { peer.stop() }
        let port = try await manualPort(peer), settings = try manualSettings(port), probe = NativeNetworkConnectionProbe(settings: settings)
        defer { probe.cancel() }
        for endpoint in ["http://localhost:\(port)/probe", "https://127.0.0.1:\(port)/probe", "http://127.0.0.1:\(port)/other",
                         "http://127.0.0.1:\(port)/probe?", "http://127.0.0.1:\(port)/probe#", "http://user@127.0.0.1:\(port)/probe",
                         "http://127.0.0.1:\(port)/%70robe", "http://127.0.0.1/probe"] {
            let result = ManualProbeResult()
            probe.start(url: URL(string: endpoint)!, completion: result.receive)
            try expect(result.values == [.refused(.unsupportedEndpoint)] && !probe.isRunning, "Unsupported endpoint acquired transport authority")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        try expect(peer.snapshot().connections == 0, "Unsupported endpoint connected")
    }
    check("PAT2666 manual probe refusal: retained offline observation blocks actual manual transport") {
        let peer = try ManualProbePeer(response: manualHTTP()); defer { peer.stop() }
        let port = try await manualPort(peer), provider = ManualProbeObservation()
        let settings = NativeNetworkSettingsController(provider: provider)
        settings.refresh(); provider.callback?(NativeNetworkObservation(path: .offline, proxy: .noConfiguredProxy))
        settings.edit(mode: .manualHTTP, host: "127.0.0.1", port: String(port))
        try expect(settings.applyChoice(), "Offline manual draft did not apply")
        let probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
        defer { probe.cancel() }
        probe.start(url: URL(string: "http://127.0.0.1:\(port)/probe")!, completion: result.receive)
        try expect(result.values == [.refused(.offline)] && !probe.isRunning, "Offline observation did not refuse synchronously")
        try await Task.sleep(nanoseconds: 200_000_000)
        try expect(peer.snapshot().connections == 0, "Offline probe connected")
    }
}


// PAT-2666 independent finite framing contract, prepared before manual socket implementation.
// Supported response framing: HTTP/1.1 final response, CRLF lines, token field names,
// one decimal Content-Length, sole Transfer-Encoding: chunked without extensions/trailers,
// or EOF-delimited body. A 204 has no body. Header section is at most 8192 wire bytes;
// decoded body is at most 65536 bytes. Ambiguous/unsupported/malformed framing refuses.
@MainActor func registerManualProxyFramingChecks() {
    let failed: NativeConnectionProbeOutcome = .refused(.transportFailed)
    let tooLarge: NativeConnectionProbeOutcome = .refused(.responseTooLarge)
    // Each tuple registers exactly one check, including malformed and policy refusals.
    let vectors: [(String, String, NativeConnectionProbeOutcome)] = [
        ("empty Content-Length", "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", .response(statusCode: 200, bytes: 0)),
        ("204 without body framing", "HTTP/1.1 204 No Content\r\n\r\n", .response(statusCode: 204, bytes: 0)),
        ("multiple chunks count decoded bytes", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n5\r\ncdefg\r\n0\r\n\r\n", .response(statusCode: 200, bytes: 7)),
        ("zero chunk", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", .response(statusCode: 200, bytes: 0)),
        ("EOF delimited body", "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\neof-proxy", .response(statusCode: 200, bytes: 9)),
        ("status missing HTTP version", "200 OK\r\nContent-Length: 0\r\n\r\n", failed),
        ("status not three decimal digits", "HTTP/1.1 20X OK\r\nContent-Length: 0\r\n\r\n", failed),
        ("duplicate equal Content-Length", "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n", failed),
        ("duplicate conflicting Content-Length", "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\nx", failed),
        ("Transfer-Encoding Content-Length conflict", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n0\r\n\r\n", failed),
        ("negative Content-Length", "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n", failed),
        ("nondecimal Content-Length", "HTTP/1.1 200 OK\r\nContent-Length: 1x\r\n\r\nx", failed),
        ("integer overflow Content-Length", "HTTP/1.1 200 OK\r\nContent-Length: 184467440737095516160\r\n\r\n", failed),
        ("unsupported transfer coding", "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\nx", failed),
        ("unsupported coding before chunked", "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n", failed),
        ("repeated chunked coding", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked, chunked\r\n\r\n0\r\n\r\n", failed),
        ("nonhex chunk length", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nG\r\nx\r\n0\r\n\r\n", failed),
        ("bad chunk data CRLF", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx!\n0\r\n\r\n", failed),
        ("short chunk EOF", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nx", failed),
        ("missing terminal chunk", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx\r\n", failed),
        ("unsupported chunk extension", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1;ext=yes\r\nx\r\n0\r\n\r\n", failed),
        ("unsupported trailer", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx\r\n0\r\nX-Trailer: value\r\n\r\n", failed),
        ("short Content-Length EOF", "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nx", failed),
        ("header beyond 8 KiB", "HTTP/1.1 200 OK\r\nX-Padding: " + String(repeating: "p", count: 8192) + "\r\nContent-Length: 0\r\n\r\n", failed),
        ("obsolete folded header", "HTTP/1.1 200 OK\r\nX-Header: value\r\n continued\r\nContent-Length: 0\r\n\r\n", failed),
        ("invalid header name", "HTTP/1.1 200 OK\r\nBad(Name: value\r\nContent-Length: 0\r\n\r\n", failed),
        ("whitespace before header colon", "HTTP/1.1 200 OK\r\nContent-Length : 0\r\n\r\n", failed),
        ("unsupported informational response", "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", failed),
        ("unsupported protocol upgrade", "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: example\r\n\r\n", failed),
        ("origin authentication refusal", "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"local\"\r\nContent-Length: 0\r\n\r\n", .refused(.authenticationRequired)),
        ("proxy authentication refusal", "HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"local\"\r\nContent-Length: 0\r\n\r\n", .refused(.authenticationRequired)),
        ("redirect refusal", "HTTP/1.1 302 Found\r\nLocation: /probe\r\nContent-Length: 0\r\n\r\n", .refused(.unsupportedEndpoint)),
        ("EOF decoded body overflow", "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + String(repeating: "x", count: 65537), tooLarge),
        ("aggregate decoded chunk overflow", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n8000\r\n" + String(repeating: "x", count: 32768) + "\r\n8001\r\n" + String(repeating: "y", count: 32769) + "\r\n0\r\n\r\n", tooLarge)
    ]
    for (name, wire, expected) in vectors {
        check("PAT2666 manual proxy HTTP framing: \(name)") {
            // A reachable origin returns a distinct nonmatching response if routing is bypassed.
            let origin = try ManualProbePeer(response: manualHTTP(Data("independent-origin".utf8), status: "418 Origin Must Remain Unused"))
            let proxy = try ManualProbePeer(response: Data(wire.utf8))
            defer { proxy.stop(); origin.stop() }
            let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
            let destination = "http://127.0.0.1:\(originPort)/probe"
            let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            probe.start(url: URL(string: destination)!, completion: result.receive)
            defer { probe.cancel() }
            try await manualDone(result, expected, probe: probe)
            try await manualQuiet(origin, proxy: proxy)
            let requests = proxy.snapshot().headers
            try expect(requests.count == 1 && requests[0].hasPrefix("GET \(destination) HTTP/1.1\r\n"),
                       "Framing vector did not traverse selected proxy with exact absolute-form GET")
            try expect(result.values == [expected], "Framing vector completed more than once")
        }
    }
}


// PAT-2666 additive independent framing-resource contract. No Content-Encoding is
// supported. The 8192-byte aggregate metadata bound includes response headers,
// chunk-size lines, chunk-data CRLF and terminal CRLF, excluding decoded body bytes.
@MainActor func registerManualProxyFramingBoundChecks() {
    let tinyChunks = String(repeating: "1\r\nx\r\n", count: 2000)
    let vectors: [(String, String)] = [
        ("unsupported gzip content coding", "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 1\r\n\r\nx"),
        ("unsupported br content coding", "HTTP/1.1 200 OK\r\nContent-Encoding: br\r\nContent-Length: 1\r\n\r\nx"),
        // 2000 decoded bytes, 10000 chunk-framing bytes plus headers/terminator:
        // header-only and decoded-body-only limits cannot detect this excess.
        ("aggregate framing metadata beyond 8 KiB", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + tinyChunks + "0\r\n\r\n")
    ]
    for (name, wire) in vectors {
        check("PAT2666 manual proxy framing bound: \(name)") {
            let origin = try ManualProbePeer(response: manualHTTP(Data("independent-origin".utf8), status: "418 Origin Must Remain Unused"))
            let proxy = try ManualProbePeer(response: Data(wire.utf8))
            defer { proxy.stop(); origin.stop() }
            let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
            let destination = "http://127.0.0.1:\(originPort)/probe"
            let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            probe.start(url: URL(string: destination)!, completion: result.receive)
            defer { probe.cancel() }
            let expected: NativeConnectionProbeOutcome = .refused(.transportFailed)
            try await manualDone(result, expected, probe: probe)
            try await manualQuiet(origin, proxy: proxy)
            let requests = proxy.snapshot().headers
            try expect(requests.count == 1 && requests[0].hasPrefix("GET \(destination) HTTP/1.1\r\n"),
                       "Framing-bound vector did not traverse selected proxy with exact absolute-form GET")
            try expect(result.values == [expected], "Framing-bound vector completed more than once")
        }
    }
}


// Separate one-connection peer for deterministic fragmented writes. All mutable
// state and scheduled work are confined to this queue; stop cancels every owned item.
private final class ManualProbeFragmentedPeer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "im.patched.check.fragmented-proxy-peer")
    private let listener: NWListener
    private let fragments: [Data]
    private var connection: NWConnection?
    private var pending: DispatchWorkItem?
    private var headers: [String] = []
    private var accepted = 0
    private var attempts = 0
    private var readyPort: UInt16?
    private var failure: String?
    private var stopped = false
    struct Snapshot { let port: UInt16?; let headers: [String]; let connections: Int; let failure: String? }

    init() throws {
        fragments = ["HTTP/1.1 200 OK\r", "\nTransfer-Encoding: chunked\r\n", "\r", "\n",
                     "2", "\r", "\n", "a", "b", "\r", "\n", "5\r", "\n", "cd", "efg",
                     "\r\n", "0", "\r", "\n", "\r", "\n"].map { Data($0.utf8) }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, !self.stopped else { return }
            switch state {
            case .ready: self.readyPort = self.listener.port?.rawValue
            case .failed: self.failure = "Fragmented controlled listener failed"
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, !self.stopped else { connection.cancel(); return }
            self.attempts += 1
            guard self.accepted == 0 else { connection.cancel(); return }
            self.accepted = 1; self.connection = connection
            connection.start(queue: self.queue)
            self.receive(connection, bytes: Data())
        }
        listener.start(queue: queue)
    }
    func snapshot() -> Snapshot {
        queue.sync { Snapshot(port: readyPort, headers: headers, connections: attempts, failure: failure) }
    }
    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - bytes.count) { [weak self] data, _, done, error in
            guard let self, !self.stopped else { connection.cancel(); return }
            var bytes = bytes
            if let data { bytes.append(data) }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: bytes[..<end.upperBound], as: UTF8.self)
                self.headers.append(header)
                guard let requestLine = header.components(separatedBy: "\r\n").first,
                      requestLine.hasPrefix("GET http://"), requestLine.hasSuffix(" HTTP/1.1") else {
                    self.failure = "Fragmented peer requires complete absolute-form GET"; connection.cancel(); return
                }
                self.scheduleFragment(0, on: connection)
            } else if done || error != nil || bytes.count >= 8192 { connection.cancel() }
            else { self.receive(connection, bytes: bytes) }
        }
    }
    private func scheduleFragment(_ index: Int, on connection: NWConnection) {
        guard !stopped, index < fragments.count else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.pending = nil
            let last = index == self.fragments.count - 1
            connection.send(content: self.fragments[index], contentContext: last ? .finalMessage : .defaultMessage,
                            isComplete: true, completion: .contentProcessed { [weak self] error in
                guard let self, !self.stopped else { connection.cancel(); return }
                if error != nil { self.failure = "Fragmented controlled response send failed"; connection.cancel() }
                else if last { connection.cancel() }
                else { self.scheduleFragment(index + 1, on: connection) }
            })
        }
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(5), execute: work)
    }
    func stop() {
        queue.sync {
            guard !stopped else { return }
            stopped = true; pending?.cancel(); pending = nil
            listener.cancel(); connection?.cancel(); connection = nil
        }
    }
    deinit { pending?.cancel(); listener.cancel(); connection?.cancel() }
}

@MainActor func registerManualProxyFramingFinalChecks() {
    for framing in ["chunked", "EOF"] {
        check("PAT2666 manual proxy exact decoded 64 KiB success: \(framing)") {
            let body = Data(repeating: 120, count: 65536)
            var wire = Data((framing == "chunked"
                ? "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10000\r\n"
                : "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n").utf8)
            wire.append(body)
            if framing == "chunked" { wire.append(Data("\r\n0\r\n\r\n".utf8)) }
            let origin = try ManualProbePeer(response: manualHTTP(Data("independent-origin".utf8), status: "418 Origin Must Remain Unused"))
            let proxy = try ManualProbePeer(response: wire)
            defer { proxy.stop(); origin.stop() }
            let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
            let destination = "http://127.0.0.1:\(originPort)/probe"
            let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
            probe.start(url: URL(string: destination)!, completion: result.receive); defer { probe.cancel() }
            try await manualDone(result, .response(statusCode: 200, bytes: 65536), probe: probe)
            try await manualQuiet(origin, proxy: proxy)
            let requests = proxy.snapshot().headers
            try expect(requests.count == 1 && requests[0].hasPrefix("GET \(destination) HTTP/1.1\r\n"),
                       "Exact-limit response did not traverse selected proxy with absolute-form GET")
        }
    }
    check("PAT2666 manual proxy IPv6 destination retains absolute-form GET and bracketed Host") {
        let origin = try ManualProbePeer(response: manualHTTP(Data("independent-origin".utf8), status: "418 Origin Must Remain Unused"))
        let proxy = try ManualProbePeer(response: manualHTTP(Data("ipv6-proxy".utf8)))
        defer { proxy.stop(); origin.stop() }
        let originPort = try await manualPort(origin), proxyPort = try await manualPort(proxy)
        let destination = "http://[::1]:\(originPort)/probe"
        let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
        probe.start(url: URL(string: destination)!, completion: result.receive); defer { probe.cancel() }
        try await manualDone(result, .response(statusCode: 200, bytes: 10), probe: probe)
        try await manualQuiet(origin, proxy: proxy)
        let requests = proxy.snapshot().headers
        try expect(requests.count == 1 && requests[0].hasPrefix("GET \(destination) HTTP/1.1\r\n"),
                   "IPv6 destination did not reach selected IPv4 proxy as exact absolute-form GET")
        try expect(requests[0].components(separatedBy: "\r\n").contains("Host: [::1]:\(originPort)"),
                   "IPv6 Host did not preserve brackets and explicit port")
    }
    check("PAT2666 manual proxy fragmented header chunk line payload and terminator boundaries") {
        let origin = try ManualProbePeer(response: manualHTTP(Data("independent-origin".utf8), status: "418 Origin Must Remain Unused"))
        let proxy = try ManualProbeFragmentedPeer()
        defer { proxy.stop(); origin.stop() }
        let originPort = try await manualPort(origin)
        try await manualWait("fragmented listener ready", seconds: 2) { proxy.snapshot().port != nil || proxy.snapshot().failure != nil }
        let ready = proxy.snapshot()
        guard let proxyPort = ready.port, ready.failure == nil else {
            throw CheckFailure(description: ready.failure ?? "Fragmented listener has no port")
        }
        let destination = "http://127.0.0.1:\(originPort)/probe"
        let settings = try manualSettings(proxyPort), probe = NativeNetworkConnectionProbe(settings: settings), result = ManualProbeResult()
        probe.start(url: URL(string: destination)!, completion: result.receive); defer { probe.cancel() }
        try await manualDone(result, .response(statusCode: 200, bytes: 7), probe: probe)
        try await manualQuiet(origin)
        let snapshot = proxy.snapshot()
        try expect(snapshot.failure == nil && snapshot.connections == 1 && snapshot.headers.count == 1,
                   "Fragmented response failed or required multiple proxy requests")
        try expect(snapshot.headers[0].hasPrefix("GET \(destination) HTTP/1.1\r\n"),
                   "Fragmented response did not traverse selected proxy with exact absolute-form GET")
        let lower = snapshot.headers[0].lowercased()
        try expect(!lower.contains("authorization:") && !lower.contains("cookie:"), "Fragmented peer received credentials or cookies")
        try expect(result.values == [.response(statusCode: 200, bytes: 7)], "Fragmented response completed twice")
    }
}
