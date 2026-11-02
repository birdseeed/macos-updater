import PatchedCore

// PAT-2582: the visible words for one prepared presentation.
// See docs/transaction-recovery.md for the visible text contract.

/// The words the view shows for one prepared presentation. Display only: it holds no
/// callback and no path authority, and it can never enable an action the presentation disabled.
public struct UpdateViewText: Equatable, Sendable {
    public let previewNotice: String
    public let heading: String
    public let installedLine: String
    public let checkedLine: String
    public let checks: [UpdateCheckRow]
    public let refusalLine: String?
    public let deferralLine: String?
    public let actionTitle: String
    public let actionEnabled: Bool
    public let actionNote: String

    public init(_ presentation: UpdatePresentation) {
        previewNotice = presentation.previewNotice; heading = presentation.heading
        installedLine = presentation.installedLine; checkedLine = presentation.checkedLine
        checks = presentation.checks.map { UpdateCheckRow(title: $0.title, status: Self.checkStatus(diagnosticStatus: $0.status)) }
        refusalLine = presentation.refusalLine.map { line in
            let prefix = "Refused: "
            return Self.refusalReason(diagnosticCode: line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : "")
        }
        deferralLine = presentation.deferralLine
        actionTitle = presentation.actionTitle; actionEnabled = presentation.actionEnabled; actionNote = presentation.actionNote
    }

    /// A brief plain reason for one diagnostic refusal code. The code itself is never shown.
    public static func refusalReason(diagnosticCode: String) -> String {
        guard let failure = TransactionFailure(rawValue: diagnosticCode) else { return "The update was refused." }
        switch failure {
        case .notImplemented: return "This step is not available in this preview."
        case .notAuthorized: return "Patched is not authorised to make this change."
        case .userTriggerRequired: return "An update starts only when you choose Update."
        case .unsafePath: return "That location cannot be used for an update."
        case .aliasedPath: return "The update and the app are in the same place."
        case .existingRoot: return "The preview folder already exists."
        case .missingTarget: return "The app to update was not found."
        case .missingSource: return "The update files were not found."
        case .notDirectory: return "Something that should be a folder is not a folder."
        case .symlink: return "A link was found where a real file or folder is required."
        case .hardlink: return "A file with more than one name was found."
        case .specialFile: return "An unsupported kind of file was found."
        case .unsafeOwner: return "A file or folder belongs to a different user."
        case .unsafeMode: return "A file or folder has permissions Patched does not accept."
        case .crossVolume: return "The update and the app are on different disks."
        case .treeLimit: return "The app is too large for this preview."
        case .artifactMismatch: return "The update file does not match the catalogue."
        case .invalidManifest: return "The update's list of files could not be read."
        case .manifestMismatch: return "The update files do not match their list."
        case .stagedBytesMismatch: return "The copied update files do not match their list."
        case .invalidBundle: return "The app's details could not be read."
        case .wrongBundle: return "The update is for a different app."
        case .wrongVersion: return "The update is not the expected version."
        case .notNewer: return "The update is not newer than the app."
        case .appRunning: return "The app is open. Close it yourself, then choose Update."
        case .identityChanged: return "Something changed on disk during the update. Recovery may be needed."
        case .existingTransaction: return "An earlier update attempt is on record. Recovery may be needed."
        case .busy: return "Another update is in progress."
        case .persistenceFailed: return "Patched could not save its progress. Recovery may be needed."
        case .journalMissing: return "No record of an update was found."
        case .journalCorrupt: return "The update record could not be read."
        case .journalMismatch: return "The update record does not match what is on disk."
        case .ambiguousState: return "Patched cannot tell which version is in place and will not guess."
        case .invalidState: return "That step is not available at this stage."
        }
    }

    /// The visible status for one diagnostic check row status. A refused row never shows its code,
    /// and a status that is not one of the known display statuses is shown as not checked.
    public static func checkStatus(diagnosticStatus: String) -> String {
        if diagnosticStatus.hasPrefix("Refused") { return "Did not pass" }
        let known = ["Not run", "Passed", "Not run in this fixture preview", "Not checked", "Closed", "Open. Patched will not quit it"]
        return known.contains(diagnosticStatus) ? diagnosticStatus : "Not checked"
    }
}
