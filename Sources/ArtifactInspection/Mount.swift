import Foundation
import Darwin

func validateMount(_ data: Data, ownedPath: String) throws -> String {
    guard data.count <= 1_048_576, safeEvidencePath(ownedPath) else { throw InspectionFailure.invalidMount }
    do {
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]] else { throw InspectionFailure.invalidMount }
        let mounted = entities.filter { $0["mount-point"] != nil }
        guard mounted.count == 1, mounted[0]["mount-point"] as? String == ownedPath,
              let device = mounted[0]["dev-entry"] as? String, device.hasPrefix("/dev/disk"),
              safeEvidencePath(device) else { throw InspectionFailure.invalidMount }
        return ownedPath
    } catch { throw InspectionFailure.invalidMount }
}
func mountedPaths() throws -> Set<String> {
    var entries: UnsafeMutablePointer<statfs>?
    let count = getmntinfo(&entries, MNT_NOWAIT)
    guard count > 0, let entries else { throw InspectionFailure.cleanupFailed }
    return Set((0..<Int(count)).map { index in
        var name = entries[index].f_mntonname
        return withUnsafePointer(to: &name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    })
}
func withReadOnlyImage<T>(dmgPath: String, workspace: String, runner: any InspectionCommandRunning,
                          image: VerifiedImage? = nil, source: LoopbackImageSource? = nil,
                          body: (String) throws -> T) throws -> T {
    let directory = try SafeFiles.privateDirectory(workspace); defer { close(directory) }
    let name = "mount-" + UUID().uuidString
    guard mkdirat(directory, name, 0o700) == 0 else { throw InspectionFailure.unsafePath }
    let mount = workspace + "/" + name
    var attached = false
    func cleanup() throws {
        let mounted = try mountedPaths().contains(mount)
        if attached || mounted {
            do {
                let result = try runner.run(executable: "/usr/bin/hdiutil", arguments: ["detach", mount], limits: .init())
                try checkResult(result)
                guard !(try mountedPaths()).contains(mount) else { throw InspectionFailure.cleanupFailed }
                attached = false
            } catch { throw InspectionFailure.cleanupFailed }
        }
        guard unlinkat(directory, name, AT_REMOVEDIR) == 0 else { throw InspectionFailure.cleanupFailed }
    }
    do {
        let result: CommandResult
        if let image {
            guard dmgPath == image.operand, let source, source.isOwned(by: image),
                  let bound = runner as? any ImageCommandRunning else {
                throw InspectionFailure.invalidMetadata
            }
            let arguments = try source.nativeAttachArguments(mountPath: mount)
            result = try bound.run(image: image, source: source, executable: "/usr/bin/hdiutil", arguments: arguments, limits: .init())
        } else {
            let arguments = ["attach", "-readonly", "-nobrowse", "-plist", "-mountpoint", mount, dmgPath]
            result = try runner.run(executable: "/usr/bin/hdiutil", arguments: arguments, limits: .init())
        }
        // Retain owned attachment evidence even for an unsuccessful command.
        if (try? validateMount(Data(result.stdout.utf8), ownedPath: mount)) != nil { attached = true }
        try checkResult(result)
        _ = try validateMount(Data(result.stdout.utf8), ownedPath: mount)
        let value = try body(mount)
        try cleanup()
        return value
    } catch {
        let original = error
        // A failed cleanup keeps evidence and the workspace. Never retry recursive
        // deletion, or detach a foreign path taken from tool output.
        if original as? InspectionFailure == .cleanupFailed { throw original }
        try cleanup()
        throw original
    }
}

extension ReadOnlyMount {
    static func withImage<T>(image: VerifiedImage, workspace: String, runner: any ImageCommandRunning,
                             body: (String) throws -> T) throws -> T {
        // Keep this one source alive through both the body and owned detach.
        // No URL/path/kernel fallback follows a failed productive attachment.
        let source = try LoopbackImageSource.start(image: image)
        do {
            let value = try withReadOnlyImage(dmgPath: image.operand, workspace: workspace,
                runner: runner, image: image, source: source, body: body)
            try source.stop()
            return value
        } catch {
            let original = error
            try source.stop()
            throw original
        }
    }
}
