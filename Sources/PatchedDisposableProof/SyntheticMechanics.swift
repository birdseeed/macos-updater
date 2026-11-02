import Foundation
import Darwin

// Synthetic surfaces exercise the same low-level mechanics used by the guest runtime.
// They must never construct runtime guest authority, a live assessment or an installed report.
// Every path is confined, before I/O, to one exclusive synthetic root directly below
// the kernel executable's nearest .build. Caller working directory and argv[0] are irrelevant.
@_spi(Testing) public struct SyntheticLimits: Sendable {
    public let entries: Int
    public let depth: Int
    public let bytes: Int64
    public init(entries: Int = 20_000, depth: Int = 40, bytes: Int64 = 2_147_483_648) {
        self.entries = entries; self.depth = depth; self.bytes = bytes
    }
}
@_spi(Testing) public enum SyntheticSync: String, CaseIterable, Sendable {
    case fileSync, fileFullSync, directorySync, committedFileFullSync
}
@_spi(Testing) public enum SyntheticBoundary: String, CaseIterable, Sendable {
    case rootHeld, beforeFileOpen, fileHeld, beforeJournalReplace, journalReplaced, beforeExchange, afterExchange
}
@_spi(Testing) public struct SyntheticProbes {
    public var boundary: ((SyntheticBoundary) throws -> Void)?
    public var sync: ((SyntheticSync) throws -> Void)?
    public init(boundary: ((SyntheticBoundary) throws -> Void)? = nil, sync: ((SyntheticSync) throws -> Void)? = nil) {
        self.boundary = boundary; self.sync = sync
    }
}
@_spi(Testing) public struct SyntheticJournalBinding: Sendable {
    public let profile: DisposableTargetProfile
    public let runID: String, caseRoot: String
    public let device: UInt64, inode: UInt64
    public init(runID: String, caseRoot: String, device: UInt64, inode: UInt64, profile: DisposableTargetProfile = .legacy) {
        self.profile = profile
        self.runID = runID; self.caseRoot = caseRoot; self.device = device; self.inode = inode
    }
}
@_spi(Testing) public struct SyntheticCatalogueResult: Sendable {
    public let sequence: UInt64
    public let payloadSHA256: String
    public let testCatalogueTrust: Bool
    public let productionTrust: Bool
    public let freshOSValidation: Bool
    public let installationAuthorized: Bool
}
@_spi(Testing) public enum SyntheticProofFiles {
    /// Returns a held root capability usable only by these synthetic mechanics. Root is exclusive,
    /// private and physically bounded; it cannot be upgraded or passed to DisposableProof.
    public static func createRoot(path: String) throws -> SyntheticRoot {
        let (parent, name) = try syntheticLocation(path)
        let held = try parent.mkdir(name)
        return SyntheticRoot(path: path, held: held)
    }
    public static func inspect(root: String, relativePath: String, limits: SyntheticLimits = .init(),
                               probes: SyntheticProbes = .init()) throws -> ProofManifest {
        let held = try syntheticOpen(root, probes)
        return try ManifestReader.read(held.descend(relativePath), bounds: TreeBounds(entries: limits.entries, depth: limits.depth, bytes: limits.bytes))
    }
    /// Independent argument root is revalidated at every operation. Existing trees are synthetic
    /// fixture inputs only; this never adopts them as a runtime or transaction authority.
    public static func readRegular(root: String, relativePath: String, maximumBytes: Int,
                                   probes: SyntheticProbes = .init()) throws -> Data {
        try PhysicalIO.read(syntheticOpen(root, probes), relativePath, maximum: maximumBytes, hooks: probes.hooks)
    }
    public static func verifyRegular(root: String, relativePath: String, expectedLength: Int64, expectedSHA256: String) throws {
        let held = try syntheticOpen(root), (parent, name) = try held.parentOf(relativePath)
        try HeldFile(parent: parent, name: name).verify(length: expectedLength, hash: expectedSHA256)
    }
    public static func writeExclusive(root: String, relativePath: String, data: Data,
                                      probes: SyntheticProbes = .init()) throws {
        try PhysicalIO.write(syntheticOpen(root, probes), relativePath, data: data, hooks: probes.hooks)
    }
    public static func exchange(root: String, left: String, right: String,
                                probes: SyntheticProbes = .init()) throws {
        try PhysicalIO.exchange(syntheticOpen(root, probes), left, right, hooks: probes.hooks)
    }
    public static func writeJournal(root: String, bytes: Data, binding: SyntheticJournalBinding,
                                    probes: SyntheticProbes = .init()) throws {
        let held = try syntheticOpen(root, probes)
        try JournalStore.write(held, data: bytes, binding: binding.physical(held), hooks: probes.hooks)
    }
    public static func readJournal(root: String, binding: SyntheticJournalBinding) throws -> ProofState {
        let held = try syntheticOpen(root)
        return try JournalStore.read(held, binding: binding.physical(held)).state
    }
    /// Synthetic Target/Retained bundles and synthetic journal only. This cannot perform live recovery.
    public static func recoverExchange(root: String, binding: SyntheticJournalBinding, probes: SyntheticProbes = .init()) throws -> ProofRecovery {
        let held = try syntheticOpen(root, probes)
        return try SharedRecovery.recover(held, binding: binding.physical(held), target: "Target", retained: "Retained", hooks: probes.hooks)
    }
    /// Fixed TEST public trust only, ordinary durable per-root checkpoint. No caller key parameter.
    /// Injected time/version apply exclusively to the synthetic surface, never runtime authority.
    public static func verifyCatalogue(root: String, envelope: Data, now: Double, bootstrap: Bool) throws -> SyntheticCatalogueResult {
        let candidate = try TestCatalogue.accept(root: syntheticOpen(root), envelope: envelope, now: now,
                                                 os: DisposableScope.guestOS, installed: "157.0", bootstrap: bootstrap)
        return SyntheticCatalogueResult(sequence: candidate.sequence, payloadSHA256: candidate.payloadSHA256,
            testCatalogueTrust: true, productionTrust: false, freshOSValidation: false, installationAuthorized: false)
    }
}
@_spi(Testing) public final class SyntheticRoot {
    public let path: String
    private let held: HeldDirectory
    fileprivate init(path: String, held: HeldDirectory) { self.path = path; self.held = held }
    public func revalidate() throws { try held.confirm(); try held.owned(privateMode: true) }
}

