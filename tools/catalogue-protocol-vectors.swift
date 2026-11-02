// CryptoKit checks only. This is NOT a Swift catalogue schema/consumer verifier.
import Foundation
import CryptoKit

struct TestKey: Decodable { let warning: String; let seedHex: String; let publicKeyBase64: String }
struct Vector: Decodable {
    let name: String; let payloadFile: String; let envelopeFile: String
    let payloadSHA256: String; let messageBase64: String; let signatureBase64: String
}
struct Corpus: Decodable { let vectors: [Vector] }
struct SwiftVector: Encodable { let name: String; let publicKeyBase64: String; let messageBase64: String; let signatureBase64: String }
struct Envelope: Decodable { let schema: String; let algorithm: String; let keyID: String; let payload: String; let signature: String }
enum CheckError: Error { case failed(String) }
func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
    guard condition() else { throw CheckError.failed(label) }
}
func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
func unhex(_ text: String) throws -> Data {
    let chars = Array(text.utf8)
    guard chars.count == 64 else { throw CheckError.failed("test seed length") }
    var bytes = [UInt8]()
    for i in stride(from: 0, to: chars.count, by: 2) {
        guard let b = UInt8(String(bytes: chars[i...i+1], encoding: .utf8)!, radix: 16) else { throw CheckError.failed("test seed encoding") }
        bytes.append(b)
    }
    return Data(bytes)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("services/catalogue/protocol/fixtures/catalogue-v2", isDirectory: true)
// Paths are fixed local test fixtures, never supplied by an envelope or a remote caller.
let allowed = Set(["TEST-ONLY-key.json", "golden-vectors.json", "empty.payload.json", "empty.envelope.json", "one-entry.payload.json", "one-entry.envelope.json", "withdrawal.payload.json", "withdrawal.envelope.json", "whitespace.payload.json", "whitespace.envelope.json"])
func read(_ name: String) throws -> Data {
    try require(allowed.contains(name), "fixture filename allowlist")
    let data = try Data(contentsOf: root.appendingPathComponent(name))
    try require(data.count <= 65536, "bounded golden file")
    return data
}
let decoder = JSONDecoder()
let key = try decoder.decode(TestKey.self, from: read("TEST-ONLY-key.json"))
try require(key.warning.contains("NEVER USE FOR PRODUCTION"), "labelled test seed")
let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: unhex(key.seedHex))
try require(signing.publicKey.rawRepresentation.base64EncodedString() == key.publicKeyBase64, "independent public key reproduction")
let corpus = try decoder.decode(Corpus.self, from: read("golden-vectors.json"))
try require(corpus.vectors.map(\.name) == ["empty", "one-entry", "withdrawal", "whitespace"], "complete ordered corpus")
var swiftVectors = [SwiftVector]()
for vector in corpus.vectors {
    let payload = try read(vector.payloadFile)
    let envelope = try decoder.decode(Envelope.self, from: read(vector.envelopeFile))
    let message = Data("im.patched.catalogue.v2".utf8) + Data([0]) + payload
    try require(message.base64EncodedString() == vector.messageBase64, "\(vector.name) exact message")
    try require(hex(Data(SHA256.hash(data: payload))) == vector.payloadSHA256, "\(vector.name) SHA256")
    try require(envelope.payload == payload.base64EncodedString(), "\(vector.name) envelope payload")
    try require(envelope.schema == "fixture-catalogue-envelope-v2" && envelope.algorithm == "Ed25519" && envelope.keyID == "test-key-1", "\(vector.name) fixed envelope fields")
    guard let goldenSignature = Data(base64Encoded: vector.signatureBase64) else { throw CheckError.failed("golden signature encoding") }
    try require(envelope.signature == vector.signatureBase64, "\(vector.name) exact golden signature bytes")
    try require(signing.publicKey.isValidSignature(goldenSignature, for: message), "\(vector.name) independent golden verification")
    // CryptoKit randomises signing to guard side channels. Only verification, not
    // signature-byte equality, is promised by Apple's signature(for:) API.
    let signature = try signing.signature(for: message)
    try require(signing.publicKey.isValidSignature(signature, for: message), "\(vector.name) generated signature verifies")
    let otherKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(repeating: 1, count: 32))
    try require(!otherKey.isValidSignature(goldenSignature, for: message), "\(vector.name) wrong key refuses")
    try require(!signing.publicKey.isValidSignature(goldenSignature, for: payload), "\(vector.name) golden wrong domain refuses")
    try require(!signing.publicKey.isValidSignature(goldenSignature, for: message + Data([32])), "\(vector.name) golden tamper refuses")
    swiftVectors.append(SwiftVector(name: vector.name, publicKeyBase64: signing.publicKey.rawRepresentation.base64EncodedString(), messageBase64: message.base64EncodedString(), signatureBase64: signature.base64EncodedString()))
    try require(!signing.publicKey.isValidSignature(signature, for: payload), "\(vector.name) missing domain refuses")
    try require(!signing.publicKey.isValidSignature(signature, for: message + Data([32])), "\(vector.name) byte tamper refuses")
    FileHandle.standardError.write(Data("PASS CryptoKit \(vector.name): exact message/key/hash, fixed golden verification and key/domain/tamper refusals\n".utf8))
}
FileHandle.standardError.write(Data("PASS 4 independent CryptoKit vectors; crypto only, no schema/installation authority\n".utf8))
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
print(String(data: try encoder.encode(swiftVectors), encoding: .utf8)!)
