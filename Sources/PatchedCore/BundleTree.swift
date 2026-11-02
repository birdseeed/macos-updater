import Foundation
import Darwin

// PAT-2582 bundle trees: the physical read of a held bundle directory, the
// pinned manifest document and the identity read from a bundle's Info.plist.
// Paths are compared byte for byte; no Unicode normalisation is applied.

struct TreeEntry {
    let path: String
    let isDirectory: Bool
    let mode: UInt16
    let byteLength: Int64
    let sha256: String
    var line: String {
        let octal = String(mode, radix: 8)
        return "\(isDirectory ? "directory" : "file")\t\(path)\t\(String(repeating: "0", count: max(0, 4 - octal.count)) + octal)\t\(byteLength)\t\(sha256)\n"
    }
    func matches(_ other: TreeEntry) -> Bool {
        sameBytes(path, other.path) && isDirectory == other.isDirectory && mode == other.mode &&
            byteLength == other.byteLength && sameBytes(sha256, other.sha256)
    }
}

/// Entries with the bundle root `.` first and every other path in ascending byte order.
struct TreeListing {
    let entries: [TreeEntry]
    static let empty = TreeListing(entries: [])
    var digest: String { sha256Hex(Data(entries.map(\.line).joined().utf8)) }
    var report: BundleManifest {
        BundleManifest(entries: entries.map {
            BundleManifestEntry(path: $0.path, type: $0.isDirectory ? "directory" : "file", mode: $0.mode,
                                byteLength: $0.byteLength, sha256: $0.sha256)
        }, fileCount: entries.filter { !$0.isDirectory }.count, directoryCount: entries.filter(\.isDirectory).count,
           totalBytes: entries.reduce(0) { $0 + $1.byteLength }, treeSHA256: digest)
    }
    func matches(_ other: TreeListing) -> Bool {
        entries.count == other.entries.count && zip(entries, other.entries).allSatisfy { $0.matches($1) }
    }
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        if sameBytes(lhs, ".") || sameBytes(rhs, ".") { return sameBytes(lhs, ".") && !sameBytes(rhs, ".") }
        return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
    /// Indices of the direct children of each entry. Only a validated listing has every parent.
    var children: [[Int]] {
        var index: [[UInt8]: Int] = [:], result = [[Int]](repeating: [], count: entries.count)
        for (position, entry) in entries.enumerated() {
            let bytes = Array(entry.path.utf8)
            index[bytes] = position
            guard position > 0 else { continue }
            let parent = bytes.lastIndex(of: 47).map { Array(bytes[..<$0]) } ?? [46]
            if let owner = index[parent] { result[owner].append(position) }
        }
        return result
    }
    static func leaf(_ path: String) -> String {
        let bytes = Array(path.utf8)
        return bytes.lastIndex(of: 47).map { String(decoding: bytes[($0 + 1)...], as: UTF8.self) } ?? path
    }
}

/// One bundle as physically read through its held root directory.
struct PhysicalBundle {
    let listing: TreeListing
    let identity: EntryIdentity
    /// File bytes in listing order, kept only when asked for; `nil` for a directory.
    let contents: [Data?]
    /// `Contents/Info.plist` exactly as hashed, when present and within its bound.
    let infoPlist: Data?
}

enum BundleTree {
    static let directoryModes: [mode_t] = [0o700, 0o755]
    static let fileModes: [mode_t] = [0o600, 0o644]

    /// Reads every entry beneath the held `root`. Each must be an owned directory or an owned
    /// single-link non-executable regular file on the root's volume, within the fixture bounds.
    /// Physical safety is judged here, before any comparison with a manifest.
    static func read(_ root: Int32, retainContents: Bool = false) throws -> PhysicalBundle {
        let info = try FixtureIO.held(root)
        var walk = Walk(device: info.st_dev, retain: retainContents)
        try walk.directory(root, info, path: ".", depth: 0)
        let rows = walk.rows.sorted { TreeListing.precedes($0.0.path, $1.0.path) }
        return PhysicalBundle(listing: TreeListing(entries: rows.map(\.0)), identity: EntryIdentity(info),
                              contents: rows.map(\.1), infoPlist: walk.infoPlist)
    }

    private struct Walk {
        let device: dev_t
        let retain: Bool
        var rows: [(TreeEntry, Data?)] = []
        var total: Int64 = 0
        var infoPlist: Data?

