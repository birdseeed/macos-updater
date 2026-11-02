import SwiftUI
import PatchedOperator

// Source only in this proof: built by the gate and never launched by a gate or an agent.
// The default session starts with no disk image and no version chosen. Nothing is
// scheduled, no network request is made and nothing is checked at startup; a check runs
// only when the operator chooses a local disk image and an approved version and clicks Verify.
@main
struct PatchedOperatorApp: App {
    @StateObject private var session = OperatorSession()

    var body: some Scene {
        WindowGroup("Patched Operator") {
            OperatorSessionView(session: session)
        }
    }
}
