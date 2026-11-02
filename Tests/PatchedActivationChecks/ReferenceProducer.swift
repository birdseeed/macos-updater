import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

let fixtureAccount = String(repeating: "a", count: 32)
let otherAccount = String(repeating: "b", count: 32)
let fixtureNow: UInt64 = 1_000
let fixtureMACKey = Data(repeating: 0x46, count: 32)
func fixtureID(_ number: Int) -> String { String(format: "%032x", number) }
func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
func unhex(_ value: String) -> Data {
    var bytes = Data(); var cursor = value.startIndex
    while cursor < value.endIndex {
        let next = value.index(cursor, offsetBy: 2)
        bytes.append(UInt8(value[cursor..<next], radix: 16)!); cursor = next
    }
    return bytes
}
func digest(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }
// Deliberately public, low-entropy test keys. Never used outside this check target.
func fixtureKey(_ number: Int = 1) throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32); scalar[31] = UInt8(number)
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}
func quoted(_ value: String) throws -> String {
    String(data: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
           encoding: .utf8)!
}
// Independent producer: explicit ordered fields; never calls production parser/message code.
func actionBytes(_ operation: DeviceOperation = .activate, request: Int = 1, key: Int = 1,
                 name: String = "Fixture Mac", activation: String = fixtureID(100),
                 revision: String = "1", caseID: String = fixtureID(900),
                 caseDigest: String = String(repeating: "c", count: 64)) throws -> Data {
    var fields = ["\"requestID\":\"\(fixtureID(request))\""]
    switch operation {
    case .activate, .replace:
        let publicKey = try fixtureKey(key).publicKey.x963Representation.base64EncodedString()
        fields += ["\"devicePublicKey\":\"\(publicKey)\"", "\"displayName\":\(try quoted(name))"]
        if operation == .replace { fields += ["\"releaseActivationID\":\"\(activation)\"", "\"expectedRevision\":\(revision)"] }
    case .refresh: fields += ["\"activationID\":\"\(activation)\""]
    case .rebind, .deactivate, .rename:
        fields += ["\"activationID\":\"\(activation)\"", "\"expectedRevision\":\(revision)"]
        if operation == .rename { fields += ["\"displayName\":\(try quoted(name))"] }
    case .recoveryPossession:
        fields += ["\"activationID\":\"\(activation)\"", "\"caseID\":\"\(caseID)\"", "\"caseDigest\":\"\(caseDigest)\""]
    }
    return Data(("{" + fields.joined(separator: ",") + "}").utf8)
}
func referenceMessage(_ action: Data, _ context: PossessionContext) -> Data {
    var result = Data("im.patched.device-proof.v1\0".utf8)
    result.append(context.operation.rawValue)
    result.append(unhex(context.accountID))
    result.append(context.activationID.map(unhex) ?? Data(repeating: 0, count: 16))
    result.append(digest(context.publicKey)); result.append(context.nonce); result.append(digest(action))
    for shift in stride(from: 56, through: 0, by: -8) {
        result.append(UInt8(truncatingIfNeeded: context.expiresAt >> UInt64(shift)))
    }
    return result
}
func bodyBytes(action: Data, challenge: String = fixtureID(500), nonce: Data = Data(repeating: 7, count: 32),
               signature: Data? = nil, extraProof: String = "") -> Data {
    let proof = signature.map { ",\"proof\":{\"challengeID\":\"\(challenge)\",\"nonce\":\"\(nonce.base64EncodedString())\",\"signature\":\"\($0.base64EncodedString())\"\(extraProof)}" } ?? ""
    return Data(("{\"action\":\"\(action.base64EncodedString())\"\(proof)}").utf8)
}
struct ProofFixture {
    var action: Data
    var context: PossessionContext
    var signature: Data
    init(operation: DeviceOperation = .activate, key: Int = 1, request: Int = 1) throws {
        action = try actionBytes(operation, request: request, key: key)
        context = PossessionContext(accountID: fixtureAccount,
            activationID: operation == .activate || operation == .replace ? nil : fixtureID(100),
            operation: operation, publicKey: try fixtureKey(key).publicKey.x963Representation,
            nonce: Data(repeating: 7, count: 32), expiresAt: 1_300)
        signature = try fixtureKey(key).signature(for: referenceMessage(action, context)).rawRepresentation
    }
    var body: Data { bodyBytes(action: action, nonce: context.nonce, signature: signature) }
}
struct ProofVector: Codable {
    let name: String
    let operation: UInt8
    let accountID: String
    let activationID: String?
    let publicKeyBase64: String
    let nonceBase64: String
    let expiresAt: UInt64
    let actionBase64: String
    let actionSHA256: String
    let messageHex: String
    let signatureBase64: String
}
func referenceVectors() throws -> [ProofVector] {
    try [DeviceOperation.activate, .replace, .refresh, .rebind, .recoveryPossession].map { operation in
        let f = try ProofFixture(operation: operation)
        return ProofVector(name: "operation-\(operation.rawValue)", operation: operation.rawValue,
            accountID: f.context.accountID, activationID: f.context.activationID,
            publicKeyBase64: f.context.publicKey.base64EncodedString(), nonceBase64: f.context.nonce.base64EncodedString(),
            expiresAt: f.context.expiresAt, actionBase64: f.action.base64EncodedString(), actionSHA256: hex(digest(f.action)),
            messageHex: hex(referenceMessage(f.action, f.context)), signatureBase64: f.signature.base64EncodedString())
    }
}
