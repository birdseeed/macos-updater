import Foundation
import Darwin
import PatchedDisposableProof

@main struct DisposableProofCommand {
    static func main() {
        do {
            let request = try DisposableArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let report = try DisposableProof.execute(request)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            print(String(decoding: try encoder.encode(report), as: UTF8.self))
        } catch {
            let reason = (error as? DisposableFailure)?.rawValue ?? "operationFailed"
            print("{\"refusal\":\"\(reason)\",\"installedFirefoxProof\":false}")
            exit(1)
        }
    }
}
