import Foundation
import Darwin

struct TreeBounds {
    var entries = DisposableScope.maximumEntries
    var depth = DisposableScope.maximumDepth
    var bytes = DisposableScope.maximumTotalBytes
}
enum ManifestReader {
    static func read(_ directory: HeldDirectory, bounds: TreeBounds = .init(), owner: uid_t? = getuid()) throws -> ProofManifest {
        guard bounds.entries > 0, bounds.depth >= 0, bounds.bytes >= 0 else { throw DisposableFailure.treeLimit }
        let device = identity(try directory.status()).0
        var entries: [ProofManifestEntry] = [], total: Int64 = 0
        func append(_ entry: ProofManifestEntry) throws {
            guard entries.count < bounds.entries else { throw DisposableFailure.treeLimit }; entries.append(entry)
        }
        func visit(_ held: HeldDirectory, path: String, depth: Int) throws {
            guard depth <= bounds.depth else { throw DisposableFailure.treeLimit }
            let before = try held.status()
            try sameVolume(device, identity(before).0)
            if let owner { guard before.st_uid == owner else { throw DisposableFailure.unsafeOwner } }
            guard safeMode(before) else { throw DisposableFailure.unsafeMode }
            try append(.init(path: path, type: "directory", mode: UInt16(permissions(before)), byteLength: 0, link: "", sha256: ""))
            for name in try held.names(maximum: bounds.entries - entries.count) {
                guard depth < bounds.depth else { throw DisposableFailure.treeLimit }
                let relative = path == "." ? name : path + "/" + name
                guard let info = try held.named(name) else { throw DisposableFailure.identityChanged }
                try sameVolume(device, identity(info).0)
                if let owner { guard info.st_uid == owner else { throw DisposableFailure.unsafeOwner } }
                switch info.st_mode & S_IFMT {
                case S_IFDIR: try visit(held.child(name), path: relative, depth: depth + 1)
                case S_IFREG:
                    let file = try HeldFile(parent: held, name: name, owner: owner)
                    guard stable(info, file.captured) else { throw DisposableFailure.identityChanged }
                    guard file.captured.st_size <= bounds.bytes - total else { throw DisposableFailure.treeLimit }
                    let (length, hash) = try file.stream(maximum: bounds.bytes - total); total += length
                    try append(.init(path: relative, type: "file", mode: UInt16(permissions(file.captured)), byteLength: length, link: "", sha256: hash))
                case S_IFLNK:
                    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
                    let count = buffer.withUnsafeMutableBufferPointer {
                        readlinkat(held.fd, name, $0.baseAddress, $0.count)
                    }
                    guard count > 0, count < buffer.count, let text = String(bytes: buffer.prefix(count).map { UInt8(bitPattern: $0) }, encoding: .utf8) else { throw DisposableFailure.escapingLink }
                    guard let after = try held.named(name), stable(info, after) else { throw DisposableFailure.identityChanged }
                    try append(.init(path: relative, type: "symlink", mode: UInt16(permissions(info)), byteLength: 0, link: text, sha256: ""))
                default: throw DisposableFailure.specialFile
                }
            }
            try held.confirm()
            guard stable(before, try held.status()) else { throw DisposableFailure.identityChanged }
        }
        try visit(directory, path: ".", depth: 0)
        entries.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        let index = Dictionary(uniqueKeysWithValues: entries.map { (Data($0.path.utf8), $0) })
        for entry in entries where entry.type == "symlink" {
            var resolved = entry.path.split(separator: "/").dropLast().map(String.init)
            var queue = entry.link.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var visited: Set<Data> = [Data(entry.path.utf8)]
            guard !entry.link.hasPrefix("/"), !entry.link.utf8.contains(0) else { throw DisposableFailure.escapingLink }
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if next == "." || next.isEmpty { continue }
                if next == ".." {
                    guard !resolved.isEmpty else { throw DisposableFailure.escapingLink }; resolved.removeLast(); continue
                }
                let key = Data((resolved + [next]).joined(separator: "/").utf8)
                guard let found = index[key] else { throw DisposableFailure.escapingLink }
                if found.type == "symlink" {
                    guard visited.insert(key).inserted, visited.count <= 80 else { throw DisposableFailure.cyclicLink }
                    guard !found.link.hasPrefix("/") else { throw DisposableFailure.escapingLink }
                    queue = found.link.split(separator: "/", omittingEmptySubsequences: false).map(String.init) + queue
                } else {
                    if !queue.isEmpty && found.type != "directory" { throw DisposableFailure.escapingLink }
                    resolved.append(next)
                }
            }
        }
        return ProofManifest(entries: entries, totalBytes: total, digest: digest(canonical(entries)))
    }
    static func canonical(_ entries: [ProofManifestEntry]) -> Data {
        var result = Data("patched-disposable-manifest-v1\0".utf8)
        func integer(_ n: UInt64) { var n = n.bigEndian; withUnsafeBytes(of: &n) { result.append(contentsOf: $0) } }
        func field(_ text: String) { let bytes = Data(text.utf8); integer(UInt64(bytes.count)); result.append(bytes) }
        integer(UInt64(entries.count))
        for entry in entries { for value in [entry.path, entry.type, String(entry.mode), String(entry.byteLength), entry.link, entry.sha256] { field(value) } }
        return result
    }
}
