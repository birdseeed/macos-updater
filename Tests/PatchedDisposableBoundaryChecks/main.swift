import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

struct Failure: Error { let message: String }
func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw Failure(message: message) }
}
func createFile(_ path: String, _ data: Data, mode: mode_t) throws {
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode)
    guard fd >= 0 else { throw Failure(message: "exclusive fixture file") }; defer { close(fd) }
    try expect(data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == data.count && fchmod(fd, mode) == 0, "fixture bytes")
}
var passed = 0
do {
    var path = [UInt8](repeating: 0, count: 4096)
    let count = proc_pidpath(getpid(), &path, UInt32(path.count))
    try expect(count > 0, "kernel executable")
    let parts = String(decoding: path.prefix(Int(count)), as: UTF8.self).split(separator: "/")
    guard let build = parts.lastIndex(of: ".build") else { throw Failure(message: "nearest build") }
    let root = "/" + parts[...build].joined(separator: "/") + "/patched-disposable-check-" + UUID().uuidString
    let held = try SyntheticProofFiles.createRoot(path: root)
    try SyntheticNativeBoundaries.validatePrivateACL(root: root); passed += 1
    try expect(mkdir(root + "/Source", 0o755) == 0 && chmod(root + "/Source", 0o755) == 0, "source directory")
    let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
    try createFile(root + "/Source/exec", bytes, mode: 0o755)
    var witnessed = false
    let copied = try SyntheticNativeBoundaries.copy(root: root, source: "Source", destination: "Complete") { relative, written, expected, inode in
        var physical = stat()
        try expect(relative == "exec" && written > 0 && written < expected && expected == bytes.count, "real mid-file witness")
        try expect(lstat(root + "/Complete/" + relative, &physical) == 0 && physical.st_ino == inode && physical.st_size == written, "witness binds incomplete physical file")
        witnessed = true
    }
    try expect(witnessed && copied == SyntheticProofFiles.inspect(root: root, relativePath: "Source"), "native metadata/content copy equality"); passed += 1
    do {
        _ = try SyntheticNativeBoundaries.copy(root: root, source: "Source", destination: "Partial") { _, _, _, _ in throw Failure(message: "stop actual copy") }
        throw Failure(message: "copy swallowed interruption")
    } catch let error as Failure { try expect(error.message == "stop actual copy", "exact witness refusal") }
    var partial = stat()
    try expect(lstat(root + "/Partial/exec", &partial) == 0 && partial.st_size > 0 && partial.st_size < bytes.count, "retained incomplete data"); passed += 1
    try expect(SyntheticNativeBoundaries.closeLease(root: root, relativeFile: "Source/exec").allSatisfy { $0 }, "all mount-lease descriptors explicitly close with live references"); passed += 1
    try held.revalidate()
    // Only this exclusive synthetic root receives an ACL; no existing ancestry changes.
    let chmodProcess = Process(); chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
    chmodProcess.arguments = ["+a", "everyone allow read", root]
    try chmodProcess.run(); chmodProcess.waitUntilExit(); try expect(chmodProcess.terminationStatus == 0, "synthetic granting ACL")
    do { try SyntheticNativeBoundaries.validatePrivateACL(root: root); throw Failure(message: "grant ACL accepted") }
    catch let error as DisposableFailure { try expect(error == .unsafeMode, "grant ACL refusal") }; passed += 1
    print("Disposable native boundary regression checks: \(passed)/5 passed; synthetic only, no mounted image or guest proof")
    try runOwnedImageSealChecks()
    try runNativeDittoChecks()
} catch { print("Disposable native boundary regression failure after \(passed) checks: \(error)"); exit(1) }

