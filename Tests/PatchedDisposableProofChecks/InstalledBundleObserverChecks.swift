import Foundation
import Darwin
@_spi(Testing) import ArtifactInspection

// Direct synthetic pipeline checks: all executables are inert bytes, and every
// observation comes from an injected closure. No ordinary Security collector runs.
private struct ObserverFixture {
    let root: String
    let app: String
    let executable: String
    let plistPath: String
    let appFD: Int32
    let executableFD: Int32
    let pin: TargetPin
    let plist: Data

    func collect(path: String? = nil, appFD: Int32? = nil, executableFD: Int32? = nil,
                 plist: Data? = nil, pin: TargetPin? = nil,
                 collector: (String, TargetPin) throws -> SignatureObservation) throws -> SignatureObservation {
        try InstalledBundleObserverTestAdapter.collect(appPath: path ?? app,
            appDescriptor: appFD ?? self.appFD, executableDescriptor: executableFD ?? self.executableFD,
            infoPlist: plist ?? self.plist, pin: pin ?? self.pin, collector: collector)
    }
    func observation() throws -> SignatureObservation {
        SignatureObservation(appPath: app,
            requirement: try PinnedSignatureRequirement.make(teamID: pin.teamID, bundleID: pin.bundleID),
            validationFlags: PinnedSignatureRequirement.validationFlags,
            validationStatus: 0, signingInformationStatus: 0,
            teamID: pin.teamID, identifier: pin.bundleID,
            startedAt: "2026-10-07T14:35:32Z", finishedAt: "2026-10-07T14:35:33Z")
    }
}

private func observerPlist(_ pin: TargetPin, change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    var fields: [String: Any] = ["CFBundleIdentifier": pin.bundleID,
        "CFBundleShortVersionString": pin.version, "CFBundleExecutable": "firefox", "CFBundlePackageType": "APPL"]
    change(&fields)
    return try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0)
}

private func withObserverFixture(version: String = "157.0", _ body: (ObserverFixture) throws -> Void) throws {
    // CHECK-MODIFIED PAT-2710: Foundation preserves the /var alias on macOS;
    // the parent measured that POSIX realpath supplies the required physical path.
    // Only this private newly created root is removed; all assertions are unchanged.
    guard let physical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
        throw CheckFailure(description: "Observer fixture physical temporary path unavailable")
    }
    let parent = String(cString: physical)
    free(physical)
    let root = parent + "/pat2710-observer-" + UUID().uuidString.lowercased()
    try directory(root)
    defer { try? FileManager.default.removeItem(atPath: root) }
    let app = root + "/Unbranded.app", executable = app + "/Contents/MacOS/firefox"
    try directory(app); try directory(app + "/Contents"); try directory(app + "/Contents/MacOS")
    let pin = try FirefoxTargets.select(version: version), plist = try observerPlist(pin)
    try file(app + "/Contents/Info.plist", plist)
    try file(executable, Data("inert synthetic executable bytes".utf8))
    let appFD = open(app, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard appFD >= 0 else { throw CheckFailure(description: "Observer fixture app open failed") }
    defer { close(appFD) }
    let executableFD = open(executable, O_RDONLY | O_NOFOLLOW)
    guard executableFD >= 0 else { throw CheckFailure(description: "Observer fixture executable open failed") }
    defer { close(executableFD) }
    let fixture = ObserverFixture(root: root, app: app, executable: executable,
        plistPath: app + "/Contents/Info.plist", appFD: appFD, executableFD: executableFD, pin: pin, plist: plist)
    var bodyError: Error?
    do { try body(fixture) } catch { bodyError = error }
    // These assertions run on both success and refusal, before caller cleanup.
    try expect(fcntl(appFD, F_GETFD) >= 0 && fcntl(executableFD, F_GETFD) >= 0,
               "Observer closed borrowed descriptors")
    if let bodyError { throw bodyError }
}

private func observerRefuses(_ reason: InspectionFailure, _ body: () throws -> Void) throws {
    do { try body() }
    catch let failure as InspectionFailure {
        try expect(failure == reason, "Observer expected \(reason.rawValue), got \(failure.rawValue)")
        return
    }
    throw CheckFailure(description: "Observer accepted instead of \(reason.rawValue)")
}
private enum ObserverCollectorFailure: Error { case injected }

