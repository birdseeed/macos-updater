import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

// Full existing schema fixture, with independently declared profile literals.
// This function performs no filesystem access and produces no native evidence.
private func profileProjectionReport(_ profile: DisposableTargetProfile) -> [String: Any] {
    var o = report()
    let ssd = profile == .ssdTesting
    let parent = ssd ? "/Users/runner/PatchedTesting" : "/Users/andy/PatchedProof"
    o["targetID"] = ssd ? "parallels-0A0A0A0A-0000-4000-8000-000000000002" : "parallels-0A0A0A0A-0000-4000-8000-000000000001"
    o["targetPath"] = parent + "/synthetic-gateway/Cases/update/Applications/Firefox.app"
    o["exchangePath"] = parent + "/synthetic-gateway/Cases/update/Transaction/Exchange/Firefox.app"
    o["guest"] = ["platformUUIDSHA256": ssd ? "a44c836bfbda0c6beb1df7b3b3178a171479d362ecfacd534a62b09890dde705" : "d0c5822c54defb6c6971336fc87f86d794dfca4d3d9497a57701f04d016de959",
        "user": ssd ? "runner" : "andy", "home": ssd ? "/Users/runner" : "/Users/andy",
        "hostname": ssd ? "patched-test-01" : "mac-staging.local", "osVersion": "27.0.1", "osBuild": "26A434",
        "architecture": "arm64", "uid": 501, "effectiveUID": 501, "consoleUID": 501, "hypervisor": 1] as [String: Any]
    return o
}
private func profileProjectionCompare(_ o: [String: Any], expectedProfile: DisposableTargetProfile,
                                      readbackPath: String? = nil) throws {
    let expected = SyntheticGatewayExpectation(binarySHA256: reportExpected.binarySHA256, receiptBytes: reportExpected.receiptBytes,
        artifactSHA256: reportExpected.artifactSHA256, artifactLength: reportExpected.artifactLength, profile: expectedProfile)
    let parent = expectedProfile == .ssdTesting ? "/Users/runner/PatchedTesting" : "/Users/andy/PatchedProof"
    let physical = readback(targetPath: readbackPath ?? parent + "/synthetic-gateway/Cases/update/Applications/Firefox.app")
    let bytes = try json(o)
    try SyntheticGatewayCompletion.compare(stdout: bytes + Data([10]), durableReport: bytes, childExit: 0,
        expectedInvocationID: invoke, observedInvocationID: invoke, durableFileIsNew: true, action: .update,
        runID: "synthetic-gateway", caseRoot: "update", expected: expected, readback: physical)
}
@MainActor func registerTargetProfileProjectionChecks() {
    let prefix = "PAT-2710 profile projection: "
    check(prefix + "expectation omission remains legacy [control]") {
        try expect(reportExpected.profile == .legacy, "SPI default must remain legacy")
    }
    for profile in [DisposableTargetProfile.legacy, .ssdTesting] {
        let name = String(describing: profile), other: DisposableTargetProfile = profile == .legacy ? .ssdTesting : .legacy
        check(prefix + "literal full \(name) report [SSD expect RED]") {
            try profileProjectionCompare(profileProjectionReport(profile), expectedProfile: profile)
        }
        check(prefix + "opposite complete report under \(name) selection [SSD expect RED]") {
            let path = other == .legacy ? "/Users/andy/PatchedProof/synthetic-gateway/Cases/update/Applications/Firefox.app" :
                "/Users/runner/PatchedTesting/synthetic-gateway/Cases/update/Applications/Firefox.app"
            try refusal(.notAuthorized) { try profileProjectionCompare(profileProjectionReport(other), expectedProfile: profile, readbackPath: path) }
        }
        for key in ["targetID", "targetPath", "exchangePath"] {
            check(prefix + "\(name) refuses mixed \(key) [control]") {
                var o = profileProjectionReport(profile); o[key] = profileProjectionReport(other)[key]
                try refusal(.notAuthorized) { try profileProjectionCompare(o, expectedProfile: profile) }
            }
        }
        for key in ["platformUUIDSHA256", "user", "home", "hostname", "uid", "effectiveUID", "consoleUID", "hypervisor", "osVersion", "osBuild", "architecture"] {
            check(prefix + "\(name) refuses changed guest \(key) [control]") {
                var o = profileProjectionReport(profile), guest = o["guest"] as! [String: Any]
                switch key {
                case "platformUUIDSHA256", "user", "home", "hostname": guest[key] = (profileProjectionReport(other)["guest"] as! [String: Any])[key]
                case "uid", "effectiveUID", "consoleUID", "hypervisor": guest[key] = 0
                default: guest[key] = "different"
                }
                o["guest"] = guest
                try refusal(.notAuthorized) { try profileProjectionCompare(o, expectedProfile: profile) }
            }
        }
        for key in ["unknownTopLevel", "unknownGuest", "guestMissing", "targetIDMissing", "physicalReadbackMix"] {
            check(prefix + "\(name) closed schema/readback \(key) [control]") {
                var o = profileProjectionReport(profile)
                switch key {
                case "unknownTopLevel": o["profile"] = "ssdTesting"
                case "unknownGuest": var guest = o["guest"] as! [String: Any]; guest["installationAuthorized"] = true; o["guest"] = guest
                case "guestMissing": o.removeValue(forKey: "guest")
                case "targetIDMissing": o.removeValue(forKey: "targetID")
                default: break
                }
                let mixedPath = key == "physicalReadbackMix" ? "/Applications/Firefox.app" : nil
                try refusal(.notAuthorized) { try profileProjectionCompare(o, expectedProfile: profile, readbackPath: mixedPath) }
            }
        }
    }
}

// Separately focused from pure projection. Parent must approve host execution.
// On any VM this refuses to invoke either issuer, even if the VM seems unrelated.
@MainActor func registerTargetProfileHostRefusalChecks() {
    for profile in [DisposableTargetProfile.legacy, .ssdTesting] {
        check("PAT-2710 profile host refusal: \(profile) before writes [control; real host only]") {
            var hv: Int32 = -1, size = MemoryLayout<Int32>.size
            try expect(sysctlbyname("kern.hv_vmm_present", &hv, &size, nil, 0) == 0 && hv == 0,
                       "Cannot invoke issuer unless physical non-VM host is positively observed")
            let parent = profile == .legacy ? "/Users/andy/PatchedProof" : "/Users/runner/PatchedTesting"
            var before = stat(), after = stat()
            let present = lstat(parent, &before) == 0
            let runID = "profile-host-refusal-" + UUID().uuidString
            var destination = stat()
            try expect(lstat(parent + "/" + runID, &destination) != 0 && errno == ENOENT, "Destination must not exist")
            try refusal(.guestMismatch) { _ = try NativeInstalledActionScope.open(runID: runID, caseRoot: "update", profile: profile) }
            try refusal(.guestMismatch) { _ = try NativeInstalledActionScope.open(runID: "../../escape", caseRoot: "/Applications", profile: profile) }
            if profile == .legacy {
                try refusal(.guestMismatch) { _ = try NativeInstalledActionScope.open(runID: runID, caseRoot: "update") }
            }
            try expect(lstat(parent + "/" + runID, &destination) != 0 && errno == ENOENT, "Issuer wrote destination")
            try expect((lstat(parent, &after) == 0) == present, "Issuer created parent")
            if present {
                try expect(before.st_dev == after.st_dev && before.st_ino == after.st_ino && before.st_mode == after.st_mode &&
                    before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec &&
                    before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
                    "Issuer mutated parent before refusal")
            }
        }
    }
}
