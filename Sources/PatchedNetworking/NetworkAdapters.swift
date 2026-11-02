// No concrete platform adapters. These interfaces exist only for boundary checks.
public protocol NetworkConfigurationStore { func load() -> NetworkConfiguration? }
public protocol SystemProxyResolver { func resolve(_ configuration: NetworkConfiguration) -> NetworkRoute }
public protocol ProxyCredentialProvider { func available(_ reference: String) -> Bool }
public protocol NetworkPathSource { func current() -> NetworkPath }
public protocol NetworkTransport { func dispatch(_ model: NetworkSyntheticModel) -> NetworkDispatchOutcome }
public enum NetworkEffect: String, CaseIterable { case session, dns, pac, credentials, persistence, process, environment, log, diagnostics, callback }
public protocol NetworkEffectSink { func observe(_ effect: NetworkEffect) }
public struct RefusingNetworkAdapters: NetworkConfigurationStore, SystemProxyResolver,
    ProxyCredentialProvider, NetworkPathSource, NetworkTransport, NetworkEffectSink {
    public init() {}
    public func load() -> NetworkConfiguration? { nil }
    public func resolve(_ configuration: NetworkConfiguration) -> NetworkRoute { .unavailable }
    public func available(_ reference: String) -> Bool { false }
    public func current() -> NetworkPath { .unknown }
    public func dispatch(_ model: NetworkSyntheticModel) -> NetworkDispatchOutcome { .unavailable }
    public func observe(_ effect: NetworkEffect) {}
}
// Test seams are supplied explicitly, never discovered from the environment.
public struct NetworkBoundaries {
    public let store: any NetworkConfigurationStore
    public let resolver: any SystemProxyResolver
    public let credentials: any ProxyCredentialProvider
    public let path: any NetworkPathSource
    public let transport: any NetworkTransport
    public let effects: any NetworkEffectSink
    public init(store: any NetworkConfigurationStore = RefusingNetworkAdapters(),
                resolver: any SystemProxyResolver = RefusingNetworkAdapters(),
                credentials: any ProxyCredentialProvider = RefusingNetworkAdapters(),
                path: any NetworkPathSource = RefusingNetworkAdapters(),
                transport: any NetworkTransport = RefusingNetworkAdapters(),
                effects: any NetworkEffectSink = RefusingNetworkAdapters()) {
        self.store = store; self.resolver = resolver; self.credentials = credentials
        self.path = path; self.transport = transport; self.effects = effects
    }
}
