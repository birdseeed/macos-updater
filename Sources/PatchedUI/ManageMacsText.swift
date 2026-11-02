import PatchedActivation
public struct ManageMacsText: Equatable, Sendable {
    public let heading: String
    public let capacity: String
    public let notice: String
    public let rowLabels: [String]
    public let actionLabels: [[String]]
    public init(_ presentation: ManageMacsPresentation) {
        heading = "Manage Macs"
        capacity = "\(presentation.activeCount) of 5 active Macs"
        if presentation.needsVerification {
            notice = "Verify your household session and refresh the Mac list before making changes."
        } else if presentation.limitReached {
            notice = "All five slots are in use. Replacing a Mac requires confirmation."
        } else if presentation.rows.isEmpty {
            notice = "No Macs are listed in this snapshot."
        } else {
            notice = "Deactivation requires confirmation. Released Macs cannot be changed."
        }
        rowLabels = presentation.rows.map { row in
            row.label + (row.isThisMac ? " · This Mac" : "") +
                (row.status == .active ? " · Active" : " · Released")
        }
        actionLabels = presentation.rows.map { row in
            row.intents.map { intent in
                switch intent.kind {
                case .rename: "Rename \(row.label)"
                case .confirmDeactivation: "Deactivate \(row.label), confirmation required"
                case .confirmReplacement: "Replace \(row.label), confirmation required"
                }
            }
        }
    }
}
