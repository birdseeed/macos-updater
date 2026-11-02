import Foundation
import Darwin
@_spi(Testing) import ArtifactInspection

// Synthetic inert headers only: these bytes are never launched, signed, mounted,
// or represented as genuine vendor evidence. Independent fixtures deliberately
// construct each byte field rather than using product encoding helpers.
private enum MachOFixture {
    static let arm: UInt32 = 0x0100000c
    static let intel: UInt32 = 0x01000007
    static func put(_ value: UInt64, width: Int, at offset: Int, in bytes: inout Data, little: Bool = false) {
        for index in 0..<width {
            let shift = little ? index * 8 : (width - index - 1) * 8
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> shift)
        }
    }
    static func thin(_ cpu: UInt32, little: Bool = true, subtype: UInt32? = nil) -> Data {
        var bytes = Data(repeating: 0, count: 32)
        put(0xfeedfacf, width: 4, at: 0, in: &bytes, little: little)
        put(UInt64(cpu), width: 4, at: 4, in: &bytes, little: little)
        put(UInt64(subtype ?? (cpu == intel ? 3 : 0)), width: 4, at: 8, in: &bytes, little: little)
        put(2, width: 4, at: 12, in: &bytes, little: little) // MH_EXECUTE
        return bytes
    }
    static func fat(wide: Bool = false, little: Bool = false) -> Data {
        var bytes = Data(repeating: 0, count: 160)
        put(wide ? 0xcafebabf : 0xcafebabe, width: 4, at: 0, in: &bytes, little: little)
        put(2, width: 4, at: 4, in: &bytes, little: little)
        let stride = wide ? 32 : 20
        for (index, cpu) in [intel, arm].enumerated() {
            let row = 8 + index * stride, start = 96 + index * 32
            put(UInt64(cpu), width: 4, at: row, in: &bytes, little: little)
            put(cpu == intel ? 3 : 0, width: 4, at: row + 4, in: &bytes, little: little)
            put(UInt64(start), width: wide ? 8 : 4, at: row + 8, in: &bytes, little: little)
            put(32, width: wide ? 8 : 4, at: row + (wide ? 16 : 12), in: &bytes, little: little)
            put(5, width: 4, at: row + (wide ? 24 : 16), in: &bytes, little: little)
            bytes.replaceSubrange(start..<(start + 32), with: thin(cpu))
        }
        return bytes
    }
}

