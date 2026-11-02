import Combine
import Foundation
import PatchedNetworking

public enum NativeNetworkProbeConfiguration: Equatable, Sendable {
    case unconfigured, invalid, controlledLocal
}
public enum NativeNetworkProbeState: Equatable, Sendable {
    case idle, running, finished(NativeConnectionProbeOutcome), stale
}

/// One retained presentation owner for the explicitly selected development route.
/// No response body, arbitrary input, header, error or endpoint enters presentation.
@MainActor public final class NativeNetworkProbeController: ObservableObject {
    public let settings: NativeNetworkSettingsController
    public let configuration: NativeNetworkProbeConfiguration
    @Published public private(set) var state: NativeNetworkProbeState = .idle
    private let endpoint: URL?
    private let probe: NativeNetworkConnectionProbe
    private var subscriptions: Set<AnyCancellable> = []
    private var active: UUID?
    private var pendingPresentation: NativeNetworkProbeState?
    private var inFlightPresentation: NativeNetworkProbeState?
    private var publishing = false
    private var publishedRevision: UInt64
    private var publishedChoice: NativeNetworkChoice?
    private var publishedSnapshot: NativeNetworkSettingsSnapshot?
    private var publishedRefreshing: Bool

    public init(settings: NativeNetworkSettingsController, rawProbeEndpoint: String? = nil) {
        self.settings = settings
        let resolvedEndpoint = rawProbeEndpoint.flatMap(Self.validatedEndpoint)
        endpoint = resolvedEndpoint
        configuration = rawProbeEndpoint == nil ? .unconfigured : resolvedEndpoint == nil ? .invalid : .controlledLocal
        probe = NativeNetworkConnectionProbe(settings: settings)
        publishedRevision = settings.revision; publishedChoice = settings.choice
        publishedSnapshot = settings.snapshot; publishedRefreshing = settings.isRefreshing
        settings.$revision.dropFirst().sink { [weak self] value in
            guard let self else { return }; self.publishedRevision = value; self.settingsChanged()
        }.store(in: &subscriptions)
        settings.$choice.dropFirst().sink { [weak self] value in
            guard let self else { return }; self.publishedChoice = value; self.settingsChanged()
        }.store(in: &subscriptions)
        settings.$snapshot.dropFirst().sink { [weak self] value in
            guard let self else { return }; self.publishedSnapshot = value; self.settingsChanged()
        }.store(in: &subscriptions)
        settings.$isRefreshing.dropFirst().sink { [weak self] value in
            guard let self else { return }; self.publishedRefreshing = value; self.settingsChanged()
        }.store(in: &subscriptions)
    }
    public var isRunning: Bool { active != nil }
    public var showsDevelopmentControls: Bool { configuration != .unconfigured }
    public var canTest: Bool { configuration == .controlledLocal && !isRunning }
    public var statusText: String {
        switch state {
        case .idle:
            return configuration == .invalid ? "Controlled local configuration refused." : "Controlled local probe has not run."
        case .running: return "Checking the controlled local route…"
        case .stale: return "Previous controlled local result is stale. Review Network settings before testing again."
        case .finished(.response(let status, let bytes)):
            return "Controlled local response: HTTP \(status), \(bytes) bytes. This does not establish Internet or service reachability."
        case .finished(.refused(let reason)):
            switch reason {
            case .notApplied: return "Apply a Network choice and finish refreshing before testing the controlled local route."
            case .unsupportedEndpoint: return "Controlled local configuration refused."
            case .unsupportedProxy: return "Controlled local proxy unsupported. Review Network settings."
            case .offline: return "Last network observation was offline. Review Network settings; service reachability is unverified."
            case .busy: return "A controlled local check is already running."
            case .cancelled: return "Controlled local check cancelled."
            case .changedSettings: return "Network settings changed. Test the controlled local route again explicitly."
            case .authenticationRequired: return "Controlled local route requires authentication, which this probe does not support. Review Network settings."
            case .transportFailed: return "Controlled local check failed. Review Network settings. No fallback was attempted."
            case .responseTooLarge: return "Controlled local response exceeded the supported bound. Review Network settings."
            }
        }
    }
    public func test() {
        // A second gesture never replaces pending authority or hides Cancel.
        guard active == nil else { return }
        guard let endpoint, configuration == .controlledLocal else {
            publish(.finished(.refused(.unsupportedEndpoint))); return
        }
        guard publicationSettled, let choice = settings.choice, !settings.isRefreshing else {
            publish(.finished(.refused(.notApplied))); return
        }
        guard settings.snapshot?.observation.path != .offline else {
            publish(.finished(.refused(.offline))); return
        }
        if choice.mode == .manualHTTP {
            guard choice.host == "127.0.0.1", let port = choice.port, (1...65535).contains(port) else {
                publish(.finished(.refused(.unsupportedProxy))); return
            }
            guard #available(macOS 14.0, *) else {
                publish(.finished(.refused(.unsupportedProxy))); return
            }
        }
        let id = UUID(); active = id
        publish(.running)
        // A completion subscriber can restart while publication is draining.
        // Let its queued running notification finish before admitting transport,
        // so synchronous Cancel or settings edits can still revoke this gesture.
        Task { @MainActor [weak self, endpoint, choice, id] in
            guard let self, self.active == id else { return }
            guard self.publicationSettled, self.settings.choice == choice, !self.settings.isRefreshing else {
                self.receive(.refused(.changedSettings), id: id); return
            }
            self.probe.start(url: endpoint) { [weak self] outcome in
                self?.receive(outcome, id: id)
            }
        }
    }
    public func cancel() {
        guard active != nil else { return }
        active = nil
        probe.cancel()
        // Revocation precedes publication, including reentrant Test gestures.
        if active == nil { publish(.finished(.refused(.cancelled))) }
    }
    private func receive(_ outcome: NativeConnectionProbeOutcome, id: UUID) {
        guard active == id else { return }
        active = nil
        publish(.finished(outcome))
    }
    private var publicationSettled: Bool {
        settings.revision == publishedRevision && settings.choice == publishedChoice &&
        settings.snapshot == publishedSnapshot && settings.isRefreshing == publishedRefreshing
    }
    private func settingsChanged() {
        if active != nil {
            active = nil; probe.cancel()
            publish(.finished(.refused(.changedSettings)))
        } else {
            // Published subscribers see the outgoing value before the getter
            // changes. Invalidate that response even while state is still running.
            switch inFlightPresentation ?? state {
            case .finished(.response), .stale: publish(.stale)
            default: break
            }
        }
    }
    private func publish(_ value: NativeNetworkProbeState) {
        // Drain reentrant publication after willSet has completed. A subscriber's
        // Cancel/Test must not be overwritten by the outer Published assignment.
        pendingPresentation = value
        guard !publishing else { return }
        publishing = true
        while let next = pendingPresentation {
            pendingPresentation = nil; inFlightPresentation = next
            state = next
            inFlightPresentation = nil
        }
        publishing = false
    }
    private static func validatedEndpoint(_ raw: String) -> URL? {
        let bytes = Array(raw.utf8.prefix(129))
        guard bytes.count <= 128, bytes.allSatisfy({ $0 < 128 }) else { return nil }
        let suffix = Array("/probe".utf8)
        for prefix in ["http://127.0.0.1:", "http://[::1]:"] {
            let prefixBytes = Array(prefix.utf8)
            guard bytes.starts(with: prefixBytes), bytes.suffix(suffix.count).elementsEqual(suffix) else { continue }
            let port = bytes.dropFirst(prefixBytes.count).dropLast(suffix.count)
            guard (1...5).contains(port.count), port.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(String(decoding: port, as: UTF8.self)), (1...65535).contains(number),
                  let endpoint = URL(string: raw), Array(endpoint.absoluteString.utf8) == bytes else { return nil }
            return endpoint
        }
        return nil
    }
}
