import Darwin

struct ProcessOwnership {
    let uid: uid_t
    let realUID: uid_t
    func belongs(to user: uid_t) -> Bool { uid == user || realUID == user }
}

// Live entry point is hardwired to Darwin. No GuestRuntime/native trust injection.
func observeProcessOwnership(_ pid: pid_t,
                             record: (ProcessObservationFailure) throws -> Void) throws -> ProcessOwnership? {
    try observeProcessOwnership(pid, read: { pid, flavor, buffer, size in
        proc_pidinfo(pid, flavor, 0, buffer, size)
    }, gone: { pid in kill(pid, 0) != 0 && errno == ESRCH }, record: record)
}

// Internal numeric syscall seam used by synthetic checks, not an authority API.
func observeProcessOwnership(_ pid: pid_t,
                             read: (pid_t, Int32, UnsafeMutableRawPointer, Int32) -> Int32,
                             gone: (pid_t) -> Bool,
                             record: (ProcessObservationFailure) throws -> Void) throws -> ProcessOwnership? {
    var process = proc_bsdshortinfo()
    errno = 0
    let result = read(pid, PROC_PIDT_SHORTBSDINFO, &process, Int32(MemoryLayout<proc_bsdshortinfo>.size))
    let readErrno = errno
    if result != MemoryLayout<proc_bsdshortinfo>.size {
        if readErrno == ESRCH { return nil }
        if gone(pid) { return nil }
        try refuseProcessObservation(.init(stage: .pidInfo, errno: readErrno, returnSize: result, pid: pid), record: record)
    }
    return .init(uid: process.pbsi_uid, realUID: process.pbsi_ruid)
}