@MainActor func registerInstalledBundleObserverChecks() {
    for version in ["157.0", "157.0.1"] {
        check("PAT-2710 observer positive exact result and one collector call \(version)") {
            try withObserverFixture(version: version) { f in
                let expected = try f.observation()
                var calls = 0
                let result = try f.collect { path, pin in
                    calls += 1
                    try expect(path == f.app && pin == f.pin, "Collector arguments changed")
                    return expected
                }
                try expect(result == expected && calls == 1, "Exact observation and single call required")
            }
        }
    }
    for field in ["version", "url", "sha256", "byteLength", "bundleID", "teamID", "architectures"] {
        check("PAT-2710 observer altered compiled pin \(field) before collector") {
            try withObserverFixture { f in
                var pin = f.pin, calls = 0
                switch field {
                case "version": pin.version = "158.0"
                case "url": pin.url += "?changed"
                case "sha256": pin.sha256 = String(repeating: "0", count: 64)
                case "byteLength": pin.byteLength -= 1
                case "bundleID": pin.bundleID = "org.example.other"
                case "teamID": pin.teamID = "AAAAAAAAAA"
                default: pin.architectures.reverse()
                }
                try observerRefuses(.unknownTarget) {
                    _ = try f.collect(pin: pin) { _, _ in calls += 1; return try f.observation() }
                }
                try expect(calls == 0, "Altered pin reached collector")
            }
        }
    }
    let metadataCases: [(String, InspectionFailure, (inout [String: Any]) -> Void)] = [
        ("bundle value", .wrongBundle, { $0["CFBundleIdentifier"] = "org.example.other" }),
        ("bundle missing", .wrongBundle, { $0.removeValue(forKey: "CFBundleIdentifier") }),
        ("bundle type", .wrongBundle, { $0["CFBundleIdentifier"] = 7 }),
        ("version value", .wrongVersion, { $0["CFBundleShortVersionString"] = "157.0.1" }),
        ("version missing", .wrongVersion, { $0.removeValue(forKey: "CFBundleShortVersionString") }),
        ("version type", .wrongVersion, { $0["CFBundleShortVersionString"] = 157 }),
        ("executable value", .invalidMetadata, { $0["CFBundleExecutable"] = "other" }),
        ("executable traversal", .invalidMetadata, { $0["CFBundleExecutable"] = "../firefox" }),
        ("executable missing", .invalidMetadata, { $0.removeValue(forKey: "CFBundleExecutable") }),
        ("executable type", .invalidMetadata, { $0["CFBundleExecutable"] = 1 }),
        ("package value", .invalidMetadata, { $0["CFBundlePackageType"] = "BNDL" }),
        ("package missing", .invalidMetadata, { $0.removeValue(forKey: "CFBundlePackageType") }),
        ("package type", .invalidMetadata, { $0["CFBundlePackageType"] = true })]
    for (label, reason, change) in metadataCases {
        check("PAT-2710 observer plist \(label) before collector") {
            try withObserverFixture { f in
                let data = try observerPlist(f.pin, change: change)
                try overwrite(f.plistPath, data)
                var calls = 0
                try observerRefuses(reason) {
                    _ = try f.collect(plist: data) { _, _ in calls += 1; return try f.observation() }
                }
                try expect(calls == 0, "Invalid plist reached collector")
            }
        }
    }
    for label in ["malformed", "array", "oversize"] {
        check("PAT-2710 observer plist \(label) before collector") {
            try withObserverFixture { f in
                let data: Data
                switch label {
                case "array": data = try PropertyListSerialization.data(fromPropertyList: ["not a dictionary"], format: .xml, options: 0)
                case "oversize": data = try observerPlist(f.pin) { $0["Padding"] = String(repeating: "x", count: 1_048_577) }
                default: data = Data("not a plist".utf8)
                }
                var calls = 0
                try observerRefuses(.invalidMetadata) {
                    _ = try f.collect(plist: data) { _, _ in calls += 1; return try f.observation() }
                }
                try expect(calls == 0, "Malformed/oversize plist reached collector")
            }
        }
    }
    for label in ["relative", "double slash", "dot", "dotdot", "control", "nul"] {
        check("PAT-2710 observer unsafe evidence path \(label) before collector") {
            try withObserverFixture { f in
                let path: String
                switch label {
                case "relative": path = "Unbranded.app"
                case "double slash": path = f.root + "//Unbranded.app"
                case "dot": path = f.root + "/./Unbranded.app"
                case "dotdot": path = f.root + "/child/../Unbranded.app"
                case "control": path = f.app + "\n"
                default: path = f.app + "\0"
                }
                var calls = 0
                try observerRefuses(.invalidMetadata) {
                    _ = try f.collect(path: path) { _, _ in calls += 1; return try f.observation() }
                }
                try expect(calls == 0, "Unsafe path reached collector")
            }
        }
    }
    for label in ["app invalid FD", "executable invalid FD", "app file FD", "executable directory FD",
                  "different directory FD", "different file FD", "plist bytes mismatch", "app symlink", "executable symlink"] {
        check("PAT-2710 observer initial binding \(label) before collector") {
            try withObserverFixture { f in
                var appFD = f.appFD, executableFD = f.executableFD, extraFD: Int32 = -1
                var plist = f.plist
                defer { if extraFD >= 0 { close(extraFD) } }
                switch label {
                case "app invalid FD": appFD = -1
                case "executable invalid FD": executableFD = -1
                case "app file FD": appFD = f.executableFD
                case "executable directory FD": executableFD = f.appFD
                case "different directory FD":
                    try directory(f.root + "/Other"); extraFD = open(f.root + "/Other", O_RDONLY | O_DIRECTORY); appFD = extraFD
                    try expect(extraFD >= 0, "Other directory open")
                case "different file FD":
                    try file(f.root + "/other", Data("inert synthetic executable bytes".utf8))
                    extraFD = open(f.root + "/other", O_RDONLY); executableFD = extraFD
                    try expect(extraFD >= 0, "Other file open")
                case "plist bytes mismatch": plist = try observerPlist(f.pin) { $0["Extra"] = "different bytes" }
                case "app symlink":
                    try expect(rename(f.app, f.root + "/Retained.app") == 0, "Retain app")
                    try symbolic("Retained.app", f.app)
                default:
                    try expect(rename(f.executable, f.executable + "-retained") == 0, "Retain executable")
                    try symbolic("firefox-retained", f.executable)
                }
                var calls = 0
                try observerRefuses(.unsafePath) {
                    _ = try f.collect(appFD: appFD, executableFD: executableFD, plist: plist) { _, _ in
                        calls += 1; return try f.observation()
                    }
                }
                try expect(calls == 0, "Unbound input reached collector")
                if extraFD >= 0 { try expect(fcntl(extraFD, F_GETFD) >= 0, "Other borrowed descriptor closed") }
            }
        }
    }
    let observationCases: [(String, InspectionFailure, (inout SignatureObservation) -> Void)] = [
        ("path", .invalidMetadata, { $0.appPath += "/" }),
        ("requirement", .invalidMetadata, { $0.requirement += " " }),
        ("flags", .invalidMetadata, { $0.validationFlags ^= 1 }),
        ("validation status", .signatureRejected, { $0.validationStatus = -67050 }),
        ("signing information status", .signatureRejected, { $0.signingInformationStatus = -50 }),
        ("team", .wrongTeam, { $0.teamID = "AAAAAAAAAA" }),
        ("identifier", .wrongBundle, { $0.identifier = "org.example.other" }),
        ("start malformed", .invalidMetadata, { $0.startedAt = "invalid" }),
        ("finish malformed", .invalidMetadata, { $0.finishedAt = "invalid" }),
        ("reversed timestamps", .invalidMetadata, { $0.finishedAt = "2026-10-07T14:35:31Z" })]
    for (label, reason, mutate) in observationCases {
        check("PAT-2710 observer returned observation \(label) refuses") {
            try withObserverFixture { f in
                var value = try f.observation(), calls = 0
                mutate(&value)
                try observerRefuses(reason) {
                    _ = try f.collect { path, pin in
                        calls += 1
                        try expect(path == f.app && pin == f.pin, "Collector exact arguments")
                        return value
                    }
                }
                try expect(calls == 1, "Observation rejection must follow exactly one collection")
            }
        }
    }
    check("PAT-2710 observer equal timestamps accepted without invented recency") {
        try withObserverFixture { f in
            var value = try f.observation(), calls = 0
            value.startedAt = "2000-01-01T00:00:00Z"; value.finishedAt = value.startedAt
            let result = try f.collect { _, _ in calls += 1; return value }
            try expect(result == value && calls == 1, "Ordered old/equal timestamps accepted exactly")
        }
    }
    check("PAT-2710 observer binding confirmation precedes observation validation") {
        try withObserverFixture { f in
            var calls = 0
            try observerRefuses(.unsafePath) {
                _ = try f.collect { _, _ in
                    calls += 1
                    var value = try f.observation()
                    value.teamID = "AAAAAAAAAA"
                    try overwrite(f.executable, Data("mutated during collector before invalid observation".utf8))
                    return value
                }
            }
            try expect(calls == 1, "Binding refusal must follow exactly one collector mutation")
        }
    }
    check("PAT-2710 observer collector error propagates once without retry") {
        try withObserverFixture { f in
            var calls = 0, propagated = false
            do { _ = try f.collect { _, _ in calls += 1; throw ObserverCollectorFailure.injected } }
            catch ObserverCollectorFailure.injected { propagated = true }
            try expect(propagated && calls == 1, "Exact collector failure must propagate without fallback/retry")
        }
    }
    for label in ["app replacement", "app mode mutation", "executable replacement", "executable bytes mutation",
                  "executable mode mutation", "plist replacement changed bytes", "plist in-place mutation", "app path symlink"] {
        check("PAT-2710 observer post-collector \(label) refuses") {
            try withObserverFixture { f in
                var calls = 0
                try observerRefuses(.unsafePath) {
                    _ = try f.collect { _, _ in
                        calls += 1
                        let observation = try f.observation()
                        switch label {
                        case "app replacement":
                            try expect(rename(f.app, f.root + "/Retained.app") == 0, "Retain held app")
                            try directory(f.app)
                        case "app mode mutation": try expect(chmod(f.app, 0o750) == 0, "Mutate app mode")
                        case "executable replacement":
                            try expect(rename(f.executable, f.executable + "-retained") == 0, "Retain held executable")
                            try file(f.executable, Data("inert synthetic executable bytes".utf8))
                        case "executable bytes mutation": try overwrite(f.executable, Data("different longer inert bytes".utf8))
                        case "executable mode mutation": try expect(chmod(f.executable, 0o640) == 0, "Mutate executable mode")
                        case "plist replacement changed bytes":
                            try expect(rename(f.plistPath, f.plistPath + "-retained") == 0, "Retain plist")
                            try file(f.plistPath, observerPlist(f.pin) { $0["Extra"] = "replacement" })
                        case "plist in-place mutation":
                            try overwrite(f.plistPath, observerPlist(f.pin) { $0["Extra"] = "mutation" })
                        default:
                            try expect(rename(f.app, f.root + "/Retained.app") == 0, "Retain app for symlink")
                            try symbolic("Retained.app", f.app)
                        }
                        return observation
                    }
                }
                try expect(calls == 1, "Mutation must occur in collector between binding and confirmation")
            }
        }
    }
    registerInstalledRefusalDiagnosticChecks()
}


