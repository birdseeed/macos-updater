@_spi(Testing) import PatchedNetworking

@MainActor func registerPolicyChecks() {
    for purpose in NetworkPurpose.allCases {
        check("positive exact synthetic purpose \(purpose.rawValue)") { try permitted(configuration(), admission(purpose)) }
    }
    for route in [NetworkRoute.systemDirect, .systemProxy] {
        check("positive system selection \(route)") { try permitted(configuration(), admission(route: route)) }
    }
    check("positive explicit direct selection") { try permitted(configuration(.direct), admission(route: .direct)) }
    check("positive manual HTTP selection and opaque reference") {
        try permitted(configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: "opaque_ref_7"),
                      admission(route: .manualProxy(host: "proxy.example", port: 8080, credentialReference: "opaque_ref_7")))
    }
    check("positive manual without credentials") {
        try permitted(configuration(.manualHTTP, host: "192.0.2.1", port: 1),
                      admission(route: .manualProxy(host: "192.0.2.1", port: 1, credentialReference: nil)))
    }
    for host in ["proxy", "proxy.example", "PROXY.Example", "a-b.example", "192.0.2.1", "0.0.0.0", "255.255.255.255",
                 "[::1]", "[::]", "[2001:db8::1]", "[2001:db8:0:0:0:0:0:1]",
                 String(repeating: "a", count: 63) + ".example",
                 String(repeating: "a", count: 63) + "." + String(repeating: "b", count: 63) + "." + String(repeating: "c", count: 63) + "." + String(repeating: "d", count: 61)] {
        check("configuration accepts conservative host \(host)") {
            try expect(configuration(.manualHTTP, host: host, port: 65535).validate() == .syntheticValid, "valid host refused")
        }
    }
    check("system is default configuration mode") {
        try expect(NetworkConfiguration().mode == .system, "default mode changed")
    }
    for mode in [NetworkMode.system, .direct] {
        check("valid \(mode.rawValue) configuration") { try expect(configuration(mode).validate() == .syntheticValid, "valid configuration refused") }
    }
    check("limited metadata is distinguishable from transfer") {
        var input = admission(); input.path = .limited
        try permitted(configuration(), input)
    }
    check("explicit limited artifact exact scoped override") {
        var input = admission(.artifact); input.path = .limited; input.transfer = .explicit; input.limitedOverride = override()
        try permitted(configuration(), input)
    }
    check("valid time zero and final exclusive tick") {
        var input = admission(); input.now = 0; input.expires = 1
        try permitted(configuration(), input)
        input.now = 199; input.expires = 200
        try permitted(configuration(), input)
    }
    check("positive distinct principal and maximum revision bind exactly") {
        let config = NetworkConfiguration(principal: .fixtureOther, revision: UInt64.max)
        var input = admission(); input.principal = .fixtureOther; input.revision = UInt64.max
        try permitted(config, input)
    }
    check("positive exact maximum time and maximum lifetime") {
        var input = admission(); input.now = 9_007_199_254_740_990; input.expires = 9_007_199_254_740_991
        try permitted(configuration(), input)
        input.now = 100; input.expires = 400
        try permitted(configuration(), input)
    }
    check("positive permitted output cannot enable ordinary policy") {
        let decision = try evaluate(configuration(), admission())
        try expect(NetworkPolicy().dispatch(decision) == .unavailable, "ordinary dispatch became available")
    }
}
