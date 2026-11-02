import Foundation
@_spi(Testing) import PatchedNetworking

@MainActor func registerSecretChecks() {
    for secret in ["password=fixture-secret", "Bearer fixture-secret", "user:secret@proxy", "https://user:secret@proxy.example/path", "secret\nAuthorization: token", "秘密"] {
        check("secret-shaped host never reaches outputs or effects \(secret.debugDescription)") {
            let config = configuration(.manualHTTP, host: secret, port: 8080, reference: "opaque_ref")
            let result = try evaluate(config, admission())
            try expect(result == .refused(.invalidConfiguration), "secret host did not refuse")
            let descriptions = [String(describing: result), String(reflecting: result)]
            try expect(descriptions.allSatisfy { !$0.contains(secret) && !$0.contains("fixture-secret") && !$0.contains("opaque_ref") }, "output echoed secret")
        }
        check("secret-shaped credential reference refuses without lookup \(secret.debugDescription)") {
            try expect(configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: secret).validate() == .refused(.invalidConfiguration), "raw secret reference accepted")
        }
    }
    check("valid opaque credential reference absent from positive model") {
        let config = configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: "opaque_never_echo")
        let result = try evaluate(config, admission(route: .manualProxy(host: "proxy.example", port: 8080, credentialReference: "opaque_never_echo")))
        guard case .syntheticPermitted = result else { throw CheckFailure(description: "positive credential model missing") }
        let text = String(reflecting: result)
        try expect(!text.contains("opaque_never_echo") && !text.contains("proxy.example"), "positive model echoes input")
    }
    check("all ordinary adapters refuse without observations") {
        let adapters = RefusingNetworkAdapters()
        try expect(adapters.load() == nil, "store returned configuration")
        try expect(adapters.resolve(configuration()) == .unavailable, "resolver returned a route")
        try expect(!adapters.available("opaque"), "credentials became available")
        try expect(adapters.current() == .unknown, "path became known")
    }
    check("every finite refusal carries no raw error or secret payload") {
        for reason in NetworkRefusal.allCases {
            let result = NetworkDecision.refused(reason)
            try expect(String(reflecting: result).count < 160, "unbounded refusal")
            try expect(NetworkPolicy().dispatch(result) == .unavailable, "refusal dispatched")
        }
    }
}