// Separately authored refusal-only checks. Every diagnostic is injected data;
// inert fixtures never enter public/native signature collection.
private extension ObserverFixture {
    func collectRefusal(pin: TargetPin? = nil,
                        collector: (String, TargetPin) throws -> SignatureObservation,
                        diagnostic: (String) throws -> InstalledSignatureRefusalDiagnostic)
        throws -> SignatureObservation {
        try InstalledBundleObserverTestAdapter.collect(appPath: app,
            appDescriptor: appFD, executableDescriptor: executableFD,
            infoPlist: plist, pin: pin ?? self.pin,
            collector: collector, diagnostic: diagnostic)
    }

    func refusalDiagnostic(path: String? = nil, flags: UInt32? = nil,
                           validation: Int32 = 0, signing: Int32 = 0,
                           team: String?, identifier: String?) -> InstalledSignatureRefusalDiagnostic {
        InstalledSignatureRefusalDiagnostic(appPath: path ?? app,
            validationFlags: flags ?? PinnedSignatureRequirement.validationFlags,
            validationStatus: validation, signingInformationStatus: signing,
            teamID: team, identifier: identifier)
    }
}

private func mutateRefusalFixture(_ f: ObserverFixture, _ label: String) throws {
    switch label {
    case "app replacement":
        try expect(rename(f.app, f.root + "/Retained.app") == 0, "Retain diagnostic app")
        try directory(f.app)
    case "app mode": try expect(chmod(f.app, 0o750) == 0, "Change diagnostic app mode")
    case "executable replacement":
        try expect(rename(f.executable, f.executable + "-retained") == 0, "Retain diagnostic executable")
        try file(f.executable, Data("inert synthetic executable bytes".utf8))
    case "executable bytes": try overwrite(f.executable, Data("changed longer inert diagnostic bytes".utf8))
    case "executable mode": try expect(chmod(f.executable, 0o640) == 0, "Change diagnostic executable mode")
    case "plist replacement":
        try expect(rename(f.plistPath, f.plistPath + "-retained") == 0, "Retain diagnostic plist")
        try file(f.plistPath, observerPlist(f.pin) { $0["Extra"] = "replacement" })
    case "plist bytes": try overwrite(f.plistPath, observerPlist(f.pin) { $0["Extra"] = "changed" })
    default:
        try expect(rename(f.app, f.root + "/Retained.app") == 0, "Retain diagnostic symlink app")
        try symbolic("Retained.app", f.app)
    }
}

