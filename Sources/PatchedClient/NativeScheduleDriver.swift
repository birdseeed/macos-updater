import Combine
import PatchedUpdatePreferences

/// Fake lifecycle injection only. These declarations confer no native or update authority.
@_spi(Testing) public enum NativeScheduleFixtureEvent { case tick, sleep, wake, clockInvalidated }
@MainActor @_spi(Testing) public protocol NativeScheduleFixtureSubscription: AnyObject { func cancel() }
@MainActor @_spi(Testing) public protocol NativeScheduleFixtureHooks: AnyObject {
    func subscribe(_ receive: @escaping @MainActor (NativeScheduleFixtureEvent) -> Void) -> any NativeScheduleFixtureSubscription
}
@MainActor @_spi(Testing) public protocol NativeScheduleFixtureRequest: AnyObject { func cancel() }
@MainActor @_spi(Testing) public protocol NativeScheduleFixtureDispatcher: AnyObject {
    func begin(completion: @escaping @MainActor (Bool) -> Void) -> any NativeScheduleFixtureRequest
}
/// The ordinary app has no trusted metadata checker and refuses before clock or storage use.
@MainActor public final class NativeScheduleDriver: @preconcurrency ObservableObject {
    public enum Phase: Equatable { case idle, unavailable, running, stopped }
    public let firstRun: NativeFirstRunController
    public let applications: LocalApplicationsController
    // Publish only settled state: synchronous observers may call back into the driver.
    public let objectWillChange = ObservableObjectPublisher()
    public private(set) var phase: Phase = .idle
    public private(set) var acceptedCompletions: UInt64 = 0
    public var checkCapabilityAvailable: Bool { dispatcher != nil }
    public var statusText: String {
        if !checkCapabilityAvailable { return "Trusted scheduled update checks unavailable. Automatic installation unavailable." }
        return phase == .stopped ? "Fixture scheduler stopped." : "Fixture scheduled check lifecycle. No productive checker or installation authority."
    }
    public var physicalCheckInFlight: Bool { physical != nil }
    private let clock: NativeScheduleClock
    private let hooks: (any NativeScheduleFixtureHooks)?
    private let dispatcher: (any NativeScheduleFixtureDispatcher)?
    private var subscription: (any NativeScheduleFixtureSubscription)?
    private var owner: PreferenceSession?
    private var generation: String?
    private var awake = true
    private var observing = false
    // This identity survives cancellation until the exact completion callback.
    private final class Flight {
        let owner: PreferenceSession
        let generation: String
        let revision: UInt64
        let attempt: ScheduledCheckAttempt
        var request: (any NativeScheduleFixtureRequest)?
        var valid = true
        var cancellationSent = false
        var finishing = false
        init(owner: PreferenceSession, generation: String, revision: UInt64, attempt: ScheduledCheckAttempt) {
            self.owner = owner; self.generation = generation; self.revision = revision; self.attempt = attempt
        }
    }
    private var physical: Flight?
    public init(firstRun: NativeFirstRunController, applications: LocalApplicationsController) {
        self.firstRun = firstRun; self.applications = applications; clock = NativeScheduleClock()
        hooks = nil; dispatcher = nil
    }
    @_spi(Testing) public init(firstRun: NativeFirstRunController, applications: LocalApplicationsController,
        clock: NativeScheduleClock, hooks: any NativeScheduleFixtureHooks,
        dispatcher: (any NativeScheduleFixtureDispatcher)?) {
        self.firstRun = firstRun; self.applications = applications; self.clock = clock
        self.hooks = hooks; self.dispatcher = dispatcher
    }
    @discardableResult public func start() -> Bool {
        guard phase != .stopped else { return false }
        // Capability refusal precedes owner access, sampling, subscriptions and opportunities.
        guard dispatcher != nil, let hooks else {
            phase = .unavailable; objectWillChange.send(); return false
        }
        if phase == .running { return true }
        guard let acquired = firstRun.acquiredScheduleOwner, firstRun.lastRefusal == nil,
              acquired.session.blockedReason == nil, acquired.session.scheduleSettings != nil else { return false }
        owner = acquired.session; generation = acquired.generation
        phase = .running
        objectWillChange.send()
        guard phase == .running else { return false }
        let token = hooks.subscribe { [weak self] event in self?.receive(event) }
        // subscribe may synchronously deliver a terminal event through a fixture.
        if phase == .running { subscription = token } else { token.cancel(); return false }
        observeAndDispatch()
        return phase == .running
    }
    public func stop() {
        guard phase != .stopped else { return }
        phase = .stopped
        let token = subscription; subscription = nil
        if let owner, let generation { _ = owner.observeSchedule(.shutdown, generation: generation) }
        invalidatePhysical()
        token?.cancel()
        objectWillChange.send()
    }
    @discardableResult public func reanchor() -> Bool {
        guard phase == .running, !observing, dispatcher != nil, let owner, let generation,
              matchesOwner(owner, generation: generation) else { return false }
        observing = true; defer { observing = false }
        invalidatePhysical()
        guard phase == .running else { return false }
        let sample = clock.reanchor()
        guard phase == .running, matchesOwner(owner, generation: generation) else { return false }
        guard let sample else {
            _ = owner.observeSchedule(.clockInvalidated, generation: generation)
            return false
        }
        return owner.reanchorScheduleClock(sample, awake: awake ? .yes : .no, generation: generation)
    }
    private func receive(_ event: NativeScheduleFixtureEvent) {
        guard phase == .running, let owner, let generation else { return }
        switch event {
        case .sleep:
            awake = false
            _ = owner.observeSchedule(.sleep, generation: generation)
            invalidatePhysical()
        case .clockInvalidated:
            _ = owner.observeSchedule(.clockInvalidated, generation: generation)
            invalidatePhysical()
        case .wake:
            awake = true
            observeAndDispatch()
        case .tick: observeAndDispatch()
        }
    }
    private func observeAndDispatch() {
        guard phase == .running, !observing, let owner, let generation, let dispatcher else { return }
        observing = true; defer { observing = false }
        fenceChangedOwner()
        guard phase == .running, matchesOwner(owner, generation: generation) else { return }
        let sample = clock.sample()
        guard phase == .running, matchesOwner(owner, generation: generation) else { return }
        guard let sample else {
            _ = owner.observeSchedule(.clockInvalidated, generation: generation)
            invalidatePhysical()
            return
        }
        guard owner.observeSchedule(.observation(sample: sample, awake: awake ? .yes : .no), generation: generation) else {
            invalidatePhysical(); return
        }
        // Never use cancellation or a new day as proof that the physical child ended.
        guard physical == nil, let revision = owner.acceptedRevision,
              let attempt = owner.beginScheduledCheck(generation: generation) else { return }
        let flight = Flight(owner: owner, generation: generation, revision: revision, attempt: attempt)
        physical = flight; objectWillChange.send()
        // Publication may stop, revoke, sleep or otherwise invalidate this reservation.
        // No child exists yet, so only this undispatched reservation may be released.
        guard phase == .running, physical === flight, flight.valid, matchesFlight(flight) else {
            if physical === flight {
                flight.valid = false
                _ = flight.owner.cancelScheduledCheck(generation: flight.generation)
                physical = nil
                objectWillChange.send()
            }
            return
        }
        let request = dispatcher.begin { [weak self, weak flight] success in
            guard let self, let flight else { return }
            self.finish(flight, success: success)
        }
        // begin may have completed synchronously. Do not resurrect the returned request.
        guard physical === flight else { return }
        flight.request = request
        if !flight.valid { cancelRequest(flight) }
    }
    private func matchesOwner(_ owner: PreferenceSession, generation: String) -> Bool {
        guard let acquired = firstRun.acquiredScheduleOwner else { return false }
        return acquired.session === owner && acquired.generation == generation &&
            firstRun.lastRefusal == nil && owner.blockedReason == nil
    }
    private func matchesFlight(_ flight: Flight) -> Bool {
        matchesOwner(flight.owner, generation: flight.generation) &&
            flight.owner.acceptedRevision == flight.revision &&
            flight.owner.scheduleSettings?.dailyChecks == true &&
            flight.owner.scheduleRuntimeSnapshot.checkInFlight &&
            flight.owner.scheduleRuntimeSnapshot.awake == .yes && awake
    }
    private func fenceChangedOwner() {
        guard let flight = physical else { return }
        guard matchesFlight(flight) else { invalidatePhysical(); return }
    }
    private func invalidatePhysical() {
        guard let flight = physical else { return }
        flight.valid = false
        _ = flight.owner.cancelScheduledCheck(generation: flight.generation)
        cancelRequest(flight)
    }
    private func cancelRequest(_ flight: Flight) {
        guard !flight.cancellationSent, let request = flight.request else { return }
        flight.cancellationSent = true
        request.cancel()
    }
    private func finish(_ flight: Flight, success: Bool) {
        guard physical === flight, !flight.finishing else { return }
        flight.finishing = true
        fenceChangedOwner()
        // Settle this logical attempt while its physical slot still excludes replacements.
        // A recursive callback from cancel() cannot settle or release this flight twice.
        if phase == .running, flight.valid, success,
           flight.owner.completeScheduledCheck(flight.attempt, generation: flight.generation) {
            if acceptedCompletions < UInt64.max { acceptedCompletions += 1 }
        } else {
            _ = flight.owner.cancelScheduledCheck(generation: flight.generation)
        }
        flight.request = nil
        physical = nil
        // No old-flight or counter writes may follow this reentrant publication.
        objectWillChange.send()
    }
    @_spi(Testing) public var testPreferenceOwner: PreferenceSession? { firstRun.acquiredScheduleOwner?.session }
}
