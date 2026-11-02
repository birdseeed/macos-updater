import Foundation
import Darwin

// A retained read-only object, not an assertion of immutable storage against a
// hostile same-UID process holding a writable alias. No pathname is reopened.
final class VerifiedImage {
    static let childDescriptor: Int32 = 198
    let operand = "/dev/fd/198"
    private(set) var descriptor: Int32
    private let device: dev_t
    private let inode: ino_t
    private let length: off_t
    private let lock = NSLock()

    private init(descriptor: Int32, info: stat) {
        self.descriptor = descriptor
        device = info.st_dev; inode = info.st_ino; length = info.st_size
    }
    // Ownership transfers only on success. A throwing validation leaves closing
    // to the caller, avoiding ambiguous partially-initialised object ownership.
    static func acquire(owning descriptor: Int32, pin: TargetPin) throws -> VerifiedImage {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, flags & O_ACCMODE == O_RDONLY,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw InspectionFailure.unsafePath }
        let info = try SafeFiles.regular(descriptor)
        guard lseek(descriptor, 0, SEEK_SET) == 0 else { throw InspectionFailure.unsafePath }
        try SafeFiles.stream(descriptor, length: pin.byteLength, digest: pin.sha256)
        guard lseek(descriptor, 0, SEEK_SET) == 0 else { throw InspectionFailure.unsafePath }
        return VerifiedImage(descriptor: descriptor, info: info)
    }
    deinit { closeImage() }
    func closeImage() {
        lock.lock(); defer { lock.unlock() }
        if descriptor >= 0 { let fd = descriptor; descriptor = -1; close(fd) }
    }
    var byteLength: Int64 { Int64(length) }
    // Duplicates only the already verified object. pread on this duplicate never
    // changes the open-file description's shared offset.
    func duplicateLoopbackReader() throws -> VerifiedImageReader {
        lock.lock(); defer { lock.unlock() }
        let reader = VerifiedImageReader(descriptor: descriptor, device: device, inode: inode, length: length)
        try reader.validate()
        let duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        guard duplicate >= 0 else { throw InspectionFailure.unsafePath }
        let owned = VerifiedImageReader(descriptor: duplicate, device: device, inode: inode, length: length)
        do { try owned.validate(); return owned }
        catch { close(duplicate); throw error }
    }
    func run(source: LoopbackImageSource, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        lock.lock(); defer { lock.unlock() }
        guard source.isOwned(by: self), source.nativeAttachAllowed(executable: executable, arguments: arguments) else {
            throw InspectionFailure.invalidMetadata
        }
        try VerifiedImageReader(descriptor: descriptor, device: device, inode: inode, length: length).validate()
        return try runBounded(executable: executable, arguments: arguments, limits: limits)
    }
    func run(executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        lock.lock(); defer { lock.unlock() }
        guard descriptor >= 0, arguments.contains(operand),
              arguments.filter({ $0.hasPrefix("/dev/fd/") }).allSatisfy({ $0 == operand }) else {
            throw InspectionFailure.invalidMetadata
        }
        let info = try SafeFiles.regular(descriptor)
        guard info.st_dev == device, info.st_ino == inode, info.st_size == length,
              fcntl(descriptor, F_GETFL) & O_ACCMODE == O_RDONLY,
              lseek(descriptor, 0, SEEK_SET) == 0 else { throw InspectionFailure.unsafePath }
        return try runBounded(executable: executable, arguments: arguments, limits: limits, imageDescriptor: descriptor)
    }
    static func borrowing(_ descriptor: Int32, pin: TargetPin) throws -> VerifiedImage {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, flags & O_ACCMODE == O_RDONLY else { throw InspectionFailure.unsafePath }
        _ = try SafeFiles.regular(descriptor)
        let owned = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        guard owned >= 0 else { throw InspectionFailure.unsafePath }
        do { return try VerifiedImage.acquire(owning: owned, pin: pin) }
        catch { close(owned); throw error }
    }
}

// Value metadata carries no productive command authority. Only VerifiedImage
// creates the duplicate; its owner closes it after the worker has finished.
struct VerifiedImageReader {
    let descriptor: Int32
    let device: dev_t
    let inode: ino_t
    let length: off_t
    func validate() throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard descriptor >= 0, flags >= 0, flags & O_ACCMODE == O_RDONLY else { throw InspectionFailure.unsafePath }
        let info = try SafeFiles.regular(descriptor)
        guard info.st_dev == device, info.st_ino == inode, info.st_size == length else { throw InspectionFailure.unsafePath }
    }
    func read(offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count > 0, count <= 65536, offset <= Int64(length),
              Int64(count) <= Int64(length) - offset else { throw InspectionFailure.unsafePath }
        var bytes = [UInt8](repeating: 0, count: count)
        var filled = 0
        var attempts = 0
        while filled < count {
            attempts += 1
            guard attempts <= 16 else { throw InspectionFailure.unsafePath }
            try validate()
            let n = bytes.withUnsafeMutableBytes {
                pread(descriptor, $0.baseAddress!.advanced(by: filled), count - filled, off_t(offset + Int64(filled)))
            }
            let interrupted = n < 0 && errno == EINTR
            try validate()
            if interrupted { continue }
            guard n > 0 else { throw InspectionFailure.unsafePath }
            filled += n
        }
        return Data(bytes)
    }
}