@MainActor private func registerInstalledRefusalDiagnosticChecks() {
    let identities: [(String, String?, Bool, InspectionFailure)] = [
        ("missing team exact identifier", nil, true, .wrongTeam),
        ("different team exact identifier", "AAAAAAAAAA", true, .wrongTeam),
        ("different team different identifier", "AAAAAAAAAA", false, .wrongTeam),
        ("missing team different identifier", nil, false, .wrongTeam),
        ("exact team different identifier", "exact", false, .wrongBundle),
        ("exact identities cannot accept", "exact", true, .signatureRejected)]
    for (label, team, exactIdentifier, refusal) in identities {
        check("PAT-2710 installed diagnostic identity \(label)") {
            try withObserverFixture { f in
                var events: [String] = []
                try observerRefuses(refusal) {
                    _ = try f.collectRefusal(collector: { path, pin in
                        events.append("pinned")
                        try expect(path == f.app && pin == f.pin, "Diagnostic pinned arguments changed")
                        throw InspectionFailure.signatureRejected
                    }, diagnostic: { path in
                        events.append("diagnostic")
                        try expect(path == f.app, "Diagnostic exact path changed")
                        return f.refusalDiagnostic(team: team == "exact" ? f.pin.teamID : team,
                            identifier: exactIdentifier ? f.pin.bundleID : "org.example.other")
                    })
                }
                try expect(events == ["pinned", "diagnostic"], "Identity refusal requires one pinned call then one diagnostic")
            }
        }
    }
    for label in ["path", "flags", "validation", "signing", "missing identifier",
                  "empty identifier", "control identifier", "empty component identifier",
                  "oversize identifier", "missing team malformed identifier", "empty team", "malformed team"] {
        check("PAT-2710 installed diagnostic malformed \(label)") {
            try withObserverFixture { f in
                var events: [String] = []
                try observerRefuses(.signatureRejected) {
                    _ = try f.collectRefusal(collector: { _, _ in
                        events.append("pinned"); throw InspectionFailure.signatureRejected
                    }, diagnostic: { path in
                        events.append("diagnostic")
                        try expect(path == f.app, "Malformed diagnostic exact path")
                        var identifier: String? = f.pin.bundleID
                        switch label {
                        case "missing identifier": identifier = nil
                        case "empty identifier": identifier = ""
                        case "control identifier", "missing team malformed identifier": identifier = "org.example.\n"
                        case "empty component identifier": identifier = "org..example"
                        case "oversize identifier": identifier = "org." + String(repeating: "a", count: 252)
                        default: break
                        }
                        let team: String? = label == "missing team malformed identifier" ? nil :
                            (label == "empty team" ? "" : (label == "malformed team" ? "lowercase1" : f.pin.teamID))
                        return f.refusalDiagnostic(path: label == "path" ? f.app + "/" : nil,
                            flags: label == "flags" ? PinnedSignatureRequirement.validationFlags ^ 1 : nil,
                            validation: label == "validation" ? -67050 : 0,
                            signing: label == "signing" ? -50 : 0, team: team, identifier: identifier)
                    })
                }
                try expect(events == ["pinned", "diagnostic"], "Malformed refusal must diagnose once without accepting/retrying")
            }
        }
    }
    for label in ["success", "wrongTeam", "wrongBundle", "independent error", "returned status", "preflight"] {
        check("PAT-2710 installed diagnostic dispatch \(label)") {
            try withObserverFixture { f in
                var events: [String] = [], pin = f.pin
                if label == "preflight" { pin.teamID = "AAAAAAAAAA" }
                let operation = {
                    try f.collectRefusal(pin: pin, collector: { path, target in
                        events.append("pinned")
                        try expect(path == f.app && target == f.pin, "Dispatch exact collector arguments")
                        if label == "wrongTeam" { throw InspectionFailure.wrongTeam }
                        if label == "wrongBundle" { throw InspectionFailure.wrongBundle }
                        if label == "independent error" { throw ObserverCollectorFailure.injected }
                        var value = try f.observation()
                        if label == "returned status" { value.validationStatus = -67050 }
                        return value
                    }, diagnostic: { _ in
                        events.append("diagnostic")
                        throw CheckFailure(description: "Ineligible path entered diagnostic")
                    })
                }
                switch label {
                case "success": try expect(try operation() == f.observation(), "Successful observation changed")
                case "independent error":
                    var propagated = false
                    do { _ = try operation() } catch ObserverCollectorFailure.injected { propagated = true }
                    try expect(propagated, "Independent collector error changed")
                default:
                    let reason: InspectionFailure = label == "wrongTeam" ? .wrongTeam :
                        (label == "wrongBundle" ? .wrongBundle : (label == "preflight" ? .unknownTarget : .signatureRejected))
                    try observerRefuses(reason) { _ = try operation() }
                }
                try expect(events == (label == "preflight" ? [] : ["pinned"]), "Ineligible path diagnosed or collector retried")
            }
        }
    }
    let mutations = ["app replacement", "app mode", "executable replacement", "executable bytes",
                     "executable mode", "plist replacement", "plist bytes", "app symlink"]
    for phase in ["before", "during"] {
        for mutation in mutations {
            check("PAT-2710 installed diagnostic binding \(phase) \(mutation)") {
                try withObserverFixture { f in
                    var events: [String] = []
                    try observerRefuses(.unsafePath) {
                        _ = try f.collectRefusal(collector: { _, _ in
                            events.append("pinned")
                            if phase == "before" { try mutateRefusalFixture(f, mutation) }
                            throw InspectionFailure.signatureRejected
                        }, diagnostic: { path in
                            events.append("diagnostic")
                            try expect(path == f.app, "Mutation diagnostic exact path")
                            try mutateRefusalFixture(f, mutation)
                            return f.refusalDiagnostic(team: nil, identifier: f.pin.bundleID)
                        })
                    }
                    try expect(events == (phase == "before" ? ["pinned"] : ["pinned", "diagnostic"]),
                        "Binding checks must surround exactly one diagnostic")
                }
            }
        }
    }
    for identity in ["wrongBundle", "matching identities"] {
        check("PAT-2710 installed diagnostic mutation overrides \(identity)") {
            try withObserverFixture { f in
                var events: [String] = []
                try observerRefuses(.unsafePath) {
                    _ = try f.collectRefusal(collector: { _, _ in
                        events.append("pinned"); throw InspectionFailure.signatureRejected
                    }, diagnostic: { _ in
                        events.append("diagnostic")
                        try mutateRefusalFixture(f, "executable bytes")
                        return f.refusalDiagnostic(team: f.pin.teamID,
                            identifier: identity == "wrongBundle" ? "org.example.other" : f.pin.bundleID)
                    })
                }
                try expect(events == ["pinned", "diagnostic"], "Binding mutation must override every diagnostic identity outcome")
            }
        }
    }
    for mutation in [false, true] {
        check("PAT-2710 installed diagnostic throwing closure mutation=\(mutation)") {
            try withObserverFixture { f in
                var events: [String] = []
                try observerRefuses(mutation ? .unsafePath : .signatureRejected) {
                    _ = try f.collectRefusal(collector: { _, _ in
                        events.append("pinned"); throw InspectionFailure.signatureRejected
                    }, diagnostic: { _ in
                        events.append("diagnostic")
                        if mutation { try mutateRefusalFixture(f, "executable bytes") }
                        throw ObserverCollectorFailure.injected
                    })
                }
                try expect(events == ["pinned", "diagnostic"], "Throwing diagnostic must run once and confirm binding before refusal")
            }
        }
    }
}
