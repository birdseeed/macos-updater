import Foundation
import AppKit
import Darwin
import CryptoKit
import Combine
import Network
import SwiftUI
import PatchedShell
import PatchedScheduling
@_spi(Testing) import PatchedClient
@_spi(Testing) import PatchedNetworking
@_spi(Testing) import PatchedUpdatePreferences

// Independent consumer checks. The accepted wire fixture is file-private in its
// frozen source, so this bounded check-only peer uses the same NWListener API.
// It is never an injected transport: the real consumer must reach its socket.
private final class CompositionCleanupStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func recordFailure() { lock.lock(); value += 1; lock.unlock() }
    var failures: Int { lock.lock(); defer { lock.unlock() }; return value }
}
private let compositionCleanup = CompositionCleanupStatus()
private final class CompositionPeer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "im.patched.check.composition-peer")
    private let listener: NWListener
    private let quiescence = DispatchGroup()
    private var cancelledConnections: Set<ObjectIdentifier> = []
    private var listenerCancelled = false
    private var sockets: [NWConnection] = []
    private var held: [NWConnection] = []
    private var response: Data?
    private var port: UInt16?
    private var failure: String?
    private var headers: [String] = []
    private var accepted = 0
    private var receiveErrors = 0, sendErrors = 0, connectionFailures = 0
    private var stopped = false
    struct Snapshot { let port: UInt16?; let failure: String?; let connections: Int; let headers: [String]; let stopped: Bool; let cancelled: Int; let listenerCancelled: Bool; let receiveErrors: Int; let sendErrors: Int; let connectionFailures: Int }
    init(response: Data?) throws {
        self.response = response
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        quiescence.enter()
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: if !self.stopped { self.port = self.listener.port?.rawValue }
            case .failed: self.failure = "Controlled composition listener failed"
            case .cancelled:
                if !self.listenerCancelled { self.listenerCancelled = true; self.quiescence.leave() }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, !self.stopped, self.accepted < 8 else { connection.cancel(); return }
            self.accepted += 1; self.sockets.append(connection)
            self.quiescence.enter()
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection else { return }
                switch state {
                case .cancelled:
                    if self.cancelledConnections.insert(ObjectIdentifier(connection)).inserted { self.quiescence.leave() }
                case .failed: self.connectionFailures += 1; connection.cancel()
                default: break
                }
            }
            connection.start(queue: self.queue)
            self.receive(connection, bytes: Data())
        }
        listener.start(queue: queue)
    }
    func snapshot() -> Snapshot {
        queue.sync { Snapshot(port: port, failure: failure, connections: accepted, headers: headers, stopped: stopped, cancelled: cancelledConnections.count, listenerCancelled: listenerCancelled, receiveErrors: receiveErrors, sendErrors: sendErrors, connectionFailures: connectionFailures) }
    }
    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - bytes.count) { [weak self] data, _, done, error in
            guard let self, !self.stopped else { connection.cancel(); return }
            if error != nil { self.receiveErrors += 1 }
            var bytes = bytes
            if let data { bytes.append(data) }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                self.headers.append(String(decoding: bytes[..<end.upperBound], as: UTF8.self))
                if let response = self.response { self.send(response, connection) }
                else { self.held.append(connection) }
            } else if done || error != nil || bytes.count >= 8192 { connection.cancel() }
            else { self.receive(connection, bytes: bytes) }
        }
    }
    private func send(_ data: Data, _ connection: NWConnection) {
        connection.send(content: data, contentContext: .finalMessage, isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if error != nil { self?.sendErrors += 1 }
                connection.cancel()
            })
    }
    func release(_ data: Data) {
        queue.async { [self] in
            guard !stopped else { return }
            response = data; let pending = held; held = []
            for socket in pending { send(data, socket) }
        }
    }
    @discardableResult func stop() -> Bool {
        let first = queue.sync { () -> Bool in
            guard !stopped else { return false }
            stopped = true; listener.cancel()
            for socket in sockets { socket.cancel() }
            held = []
            return true
        }
        // Network.framework owns descriptor options/closure. Wait for the actual
        // cancellation callbacks on its serial queue, never a guessed FD close.
        let joined = quiescence.wait(timeout: .now() + .seconds(2)) == .success
        if first && !joined { compositionCleanup.recordFailure() }
        compositionEvidence("peer shutdown after bounded join", [self])
        return joined
    }
    deinit { listener.cancel(); for socket in sockets { socket.cancel() } }
}
@MainActor private final class CompositionRequest: NativeNetworkObservationRequest {
    var cancellations = 0
    func cancel() { cancellations += 1 }
}
@MainActor private final class CompositionObservation: NativeNetworkObservationProvider {
    var calls = 0
    var callbacks: [@MainActor (NativeNetworkObservation) -> Void] = []
    var requests: [CompositionRequest] = []
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        calls += 1; callbacks.append(completion)
        let request = CompositionRequest(); requests.append(request); return request
    }
}
@MainActor private final class CompositionStore: PreferenceStore {
    var bytes: Data?
    var reads = 0, writes = 0
    func read(maximumBytes: Int) -> PreferenceRead {
        reads += 1
        guard let bytes else { return .missing }
        return bytes.count <= maximumBytes ? .bytes(bytes) : .unavailable
    }
    func compareAndSwap(expected: Data?, proposed: Data, maximumBytes: Int) -> PreferenceCommit {
        writes += 1
        guard proposed.count <= maximumBytes else { return .notCommitted }
        guard expected == bytes else { return .conflict }
        bytes = proposed; return .committed
    }
}
private func compositionHTTP(_ body: String = "proxy-result", status: String = "200 OK", extra: String = "") -> Data {
    Data(("HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\(extra)\r\n" + body).utf8)
}
@MainActor private func compositionWait(_ label: String, seconds: Double = 7, _ predicate: () -> Bool) async throws {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    while ProcessInfo.processInfo.systemUptime < end {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw CheckFailure(description: "SETUP/EXECUTION TIMEOUT (not meaningful RED): \(label)")
}
private func compositionEvidence(_ label: String, _ peers: [CompositionPeer]) {
    let records: [[String: Any]] = peers.enumerated().map { index, peer in
        let value = peer.snapshot()
        return ["peer": index, "port": value.port.map { Int($0) as Any } ?? NSNull(),
                "failure": value.failure.map { $0 as Any } ?? NSNull(), "connections": value.connections, "received": value.headers,
                "stopped": value.stopped, "cancelledConnections": value.cancelled, "listenerCancelled": value.listenerCancelled,
                "receiveErrors": value.receiveErrors, "sendErrors": value.sendErrors, "connectionFailures": value.connectionFailures]
    }
    if let data = try? JSONSerialization.data(withJSONObject: ["label": label, "peers": records], options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print("COMPOSITION-PEER-EVIDENCE " + text) }
}
@MainActor private func compositionPort(_ peer: CompositionPeer) async throws -> UInt16 {
    try await compositionWait("loopback listener readiness", seconds: 2) { peer.snapshot().port != nil || peer.snapshot().failure != nil }
    let snapshot = peer.snapshot()
    compositionEvidence("listener setup before assertions", [peer])
    guard let port = snapshot.port, snapshot.failure == nil else {
        throw CheckFailure(description: "SETUP FAILURE (not meaningful RED): controlled listener unavailable")
    }
    print("SETUP PASS composition controlled loopback listener ready")
    return port
}
@MainActor private func compositionSettled(_ owner: NativeNetworkProbeController) async throws {
    try await compositionWait("consumer finite settlement") { !owner.isRunning }
    try await Task.sleep(nanoseconds: 150_000_000)
}
@MainActor private func compositionPending(_ peer: CompositionPeer, _ owner: NativeNetworkProbeController, requests: Int = 1) async throws {
    try await compositionWait("held real consumer request", seconds: 2) { peer.snapshot().headers.count >= requests || !owner.isRunning }
    compositionEvidence("held request before assertions", [peer])
    try expect(peer.snapshot().headers.count == requests && owner.isRunning,
               "BEHAVIOURAL RED: actual consumer did not establish a held request; state \(owner.state)")
}
@MainActor private func compositionPixels<V: View>(_ view: V) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: 800, height: 1100, alignment: .topLeading)
        .background(Color.white).environment(\.colorScheme, .light))
    renderer.scale = 1
    guard let image = renderer.cgImage, let data = image.dataProvider?.data as Data? else {
        throw CheckFailure(description: "SETUP FAILURE: composition offscreen image missing")
    }
    try expect(image.width == 800 && image.height == 1100 && !data.isEmpty, "SETUP FAILURE: composition image bounds")
    return data
}
// V01 only: one actual root stays mounted across idle, Test and Settings.
// The optional destination is supplied by the admitting parent, never inferred.
@MainActor private func compositionV01NativePaint(_ session: NativeClientSession,
    body: (@MainActor (String) throws -> Data) async throws -> Void) async throws {
    let app = NSApplication.shared
    if app.activationPolicy() != .prohibited { _ = app.setActivationPolicy(.prohibited) }
    try expect(app.activationPolicy() == .prohibited && !app.isActive, "V01 capture must remain prohibited/inactive")
    let host = NSHostingView(rootView: NativeClientRootView(session: session)
        .frame(width: 800, height: 1100, alignment: .topLeading)
        .background(Color.white).environment(\.colorScheme, .light))
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 1100)
    host.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }

    var evidenceDirectory: Int32 = -1
    defer { if evidenceDirectory >= 0 { _ = Darwin.close(evidenceDirectory) } }
    if let path = ProcessInfo.processInfo.environment["PAT2666_V01_EVIDENCE_DIRECTORY"] {
        try expect(path.hasPrefix("/") && path.utf8.count <= 4096 && !path.hasSuffix("/"), "V01 evidence requires bounded absolute path")
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        try expect(!components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, "V01 evidence path components invalid")
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try expect(parent >= 0, "V01 evidence root unavailable")
        defer { _ = Darwin.close(parent) }
        for component in components.dropLast() {
            let next = Darwin.openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            try expect(next >= 0, "V01 evidence ancestor unavailable or symlink")
            _ = Darwin.close(parent); parent = next
        }
        let name = components.last!
        try expect(Darwin.mkdirat(parent, name, 0o700) == 0, "V01 evidence directory must be new/exclusive")
        evidenceDirectory = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        try expect(evidenceDirectory >= 0, "V01 evidence directory unavailable")
        var info = stat(), named = stat()
        try expect(Darwin.fstat(evidenceDirectory, &info) == 0 &&
            Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0 &&
            info.st_dev == named.st_dev && info.st_ino == named.st_ino &&
            info.st_uid == getuid() && info.st_mode & 0o177777 == 0o040700,
            "V01 evidence directory identity/owner/mode invalid")
    }
    let names = ["setup-idle", "setup-idle-control", "setup-result", "settings-result"]
    var captures = 0, retainedBytes = 0
    var format: String?
    func capture(_ name: String) throws -> Data {
        try expect(captures < names.count && captures < 5 && name == names[captures], "V01 capture count/name out of bounds")
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        // Same bounded native settlement as menuPaint; no retries or longer sleep.
        let deadline = Date().addingTimeInterval(0.20)
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
        }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        try expect(host.bounds == NSRect(x: 0, y: 0, width: 800, height: 1100), "V01 logical capture geometry changed")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CheckFailure(description: "V01 native bitmap unavailable")
        }
        try expect(bitmap.pixelsWide >= 800 && bitmap.pixelsWide <= 1600 &&
            bitmap.pixelsHigh >= 1100 && bitmap.pixelsHigh <= 2200 &&
            bitmap.pixelsWide * 1100 == bitmap.pixelsHigh * 800 &&
            bitmap.bytesPerRow > 0 && bitmap.bytesPerRow <= 1600 * 16 &&
            bitmap.bitsPerSample == 8 && bitmap.bitsPerPixel > 0 && bitmap.bitsPerPixel <= 128 &&
            bitmap.bytesPerRow >= bitmap.pixelsWide * ((bitmap.bitsPerPixel + 7) / 8) && !bitmap.isPlanar, "V01 native bitmap geometry/format outside bounds")
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try expect(!window.isVisible && !app.isActive && app.activationPolicy() == .prohibited,
                   "V01 capture became visible/active")
        let currentFormat = "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh):\(bitmap.bitsPerSample):\(bitmap.bitsPerPixel):\(bitmap.samplesPerPixel):\(bitmap.bytesPerRow):\(bitmap.bitmapFormat.rawValue):\(bitmap.colorSpaceName.rawValue)"
        if let format { try expect(format == currentFormat, "V01 same-host bitmap format changed") }
        else { format = currentFormat }
        guard let pixels = bitmap.bitmapData, let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckFailure(description: "V01 native pixels/PNG unavailable")
        }
        try expect(!png.isEmpty && png.count <= 8 * 1024 * 1024 && retainedBytes + png.count <= 40 * 1024 * 1024,
                   "V01 PNG output outside bounds")
        // Compare actual packed pixel rows, excluding allocator-owned row padding.
        let rowBytes = bitmap.pixelsWide * ((bitmap.bitsPerPixel + 7) / 8)
        var bytes = Data(capacity: rowBytes * bitmap.pixelsHigh)
        for row in 0..<bitmap.pixelsHigh {
            bytes.append(pixels.advanced(by: row * bitmap.bytesPerRow), count: rowBytes)
        }
        try expect(!bytes.isEmpty, "V01 native pixel data empty")
        if evidenceDirectory >= 0 {
            let descriptor = Darwin.openat(evidenceDirectory, name + ".png", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            try expect(descriptor >= 0, "V01 evidence file must be exclusive/no-follow")
            defer { _ = Darwin.close(descriptor) }
            var info = stat()
            try expect(Darwin.fstat(descriptor, &info) == 0 && info.st_uid == getuid() &&
                info.st_mode & 0o177777 == 0o100600 && info.st_nlink == 1, "V01 evidence file owner/type/mode invalid")
            try png.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { throw CheckFailure(description: "V01 PNG buffer unavailable") }
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                    try expect(written > 0, "V01 evidence write failed")
                    offset += written
                }
            }
            try expect(Darwin.fsync(descriptor) == 0, "V01 evidence flush failed")
        }
        captures += 1; retainedBytes += png.count
        let pixelHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let pngHash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        print("COMPOSITION-V01-CAPTURE name=\(name) logical=800x1100 bitmap=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) scale=\(Double(bitmap.pixelsWide) / 800) format=\(currentFormat) pngBytes=\(png.count) pixelSHA256=\(pixelHash) pngSHA256=\(pngHash) retained=\(evidenceDirectory >= 0)")
        return bytes
    }
    try await body(capture)
    try expect(captures == names.count, "V01 did not capture all required native states")
}

