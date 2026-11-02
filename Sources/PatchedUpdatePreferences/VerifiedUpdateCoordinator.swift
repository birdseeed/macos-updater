import PatchedScheduling

/// One read-only synthetic display owner. Nothing returned here authorises an update.
@MainActor public final class VerifiedUpdateCoordinator {
    private var source: (any SyntheticInventorySource)?
    private var preferences: PreferenceSession?
    private var principal = SchedulingPrincipal("")
    private var sessionGeneration = ""
    private var accepted: InventorySnapshot?
    private var validRead = false
    private var drifted = false
    private var reading = false

    public init() {}
    @_spi(Testing) public init(source: any SyntheticInventorySource, preferences: PreferenceSession,
                               principal: SchedulingPrincipal, sessionGeneration: String) {
        self.source = source; self.preferences = preferences
        self.principal = principal; self.sessionGeneration = sessionGeneration
    }
    private func callerRefusal(_ caller: SchedulingPrincipal) -> InventoryRefusal? {
        guard source != nil, preferences != nil else { return .unavailable }
        guard InventoryValidation.configurationText(principal.value),
              InventoryValidation.configurationText(caller.value),
              InventoryValidation.exact(principal.value, caller.value) else { return .principal }
        guard InventoryValidation.configurationText(sessionGeneration) else { return .generation }
        guard !reading else { return .reentrant }
        guard preferences?.matchesInventoryProjectionOwner(principal: principal, generation: sessionGeneration) == true
            else { return .preferences }
        return nil
    }
    private func invalidate(_ reason: InventoryRefusal, observedGeneration: UInt64? = nil) -> InventoryRefreshResult {
        // Malformed same-generation input is continuity drift too. Preserve its
        // original refusal without comparing or retaining the malformed payload.
        if let observedGeneration, let accepted, observedGeneration == accepted.generation { drifted = true }
        validRead = false
        return .refused(reason)
    }
    public func refresh(principal: SchedulingPrincipal) -> InventoryRefreshResult {
        // A bad caller or recursive call has no effect on the accepted owner's view.
        if let refusal = callerRefusal(principal) { return .refused(refusal) }
        guard let source else { return .refused(.unavailable) }
        reading = true; defer { reading = false }
        guard case .snapshot(let snapshot) = source.read(maximumRows: 512) else { return invalidate(.unavailable) }
        if let refusal = InventoryValidation.snapshotRefusal(snapshot) {
            return invalidate(refusal, observedGeneration: snapshot.generation)
        }
        guard InventoryValidation.configurationText(snapshot.principal.value),
              InventoryValidation.exact(snapshot.principal.value, self.principal.value) else {
            return invalidate(.principal, observedGeneration: snapshot.generation)
        }
        guard snapshot.generation > 0 else { return invalidate(.generation) }
        if let previous = accepted {
            guard snapshot.generation >= previous.generation else { return invalidate(.generation) }
            if snapshot.generation == previous.generation {
                guard !drifted else { return invalidate(.generation) }
                guard InventoryValidation.exact(snapshot, previous) else {
                    drifted = true
                    return invalidate(.generation)
                }
                validRead = true
                return .unchanged(generation: snapshot.generation)
            }
        }
        accepted = snapshot; validRead = true; drifted = false
        return .accepted(generation: snapshot.generation)
    }

