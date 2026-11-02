import Foundation
import CoreFoundation
import CryptoKit
import Darwin

/// A physical snapshot, never an issuer credential or persistent identity.
internal struct InstalledIdentityStamp: Codable, Equatable {
    let device: UInt32
    let inode: UInt64
    let mode: UInt32
    let uid: UInt32
    let gid: UInt32
    let links: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ value: stat) {
        device = UInt32(bitPattern: value.st_dev); inode = UInt64(value.st_ino)
        mode = UInt32(value.st_mode); uid = value.st_uid; gid = value.st_gid
        links = UInt64(value.st_nlink); size = value.st_size
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }
    init(descriptor: Int32, type: mode_t) throws {
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == type,
              value.st_nlink > 0 else { throw InspectionFailure.unsafePath }
        self.init(value)
    }
}

internal struct InstalledIdentityBinding: Codable, Equatable {
    let app: InstalledIdentityStamp
    let executable: InstalledIdentityStamp
    let plistSHA256: String
    init(app: Int32, executable: Int32, plist: Data) throws {
        self.app = try InstalledIdentityStamp(descriptor: app, type: S_IFDIR)
        self.executable = try InstalledIdentityStamp(descriptor: executable, type: S_IFREG)
        guard self.executable.links == 1 else { throw InspectionFailure.unsafePath }
        plistSHA256 = SHA256.hash(data: plist).map { String(format: "%02x", $0) }.joined()
    }
}

internal struct InstalledIdentityRequest: Codable, Equatable {
    let schemaVersion: Int
    let appPath: String
    let pin: TargetPin
    let requirement: String
    let validationFlags: UInt32
    let binding: InstalledIdentityBinding
    let nonce: String
}
internal struct InstalledIdentityResult: Codable {
    let kind: String
    let validationStatus: Int32
    let signingInformationStatus: Int32
    let teamID: String
    let identifier: String
    let startedAt: String
    let finishedAt: String
    init(_ value: SignatureObservation) {
        kind = "pinned"; validationStatus = value.validationStatus
        signingInformationStatus = value.signingInformationStatus
        teamID = value.teamID; identifier = value.identifier
        startedAt = value.startedAt; finishedAt = value.finishedAt
    }
    private init() {
        kind = "refused"; validationStatus = -1; signingInformationStatus = -1
        teamID = ""; identifier = ""; startedAt = ""; finishedAt = ""
    }
    static var refused: Self { Self() }
}
internal struct InstalledIdentityEnvelope: Codable {
    let schemaVersion: Int
    let request: InstalledIdentityRequest
    let result: InstalledIdentityResult
}

internal enum InstalledIdentityWire {
    private static func strings(_ object: [String: Any], _ keys: [String]) throws {
        for key in keys { guard object[key] is String else { throw InspectionFailure.invalidRecord } }
    }
    private static func integers(_ object: [String: Any], _ keys: [String]) throws {
        for key in keys {
            guard let value = object[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: value.objCType)) else { throw InspectionFailure.invalidRecord }
        }
    }
    private static func requestObject(_ object: [String: Any]) throws {
        try StrictJSON.keys(object, ["schemaVersion", "appPath", "pin", "requirement", "validationFlags", "binding", "nonce"])
        try strings(object, ["appPath", "requirement", "nonce"])
        try integers(object, ["schemaVersion", "validationFlags"])
        guard let pin = object["pin"] as? [String: Any],
              let binding = object["binding"] as? [String: Any] else { throw InspectionFailure.invalidRecord }
        try StrictJSON.keys(pin, ["version", "url", "sha256", "byteLength", "bundleID", "teamID", "architectures"])
        try strings(pin, ["version", "url", "sha256", "bundleID", "teamID"])
        try integers(pin, ["byteLength"])
        guard pin["architectures"] is [String] else { throw InspectionFailure.invalidRecord }
        try StrictJSON.keys(binding, ["app", "executable", "plistSHA256"])
        try strings(binding, ["plistSHA256"])
        let fields: Set<String> = ["device", "inode", "mode", "uid", "gid", "links", "size",
            "modifiedSeconds", "modifiedNanoseconds", "changedSeconds", "changedNanoseconds"]
        for key in ["app", "executable"] {
            guard let stamp = binding[key] as? [String: Any] else { throw InspectionFailure.invalidRecord }
            try StrictJSON.keys(stamp, fields)
            try integers(stamp, Array(fields))
        }
    }
    static func decodeRequest(_ data: Data) throws -> InstalledIdentityRequest {
        guard data.count <= 32_768 else { throw InspectionFailure.outputLimit }
        let object = try StrictJSON.object(data)
        try requestObject(object)
        let request = try JSONDecoder().decode(InstalledIdentityRequest.self, from: data)
        try validateHeader(request)
        return request
    }
    static func decodeEnvelope(_ data: Data) throws -> InstalledIdentityEnvelope {
        guard data.count <= 16_384 else { throw InspectionFailure.outputLimit }
        let object = try StrictJSON.object(data)
        try StrictJSON.keys(object, ["schemaVersion", "request", "result"])
        try integers(object, ["schemaVersion"])
        guard let request = object["request"] as? [String: Any],
              let result = object["result"] as? [String: Any] else { throw InspectionFailure.invalidRecord }
        try requestObject(request)
        try StrictJSON.keys(result, ["kind", "validationStatus", "signingInformationStatus", "teamID", "identifier", "startedAt", "finishedAt"])
        try strings(result, ["kind", "teamID", "identifier", "startedAt", "finishedAt"])
        try integers(result, ["validationStatus", "signingInformationStatus"])
        let decoded = try JSONDecoder().decode(InstalledIdentityEnvelope.self, from: data)
        guard ["pinned", "refused"].contains(decoded.result.kind) else { throw InspectionFailure.invalidRecord }
        return decoded
    }
    private static func validateHeader(_ request: InstalledIdentityRequest) throws {
        guard request.schemaVersion == 1, FirefoxTargets.pins.contains(request.pin),
              request.appPath.utf8.count <= 4096, safeEvidencePath(request.appPath),
              request.validationFlags == PinnedSignatureRequirement.validationFlags,
              request.requirement == (try PinnedSignatureRequirement.make(teamID: request.pin.teamID, bundleID: request.pin.bundleID)),
              let nonce = UUID(uuidString: request.nonce), nonce.uuidString == request.nonce else {
            throw InspectionFailure.invalidMetadata
        }
    }
    static func validate(_ request: InstalledIdentityRequest, infoPlist: Data) throws {
        try validateHeader(request)
        guard infoPlist.count <= 1_048_576,
              let fields = try PropertyListSerialization.propertyList(from: infoPlist, options: [], format: nil) as? [String: Any],
              fields["CFBundleIdentifier"] as? String == request.pin.bundleID,
              fields["CFBundleShortVersionString"] as? String == request.pin.version,
              fields["CFBundleExecutable"] as? String == "firefox",
              fields["CFBundlePackageType"] as? String == "APPL" else { throw InspectionFailure.invalidMetadata }
    }
}