private func syntheticLocation(_ path: String) throws -> (HeldDirectory, String) {
    let parts = try components(path, absolute: true)
    let executable = try components(kernelExecutable(), absolute: true)
    guard let index = executable.dropLast().lastIndex(of: ".build") else { throw DisposableFailure.notAuthorized }
    let buildParts = Array(executable[...index]), prefix = "patched-disposable-check-"
    guard parts.dropLast().elementsEqual(buildParts), let name = parts.last,
          name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil else { throw DisposableFailure.notAuthorized }
    let build = try HeldDirectory.absolute("/" + buildParts.joined(separator: "/"))
    return (build, name)
}
private func syntheticOpen(_ path: String, _ probes: SyntheticProbes = .init()) throws -> HeldDirectory {
    let (build, name) = try syntheticLocation(path), root = try build.child(name)
    try root.owned(privateMode: true); try probes.hooks.hit("rootHeld"); try root.confirm()
    return root
}
private extension SyntheticProbes {
    var hooks: FileHooks {
        FileHooks(boundary: { name in if let event = SyntheticBoundary(rawValue: name) { try boundary?(event) } },
                  sync: { name in if let event = SyntheticSync(rawValue: name) { try sync?(event) } })
    }
}
private extension SyntheticJournalBinding {
    func physical(_ held: HeldDirectory) throws -> JournalBinding {
        let binding = try JournalBinding(root: held, run: runID, caseRoot: caseRoot, origin: "synthetic", profile: profile)
        guard binding.device == device, binding.inode == inode else { throw DisposableFailure.journalMismatch }
        return binding
    }
}

// The copy, ACL and lease regressions were added after native review, not as Phase A red cases.
@_spi(Testing) public enum SyntheticNativeBoundaries {
    /// Executes the real native copy helper for bounded synthetic bytes only. Callbacks
    /// observe the exclusive destination and completed command; they grant no guest authority.
    public static func copyWithDitto(root: String, source: String, destination: String,
                                     beforeCopy: @escaping () throws -> Void = {},
                                     afterCopy: @escaping () throws -> Void = {}) throws -> ProofManifest {
        _ = try components(destination)
        guard !destination.contains("/") else { throw DisposableFailure.unsafePath }
        let held = try syntheticOpen(root), input = try held.descend(source)
        try requirePrivateACL(held)
        let manifest = try ManifestReader.read(input, bounds: TreeBounds(entries: 100, depth: 8, bytes: 1_048_576))
        let commands = NativeCommands()
        var started = false
        commands.anchorCheck = {
            try held.confirm(); try held.owned(privateMode: true)
            if !started { started = true; try beforeCopy() }
        }
        commands.event = { _ in try afterCopy() }
        let copy = try nativeDittoBundle(input, parent: held, name: destination, expected: manifest, commands: commands)
        return try ManifestReader.read(copy)
    }
    /// Stages synthetic bytes through the owned-image copier without constructing image or guest authority.
    /// The callback runs after capture; the original handle must still confirm before bytes can return.
    public static func stageImage(root: String, source: String, destination: String,
                                  afterCapture: () throws -> Void = {}) throws -> Data {
        _ = try components(destination)
        guard !destination.contains("/") else { throw DisposableFailure.unsafePath }
        let held = try syntheticOpen(root), (parent, name) = try held.parentOf(source)
        let sourceFile = try HeldFile(parent: parent, name: name)
        guard sourceFile.captured.st_size <= 1_048_576 else { throw DisposableFailure.treeLimit }
        let staged = try stageOwnedImage(sourceFile, to: held, name: destination)
        try afterCapture()
        return try staged.data(maximum: 1_048_576)
    }
    public static func validatePrivateACL(root: String) throws {
        try requirePrivateACL(syntheticOpen(root))
    }
    public static func copy(root: String, source: String, destination: String,
                            witness: ((String, Int64, Int64, UInt64) throws -> Void)? = nil) throws -> ProofManifest {
        let held = try syntheticOpen(root)
        let copy = try copyBundle(held.descend(source), into: held, name: destination, witness: witness)
        return try ManifestReader.read(copy)
    }
    public static func closeLease(root: String, relativeFile: String) throws -> [Bool] {
        let independent = try syntheticOpen(root), closing = try syntheticOpen(root)
        let (directory, name) = try closing.parentOf(relativeFile)
        let file = try HeldFile(parent: directory, name: name)
        let descriptors = [closing.fd, directory.fd, file.fd]
        closing.closeOwnedChain()
        let closed = descriptors.map { fcntl($0, F_GETFD) == -1 && errno == EBADF }
        // Repeated closure must not close another live lease or a subsequently reused fd.
        let fresh = try syntheticOpen(root)
        closing.closeOwnedChain(); try fresh.confirm(); try independent.confirm()
        return closed + [closing.fd == -1, directory.fd == -1, file.fd == -1]
    }
}
