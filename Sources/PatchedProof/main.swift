import Foundation
import ReferenceVerification

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["verify-references"] ||
      (arguments.count == 3 && arguments[0] == "verify-references" && arguments[1] == "--root" && !arguments[2].isEmpty) else {
    FileHandle.standardError.write(Data("Usage: patched-proof verify-references [--root <path>]\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments.count == 3 ? arguments[2] : FileManager.default.currentDirectoryPath)
do {
    let verified = try ReferenceVerifier.verify(root: root)
    print("Verified \(verified.count) preserved references against source-provenance.json.")
    print("Reference integrity only; no vendor authenticity or release verification.")
} catch {
    FileHandle.standardError.write(Data("Reference verification failed: \(error)\n".utf8))
    exit(1)
}
