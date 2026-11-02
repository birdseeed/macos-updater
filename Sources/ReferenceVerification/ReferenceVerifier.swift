import Foundation
import CryptoKit
import Darwin

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

private struct Manifest: Decodable {
    let schema_version: Int
    let files: [Reference]
}

private struct Reference: Decodable {
    let destination: String
    let sha256: String
    let byte_length: Int
    let read_only_reference: Bool
    let actionable: Bool
    let extracted: Bool
    let source_repository: String
    let source_commit: String
    let source_path: String
    let source_git_blob: String
    let source_url: String
    let verification: [String: String]
}

public enum ReferenceVerifier {
    private static let limit = 1_048_576
    private static let destinations: Set<String> = [
        "ThirdParty/Installomator/LICENSE", "References/Legacy/firefox.recipe.json"
    ]

    public static func verify(root: URL) throws -> [String] {
        guard root.isFileURL, root.path.hasPrefix("/"), !root.path.contains("\0") else {
            throw VerificationFailure(description: "Root must be a local directory")
        }
        let filesystem = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard filesystem >= 0 else { throw failure("Cannot open filesystem root") }
        defer { close(filesystem) }
        let directory = try openPath(root.path, from: filesystem, directory: true)
        defer { close(directory) }
        let data = try read("source-provenance.json", from: directory)
        // Root metadata may evolve; reference records have a closed vocabulary.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let allowed: Set<String> = ["destination", "sha256", "byte_length", "read_only_reference",
            "actionable", "extracted", "source_repository", "source_commit", "source_path",
            "source_git_blob", "source_url", "verification"]
        guard let records = object?["files"] as? [[String: Any]],
              records.allSatisfy({ Set($0.keys).isSubset(of: allowed) }) else {
            throw VerificationFailure(description: "Malformed reference records or unexpected fields")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schema_version == 1, manifest.files.count == 2,
              Set(manifest.files.map(\.destination)) == destinations else {
            throw VerificationFailure(description: "Expected schema 1 and exactly the two preserved references")
        }
        for reference in manifest.files {
            guard reference.read_only_reference, !reference.actionable, reference.extracted,
                  reference.byte_length > 0, reference.byte_length <= limit,
                  hex(reference.sha256, count: 64), hex(reference.source_commit, count: 40),
                  hex(reference.source_git_blob, count: 40), !reference.source_repository.isEmpty,
                  !reference.source_url.isEmpty, !reference.source_path.isEmpty else {
                throw VerificationFailure(description: "Invalid reference metadata: \(reference.destination)")
            }
            let bytes = try read(reference.destination, from: directory)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard bytes.count == reference.byte_length, digest == reference.sha256 else {
                throw VerificationFailure(description: "Reference length or SHA-256 mismatch: \(reference.destination)")
            }
        }
        return destinations.sorted()
    }

    private static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func failure(_ message: String) -> VerificationFailure {
        VerificationFailure(description: "\(message): \(String(cString: strerror(errno)))")
    }

    // Walk from an open descriptor: no ancestor or final symlink is followed,
    // including if a path is replaced between component opens.
    private static func openPath(_ path: String, from base: Int32, directory: Bool) throws -> Int32 {
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0 == "." || $0 == ".." || $0.contains("\0") }) else {
            throw VerificationFailure(description: "Unsafe path")
        }
        var current = fcntl(base, F_DUPFD_CLOEXEC, 0)
        guard current >= 0 else { throw failure("Cannot retain directory") }
        for (index, component) in components.enumerated() {
            let isDirectory = directory || index < components.count - 1
            let next = openat(current, component, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK |
                (isDirectory ? O_DIRECTORY : 0))
            let error = next < 0 ? failure("Cannot safely open \(path)") : nil
            close(current)
            if let error { throw error }
            current = next
        }
        return current
    }

    private static func read(_ path: String, from directory: Int32) throws -> Data {
        let descriptor = try openPath(path, from: directory, directory: false)
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else {
            throw VerificationFailure(description: "Expected a regular file of at most \(limit) bytes: \(path)")
        }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw failure("Cannot read \(path)")
            }
            if count == 0 { return bytes }
            guard bytes.count + count <= limit else {
                throw VerificationFailure(description: "File exceeds size limit: \(path)")
            }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }
}