    // The existing session owns skip/exclusion policy. This adapter only checks that its
    // pure display result has exactly the requested IDs, revision and shared screen rows.
    private func preferenceRows(_ snapshot: InventorySnapshot) -> (UInt64?, [[UInt8]: PreferenceProjectionRow]?) {
        guard let preferences,
              preferences.matchesInventoryProjectionOwner(principal: principal, generation: sessionGeneration),
              let revision = preferences.acceptedRevision, preferences.blockedReason == nil else { return (preferences?.acceptedRevision, nil) }
        let candidates = snapshot.rows.compactMap { row -> PreferenceCandidate? in
            guard case .syntheticAvailable(let candidate) = row.update else { return nil }
            return PreferenceCandidate(id: row.identity.instanceID, release: .verified(candidate.release))
        }
        let projected = preferences.projection(candidates)
        guard projected.revision == revision, projected.applications.count == candidates.count,
              projected.updates.count == candidates.count else { return (revision, nil) }
        var result: [[UInt8]: PreferenceProjectionRow] = [:]
        for index in candidates.indices {
            let app = projected.applications[index]
            let update = projected.updates[index]
            let key = Array(candidates[index].id.utf8)
            guard InventoryValidation.exact(app.id, candidates[index].id),
                  InventoryValidation.exact(update.id, candidates[index].id),
                  app.availability == update.availability, app.automaticExcluded == update.automaticExcluded,
                  app.canUndo == update.canUndo, result[key] == nil else { return (revision, nil) }
            result[key] = app
        }
        return (revision, result)
    }
    public func projection() -> InventoryProjection {
        guard let snapshot = accepted else { return InventoryProjection() }
        let ownerMatches = preferences?.matchesInventoryProjectionOwner(principal: principal, generation: sessionGeneration) == true
        let (revision, policyRows) = preferenceRows(snapshot)
        var copies: [[[UInt8]]: Int] = [:]
        for row in snapshot.rows { copies[InventoryValidation.copyKey(row.identity), default: 0] += 1 }
        let rows = snapshot.rows.map { row -> InventoryProjectionRow in
            let preference = policyRows?[Array(row.identity.instanceID.utf8)]
            let availableVersion: String?
            if case .syntheticAvailable(let candidate) = row.update { availableVersion = candidate.release.release }
            else { availableVersion = nil }
            let availability: InventoryAvailability
            if !validRead || !ownerMatches { availability = .unknown }
            else if row.externallyManaged { availability = .externalManaged }
            else if snapshot.catalogue != .fresh { availability = .unknown }
            else if copies[InventoryValidation.copyKey(row.identity), default: 0] > 1 { availability = .attention }
            else {
                switch row.update {
                case .unknown: availability = .unknown
                case .syntheticCurrent: availability = .syntheticCurrent
                case .syntheticAvailable:
                    switch preference?.availability {
                    case .some(.skipped): availability = .skipped
                    case .some(.available):
                        if row.running == .running { availability = .deferredRunning }
                        else if row.running == .unknown { availability = .unknown }
                        else if row.route == .attention { availability = .attention }
                        else if row.route == .unknown { availability = .unknown }
                        else { availability = .syntheticReady }
                    default: availability = .unknown
                    }
                }
            }
            return InventoryProjectionRow(identity: row.identity, displayName: row.displayName,
                availableVersion: availableVersion, availability: availability,
                automaticExcluded: preference?.automaticExcluded ?? false)
        }
        return InventoryProjection(rows: rows, generation: snapshot.generation, preferenceRevision: revision,
            syntheticLastChecked: snapshot.observedAt, isFresh: validRead && ownerMatches && snapshot.catalogue == .fresh)
    }
    public func select(_ request: InventorySelectionRequest) -> InventorySelectionResult {
        if let refusal = callerRefusal(request.principal) { return .refused(refusal) }
        guard InventoryValidation.identityBounds(request.identity), InventoryValidation.releaseBounds(request.release)
            else { return .refused(.bounds) }
        guard InventoryValidation.identityShape(request.identity), InventoryValidation.releaseShape(request.release)
            else { return .refused(.identity) }
        // The request is a display binding, so every valid-shaped selection rereads only
        // the injected synthetic inventory. It never consults storage or starts a queue.
        if case .refused(let refusal) = refresh(principal: request.principal) { return .refused(refusal) }
        guard let snapshot = accepted else { return .refused(.unavailable) }
        let (revision, policyRows) = preferenceRows(snapshot)
        guard let revision, policyRows != nil else { return .refused(.preferences) }
        guard request.observedGeneration == snapshot.generation, request.preferenceRevision == revision
            else { return .refused(.staleSelection) }
        guard let index = snapshot.rows.firstIndex(where: { InventoryValidation.exact($0.identity, request.identity) })
            else { return .refused(.identity) }
        guard case .syntheticAvailable(let candidate) = snapshot.rows[index].update else { return .refused(.notReady) }
        guard InventoryValidation.exact(candidate.release, request.release) else { return .refused(.identity) }
        guard projection().applications[index].availability == .syntheticReady else { return .refused(.notReady) }
        return .selected(SyntheticInventorySelection(identity: snapshot.rows[index].identity, release: candidate.release,
            observedGeneration: snapshot.generation, preferenceRevision: revision))
    }
    public func requestStart(_ request: InventorySelectionRequest, kind: StartKind) -> InventorySelectionResult {
        .refused(.unavailable)
    }
}