@MainActor func runMachOArchitectureChecks() -> Never {
    var checks: [(String, () throws -> Void)] = []
    func positive(_ name: String, _ bytes: Data, _ expected: [String]) {
        checks.append((name, {
            let actual = try MachOArchitectures.parse(bytes)
            try expect(actual == expected, "Expected canonical architectures \(expected), got \(actual)")
        }))
    }
    func negative(_ name: String, _ bytes: Data) {
        checks.append((name, {
            try refuses(.wrongArchitecture) { _ = try MachOArchitectures.parse(bytes) }
        }))
    }
    for little in [false, true] {
        positive("thin arm64 endian=\(little)", MachOFixture.thin(MachOFixture.arm, little: little), ["arm64"])
        positive("thin x86_64 endian=\(little)", MachOFixture.thin(MachOFixture.intel, little: little), ["x86_64"])
        for wide in [false, true] {
            positive("universal wide=\(wide) endian=\(little)", MachOFixture.fat(wide: wide, little: little), ["arm64", "x86_64"])
        }
    }
    // CHECK-MODIFIED PAT-2706 subtype repair: Apple names arm64e/x86_64h
    // separately, so those subtypes cannot satisfy today's generic-only pins.
    // Only these two earlier expectations change; all other original cases stay exact.
    negative("arm64e subtype cannot satisfy generic arm64 pin", MachOFixture.thin(MachOFixture.arm, subtype: 2))
    negative("x86_64h subtype cannot satisfy generic x86_64 pin", MachOFixture.thin(MachOFixture.intel, subtype: 8))
    for size in [0, 1, 3, 4, 7, 8, 27, 31] {
        negative("truncated thin \(size)", Data(MachOFixture.thin(MachOFixture.arm).prefix(size)))
    }
    for size in [7, 8, 27, 47, 95, 127, 159] {
        negative("truncated universal \(size)", Data(MachOFixture.fat().prefix(size)))
    }
    negative("non Mach-O bytes", Data(repeating: 0xff, count: 160))
    negative("unsupported thin 32-bit CPU", MachOFixture.thin(7))
    negative("unsupported thin CPU", MachOFixture.thin(0x01000012))
    for (name, offset, value) in [("thin non executable", 12, UInt64(6)), ("thin wrong magic", 0, UInt64(0xfeedface))] {
        var bytes = MachOFixture.thin(MachOFixture.arm)
        MachOFixture.put(value, width: 4, at: offset, in: &bytes, little: true)
        negative(name, bytes)
    }
    for wide in [false, true] {
        let stride = wide ? 32 : 20
        let cases: [(String, Int, UInt64, Int)] = [
            ("zero slices", 4, 0, 4), ("excessive slices", 4, 65, 4),
            ("overflowing slice count", 4, UInt64(UInt32.max), 4),
            ("duplicate CPU", 8 + stride, UInt64(MachOFixture.intel), 4),
            ("unknown fat CPU", 8, 0x01000012, 4),
            ("slice overlaps table", 16, 16, wide ? 8 : 4),
            ("slice starts beyond file", 16, 4096, wide ? 8 : 4),
            ("slice size exceeds file", 8 + (wide ? 16 : 12), 4096, wide ? 8 : 4),
            ("slice too short", 8 + (wide ? 16 : 12), 31, wide ? 8 : 4),
            ("slice overlaps sibling", 8 + stride + 8, 96, wide ? 8 : 4),
            ("misaligned slice", 16, 97, wide ? 8 : 4),
            ("alignment shift overflow", 8 + (wide ? 24 : 16), 64, 4),
            ("fat inner CPU disagreement", 100, UInt64(MachOFixture.arm), 4),
            ("fat inner subtype disagreement", 104, 8, 4),
            ("fat inner wrong magic", 96, 0, 4),
            ("fat inner non executable", 108, 6, 4)
        ]
        for (name, offset, value, width) in cases {
            var bytes = MachOFixture.fat(wide: wide)
            MachOFixture.put(value, width: width, at: offset, in: &bytes, little: offset >= 96)
            negative("\(name) wide=\(wide)", bytes)
        }
    }
    var reserved = MachOFixture.fat(wide: true)
    MachOFixture.put(1, width: 4, at: 36, in: &reserved)
    negative("fat64 reserved field nonzero", reserved)
    var overflow = MachOFixture.fat(wide: true)
    MachOFixture.put(UInt64.max - 15, width: 8, at: 16, in: &overflow)
    MachOFixture.put(32, width: 8, at: 24, in: &overflow)
    negative("fat64 offset plus size overflow", overflow)
    var oversized = MachOFixture.fat(wide: true)
    MachOFixture.put(UInt64.max, width: 8, at: 24, in: &oversized)
    negative("fat64 unrepresentable slice size", oversized)
    // CHECK-ADDED PAT-2706 subtype repair: independently match raw outer/inner
    // subtype words in universal fixtures. High eight capability bits are masked
    // for naming, while low24 subtype bits must be ARM64_ALL=0/X86_64_ALL=3.
    let subtypeVariants: [(UInt32, [UInt32])] = [
        (MachOFixture.arm, [1, 2, 0x00ffffff]),
        (MachOFixture.intel, [0, 8, 0x00ffffff])
    ]
    let capabilityFlags: [UInt32] = [0x80000000, 0x01000000, 0xff000000]
    for little in [false, true] {
        for (cpu, variants) in subtypeVariants {
            for subtype in variants {
                negative("thin nongeneric subtype cpu=\(cpu) subtype=\(subtype) endian=\(little)",
                         MachOFixture.thin(cpu, little: little, subtype: subtype))
            }
            let generic: UInt32 = cpu == MachOFixture.arm ? 0 : 3
            for flags in capabilityFlags {
                positive("thin generic capability bits cpu=\(cpu) flags=\(flags) endian=\(little)",
                         MachOFixture.thin(cpu, little: little, subtype: generic | flags),
                         [cpu == MachOFixture.arm ? "arm64" : "x86_64"])
            }
        }
        for wide in [false, true] {
            let stride = wide ? 32 : 20
            for (cpu, variants) in subtypeVariants {
                let index = cpu == MachOFixture.intel ? 0 : 1
                for subtype in variants {
                    var bytes = MachOFixture.fat(wide: wide, little: little)
                    MachOFixture.put(UInt64(subtype), width: 4, at: 8 + index * stride + 4, in: &bytes, little: little)
                    // Existing fat fixture's slice headers are little-endian,
                    // independently of the outer table's byte order.
                    MachOFixture.put(UInt64(subtype), width: 4, at: 96 + index * 32 + 8, in: &bytes, little: true)
                    negative("universal nongeneric subtype cpu=\(cpu) subtype=\(subtype) wide=\(wide) endian=\(little)", bytes)
                }
            }
            for flags in capabilityFlags {
                var bytes = MachOFixture.fat(wide: wide, little: little)
                for (index, generic) in [UInt32(3), UInt32(0)].enumerated() {
                    let subtype = generic | flags
                    MachOFixture.put(UInt64(subtype), width: 4, at: 8 + index * stride + 4, in: &bytes, little: little)
                    MachOFixture.put(UInt64(subtype), width: 4, at: 96 + index * 32 + 8, in: &bytes, little: true)
                }
                positive("universal generic capability bits flags=\(flags) wide=\(wide) endian=\(little)", bytes, ["arm64", "x86_64"])
            }
            var mismatchedFlags = MachOFixture.fat(wide: wide, little: little)
            MachOFixture.put(0x80000003, width: 4, at: 104, in: &mismatchedFlags, little: true)
            negative("universal raw capability mismatch wide=\(wide) endian=\(little)", mismatchedFlags)
        }
    }
    var failures: [String] = []
    for (name, body) in checks {
        do { try body() } catch { failures.append("\(name): \(error)") }
    }
    for failure in failures { print("FAIL \(failure)") }
    print("PAT-2706 Mach-O fixtures: \(checks.count) cases; \(failures.count) failures. Synthetic parser checks are not clean-Mac proof.")
    exit(failures.isEmpty ? 0 : 1)
}
