import Darwin
@testable import PatchedDisposableProof

// Emulates numeric syscall results only; no host process scan or live authority.
@MainActor func registerProcessOwnershipChecks() {
    for (effective, real, expected) in [(uid_t(501), uid_t(501), true), (501, 0, true),
                                       (0, 501, true), (502, 501, true), (502, 502, false), (0, 0, false)] {
        check("short ownership read effective \(effective) real \(real)") {
            var calls = 0, observations = 0
            let result = try observeProcessOwnership(123, read: { pid, flavor, buffer, size in
                calls += 1
                guard pid == 123, flavor == PROC_PIDT_SHORTBSDINFO,
                      size == MemoryLayout<proc_bsdshortinfo>.size else {
                    errno = EPERM; return 0 // Full BSDINFO has the observed privilege refusal.
                }
                var info = proc_bsdshortinfo()
                info.pbsi_pid = UInt32(pid); info.pbsi_uid = effective; info.pbsi_ruid = real
                buffer.assumingMemoryBound(to: proc_bsdshortinfo.self).pointee = info
                return Int32(MemoryLayout<proc_bsdshortinfo>.size)
            }, gone: { _ in false }, record: { _ in observations += 1 })
            try expect(result?.uid == effective && result?.realUID == real, "Exact numeric ownership survives the minimal native read")
            try expect(result?.belongs(to: 501) == expected, "Either effective or real UID retains the process, including effective root")
            try expect(calls == 1 && observations == 0, "One minimal read, no fallback or ignored refusal")
        }
    }
    for (returned, readErrno) in [(Int32(0), EPERM), (0, EACCES), (0, 0),
                                 (Int32(MemoryLayout<proc_bsdshortinfo>.size - 1), Int32(0)),
                                 (Int32(MemoryLayout<proc_bsdshortinfo>.size + 1), Int32(0))] {
        check("unresolved ownership read refuses result \(returned) errno \(readErrno)") {
            var observed: ProcessObservationFailure?
            try refuses(.commandFailed) {
                _ = try observeProcessOwnership(123, read: { _, _, _, _ in errno = readErrno; return returned },
                    gone: { _ in errno = ESRCH; return false }, record: { observed = $0 })
            }
            try expect(observed?.stage == .pidInfo && observed?.errno == readErrno &&
                       observed?.returnSize == returned && observed?.pid == 123 && observed?.uid == nil,
                       "Unresolved short/unknown/permission failure retains original numeric diagnostic")
        }
    }
    for vanishedAtRead in [false, true] {
        check("ownership process disappearance retains existing handling \(vanishedAtRead)") {
            var probes = 0, observations = 0
            let result = try observeProcessOwnership(123,
                read: { _, _, _, _ in errno = vanishedAtRead ? ESRCH : EPERM; return 0 },
                gone: { _ in probes += 1; return true }, record: { _ in observations += 1 })
            try expect(result == nil && probes == (vanishedAtRead ? 0 : 1) && observations == 0,
                       "Only existing disappearance evidence skips the PID")
        }
    }
}
