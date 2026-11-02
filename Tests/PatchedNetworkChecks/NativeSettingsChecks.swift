import Foundation
@_spi(Testing) import PatchedNetworking

@MainActor private final class SettingsRequest: NativeNetworkObservationRequest {
    var cancellations = 0
    func cancel() { cancellations += 1 }
}
@MainActor private final class SettingsProvider: NativeNetworkObservationProvider {
    var completions: [@MainActor (NativeNetworkObservation) -> Void] = []
    var requests: [SettingsRequest] = []
    var immediate: NativeNetworkObservation?
    var onBegin: (() -> Void)?
    func begin(completion: @escaping @MainActor (NativeNetworkObservation) -> Void) -> any NativeNetworkObservationRequest {
        let request = SettingsRequest(); requests.append(request); completions.append(completion)
        onBegin?()
        if let immediate { completion(immediate) }
        return request
    }
    func deliver(_ index: Int, path: NativeNetworkPath = .available, proxy: NativeNetworkProxy = .noConfiguredProxy) {
        completions[index](NativeNetworkObservation(path: path, proxy: proxy))
    }
}
@MainActor func registerNativeSettingsChecks() {
    // Literal CFNetwork dictionary fixtures; no platform API is called.
    let proxyCases: [(String, [String: Any]?, NativeNetworkProxy)] = [
        ("missing dictionary", nil, .unknown),
        ("empty dictionary", [:], .noConfiguredProxy),
        ("all disabled", ["HTTPEnable": 0, "HTTPSEnable": 0, "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0, "SOCKSEnable": 0], .noConfiguredProxy),
        ("HTTP enabled", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 8080], .httpConfigured),
        ("HTTPS enabled", ["HTTPSEnable": 1, "HTTPSProxy": "secure.example", "HTTPSPort": 443], .httpsConfigured),
        ("HTTP and HTTPS", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 8080, "HTTPSEnable": 1, "HTTPSProxy": "secure.example", "HTTPSPort": 443], .httpAndHTTPSConfigured),
        ("CF numeric flags", ["HTTPEnable": NSNumber(value: 1), "HTTPProxy": "proxy.example", "HTTPPort": NSNumber(value: 8080)], .httpConfigured),
        ("disabled irrelevant payload", ["HTTPEnable": 0, "HTTPProxy": ["host": "secret"], "HTTPPort": "password"], .noConfiguredProxy),
        ("enabled PAC", ["ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://user:password@pac.example/private"], .pacUnsupported),
        ("PAC missing URL still unsupported", ["ProxyAutoConfigEnable": 1], .pacUnsupported),
        ("PAC wins configured HTTP", ["ProxyAutoConfigEnable": 1, "HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 8080], .pacUnsupported),
        ("enabled discovery", ["ProxyAutoDiscoveryEnable": 1], .discoveryUnsupported),
        ("discovery wins configured HTTP", ["ProxyAutoDiscoveryEnable": 1, "HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 8080], .discoveryUnsupported),
        ("enabled SOCKS", ["SOCKSEnable": 1, "SOCKSProxy": "secret.example", "SOCKSPort": 1080], .socksUnsupported),
        ("SOCKS wins configured HTTP", ["SOCKSEnable": 1, "HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 8080], .socksUnsupported),
        ("scoped dictionary unsupported", ["__SCOPED__": ["en0": ["HTTPEnable": 1, "HTTPProxy": "secret.example", "HTTPPort": 8080]]], .invalid),
        ("malformed scoped dictionary unsupported", ["__SCOPED__": "secret.example"], .invalid),
        ("unknown irrelevant metadata", ["username": "secret-user", "password": "secret-password", "ExceptionsList": ["private.example"]], .noConfiguredProxy),
        ("HTTP missing host", ["HTTPEnable": 1, "HTTPPort": 80], .invalid),
        ("HTTP missing port", ["HTTPEnable": 1, "HTTPProxy": "proxy.example"], .invalid),
        ("HTTP host wrong type", ["HTTPEnable": 1, "HTTPProxy": 7, "HTTPPort": 80], .invalid),
        ("HTTP port string", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": "80"], .invalid),
        ("HTTP port boolean", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": true], .invalid),
        ("HTTP port fractional", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 80.5], .invalid),
        ("HTTP port low", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 0], .invalid),
        ("HTTP port high", ["HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 65536], .invalid),
        ("HTTP host URL secret", ["HTTPEnable": 1, "HTTPProxy": "https://user:password@proxy.example", "HTTPPort": 80], .invalid),
        ("HTTP host injection", ["HTTPEnable": 1, "HTTPProxy": "proxy.example\r\npassword", "HTTPPort": 80], .invalid),
        ("HTTPS invalid host", ["HTTPSEnable": 1, "HTTPSProxy": "bad host", "HTTPSPort": 443], .invalid),
        ("disabled PAC payload inert", ["ProxyAutoConfigEnable": 0, "ProxyAutoConfigURLString": ["secret": "https://secret.example"]], .noConfiguredProxy),
    ]
    for (name, dictionary, expected) in proxyCases {
        check("PAT2666 native parser: \(name)") {
            try expect(NativeNetworkProxySnapshot.classify(dictionary) == expected, "Finite proxy classification differs from independent literal")
        }
    }
    for key in ["HTTPEnable", "HTTPSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable", "SOCKSEnable"] {
        for (name, value) in [("string zero", "0" as Any), ("string one", "1" as Any), ("boolean", true as Any),
                              ("negative", -1 as Any), ("two", 2 as Any), ("fraction", 0.5 as Any),
                              ("array", [1] as Any), ("null", NSNull() as Any)] {
            check("PAT2666 native parser: strict \(key) refuses \(name)") {
                try expect(NativeNetworkProxySnapshot.classify([key: value]) == .invalid, "Proxy flag accepted coercion or non-binary value")
            }
        }
    }
    check("PAT2666 native: construction, display and draft edits do not begin observation") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: SettingsProvider())
        let observed = NativeNetworkSettingsController(provider: provider)
        for mode in [NetworkMode.system, .direct, .manualHTTP] {
            observed.edit(mode: mode, host: "proxy.example", port: "8080"); _ = observed.text
        }
        try expect(provider.requests.isEmpty && observed.snapshot == nil && !observed.isRefreshing, "Idle lifecycle performed observation")
        try expect(controller.choice == nil && controller.text.freshness == "Not refreshed", "Construction invented applied choice/freshness")
    }
    check("PAT2666 native: valid modes and endpoints create a validated choice retained by the app session") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        for mode in [NetworkMode.system, .direct] {
            controller.edit(mode: mode)
            try expect(controller.applyChoice(), "Valid explicit system/direct choice refused")
            try expect(controller.choice == NativeNetworkChoice(mode: mode), "Selected choice not retained")
        }
        for (host, port) in [("proxy.example", "8080"), ("127.0.0.1", "1"), ("[::1]", "65535")] {
            controller.edit(mode: .manualHTTP, host: host, port: port)
            try expect(controller.mode == .manualHTTP && controller.host == host && controller.port == port, "Draft fields not bound")
            try expect(controller.applyChoice(), "Valid manual endpoint refused")
            try expect(controller.choice == NativeNetworkChoice(mode: .manualHTTP, host: host, port: Int(port)), "Validated endpoint mismatch")
        }
        try expect(provider.requests.isEmpty && controller.snapshot == nil, "Applying choice observed system")
    }
    let denied: [(String, String)] = [("", "8080"), ("proxy.example", ""), ("proxy.example", "0"), ("proxy.example", "65536"),
        ("proxy.example", "-1"), ("proxy.example", "8.5"), ("proxy.example", " 80"), ("proxy.example", "80\n"),
        ("user:password@proxy.example", "80"), ("https://proxy.example", "80"), ("bad host", "80"),
        ("a..example", "80"), ("999.0.0.1", "80"), ("[:::1]", "80"), (String(repeating: "x", count: 254), "80")]
    for (index, pair) in denied.enumerated() {
        check("PAT2666 native: invalid manual endpoint \(index) refuses without observation") {
            let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
            controller.edit(mode: .manualHTTP, host: pair.0, port: pair.1)
            try expect(!controller.applyChoice() && controller.choice == nil && provider.requests.isEmpty, "Invalid endpoint admitted or effect started")
            try expect(controller.text.guidance?.isEmpty == false, "Invalid manual choice lacks useful guidance")
            let status = [controller.text.status, controller.text.proxy, controller.text.path, controller.text.guidance ?? ""].joined(separator: " ")
            for raw in ["user:password", "NSError", "invalidConfiguration", "https://proxy.example", "bad host"] {
                try expect(!status.contains(raw), "Invalid status leaks endpoint/credentials/raw error")
            }
        }
    }
    check("PAT2666 native: edit invalidates accepted choice without observing or retaining stale endpoint") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        controller.edit(mode: .manualHTTP, host: "proxy.example", port: "8080")
        try expect(controller.applyChoice(), "Valid setup refused")
        controller.edit(mode: .manualHTTP, host: "bad host", port: "8080")
        try expect(controller.choice == nil && !controller.applyChoice(), "Edit retained valid choice for different draft")
        controller.edit(mode: .system)
        try expect(controller.host.isEmpty && controller.port.isEmpty && controller.applyChoice(), "System switch retained manual secrets/endpoint")
        try expect(provider.requests.isEmpty, "Edit/apply observed system")
    }
    check("PAT2666 native: explicit refresh is singleflight and preserves descriptive fake provenance") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        controller.refresh(); controller.refresh()
        try expect(provider.requests.count == 1 && controller.isRefreshing, "Explicit refresh did not begin exactly one pending request")
        guard provider.requests.count == 1 else { return }
        provider.deliver(0, path: .offline, proxy: .httpConfigured)
        try expect(!controller.isRefreshing && controller.snapshot?.observation == NativeNetworkObservation(path: .offline, proxy: .httpConfigured), "Completion did not publish finite observation")
        try expect(controller.snapshot?.provenance == .testDouble && controller.text.provenance.lowercased().contains("test double"), "Injected data represented as native")
        try expect(provider.requests[0].cancellations == 1, "Completed request was not cancelled")
        provider.deliver(0, path: .available)
        try expect(controller.snapshot?.observation.path == .offline, "Duplicate completion replaced settled snapshot")
        try expect(provider.requests[0].cancellations == 1, "Duplicate completion cancelled settled request twice")
        try expect(controller.snapshot?.revision == controller.revision, "Snapshot revision is not bound")
        try expect(controller.choice == nil, "Observation granted applied choice")
    }
    check("PAT2666 native: cancel and newer refresh fence every stale completion") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        controller.refresh()
        try expect(provider.requests.count == 1, "Initial refresh missing")
        guard provider.requests.count == 1 else { return }
        controller.cancelRefresh(); controller.cancelRefresh()
        try expect(provider.requests[0].cancellations == 1 && !controller.isRefreshing, "Cancel did not release once")
        provider.deliver(0)
        try expect(controller.snapshot == nil, "Cancelled callback published")
        controller.refresh()
        try expect(provider.requests.count == 2, "New explicit refresh missing")
        guard provider.requests.count == 2 else { return }
        provider.deliver(0, path: .offline); provider.deliver(1, path: .constrained)
        try expect(controller.snapshot?.observation.path == .constrained, "Older refresh replaced current observation")
    }
    check("PAT2666 native: editing cancels pending request and revision fences late completion") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        let revision = controller.revision
        controller.refresh()
        try expect(provider.requests.count == 1, "Explicit refresh missing")
        guard provider.requests.count == 1 else { return }
        controller.edit(mode: .direct)
        try expect(controller.revision > revision && !controller.isRefreshing && provider.requests[0].cancellations == 1, "Edit failed to invalidate pending observation")
        provider.deliver(0)
        try expect(controller.snapshot == nil, "Pre-edit callback published")
    }
    check("PAT2666 native: synchronous completion and reentrant refresh cannot leak a request") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        provider.immediate = NativeNetworkObservation(path: .unknown, proxy: .unknown)
        provider.onBegin = { controller.refresh() }
        controller.refresh()
        try expect(provider.requests.count == 1 && controller.snapshot != nil && !controller.isRefreshing, "Synchronous/reentrant completion state broken")
        try expect(provider.requests.first?.cancellations == 1, "Synchronously settled request leaked")
    }
    check("PAT2666 native: settled unsupported snapshot stays descriptive across edits and fresh supported refresh unblocks system choice") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        provider.immediate = NativeNetworkObservation(path: .offline, proxy: .pacUnsupported)
        controller.refresh()
        try expect(controller.snapshot?.observation.proxy == .pacUnsupported, "Unsupported setup observation missing")
        controller.edit(mode: .manualHTTP, host: "proxy.example", port: "8080")
        controller.edit(mode: .system)
        try expect(!controller.applyChoice(), "Draft edit bypassed unsupported system snapshot")
        try expect(controller.snapshot?.observation.proxy == .pacUnsupported && controller.text.freshness.lowercased().contains("may have changed"), "Settled descriptive snapshot lost or falsely fresh")
        provider.immediate = NativeNetworkObservation(path: .unknown, proxy: .noConfiguredProxy)
        controller.refresh()
        try expect(controller.snapshot?.observation.proxy == .noConfiguredProxy && controller.applyChoice(), "Fresh supported observation did not unblock a valid system choice")
        try expect(controller.choice == NativeNetworkChoice(mode: .system), "Fresh system choice mismatch")
    }
    for path in NativeNetworkPath.allCases {
        check("PAT2666 native: finite path \(path.rawValue) is honest and never service readiness") {
            let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
            provider.immediate = NativeNetworkObservation(path: path, proxy: .noConfiguredProxy); controller.refresh()
            try expect(controller.snapshot?.observation.path == path, "Path lost")
            let text = controller.text
            try expect(text.path.lowercased().contains(path == .available ? "available" : path.rawValue), "Finite path not displayed honestly")
            try expect(text.limitation.contains("No network transport connected yet") && text.limitation.contains("future in-app"), "Snapshot implies transport readiness")
            try expect(text.freshness.lowercased().contains("may have changed"), "Snapshot claims current/fresh connectivity")
            for claim in ["Internet reachable", "service reachable", "ready to install", "ready to update"] {
                try expect(!text.path.contains(claim) && !text.status.contains(claim), "Path granted unsupported readiness")
            }
        }
    }
    for proxy in NativeNetworkProxy.allCases {
        check("PAT2666 native: finite proxy \(proxy.rawValue) describes configuration and unsupported systems refuse") {
            let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
            provider.immediate = NativeNetworkObservation(path: .available, proxy: proxy); controller.refresh()
            try expect(controller.snapshot?.observation.proxy == proxy, "Proxy lost")
            if [.pacUnsupported, .discoveryUnsupported, .socksUnsupported, .invalid].contains(proxy) {
                try expect(controller.text.guidance?.contains("Network settings") == true, "Unsupported proxy lacks Network settings guidance")
                controller.edit(mode: .system)
                try expect(!controller.applyChoice(), "Unsupported observed system proxy silently fell back or applied")
            }
            let visible = [controller.text.status, controller.text.proxy, controller.text.path, controller.text.freshness].joined(separator: " ")
            for forbidden in ["proxy.example", "password", "username", "http://", "https://", "NSError", "systemDirect"] {
                try expect(!visible.contains(forbidden), "Status leaked raw or authority-like value")
            }
        }
    }
    // CHECK-MODIFIED PAT-2666: additive UTF-8 retention bounds; original 107 cases unchanged.
    registerNativeSettingsByteBoundChecks()
}

