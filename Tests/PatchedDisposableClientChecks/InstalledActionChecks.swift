import Foundation
@_spi(Testing) import PatchedDisposableClient

private struct InstalledCheckRefusal: Error {}
private actor InstalledGatewayDouble: InstalledActionTestGateway {
    var calls: [String] = []
    var changed = false
    var invalidReadback = false
    var forgedStdout = false
    var readbackGate: Gate?
    var executionGate: Gate?
    func setChanged() { changed = true }
    func setInvalidReadback() { invalidReadback = true }
    func setForgedStdout() { forgedStdout = true }
    func blockReadback(_ gate: Gate) { readbackGate = gate }
    func blockExecution(_ gate: Gate) { executionGate = gate }
    func prepare(_ selection: InstalledActionSelection) async throws -> DisposableInstalledActionCapability {
        calls.append("prepare"); return .testDouble()
    }
    func revalidate(_ capability: DisposableInstalledActionCapability, selection: InstalledActionSelection) async throws {
        calls.append("revalidate"); if changed { throw InstalledCheckRefusal() }
    }
    func execute(_ capability: DisposableInstalledActionCapability, action: InstalledAction) async throws -> InstalledActionTestChild {
        calls.append("execute:" + action.rawValue)
        if let gate = executionGate { await gate.wait() }
        let state = action == .update ? "committed" : "rolledBack"
        let recovery = action == .recoverAfterStaging ? "oldAlreadyInPlace" : (action == .update ? "none" : "restoredOldBySwap")
        let object: [String: Any] = ["action": action.rawValue, "runID": installedSelection.runID,
            "caseRoot": installedSelection.caseRoot, "targetPath": installedSelection.targetPath,
            "transactionID": "00000000-0000-4000-8000-000000000001", "state": state, "recoveryAction": recovery,
            "installedFirefoxProof": action == .update, "freshOSValidation": true, "ownedMountsAbsent": true,
            "productionTrust": false, "globalProductReadiness": false]
        return InstalledActionTestChild(exitCode: 0, stdout: try JSONSerialization.data(withJSONObject: object))
    }
    func readback(_ capability: DisposableInstalledActionCapability, action: InstalledAction) async throws -> InstalledActionTestReadback {
        calls.append("readback:" + action.rawValue)
        if let gate = readbackGate { await gate.wait() }
        return InstalledActionTestReadback(runID: installedSelection.runID, targetPath: installedSelection.targetPath,
            version: action == .update ? "157.0.1" : "157.0", transactionID: "00000000-0000-4000-8000-000000000001",
            targetVerified: !invalidReadback && !forgedStdout, oldRetainedVerified: !invalidReadback,
            fresh: !invalidReadback && !forgedStdout)
    }
}
private let installedSelection = InstalledActionSelection(runID: "native-proof-check-only", caseRoot: "update",
    artifactPath: "/TEST-ONLY/Incoming/Firefox 157.0.1.dmg", targetPath: "/TEST-ONLY/Cases/update/Applications/Firefox.app", version: "157.0.1")