        mutating func append(_ entry: TreeEntry, _ data: Data?) throws {
            guard rows.count < TransactionLimits.maximumEntries else { throw TransactionFailure.treeLimit }
            rows.append((entry, data))
        }
        mutating func directory(_ descriptor: Int32, _ info: stat, path: String, depth: Int) throws {
            guard info.st_dev == device else { throw TransactionFailure.crossVolume }
            try FixtureIO.requireDirectory(info, modes: BundleTree.directoryModes)
            try append(TreeEntry(path: path, isDirectory: true, mode: UInt16(FixtureIO.permissions(info)), byteLength: 0, sha256: "-"), nil)
            let names = try FixtureIO.names(in: descriptor, limit: TransactionLimits.maximumEntries - rows.count + 1)
            guard names.isEmpty || depth < TransactionLimits.maximumDepth else { throw TransactionFailure.treeLimit }
            for name in names {
                let child = depth == 0 ? name : path + "/" + name
                guard let entry = try FixtureIO.named(name, in: descriptor) else { throw TransactionFailure.identityChanged }
                switch FixtureIO.kind(entry) {
                case S_IFLNK: throw TransactionFailure.symlink
                case S_IFDIR:
                    let (opened, held) = try FixtureIO.openDirectory(name, in: descriptor, missing: .identityChanged)
                    defer { close(opened) }
                    try directory(opened, held, path: child, depth: depth + 1)
                    _ = try FixtureIO.confirm(opened, named: name, in: descriptor)
                case S_IFREG: try file(name, in: descriptor, entry, path: child)
                default: throw TransactionFailure.specialFile
                }
            }
        }
        mutating func file(_ name: String, in directory: Int32, _ entry: stat, path: String) throws {
            guard entry.st_dev == device else { throw TransactionFailure.crossVolume }
            try FixtureIO.requireFile(entry, modes: BundleTree.fileModes)
            // The size is bounded from the entry itself, before a byte is read.
            guard entry.st_size >= 0, entry.st_size <= TransactionLimits.maximumTotalBytes - total else { throw TransactionFailure.treeLimit }
            total += Int64(entry.st_size)
            let (opened, held) = try FixtureIO.openFile(name, in: directory, missing: .identityChanged)
            defer { close(opened) }
            guard held.st_size == entry.st_size else { throw TransactionFailure.identityChanged }
            try FixtureIO.requireFile(held, modes: BundleTree.fileModes)
            let data = try FixtureIO.read(opened, held)
            _ = try FixtureIO.confirm(opened, named: name, in: directory)
            if sameBytes(path, "Contents/Info.plist") && data.count <= TransactionLimits.maximumInfoPlistBytes { infoPlist = data }
            try append(TreeEntry(path: path, isDirectory: false, mode: UInt16(FixtureIO.permissions(held)),
                                 byteLength: Int64(data.count), sha256: sha256Hex(data)), retain ? data : nil)
        }
    }
}

/// `<name>.app` as one plain path component.
func validBundleName(_ name: String) -> Bool {
    let bytes = Array(name.utf8)
    return bytes.count > 4 && bytes.count <= Int(NAME_MAX) && bytes.suffix(4).elementsEqual(".app".utf8) &&
        !bytes.contains(47) && !bytes.contains(0) && !FixtureIO.hasControl(bytes)
}

/// The pinned bundle manifest: the catalogue artifact of a fixture transaction.
struct ManifestDocument {
    static let kind = "patched-fixture-bundle-manifest-v1"
    let bundleName: String
    let bundleID: String
    let version: String
    let listing: TreeListing