// The only writable staging owner. Settling it invalidates the stored fd before
// closing, so a late receiver callback cannot write to a recycled descriptor.
final class StagedImageWriter {
    private(set) var descriptor: Int32
    init(directory: Int32) throws {
        descriptor = openat(directory, "artifact.dmg", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw InspectionFailure.unsafePath }
    }
    deinit { closeWriter() }
    func closeWriter() {
        if descriptor >= 0 { let fd = descriptor; descriptor = -1; close(fd) }
    }
    func write(_ data: Data) throws {
        guard descriptor >= 0 else { throw InspectionFailure.unsafePath }
        try SafeFiles.write(data, fd: descriptor)
    }
    func sync() throws {
        guard descriptor >= 0, fsync(descriptor) == 0, fchmod(descriptor, 0o400) == 0 else {
            throw InspectionFailure.unsafePath
        }
    }
    func finish(directory: Int32, pin: TargetPin) throws -> VerifiedImage {
        defer { closeWriter() }
        try sync()
        let written = try SafeFiles.regular(descriptor)
        let reader = openat(directory, "artifact.dmg", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard reader >= 0 else { throw InspectionFailure.unsafePath }
        do {
            let retained = try SafeFiles.regular(reader)
            guard retained.st_dev == written.st_dev, retained.st_ino == written.st_ino else {
                throw InspectionFailure.unsafePath
            }
            // Drop our sole writer and name before hashing the retained reader.
            closeWriter()
            guard unlinkat(directory, "artifact.dmg", 0) == 0 else { throw InspectionFailure.unsafePath }
            return try VerifiedImage.acquire(owning: reader, pin: pin)
        } catch { close(reader); throw error }
    }
}

@_spi(Testing) public final class VerifiedImageFixtureHandle {
    private let image: VerifiedImage
    fileprivate init(_ image: VerifiedImage) { self.image = image }
    public var descriptor: Int32 { image.descriptor }
    public var operand: String { image.operand }
    public func withLoopbackSource<T>(limits: LoopbackImageFixtureLimits = .init(),
                                      configurationGate: LoopbackImageFixtureConfigurationGate? = nil,
                                      body: (LoopbackImageFixtureSource) throws -> T) throws -> T {
        let source = try LoopbackImageSource.fixture(image: image, limits: limits, configurationGate: configurationGate)
        do {
            let value = try body(LoopbackImageFixtureSource(source))
            try source.stop()
            return value
        } catch {
            let original = error
            try source.stop()
            throw original
        }
    }
    public func run(executable: String, arguments: [String], limits: InspectionLimits = .init()) throws -> CommandResult {
        try image.run(executable: executable, arguments: arguments, limits: limits)
    }
}

// Historical descriptor-command fixture policy and explicit fd runner allowlist.
// Productive mounting uses LoopbackImageSource instead. Shape alone establishes
// neither descriptor compatibility nor image authority.
func nativeImageAttachArguments(mountPath: String) throws -> [String] {
    guard mountPath.utf8.count < Int(MAXPATHLEN), safeEvidencePath(mountPath) else {
        throw InspectionFailure.unsafePath
    }
    return ["attach", "-kernel", "-readonly", "-nobrowse", "-plist", "-mountpoint", mountPath, "/dev/fd/198"]
}
func nativeImageAttachAllowed(executable: String, arguments: [String]) -> Bool {
    guard executable == "/usr/bin/hdiutil", arguments.count == 8,
          let canonical = try? nativeImageAttachArguments(mountPath: arguments[6]) else { return false }
    return arguments == canonical
}

@_spi(Testing) public enum VerifiedImageFixtures {
    // These expose command shape only and cannot manufacture image authority.
    public static func nativeAttachArguments(mountPath: String) throws -> [String] {
        try nativeImageAttachArguments(mountPath: mountPath)
    }
    public static func nativeAttachAllowed(executable: String, arguments: [String]) -> Bool {
        nativeImageAttachAllowed(executable: executable, arguments: arguments)
    }
    public static func withLocalImage<T>(path: String, pin: TargetPin, workspace: String,
                                         body: (VerifiedImageFixtureHandle) throws -> T) throws -> T {
        let image = try SafeFiles.stageImage(path: path, pin: pin, workspace: workspace)
        defer { image.closeImage() }
        return try body(VerifiedImageFixtureHandle(image))
    }
    public static func withDownloadedImage<T>(pin: TargetPin, chunks: [Data], workspace: String,
                                              body: (VerifiedImageFixtureHandle) throws -> T) throws -> T {
        let image = try downloadImageFixture(pin: pin, chunks: chunks, workspace: workspace)
        defer { image.closeImage() }
        return try body(VerifiedImageFixtureHandle(image))
    }
    public static func withDescriptor<T>(descriptor: Int32, pin: TargetPin,
                                         body: (VerifiedImageFixtureHandle) throws -> T) throws -> T {
        let image = try VerifiedImage.borrowing(descriptor, pin: pin)
        defer { image.closeImage() }
        return try body(VerifiedImageFixtureHandle(image))
    }
}

// Only this internal capability may carry the retained object into OS tools.
protocol ImageCommandRunning: InspectionCommandRunning {
    func run(image: VerifiedImage, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult
    func run(image: VerifiedImage, source: LoopbackImageSource, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult
}
extension BoundedCommandRunner: ImageCommandRunning {
    func run(image: VerifiedImage, source: LoopbackImageSource, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        try image.run(source: source, executable: executable, arguments: arguments, limits: limits)
    }
    func run(image: VerifiedImage, executable: String, arguments: [String], limits: InspectionLimits) throws -> CommandResult {
        let verify = executable == "/usr/bin/hdiutil" && arguments == ["verify", image.operand]
        let attach = nativeImageAttachAllowed(executable: executable, arguments: arguments)
        let signature = executable == "/usr/bin/codesign" && arguments == ["--verify", "--deep", "--strict", image.operand]
        let gatekeeper = executable == "/usr/sbin/spctl" && arguments == ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", image.operand]
        guard verify || attach || signature || gatekeeper else { throw InspectionFailure.invalidMetadata }
        return try image.run(executable: executable, arguments: arguments, limits: limits)
    }
}