@MainActor private func compositionView(_ session: NativeClientSession) -> NativeNetworkSettingsView {
    NativeNetworkSettingsView(controller: session.network, probe: session.networkProbe)
}
@MainActor private func compositionApplied(_ settings: NativeNetworkSettingsController, mode: NetworkMode = .direct, port: UInt16 = 1) throws {
    settings.edit(mode: mode, host: "127.0.0.1", port: String(port))
    try expect(settings.applyChoice(), "SETUP FAILURE: controlled choice did not apply")
}
@MainActor private func compositionResponse(_ session: NativeClientSession, status: Int = 200, bytes: Int) throws {
    try expect(session.networkProbe.state == .finished(.response(statusCode: status, bytes: bytes)),
               "BEHAVIOURAL RED: actual consumer response absent, got \(session.networkProbe.state)")
    try expect(session.networkProbe.statusText.contains("HTTP \(status)") && session.networkProbe.statusText.contains("\(bytes) bytes") &&
        session.networkProbe.statusText.contains("does not establish Internet or service reachability"), "Real response is not finite truthful visible guidance")
}

@MainActor func registerNativeNetworkProbeCompositionChecks() {
    check("PAT2666 composition S01 independent real-worker direct peer setup control") {
        let origin = try CompositionPeer(response: compositionHTTP("setup")); defer { compositionEvidence("S01 final", [origin]); origin.stop() }
        let port = try await compositionPort(origin)
        let provider = CompositionObservation(), settings = NativeNetworkSettingsController(provider: provider)
        try compositionApplied(settings)
        let worker = NativeNetworkConnectionProbe(settings: settings)
        var outcome: NativeConnectionProbeOutcome?
        worker.start(url: URL(string: "http://127.0.0.1:\(port)/probe")!) { outcome = $0 }
        defer { worker.cancel() }
        try await compositionWait("setup worker response") { outcome != nil }
        compositionEvidence("S01 before assertions", [origin])
        try expect(outcome == .response(statusCode: 200, bytes: 5) && origin.snapshot().connections == 1 &&
            origin.snapshot().headers.first?.hasPrefix("GET /probe HTTP/1.1\r\n") == true, "SETUP FAILURE: real-worker peer control failed")
        try expect(provider.calls == 0, "SETUP FAILURE: control started observation")
    }
    check("PAT2666 composition P01 shared owner across setup/settings/menu navigation") {
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:1/probe")
        let settings = session.network, probe = session.networkProbe
        try expect(probe.settings === settings && session.firstRun.network === settings && session.firstRun.networkProbe === probe,
                   "Actual development session has competing owners")
        session.firstRun.showNetwork()
        _ = try compositionPixels(NativeClientRootView(session: session))
        session.firstRun.returnFromNetwork(); session.firstRun.dismiss()
        for destination in ShellDestination.allCases {
            session.navigation.select(destination)
            for section in ShellSettingsSection.allCases { session.navigation.selectSettings(section) }
            _ = try compositionPixels(NativeClientRootView(session: session))
            try expect(session.networkProbe === probe && session.network === settings, "Navigation replaced real owner")
        }
        _ = try compositionPixels(NativeClientMenuView(session: session, openWindow: {}))
        let other = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:2/probe")
        try expect(other.network !== settings && other.networkProbe !== probe, "Separate sessions share diagnostic authority")
        let first = code(try source("Sources/PatchedClient/NativeFirstRunView.swift"))
        let root = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        try expect(first.contains("NativeNetworkSettingsView(controller: controller.network, probe: controller.networkProbe)") &&
            root.contains("NativeNetworkSettingsView(controller: session.network, probe: session.networkProbe)"), "Actual roots omit retained probe owner")
    }
    check("PAT2666 composition P02 construction edit apply preferences render remain inert") {
        let peer = try CompositionPeer(response: compositionHTTP()); defer { compositionEvidence("P02 final", [peer]); peer.stop() }
        let port = try await compositionPort(peer)
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
        try compositionApplied(session.network)
        session.firstRun.showNetwork(); _ = try compositionPixels(NativeClientRootView(session: session)); session.firstRun.returnFromNetwork()
        session.firstRun.dismiss(); session.navigation.select(.settings); session.navigation.selectSettings(.network)
        _ = try compositionPixels(NativeClientRootView(session: session)); _ = try compositionPixels(compositionView(session))
        let observation = CompositionObservation(), network = NativeNetworkSettingsController(provider: observation)
        let store = CompositionStore(), generation = "pat2666-composition-generation"
        let prefs = PreferenceSession(store: store, principal: SchedulingPrincipal("pat2666-composition-principal"),
            storeScope: "pat2666-composition-scope", generation: generation, queueID: "pat2666-composition-queue")
        let setup = NativeFirstRunController(navigation: session.navigation, applications: session.applications,
            network: network, preferences: prefs, generation: generation)
        setup.openPreferences(); _ = setup.createFreshPreferences()
        network.edit(mode: .manualHTTP, host: "127.0.0.1", port: String(port))
        _ = setup.saveChoices(complete: false); setup.openPreferences()
        try await Task.sleep(nanoseconds: 150_000_000)
        compositionEvidence("P02 before assertions", [peer])
        try expect(store.reads > 0 && store.writes > 0 && setup.acceptedRevision != nil && setup.firstRunSetup?.networkDraft.host == "127.0.0.1", "Fixture preference save/reload missing")
        try expect(observation.calls == 0 && network.choice == nil && session.network.snapshot == nil && !session.network.isRefreshing &&
            session.networkProbe.state == .idle && peer.snapshot().connections == 0, "Construction/edit/Apply/preferences/navigation/render performed I/O")
        // Preserve the original descriptive Apply/Refresh ownership and stale fence.
        network.refresh()
        try expect(observation.calls == 1 && network.isRefreshing, "Explicit refresh/provider count changed")
        let stale = observation.callbacks[0]
        network.edit(mode: .direct)
        stale(NativeNetworkObservation(path: .offline, proxy: .pacUnsupported))
        try expect(network.snapshot == nil && !network.isRefreshing && observation.requests[0].cancellations == 1,
                   "Edit failed to revoke old observation callback")
        try expect(network.applyChoice() && observation.calls == 1, "Apply unexpectedly observed network")
        network.refresh(); network.cancelRefresh()
        observation.callbacks[1](NativeNetworkObservation(path: .available, proxy: .noConfiguredProxy))
        try expect(observation.calls == 2 && observation.requests[1].cancellations == 1 && network.snapshot == nil,
                   "Cancelled refresh callback retained observation authority")
        let ordinary = NativeClientSession()
        ordinary.networkProbe.test()
        try expect(ordinary.networkProbe.configuration == .unconfigured && !ordinary.networkProbe.canTest && !ordinary.networkProbe.isRunning,
                   "Ordinary construction acquired a development route")
    }
    check("PAT2666 composition P03 explicit direct controlled result reaches visible consumer") {
        let origin = try CompositionPeer(response: compositionHTTP("direct-result")); defer { compositionEvidence("P03 final", [origin]); origin.stop() }
        let port = try await compositionPort(origin)
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
        try compositionApplied(session.network)
        let before = try compositionPixels(compositionView(session))
        var states: [NativeNetworkProbeState] = []
        let token = session.networkProbe.$state.dropFirst().sink { states.append($0) }; defer { token.cancel() }
        session.networkProbe.test(); try await compositionSettled(session.networkProbe)
        let after = try compositionPixels(compositionView(session))
        compositionEvidence("P03 before assertions", [origin])
        try expect(origin.snapshot().connections == 1 && origin.snapshot().headers.count == 1 &&
            origin.snapshot().headers[0].hasPrefix("GET /probe HTTP/1.1\r\n"), "BEHAVIOURAL RED: real consumer did not reach controlled origin exactly once")
        try compositionResponse(session, bytes: 13)
        try expect(states.contains(.running) && before != after, "Actual action/result did not alter rendered consumer")
    }
    check("PAT2666 composition P04 explicit manual selected route reaches visible consumer") {
        let origin = try CompositionPeer(response: compositionHTTP("origin-sentinel", status: "418 Unused"))
        let proxy = try CompositionPeer(response: compositionHTTP("manual-result")); defer { compositionEvidence("P04 final", [origin, proxy]); proxy.stop(); origin.stop() }
        let originPort = try await compositionPort(origin), proxyPort = try await compositionPort(proxy)
        let endpoint = "http://127.0.0.1:\(originPort)/probe"
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: endpoint)
        try compositionApplied(session.network, mode: .manualHTTP, port: proxyPort)
        session.networkProbe.test(); try await compositionSettled(session.networkProbe)
        compositionEvidence("P04 before assertions", [origin, proxy])
        if #available(macOS 14.0, *) {
            let expectedRequest = "GET \(endpoint) HTTP/1.1\r\nHost: 127.0.0.1:\(originPort)\r\n" +
                "Connection: close\r\nAccept-Encoding: identity\r\n\r\n"
            try expect(proxy.snapshot().connections == 1 && proxy.snapshot().headers == [expectedRequest],
                       "BEHAVIOURAL RED: actual consumer did not send exact absolute-form request to selected proxy")
            try compositionResponse(session, bytes: 13)
        } else {
            try expect(session.networkProbe.state == .finished(.refused(.unsupportedProxy)) && proxy.snapshot().connections == 0, "macOS13 manual route did not refuse")
        }
        try expect(origin.snapshot().connections == 0 && origin.snapshot().headers.isEmpty, "Selected proxy bypassed to live origin")
    }
    for refreshing in [false, true] {
        check("PAT2666 composition R01 no applied choice or refreshing \(refreshing)") {
            let peer = try CompositionPeer(response: compositionHTTP()); defer { compositionEvidence("R01 final", [peer]); peer.stop() }
            let port = try await compositionPort(peer), observation = CompositionObservation()
            let settings = NativeNetworkSettingsController(provider: observation)
            if refreshing { try compositionApplied(settings); settings.refresh() }
            let owner = NativeNetworkProbeController(settings: settings, rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            owner.test(); try await compositionSettled(owner)
            compositionEvidence("R01 before assertions", [peer])
            try expect(owner.state == .finished(.refused(.notApplied)) && !owner.isRunning &&
                peer.snapshot().connections == 0 && observation.calls == (refreshing ? 1 : 0), "No-choice/refreshing Test did work or lost finite refusal")
            settings.cancelRefresh()
        }
    }
    let invalid = ["", "http://localhost:80/probe", "https://127.0.0.1:80/probe", "http://example.invalid:80/probe",
        "http://127.0.0.1/probe", "http://127.0.0.1:0/probe", "http://127.0.0.1:65536/probe", "http://127.0.0.1:000001/probe",
        "http://127.0.0.1:80/probe?", "http://127.0.0.1:80/probe#", "http://user@127.0.0.1:80/probe",
        "http://127.0.0.1:80/%70robe", "http://127.0.0.1:80/a/../probe", " http://127.0.0.1:80/probe",
        "http://127.0.0.1:80/probe\n", "HTTP://127.0.0.1:80/probe", "http://127.0.0.1:８０/probe",
        "http://[0:0:0:0:0:0:0:1]:80/probe", "http://127.000.0.1:80/probe", "http://127.0.0.1:80/probe\u{0}", String(repeating: "x", count: 4096)]
    for (index, raw) in invalid.enumerated() {
        check("PAT2666 composition R02 invalid closed endpoint vector \(index)") {
            let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: raw)
            try compositionApplied(session.network)
            session.networkProbe.test()
            try expect(session.networkProbe.configuration == .invalid && session.networkProbe.state == .finished(.refused(.unsupportedEndpoint)) &&
                !session.networkProbe.isRunning && session.networkProbe.statusText == "Controlled local configuration refused.", "Invalid original bytes acquired route or leaked input")
        }
    }
    for host in ["localhost", "192.0.2.1"] {
        check("PAT2666 composition R02 unsupported proxy \(host)") {
            let peer = try CompositionPeer(response: compositionHTTP()); defer { compositionEvidence("R02 proxy final", [peer]); peer.stop() }
            let port = try await compositionPort(peer)
            let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            session.network.edit(mode: .manualHTTP, host: host, port: "8080")
            try expect(session.network.applyChoice(), "SETUP FAILURE: descriptive proxy choice refused")
            session.networkProbe.test(); try await compositionSettled(session.networkProbe)
            compositionEvidence("R02 proxy before assertions", [peer])
            try expect(session.networkProbe.state == .finished(.refused(.unsupportedProxy)) && peer.snapshot().connections == 0, "Unsupported proxy acquired native dispatch")
        }
    }
    for mode in [NetworkMode.direct, .manualHTTP] {
        check("PAT2666 composition R03 observed offline \(mode)") {
            let peer = try CompositionPeer(response: compositionHTTP()); defer { compositionEvidence("R03 final", [peer]); peer.stop() }
            let port = try await compositionPort(peer), observation = CompositionObservation()
            let settings = NativeNetworkSettingsController(provider: observation)
            settings.refresh(); observation.callbacks[0](NativeNetworkObservation(path: .offline, proxy: .noConfiguredProxy))
            try compositionApplied(settings, mode: mode, port: port)
            let owner = NativeNetworkProbeController(settings: settings, rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            owner.test(); try await compositionSettled(owner)
            compositionEvidence("R03 before assertions", [peer])
            try expect(owner.state == .finished(.refused(.offline)) && owner.statusText.contains("observation") &&
                settings.text.provenance == "Test double" && peer.snapshot().connections == 0 && observation.calls == 1, "Offline observation was ignored or overstated")
        }
    }
    check("PAT2666 composition R04 dead selected proxy never falls back") {
        let origin = try CompositionPeer(response: compositionHTTP("origin-sentinel")), proxy = try CompositionPeer(response: nil)
        defer { compositionEvidence("R04 final", [origin, proxy]); proxy.stop(); origin.stop() }
        let port = try await compositionPort(origin), proxyPort = try await compositionPort(proxy); proxy.stop()
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
        try compositionApplied(session.network, mode: .manualHTTP, port: proxyPort)
        session.networkProbe.test(); try await compositionSettled(session.networkProbe)
        compositionEvidence("R04 before assertions", [origin, proxy])
        let expected: NativeConnectionProbeOutcome
        if #available(macOS 14.0, *) { expected = .refused(.transportFailed) } else { expected = .refused(.unsupportedProxy) }
        try expect(session.networkProbe.state == .finished(expected) && origin.snapshot().connections == 0 && origin.snapshot().headers.isEmpty,
                   "Dead proxy escaped finite refusal or reached live origin")
    }
    let responses: [(String, Data, NativeConnectionProbeOutcome)] = [
        ("401", compositionHTTP("secret-body", status: "401 Unauthorized", extra: "WWW-Authenticate: Basic realm=secret-header\r\n"), .refused(.authenticationRequired)),
        ("407", compositionHTTP("secret-body", status: "407 Proxy Authentication Required"), .refused(.authenticationRequired)),
        ("redirect", compositionHTTP("secret-body", status: "302 Found", extra: "Location: http://example.invalid/secret-location\r\n"), .refused(.unsupportedEndpoint)),
        ("oversize", Data("HTTP/1.1 200 OK\r\nContent-Length: 65537\r\n\r\n".utf8), .refused(.responseTooLarge)),
        ("framing", Data("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nx".utf8), .refused(.transportFailed)),
        ("503 response is not service success", compositionHTTP("secret-body", status: "503 Unavailable"), .response(statusCode: 503, bytes: 11))]
    for (name, response, expected) in responses {
        check("PAT2666 composition R05 finite actual response mapping \(name)") {
            let origin = try CompositionPeer(response: compositionHTTP("origin-sentinel")), proxy = try CompositionPeer(response: response)
            defer { compositionEvidence("R05 \(name) final", [origin, proxy]); proxy.stop(); origin.stop() }
            let port = try await compositionPort(origin), proxyPort = try await compositionPort(proxy)
            let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            try compositionApplied(session.network, mode: .manualHTTP, port: proxyPort)
            session.networkProbe.test(); try await compositionSettled(session.networkProbe)
            compositionEvidence("R05 before assertions", [origin, proxy])
            if #available(macOS 14.0, *) {
                try expect(proxy.snapshot().connections == 1 && proxy.snapshot().headers.count == 1 &&
                    session.networkProbe.state == .finished(expected), "BEHAVIOURAL RED: real finite response did not reach consumer")
            } else { try expect(session.networkProbe.state == .finished(.refused(.unsupportedProxy)), "macOS13 manual route was attempted") }
            let text = session.networkProbe.statusText
            for secret in ["secret-body", "secret-header", "secret-location", "example.invalid", "http://", "success"] {
                try expect(!text.lowercased().contains(secret), "Consumer interpolated response data or claimed success")
            }
            _ = try compositionPixels(compositionView(session))
            try expect(origin.snapshot().connections == 0, "Finite refusal or HTTP status triggered fallback")
        }
    }
    for action in ["cancel", "edit", "refresh"] {
        check("PAT2666 composition R06 held busy \(action) invalidation and late callback fence") {
            let origin = try CompositionPeer(response: nil); defer { compositionEvidence("R06 \(action) final", [origin]); origin.stop() }
            let port = try await compositionPort(origin)
            let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            try compositionApplied(session.network)
            let owner = session.networkProbe
            var settlements: [NativeNetworkProbeState] = []
            let token = owner.$state.dropFirst().sink { if case .finished = $0 { settlements.append($0) } }; defer { token.cancel() }
            owner.test(); try await compositionPending(origin, owner)
            owner.test()
            try expect(owner.isRunning && owner.state == .running && settlements.isEmpty, "Busy gesture overwrote active authority")
            if action == "cancel" { owner.cancel(); owner.cancel() }
            else if action == "edit" { session.network.edit(mode: .direct) }
            else { session.network.refresh(); session.network.cancelRefresh() }
            let expected: NativeConnectionProbeOutcome = .refused(action == "cancel" ? .cancelled : .changedSettings)
            try expect(owner.state == .finished(expected) && settlements == [.finished(expected)] && !owner.isRunning,
                       "Old operation did not settle exactly once before publication")
            try compositionApplied(session.network)
            owner.test(); try await compositionPending(origin, owner, requests: 2)
            owner.cancel()
            let final = owner.state
            origin.release(compositionHTTP("late-body")); try await Task.sleep(nanoseconds: 200_000_000)
            compositionEvidence("R06 before final assertions", [origin])
            try expect(owner.state == final && settlements.count == 2 && origin.snapshot().connections == 2, "Late callback replaced state or extra request occurred")
        }
    }
    check("PAT2666 composition R07 immutable endpoint replacement isolates abandoned owner") {
        let oldPeer = try CompositionPeer(response: nil), newPeer = try CompositionPeer(response: compositionHTTP("new-result"))
        defer { compositionEvidence("R07 final", [oldPeer, newPeer]); newPeer.stop(); oldPeer.stop() }
        let oldPort = try await compositionPort(oldPeer), newPort = try await compositionPort(newPeer)
        let old = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(oldPort)/probe")
        let new = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(newPort)/probe")
        try compositionApplied(old.network); try compositionApplied(new.network)
        old.networkProbe.test(); try await compositionPending(oldPeer, old.networkProbe); old.networkProbe.cancel()
        new.networkProbe.test(); try await compositionSettled(new.networkProbe)
        oldPeer.release(compositionHTTP("abandoned")); try await Task.sleep(nanoseconds: 150_000_000)
        compositionEvidence("R07 before assertions", [oldPeer, newPeer])
        try compositionResponse(new, bytes: 10)
        try expect(old.networkProbe.state == .finished(.refused(.cancelled)) && old.networkProbe !== new.networkProbe &&
            oldPeer.snapshot().connections == 1 && newPeer.snapshot().connections == 1, "Abandoned owner affected replacement")
        let controller = code(try source("Sources/PatchedClient/NativeNetworkProbeController.swift"))
        try expect(controller.contains("private let endpoint:") && !controller.contains("func setEndpoint"), "Endpoint is mutable")
    }
    check("PAT2666 composition R08 provenance cannot mint trust or change setup owners") {
        let observation = CompositionObservation(), settings = NativeNetworkSettingsController(provider: observation)
        let owner = NativeNetworkProbeController(settings: settings, rawProbeEndpoint: "http://127.0.0.1:1/probe")
        settings.refresh(); observation.callbacks[0](NativeNetworkObservation(path: .offline, proxy: .noConfiguredProxy))
        try compositionApplied(settings); let revision = settings.revision, choice = settings.choice
        owner.test()
        try expect(settings.provenance == .testDouble && settings.text.provenance == "Test double" &&
            settings.revision == revision && settings.choice == choice, "Consumer changed descriptive provenance or applied choice")
        let actual = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:1/probe")
        let setup = actual.firstRun, applications = actual.applications, schedule = actual.scheduleSettings
        actual.networkProbe.test()
        try expect(actual.firstRun === setup && actual.applications === applications && actual.scheduleSettings === schedule &&
            setup.acceptedRevision == nil && setup.firstRunSetup == nil, "Diagnostic minted saved preferences or another owner")
        let text = code(try source("Sources/PatchedClient/NativeNetworkProbeController.swift"))
        for forbidden in ["SecItem", "URLSession", "NWConnection", "PreferenceSession(", "NativePreferenceContext", "bootstrapFresh", "installationAllowed", "grant"] {
            try expect(!text.contains(forbidden), "Consumer crossed trust boundary: \(forbidden)")
        }
    }
    check("PAT2666 composition R09 synchronous refusal has no residual running state") {
        let settings = NativeNetworkSettingsController(provider: CompositionObservation())
        let owner = NativeNetworkProbeController(settings: settings, rawProbeEndpoint: "http://127.0.0.1:1/probe")
        owner.test()
        try expect(owner.state == .finished(.refused(.notApplied)) && !owner.isRunning, "Synchronous admission refusal left running state")
        let invalid = NativeNetworkProbeController(settings: settings, rawProbeEndpoint: "http://localhost:1/probe")
        invalid.test()
        try expect(invalid.state == .finished(.refused(.unsupportedEndpoint)) && !invalid.isRunning, "Synchronous configuration refusal left running state")
    }
    for action in ["cancel", "edit"] {
        check("PAT2666 composition R09 synchronous running publication \(action) prevents dispatch") {
            let origin = try CompositionPeer(response: compositionHTTP()); defer { compositionEvidence("R09 \(action) final", [origin]); origin.stop() }
            let port = try await compositionPort(origin)
            let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            try compositionApplied(session.network)
            let owner = session.networkProbe
            let token = owner.$state.dropFirst().sink { value in
                if value == .running { if action == "cancel" { owner.cancel() } else { session.network.edit(mode: .direct) } }
            }; defer { token.cancel() }
            owner.test(); try await compositionSettled(owner)
            compositionEvidence("R09 before assertions", [origin])
            let refusal: NativeConnectionProbeRefusal = action == "cancel" ? .cancelled : .changedSettings
            try expect(owner.state == .finished(.refused(refusal)) && !owner.isRunning && origin.snapshot().connections == 0,
                       "Synchronous published-state invalidation was overwritten or followed by dispatch")
        }
    }
    check("PAT2666 composition R09 completion publication can start another real operation") {
        let origin = try CompositionPeer(response: compositionHTTP("again")); defer { compositionEvidence("R09 restart final", [origin]); origin.stop() }
        let port = try await compositionPort(origin)
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
        try compositionApplied(session.network)
        let owner = session.networkProbe
        var restarted = false, responses = 0
        let token = owner.$state.dropFirst().sink { value in
            if case .finished(.response) = value {
                responses += 1
                if !restarted { restarted = true; owner.test() }
            }
        }; defer { token.cancel() }
        owner.test()
        try await compositionWait("consumer restart settlements") { (!owner.isRunning && owner.state != .idle && !restarted) || responses == 2 }
        try await compositionSettled(owner)
        compositionEvidence("R09 restart before assertions", [origin])
        try expect(restarted && responses == 2 && origin.snapshot().connections == 2, "BEHAVIOURAL RED: real completion restart was lost or never reached")
        try compositionResponse(session, bytes: 5)
    }
    for action in ["edit", "apply", "refresh", "observation"] {
        check("PAT2666 composition R10 completed result freshness \(action)") {
            let origin = try CompositionPeer(response: compositionHTTP("fresh")); defer { compositionEvidence("R10 \(action) final", [origin]); origin.stop() }
            let port = try await compositionPort(origin), provider = CompositionObservation()
            let network = NativeNetworkSettingsController(provider: provider)
            let probe = NativeNetworkProbeController(settings: network, rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
            let navigation = ShellNavigation(destination: .settings, settingsSection: .network, drafts: ShellDrafts(values: [:]))
            let apps = LocalApplicationsController()
            let first = NativeFirstRunController(navigation: navigation, applications: apps, network: network, networkProbe: probe)
            let session = NativeClientSession(navigation: navigation, applications: apps, inspection: ClientController(), network: network, firstRun: first)
            try compositionApplied(network); probe.test(); try await compositionSettled(probe)
            compositionEvidence("R10 response before assertions", [origin])
            try compositionResponse(session, bytes: 5)
            session.navigation.select(.applications); session.navigation.select(.settings); first.dismiss()
            _ = try compositionPixels(NativeClientRootView(session: session))
            try expect(probe.state == .finished(.response(statusCode: 200, bytes: 5)) && origin.snapshot().connections == 1,
                       "Navigation alone lost result or dispatched again")
            switch action {
            case "edit": network.edit(mode: .direct)
            case "apply": _ = network.applyChoice()
            case "refresh": network.refresh(); network.cancelRefresh()
            default:
                network.refresh(); provider.callbacks[0](NativeNetworkObservation(path: .available, proxy: .noConfiguredProxy))
            }
            try expect(probe.state == .stale && probe.statusText.contains("stale") && !probe.isRunning, "Finished response remained current after settings publication")
            compositionEvidence("R10 freshness before assertions", [origin])
            try expect(origin.snapshot().connections == 1, "Freshness invalidation dispatched another probe")
        }
    }
    check("PAT2666 composition R11 exact launch selector DEBUG app binding and release isolation") {
        let flag = "--controlled-local-network-probe"
        for args in [[], ["app"], ["app", flag], ["app", "--other", "http://127.0.0.1:1/probe"],
                     ["app", flag, "http://127.0.0.1:1/probe", "extra"]] {
            try expect(NativeDevelopmentProbeLaunch.rawEndpoint(arguments: args) == nil, "Non-exact argv selected a diagnostic")
        }
        for raw in ["http://127.0.0.1:1/probe", "http://[::1]:65535/probe", "http://127.0.0.1:00001/probe"] {
            let selected = NativeDevelopmentProbeLaunch.rawEndpoint(arguments: ["app", flag, raw])
            try expect(selected.map { Array($0.utf8) } == Array(raw.utf8), "Selector changed original endpoint bytes")
            let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: selected!)
            try expect(session.networkProbe.configuration == .controlledLocal && session.networkProbe.state == .idle && session.network.choice == nil,
                       "Valid closed endpoint was not retained inertly")
        }
        let malformed = NativeDevelopmentProbeLaunch.rawEndpoint(arguments: ["app", flag, "http://localhost:80/probe"])!
        try expect(NativeClientSession.controlledDevelopment(rawProbeEndpoint: malformed).networkProbe.configuration == .invalid,
                   "Exact argv bypassed endpoint grammar")
        try expect(NativeClientSession().networkProbe.configuration == .unconfigured, "Ordinary path configured diagnostic")
        let app = code(try source("Sources/PatchedApp/PatchedApp.swift"))
        guard let debug = app.range(of: "#if DEBUG"), let end = app.range(of: "#endif", range: debug.upperBound..<app.endIndex),
              let worker = app.range(of: "InstalledIdentityWorker.dispatchChild(arguments: CommandLine.arguments)"),
              let exit = app.range(of: "exit(status)"), let launch = app.range(of: "PatchedApp.main()") else {
            throw CheckFailure(description: "Actual app lacks guarded selector/worker dispatch")
        }
        let selectedBlock = String(app[debug.upperBound..<end.lowerBound])
        let releaseSource = String(app[..<debug.lowerBound]) + String(app[end.upperBound...])
        try expect(selectedBlock.contains("NativeDevelopmentProbeLaunch.rawEndpoint(arguments: CommandLine.arguments)") &&
            selectedBlock.contains("NativeClientSession.controlledDevelopment(rawProbeEndpoint: raw)") &&
            !releaseSource.contains("controlledDevelopment(") && !releaseSource.contains("rawEndpoint(arguments:") &&
            releaseSource.contains("return NativeClientSession()"), "Release actual app acquired development selection")
        try expect(worker.lowerBound < exit.lowerBound && exit.lowerBound < launch.lowerBound &&
            app.components(separatedBy: "@StateObject private var session").count == 2 &&
            app.contains("@StateObject private var session = PatchedApp.makeSession()"), "Worker-first/single-session ownership changed")
        let first = code(try source("Sources/PatchedClient/NativeFirstRunController.swift"))
        let root = code(try source("Sources/PatchedClient/NativeClientSession.swift"))
        try expect(root.contains("setup.network === resolvedNetwork") && first.contains("precondition(probe.settings === network"), "Testing owner identity fence removed")
    }
    check("PAT2666 composition V01 actual setup and Settings controls render real finite result") {
        let peer = try CompositionPeer(response: compositionHTTP("visible")); defer { compositionEvidence("V01 final", [peer]); peer.stop() }
        let port = try await compositionPort(peer)
        let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
        session.firstRun.showNetwork(); try compositionApplied(session.network)
        try await compositionV01NativePaint(session) { capture in
            let before = try capture("setup-idle")
            let idleControl = try capture("setup-idle-control")
            try expect(before == idleControl && peer.snapshot().connections == 0 && peer.snapshot().headers.isEmpty &&
                session.networkProbe.state == .idle && !session.networkProbe.isRunning,
                "V01 unchanged native setup is unstable or performed a request")
            let view = code(try source("Sources/PatchedClient/NativeNetworkSettingsView.swift"))
            for required in ["probe.showsDevelopmentControls", "Development controlled local probe", "probe.test()", "probe.cancel()", "probe.statusText", "!probe.canTest", "!probe.isRunning", "controller.applyChoice()", "controller.refresh()"] {
                try expect(view.contains(required), "Actual view lacks bound finite control: \(required)")
            }
            for forbidden in ["Task {", ".onAppear", ".task", "URLSession", "SecureField", "rawProbeEndpoint", "Font.custom"] {
                try expect(!view.contains(forbidden), "View adds I/O or internal endpoint entry: \(forbidden)")
            }
            try expect(session.firstRun.networkProbe === session.networkProbe, "First-run action uses another owner")
            session.networkProbe.test(); try await compositionSettled(session.networkProbe)
            let setupAfter = try capture("setup-result")
            session.firstRun.returnFromNetwork(); session.firstRun.dismiss()
            session.navigation.select(.settings); session.navigation.selectSettings(.network)
            _ = try capture("settings-result")
            try expect(peer.snapshot().connections == 1 && peer.snapshot().headers.count == 1, "V01 Settings navigation added a request")
            compositionEvidence("V01 before result assertions", [peer])
            try compositionResponse(session, bytes: 7)
            try expect(peer.snapshot().connections == 1 && before != setupAfter, "BEHAVIOURAL RED: real view action/result missing")
            let ordinary = NativeClientSession()
            try expect(!ordinary.networkProbe.showsDevelopmentControls && !ordinary.networkProbe.canTest, "Ordinary Network exposes internal probe controls")
        }
    }
    check("PAT2666 composition S02 all owned peers quiesce with bounded cancellation") {
        let peer = try CompositionPeer(response: nil)
        _ = try await compositionPort(peer)
        let joined = peer.stop()
        compositionEvidence("S02 shutdown before assertions", [peer])
        let snapshot = peer.snapshot()
        try expect(joined && snapshot.stopped && snapshot.listenerCancelled && snapshot.cancelled == snapshot.connections &&
            compositionCleanup.failures == 0, "SETUP/CLEANUP FAILURE (not meaningful RED): controlled peers did not quiesce")
    }

}

