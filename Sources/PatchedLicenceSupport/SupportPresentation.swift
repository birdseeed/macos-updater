public struct SupportDisplayField: Equatable, Sendable {
    public let path: String
    public let text: String
}
/// Literal text values only. A future native view must use text controls, never an HTML renderer.
public struct SupportPresentation: Sendable {
    public let fields: [SupportDisplayField]
    public let consequenceWords: [String]
    public static func confirmation(_ value: SupportConfirmation) throws -> SupportPresentation {
        let words: [String]
        switch value.target {
        case .activation(let a):
            words = ["Release Mac \(a.activationID) from slot \(a.slot). Cached update starts can continue until its next successful check or \(a.maxGrantPermittedUntil.map(String.init) ?? "no previously issued grant"), whichever is first. An update underway can finish or recover."]
        case .account:
            words = ["Resend only to the registered address \(value.maskedEmail) under the ordinary limits. This neither signs anyone in nor changes the address."]
        case .provider(let p):
            switch value.action {
            case .reconcileProviderState:
                words = ["Reconcile \(p.subscriptionID). Entitlement may rise or fall to match confirmed provider state."]
            case .initiateCancellation:
                words = ["Request renewal cancellation for \(p.subscriptionID). Requested is not confirmed. Existing paid access ends at \(p.paidThrough)."]
            case .initiateRefund:
                guard let transaction = p.transactionID, let start = p.periodStart, let end = p.periodEnd else {
                    throw SupportError.malformedDescriptor
                }
                words = ["Request the full refund for \(transaction), interval \(start) to \(end). That interval's access ends only after provider approval is read.",
                         "Request the separate stop to future renewal for \(p.subscriptionID). The renewal stop needs its own confirmation."]
            default: throw SupportError.malformedDescriptor
            }
        case .recovery(let r):
            words = ["Change this account to \(r.newMaskedEmail), revoke all its sessions and release all \(r.activations.count) occupied Mac slots. Cached grants remain bounded by the displayed recorded maxima. Account identity and entitlement history are preserved; sign in and activate again."]
        }
        return SupportPresentation(fields: flatten(value.object), consequenceWords: words)
    }
    private static func flatten(_ node: SupportJSON, path: String = "") -> [SupportDisplayField] {
        switch node {
        case .object(let values):
            return values.flatMap { key, value in flatten(value, path: path.isEmpty ? key : path + "." + key) }
        case .array(let values):
            return values.enumerated().flatMap { offset, value in flatten(value, path: path + "[\(offset)]") }
        case .string(let text): return [SupportDisplayField(path: path, text: text)]
        case .number(let n): return [SupportDisplayField(path: path, text: String(n))]
        case .bool(let b): return [SupportDisplayField(path: path, text: b ? "true" : "false")]
        case .null: return [SupportDisplayField(path: path, text: "null")]
        }
    }
}
