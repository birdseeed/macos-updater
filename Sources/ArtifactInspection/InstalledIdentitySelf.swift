import Foundation
import Darwin
import MachO

/// Authenticates the physical current main executable, rather than a name from
/// argv, PATH or the environment. This is not Developer ID validation or proof
/// against same-user process injection or mutation of already-loaded pages.
internal final class InstalledIdentitySelf: InstalledIdentityChildSelection {
    private struct Held {
        let descriptor: Int32
        let stamp: InstalledIdentityStamp
        let parent: Int32?
        let name: String
    }
    let executable: String
    let arguments = ["--patched-installed-identity-worker-v1"]
    private var held: [Held] = []
    private var plist = Data()
    private var plistDescriptor: Int32 = -1

    private init(executable: String) { self.executable = executable }
    deinit { for value in held { close(value.descriptor) } }

    static func capture() throws -> InstalledIdentitySelf {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = path.withUnsafeMutableBytes {
            proc_pidpath(getpid(), $0.baseAddress, UInt32($0.count))
        }
        guard count > 0, Int(count) < path.count, let zero = path.firstIndex(of: 0), zero > 0 else {
            throw InspectionFailure.unsafePath
        }
        let bytes = path.prefix(zero).map { UInt8(bitPattern: $0) }
        guard let executable = String(bytes: bytes, encoding: .utf8), executable.utf8.count <= 4096,
              executable.hasPrefix("/"), !executable.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw InspectionFailure.unsafePath
        }
        let parts = executable.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, Array(parts.suffix(4)) == ["PatchedApp.app", "Contents", "MacOS", "PatchedApp"],
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= Int(NAME_MAX) }) else {
            throw InspectionFailure.unsafePath
        }
        let own = InstalledIdentitySelf(executable: executable)
        let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        let root = Darwin.open("/", directoryFlags)
        guard root >= 0 else { throw InspectionFailure.unsafePath }
        do {
            own.held.append(Held(descriptor: root,
                stamp: try InstalledIdentityStamp(descriptor: root, type: S_IFDIR), parent: nil, name: "/"))
        } catch { close(root); throw error }
        for (index, name) in parts.enumerated() {
            let parent = own.held.last!.descriptor
            let directory = index < parts.count - 1
            let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (directory ? O_DIRECTORY : 0))
            guard fd >= 0 else { throw InspectionFailure.unsafePath }
            do {
                own.held.append(Held(descriptor: fd,
                    stamp: try InstalledIdentityStamp(descriptor: fd, type: directory ? S_IFDIR : S_IFREG),
                    parent: parent, name: name))
            } catch { close(fd); throw error }
        }
        guard let leaf = own.held.last, leaf.stamp.links == 1, leaf.stamp.mode & 0o111 != 0 else {
            throw InspectionFailure.unsafePath
        }
        // Query the vnode backing the current mapped main Mach-O header, using
        // SDK structs and constants. Names alone do not authenticate a worker.
        guard let header = _dyld_get_image_header(0) else { throw InspectionFailure.unsafePath }
        let address = UInt64(UInt(bitPattern: header))
        var region = proc_regionwithpathinfo()
        let received = withUnsafeMutablePointer(to: &region) {
            proc_pidinfo(getpid(), PROC_PIDREGIONPATHINFO, address, $0, Int32(MemoryLayout<proc_regionwithpathinfo>.size))
        }
        let mapped = region.prp_prinfo
        let vnode = region.prp_vip.vip_vi.vi_stat
        guard Int(received) == MemoryLayout<proc_regionwithpathinfo>.size,
              mapped.pri_address <= address, address - mapped.pri_address < mapped.pri_size,
              vnode.vst_dev == leaf.stamp.device, vnode.vst_ino == leaf.stamp.inode,
              UInt32(vnode.vst_mode) & UInt32(S_IFMT) == UInt32(S_IFREG) else {
            throw InspectionFailure.unsafePath
        }
        // Contents is held two entries before the executable, including root.
        let contents = own.held[own.held.count - 3].descriptor
        let fd = openat(contents, "Info.plist", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw InspectionFailure.unsafePath }
        do {
            own.held.append(Held(descriptor: fd,
                stamp: try InstalledIdentityStamp(descriptor: fd, type: S_IFREG), parent: contents, name: "Info.plist"))
        } catch { close(fd); throw error }
        own.plistDescriptor = fd
        own.plist = try own.readPlist()
        guard let fields = try PropertyListSerialization.propertyList(from: own.plist, options: [], format: nil) as? [String: Any],
              fields["CFBundleExecutable"] as? String == "PatchedApp",
              fields["CFBundlePackageType"] as? String == "APPL" else { throw InspectionFailure.unsafePath }
        try own.confirm()
        return own
    }

    private func readPlist() throws -> Data {
        let stamp = try InstalledIdentityStamp(descriptor: plistDescriptor, type: S_IFREG)
        guard stamp.links == 1, stamp.size > 0, stamp.size <= 1_048_576 else { throw InspectionFailure.unsafePath }
        var bytes = Data(repeating: 0, count: Int(stamp.size))
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes {
                pread(plistDescriptor, $0.baseAddress! + offset, min(16_384, $0.count - offset), off_t(offset))
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw InspectionFailure.unsafePath }
            offset += count
        }
        return bytes
    }

    func confirm() throws {
        for value in held {
            var current = stat(), named = stat()
            guard fstat(value.descriptor, &current) == 0, InstalledIdentityStamp(current) == value.stamp else {
                throw InspectionFailure.unsafePath
            }
            let status: Int32
            if let parent = value.parent { status = fstatat(parent, value.name, &named, AT_SYMLINK_NOFOLLOW) }
            else { status = lstat("/", &named) }
            guard status == 0, InstalledIdentityStamp(named) == value.stamp else { throw InspectionFailure.unsafePath }
        }
        guard try readPlist() == plist else { throw InspectionFailure.unsafePath }
        // Plist reading also falls within the held physical observation window.
        for value in held {
            var current = stat()
            guard fstat(value.descriptor, &current) == 0, InstalledIdentityStamp(current) == value.stamp else {
                throw InspectionFailure.unsafePath
            }
        }
    }
}
