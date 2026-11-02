/// Inert storage choices only. No clock, policy, permission or consent authority.
public struct SchedulePauseChoice: Equatable, Sendable {
    public let resumeUTC: Int64
    public let displayZone: String
    /// Validates only the existing wire syntax, without consulting a clock or zone database.
    public static func declared(resumeUTC: Int64, displayZone: String) -> SchedulePauseChoice? {
        let bytes = displayZone.utf8
        guard resumeUTC >= 0, !bytes.isEmpty, bytes.count <= 128 else { return nil }
        var component = false
        for byte in bytes {
            if byte == 47 {
                guard component else { return nil }
                component = false
            } else {
                guard (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) ||
                    byte == 95 || byte == 43 || byte == 45 else { return nil }
                component = true
            }
        }
        guard component else { return nil }
        return SchedulePauseChoice(resumeUTC: resumeUTC, displayZone: displayZone)
    }
    /// Unvalidated declaration. The zone is syntactic display intent only.
    @_spi(Testing) public init(resumeUTC: Int64, displayZone: String) {
        self.resumeUTC = resumeUTC; self.displayZone = displayZone
    }
}
public struct ScheduleSettings: Equatable, Sendable {
    public let dailyChecks: Bool
    public let notifications: Bool
    public let automaticUpdates: Bool
    public let pause: SchedulePauseChoice?
    /// Unvalidated choices; never acknowledges a save or enables a start.
    @_spi(Testing) public init(dailyChecks: Bool = true, notifications: Bool = true,
                              automaticUpdates: Bool = false, pause: SchedulePauseChoice? = nil) {
        self.dailyChecks = dailyChecks; self.notifications = notifications
        self.automaticUpdates = automaticUpdates; self.pause = pause
    }
}
public enum ScheduleSettingsChange: Equatable, Sendable {
    case dailyChecks(Bool), notifications(Bool), automaticUpdates(Bool), pause(SchedulePauseChoice?)
}
public struct ScheduleSettingsMutationReceipt: Equatable, Sendable {
    public let id: String
    public let change: ScheduleSettingsChange
    /// An unvalidated, non-executable declaration with no audit authority.
    @_spi(Testing) public init(id: String, change: ScheduleSettingsChange) {
        self.id = id; self.change = change
    }
}
