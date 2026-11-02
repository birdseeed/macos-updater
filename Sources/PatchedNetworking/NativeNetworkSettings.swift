import Combine
import Foundation
import CoreFoundation
import CFNetwork
import Network

/// Read-only descriptive values. Neither a path nor proxy snapshot authorises transport.
public enum NativeNetworkPath: String, CaseIterable, Equatable, Sendable {
    case unknown, offline, available, constrained, expensive
}
public enum NativeNetworkProxy: String, CaseIterable, Equatable, Sendable {
    case unknown, noConfiguredProxy, httpConfigured, httpsConfigured, httpAndHTTPSConfigured
    case pacUnsupported, discoveryUnsupported, socksUnsupported, invalid
}
/// The real CFNetwork provider must use this same finite parser; raw values never enter status.
@_spi(Testing) public enum NativeNetworkProxySnapshot {
    public static func classify(_ settings: [String: Any]?) -> NativeNetworkProxy {
        guard let settings else { return .unknown }
        guard settings.count <= 128, settings["__SCOPED__"] == nil else { return .invalid }
        let keys = ["HTTPEnable", "HTTPSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable", "SOCKSEnable"]
        var flags: [Bool] = []
        for key in keys {
            guard let raw = settings[key] else { flags.append(false); continue }
            guard let number = integer(raw), number == 0 || number == 1 else { return .invalid }
            flags.append(number == 1)
        }
        if flags[2] { return .pacUnsupported }
        if flags[3] { return .discoveryUnsupported }
        if flags[4] { return .socksUnsupported }
        for (enabled, prefix) in [(flags[0], "HTTP"), (flags[1], "HTTPS")] where enabled {
            guard let host = settings[prefix + "Proxy"] as? String,
                  let rawPort = settings[prefix + "Port"], let port = integer(rawPort),
                  NetworkConfiguration(mode: .manualHTTP, host: host, port: port).validate() == .syntheticValid
            else { return .invalid }
        }
        if flags[0] && flags[1] { return .httpAndHTTPSConfigured }
        if flags[0] { return .httpConfigured }
        if flags[1] { return .httpsConfigured }
        return .noConfiguredProxy
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID(),
              !CFNumberIsFloatType(unsafeBitCast(number, to: CFNumber.self)) else { return nil }
        // Int64 conversion alone can truncate or wrap unsigned CFNumbers.
        let candidate = number.int64Value
        guard number.compare(NSNumber(value: candidate)) == .orderedSame,
              let result = Int(exactly: candidate) else { return nil }
        return result
    }
}
public enum NativeNetworkProvenance: String, Equatable, Sendable { case nativeSystem, testDouble }
public struct NativeNetworkObservation: Equatable, Sendable {
    public let path: NativeNetworkPath
    public let proxy: NativeNetworkProxy
    public init(path: NativeNetworkPath, proxy: NativeNetworkProxy) { self.path = path; self.proxy = proxy }
}
public struct NativeNetworkSettingsSnapshot: Equatable, Sendable {
    public let observation: NativeNetworkObservation
    public let provenance: NativeNetworkProvenance
    public let revision: UInt64
    public init(observation: NativeNetworkObservation, provenance: NativeNetworkProvenance, revision: UInt64) {
        self.observation = observation; self.provenance = provenance; self.revision = revision
    }
}
public struct NativeNetworkChoice: Equatable, Sendable {
    public let mode: NetworkMode
    public let host: String?
    public let port: Int?
    public init(mode: NetworkMode, host: String? = nil, port: Int? = nil) {
        self.mode = mode; self.host = host; self.port = port
    }
}
@_spi(Testing) @MainActor public protocol NativeNetworkObservationRequest: AnyObject {
    func cancel()
}
@_spi(Testing) @MainActor public protocol NativeNetworkObservationProvider: AnyObject {
    /// May complete synchronously. Native requests schedule a two second descriptive timeout.
    /// Cancellation releases platform work; late callbacks carry no current-state authority.
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest
}
public struct NativeNetworkSettingsText: Equatable, Sendable {
    public let status: String
    public let path: String
    public let proxy: String
    public let provenance: String
    public let freshness: String
    public let limitation: String
    public let guidance: String?
}

