import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

func runOwnedImageSealChecks() throws {
    try expect(getuid() != 0 && geteuid() != 0, "seal checks require an ordinary non-root user")
    var executable = [UInt8](repeating: 0, count: 4096)
    let length = proc_pidpath(getpid(), &executable, UInt32(executable.count))
    try expect(length > 0 && length < executable.count, "seal check kernel executable")
    let parts = String(decoding: executable.prefix(Int(length)), as: UTF8.self).split(separator: "/")
    guard let build = parts.lastIndex(of: ".build") else { throw Failure(message: "seal check nearest build") }
    let root = "/" + parts[...build].joined(separator: "/") + "/patched-disposable-check-" + UUID().uuidString
    let capability = try SyntheticProofFiles.createRoot(path: root)
    let bytes = Data((0..<131_073).map { UInt8($0 % 251) })
    try createFile(root + "/input", bytes, mode: 0o600)
    let staged = try SyntheticNativeBoundaries.stageImage(root: root, source: "input", destination: "staged")
    var failures = 0, count = 0
    func check(_ label: String, _ body: () throws -> Void) {
        count += 1
        do { try body() }
        catch { failures += 1; print("Owned image seal FAIL: \(label): \(error)") }
    }
    func status(_ leaf: String) throws -> stat {
        var result = stat()
        try expect(lstat(root + "/" + leaf, &result) == 0, "independent fixture stat")
        return result
    }
    func refusesChangedCapture(_ name: String, _ mutation: () throws -> Void) throws {
        do {
            _ = try SyntheticNativeBoundaries.stageImage(root: root, source: "input", destination: name,
                                                        afterCapture: mutation)
            throw Failure(message: "original staged handle accepted changed identity or metadata")
        } catch let error as DisposableFailure {
            try expect(error == .identityChanged, "strict original-handle identityChanged refusal")
        }
    }
    check("owned staged bytes match source") {
        try expect(staged == bytes && Data(contentsOf: URL(fileURLWithPath: root + "/staged")) == bytes,
                   "actual staged bytes")
    }
    check("owned staged file is sealed 0400 before capture") {
        let info = try status("staged")
        try expect(info.st_mode & 0o7777 == 0o400, "staged mode must be 0400; observed \(String(info.st_mode & 0o7777, radix: 8))")
        try expect(info.st_mode & S_IFMT == S_IFREG && info.st_uid == getuid() && info.st_nlink == 1,
                   "exclusive ordinary owned file")
    }
    check("fresh ordinary write-open is refused") {
        errno = 0
        let writable = open(root + "/staged", O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        let failure = errno
        if writable >= 0 { close(writable) }
        try expect(writable == -1 && failure == EACCES, "ordinary write-open must fail with EACCES")
    }
    check("source bytes, mode and distinct identity preserved") {
        let input = try status("input"), output = try status("staged")
        try expect(input.st_mode & 0o7777 == 0o600 && input.st_ino != output.st_ino,
                   "source remains writable and distinct")
        try expect(Data(contentsOf: URL(fileURLWithPath: root + "/input")) == bytes, "source bytes unchanged")
    }
    check("captured handle refuses actual mode change") {
        try refusesChangedCapture("mode-change") {
            let before = try status("mode-change")
            try expect(chmod(root + "/mode-change", (before.st_mode & 0o7777) ^ 0o200) == 0,
                       "change synthetic owned mode")
        }
    }
    check("captured handle refuses ctime-only change after mode restoration") {
        try refusesChangedCapture("ctime-change") {
            let before = try status("ctime-change"), mode = before.st_mode & 0o7777
            try expect(chmod(root + "/ctime-change", mode ^ 0o200) == 0 &&
                       chmod(root + "/ctime-change", mode) == 0, "change and restore synthetic mode")
            let after = try status("ctime-change")
            try expect(before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
                       before.st_mode == after.st_mode && before.st_uid == after.st_uid &&
                       before.st_nlink == after.st_nlink && before.st_size == after.st_size &&
                       before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
                       before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                       "all strict confirmation fields except ctime unchanged")
            try expect(before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec ||
                       before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec, "real ctime change observed")
        }
    }
    check("captured handle refuses actual named replacement") {
        try refusesChangedCapture("replacement") {
            let before = try status("replacement")
            try expect(rename(root + "/replacement", root + "/retained-original") == 0,
                       "retain original synthetic file")
            try createFile(root + "/replacement", bytes, mode: before.st_mode & 0o7777)
            let after = try status("replacement")
            try expect(before.st_ino != after.st_ino, "actual replacement inode differs")
        }
    }
    try capability.revalidate()
    print("Owned image seal checks: \(count - failures)/\(count) passed; synthetic only, no native image command or guest proof")
    try expect(failures == 0, "\(failures) owned image sealing checks failed")
}
