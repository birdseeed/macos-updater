import Foundation
import Darwin
import IOKit
import AppKit
import ArtifactInspection

public struct GuestObservation: Encodable, Sendable {
    public let platformUUIDSHA256: String, user: String, home: String, hostname: String
    public let osVersion: String, osBuild: String, architecture: String
    public let uid: UInt32, effectiveUID: UInt32, consoleUID: UInt32
    public let hypervisor: Int32
}
enum GuestGuard {
    static func observe() throws -> GuestObservation {
        try observe(profile: .legacy)
    }
    static func observe(profile: DisposableTargetProfile) throws -> GuestObservation {
        let realUID = getuid(), effectiveUID = geteuid()
        guard let account = getpwuid(realUID), let homeEnvironment = ProcessInfo.processInfo.environment["HOME"] else { throw DisposableFailure.guestMismatch }
        let user = String(cString: account.pointee.pw_name), home = String(cString: account.pointee.pw_dir)
        var console = stat()
        guard lstat("/dev/console", &console) == 0 else { throw DisposableFailure.guestMismatch }
        var hv: Int32 = 0, size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.hv_vmm_present", &hv, &size, nil, 0) == 0, hv == 1 else { throw DisposableFailure.guestMismatch }
        func sys(_ name: String) throws -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 1024 else { throw DisposableFailure.guestMismatch }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { throw DisposableFailure.guestMismatch }
            return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", build = try sys("kern.osversion")
        var system = utsname(); guard uname(&system) == 0 else { throw DisposableFailure.guestMismatch }
        let architecture = withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
        var hostname = [CChar](repeating: 0, count: 256)
        guard gethostname(&hostname, hostname.count) == 0 else { throw DisposableFailure.guestMismatch }
        let host = String(decoding: hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { throw DisposableFailure.guestMismatch }; defer { IOObjectRelease(service) }
        // Raw hardware identifier remains inside this function and never enters command evidence.
        guard let property = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0),
              let uuid = property.takeRetainedValue() as? String, UUID(uuidString: uuid) != nil else { throw DisposableFailure.guestMismatch }
        let hashed = digest(Data(uuid.uppercased().utf8))
        let facts = GuestIdentityFacts(realUID: realUID, effectiveUID: effectiveUID, consoleUID: console.st_uid,
            accountName: user, accountHome: home, homeEnvironment: homeEnvironment, hypervisor: hv,
            osVersion: version, osBuild: build, architecture: architecture, hostname: host, platformUUIDSHA256: hashed)
        guard facts.matches(profile) else { throw DisposableFailure.guestMismatch }
        return .init(platformUUIDSHA256: hashed, user: user, home: home, hostname: host,
                     osVersion: version, osBuild: build, architecture: architecture, uid: realUID, effectiveUID: effectiveUID,
                     consoleUID: console.st_uid, hypervisor: hv)
    }
}
func aclEntries(_ directory: HeldDirectory, visit: (acl_entry_t) throws -> Void) throws {
    errno = 0
    guard let acl = acl_get_fd_np(directory.fd, ACL_TYPE_EXTENDED) else {
        guard errno == ENOENT else { throw DisposableFailure.unsafeMode }
        return // Darwin: this valid descriptor has no extended ACL.
    }
    defer { acl_free(UnsafeMutableRawPointer(acl)) }
    guard acl_valid(acl) == 0 else { throw DisposableFailure.unsafeMode }
    var entry: acl_entry_t?, cursor = Int32(ACL_FIRST_ENTRY.rawValue)
    while true {
        errno = 0
        let result = acl_get_entry(acl, cursor, &entry)
        if result == -1 {
            // Darwin's documented end condition after acl_valid has established a valid ACL.
            guard errno == EINVAL else { throw DisposableFailure.unsafeMode }
            return
        }
        guard result == 0, let current = entry else { throw DisposableFailure.unsafeMode }
        try visit(current); cursor = Int32(ACL_NEXT_ENTRY.rawValue)
    }
}
func requirePrivateACL(_ directory: HeldDirectory) throws {
    try aclEntries(directory) { _ in throw DisposableFailure.unsafeMode }
}
func requireTrustedAncestry(_ directory: HeldDirectory) throws {
    if let parent = directory.parent { try requireTrustedAncestry(parent) }
    let info = try directory.status()
    guard info.st_uid == 0 || info.st_uid == getuid(), safeMode(info) else { throw DisposableFailure.unsafeMode }
    try aclEntries(directory) { entry in
        var tag = ACL_UNDEFINED_TAG
        guard acl_get_tag_type(entry, &tag) == 0, tag != ACL_EXTENDED_ALLOW else { throw DisposableFailure.unsafeMode }
    }
}
public struct NativeAppObservation: Encodable, Sendable {
    public let path: String, version: String, bundleID: String, teamID: String
    public let observedAt: String
    public let commands: [CommandResult]
    public let signatureObservation: SignatureObservation
    public let architectureObservation: ArchitectureObservation
    public let manifest: ProofManifest
}
final class NativeCommands {
    var results: [CommandResult] = []
    var anchorCheck: (() throws -> Void)?
    var event: ((CommandResult) throws -> Void)?
    func run(_ executable: String, _ arguments: [String], seconds: Double = 60, output: Int = 1_048_576) throws -> CommandResult {
        let allowed: Set<String> = ["/usr/bin/codesign", "/usr/sbin/spctl",
            "/usr/bin/hdiutil", "/usr/bin/ditto", "/usr/sbin/mtree"]
        guard allowed.contains(executable), arguments.allSatisfy({ !$0.utf8.contains(0) }) else { throw DisposableFailure.notAuthorized }
        try anchorCheck?()
        var limits = InspectionLimits(); limits.commandSeconds = seconds; limits.outputBytes = output
        let result: CommandResult
        do { result = try BoundedCommandRunner().run(executable: executable, arguments: arguments, limits: limits) }
        catch { throw DisposableFailure.commandFailed }
        results.append(result); try anchorCheck?(); try event?(result)
        guard !result.timedOut else { throw DisposableFailure.commandTimedOut }
        guard !result.outputExceeded else { throw DisposableFailure.outputLimit }
        return result
    }
    func success(_ executable: String, _ arguments: [String], seconds: Double = 60, output: Int = 1_048_576,
                 failure: DisposableFailure = .commandFailed) throws -> CommandResult {
        let result = try run(executable, arguments, seconds: seconds, output: output)
        guard result.exitCode == 0 else { throw failure }; return result
    }
    func app(_ held: HeldDirectory, version: String, owner: uid_t? = getuid()) throws -> NativeAppObservation {
        try held.confirm()
        let before = try ManifestReader.read(held, owner: owner)
        let contents = try held.child("Contents"), info = try HeldFile(parent: contents, name: "Info.plist", owner: owner).data(maximum: 1_048_576)
        guard let object = try PropertyListSerialization.propertyList(from: info, options: [], format: nil) as? [String: Any],
              object["CFBundleIdentifier"] as? String == "org.mozilla.firefox", object["CFBundleExecutable"] as? String == "firefox",
              object["CFBundlePackageType"] as? String == "APPL" else { throw DisposableFailure.wrongBundle }
        guard object["CFBundleShortVersionString"] as? String == version else { throw DisposableFailure.wrongVersion }
        let executable = try HeldFile(parent: contents.child("MacOS"), name: "firefox", owner: owner)
        _ = try executable.stream(maximum: DisposableScope.maximumTotalBytes)
        let start = results.count
        func fresh() throws { try held.confirm(); try executable.confirm() }
        try fresh()
        let signature: SignatureObservation
        try anchorCheck?()
        do {
            signature = try InstalledBundleObserver.collect(appPath: held.path, appDescriptor: held.fd,
                executableDescriptor: executable.fd, infoPlist: info, pin: fixedPin(version))
        } catch let failure as InspectionFailure {
            // Keep identity/signature refusals meaningful for guest refusal cases.
            switch failure {
            case .wrongTeam: throw DisposableFailure.wrongTeam
            case .wrongBundle: throw DisposableFailure.wrongBundle
            case .wrongVersion: throw DisposableFailure.wrongVersion
            case .unsafePath: throw DisposableFailure.identityChanged
            default: throw DisposableFailure.signatureRejected
            }
        }
        try anchorCheck?()
        try fresh()
        let gatekeeper = try success("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", held.path], failure: .notarizationRejected)
        let assessment = (gatekeeper.stdout + "\n" + gatekeeper.stderr).split(separator: "\n").map(String.init)
        guard assessment.filter({ $0 == held.path + ": accepted" }).count == 1,
              assessment.filter({ $0 == "source=Notarized Developer ID" }).count == 1,
              !assessment.contains(where: { $0.localizedCaseInsensitiveContains("rejected") || $0.localizedCaseInsensitiveContains("unavailable") }) else {
            throw DisposableFailure.notarizationRejected
        }
        try fresh()
        let architectures: [String]
        do { architectures = try MachOArchitectures.inspect(fileDescriptor: executable.fd) }
        catch { throw DisposableFailure.wrongArchitecture }
        guard architectures == ["arm64", "x86_64"] else { throw DisposableFailure.wrongArchitecture }
        try fresh()
        let after = try ManifestReader.read(held, owner: owner)
        guard before == after else { throw DisposableFailure.identityChanged }
        return .init(path: held.path, version: version, bundleID: "org.mozilla.firefox", teamID: "43AQ936H96",
                     observedAt: ISO8601DateFormatter().string(from: Date()), commands: Array(results.dropFirst(start)),
                     signatureObservation: signature, architectureObservation: .init(executablePath: held.path + "/Contents/MacOS/firefox", architectures: architectures), manifest: after)
    }
}
func observeAppClosed(_ held: HeldDirectory, record: (ProcessObservationFailure) throws -> Void) throws {
    try held.confirm()
    // AppKit supplies actual running applications and their bundle URLs; process names are insufficient.
    for app in NSWorkspace.shared.runningApplications {
        if let path = app.bundleURL?.path, path.utf8.elementsEqual(held.path.utf8) { throw DisposableFailure.appRunning }
        // Kernel executable path catches a process whose bundle URL is absent.
        var bytes = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = proc_pidpath(app.processIdentifier, &bytes, UInt32(bytes.count))
        if count > 0 {
            let executable = String(decoding: bytes.prefix(Int(count)), as: UTF8.self)
            if executable.utf8.elementsEqual((held.path + "/Contents/MacOS/firefox").utf8) { throw DisposableFailure.appRunning }
        }
    }
    // Include processes that AppKit has not registered (including helper/content processes).
    errno = 0
    let required = proc_listallpids(nil, 0), requiredErrno = errno
    guard required > 0, required < 100_000 else {
        try refuseProcessObservation(.init(stage: .listAllPIDsSize, errno: requiredErrno, returnSize: required), record: record)
    }
    var pids = [pid_t](repeating: 0, count: Int(required) + 256)
    errno = 0
    let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)), countErrno = errno
    guard count > 0, count < pids.count else {
        try refuseProcessObservation(.init(stage: .listAllPIDsRead, errno: countErrno, returnSize: count), record: record)
    }
    let bundleInfo = try held.status()
    for pid in pids.prefix(Int(count)) where pid > 0 {
        guard let process = try observeProcessOwnership(pid, record: record) else { continue }
        guard process.belongs(to: getuid()) else { continue }
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        errno = 0
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count)), pathErrno = errno
        if n <= 0 {
            if kill(pid, 0) != 0 && errno == ESRCH { continue }
            try refuseProcessObservation(.init(stage: .pidPath, errno: pathErrno, returnSize: n, pid: pid, uid: process.uid), record: record)
        }
        let path = String(decoding: buffer.prefix(Int(n)), as: UTF8.self)
        if path.hasPrefix(held.path + "/") { throw DisposableFailure.appRunning }
        // These OS-observed path reads compare identity only and cannot grant authority.
        var ancestor = URL(fileURLWithPath: path).deletingLastPathComponent().path
        while ancestor != "/" && ancestor != "." {
            var info = stat()
            errno = 0
            let result = fstatat(AT_FDCWD, ancestor, &info, 0), statErrno = errno
            guard result == 0 else {
                if kill(pid, 0) != 0 && errno == ESRCH { break }
                try refuseProcessObservation(.init(stage: .ancestorStat, errno: statErrno, returnSize: result, pid: pid, uid: process.uid), record: record)
            }
            if sameIdentity(info, bundleInfo) { throw DisposableFailure.appRunning }
            ancestor = URL(fileURLWithPath: ancestor).deletingLastPathComponent().path
        }
    }
    try held.confirm()
}