// Add-only supplemental publication checks. The peer remains the original real
// loopback peer; descriptive observations never inject a transport outcome.
@MainActor private final class CompositionSupplementalRecord {
    var owner: NativeNetworkProbeController?
    var network: NativeNetworkSettingsController?
    var token: AnyCancellable?
    var states: [NativeNetworkProbeState] = []
    var restarted = false, mutated = false, observationDelivered = false
    var applied: Bool?
    var observationCalls = 0
    func evidence(_ label: String) {
        let value: [String: Any] = ["label": label, "state": owner.map { String(describing: $0.state) } ?? "unconstructed",
            "isRunning": owner?.isRunning ?? false, "isRefreshing": network?.isRefreshing ?? false,
            "notifications": states.map { String(describing: $0) }, "restarted": restarted, "mutated": mutated,
            "observationDelivered": observationDelivered, "observationCalls": observationCalls,
            "applyResult": applied.map { $0 as Any } ?? NSNull()]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print("COMPOSITION-SUPPLEMENTAL-STATE-EVIDENCE " + text) }
    }
}
@MainActor private func compositionSupplementalPeerCheck(_ label: String,
    _ body: @MainActor (CompositionPeer, CompositionSupplementalRecord) async throws -> Void) async throws {
    let peer = try CompositionPeer(response: compositionHTTP("fresh"))
    let record = CompositionSupplementalRecord()
    var bodyError: Error?
    do { try await body(peer, record) }
    catch {
        bodyError = error
        print("COMPOSITION-SUPPLEMENTAL-ORIGINAL-BODY-ERROR \(label): \(error)")
    }
    record.evidence(label + " before cleanup")
    compositionEvidence(label + " before cleanup", [peer])
    // Original S02 precedes these additions. Every new case must join and assert
    // its own peer, including when its body has already failed.
    record.token?.cancel(); record.token = nil
    record.owner?.cancel(); record.network?.cancelRefresh()
    let joined = peer.stop()
    record.evidence(label + " after cleanup before assertions")
    compositionEvidence(label + " after cleanup before assertions", [peer])
    let snapshot = peer.snapshot()
    var cleanupError: Error?
    do {
        try expect(joined && snapshot.stopped && snapshot.listenerCancelled && snapshot.cancelled == snapshot.connections &&
            record.owner?.isRunning != true && record.network?.isRefreshing != true,
            "SETUP/CLEANUP FAILURE (not meaningful RED): supplemental peer or operation did not quiesce: \(label)")
    } catch {
        cleanupError = error
        print("COMPOSITION-SUPPLEMENTAL-CLEANUP-ERROR \(label): \(error)")
    }
    // Preserve the original thrown error unchanged; cleanup failure is also
    // printed above and is thrown directly when there was no earlier error.
    if let bodyError { throw bodyError }
    if let cleanupError { throw cleanupError }
}