func runNativeDittoChecks() throws {
    try expect(getuid() != 0 && geteuid() != 0, "ditto checks require an ordinary non-root user")
    var executable = [UInt8](repeating: 0, count: 4096)
    let length = proc_pidpath(getpid(), &executable, UInt32(executable.count))
    try expect(length > 0 && length < executable.count, "ditto check kernel executable")
    let parts = String(decoding: executable.prefix(Int(length)), as: UTF8.self).split(separator: "/")
    guard let build = parts.lastIndex(of: ".build") else { throw Failure(message: "ditto check nearest build") }
    let root = "/" + parts[...build].joined(separator: "/") + "/patched-disposable-check-" + UUID().uuidString
    let capability = try SyntheticProofFiles.createRoot(path: root)
    func directory(_ leaf: String, _ mode: mode_t) throws {
        try expect(mkdir(root + "/" + leaf, mode) == 0 && chmod(root + "/" + leaf, mode) == 0, "exclusive fixture directory")
    }
    func status(_ leaf: String) throws -> stat {
        var value = stat()
        try expect(lstat(root + "/" + leaf, &value) == 0, "independent directory stat")
        return value
    }
    try directory("Source", 0o755)
    try directory("Source/Contents", 0o750)
    try createFile(root + "/Source/Contents/exec", Data("inert synthetic executable bytes\n".utf8), mode: 0o755)
    try createFile(root + "/Source/Contents/data", Data("synthetic resource\n".utf8), mode: 0o640)
    try expect(symlink("Contents/exec", root + "/Source/Current") == 0, "internal synthetic symlink")
    let source = try SyntheticProofFiles.inspect(root: root, relativePath: "Source"), sourceIdentity = try status("Source")
    var original: stat?, returned: ProofManifest?, refusal: Error?, copiedCommand = false
    do {
        returned = try SyntheticNativeBoundaries.copyWithDitto(root: root, source: "Source", destination: "Copied",
            beforeCopy: { original = try status("Copied") }, afterCopy: { copiedCommand = true })
    } catch { refusal = error }
    let actual = try SyntheticProofFiles.inspect(root: root, relativePath: "Copied")
    var failures = 0, count = 0
    func check(_ label: String, _ body: () throws -> Void) {
        count += 1
        do { try body() }
        catch { failures += 1; print("Native ditto FAIL: \(label): \(error)") }
    }
    check("native helper returns the entire source manifest") {
        try expect(returned == source && refusal == nil, "full manifest must accept; observed \(String(describing: refusal))")
    }
    check("root mode is preserved") {
        try expect(actual.entries.first(where: { $0.path == "." })?.mode == 0o755,
                   "source root 0755 must survive exclusive precreation")
    }
    check("every manifest entry including root matches") {
        try expect(actual == source, "full type/mode/length/link/content manifest equality")
    }
    check("exclusive destination inode and private parent survive") {
        let after = try status("Copied")
        try expect(copiedCommand && ((original?.st_mode ?? 0) & 0o7777) == 0o700, "observed exclusive 0700 precreation")
        try expect(original?.st_ino == after.st_ino && original?.st_dev == after.st_dev &&
                   after.st_uid == getuid() && after.st_ino != sourceIdentity.st_ino, "same exclusive owned destination inode")
        try capability.revalidate()
    }
    check("source complete manifest and identity survive") {
        let after = try status("Source")
        try expect(after.st_dev == sourceIdentity.st_dev && after.st_ino == sourceIdentity.st_ino &&
                   after.st_mode == sourceIdentity.st_mode && after.st_uid == sourceIdentity.st_uid,
                   "source root identity and permissions unchanged")
        try expect(SyntheticProofFiles.inspect(root: root, relativePath: "Source") == source, "source entire tree unchanged")
    }
    check("existing destination refuses before native command") {
        var started = false
        do {
            _ = try SyntheticNativeBoundaries.copyWithDitto(root: root, source: "Source", destination: "Copied",
                                                           beforeCopy: { started = true })
            throw Failure(message: "existing destination accepted")
        } catch let error as DisposableFailure { try expect(error == .existingRoot && !started, "exclusive creation refusal") }
    }
    // A 0700 source is the positive control: original helper must accept all fields.
    try directory("PrivateSource", 0o700)
    try createFile(root + "/PrivateSource/data", Data("private synthetic source\n".utf8), mode: 0o600)
    check("0700 source positive control accepts") {
        let copied = try SyntheticNativeBoundaries.copyWithDitto(root: root, source: "PrivateSource", destination: "PrivateCopy")
        try expect(copied == SyntheticProofFiles.inspect(root: root, relativePath: "PrivateSource"), "unchanged helper positive control")
    }
    check("full manifest still refuses changed copied file mode") {
        do {
            _ = try SyntheticNativeBoundaries.copyWithDitto(root: root, source: "PrivateSource", destination: "ChangedCopy",
                afterCopy: { try expect(chmod(root + "/ChangedCopy/data", 0o400) == 0, "synthetic copied mode mutation") })
            throw Failure(message: "changed copied manifest accepted")
        } catch let error as DisposableFailure { try expect(error == .manifestMismatch, "strict complete manifest refusal") }
    }
    check("named destination replacement refuses without changing replacement") {
        var replacement: stat?
        do {
            _ = try SyntheticNativeBoundaries.copyWithDitto(root: root, source: "PrivateSource", destination: "ReplacedCopy",
                afterCopy: {
                    try expect(rename(root + "/ReplacedCopy", root + "/RetainedCopy") == 0, "retain original synthetic copy")
                    try directory("ReplacedCopy", 0o750)
                    replacement = try status("ReplacedCopy")
                })
            throw Failure(message: "replaced destination accepted")
        } catch let error as DisposableFailure {
            try expect(error == .identityChanged || error == .manifestMismatch, "held destination identity refusal")
        }
        let after = try status("ReplacedCopy")
        try expect(replacement?.st_dev == after.st_dev && replacement?.st_ino == after.st_ino &&
                   replacement?.st_mode == after.st_mode && replacement?.st_uid == after.st_uid &&
                   replacement?.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec &&
                   replacement?.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
                   "replacement directory identity and metadata remain unchanged")
    }
    check("source replacement refuses") {
        do {
            _ = try SyntheticNativeBoundaries.copyWithDitto(root: root, source: "PrivateSource", destination: "ReplacedSourceCopy",
                afterCopy: {
                    try expect(rename(root + "/PrivateSource", root + "/RetainedSource") == 0, "retain synthetic source")
                    try directory("PrivateSource", 0o700)
                })
            throw Failure(message: "replaced held source accepted")
        } catch let error as DisposableFailure { try expect(error == .identityChanged, "held source identity refusal") }
    }
    print("Native ditto root checks: \(count - failures)/\(count) passed; synthetic root \(root); no guest proof")
    try expect(failures == 0, "\(failures) native ditto root checks failed")
}