/// State retained by the client session. Construction, reading and editing never observe or persist.
@MainActor public final class NativeNetworkSettingsController: ObservableObject {
    @Published public private(set) var mode: NetworkMode = .system
    @Published public private(set) var host = ""
    @Published public private(set) var port = ""
    @Published public private(set) var revision: UInt64 = 1
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var snapshot: NativeNetworkSettingsSnapshot?
    @Published public private(set) var choice: NativeNetworkChoice?
    @Published private var invalidDraft = false
    public let provenance: NativeNetworkProvenance
    private let provider: any NativeNetworkObservationProvider
    private var pending: RequestCleanup?

    private init() { provenance = .nativeSystem; provider = NativeObservationProvider() }
    public static func native() -> NativeNetworkSettingsController { NativeNetworkSettingsController() }
    @_spi(Testing) public init(provider: any NativeNetworkObservationProvider) {
        provenance = .testDouble; self.provider = provider
    }
    public func edit(mode: NetworkMode, host: String = "", port: String = "") {
        cancelRefresh()
        // Saturation cannot revive an old callback: request identity is a separate fence.
        if revision < UInt64.max { revision += 1 }
        self.mode = mode
        self.host = mode == .manualHTTP ? (String(bytes: host.utf8.prefix(254), encoding: .utf8) ?? "") : ""
        self.port = mode == .manualHTTP ? (String(bytes: port.utf8.prefix(6), encoding: .utf8) ?? "") : ""
        choice = nil; invalidDraft = false
    }
    @discardableResult public func applyChoice() -> Bool {
        let manual = mode == .manualHTTP
        let parsedPort: Int? = manual && !port.isEmpty && port.utf8.allSatisfy({ (48...57).contains($0) }) ? Int(port) : nil
        let configuration = NetworkConfiguration(revision: revision, mode: mode,
            host: manual ? host : nil, port: parsedPort)
        guard (!manual || port.utf8.count <= 5), configuration.validate() == .syntheticValid,
              mode != .system || !unsupportedProxy else {
            choice = nil; invalidDraft = true; return false
        }
        choice = NativeNetworkChoice(mode: mode, host: manual ? host : nil, port: parsedPort)
        invalidDraft = false
        return true
    }
    public func refresh() {
        guard pending == nil else { return }
        let token = RequestCleanup()
        pending = token; isRefreshing = true
        let capturedRevision = revision
        let request = provider.begin { [weak self, weak token] observation in
            guard let self, let token, self.pending === token, self.revision == capturedRevision else { return }
            // Clear authority before cancellation, which may itself call a provider callback.
            self.pending = nil; self.isRefreshing = false
            self.snapshot = NativeNetworkSettingsSnapshot(observation: observation,
                provenance: self.provenance, revision: capturedRevision)
            self.choice = nil; self.invalidDraft = false
            token.cancel()
        }
        if pending === token { token.request = request } else { request.cancel() }
    }
    public func cancelRefresh() {
        let previous = pending
        pending = nil; isRefreshing = false
        previous?.cancel()
    }
    private var unsupportedProxy: Bool {
        guard let proxy = snapshot?.observation.proxy else { return false }
        return [.pacUnsupported, .discoveryUnsupported, .socksUnsupported, .invalid].contains(proxy)
    }
    public var text: NativeNetworkSettingsText {
        let path: String
        switch snapshot?.observation.path ?? .unknown {
        case .unknown: path = "Path unknown"
        case .offline: path = "Path offline"
        case .available: path = "Path available; Internet and service reachability are unverified"
        case .constrained: path = "Path constrained"
        case .expensive: path = "Path expensive"
        }
        let proxy: String
        switch snapshot?.observation.proxy ?? .unknown {
        case .unknown: proxy = "Proxy unknown"
        case .noConfiguredProxy: proxy = "No configured proxy reported; destination routing is unverified"
        case .httpConfigured: proxy = "HTTP proxy configured"
        case .httpsConfigured: proxy = "HTTPS proxy configured"
        case .httpAndHTTPSConfigured: proxy = "HTTP and HTTPS proxies configured"
        case .pacUnsupported: proxy = "Automatic proxy configuration (PAC) unsupported"
        case .discoveryUnsupported: proxy = "Automatic proxy discovery unsupported"
        case .socksUnsupported: proxy = "SOCKS proxy unsupported"
        case .invalid: proxy = "Proxy configuration unsupported or invalid"
        }
        let guidance: String?
        if unsupportedProxy {
            guidance = "Review Network settings: this system proxy configuration is unsupported. System choice requires a fresh supported refresh."
        } else if invalidDraft {
            guidance = "Enter a valid proxy host and a port from 1 to 65535 in Network settings."
        } else { guidance = nil }
        return NativeNetworkSettingsText(
            status: isRefreshing ? "Refreshing descriptive network information…" : choice == nil ? "Network choice not applied" : "Choice retained for this app session",
            path: path, proxy: proxy,
            provenance: provenance == .testDouble ? "Test double" : "Native system observation",
            freshness: snapshot == nil ? "Not refreshed" : "Last explicit refresh; may have changed",
            limitation: "No network transport connected yet. Choices apply only to future in-app networking and are retained for this app session. Path information does not establish destination reachability.",
            guidance: guidance)
    }
}

