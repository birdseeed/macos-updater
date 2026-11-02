import Foundation
import Darwin

// Identity-only binding. Productive read-only mount validation stays in Inspector.
internal struct HeldSignatureBundleBinding {
    private struct Stamp {
        let value: stat

        init(descriptor: Int32, type: mode_t) throws {
            var value = stat()
            guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == type else {
                throw InspectionFailure.unsafePath
            }
            self.value = value
        }

        func confirm(descriptor: Int32, type: mode_t) throws {
            let current = try Stamp(descriptor: descriptor, type: type).value
            guard current.st_dev == value.st_dev, current.st_ino == value.st_ino,
                  current.st_mode == value.st_mode, current.st_uid == value.st_uid,
                  current.st_gid == value.st_gid, current.st_nlink == value.st_nlink,
                  current.st_size == value.st_size,
                  current.st_mtimespec.tv_sec == value.st_mtimespec.tv_sec,
                  current.st_mtimespec.tv_nsec == value.st_mtimespec.tv_nsec,
                  current.st_ctimespec.tv_sec == value.st_ctimespec.tv_sec,
                  current.st_ctimespec.tv_nsec == value.st_ctimespec.tv_nsec else {
                throw InspectionFailure.unsafePath
            }
        }
    }

    private let appPath: String
    private let executablePath: String
    private let appDescriptor: Int32
    private let executableDescriptor: Int32
    private let infoPlist: Data
    private let appStamp: Stamp
    private let executableStamp: Stamp

    internal init(appPath: String, appDescriptor: Int32, executableDescriptor: Int32,
                  infoPlist: Data) throws {
        // Borrowed descriptors remain owned by the caller on every exit path.
        let appStamp = try Stamp(descriptor: appDescriptor, type: S_IFDIR)
        let executableStamp = try Stamp(descriptor: executableDescriptor, type: S_IFREG)
        let executableName: String
        do {
            guard infoPlist.count <= 1_048_576,
                  let dictionary = try PropertyListSerialization.propertyList(
                    from: infoPlist, options: [], format: nil) as? [String: Any],
                  let name = dictionary["CFBundleExecutable"] as? String,
                  !name.isEmpty, name != ".", name != "..",
                  !name.contains("/"), !name.contains("\0") else {
                throw InspectionFailure.unsafePath
            }
            executableName = name
        } catch { throw InspectionFailure.unsafePath }
        self.appPath = appPath
        self.executablePath = appPath + "/Contents/MacOS/" + executableName
        self.appDescriptor = appDescriptor
        self.executableDescriptor = executableDescriptor
        self.infoPlist = infoPlist
        self.appStamp = appStamp
        self.executableStamp = executableStamp
        try confirm()
    }

    internal func confirm() throws {
        do {
            try appStamp.confirm(descriptor: appDescriptor, type: S_IFDIR)
            try executableStamp.confirm(descriptor: executableDescriptor, type: S_IFREG)
            let currentApp = try SafeFiles.openPath(appPath, directory: true)
            defer { close(currentApp) }
            let currentExecutable = try SafeFiles.openPath(executablePath)
            defer { close(currentExecutable) }
            try appStamp.confirm(descriptor: currentApp, type: S_IFDIR)
            try executableStamp.confirm(descriptor: currentExecutable, type: S_IFREG)
            guard try SafeFiles.read(appPath + "/Contents/Info.plist", maximum: 1_048_576) == infoPlist else {
                throw InspectionFailure.unsafePath
            }
            // Check both held and reopened identities again after the bounded read.
            try appStamp.confirm(descriptor: appDescriptor, type: S_IFDIR)
            try executableStamp.confirm(descriptor: executableDescriptor, type: S_IFREG)
            try appStamp.confirm(descriptor: currentApp, type: S_IFDIR)
            try executableStamp.confirm(descriptor: currentExecutable, type: S_IFREG)
        } catch { throw InspectionFailure.unsafePath }
    }
}

// Testing SPI exposes only an opaque identity handle to the same internal helper.
// It cannot perform Security validation or construct evidence or live authority.
@_spi(Testing) public final class SignatureBundleBindingTestHandle {
    private let binding: HeldSignatureBundleBinding

    fileprivate init(binding: HeldSignatureBundleBinding) { self.binding = binding }

    public func confirm() throws { try binding.confirm() }
}

@_spi(Testing) public enum SignatureBundleBindingTestAdapter {
    public static func capture(appPath: String, appDescriptor: Int32,
                               executableDescriptor: Int32, infoPlist: Data) throws
        -> SignatureBundleBindingTestHandle {
        SignatureBundleBindingTestHandle(binding: try HeldSignatureBundleBinding(
            appPath: appPath, appDescriptor: appDescriptor,
            executableDescriptor: executableDescriptor, infoPlist: infoPlist))
    }
}
