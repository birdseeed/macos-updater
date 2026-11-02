import Foundation
import CryptoKit
import Darwin
@_spi(Testing) import PatchedDisposableProof

struct CheckFailure: Error, CustomStringConvertible { let description: String }
struct ProbeRefusal: Error {}
func expect(_ value: @autoclosure () throws -> Bool, _ detail: String) throws {
    if try !value() { throw CheckFailure(description: detail) }
}
func refuses(_ reason: DisposableFailure, _ action: () throws -> Void) throws {
    do { try action() }
    catch let failure as DisposableFailure {
        try expect(failure == reason, "Expected \(reason.rawValue), got \(failure.rawValue)"); return
    }
    throw CheckFailure(description: "Expected refusal \(reason.rawValue); accepted")
}
func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
func statOf(_ path: String) throws -> stat {
    var info = stat(); guard lstat(path, &info) == 0 else { throw CheckFailure(description: "Fixture lstat failed: \(path)") }; return info
}
func bytes(_ path: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: path)) }
func exists(_ path: String) -> Bool { var info = stat(); return lstat(path, &info) == 0 }
func directory(_ path: String, mode: mode_t = 0o700) throws {
    guard mkdir(path, mode) == 0, chmod(path, mode) == 0 else { throw CheckFailure(description: "Fixture mkdir failed") }
}
func file(_ path: String, _ data: Data = Data("old".utf8), mode: mode_t = 0o600) throws {
    let descriptor = open(path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode)
    guard descriptor >= 0 else { throw CheckFailure(description: "Fixture exclusive open failed") }
    defer { close(descriptor) }
    let count = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    guard count == data.count, fchmod(descriptor, mode) == 0 else { throw CheckFailure(description: "Fixture write failed") }
}
func overwrite(_ path: String, _ data: Data) throws {
    let fd = open(path, O_WRONLY | O_TRUNC | O_NOFOLLOW)
    guard fd >= 0 else { throw CheckFailure(description: "Fixture overwrite open failed") }; defer { close(fd) }
    try expect(data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == data.count, "Fixture overwrite failed")
}
func symbolic(_ target: String, _ path: String) throws { try expect(symlink(target, path) == 0, "Fixture symlink failed") }
func physicalBuild() throws -> String {
    var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
    try expect(length > 0, "Kernel executable unavailable")
    let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    let parts = path.split(separator: "/").map(String.init)
    guard let index = parts.dropLast().lastIndex(of: ".build") else { throw CheckFailure(description: "Checks require nearest executable .build") }
    let build = "/" + parts[...index].joined(separator: "/")
    var current = ""
    for part in parts[...index] { current += "/" + part; try expect(try statOf(current).st_mode & S_IFMT == S_IFDIR, "Build ancestry contains a link") }
    return build
}
func fixture() throws -> String {
    let root = try physicalBuild() + "/patched-disposable-check-" + UUID().uuidString
    try directory(root); return root
}
func tree(_ root: String, _ name: String = "App") throws -> String {
    let path = root + "/" + name
    try directory(path); try directory(path + "/Contents", mode: 0o755)
    try file(path + "/Contents/exec", Data("synthetic executable bytes".utf8), mode: 0o755)
    try file(path + "/Contents/data", Data([0, 1, 2, 3]))
    try symbolic("Contents/exec", path + "/Current")
    return path
}
struct PhysicalEntry {
    let path: String, type: String, mode: UInt16, length: Int64, link: String, digest: String
}
func independentManifest(_ path: String) throws -> [PhysicalEntry] {
    var rows: [PhysicalEntry] = []
    func visit(_ absolute: String, _ relative: String) throws {
        let info = try statOf(absolute), mode = UInt16(info.st_mode & 0o7777)
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            rows.append(.init(path: relative, type: "directory", mode: mode, length: 0, link: "", digest: ""))
            for name in try FileManager.default.contentsOfDirectory(atPath: absolute) { try visit(absolute + "/" + name, relative == "." ? name : relative + "/" + name) }
        case S_IFREG:
            let data = try bytes(absolute)
            rows.append(.init(path: relative, type: "file", mode: mode, length: Int64(data.count), link: "", digest: sha(data)))
        case S_IFLNK:
            rows.append(.init(path: relative, type: "symlink", mode: mode, length: 0,
                              link: try FileManager.default.destinationOfSymbolicLink(atPath: absolute), digest: ""))
        default: throw CheckFailure(description: "Independent fixture manifest contains special file")
        }
    }
    try visit(path, ".")
    return rows.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
}
func canonical(_ rows: [PhysicalEntry]) -> Data {
    var output = Data("patched-disposable-manifest-v1\0".utf8)
    func number(_ n: UInt64) { var n = n.bigEndian; withUnsafeBytes(of: &n) { output.append(contentsOf: $0) } }
    func field(_ s: String) { let data = Data(s.utf8); number(UInt64(data.count)); output.append(data) }
    number(UInt64(rows.count))
    for row in rows { for value in [row.path, row.type, String(row.mode), String(row.length), row.link, row.digest] { field(value) } }
    return output
}
func matches(_ manifest: ProofManifest, _ physical: [PhysicalEntry]) throws {
    try expect(manifest.entries.count == physical.count, "Every physical entry must be reported")
    for (actual, wanted) in zip(manifest.entries, physical) {
        try expect(actual.path == wanted.path && actual.type == wanted.type && actual.mode == wanted.mode &&
                   actual.byteLength == wanted.length && actual.link == wanted.link && actual.sha256 == wanted.digest, "Full manifest entry differs: \(wanted.path)")
    }
    try expect(manifest.totalBytes == physical.reduce(0) { $0 + $1.length }, "Exact total byte count")
    try expect(manifest.digest == sha(canonical(physical)), "Independent length-delimited sorted manifest digest")
}
func binding(_ root: String, run: String = "phase-a", caseRoot: String = "update") throws -> SyntheticJournalBinding {
    let info = try statOf(root)
    return .init(runID: run, caseRoot: caseRoot, device: UInt64(UInt32(bitPattern: info.st_dev)), inode: info.st_ino)
}
func journal(_ root: String, state: ProofState = .prepared) throws -> [String: Any] {
    let b = try binding(root)
    return ["schemaVersion": 1, "kind": "patched-disposable-journal-v1", "origin": "synthetic",
            "guestUUIDSHA256": DisposableScope.guestUUIDSHA256, "uid": getuid(), "runID": b.runID,
            "caseRoot": b.caseRoot, "device": b.device, "inode": b.inode, "state": state.rawValue,
            "transactionID": "01234567-89AB-CDEF-0123-456789ABCDEF", "oldInode": 10, "newInode": 11,
            "beforeManifestSHA256": String(repeating: "a", count: 64), "afterManifestSHA256": String(repeating: "b", count: 64),
            "cataloguePayloadSHA256": String(repeating: "c", count: 64),
            "artifactSHA256": "40a0a649120635460256dae9ad63e40377f77326cbc9c449a5d0a1d7f5dd7982"]
}
func args(_ action: String = "update", root: String? = "update", run: String = "phase-a") -> [String] {
    var result = ["--target-id", DisposableScope.targetID, "--run-id", run, "--case", action, "--explicit-trigger"]
    if let root { result += ["--case-root", root] }; return result
}
