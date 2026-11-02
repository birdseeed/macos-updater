import Foundation
public struct LicenceSupportViewText: Equatable {
    public let title: String
    public let notice: String
    public let status: String
    public let rows: [LicenceSupportRow]
    public let consequences: [String]
    public let confirmTitle: String
    public let recoveryNotice: String
    public let canConfirm: Bool
    public var accessibilityText: String {
        ([title, notice, status] + rows.flatMap { [$0.label, $0.value] } + consequences + [confirmTitle, recoveryNotice]).joined(separator: "\n")
    }
    @MainActor public init(_ controller: LicenceSupportController) {
        title = "Licence support"; notice = "Local support preview. No real account is accessed."
        status = switch controller.state {
        case .idle: "Support is unavailable. No account is loaded."
        case .readOnly: "Read-only synthetic account facts. No action has been prepared."
        case .confirmation: "Review the exact target and every consequence before confirming."
        case .requested: "Requested. Provider effects are not confirmed. Refund and renewal stop require separate confirmation."
        case .unknown: "Outcome unknown. Do not repeat the request; resolve it by readback."
        case .failed: "Action unavailable or refused. No success is established."
        case .confirmed: "Confirmed in this synthetic preview only. No real action was performed."
        }
        rows = controller.rows; consequences = controller.consequences
        confirmTitle = "Confirm this exact action"; recoveryNotice = "Account recovery is unavailable."
        canConfirm = controller.canConfirm
    }
}
