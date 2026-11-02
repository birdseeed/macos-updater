import Foundation
@_spi(Testing) import PatchedCore

@MainActor func registerSizePolicyCatalogueChecks() {
    for length: Int64 in [1, 170_000_000, 170_000_001, 2_147_483_647, 2_147_483_648] {
        check("PAT-2709 signed v1 catalogue accepts exact byte pin \(length)") {
            try withWorkspace { root in
                try seedState(root)
                let envelope = try mutateArtifact { $0["byteLength"] = length }
                let result = try Fixture.verifier(root).verify(envelope: envelope, now: Fixture.now)
                try expect(result.artifact.byteLength == length, "Signed length was rounded or clamped")
                let outer = try object(envelope)
                let payload = Data(base64Encoded: outer["payload"] as! String)!
                try assertCheckpoint(root, sequence: 7, payload: payload)
                try expect(!result.installationAuthorized && !result.freshOSValidation, "Size pin granted authority")
            }
        }
    }
    for length: Any in [0, -1, 2_147_483_649 as Int64, Int64.max, UInt64.max, 3.5, true, "2147483648", NSNull()] {
        check("PAT-2709 invalid or oversized signed byte pin \(length) refuses without checkpoint write") {
            try verifyRefusal(mutateArtifact { $0["byteLength"] = length }, .invalidPayload)
        }
    }
}
