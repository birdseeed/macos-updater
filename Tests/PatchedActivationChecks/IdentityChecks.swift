import Foundation
@_spi(Testing) import PatchedActivation

@MainActor func registerIdentityChecks() {
    for (input, expected) in [("A", "A"), ("  Café  ", "Café"), ("Cafe\u{301}", "Café"),
                              (String(repeating: "猫", count: 64), String(repeating: "猫", count: 64)),
                              (String(repeating: "🐈", count: 64), String(repeating: "🐈", count: 64)),
                              ("<script>fixture</script>", "<script>fixture</script>")] {
        check("Unicode name accepts \(input.utf8.count) bytes and normalises as text") {
            try expect(ActivationIdentity.displayName(input) == expected, "Name lost scalar/NFC/plain-text meaning")
        }
    }
    for input in ["", "   ", String(repeating: "a", count: 65), String(repeating: "🐈", count: 65),
                  "\nMac", "Mac\r", "Mac\t", "Mac\0", "Mac\u{7f}", "Mac\u{202e}", "Mac\u{2028}", "Mac\u{2029}",
                  String(repeating: "x\u{301}", count: 33)] {
        check("invalid name raw scalars \(input.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ":")) refuses") {
            try refuses(.invalidRequest) { _ = try ActivationIdentity.displayName(input) }
        }
    }
    check("identifier exact lower hex bytes") {
        try expect(ActivationIdentity.identifierBytes(fixtureAccount) == Data(repeating: 0xaa, count: 16), "Identifier bytes differ")
    }
    for identifier in [String(repeating: "A", count: 32), "g" + String(repeating: "a", count: 31), String(repeating: "a", count: 31), String(repeating: "a", count: 33)] {
        check("invalid identifier \(identifier) refuses") {
            try refuses(.invalidRequest) { _ = try ActivationIdentity.identifierBytes(identifier) }
        }
    }
    check("public key hash is SHA256 of valid uncompressed P256") {
        let bytes = try fixtureKey().publicKey.x963Representation
        try expect(ActivationIdentity.publicKeyDigest(bytes) == digest(bytes), "Key hash differs")
    }
    for bytes in [Data(), Data(repeating: 4, count: 65), Data([4]) + Data(repeating: 0, count: 64), Data(repeating: 2, count: 33)] {
        check("invalid curve point \(bytes.count) bytes refuses") {
            try refuses(.invalidRequest) { _ = try ActivationIdentity.publicKeyDigest(bytes) }
        }
    }
    check("default key provider refuses read and signing") {
        let provider = UnavailableActivationKeyProvider()
        try refuses(.keyUnavailable) { _ = try provider.existingPublicKey() }
        try refuses(.keyUnavailable) { _ = try provider.signPossessionMessage(Data(repeating: 0, count: 164)) }
    }
    check("absent or unsupported optional adapter selects honest fallback") {
        try expect(AttestationBinding.assurance(evidenceSupplied: false, adapterAvailable: false) == .secureStorageFallback, "Unavailable adapter claimed hardware")
        try expect(AttestationBinding.assurance(evidenceSupplied: false, adapterAvailable: true) == .secureStorageFallback, "Absent evidence claimed attestation")
    }
    check("supplied evidence without validation refuses") {
        try refuses(.proofRefused) { _ = try AttestationBinding.assurance(evidenceSupplied: true, adapterAvailable: false) }
    }
}
