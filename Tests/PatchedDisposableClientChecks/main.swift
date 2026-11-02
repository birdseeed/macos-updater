import Foundation
import Darwin

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}
var cases: [(String, @MainActor () async throws -> Void)] = []
@MainActor func check(_ name: String, _ action: @escaping @MainActor () async throws -> Void) { cases.append((name, action)) }
func source(_ relative: String) throws -> String {
    // Resolve only checked-in source beside this file, never an arbitrary caller path.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
}
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { isOpen = true; let pending = waiters; waiters = []; pending.forEach { $0.resume() } }
}
registerInstalledActionChecks()
registerTargetProfileClientChecks()
if Array(CommandLine.arguments.dropFirst()) == ["--pat-2710-profile-client"] {
    cases = cases.filter { $0.0.hasPrefix("PAT-2710 profile client: ") }
    if cases.isEmpty { print("FAIL PAT-2710 profile client selection empty"); exit(1) }
}
var failures = 0
for (name, action) in cases {
    do { try await action(); print("PASS disposable-client: \(name)") }
    catch { failures += 1; print("FAIL disposable-client: \(name): \(error)") }
}
print("Disposable client acceptance: \(cases.count) cases, \(failures) failures. In-memory test doubles only; no live issuer, child execution, installation or launch.")
exit(failures == 0 ? 0 : 1)
