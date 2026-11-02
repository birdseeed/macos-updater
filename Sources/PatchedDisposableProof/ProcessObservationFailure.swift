import Darwin

// Observation only. No executable paths, contents or injected native acceptance.
struct ProcessObservationFailure: Encodable {
    enum Stage: String, Encodable, CaseIterable {
        case listAllPIDsSize = "proc_listallpids.size"
        case listAllPIDsRead = "proc_listallpids.read"
        case pidInfo = "proc_pidinfo"
        case pidPath = "proc_pidpath"
        case ancestorStat = "fstatat.ancestor"
    }
    let stage: Stage
    let errno: Int32
    let returnSize: Int32
    var pid: pid_t? = nil
    var uid: uid_t? = nil
}

func refuseProcessObservation(_ failure: ProcessObservationFailure,
                              record: (ProcessObservationFailure) throws -> Void) throws -> Never {
    // Evidence is best effort; a failed write must not change the existing refusal.
    try? record(failure)
    throw DisposableFailure.commandFailed
}