@MainActor func registerInstalledActionChecks() {
    check("installed authority: ordinary controller cannot arm from paths, pin or explicit trigger") {
        let c = InstalledActionController(); c.select(installedSelection)
        await c.prepare(); await c.request(.update, trigger: .explicitUserAction)
        try expect(c.phase == .refused && !c.actionEnabled && !c.installedFirefoxProof && !c.productionTrust && !c.isTestDouble,
                   "Ordinary controller armed an installed action")
    }
    check("installed authority: opaque capability has no summary, boolean, fixture-candidate or saved-JSON issuer") {
        let text = try source("Sources/PatchedDisposableClient/InstalledActionController.swift")
        let start = text.range(of: "public final class DisposableInstalledActionCapability")!
        let end = text.range(of: "/// These test outputs", range: start.upperBound..<text.endIndex)!
        let capability = String(text[start.lowerBound..<end.lowerBound])
        for word in ["Codable", "Decodable", "JSONDecoder", "ClientInspectionSummary", "CatalogueCandidate", "FixtureTrust", "Bool", "Data"] {
            try expect(!capability.contains(word), "Capability can be supplied through \(word)")
        }
        try expect(capability.contains("private init()") && capability.contains("@_spi(Testing) public static func testDouble()"),
                   "Capability initializer/factory boundary changed")
        let app = try source("Sources/PatchedApp/PatchedApp.swift")
        try expect(!app.contains("InstalledAction") && !app.contains("@_spi"), "Phase A armed the ordinary app")
    }
    check("installed dispatch: prepare obtains only the labelled gateway token without executing") {
        let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
        c.select(installedSelection); await c.prepare()
        try expect(await g.calls == ["prepare"], "Meaningful red: bound preparation gateway was not called")
        try expect(c.phase == .ready && c.actionEnabled && c.isTestDouble && !c.productionTrust, "Bound test action was not ready")
    }
    check("installed dispatch: explicit update revalidates, executes once and independently reads target") {
        let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
        c.select(installedSelection); await c.prepare(); await c.request(.update, trigger: .explicitUserAction)
        try expect(await g.calls == ["prepare", "revalidate", "execute:update", "readback:update"], "Meaningful red: installed update dispatch/readback missing")
        try expect(c.phase == .succeeded && !c.installedFirefoxProof && c.isTestDouble && !c.productionTrust,
                   "Test success missing or incorrectly claimed actual proof")
    }
    check("installed trigger: prepare and background requests never execute a child") {
        let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
        c.select(installedSelection); await c.prepare(); await c.request(.update, trigger: .background)
        try expect(!(await g.calls).contains(where: { $0.hasPrefix("execute:") }), "Background operation executed")
        try expect(!c.installedFirefoxProof && !c.productionTrust, "Background operation granted authority")
    }
    for replacement in ["candidate", "target", "binary"] {
        check("installed stale: \(replacement) replacement refuses before child dispatch") {
            let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
            c.select(installedSelection); await c.prepare(); await g.setChanged()
            await c.request(.update, trigger: .explicitUserAction)
            try expect((await g.calls).contains("revalidate"), "Meaningful red: no action-time \(replacement) revalidation")
            try expect(!(await g.calls).contains(where: { $0.hasPrefix("execute:") }) && c.phase == .refused, "Changed \(replacement) was executed")
        }
    }
    for action in [InstalledAction.recoverAfterStaging, .recoverAfterSwap, .restoreOld] {
        check("installed recovery: \(action.rawValue) verifies old target before restored UI") {
            let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
            c.select(installedSelection); await c.prepare(); await c.request(action, trigger: .explicitUserAction)
            try expect(await g.calls == ["prepare", "revalidate", "execute:" + action.rawValue, "readback:" + action.rawValue],
                       "Meaningful red: actual recovery dispatch/readback missing")
            try expect(c.phase == .restored && !c.installedFirefoxProof && !c.productionTrust, "Verified-old recovery was not shown")
        }
    }
    check("installed recovery: unverifiable old bundle cannot show restored") {
        let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
        c.select(installedSelection); await c.prepare(); await g.setInvalidReadback()
        await c.request(.restoreOld, trigger: .explicitUserAction)
        try expect((await g.calls).contains("readback:restoreOld"), "Meaningful red: old target readback missing")
        try expect(c.phase == .refused && !c.installedFirefoxProof, "Unverified old target was shown restored")
    }
    check("installed readback: forged successful child stdout alone cannot show success") {
        let g = InstalledGatewayDouble(), c = InstalledActionController(gateway: g)
        c.select(installedSelection); await c.prepare(); await g.setForgedStdout()
        await c.request(.update, trigger: .explicitUserAction)
        try expect((await g.calls).contains("readback:update"), "Meaningful red: stdout was not independently checked on target")
        try expect(c.phase == .refused && !c.installedFirefoxProof, "Forged stdout became success")
    }
    check("installed concurrency: one outstanding child, no UI success while readback waits") {
        let g = InstalledGatewayDouble(), gate = Gate(), c = InstalledActionController(gateway: g)
        await g.blockReadback(gate); c.select(installedSelection); await c.prepare()
        let first = Task { await c.request(.update, trigger: .explicitUserAction) }
        // A bounded sampling delay also lets the refusing Phase A return cleanly.
        try await Task.sleep(nanoseconds: 30_000_000)
        let overlapping = Task { await c.request(.update, trigger: .explicitUserAction) }
        try await Task.sleep(nanoseconds: 30_000_000)
        let calls = await g.calls
        let pending = c.phase
        await gate.open(); await first.value; await overlapping.value
        try expect(calls.filter { $0 == "execute:update" }.count == 1 && calls.contains("readback:update"),
                   "Meaningful red: no single-flight child/readback")
        try expect(pending == .running, "UI showed success before target readback")
        try expect(c.phase == .succeeded, "Fresh verified target did not complete UI")
    }
    check("installed cancellation: a replaced selection invalidates pending child success") {
        let g = InstalledGatewayDouble(), gate = Gate(), c = InstalledActionController(gateway: g)
        await g.blockExecution(gate); c.select(installedSelection); await c.prepare()
        let first = Task { await c.request(.update, trigger: .explicitUserAction) }
        try await Task.sleep(nanoseconds: 30_000_000)
        c.select(InstalledActionSelection(runID: "different", caseRoot: "update", artifactPath: "/TEST-ONLY/different.dmg",
                                         targetPath: installedSelection.targetPath, version: "157.0.1"))
        await gate.open(); await first.value
        try expect((await g.calls).contains("execute:update"), "Meaningful red: no pending child to invalidate")
        try expect(c.phase != .succeeded && !c.actionEnabled && !c.installedFirefoxProof, "Stale child success survived selection change")
    }
}
