import Foundation
import CryptoKit
@_spi(Testing) import PatchedActivation

// Additive Phase A contract. The original diagnostic and earlier acceptance cases stay frozen.
private let fixedReplayStages: Set<String> = [
    "bodyParse", "bodyActionMatches", "bodyPublicKeyMatches", "bodySignatureMatches", "bodyNonceMatches",
    "referenceMessageMatches", "productionMessageMatches", "cryptoKitKeyConstruction",
    "cryptoKitSignatureConstruction", "cryptoKitRawRoundTrip", "canonicalDERConstruction",
    "cryptoKitDERMatchesCanonical", "cryptoKitDERRoundTrip", "cryptoKitMessageVerification",
    "cryptoKitDigestVerification", "securityKeyConstruction", "securityMessageAlgorithm",
    "securityDigestAlgorithm", "securityMessageVerification", "securityDigestVerification", "productionProof"
]
private let capturedDERHex = "3044022003eb3b8263dffe5324cf0e86e10ac7be461859d44bd457c18f48d8f0160c8b71"
    + "022071826ce1b7ead67404f88aeb113f764a2ac1a1bcd426a3805323ab0ddee41b4f"
private func fixedReplayInput() throws -> FixedProofReplayInput {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/ci-refused-20261009.json"))
    return try JSONDecoder().decode(FixedProofReplayInput.self, from: bytes)
}
private func requireStage(_ report: FixedProofReplayReport, _ name: String,
                          _ status: FixedProofReplayStatus) throws {
    try expect(report.stages[name]?.status == status, "Replay stage \(name) missing or not \(status.rawValue)")
}
private func completeReplay(_ input: FixedProofReplayInput) throws -> FixedProofReplayReport {
    let report = FixedProofReplay.inspect(input)
    try expect(report.availability == .complete && report.reason == nil,
               "Fixed public proof replay report not implemented or unavailable")
    try expect(Set(report.stages.keys) == fixedReplayStages, "Missing or invented replay stage")
    return report
}
@MainActor func registerFixedProofReplayChecks() {
    check("fixed replay original CI vector retains exact public bytes") {
        let input = try fixedReplayInput()
        let raw = try Data(contentsOf: URL(fileURLWithPath: "Fixtures/Activation/ci-refused-20261009.json"))
        try expect(hex(digest(raw)) == "d161a050ee1786f96bebb8b657d370c7a662ce4f1ea3592bf0f406e12395995d", "Original full CI diagnostic changed")
        try expect(hex(digest(input.body)) == "c25c668d957c100a5752811cb36243b797efa5a9a20bf75a1f47f9fec92e3862", "Original CI body changed")
        try expect(hex(digest(input.action)) == "f9c4fb8ee18180c1632325baba1c1b8a9c507656cc47885fa80787b0fbc8d5b2", "Original CI action changed")
        try expect(hex(digest(input.publicKey)) == "7710e28392251c0b70f8299fd465e9c200db6e7c415d18bae009e1ac75b17dc9", "Original CI key changed")
        try expect(hex(digest(input.referenceMessage)) == "17199d49f4360752cb56768b0d80e535c199aefe2790cc7c21a891bb34e7706f", "Original CI message changed")
        try expect(hex(digest(input.signature)) == "69faf68abe33c603d17ba21ae4020c280c1cea2caa13b45808feab4a26b48d71", "Original CI signature changed")
        try expect(input.operation == 2 && input.accountID == Data(fixtureAccount.utf8)
                   && input.activationID == nil && input.nonce == Data(repeating: 2, count: 32)
                   && input.expiresAt == 1_300 && input.now == 1_000, "Original CI context changed")
    }
    check("fixed replay known valid captured proof reports every independent stage") {
        let input = try fixedReplayInput()
        let report = FixedProofReplay.inspect(input)
        // Emit before acceptance assertions so affected-platform refusals retain all available stages.
        print(try FixedProofReplay.render(report))
        try expect(report.availability == .complete && report.reason == nil, "Fixed replay not implemented")
        try expect(report.input == input && Set(report.stages.keys) == fixedReplayStages, "Exact input/stages absent")
        let rawVerification = Set(["cryptoKitMessageVerification", "cryptoKitDigestVerification",
                                   "securityMessageVerification", "securityDigestVerification"])
        for name in fixedReplayStages.sorted() {
            if rawVerification.contains(name) {
                try expect(report.stages[name]?.status == .accepted || report.stages[name]?.status == .refused,
                           "Raw verification must record an actual accepted/refused result")
            } else {
                try requireStage(report, name, .accepted)
            }
            try expect(report.stages[name]?.errorType == nil, "Successful stage carries constructor error")
        }
        try expect(report.canonicalDER == unhex(capturedDERHex) && report.cryptoKitDER == report.canonicalDER,
                   "Captured signature DER differs from independent literal golden")
    }
    check("fixed replay report serialises exact stages bytes and runtime with bounded output") {
        let input = try fixedReplayInput(); let report = try completeReplay(input)
        let text = try FixedProofReplay.render(report)
        try expect(text.utf8.count <= FixedProofReplay.maximumOutputBytes && !text.contains("\n"), "Report is not one bounded line")
        let decoded = try JSONDecoder().decode(FixedProofReplayReport.self, from: Data(text.utf8))
        try expect(decoded.schema == 1 && decoded.scope == "fixed-public-proof-replay" && decoded.input == input, "Report altered identity/public bytes")
        try expect(decoded.stages == report.stages && Set(decoded.stages.keys) == fixedReplayStages, "Encoded stages missing")
        try expect(decoded.os == ProcessInfo.processInfo.operatingSystemVersionString, "Report invents runtime OS")
        #if arch(arm64)
        try expect(decoded.architecture == "arm64", "Report invents runtime architecture")
        #elseif arch(x86_64)
        try expect(decoded.architecture == "x86_64", "Report invents runtime architecture")
        #else
        try expect(decoded.architecture == "other", "Report invents runtime architecture")
        #endif
    }
    check("fixed replay canonical DER retains exact captured signature") {
        let input = try fixedReplayInput()
        try expect(try FixedProofReplay.canonicalDER(rawSignature: input.signature) == unhex(capturedDERHex), "Canonical DER wrong")
    }
    check("fixed replay canonical DER removes redundant zero and adds positive padding") {
        let raw = Data(repeating: 0, count: 31) + Data([1, 0x80]) + Data(repeating: 0, count: 31)
        let golden = unhex("302602010102210080" + String(repeating: "00", count: 31))
        try expect(try FixedProofReplay.canonicalDER(rawSignature: raw) == golden, "Unsigned DER padding/trimming wrong")
        try expect(try FixedProofReplay.canonicalDER(rawSignature: Data(repeating: 0, count: 64)) == unhex("3006020100020100"), "Zero INTEGER encoding wrong")
    }
    check("fixed replay canonical DER refuses non raw64 input") {
        for count in [0, 63, 65, 72] {
            do {
                _ = try FixedProofReplay.canonicalDER(rawSignature: Data(repeating: 0, count: count))
                throw CheckFailure(description: "Non raw64 DER accepted")
            } catch let error as FixedProofReplayError {
                try expect(error == .invalidSignatureLength, "Wrong DER refusal type: \(error.rawValue)")
            }
        }
    }
    check("fixed replay tampered signature remains exact and both verifiers refuse") {
        var input = try fixedReplayInput(); input.signature[0] ^= 1
        let report = try completeReplay(input)
        try expect(report.input == input, "Tampered signature replaced")
        try requireStage(report, "bodySignatureMatches", .refused)
        for name in ["cryptoKitMessageVerification", "cryptoKitDigestVerification", "securityMessageVerification",
                     "securityDigestVerification", "productionProof"] { try requireStage(report, name, .refused) }
        try requireStage(report, "bodyParse", .accepted)
        try requireStage(report, "cryptoKitSignatureConstruction", .accepted)
    }
    check("fixed replay changed captured message refuses independently of production proof") {
        var input = try fixedReplayInput(); input.referenceMessage[0] ^= 1
        let report = try completeReplay(input)
        try expect(report.input == input, "Changed captured message replaced")
        for name in ["referenceMessageMatches", "productionMessageMatches", "cryptoKitMessageVerification",
                     "cryptoKitDigestVerification", "securityMessageVerification", "securityDigestVerification"] {
            try requireStage(report, name, .refused)
        }
        try requireStage(report, "productionProof", .accepted)
    }
    check("fixed replay parsed body mismatches do not substitute cryptographic inputs") {
        var input = try fixedReplayInput()
        input.body = bodyBytes(action: try actionBytes(.replace, request: 501, key: 8),
                               challenge: fixtureID(501), nonce: Data(repeating: 3, count: 32),
                               signature: input.signature)
        let report = try completeReplay(input)
        try expect(report.input == input, "Mismatched body substituted capture fields")
        try requireStage(report, "bodyParse", .accepted)
        for name in ["bodyActionMatches", "bodyPublicKeyMatches", "bodyNonceMatches"] {
            try requireStage(report, name, .refused)
        }
        for name in ["bodySignatureMatches", "productionProof"] {
            try requireStage(report, name, .accepted)
        }
        let baseline = try completeReplay(fixedReplayInput())
        for name in ["cryptoKitMessageVerification", "cryptoKitDigestVerification",
                     "securityMessageVerification", "securityDigestVerification"] {
            try expect(report.stages[name] == baseline.stages[name], "Body mismatch changed raw verification stage")
        }
    }
    check("fixed replay malformed body preserves bytes and independent cryptography") {
        var input = try fixedReplayInput(); input.body = Data([0, 0xff, 10, 27])
        let report = try completeReplay(input)
        try expect(report.input == input, "Malformed body lost")
        try requireStage(report, "bodyParse", .error)
        try expect(report.stages["bodyParse"]?.errorType == .invalidRequest, "Parse error type absent")
        for name in ["bodyActionMatches", "bodyPublicKeyMatches", "bodySignatureMatches", "bodyNonceMatches"] {
            try requireStage(report, name, .unavailable)
        }
        let baseline = try completeReplay(fixedReplayInput())
        for name in ["cryptoKitMessageVerification", "cryptoKitDigestVerification",
                     "securityMessageVerification", "securityDigestVerification"] {
            try expect(report.stages[name] == baseline.stages[name], "Malformed body changed raw verification stage")
        }
        try requireStage(report, "productionProof", .accepted)
    }
    check("fixed replay key construction error is separate from signature construction") {
        var input = try fixedReplayInput(); input.publicKey = Data([4])
        let report = try completeReplay(input)
        try expect(report.input == input, "Malformed key replaced")
        try requireStage(report, "cryptoKitKeyConstruction", .error)
        try requireStage(report, "securityKeyConstruction", .error)
        try expect(report.stages["cryptoKitKeyConstruction"]?.errorType == .cryptoKitError
                   && report.stages["securityKeyConstruction"]?.errorType == .securityError, "Constructor error types collapsed")
        try requireStage(report, "cryptoKitSignatureConstruction", .accepted)
        try requireStage(report, "cryptoKitMessageVerification", .unavailable)
        try requireStage(report, "securityMessageVerification", .unavailable)
    }
    check("fixed replay signature construction error is separate from key construction") {
        var input = try fixedReplayInput(); input.signature = Data([1])
        let report = try completeReplay(input)
        try expect(report.input == input, "Malformed signature replaced")
        try requireStage(report, "cryptoKitSignatureConstruction", .error)
        try expect(report.stages["cryptoKitSignatureConstruction"]?.errorType == .cryptoKitError, "Signature error type absent")
        try requireStage(report, "cryptoKitKeyConstruction", .accepted)
        try requireStage(report, "canonicalDERConstruction", .error)
        try expect(report.stages["canonicalDERConstruction"]?.errorType == .invalidSignatureLength, "DER length error absent")
        try requireStage(report, "cryptoKitMessageVerification", .unavailable)
        try requireStage(report, "securityMessageVerification", .unavailable)
    }
    check("fixed replay input bounds do not truncate or echo oversized public data") {
        var input = try fixedReplayInput(); input.body = Data(repeating: 65, count: 16_385)
        let report = FixedProofReplay.inspect(input)
        try expect(report.availability == .unavailable && report.reason == .inputBound && report.input == nil,
                   "Oversized input processed, truncated or echoed")
        let text = try FixedProofReplay.render(report)
        try expect(text.utf8.count <= FixedProofReplay.maximumOutputBytes, "Oversized input caused oversized output")
    }
    check("fixed replay renderer refuses oversized encoded report without truncation") {
        var report = FixedProofReplayReport()
        var input = try fixedReplayInput(); input.body = Data(repeating: 65, count: 65_537)
        report.input = input
        do {
            _ = try FixedProofReplay.render(report)
            throw CheckFailure(description: "Oversized report encoded")
        } catch let error as FixedProofReplayError {
            try expect(error == .outputBound, "Wrong oversized report refusal type")
        }
    }
    check("fixed replay malformed context reports unavailable without reference traps") {
        var input = try fixedReplayInput(); input.accountID = Data("not-hex\n".utf8)
        let report = FixedProofReplay.inspect(input)
        try expect(report.availability == .unavailable && report.reason == .inputShape && report.input == nil,
                   "Malformed context reached unhex or invented proof results")
    }
}
