import Foundation
import Darwin
@_spi(Testing) import PatchedDisposableProof

@MainActor func registerFilesystemChecks() {
    check("exclusive synthetic root and held identity") {
        let path = try physicalBuild() + "/patched-disposable-check-" + UUID().uuidString
        let root = try SyntheticProofFiles.createRoot(path: path)
        try expect(root.path == path && (try statOf(path).st_mode & 0o7777) == 0o700, "Exclusive private root")
        try root.revalidate()
        try refuses(.existingRoot) { _ = try SyntheticProofFiles.createRoot(path: path) }
    }
    check("synthetic root cannot name production run") { try refuses(.notAuthorized) { _ = try SyntheticProofFiles.createRoot(path: "/Users/andy/PatchedProof/phase-a") } }
    check("synthetic root refuses existing owned directory") { let root = try fixture(); try refuses(.existingRoot) { _ = try SyntheticProofFiles.createRoot(path: root) } }
    check("synthetic held root detects ancestry replacement") {
        let path = try physicalBuild() + "/patched-disposable-check-" + UUID().uuidString
        let held = try SyntheticProofFiles.createRoot(path: path)
        try expect(rename(path, path + "-retained") == 0, "Fixture rename"); try directory(path)
        try refuses(.identityChanged) { try held.revalidate() }
    }
    check("manifest exact physical bytes executable and internal link") {
        let root = try fixture(), app = try tree(root)
        try matches(SyntheticProofFiles.inspect(root: root, relativePath: "App"), independentManifest(app))
    }
    check("manifest deterministic order despite creation order") {
        let root = try fixture(); try directory(root + "/A"); try directory(root + "/B")
        for name in ["z", "a", "b"] { try file(root + "/A/" + name, Data(name.utf8)) }
        for name in ["b", "a", "z"] { try file(root + "/B/" + name, Data(name.utf8)) }
        try expect(try SyntheticProofFiles.inspect(root: root, relativePath: "A") == SyntheticProofFiles.inspect(root: root, relativePath: "B"), "Creation order changes digest")
    }
    for mutation in ["byte", "mode", "link", "type"] {
        check("manifest detects \(mutation) mutation") {
            let root = try fixture(), app = try tree(root)
            let before = try SyntheticProofFiles.inspect(root: root, relativePath: "App")
            switch mutation {
            case "byte": try overwrite(app + "/Contents/data", Data([0, 1, 2, 4]))
            case "mode": try expect(chmod(app + "/Contents/data", 0o644) == 0, "Fixture chmod")
            case "link": try expect(unlink(app + "/Current") == 0, "Fixture unlink"); try symbolic("Contents/data", app + "/Current")
            default: try expect(unlink(app + "/Contents/data") == 0, "Fixture unlink"); try directory(app + "/Contents/data")
            }
            let after = try SyntheticProofFiles.inspect(root: root, relativePath: "App")
            try expect(before.digest != after.digest && before.entries != after.entries, "Mutation invisible")
            try matches(after, independentManifest(app))
        }
    }
    for mode: mode_t in [0o4755, 0o2755, 0o1755, 0o777, 0o666] {
        check("unsafe file mode \(String(mode, radix: 8))") {
            let root = try fixture(), app = try tree(root)
            try expect(chmod(app + "/Contents/exec", mode) == 0, "Fixture chmod")
            try refuses(.unsafeMode) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
        }
    }
    for target in ["/etc/passwd", "../outside", "Contents/../../outside"] {
        check("manifest escaping symlink \(target)") {
            let root = try fixture(); _ = try tree(root); try symbolic(target, root + "/App/Escape")
            try refuses(.escapingLink) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
        }
    }
    check("manifest refuses cyclic relative links") {
        let root = try fixture(); _ = try tree(root)
        try symbolic("B", root + "/App/A"); try symbolic("A", root + "/App/B")
        try refuses(.cyclicLink) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
    }
    check("manifest permits relative framework chain") {
        let root = try fixture(), app = try tree(root)
        try directory(app + "/Versions"); try directory(app + "/Versions/A"); try file(app + "/Versions/A/framework", mode: 0o755)
        try symbolic("A", app + "/Versions/Current"); try symbolic("Versions/Current/framework", app + "/framework")
        try matches(SyntheticProofFiles.inspect(root: root, relativePath: "App"), independentManifest(app))
    }
    check("manifest refuses hardlink") {
        let root = try fixture(), app = try tree(root); try expect(link(app + "/Contents/data", app + "/Alias") == 0, "Fixture hardlink")
        try refuses(.hardlink) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
    }
    check("manifest FIFO refused without opening") {
        let root = try fixture(), app = try tree(root); try expect(mkfifo(app + "/fifo", 0o600) == 0, "Fixture fifo")
        try refuses(.specialFile) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
    }
    for path in ["../App", "/Applications/Firefox.app", "App//Contents", "App/./Contents", "App/Contents/", "App\0x"] {
        check("relative traversal refused \(String(reflecting: path))") {
            let root = try fixture(); try refuses(.unsafePath) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: path) }
        }
    }
    check("symlinked inspection ancestry refused") {
        let root = try fixture(); _ = try tree(root); try symbolic("App", root + "/Alias")
        try refuses(.symlink) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "Alias/Contents") }
    }
    for limit in [SyntheticLimits(entries: 2), .init(depth: 1), .init(bytes: 3)] {
        check("manifest never silently truncates bound \(limit)") {
            let root = try fixture(); _ = try tree(root)
            try refuses(.treeLimit) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App", limits: limit) }
        }
    }
    check("exact inclusive small manifest limits") {
        let root = try fixture(); try directory(root + "/App"); try file(root + "/App/file", Data([1, 2, 3]))
        let manifest = try SyntheticProofFiles.inspect(root: root, relativePath: "App", limits: .init(entries: 2, depth: 1, bytes: 3))
        try expect(manifest.entries.count == 2 && manifest.totalBytes == 3, "Inclusive exact bound")
    }
    check("descriptor regular file exact bounded read") {
        let root = try fixture(); try file(root + "/data", Data([1, 2, 3]))
        try expect(try SyntheticProofFiles.readRegular(root: root, relativePath: "data", maximumBytes: 3) == Data([1, 2, 3]), "Exact physical bytes")
    }
    check("descriptor file read never truncates") {
        let root = try fixture(); try file(root + "/data", Data([1, 2, 3]))
        try refuses(.treeLimit) { _ = try SyntheticProofFiles.readRegular(root: root, relativePath: "data", maximumBytes: 2) }
    }
    check("descriptor physical full-content hashing") {
        let root = try fixture(), data = Data((0..<4096).map { UInt8($0 % 251) }); try file(root + "/image", data)
        try SyntheticProofFiles.verifyRegular(root: root, relativePath: "image", expectedLength: 4096, expectedSHA256: sha(data))
        var changed = data; changed[2048] ^= 1; try overwrite(root + "/image", changed)
        try refuses(.digestMismatch) { try SyntheticProofFiles.verifyRegular(root: root, relativePath: "image", expectedLength: 4096, expectedSHA256: sha(data)) }
    }
    check("descriptor held byte length checked first") {
        let root = try fixture(); try file(root + "/image", Data([1]))
        try refuses(.lengthMismatch) { try SyntheticProofFiles.verifyRegular(root: root, relativePath: "image", expectedLength: 2, expectedSHA256: "bad") }
    }
    check("descriptor root substitution before file open preserves substitute") {
        let root = try fixture(); try file(root + "/data")
        let probe = SyntheticProbes(boundary: { boundary in
            if boundary == .rootHeld { try expect(rename(root, root + "-held") == 0, "Fixture rename"); try directory(root); try file(root + "/sentinel") }
        })
        try refuses(.identityChanged) { _ = try SyntheticProofFiles.readRegular(root: root, relativePath: "data", maximumBytes: 10, probes: probe) }
        try expect(try bytes(root + "/sentinel") == Data("old".utf8), "Substitute changed")
    }
    for mode: mode_t in [0o777, 0o1777, 0o2755] {
        check("unsafe directory mode \\(String(mode, radix: 8))") {
            let root = try fixture(), app = try tree(root)
            try expect(chmod(app + "/Contents", mode) == 0, "Fixture directory chmod")
            try refuses(.unsafeMode) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
        }
    }
    check("dangling relative link refused") {
        let root = try fixture(); _ = try tree(root); try symbolic("Missing", root + "/App/Dangling")
        try refuses(.escapingLink) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
    }
    check("relative link through escaping link refused") {
        let root = try fixture(); _ = try tree(root); try symbolic("../outside", root + "/App/A")
        try symbolic("A/secret", root + "/App/B")
        try refuses(.escapingLink) { _ = try SyntheticProofFiles.inspect(root: root, relativePath: "App") }
    }
    check("file substitution between metadata read and open refused") {
        let root = try fixture(); try file(root + "/data")
        let probe = SyntheticProbes(boundary: { if $0 == .beforeFileOpen {
            try expect(rename(root + "/data", root + "/retained") == 0, "Fixture rename")
            try file(root + "/data", Data("new".utf8))
        } })
        try refuses(.identityChanged) { _ = try SyntheticProofFiles.readRegular(root: root, relativePath: "data", maximumBytes: 10, probes: probe) }
        try expect(try bytes(root + "/data") == Data("new".utf8) && bytes(root + "/retained") == Data("old".utf8), "Substitution altered fixture")
    }
    check("held file rewrite is detected") {
        let root = try fixture(); try file(root + "/data")
        let probe = SyntheticProbes(boundary: { if $0 == .fileHeld { try overwrite(root + "/data", Data("changed-size".utf8)) } })
        try refuses(.identityChanged) { _ = try SyntheticProofFiles.readRegular(root: root, relativePath: "data", maximumBytes: 100, probes: probe) }
    }
    check("exclusive write preserves existing file") {
        let root = try fixture(); try file(root + "/kept")
        try refuses(.existingRoot) { try SyntheticProofFiles.writeExclusive(root: root, relativePath: "kept", data: Data("new".utf8)) }
        try expect(try bytes(root + "/kept") == Data("old".utf8), "Existing bytes changed")
    }
    check("exclusive durable write rereads exact bytes") {
        let root = try fixture(), data = Data([4, 5, 6]); try SyntheticProofFiles.writeExclusive(root: root, relativePath: "created", data: data)
        try expect(try bytes(root + "/created") == data, "Created bytes differ")
        try expect(try statOf(root + "/created").st_mode & 0o7777 == 0o600, "Private file mode")
    }
    check("actual atomic exchange keeps both identities and contents") {
        let root = try fixture(); try file(root + "/old", Data("old".utf8)); try file(root + "/new", Data("new".utf8))
        let old = try statOf(root + "/old"), new = try statOf(root + "/new")
        try SyntheticProofFiles.exchange(root: root, left: "old", right: "new")
        try expect(try statOf(root + "/old").st_ino == new.st_ino && statOf(root + "/new").st_ino == old.st_ino, "Inodes not exchanged")
        try expect(try bytes(root + "/old") == Data("new".utf8) && bytes(root + "/new") == Data("old".utf8), "Whole bytes not retained")
    }
    check("exchange refuses path alias") { let root = try fixture(); try file(root + "/old"); try refuses(.unsafePath) { try SyntheticProofFiles.exchange(root: root, left: "old", right: "old") } }
    check("exchange refuses symbolic endpoint") {
        let root = try fixture(); try file(root + "/kept"); try symbolic("kept", root + "/link"); try file(root + "/new")
        try refuses(.symlink) { try SyntheticProofFiles.exchange(root: root, left: "link", right: "new") }
        try expect(try bytes(root + "/kept") == Data("old".utf8), "Symlink endpoint modified")
    }
}
