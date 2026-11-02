import Foundation
import Darwin
@testable import PatchedDisposableProof

// Post-change regression of diagnostic representation/refusal only. These checks
// never enumerate processes or inject an accepted native observation.
@MainActor func registerProcessObservationChecks() {
    for stage in ProcessObservationFailure.Stage.allCases {
        check("process diagnostic bounded fields \(stage.rawValue)") {
            let observation = ProcessObservationFailure(stage: stage, errno: EPERM, returnSize: -1, pid: 123, uid: 501)
            let bytes = try JSONEncoder().encode(observation)
            let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            try expect(Set(object.keys) == ["stage", "errno", "returnSize", "pid", "uid"], "Only fixed stage and numeric observations")
            try expect(object["stage"] as? String == stage.rawValue && object["errno"] as? Int32 == EPERM &&
                       object["returnSize"] as? Int32 == -1 && object["pid"] as? Int32 == 123 &&
                       object["uid"] as? UInt32 == 501, "Exact captured API result, errno and identifiers")
            try expect(bytes.count < 256, "Bounded diagnostic encoding")
        }
    }
    check("process diagnostic absent identifiers omitted") {
        let observation = ProcessObservationFailure(stage: .listAllPIDsSize, errno: 0, returnSize: 100_000)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(observation)) as! [String: Any]
        try expect(Set(object.keys) == ["stage", "errno", "returnSize"], "No guessed PID or UID")
    }
    for writeFails in [false, true] {
        check("process diagnostic preserves commandFailed with write failure \(writeFails)") {
            let originalErrno = EPERM
            let observation = ProcessObservationFailure(stage: .pidInfo, errno: originalErrno, returnSize: 0, pid: 123)
            // Models an intervening errno change, not a liveness/OS authority result.
            errno = ESRCH
            var recordCount = 0
            var capturedErrno: Int32?
            try refuses(.commandFailed) {
                try refuseProcessObservation(observation) { captured in
                    recordCount += 1
                    capturedErrno = captured.errno
                    if writeFails { throw DisposableFailure.persistenceFailed }
                }
            }
            try expect(recordCount == 1, "One diagnostic attempt before unchanged refusal")
            try expect(capturedErrno == originalErrno, "Captured errno survives later errno changes")
        }
    }
}