    /// Strict parse. A malformed document is `invalidManifest`; one beyond the fixture bounds is `treeLimit`.
    static func parse(_ data: Data) throws -> ManifestDocument {
        let invalid = TransactionFailure.invalidManifest
        guard let fields = try? CoreJSON.object(data, maximum: TransactionLimits.maximumManifestBytes, failure: .invalidPayload),
              Set(fields.keys) == ["schemaVersion", "kind", "bundleName", "bundleID", "version", "entries"],
              fields["schemaVersion"]?.unsigned == 1, fields["kind"]?.string.map({ sameBytes($0, kind) }) == true,
              let bundleName = fields["bundleName"]?.string, validBundleName(bundleName),
              let bundleID = fields["bundleID"]?.string, validIdentifier(bundleID),
              let version = fields["version"]?.string, (try? NumericVersion(version)) != nil,
              case .array(let rows)? = fields["entries"], !rows.isEmpty else { throw invalid }
        guard rows.count <= TransactionLimits.maximumEntries else { throw TransactionFailure.treeLimit }
        var entries: [TreeEntry] = [], directories = Set<[UInt8]>(), previous: [UInt8]?, total: Int64 = 0
        for (index, row) in rows.enumerated() {
            guard let object = row.object, let path = object["path"]?.string, let type = object["type"]?.string,
                  let mode = object["mode"]?.unsigned, mode <= 0o7777 else { throw invalid }
            let bytes = Array(path.utf8), isDirectory = sameBytes(type, "directory")
            var length: UInt64 = 0, digest = "-"
            if isDirectory {
                guard Set(object.keys) == ["path", "type", "mode"] else { throw invalid }
            } else {
                guard sameBytes(type, "file"), Set(object.keys) == ["path", "type", "mode", "byteLength", "sha256"],
                      let size = object["byteLength"]?.unsigned, let hash = object["sha256"]?.string, validDigest(hash) else { throw invalid }
                length = size; digest = hash
            }
            if index == 0 {
                guard bytes == [46], isDirectory else { throw invalid }
            } else {
                let parts = bytes.split(separator: 47, omittingEmptySubsequences: false)
                guard parts.allSatisfy({ !$0.isEmpty && $0.count <= Int(NAME_MAX) && !$0.elementsEqual([46]) &&
                                         !$0.elementsEqual([46, 46]) && !FixtureIO.hasControl($0) }) else { throw invalid }
                guard parts.count <= TransactionLimits.maximumDepth else { throw TransactionFailure.treeLimit }
                if let previous { guard previous.lexicographicallyPrecedes(bytes) else { throw invalid } }
                previous = bytes
                // Every entry lies beneath a directory entry of this same document.
                guard directories.contains(parts.count == 1 ? [46] : Array(bytes[..<bytes.lastIndex(of: 47)!])) else { throw invalid }
            }
            if isDirectory { directories.insert(bytes) }
            guard length <= UInt64(TransactionLimits.maximumTotalBytes - total) else { throw TransactionFailure.treeLimit }
            total += Int64(length)
            entries.append(TreeEntry(path: path, isDirectory: isDirectory, mode: UInt16(mode), byteLength: Int64(length), sha256: digest))
        }
        return ManifestDocument(bundleName: bundleName, bundleID: bundleID, version: version, listing: TreeListing(entries: entries))
    }

    /// The same schema, written for the old bundle that a transaction freezes.
    var encoded: Data {
        let rows = listing.entries.map { entry in
            "{\"path\":\(jsonString(entry.path)),\"type\":\"\(entry.isDirectory ? "directory" : "file")\",\"mode\":\(entry.mode)" +
                (entry.isDirectory ? "}" : ",\"byteLength\":\(entry.byteLength),\"sha256\":\"\(entry.sha256)\"}")
        }
        return Data(("{\"schemaVersion\":1,\"kind\":\"\(Self.kind)\",\"bundleName\":\(jsonString(bundleName)),\"bundleID\":\(jsonString(bundleID))," +
                     "\"version\":\(jsonString(version)),\"entries\":[\(rows.joined(separator: ","))]}").utf8)
    }
}

/// A JSON string token. Only the quote, the backslash and C0 controls are escaped.
func jsonString(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 34: result += "\\\""
        case 92: result += "\\\\"
        case 0..<32: result += String(format: "\\u%04x", scalar.value)
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}

/// Identity read from the exact `Contents/Info.plist` bytes that were hashed in the tree.
struct BundleIdentity {
    let bundleID: String
    let version: String
    init(_ bundle: PhysicalBundle) throws {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let data = bundle.infoPlist,
              let values = (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) as? [String: Any],
              format == .xml, (values["CFBundlePackageType"] as? String).map({ sameBytes($0, "APPL") }) == true,
              let bundleID = values["CFBundleIdentifier"] as? String, validIdentifier(bundleID),
              let version = values["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            throw TransactionFailure.invalidBundle
        }
        self.bundleID = bundleID; self.version = version
    }
}
