import Foundation
import Darwin
@_spi(Testing) import ArtifactInspection

// Inert fake bundles only. No mount, Security API, app execution or OS authority.
private final class BindingFixture {
    let root: String
    let rootDevice: dev_t
    let rootInode: ino_t
    let info: Data
    var app: String { root + "/Fake.app" }
    var executable: String { app + "/Contents/MacOS/fixture" }
    var plistPath: String { app + "/Contents/Info.plist" }
    private var descriptors: [Int32] = []
    private(set) var appFD: Int32 = -1
    private(set) var executableFD: Int32 = -1

    init() throws {
        guard let physical = realpath(FileManager.default.currentDirectoryPath, nil) else {
            throw InspectionFailure.unsafePath
        }
        let working = String(cString: physical)
        free(physical)
        let build = working + "/.build"
        if mkdir(build, 0o700) != 0 && errno != EEXIST { throw InspectionFailure.unsafePath }
        var buildStat = stat()
        guard lstat(build, &buildStat) == 0, buildStat.st_mode & S_IFMT == S_IFDIR,
              buildStat.st_uid == geteuid() else { throw InspectionFailure.unsafePath }
        var template = Array((build + "/pinned-binding-XXXXXXXX").utf8CString)
        guard let created = mkdtemp(&template) else { throw InspectionFailure.unsafePath }
        root = String(cString: created)
        var owned = stat()
        guard lstat(root, &owned) == 0 else { throw InspectionFailure.unsafePath }
        rootDevice = owned.st_dev
        rootInode = owned.st_ino
        info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleExecutable": "fixture", "CFBundleIdentifier": "invalid.inert.fixture",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0"],
            format: .xml, options: 0)
        do {
            try makeBundle(at: app)
            appFD = try borrow(app, directory: true)
            executableFD = try borrow(executable)
        } catch {
            cleanup()
            throw error
        }
    }

    deinit { cleanup() }

    private func cleanup() {
        for descriptor in descriptors { close(descriptor) }
        descriptors.removeAll()
        var current = stat()
        // Only the exclusively created, still-owned root beneath .build is removed.
        guard lstat(root, &current) == 0, current.st_dev == rootDevice,
              current.st_ino == rootInode, current.st_uid == geteuid(),
              current.st_mode & S_IFMT == S_IFDIR, current.st_mode & 0o777 == 0o700 else { return }
        try? FileManager.default.removeItem(atPath: root)
    }

    func makeBundle(at path: String) throws {
        try FileManager.default.createDirectory(atPath: path + "/Contents/MacOS", withIntermediateDirectories: true)
        try info.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
        // Deliberately not a Mach-O or script and never executed.
        try Data("inert-file-0000".utf8).write(to: URL(fileURLWithPath: path + "/Contents/MacOS/fixture"))
    }

    func borrow(_ path: String, directory: Bool = false) throws -> Int32 {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0))
        guard descriptor >= 0 else { throw InspectionFailure.unsafePath }
        descriptors.append(descriptor)
        return descriptor
    }

    func capture(path: String? = nil, appDescriptor: Int32? = nil,
                 executableDescriptor: Int32? = nil, plist: Data? = nil) throws -> SignatureBundleBindingTestHandle {
        try SignatureBundleBindingTestAdapter.capture(appPath: path ?? app,
            appDescriptor: appDescriptor ?? appFD, executableDescriptor: executableDescriptor ?? executableFD,
            infoPlist: plist ?? info)
    }

    func requireBorrowedOpen() throws {
        var appStat = stat(), exeStat = stat()
        try expect(fstat(appFD, &appStat) == 0 && appStat.st_mode & S_IFMT == S_IFDIR,
                   "Binding closed or replaced the borrowed app descriptor")
        try expect(fstat(executableFD, &exeStat) == 0 && exeStat.st_mode & S_IFMT == S_IFREG,
                   "Binding closed or replaced the borrowed executable descriptor")
    }
}

