import Foundation
import Darwin
import PatchedLicensing

@MainActor func registerSubscriptionSummaryChecks() {
    if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--verify-billing-lease" {
        do {
            let o = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
            let binding = LicenceBinding(accountID: o["accountID"] as! String, activationID: o["activationID"] as! String, deviceKeySHA256: o["deviceKeySHA256"] as! String)
            let bytes = Data((o["envelope"] as! String).utf8)
            let lease = try SignedLease.verify(bytes, trust: fixtureTrust, binding: binding, replay: .initialAuthenticatedRefresh)
            try expect(lease.sequence == (o["sequence"] as! NSNumber).int64Value, "Literal service sequence")
            print("PASS billing service exact signed bytes through native SignedLease")
            exit(0)
        } catch { print("FAIL billing native service lease: \(error)"); exit(1) }
    }
    let source = "{\"schemaVersion\":1,\"subscriptionID\":\"sub_fixture_A\",\"status\":\"pastDue\",\"paidThrough\":1790812800,\"renewsAt\":null,\"cancellation\":{\"state\":\"none\",\"accessEnds\":null},\"payment\":{\"state\":\"failed\",\"graceDeadline\":1791417600},\"refund\":\"none\",\"endReason\":null}"
    check("subscription summary displays exact target grace pair") {
        let s = try SubscriptionSummary.decode(Data(source.utf8))
        try expect(s.subscriptionID == "sub_fixture_A" && s.status == "pastDue", "Exact target identity and status")
        try expect(s.paidThrough == 1790812800 && s.graceDeadline == 1791417600 && s.renewsAt == nil, "Never substitute another subscription or infer renewal")
    }
    check("all literal summary vectors decode as display only") {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Fixtures/Billing/summary-vectors.json"))) as! [String: Any]
        for row in object["valid"] as! [[String: Any]] {
            let s = try SubscriptionSummary.decode(JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
            try expect(s.status == row["status"] as? String, "Literal status")
            try expect(s.cancellationState == (row["cancellation"] as! [String:Any])["state"] as? String, "Literal cancellation")
        }
    }
    for (name, text) in [
        ("duplicate", source.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"schemaVersion\":1")),
        ("escaped duplicate", source.replacingOccurrences(of: "\"status\":", with: "\"st\\u0061tus\":\"active\",\"status\":")),
        ("unknown", source.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"installAllowed\":true,\"schemaVersion\":1")),
        ("numeric string", source.replacingOccurrences(of: "1790812800", with: "\"1790812800\"")),
        ("boolean", source.replacingOccurrences(of: "1790812800", with: "true")),
        ("fraction", source.replacingOccurrences(of: "1790812800", with: "1790812800.0")),
        ("exponent", source.replacingOccurrences(of: "1790812800", with: "1e9")),
        ("negative", source.replacingOccurrences(of: "1790812800", with: "-1")),
        ("unsafe", source.replacingOccurrences(of: "1790812800", with: "9007199254740992")),
        ("maximum time", source.replacingOccurrences(of: "1790812800", with: "253402300800")),
        ("wrong version", source.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")),
        ("wrong status", source.replacingOccurrences(of: "pastDue", with: "paid")),
        ("foreign identifier grammar", source.replacingOccurrences(of: "sub_fixture_A", with: "https://foreign.invalid/")),
        ("missing explicit null", source.replacingOccurrences(of: "\"renewsAt\":null,", with: "")),
        ("wrong grace difference", source.replacingOccurrences(of: "1791417600", with: "1791417601")),
        ("nested unknown", source.replacingOccurrences(of: "\"state\":\"failed\"", with: "\"state\":\"failed\",\"grant\":true")),
        ("trailing", source + "true"), ("BOM", "\u{feff}" + source), ("NUL", source + "\0"),
        ("oversized", String(repeating: " ", count: 16385) + source),
    ] {
        check("subscription summary strict refusal \(name)") {
            do { _ = try SubscriptionSummary.decode(Data(text.utf8)) }
            catch { return }
            throw CheckFailure(description: "Malformed display accepted")
        }
    }
}
