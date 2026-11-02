import Foundation
import Darwin
import ArtifactInspection

// CHECK-ADDED: reviewer claim validation. The parent harness invokes this helper
// only through BoundedCommandRunner, which creates a fresh process group. Refuse
// direct, unisolated invocation before exercising a suspected kill(0) path.
func runSpawnFailureProbe() -> Never {
    guard getpgrp() == getpid() else {
        print("spawn-failure-probe: requires an isolated process group")
        exit(2)
    }
    let missing = "/__patched_spawn_probe_\(UUID().uuidString)/missing-executable"
    guard !FileManager.default.fileExists(atPath: missing) else { exit(2) }
    do {
        _ = try BoundedCommandRunner().run(executable: missing, arguments: [], limits: .init())
        print("spawn-failure-probe: unexpectedly returned a result")
        exit(1)
    } catch InspectionFailure.commandFailed {
        print("spawn-failure-probe: isolated; commandFailed safely")
        exit(0)
    } catch {
        print("spawn-failure-probe: unexpected error \(error)")
        exit(1)
    }
}

@MainActor func addSpawnFailureCheck() {
    check("isolated failed spawn throws without signalling its process group") {
        var limits = InspectionLimits(); limits.commandSeconds = 3
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let result = try BoundedCommandRunner().run(executable: executable,
            arguments: ["--probe-spawn-failure"], limits: limits)
        try expect(result.exitCode == 0 && !result.timedOut && !result.outputExceeded,
                   "Isolated probe must exit normally, not die from a group signal")
        try expect(result.stdout == "spawn-failure-probe: isolated; commandFailed safely\n" && result.stderr.isEmpty,
                   "Isolated child must observe the exact commandFailed refusal")
        print(result.stdout, terminator: "")
    }
}