// Controller state accesses this holder only on the main actor. Its deinitialiser
// also covers controller release with a pending injected or native request.
private final class RequestCleanup: @unchecked Sendable {
    var request: (any NativeNetworkObservationRequest)?
    @MainActor func cancel() {
        let previous = request; request = nil
        previous?.cancel()
    }
    deinit {
        if let request {
            let delivery = CancellationDelivery(request)
            DispatchQueue.main.async { delivery.request.cancel() }
        }
    }
}
private final class CancellationDelivery: @unchecked Sendable {
    let request: any NativeNetworkObservationRequest
    init(_ request: any NativeNetworkObservationRequest) { self.request = request }
}

@MainActor private final class NativeObservationProvider: NativeNetworkObservationProvider {
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        let worker = NativeObservationWorker { observation in
            DispatchQueue.main.async { completion(observation) }
        }
        let request = NativeObservationRequest(worker: worker)
        worker.start()
        return request
    }
}
@MainActor private final class NativeObservationRequest: NativeNetworkObservationRequest {
    private let worker: NativeObservationWorker
    init(worker: NativeObservationWorker) { self.worker = worker }
    func cancel() { worker.cancel() }
    deinit { worker.cancel() }
}

// All mutable fields belong to queue; raw CF values stay in the separate copy
// closure. unchecked Sendable describes this private queue confinement only.
private final class NativeObservationWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "im.patched.network-observation")
    private var monitor: NWPathMonitor?
    private var timeout: DispatchSourceTimer?
    private var completion: (@Sendable (NativeNetworkObservation) -> Void)?
    private var path: NativeNetworkPath?
    private var proxy: NativeNetworkProxy?
    private var finished = false
    init(completion: @escaping @Sendable (NativeNetworkObservation) -> Void) { self.completion = completion }
    func start() {
        queue.async { [self] in
            guard !finished else { return }
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                // Handler executes on the supplied serial queue.
                guard !self.finished, self.path == nil else { return }
                if path.status == .unsatisfied { self.path = .offline }
                else if path.status != .satisfied { self.path = .unknown }
                else if path.isConstrained { self.path = .constrained }
                else if path.isExpensive { self.path = .expensive }
                else { self.path = .available }
                self.monitor?.cancel(); self.monitor = nil
                self.finishIfComplete()
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timeout = timer
            timer.schedule(deadline: .now() + .seconds(2))
            timer.setEventHandler { [weak self] in self?.finish() }
            timer.resume()
            monitor.start(queue: queue)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                // The OS copy cannot be preempted. Only the finite result leaves
                // this closure; timeout/cancellation can settle without waiting.
                let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
                let proxy = NativeNetworkProxySnapshot.classify(settings)
                self?.receive(proxy)
            }
        }
    }
    private func receive(_ value: NativeNetworkProxy) {
        queue.async { [self] in
            guard !finished else { return }
            proxy = value; finishIfComplete()
        }
    }
    private func finishIfComplete() { if path != nil && proxy != nil { finish() } }
    private func finish() {
        guard !finished else { return }
        finished = true
        let callback = completion; completion = nil
        monitor?.cancel(); monitor = nil
        timeout?.cancel(); timeout = nil
        callback?(NativeNetworkObservation(path: path ?? .unknown, proxy: proxy ?? .unknown))
    }
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true; completion = nil
            monitor?.cancel(); monitor = nil
            timeout?.cancel(); timeout = nil
        }
    }
}
