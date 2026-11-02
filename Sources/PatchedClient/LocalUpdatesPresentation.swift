/// Read-only projection of the sole scanner owner's current display values.
/// Observations remain unverified and grant no update or installation authority.
extension LocalApplicationsController {
    public var updatesText: LocalApplicationsText {
        let applications = text
        return LocalApplicationsText(heading: "Updates", status: applications.status,
            scanTitle: applications.scanTitle, scanEnabled: applications.scanEnabled,
            notice: applications.notice, observedAt: applications.observedAt,
            provenance: applications.provenance, roots: applications.roots,
            issues: applications.issues, rows: applications.rows)
    }
    public var readyForUpdateCount: Int { 0 }
    public var unknownUpdateCount: Int { observation?.applications.count ?? 0 }
    public var allVerifiedUpToDate: Bool { false }
}