@MainActor func pinnedSignatureBindingCases() -> [(String, () throws -> Void)] {
    var cases: [(String, () throws -> Void)] = []
    func add(_ name: String, _ body: @escaping () throws -> Void) { cases.append(("binding " + name, body)) }
    func altered(_ name: String, _ mutate: @escaping (BindingFixture) throws -> Void) {
        add(name) {
            let fixture = try BindingFixture()
            // Capture always precedes the independent mutation.
            let binding = try fixture.capture()
            try mutate(fixture)
            try refuses(.unsafePath) { try binding.confirm() }
            try fixture.requireBorrowedOpen()
        }
    }
    // First new case is a meaningful success control, not an arbitrary refusal.
    add("unchanged identity confirms twice without closing borrowed descriptors") {
        let fixture = try BindingFixture()
        let binding = try fixture.capture()
        try binding.confirm()
        try binding.confirm()
        try fixture.requireBorrowedOpen()
    }
    altered("app directory inode swap") { fixture in
        try FileManager.default.moveItem(atPath: fixture.app, toPath: fixture.root + "/original.app")
        try fixture.makeBundle(at: fixture.app)
    }
    altered("executable inode swap with identical bytes") { fixture in
        try FileManager.default.moveItem(atPath: fixture.executable, toPath: fixture.root + "/original-executable")
        try Data("inert-file-0000".utf8).write(to: URL(fileURLWithPath: fixture.executable))
    }
    altered("same-length executable in-place mutation") { fixture in
        let descriptor = open(fixture.executable, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw InspectionFailure.unsafePath }
        defer { close(descriptor) }
        let bytes = Array("inert-file-1111".utf8)
        let count = bytes.withUnsafeBytes { Darwin.pwrite(descriptor, $0.baseAddress, $0.count, 0) }
        try expect(count == bytes.count && fsync(descriptor) == 0, "Failed to mutate inert executable in place")
        // Deterministic fixture-only timestamp avoids coarse filesystem clock resolution.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_234_567_890)],
                                              ofItemAtPath: fixture.executable)
    }
    altered("plist bytes mutation") { fixture in
        let changed = String(decoding: fixture.info, as: UTF8.self).replacingOccurrences(of: "invalid.inert.fixture", with: "invalid.other.fixture")
        try expect(Data(changed.utf8) != fixture.info, "Plist mutation was ineffective")
        try Data(changed.utf8).write(to: URL(fileURLWithPath: fixture.plistPath))
    }
    altered("app path replaced by symlink") { fixture in
        let saved = fixture.root + "/saved.app"
        try FileManager.default.moveItem(atPath: fixture.app, toPath: saved)
        try FileManager.default.createSymbolicLink(atPath: fixture.app, withDestinationPath: saved)
    }
    altered("executable path replaced by symlink") { fixture in
        let saved = fixture.root + "/saved-executable"
        try FileManager.default.moveItem(atPath: fixture.executable, toPath: saved)
        try FileManager.default.createSymbolicLink(atPath: fixture.executable, withDestinationPath: saved)
    }
    altered("Info.plist path replaced by symlink") { fixture in
        let saved = fixture.root + "/saved-plist"
        try FileManager.default.moveItem(atPath: fixture.plistPath, toPath: saved)
        try FileManager.default.createSymbolicLink(atPath: fixture.plistPath, withDestinationPath: saved)
    }
    for kind in ["app", "executable", "plist"] {
        add("capture refuses existing \(kind) symlink") {
            let fixture = try BindingFixture()
            let path = kind == "app" ? fixture.app : kind == "executable" ? fixture.executable : fixture.plistPath
            let saved = fixture.root + "/symlink-target"
            try FileManager.default.moveItem(atPath: path, toPath: saved)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: saved)
            try refuses(.unsafePath) { _ = try fixture.capture() }
            try fixture.requireBorrowedOpen()
        }
    }
    for kind in ["invalid app", "invalid executable", "regular app", "directory executable", "other app", "other executable"] {
        add("capture refuses \(kind) descriptor") {
            let fixture = try BindingFixture()
            var appFD = fixture.appFD, exeFD = fixture.executableFD
            switch kind {
            case "invalid app": appFD = -1
            case "invalid executable": exeFD = -1
            case "regular app": appFD = fixture.executableFD
            case "directory executable": exeFD = fixture.appFD
            case "other app": appFD = try fixture.borrow(fixture.root, directory: true)
            default:
                let other = fixture.root + "/other-file"
                try Data("inert-file-0000".utf8).write(to: URL(fileURLWithPath: other))
                exeFD = try fixture.borrow(other)
            }
            // No valid descriptor is closed and subsequently reused as a negative input.
            try refuses(.unsafePath) { _ = try fixture.capture(appDescriptor: appFD, executableDescriptor: exeFD) }
            try fixture.requireBorrowedOpen()
        }
    }
    add("capture refuses alternate bundle path with original descriptors") {
        let fixture = try BindingFixture()
        let alternate = fixture.root + "/Alternate.app"
        try fixture.makeBundle(at: alternate)
        try refuses(.unsafePath) { _ = try fixture.capture(path: alternate) }
        try fixture.requireBorrowedOpen()
    }
    add("capture refuses mismatched plist bytes") {
        let fixture = try BindingFixture()
        try refuses(.unsafePath) { _ = try fixture.capture(plist: Data("different".utf8)) }
        try fixture.requireBorrowedOpen()
    }
    return cases
}