@MainActor func registerNativeNetworkProbeSupplementalReentrancyChecks() {
    for action in ["Cancel", "Edit"] {
        check("PAT2666 composition R09 nested completion restart then running \(action)") {
            try await compositionSupplementalPeerCheck("R09 nested " + action) { peer, record in
                let port = try await compositionPort(peer)
                let session = NativeClientSession.controlledDevelopment(rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
                try compositionApplied(session.network)
                let owner = session.networkProbe
                record.owner = owner; record.network = session.network
                record.token = owner.$state.dropFirst().sink { value in
                    record.states.append(value)
                    if value == .running && record.states.filter({ $0 == .running }).count == 2 {
                        if action == "Cancel" { owner.cancel() }
                        else { session.network.edit(mode: .direct) }
                    }
                    if case .finished(.response) = value, !record.restarted {
                        record.restarted = true
                        owner.test()
                    }
                }
                owner.test(); try await compositionSettled(owner)
                record.evidence("R09 nested " + action + " before assertions")
                compositionEvidence("R09 nested " + action + " before assertions", [peer])
                let responses = record.states.filter { if case .finished(.response) = $0 { return true }; return false }
                let refusals = record.states.filter { if case .finished(.refused) = $0 { return true }; return false }
                let refusal: NativeConnectionProbeRefusal = action == "Cancel" ? .cancelled : .changedSettings
                try expect(record.restarted && record.states.filter({ $0 == .running }).count == 2 &&
                    responses == [.finished(.response(statusCode: 200, bytes: 5))] && refusals == [.finished(.refused(refusal))] &&
                    owner.state == .finished(.refused(refusal)) && !owner.isRunning,
                    "BEHAVIOURAL RED: nested real completion restart/running invalidation lost finite ownership: \(action)")
                try expect(peer.snapshot().connections == 1 && peer.snapshot().headers.count == 1 &&
                    peer.snapshot().headers[0].hasPrefix("GET /probe HTTP/1.1\r\n"),
                    "BEHAVIOURAL RED: nested running invalidation emitted extra peer work or first real request was absent: \(action)")
                // Socket absence is effect evidence only. Parent source inspection
                // separately proves publication-drain ordering at probe.start.
            }
        }
    }
    for action in ["Edit", "Apply", "Refresh", "Observation"] {
        check("PAT2666 composition R10 response publication \(action)") {
            try await compositionSupplementalPeerCheck("R10 publication " + action) { peer, record in
                let port = try await compositionPort(peer), provider = CompositionObservation()
                let network = NativeNetworkSettingsController(provider: provider)
                let owner = NativeNetworkProbeController(settings: network, rawProbeEndpoint: "http://127.0.0.1:\(port)/probe")
                record.owner = owner; record.network = network
                try compositionApplied(network)
                record.token = owner.$state.dropFirst().sink { value in
                    record.states.append(value)
                    guard case .finished(.response) = value, !record.mutated else { return }
                    record.mutated = true
                    // Deliberately synchronous inside the first actual response
                    // notification, before Published assigns the outgoing value.
                    switch action {
                    case "Edit": network.edit(mode: .direct)
                    case "Apply": record.applied = network.applyChoice()
                    case "Refresh": network.refresh()
                    default:
                        network.refresh()
                        if let callback = provider.callbacks.first {
                            record.observationDelivered = true
                            callback(NativeNetworkObservation(path: .available, proxy: .noConfiguredProxy))
                        }
                    }
                    record.observationCalls = provider.calls
                }
                owner.test(); try await compositionSettled(owner)
                record.evidence("R10 publication " + action + " before assertions")
                compositionEvidence("R10 publication " + action + " before assertions", [peer])
                let responses = record.states.filter { if case .finished(.response) = $0 { return true }; return false }
                try expect(record.mutated && responses == [.finished(.response(statusCode: 200, bytes: 5))] &&
                    owner.state == .stale && owner.statusText.contains("stale") && !owner.isRunning,
                    "BEHAVIOURAL RED: first real response stayed current after synchronous settings publication: \(action)")
                try expect(peer.snapshot().connections == 1 && peer.snapshot().headers.count == 1 &&
                    peer.snapshot().headers[0].hasPrefix("GET /probe HTTP/1.1\r\n"),
                    "BEHAVIOURAL RED: response-publication invalidation dispatched extra peer work: \(action)")
                try expect(provider.calls == ((action == "Refresh" || action == "Observation") ? 1 : 0) &&
                    (action != "Apply" || record.applied == true) &&
                    (action != "Observation" || (record.observationDelivered && network.snapshot?.observation ==
                        NativeNetworkObservation(path: .available, proxy: .noConfiguredProxy))),
                    "Supplemental mutation or descriptive observation was not delivered exactly as requested: \(action)")
                // The wrapper cancels any pending descriptive refresh even if an
                // assertion throws, and checks refresh/peer quiescence afterwards.
            }
        }
    }
}