// CHECK-MODIFIED PAT-2666: independent large-single-grapheme retention checks.
// Added after useful candidate source exists; these are not claimed as initial RED.
@MainActor private func registerNativeSettingsByteBoundChecks() {
    check("PAT2666 native: retained host is bounded in UTF-8 bytes for a large single grapheme") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        let cluster = "a" + String(repeating: "\u{0301}", count: 8192)
        try expect(cluster.count == 1 && cluster.utf8.count > 254, "Host fixture is not one oversized grapheme")
        controller.edit(mode: .manualHTTP, host: cluster, port: "8080")
        try expect(controller.host.utf8.count <= 254, "Retained host exceeds the independent 254-byte bound")
        try expect(!controller.applyChoice() && controller.choice == nil, "Oversized combining host admitted")
        try expect(provider.requests.isEmpty && controller.snapshot == nil && !controller.isRefreshing, "Invalid host caused observation")
    }
    check("PAT2666 native: retained port is bounded in UTF-8 bytes for a large single grapheme") {
        let provider = SettingsProvider(), controller = NativeNetworkSettingsController(provider: provider)
        let cluster = "a" + String(repeating: "\u{0301}", count: 8192)
        try expect(cluster.count == 1 && cluster.utf8.count > 6, "Port fixture is not one oversized grapheme")
        controller.edit(mode: .manualHTTP, host: "proxy.example", port: cluster)
        try expect(controller.port.utf8.count <= 6, "Retained port exceeds the independent 6-byte bound")
        try expect(!controller.applyChoice() && controller.choice == nil, "Oversized combining port admitted")
        try expect(provider.requests.isEmpty && controller.snapshot == nil && !controller.isRefreshing, "Invalid port caused observation")
    }
}
