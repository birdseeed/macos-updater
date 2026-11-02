@_spi(Testing) import PatchedNetworking

@MainActor func denial(_ name: String, reason: NetworkRefusal, purpose: NetworkPurpose = .catalogue,
                       mutate: @escaping (inout NetworkAdmission) -> Void) {
    check(name) { var input = admission(purpose); mutate(&input); try refused(configuration(), input, reason) }
}
@MainActor func registerDenialChecks() {
    // PAT-2666 Unicode binding amendment: these ASCII positives must remain admissible.
    check("positive byte-exact manual host ASCII K") {
        let config = configuration(.manualHTTP, host: "K.example", port: 8080)
        try expect(config.validate() == .syntheticValid, "ASCII host configuration refused")
        try permitted(config, admission(route: .manualProxy(host: "K.example", port: 8080, credentialReference: nil)))
    }
    check("Unicode Kelvin manual host binding refuses routeMismatch") {
        let ascii = "K.example", kelvin = "\u{212A}.example"
        try expect(ascii == kelvin && !ascii.utf8.elementsEqual(kelvin.utf8), "host fixture must be canonically equal with different UTF8")
        let config = configuration(.manualHTTP, host: ascii, port: 8080)
        try expect(config.validate() == .syntheticValid, "ASCII host configuration refused")
        try refused(config, admission(route: .manualProxy(host: kelvin, port: 8080, credentialReference: nil)), .routeMismatch)
    }
    check("positive byte-exact manual credential reference ASCII K") {
        let config = configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: "K")
        try expect(config.validate() == .syntheticValid, "ASCII reference configuration refused")
        try permitted(config, admission(route: .manualProxy(host: "proxy.example", port: 8080, credentialReference: "K")))
    }
    check("Unicode Kelvin manual credential reference binding refuses routeMismatch") {
        let ascii = "K", kelvin = "\u{212A}"
        try expect(ascii == kelvin && !ascii.utf8.elementsEqual(kelvin.utf8), "reference fixture must be canonically equal with different UTF8")
        let config = configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: ascii)
        try expect(config.validate() == .syntheticValid, "ASCII reference configuration refused")
        try refused(config, admission(route: .manualProxy(host: "proxy.example", port: 8080, credentialReference: kelvin)), .routeMismatch)
    }
    check("positive byte-exact limited override app ASCII K") {
        var input = admission(.artifact); input.path = .limited; input.transfer = .explicit
        input.artifact?.app = "K"
        var value = override(); value.artifact.app = "K"; input.limitedOverride = value
        try permitted(configuration(), input)
    }
    check("Unicode Kelvin limited override app binding refuses limitedData") {
        let ascii = "K", kelvin = "\u{212A}"
        try expect(ascii == kelvin && !ascii.utf8.elementsEqual(kelvin.utf8), "app fixture must be canonically equal with different UTF8")
        var input = admission(.artifact); input.path = .limited; input.transfer = .explicit
        input.artifact?.app = ascii
        var value = override(); value.artifact.app = kelvin; input.limitedOverride = value
        try refused(configuration(), input, .limitedData)
    }
    check("positive byte-exact limited override version ASCII K") {
        var input = admission(.artifact); input.path = .limited; input.transfer = .explicit
        input.artifact?.version = "K"
        var value = override(); value.artifact.version = "K"; input.limitedOverride = value
        try permitted(configuration(), input)
    }
    check("Unicode Kelvin limited override version binding refuses limitedData") {
        let ascii = "K", kelvin = "\u{212A}"
        try expect(ascii == kelvin && !ascii.utf8.elementsEqual(kelvin.utf8), "version fixture must be canonically equal with different UTF8")
        var input = admission(.artifact); input.path = .limited; input.transfer = .explicit
        input.artifact?.version = ascii
        var value = override(); value.artifact.version = kelvin; input.limitedOverride = value
        try refused(configuration(), input, .limitedData)
    }
    // End PAT-2666 Unicode binding amendment.
    check("ordinary policy has no synthetic allowlist") {
        try expect(NetworkPolicy().admit(configuration: configuration(), observation: admission()) == .refused(.unavailable), "default policy admitted")
    }
    check("missing observations refuse") {
        let input = NetworkAdmission(principal: .fixtureOwner, revision: 7, purpose: .catalogue, destination: .catalogueFixture, method: .get)
        // Missing route is checked before time/path. No platform lookup may fill it.
        try refused(configuration(), input, .unavailable)
    }
    check("missing immutable fixture allowlist refuses") {
        try expect(NetworkPolicy(syntheticEndpoints: []).admit(configuration: configuration(), observation: admission()) == .refused(.unavailable), "empty allowlist admitted")
    }
    for host in ["", " ", " proxy.example", "proxy.example ", "proxy\t.example", "proxy\n.example", "proxy\u{0}.example",
                 "https://proxy.example", "user:password@proxy.example", "proxy.example:8080", "proxy.example/path", "proxy?x", "proxy#x",
                 "--proxy", "-x", "a_.example", "a..example", ".example", "example.", "-a.example", "a-.example",
                 "pröxy.example", "ｐroxy.example", "proxy%2eexample", "127.1", "123", "1.2.3", "1.2.3.04", "0127.0.0.1", "256.0.0.1", "1.2.3.4.5",
                 "2001:db8::1", "[::1]:80", "[fe80::1%en0]", "[::ffff:192.0.2.1]", "[:::1]", "[1::2::3]", "[1:2:3]",
                 "[1:2:3:4:5:6:7:8:9]", "[12345::1]", "[gggg::1]", "[1:2:3:4:5:6:7:8::]",
                 String(repeating: "a", count: 64) + ".example", String(repeating: "a", count: 254)] {
        check("reject hostile or unsupported manual host \(host.debugDescription)") {
            let config = configuration(.manualHTTP, host: host, port: 8080)
            try expect(config.validate() == .refused(.invalidConfiguration), "unsafe host accepted")
            try refused(config, admission(route: .manualProxy(host: host, port: 8080, credentialReference: nil)), .invalidConfiguration)
        }
    }
    for port in [Int.min, -1, 0, 65536, Int.max] {
        check("manual port bound \(port)") { try expect(configuration(.manualHTTP, host: "proxy.example", port: port).validate() == .refused(.invalidConfiguration), "invalid port accepted") }
    }
    for config in [configuration(.manualHTTP), configuration(.manualHTTP, host: "proxy.example"), configuration(.manualHTTP, port: 8080),
                   configuration(.system, host: "proxy.example", port: 8080), configuration(.direct, reference: "opaque"),
                   configuration(.system, revision: 0), configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: ""),
                   configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: String(repeating: "x", count: 65))] {
        check("invalid configuration shape \(config.mode.rawValue) \(config.revision) \(String(describing: config.port))") {
            try expect(config.validate() == .refused(.invalidConfiguration), "configuration shape admitted")
        }
    }
    denial("principal changed", reason: .bindingMismatch) { $0.principal = .fixtureOther }
    denial("configuration revision stale", reason: .bindingMismatch) { $0.revision = 6 }
    denial("configuration revision future", reason: .bindingMismatch) { $0.revision = 8 }
    denial("zero observed revision", reason: .bindingMismatch) { $0.revision = 0 }
    denial("overflow-shaped observed revision", reason: .bindingMismatch) { $0.revision = UInt64.max }
    denial("unknown clock", reason: .invalidTime) { $0.now = nil }
    denial("negative clock", reason: .invalidTime) { $0.now = -1 }
    denial("negative expiry", reason: .invalidTime) { $0.expires = -1 }
    denial("clock outside exact bound", reason: .invalidTime) { $0.now = 9_007_199_254_740_992; $0.expires = 9_007_199_254_740_993 }
    denial("expiry overflow", reason: .invalidTime) { $0.expires = Int64.max }
    denial("clock overflow", reason: .invalidTime) { $0.now = Int64.max }
    denial("exclusive expiry", reason: .expired) { $0.now = 200 }
    denial("stale admission", reason: .expired) { $0.now = 201 }
    denial("unbounded admission duration", reason: .invalidTime) { $0.expires = 401 }
    denial("unapproved destination", reason: .destinationMismatch) { $0.destination = .unapprovedFixture }
    denial("destination purpose mismatch", reason: .destinationMismatch) { $0.destination = .supportFixture }
    denial("wrong GET method", reason: .methodMismatch) { $0.method = .post }
    denial("wrong POST method", reason: .methodMismatch, purpose: .manualSupport) { $0.method = .get }
    denial("unsupported method", reason: .methodMismatch) { $0.method = .put }
    for purpose in [NetworkPurpose.catalogue, .artifact] {
        denial("GET has body \(purpose.rawValue)", reason: .bodyMismatch, purpose: purpose) { $0.bodyDigest = digestA }
    }
    denial("GET frozen body binding forbidden", reason: .bodyMismatch) { $0.frozenBodyDigest = digestA }
    for purpose in [NetworkPurpose.manualSupport, .failureReport] {
        for body in [nil, "", String(repeating: "a", count: 63), String(repeating: "a", count: 65), String(repeating: "A", count: 64), String(repeating: "g", count: 64), " " + String(repeating: "a", count: 63)] as [String?] {
            denial("POST digest grammar \(purpose.rawValue) \(String(describing: body))", reason: .bodyMismatch, purpose: purpose) { $0.bodyDigest = body }
        }
        denial("POST exact frozen digest mismatch \(purpose.rawValue)", reason: .bodyMismatch, purpose: purpose) { $0.bodyDigest = digestB }
        denial("POST frozen digest missing \(purpose.rawValue)", reason: .bodyMismatch, purpose: purpose) { $0.frozenBodyDigest = nil }
        denial("missing consent \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consent = nil }
        denial("missing consent generation \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consentGeneration = nil }
        denial("zero consent generation \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consentGeneration = 0; $0.consent?.generation = 0 }
        denial("consent optout \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consent?.allowed = false }
        denial("stale consent generation \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consent?.generation = 2 }
        denial("consent principal mismatch \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consent?.principal = .fixtureOther }
        denial("consent purpose mismatch \(purpose.rawValue)", reason: .consentRequired, purpose: purpose) { $0.consent?.purpose = .catalogue }
    }
    for (route, reason) in [(NetworkRoute.unavailable, NetworkRefusal.unavailable), (.pacFailure, .pacFailure),
                            (.authenticationNeeded, .authenticationNeeded), (.unsupported, .unsupported), (.direct, .routeMismatch)] {
        denial("system never bypasses \(route)", reason: reason) { $0.route = route }
    }
    check("explicit direct rejects system direct") { try refused(configuration(.direct), admission(), .routeMismatch) }
    for route in [NetworkRoute.direct, .systemDirect, .systemProxy,
                  .manualProxy(host: "other.example", port: 8080, credentialReference: "opaque"),
                  .manualProxy(host: "proxy.example", port: 80, credentialReference: "opaque"),
                  .manualProxy(host: "proxy.example", port: 8080, credentialReference: "changed")] {
        check("manual proxy requires exact selected route \(route)") {
            try refused(configuration(.manualHTTP, host: "proxy.example", port: 8080, reference: "opaque"), admission(route: route), .routeMismatch)
        }
    }
    denial("offline defers new admission", reason: .offline) { $0.path = .offline }
    denial("unknown path refuses metadata", reason: .unknownPath) { $0.path = .unknown }
    denial("limited automatic artifact", reason: .limitedData, purpose: .artifact) { $0.path = .limited }
    denial("limited explicit artifact without override", reason: .limitedData, purpose: .artifact) { $0.path = .limited; $0.transfer = .explicit }
    denial("limited automatic ignores override", reason: .limitedData, purpose: .artifact) { $0.path = .limited; $0.limitedOverride = override() }
    for purpose in [NetworkPurpose.manualSupport, .failureReport] {
        denial("limited submission is not metadata \(purpose.rawValue)", reason: .limitedData, purpose: purpose) { $0.path = .limited }
    }
    let overrideMutations: [(String, (inout NetworkLimitedOverride) -> Void)] = [
        ("principal", { $0.principal = .fixtureOther }), ("revision", { $0.revision = 6 }),
        ("purpose", { $0.purpose = .catalogue }), ("destination", { $0.destination = .catalogueFixture }),
        ("app", { $0.artifact.app = "other-app" }), ("version", { $0.artifact.version = "2" }),
        ("digest", { $0.artifact.digest = digestB }), ("expired", { $0.expires = 100 }),
        ("negative expiry", { $0.expires = -1 }), ("overflow expiry", { $0.expires = Int64.max }),
        ("long lifetime", { $0.expires = 401 })]
    for (name, mutate) in overrideMutations {
        denial("limited override mismatch \(name)", reason: .limitedData, purpose: .artifact) {
            $0.path = .limited; $0.transfer = .explicit
            var value = override(); mutate(&value); $0.limitedOverride = value
        }
    }
    denial("limited override missing artifact", reason: .limitedData, purpose: .artifact) {
        $0.path = .limited; $0.transfer = .explicit; $0.limitedOverride = override(); $0.artifact = nil
    }
    for item in [NetworkArtifact(app: "", version: "1", digest: digestA), NetworkArtifact(app: "fixture-app", version: "", digest: digestA), NetworkArtifact(app: "fixture-app", version: "1", digest: "bad")] {
        denial("limited override requires valid artifact identity \(item)", reason: .limitedData, purpose: .artifact) {
            $0.path = .limited; $0.transfer = .explicit; $0.artifact = item
            var value = override(); value.artifact = item; $0.limitedOverride = value
        }
    }
    check("redirect destination is a new refusing admission") {
        try permitted()
        var redirected = admission(); redirected.destination = .unapprovedFixture
        try refused(configuration(), redirected, .destinationMismatch)
    }
    check("configuration replacement invalidates old admission") {
        try permitted()
        try refused(configuration(revision: 8), admission(), .bindingMismatch)
    }
    check("late report callback after optout is a new refusing admission") {
        try permitted(configuration(), admission(.failureReport))
        var retried = admission(.failureReport); retried.consent?.allowed = false
        try refused(configuration(), retried, .consentRequired)
    }
}
