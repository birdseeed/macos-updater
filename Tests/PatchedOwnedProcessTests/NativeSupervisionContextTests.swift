import Foundation
import Testing
import Darwin
@testable import PatchedDisposableProof

// PURE DATA and harmless current-process observations only. No child or signal.
@Suite("OwnedProcessLifecycleTests.NativeSupervisionContextTests")
struct NativeSupervisionContextOwnedProcessLifecycleTests {
    private let revision = String(repeating: "a", count: 40)
    private let nativeHash = String(repeating: "b", count: 64)
    private let childHash = String(repeating: "c", count: 64)
    private func object() -> [String: Any] {
        ["schemaVersion": 1, "kind": "patched-owned-native-supervision-v1",
         "targetID": "test-target", "runID": "test-run", "sourceRevision": revision,
         "nativeBinarySHA256": nativeHash, "childBinarySHA256": childHash,
         "nonce": String(repeating: "d", count: 64), "clock": "darwin-mach-absolute-ns-v1",
         "startedNanoseconds": UInt64(100), "deadlineNanoseconds": UInt64(1770000000100),
         "leaderPID": 410, "leaderStartSeconds": 10, "leaderStartMicroseconds": 999999,
         "ownerPID": 400, "ownerStartSeconds": 9, "ownerStartMicroseconds": 0,
         "stopWriterDevice": 0, "stopWriterInode": UInt64.max]
    }
    private func bytes(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func decode(_ data: Data) throws -> NativeSupervisionDescriptor {
        try NativeSupervisionDescriptor.decode(data, expectedTargetID: "test-target",
            expectedRunID: "test-run", expectedSourceRevision: revision,
            expectedNativeBinarySHA256: nativeHash, expectedChildBinarySHA256: childHash)
    }
    private func refuses(_ data: Data) {
        do { _ = try decode(data); Issue.record("Invalid descriptor was accepted") }
        catch let error as DisposableFailure { #expect(error == .notAuthorized) }
        catch { Issue.record(Comment(rawValue: "Unexpected refusal: \(error)")) }
    }
    private func refuses(_ key: String, _ values: [Any]) throws {
        for value in values { var input = object(); input[key] = value; refuses(try bytes(input)) }
    }
    @Test func validDescriptorPreservesEveryField() throws {
        let d = try decode(bytes(object()))
        #expect(d.schemaVersion == 1); #expect(d.kind == "patched-owned-native-supervision-v1")
        #expect(d.targetID == "test-target"); #expect(d.runID == "test-run")
        #expect(d.sourceRevision == revision); #expect(d.nativeBinarySHA256 == nativeHash)
        #expect(d.childBinarySHA256 == childHash); #expect(d.nonce == String(repeating: "d", count: 64))
        #expect(d.clock == "darwin-mach-absolute-ns-v1"); #expect(d.startedNanoseconds == 100)
        #expect(d.deadlineNanoseconds == 1770000000100); #expect(d.leaderPID == 410)
        #expect(d.leaderStartSeconds == 10); #expect(d.leaderStartMicroseconds == 999999)
        #expect(d.ownerPID == 400); #expect(d.ownerStartSeconds == 9)
        #expect(d.ownerStartMicroseconds == 0); #expect(d.stopWriterDevice == 0)
        #expect(d.stopWriterInode == UInt64.max)
    }
    @Test func minimumIntervalAndPIDBoundsAccepted() throws {
        var input = object(); input["startedNanoseconds"] = 1; input["deadlineNanoseconds"] = 2
        input["leaderPID"] = 2; input["ownerPID"] = Int32.max
        input["stopWriterInode"] = 1
        let d = try decode(bytes(input))
        #expect(d.startedNanoseconds == 1); #expect(d.deadlineNanoseconds == 2)
        #expect(d.leaderPID == 2); #expect(d.ownerPID == Int32.max); #expect(d.stopWriterInode == 1)
    }
    @Test func everyKeyRequired() throws {
        for key in object().keys { var input = object(); input.removeValue(forKey: key); refuses(try bytes(input)) }
    }
    @Test func unknownKeyRefused() throws { var input = object(); input["authority"] = true; refuses(try bytes(input)) }
    @Test func duplicateAndEscapedDuplicateKeysRefused() throws {
        let body = String(decoding: try bytes(object()), as: UTF8.self)
        refuses(Data(("{\"runID\":\"test-run\"," + String(body.dropFirst())).utf8))
        refuses(Data(("{\"run\\u0049D\":\"test-run\"," + String(body.dropFirst())).utf8))
    }
    @Test func trailingAndMalformedJSONRefused() throws {
        let good = try bytes(object())
        refuses(good + Data("{}".utf8)); refuses(good + Data("x".utf8))
        refuses(Data("[]".utf8)); refuses(Data("null".utf8)); refuses(Data())
        refuses(Data([0xff])); refuses(Data("{\"x\":}".utf8))
    }
    @Test func exact4096ByteInputAcceptedAnd4097Refused() throws {
        let good = try bytes(object()); try #require(good.count < 4096)
        let bounded = good + Data(repeating: 32, count: 4096 - good.count)
        let d = try decode(bounded); #expect(d.runID == "test-run")
        refuses(bounded + Data([32]))
    }
    @Test func schemaAndKindRefused() throws {
        try refuses("schemaVersion", [0, 2, true, "1", 1.5, NSNull()])
        try refuses("kind", ["", "patched-owned-native-supervision-v2", 1, NSNull()])
    }
    @Test func allIndependentIdentityBindingsRefused() throws {
        for key in ["targetID", "runID", "sourceRevision", "nativeBinarySHA256", "childBinarySHA256"] {
            try refuses(key, ["wrong", "", 1, true, NSNull()])
        }
    }
    @Test func independentlyExpectedValuesCannotBeReplacedByDescriptor() throws {
        let input = try bytes(object())
        for index in 0..<5 {
            var expected = ["test-target", "test-run", revision, nativeHash, childHash]; expected[index] = "other"
            do {
                _ = try NativeSupervisionDescriptor.decode(input, expectedTargetID: expected[0], expectedRunID: expected[1],
                    expectedSourceRevision: expected[2], expectedNativeBinarySHA256: expected[3], expectedChildBinarySHA256: expected[4])
                Issue.record("Mismatched independent expectation accepted")
            } catch let error as DisposableFailure { #expect(error == .notAuthorized) }
            catch { Issue.record(Comment(rawValue: "Unexpected failure: \(error)")) }
        }
    }
    @Test func revisionAndDigestsRequireLowerHexEvenWhenExpectedMatches() throws {
        for (key, index, length) in [("sourceRevision", 2, 40), ("nativeBinarySHA256", 3, 64), ("childBinarySHA256", 4, 64)] {
            for bad in [String(repeating: "A", count: length), String(repeating: "g", count: length), String(repeating: "a", count: length - 1)] {
                var input = object(); input[key] = bad
                var expected = ["test-target", "test-run", revision, nativeHash, childHash]; expected[index] = bad
                do {
                    _ = try NativeSupervisionDescriptor.decode(bytes(input), expectedTargetID: expected[0], expectedRunID: expected[1],
                        expectedSourceRevision: expected[2], expectedNativeBinarySHA256: expected[3], expectedChildBinarySHA256: expected[4])
                    Issue.record("Malformed bound hash/revision accepted")
                } catch let error as DisposableFailure { #expect(error == .notAuthorized) }
                catch { Issue.record(Comment(rawValue: "Unexpected failure: \(error)")) }
            }
        }
    }
    @Test func nonceStrictLowerHexRefused() throws {
        try refuses("nonce", ["", String(repeating: "d", count: 63), String(repeating: "d", count: 65), String(repeating: "D", count: 64), String(repeating: "g", count: 64), 1, NSNull()])
    }
    @Test func onlyExplicitMachClockAccepted() throws { try refuses("clock", ["", "monotonic", "dispatch", 1, NSNull()]) }
    @Test func allNumericFieldsRejectNonIntegers() throws {
        for key in ["startedNanoseconds", "deadlineNanoseconds", "leaderPID", "leaderStartSeconds", "leaderStartMicroseconds", "ownerPID", "ownerStartSeconds", "ownerStartMicroseconds", "stopWriterDevice", "stopWriterInode"] {
            try refuses(key, [true, false, "1", 1.5, -1, NSNull()])
        }
    }
    @Test func fractionalAndExponentLexemesRefused() throws {
        let good = String(decoding: try bytes(object()), as: UTF8.self)
        for token in ["1.0", "1e0", "1E+0", "18446744073709551616"] {
            refuses(Data(good.replacingOccurrences(of: "\"startedNanoseconds\":100", with: "\"startedNanoseconds\":" + token).utf8))
        }
    }
    @Test func zeroStartAndDeadlineRefused() throws { try refuses("startedNanoseconds", [0]); try refuses("deadlineNanoseconds", [0]) }
    @Test func deadlineOrderingAnd1770SecondLimitRefused() throws { try refuses("deadlineNanoseconds", [99, 100, UInt64(1770000000101), UInt64.max]) }
    @Test func nearUInt64MaximumDoesNotOverflow() throws {
        var input = object(); input["startedNanoseconds"] = UInt64.max - 1; input["deadlineNanoseconds"] = UInt64.max
        let d = try decode(bytes(input)); #expect(d.deadlineNanoseconds - d.startedNanoseconds == 1)
    }
    @Test func invalidPIDRangeAndEqualityRefused() throws {
        for key in ["leaderPID", "ownerPID"] { try refuses(key, [0, 1, Int64(Int32.max) + 1, UInt64.max]) }
        var input = object(); input["ownerPID"] = 410; refuses(try bytes(input))
    }
    @Test func processStartBoundsRefused() throws {
        for key in ["leaderStartSeconds", "ownerStartSeconds"] { try refuses(key, [0]) }
        for key in ["leaderStartMicroseconds", "ownerStartMicroseconds"] { try refuses(key, [1000000, UInt64.max]) }
    }
    @Test func writerInodeMustBePositive() throws { try refuses("stopWriterInode", [0]) }
    @Test func unsignedDeviceAndInodeRetainHighBits() throws {
        var input = object(); input["stopWriterDevice"] = UInt64.max
        let d = try decode(bytes(input)); #expect(d.stopWriterDevice == UInt64.max); #expect(d.stopWriterInode == UInt64.max)
    }
    @Test func currentProcessFactsMatchDarwin() throws {
        let d = try NativeSupervisionKernel.process(pid: getpid())
        #expect(d.pid == getpid()); #expect(d.parentPID == getppid()); #expect(d.processGroupID == getpgrp())
        #expect(d.realUID == getuid())
        #expect(d.uid == geteuid()); #expect(d.startSeconds > 0); #expect(d.startMicroseconds < 1000000)
        #expect(d.status > 0)
    }
    @Test func anonymousPipeHasReciprocalKernelHandles() throws {
        var descriptors: [Int32] = [-1, -1]
        let result = descriptors.withUnsafeMutableBufferPointer { Darwin.pipe($0.baseAddress!) }
        try #require(result == 0)
        defer { _ = close(descriptors[0]); _ = close(descriptors[1]) }
        let reader = try NativeSupervisionKernel.pipe(pid: getpid(), fd: descriptors[0])
        let writer = try NativeSupervisionKernel.pipe(pid: getpid(), fd: descriptors[1])
        #expect(reader.handle != 0); #expect(writer.handle != 0)
        #expect(reader.peerHandle == writer.handle); #expect(writer.peerHandle == reader.handle)
        #expect(reader.uid == getuid()); #expect(writer.uid == getuid())
        #expect(reader.openFlags & UInt32(FREAD | FWRITE) == UInt32(FREAD))
        #expect(writer.openFlags & UInt32(FREAD | FWRITE) == UInt32(FWRITE))
        var r = stat(), w = stat()
        try #require(fstat(descriptors[0], &r) == 0); try #require(fstat(descriptors[1], &w) == 0)
        #expect(reader.device == UInt64(UInt32(bitPattern: r.st_dev))); #expect(writer.device == UInt64(UInt32(bitPattern: w.st_dev)))
        #expect(reader.inode == r.st_ino); #expect(writer.inode == w.st_ino)
        #expect(reader.uid == r.st_uid); #expect(writer.uid == w.st_uid)
        // Endpoint inodes are observed separately. No exclusive-reader inference.
    }
    @Test func ephemeralWriterSupportsNonblockingAndNoSIGPIPE() throws {
        var descriptors: [Int32] = [-1, -1]
        let result = descriptors.withUnsafeMutableBufferPointer { Darwin.pipe($0.baseAddress!) }
        try #require(result == 0)
        defer { _ = close(descriptors[0]); _ = close(descriptors[1]) }
        let writer = descriptors[1]
        let flags = fcntl(writer, F_GETFL); try #require(flags >= 0)
        try #require(fcntl(writer, F_SETFL, flags | O_NONBLOCK) == 0)
        let updated = fcntl(writer, F_GETFL); try #require(updated >= 0)
        #expect(updated & O_NONBLOCK != 0); #expect(updated & O_ACCMODE == O_WRONLY)
        try #require(fcntl(writer, F_SETNOSIGPIPE, 1) == 0)
        #expect(fcntl(writer, F_GETNOSIGPIPE) == 1)
        let observed = try NativeSupervisionKernel.pipe(pid: getpid(), fd: writer)
        #expect(observed.openFlags & UInt32(FREAD | FWRITE) == UInt32(FWRITE))
        // No write occurs; no process or global SIGPIPE disposition changes.
    }
    @Test func regularDeviceCannotMasqueradeAsPipe() throws {
        let fd = open("/dev/null", O_RDONLY); try #require(fd >= 0); defer { _ = close(fd) }
        do { _ = try NativeSupervisionKernel.pipe(pid: getpid(), fd: fd); Issue.record("Non-pipe accepted") }
        catch let error as DisposableFailure { #expect(error == .notAuthorized) }
        catch { Issue.record(Comment(rawValue: "Unexpected pipe failure: \(error)")) }
    }
    @Test func explicitMachAbsoluteNanosecondsAreBracketed() throws {
        var timebase = mach_timebase_info_data_t(); try #require(mach_timebase_info(&timebase) == KERN_SUCCESS)
        try #require(timebase.denom > 0); try #require(timebase.numer > 0)
        func nanos(_ ticks: UInt64) throws -> UInt64 {
            let product = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer))
            try #require(!product.overflow); return product.partialValue / UInt64(timebase.denom)
        }
        let before = try nanos(mach_absolute_time())
        let observed = try NativeSupervisionKernel.nowNanoseconds()
        let after = try nanos(mach_absolute_time())
        #expect(before <= observed); #expect(observed <= after); #expect(observed > 0)
    }
}
