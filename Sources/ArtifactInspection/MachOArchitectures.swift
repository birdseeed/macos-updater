import Foundation
import Darwin

/// Architecture inspection only. This does not establish signing or installation authority.
public enum MachOArchitectures {
    @_spi(Testing) public static func parse(_ bytes: Data) throws -> [String] {
        // Normalise Data's index origin for the fixture-only adapter.
        let data = Data(bytes)
        return try parse(length: UInt64(data.count)) { offset, count in
            guard offset <= UInt64(data.count), UInt64(count) <= UInt64(data.count) - offset else {
                throw InspectionFailure.wrongArchitecture
            }
            return data.subdata(in: Int(offset)..<(Int(offset) + count))
        }
    }

    /// Reads a caller-owned regular-file descriptor without closing it or changing
    /// its offset. This extracts architectures only, never signing/install authority.
    public static func inspect(fileDescriptor fd: Int32) throws -> [String] {
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw InspectionFailure.notRegularFile }
        guard before.st_size >= 0 else { throw InspectionFailure.wrongArchitecture }
        let length = UInt64(before.st_size)
        let result = try parse(length: length) { offset, count in
            guard offset <= length, UInt64(count) <= length - offset, offset <= UInt64(Int64.max) else {
                throw InspectionFailure.wrongArchitecture
            }
            var bytes = [UInt8](repeating: 0, count: count), completed = 0
            while completed < count {
                let amount = bytes.withUnsafeMutableBytes { buffer in
                    pread(fd, buffer.baseAddress!.advanced(by: completed), count - completed, off_t(offset) + off_t(completed))
                }
                if amount < 0 && errno == EINTR { continue }
                guard amount > 0 else { throw InspectionFailure.wrongArchitecture }
                completed += amount
            }
            return Data(bytes)
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_mode == after.st_mode, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw InspectionFailure.wrongArchitecture
        }
        return result
    }

    private static func word(_ bytes: Data, _ offset: Int, _ width: Int = 4, little: Bool = false) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<width {
            let position = little ? offset + width - 1 - index : offset + index
            result = (result << 8) | UInt64(bytes[position])
        }
        return result
    }
    private static func thin(_ bytes: Data) throws -> (cpu: UInt64, subtype: UInt64, name: String) {
        guard bytes.count == 32 else { throw InspectionFailure.wrongArchitecture }
        let magic = word(bytes, 0)
        guard magic == 0xfeedfacf || magic == 0xcffaedfe else { throw InspectionFailure.wrongArchitecture }
        let little = magic == 0xcffaedfe, cpu = word(bytes, 4, little: little)
        guard word(bytes, 12, little: little) == 2, cpu == 0x0100000c || cpu == 0x01000007 else {
            throw InspectionFailure.wrongArchitecture
        }
        let subtype = word(bytes, 8, little: little)
        // Apple architecture naming masks capability bits, but specialised or
        // unknown base subtypes cannot satisfy the current generic-only pins.
        guard subtype & 0x00ffffff == (cpu == 0x0100000c ? 0 : 3) else { throw InspectionFailure.wrongArchitecture }
        return (cpu, subtype, cpu == 0x0100000c ? "arm64" : "x86_64")
    }
    private static func parse(length: UInt64, read: (UInt64, Int) throws -> Data) throws -> [String] {
        guard length >= 4 else { throw InspectionFailure.wrongArchitecture }
        let magic = word(try read(0, 4), 0)
        if magic == 0xfeedfacf || magic == 0xcffaedfe {
            guard length >= 32 else { throw InspectionFailure.wrongArchitecture }
            return [try thin(read(0, 32)).name]
        }
        guard [UInt64(0xcafebabe), 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic), length >= 8 else {
            throw InspectionFailure.wrongArchitecture
        }
        let little = magic == 0xbebafeca || magic == 0xbfbafeca
        let wide = magic == 0xcafebabf || magic == 0xbfbafeca
        let count = word(try read(0, 8), 4, little: little), stride = wide ? 32 : 20
        guard count > 0, count <= 64 else { throw InspectionFailure.wrongArchitecture }
        let tableSize = Int(count) * stride, tableEnd = UInt64(8 + tableSize)
        guard tableEnd <= length else { throw InspectionFailure.wrongArchitecture }
        let table = try read(8, tableSize)
        var names: Set<String> = [], ranges: [(UInt64, UInt64)] = []
        for index in 0..<Int(count) {
            let row = index * stride, width = wide ? 8 : 4
            let cpu = word(table, row, little: little), subtype = word(table, row + 4, little: little)
            let offset = word(table, row + 8, width, little: little)
            let size = word(table, row + (wide ? 16 : 12), width, little: little)
            let alignment = word(table, row + (wide ? 24 : 16), little: little)
            guard alignment < 64, offset >= tableEnd, offset <= length, size >= 32, size <= length - offset,
                  offset % (UInt64(1) << alignment) == 0,
                  !wide || word(table, row + 28, little: little) == 0 else { throw InspectionFailure.wrongArchitecture }
            let end = offset + size
            guard !ranges.contains(where: { offset < $0.1 && $0.0 < end }) else { throw InspectionFailure.wrongArchitecture }
            let header = try thin(read(offset, 32))
            guard header.cpu == cpu, header.subtype == subtype, names.insert(header.name).inserted else {
                throw InspectionFailure.wrongArchitecture
            }
            ranges.append((offset, end))
        }
        return names.sorted()
    }
}
