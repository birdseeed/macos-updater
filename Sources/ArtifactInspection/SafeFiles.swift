import Foundation
import CryptoKit
import Darwin

// Descriptor walks retain each ancestor and never follow user-supplied symlinks.
enum SafeFiles {
    static func openPath(_ path: String, directory: Bool = false) throws -> Int32 {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.contains("//"), path != "/" else {
            throw InspectionFailure.unsafePath
        }
        let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw InspectionFailure.unsafePath }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw InspectionFailure.unsafePath }
        for (index, part) in parts.enumerated() {
            let next = openat(fd, String(part), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK |
                (directory || index < parts.count - 1 ? O_DIRECTORY : 0))
            close(fd)
            guard next >= 0 else { throw InspectionFailure.unsafePath }
            fd = next
        }
        return fd
    }
    static func regular(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw InspectionFailure.notRegularFile }
        return info
    }
    static func privateDirectory(_ path: String) throws -> Int32 {
        let fd = try openPath(path, directory: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else {
            close(fd); throw InspectionFailure.unsafePath
        }
        return fd
    }
    static func read(_ path: String, maximum: Int) throws -> Data {
        let fd = try openPath(path); defer { close(fd) }
        let info = try regular(fd)
        guard info.st_size >= 0, info.st_size <= maximum else { throw InspectionFailure.outputLimit }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw InspectionFailure.unsafePath }
            if count == 0 { return data }
            guard data.count + count <= maximum else { throw InspectionFailure.outputLimit }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
    static func stream(_ fd: Int32, length: Int64, digest: String, copyTo: Int32? = nil) throws {
        try ArtifactSizePolicy.validateExpectedLength(length)
        guard digest.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw InspectionFailure.invalidMetadata }
        let info = try regular(fd)
        guard info.st_size == length else { throw InspectionFailure.lengthMismatch }
        var hash = SHA256(); var count: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 { if errno == EINTR { continue }; throw InspectionFailure.unsafePath }
            if n == 0 { break }
            do { count = try ArtifactSizePolicy.adding(Int64(n), to: count, expectedLength: length) }
            catch { throw InspectionFailure.lengthMismatch }
            let bytes = Data(buffer.prefix(n)); hash.update(data: bytes)
            if let output = copyTo { try write(bytes, fd: output) }
        }
        try ArtifactSizePolicy.validateComplete(receivedBytes: count, expectedLength: length)
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { throw InspectionFailure.digestMismatch }
    }
    static func write(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 { if errno == EINTR { continue }; throw InspectionFailure.unsafePath }
                guard n > 0 else { throw InspectionFailure.unsafePath }; offset += n
            }
        }
    }
    // f_bavail is the space available to this unprivileged process, on the
    // opened destination volume. Never infer capacity from the source or /tmp.
    static func availableCapacity(_ directory: Int32) throws -> Int64? {
        var volume = statfs()
        guard fstatfs(directory, &volume) == 0, volume.f_bsize > 0,
              let blocks = Int64(exactly: volume.f_bavail), blocks >= 0 else {
            throw InspectionFailure.downloadLimit
        }
        let (bytes, overflow) = blocks.multipliedReportingOverflow(by: Int64(volume.f_bsize))
        guard !overflow else { throw InspectionFailure.downloadLimit }
        return bytes
    }
    static func preflight(_ directory: Int32, length: Int64,
                          capacity: (Int32) throws -> Int64? = availableCapacity) throws {
        try ArtifactSizePolicy.validateExpectedLength(length)
        try ArtifactSizePolicy.validateStagingCapacity(availableBytes: capacity(directory), expectedLength: length)
    }
    static func stageImage(path: String, pin: TargetPin, workspace: String) throws -> VerifiedImage {
        let input = try openPath(path); defer { close(input) }
        let directory = try privateDirectory(workspace); defer { close(directory) }
        try preflight(directory, length: pin.byteLength)
        let writer = try StagedImageWriter(directory: directory)
        defer { writer.closeWriter() }
        try stream(input, length: pin.byteLength, digest: pin.sha256, copyTo: writer.descriptor)
        return try writer.finish(directory: directory, pin: pin)
    }
    static func stage(path: String, pin: TargetPin, workspace: String,
                      capacity: (Int32) throws -> Int64? = availableCapacity) throws -> String {
        let input = try openPath(path); defer { close(input) }
        let directory = try privateDirectory(workspace); defer { close(directory) }
        try preflight(directory, length: pin.byteLength, capacity: capacity)
        let output = openat(directory, "artifact.dmg", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw InspectionFailure.unsafePath }
        defer { close(output) }
        try stream(input, length: pin.byteLength, digest: pin.sha256, copyTo: output)
        guard fsync(output) == 0, fchmod(output, 0o400) == 0 else { throw InspectionFailure.unsafePath }
        let staged = workspace + "/artifact.dmg"
        try ArtifactBytes.verify(path: staged, expectedSHA256: pin.sha256, expectedLength: pin.byteLength)
        return staged
    }
    static func makeWorkspace() throws -> String {
        guard let physical = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw InspectionFailure.unsafePath }
        defer { free(physical) }
        var template = Array((String(cString: physical) + "/patched-artifact-XXXXXXXX").utf8CString)
        guard let created = mkdtemp(&template) else { throw InspectionFailure.unsafePath }
        let path = String(cString: created)
        let fd = try privateDirectory(path); close(fd)
        return path
    }
}
