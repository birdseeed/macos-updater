import Foundation
import Darwin
import ArtifactInspection

func mountedPaths() throws -> Set<String> {
    var pointer: UnsafeMutablePointer<statfs>?
    let count = getmntinfo(&pointer, MNT_NOWAIT)
    guard count > 0, let pointer else { throw DisposableFailure.cleanupFailed }
    return Set((0..<Int(count)).map { index in
        var name = pointer[index].f_mntonname
        return withUnsafePointer(to: &name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
    })
}
func requireSpace(_ run: HeldDirectory, nextBytes: Int64) throws -> [String: Int64] {
    var filesystem = statfs()
    guard fstatfs(run.fd, &filesystem) == 0 else { throw DisposableFailure.persistenceFailed }
    let free = Int64(filesystem.f_bavail) * Int64(filesystem.f_bsize)
    let mounts = try mountedPaths()
    var entries = 0, retained: Int64 = 0
    func count(_ root: HeldDirectory) throws {
        for name in try root.names(maximum: 100_000) {
            entries += 1; guard entries <= 100_000, let info = try root.named(name) else { throw DisposableFailure.treeLimit }
            if mounts.contains(root.path + "/" + name) { continue }
            if info.st_mode & S_IFMT == S_IFDIR { try count(root.child(name)) }
            else if info.st_mode & S_IFMT == S_IFREG { guard info.st_size >= 0 else { throw DisposableFailure.unsafePath }; retained += info.st_size }
            else if info.st_mode & S_IFMT != S_IFLNK { throw DisposableFailure.specialFile }
        }
    }
    try count(run)
    let required = max(nextBytes, max(0, 22_000_000_000 - retained)) + 2_147_483_648
    guard free >= required else { throw DisposableFailure.insufficientSpace }
    return ["availableBytes": free, "retainedLogicalBytes": retained, "requiredBytes": required, "nextCopyBytes": nextBytes]
}
func streamCopy(_ source: HeldFile, to directory: HeldDirectory, name: String,
                witness: ((Int64, Int64, UInt64) throws -> Void)? = nil, metadata: Bool = false,
                sealReadOnly: Bool = false) throws {
    try source.confirm(); try directory.confirm()
    let fd = openat(directory.fd, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw errno == EEXIST ? DisposableFailure.existingRoot : .persistenceFailed }; defer { close(fd) }
    var original = stat(); guard fstat(fd, &original) == 0, fchmod(fd, 0o600) == 0 else { throw DisposableFailure.persistenceFailed }
    var copied: Int64 = 0, witnessed = false
    _ = try source.stream(maximum: DisposableScope.maximumTotalBytes) { bytes in
        try directory.confirm(); try source.confirm()
        guard let named = try directory.named(name), sameIdentity(named, original), named.st_nlink == 1 else { throw DisposableFailure.identityChanged }
        try PhysicalIO.writeAll(fd, bytes); copied += Int64(bytes.count)
        if !witnessed && copied > 0 && copied < source.captured.st_size, let witness {
            try PhysicalIO.syncFile(fd); try directory.syncDirectory()
            try witness(copied, source.captured.st_size, original.st_ino); witnessed = true
        }
    }
    guard copied == source.captured.st_size else { throw DisposableFailure.lengthMismatch }
    if metadata {
        guard fcopyfile(source.fd, fd, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0,
              fchmod(fd, permissions(source.captured)) == 0 else { throw DisposableFailure.persistenceFailed }
    }
    if sealReadOnly {
        guard fchmod(fd, 0o400) == 0 else { throw DisposableFailure.persistenceFailed }
    }
    try PhysicalIO.syncFile(fd); try directory.syncDirectory(); try source.confirm()
    guard let named = try directory.named(name), sameIdentity(named, original) else { throw DisposableFailure.identityChanged }
}
func copyBundle(_ source: HeldDirectory, into parent: HeldDirectory, name: String,
                witness: ((String, Int64, Int64, UInt64) throws -> Void)? = nil) throws -> HeldDirectory {
    let sourceManifest = try ManifestReader.read(source)
    let destination = try parent.mkdir(name)
    var witnessSent = false
    func copy(_ from: HeldDirectory, _ to: HeldDirectory, relative: String) throws {
        for leaf in try from.names(maximum: DisposableScope.maximumEntries) {
            guard let info = try from.named(leaf) else { throw DisposableFailure.identityChanged }
            let child = relative.isEmpty ? leaf : relative + "/" + leaf
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                let next = try to.mkdir(leaf); try copy(from.child(leaf), next, relative: child)
            case S_IFREG:
                let file = try HeldFile(parent: from, name: leaf)
                try streamCopy(file, to: to, name: leaf, witness: { copied, total, inode in
                    if !witnessSent, let witness { witnessSent = true; try witness(child, copied, total, inode) }
                }, metadata: true)
            case S_IFLNK:
                guard let entry = sourceManifest.entries.first(where: { $0.path.utf8.elementsEqual(child.utf8) }) else { throw DisposableFailure.manifestMismatch }
                try from.confirm(); try to.confirm()
                guard symlinkat(entry.link, to.fd, leaf) == 0 else { throw DisposableFailure.persistenceFailed }
                // No data follows these descriptors; failure to preserve metadata refuses the stage.
                let a = openat(from.fd, leaf, O_RDONLY | O_SYMLINK | O_CLOEXEC)
                let b = openat(to.fd, leaf, O_RDONLY | O_SYMLINK | O_CLOEXEC)
                guard a >= 0, b >= 0 else { if a >= 0 { close(a) }; if b >= 0 { close(b) }; throw DisposableFailure.persistenceFailed }
                let result = fcopyfile(a, b, nil, copyfile_flags_t(COPYFILE_METADATA)); close(a); close(b)
                guard result == 0 else { throw DisposableFailure.persistenceFailed }
                try to.syncDirectory()
            default: throw DisposableFailure.specialFile
            }
        }
        try from.confirm(); try to.confirm()
        guard fcopyfile(from.fd, to.fd, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0,
              fchmod(to.fd, permissions(from.captured)) == 0, fsync(to.fd) == 0 else { throw DisposableFailure.persistenceFailed }
        // Metadata intentionally changes the new directory's mode. Reopen from its held parent
        // after this function returns instead of accepting a stale captured identity/mode.
    }
    try copy(source, destination, relative: "")
    let completed = try parent.child(name)
    guard try ManifestReader.read(source) == sourceManifest, try ManifestReader.read(completed) == sourceManifest else {
        throw DisposableFailure.manifestMismatch
    }
    return completed
}
func stageOwnedImage(_ source: HeldFile, to directory: HeldDirectory, name: String) throws -> HeldFile {
    // Seal on the exclusive copy descriptor before flush, closure and lasting identity capture.
    // Native image verification must not add a checksum cache to the held container.
    try streamCopy(source, to: directory, name: name, sealReadOnly: true)
    let staged = try HeldFile(parent: directory, name: name)
    guard permissions(staged.captured) == 0o400 else { throw DisposableFailure.unsafeMode }
    return staged
}
final class OwnedImage {
    let profile: DisposableTargetProfile
    let directory: HeldDirectory, file: HeldFile, version: String
    init(incoming: HeldDirectory, input: String, work: HeldDirectory, version: String, profile: DisposableTargetProfile = .legacy, space: () throws -> Void) throws {
        self.profile = profile
        let pin = try fixedPin(version), inputFile = try HeldFile(parent: incoming, name: input)
        try inputFile.verify(length: pin.byteLength, hash: pin.sha256)
        try space()
        let name = "held-" + version + "-" + UUID().uuidString + ".dmg"
        let staged = try stageOwnedImage(inputFile, to: work, name: name)
        self.directory = work; self.file = staged; self.version = version
        try file.verify(length: pin.byteLength, hash: pin.sha256)
    }
    var path: String { directory.path + "/" + file.name }
    func confirm() throws { let pin = try fixedPin(version); try file.verify(length: pin.byteLength, hash: pin.sha256) }
    func withMount<T>(commands: NativeCommands, _ body: (HeldDirectory) throws -> T) throws -> T {
        try confirm()
        _ = try commands.success("/usr/bin/hdiutil", ["verify", path], seconds: 180)
        let name = "Mount-" + UUID().uuidString, mount = try directory.mkdir(name)
        try requirePrivateACL(mount)
        let marker: [String: Any] = ["schemaVersion": 1, "kind": "patched-owned-mount-v1",
            "guestUUIDSHA256": profile.guestUUIDSHA256, "path": mount.path, "image": path,
            "parentDevice": identity(directory.captured).0, "parentInode": directory.captured.st_ino, "mountInode": mount.captured.st_ino]
        try PhysicalIO.write(directory, name + ".json", data: encodeJSON(marker))
        var attempted = false
        func detach() throws {
            if try mountedPaths().contains(mount.path) {
                let raw = try commands.success("/usr/bin/hdiutil", ["info", "-plist"], output: 1_048_576)
                guard let info = try PropertyListSerialization.propertyList(from: Data(raw.stdout.utf8), options: [], format: nil) as? [String: Any],
                      let images = info["images"] as? [[String: Any]],
                      images.filter({ image in
                          image["image-path"] as? String == path &&
                          ((image["system-entities"] as? [[String: Any]]) ?? []).contains { $0["mount-point"] as? String == mount.path }
                      }).count == 1 else { throw DisposableFailure.cleanupFailed }
                _ = try commands.success("/usr/bin/hdiutil", ["detach", mount.path], seconds: 60, failure: .cleanupFailed)
            }
            guard !(try mountedPaths()).contains(mount.path) else { throw DisposableFailure.cleanupFailed }
            try mount.confirm(); try confirm()
        }
        do {
            attempted = true
            let attachment = try commands.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-plist", "-mountpoint", mount.path, path], seconds: 180)
            guard attachment.exitCode == 0 else { throw DisposableFailure.invalidMount }
            _ = try ReadOnlyMount.validateAttachment(Data(attachment.stdout.utf8), ownedMountPath: mount.path)
            func useMountedPayload() throws -> T {
                let mounted = try HeldDirectory.absolute(mount.path)
                defer { mounted.closeOwnedChain() }
                var filesystem = statfs()
                guard fstatfs(mounted.fd, &filesystem) == 0, filesystem.f_flags & UInt32(MNT_RDONLY) != 0,
                      try mountedPaths().contains(mount.path) else { throw DisposableFailure.invalidMount }
                try confirm()
                return try body(mounted)
            }
            // Both callers return only Void or a copied Source rooted outside the mount.
            // The callback's mounted directory descriptors are released before ordinary detach.
            let value = try useMountedPayload()
            try detach(); return value
        } catch {
            let original = error
            if original as? DisposableFailure == .cleanupFailed { throw original }
            if attempted {
                do { try detach() } catch { throw DisposableFailure.cleanupFailed }
            }
            throw original
        }
    }
}
