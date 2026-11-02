import Foundation

/// One absolute byte ceiling; an authenticated exact-length pin is always stricter.
public enum ArtifactSizePolicy {
    public static let absoluteMaximumBytes: Int64 = 2_147_483_648
    /// Free bytes to retain on the staging volume, beyond the artifact itself.
    public static let stagingReserveBytes: Int64 = 67_108_864

    public static func validateExpectedLength(_ length: Int64) throws {
        guard length > 0, length <= absoluteMaximumBytes else { throw InspectionFailure.invalidMetadata }
    }
    public static func adding(_ incomingBytes: Int64, to receivedBytes: Int64, expectedLength: Int64) throws -> Int64 {
        try validateExpectedLength(expectedLength)
        let (total, overflow) = receivedBytes.addingReportingOverflow(incomingBytes)
        guard incomingBytes >= 0, receivedBytes >= 0, !overflow, total <= expectedLength else {
            throw InspectionFailure.downloadLimit
        }
        return total
    }
    public static func validateComplete(receivedBytes: Int64, expectedLength: Int64) throws {
        try validateExpectedLength(expectedLength)
        guard receivedBytes == expectedLength else { throw InspectionFailure.lengthMismatch }
    }
    public static func requiredStagingBytes(expectedLength: Int64) throws -> Int64 {
        try validateExpectedLength(expectedLength)
        let (required, overflow) = expectedLength.addingReportingOverflow(stagingReserveBytes)
        guard !overflow else { throw InspectionFailure.invalidMetadata }
        return required
    }
    public static func validateStagingCapacity(availableBytes: Int64?, expectedLength: Int64) throws {
        let required = try requiredStagingBytes(expectedLength: expectedLength)
        guard let availableBytes, availableBytes >= required else { throw InspectionFailure.downloadLimit }
    }
}

/// Fixture-only transport/capacity injection. Uses ordinary receiver and descriptor
/// hash/staging mechanics. Synthetic pins grant no ordinary network or OS trust.
@_spi(Testing) public enum ArtifactSizeFixtures {
    public static func download(pin: TargetPin, declaredLength: Int64, chunks: [Data],
                                workspace: String, availableBytes: Int64?) throws -> String {
        try downloadFixture(pin: pin, declaredLength: declaredLength, chunks: chunks,
                            workspace: workspace, availableBytes: availableBytes)
    }
    public static func stage(path: String, pin: TargetPin, workspace: String, availableBytes: Int64?) throws -> String {
        try SafeFiles.stage(path: path, pin: pin, workspace: workspace, capacity: { _ in availableBytes })
    }
}
