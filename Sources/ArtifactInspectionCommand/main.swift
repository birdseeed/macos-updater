import Foundation
import Darwin
import ArtifactInspection

func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(value)); FileHandle.standardOutput.write(Data("\n".utf8))
}
let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "verify-record" where args.count == 2:
        let pins = try FirefoxTargets.verifyRecord(ArtifactInspector.readRecord(path: args[1]))
        struct Result: Encodable {
            let targets: [TargetPin]; let recordConsistent = true; let freshOSValidation = false
            let installationAuthorized = false
            let limitation = "Consistency with compiled pins only; historical observations are not independently authenticated."
        }
        try emit(Result(targets: pins))
    case "replay" where args.count == 3:
        let pin = try FirefoxTargets.select(version: args[1])
        try emit(EvidenceEvaluator.replay(ArtifactInspector.readRecord(path: args[2]), pin: pin))
    case "inspect-local" where args.count == 3:
        let report = try ArtifactInspector.inspectLocal(version: args[1], path: args[2]); try emit(report)
        if report.refusal != nil { exit(1) }
    case "download-inspect" where args.count == 2:
        let report = try ArtifactInspector.downloadAndInspect(version: args[1]); try emit(report)
        if report.refusal != nil { exit(1) }
    default:
        FileHandle.standardError.write(Data("Usage: artifact-inspector verify-record <absolute-record.json> | replay <157.0|157.0.1> <absolute-evidence.json> | inspect-local <157.0|157.0.1> <absolute-dmg> | download-inspect <157.0|157.0.1>\n".utf8))
        exit(2)
    }
} catch {
    struct Refusal: Encodable { let refusal: String; let installationAuthorized = false; let freshOSValidation = false }
    try? emit(Refusal(refusal: (error as? InspectionFailure)?.rawValue ?? String(describing: error)))
    exit(1)
}
