import Foundation
import Darwin
import PatchedCore

// This consumer can only verify a fixture with an explicitly supplied public
// key. Signing, key generation, networking, OS inspection and installation are absent.
func readInput(_ path: String, maximum: Int) throws -> Data {
    guard path.hasPrefix("/"), path != "/", path.utf8.count < 4096, !path.contains("\0") else { throw CoreFailure.unsafePath }
    let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count < 256, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw CoreFailure.unsafePath }
    var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw CoreFailure.unsafePath }
    defer { close(descriptor) }
    for (index, part) in parts.enumerated() {
        let next = openat(descriptor, String(part), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | (index < parts.count - 1 ? O_DIRECTORY : 0))
        guard next >= 0 else { throw CoreFailure.unsafePath }
        close(descriptor); descriptor = next
    }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw CoreFailure.notRegularFile }
    guard info.st_size > 0, info.st_size <= maximum else { throw CoreFailure.invalidEnvelope }
    var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw CoreFailure.unsafePath }
        if count == 0 { break }
        guard result.count + count <= maximum else { throw CoreFailure.invalidEnvelope }
        result.append(contentsOf: buffer.prefix(count))
    }
    guard result.count == info.st_size else { throw CoreFailure.invalidEnvelope }
    return result
}
func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(value)); print("")
}
let args = Array(CommandLine.arguments.dropFirst())
let commands = ["bootstrap-fixture", "verify-fixture", "verify-artifact-fixture"]
guard let command = args.first, commands.contains(command), args.count == (command == "verify-artifact-fixture" ? 10 : 9) else {
    print("Usage: patched-core-proof <bootstrap-fixture|verify-fixture|verify-artifact-fixture> <absolute-envelope> <absolute-public-key> <key-id> <catalogue-id> <absolute-state-directory> <now-unix-seconds> <os-version> <installed-version> [absolute-artifact]")
    exit(2)
}
do {
    guard let now = Double(args[6]) else { throw CoreFailure.invalidClock }
    let envelope = try readInput(args[1], maximum: 131_072)
    let publicKey = try readInput(args[2], maximum: 32)
    let verifier = CatalogueVerifier(trust: FixtureTrust(keyID: args[3], catalogueID: args[4], publicKey: publicKey),
        policy: CandidatePolicy(bundleID: "org.mozilla.firefox", teamID: "43AQ936H96", osVersion: args[7], installedVersion: args[8]), stateDirectory: args[5])
    let candidate: CatalogueCandidate
    if command == "bootstrap-fixture" { candidate = try verifier.bootstrapFreshProofNamespace(envelope: envelope, now: now) }
    else { candidate = try verifier.verify(envelope: envelope, now: now) }
    if command == "verify-artifact-fixture" { try emit(ArtifactVerifier.verify(path: args[9], candidate: candidate)) }
    else { try emit(candidate) }
} catch {
    FileHandle.standardError.write(Data("Fixture verification refused: \(error). No OS or installation trust granted.\n".utf8))
    exit(1)
}
