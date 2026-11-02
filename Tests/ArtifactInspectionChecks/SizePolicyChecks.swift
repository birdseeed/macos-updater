import Foundation
import CryptoKit
@_spi(Testing) import ArtifactInspection

private let sizeCeiling: Int64 = 2_147_483_648
private let sizeReserve: Int64 = 67_108_864
private let sizeBytes = Data("abc".utf8)
private let sizeDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
private func sizePin(_ length: Int64 = 3, digest: String = sizeDigest) -> TargetPin {
    .init(version: "synthetic-size-only", url: FirefoxTargets.pins[0].url, sha256: digest, byteLength: length)
}
private func sizeWorkspace(_ body: (URL, URL) throws -> Void) throws {
    try withWorkspace { root in
        let output = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try body(root, output)
    }
}

@MainActor func addSizePolicyChecks() {
    check("PAT-2709 one absolute ceiling and documented staging reserve") {
        try expect(ArtifactSizePolicy.absoluteMaximumBytes == sizeCeiling, "Absolute ceiling must be exactly 2 GiB")
        try expect(ArtifactSizePolicy.stagingReserveBytes == sizeReserve, "Reserve must be exactly 64 MiB")
        try expect(InspectionLimits().downloadBytes == sizeCeiling, "Ordinary downloader still has a divergent default ceiling")
    }
    for length: Int64 in [1, 170_000_001, sizeCeiling - 1, sizeCeiling] {
        check("PAT-2709 shared metadata accepts bounded exact pin \(length)") {
            try ArtifactSizePolicy.validateExpectedLength(length)
            let required = try ArtifactSizePolicy.requiredStagingBytes(expectedLength: length)
            try expect(required == length + sizeReserve, "Staging requirement must preserve pin plus reserve")
        }
    }
    for length: Int64 in [Int64.min, -1, 0, sizeCeiling + 1, Int64.max] {
        check("PAT-2709 invalid pin refuses safely before capacity arithmetic \(length)") {
            try refuses(.invalidMetadata) { try ArtifactSizePolicy.validateExpectedLength(length) }
            try refuses(.invalidMetadata) { _ = try ArtifactSizePolicy.requiredStagingBytes(expectedLength: length) }
        }
    }
    check("PAT-2709 streamed progress reaches exact ceiling using only integer boundaries") {
        let total = try ArtifactSizePolicy.adding(1, to: sizeCeiling - 1, expectedLength: sizeCeiling)
        try expect(total == sizeCeiling, "Exact last byte must be admitted")
        try ArtifactSizePolicy.validateComplete(receivedBytes: total, expectedLength: sizeCeiling)
    }
    for (received, incoming, pin) in [(Int64.max, Int64(1), sizeCeiling), (Int64(1), Int64.max, Int64(3)),
                                    (Int64(-1), Int64(1), Int64(3)), (Int64(1), Int64(-1), Int64(3)),
                                    (Int64(3), Int64(1), Int64(3)), (sizeCeiling, Int64(1), sizeCeiling)] {
        check("PAT-2709 progress overflow negative or exact-pin excess \(received) + \(incoming)") {
            try refuses(.downloadLimit) { _ = try ArtifactSizePolicy.adding(incoming, to: received, expectedLength: pin) }
        }
    }
    for received: Int64 in [0, 2, 4, Int64.max] {
        check("PAT-2709 completed stream requires exact pin \(received)") {
            try refuses(.lengthMismatch) { try ArtifactSizePolicy.validateComplete(receivedBytes: received, expectedLength: 3) }
        }
    }
    check("PAT-2709 raised ordinary download bound still obeys compiled exact signed pin") {
        let pin = FirefoxTargets.pins[0]
        var limits = InspectionLimits(); limits.downloadBytes = sizeCeiling
        try DownloadPolicy.validate(hops: [pin.url], pin: pin, receivedBytes: pin.byteLength, elapsedSeconds: 1, limits: limits)
        try refuses(.downloadLimit) {
            try DownloadPolicy.validate(hops: [pin.url], pin: pin, receivedBytes: pin.byteLength + 1, elapsedSeconds: 1, limits: limits)
        }
        limits.downloadBytes = pin.byteLength - 1
        try refuses(.downloadLimit) {
            try DownloadPolicy.validate(hops: [pin.url], pin: pin, receivedBytes: pin.byteLength, elapsedSeconds: 1, limits: limits)
        }
    }
    for length: Int64 in [170_000_001, sizeCeiling] {
        check("PAT-2709 real descriptor hash accepts large metadata then refuses tiny file length \(length)") {
            try withWorkspace { root in
                let input = root.appendingPathComponent("tiny.bin")
                try sizeBytes.write(to: input)
                try refuses(.lengthMismatch) {
                    try ArtifactBytes.verify(path: input.path, expectedSHA256: sizeDigest, expectedLength: length)
                }
            }
        }
    }
    for length: Int64 in [-1, 0, sizeCeiling + 1, Int64.max] {
        check("PAT-2709 actual descriptor hash refuses invalid or oversized pin \(length)") {
            try withWorkspace { root in
                let input = root.appendingPathComponent("tiny.bin"); try sizeBytes.write(to: input)
                try refuses(.invalidMetadata) {
                    try ArtifactBytes.verify(path: input.path, expectedSHA256: sizeDigest, expectedLength: length)
                }
            }
        }
    }
    for available: Int64? in [nil, -1, 0, sizeReserve + 2] {
        check("PAT-2709 unavailable or insufficient destination capacity \(String(describing: available))") {
            try refuses(.downloadLimit) { try ArtifactSizePolicy.validateStagingCapacity(availableBytes: available, expectedLength: 3) }
        }
    }
    for available in [sizeReserve + 3, Int64.max] {
        check("PAT-2709 destination capacity includes reserve at exact equality \(available)") {
            try ArtifactSizePolicy.validateStagingCapacity(availableBytes: available, expectedLength: 3)
        }
    }
    check("PAT-2709 actual receiver streams tiny chunks and hashes exact pin") {
        try sizeWorkspace { _, output in
            let path = try ArtifactSizeFixtures.download(pin: sizePin(), declaredLength: 3,
                chunks: [Data("a".utf8), Data(), Data("bc".utf8)], workspace: output.path, availableBytes: sizeReserve + 3)
            try expect(path == output.appendingPathComponent("artifact.dmg").path, "Receiver escaped owned staging destination")
            let written = try Data(contentsOf: URL(fileURLWithPath: path))
            try expect(written == sizeBytes, "Receiver changed or omitted stream bytes")
            try ArtifactBytes.verify(path: path, expectedSHA256: sizeDigest, expectedLength: 3)
        }
    }
    for (label, declared, chunks, reason) in [
        ("short content-length", Int64(2), [sizeBytes], InspectionFailure.downloadLimit),
        ("excess content-length", Int64(4), [sizeBytes], .downloadLimit),
        ("unknown content-length", Int64(-1), [sizeBytes], .downloadLimit),
        ("truncated stream", Int64(3), [Data("ab".utf8)], .lengthMismatch),
        ("excess first chunk", Int64(3), [Data("abcd".utf8)], .downloadLimit),
        ("excess later chunk", Int64(3), [sizeBytes, Data("d".utf8)], .downloadLimit),
        ("same-length wrong hash", Int64(3), [Data("abd".utf8)], .digestMismatch)
    ] {
        check("PAT-2709 actual receiver refuses \(label)") {
            try sizeWorkspace { _, output in
                try refuses(reason) {
                    _ = try ArtifactSizeFixtures.download(pin: sizePin(), declaredLength: declared, chunks: chunks,
                                                         workspace: output.path, availableBytes: sizeReserve + 3)
                }
            }
        }
    }
    for route in ["download", "stage"] {
        for available: Int64? in [nil, sizeReserve + 2] {
            check("PAT-2709 actual \(route) refuses capacity before creating output \(String(describing: available))") {
                try sizeWorkspace { root, output in
                    let input = root.appendingPathComponent("input.bin"); try sizeBytes.write(to: input)
                    try refuses(.downloadLimit) {
                        if route == "download" {
                            _ = try ArtifactSizeFixtures.download(pin: sizePin(), declaredLength: 3, chunks: [sizeBytes],
                                                                 workspace: output.path, availableBytes: available)
                        } else {
                            _ = try ArtifactSizeFixtures.stage(path: input.path, pin: sizePin(), workspace: output.path, availableBytes: available)
                        }
                    }
                    let children = try FileManager.default.contentsOfDirectory(atPath: output.path)
                    try expect(children.isEmpty,
                               "Capacity refusal created staging bytes before preflight")
                }
            }
        }
    }
    check("PAT-2709 actual local staging accepts capacity equality and preserves exact digest") {
        try sizeWorkspace { root, output in
            let input = root.appendingPathComponent("input.bin"); try sizeBytes.write(to: input)
            let path = try ArtifactSizeFixtures.stage(path: input.path, pin: sizePin(), workspace: output.path, availableBytes: sizeReserve + 3)
            try ArtifactBytes.verify(path: path, expectedSHA256: sizeDigest, expectedLength: 3)
        }
    }
    check("PAT-2709 synthetic fixture pin never authorises ordinary network download") {
        try refuses(.unknownTarget) {
            let pin = sizePin()
            try DownloadPolicy.validate(hops: [pin.url], pin: pin, receivedBytes: 0, elapsedSeconds: 0)
        }
    }
}
