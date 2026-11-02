import Foundation

// Internal finite framing for the controlled manual probe only. It retains at
// most the 8192-byte header, never a body or a chunk line. Each consume call does
// linear work in the caller's bounded input. No decoder, trailer or reuse path.
struct ManualProxyProbeResponseParser {
    private enum Phase {
        case header, fixed(Int), untilEOF, chunkSize, chunkData(Int)
        case chunkCR, chunkLF, terminalCR, terminalLF, complete
    }
    private var phase = Phase.header
    private var header: [UInt8] = []
    private var metadataBytes = 0
    private var bodyBytes = 0
    private var status = 0
    private var chunkLength = 0
    private var chunkDigits = 0
    private var chunkSizeSawCR = false
    private static var failed: NativeConnectionProbeOutcome { .refused(.transportFailed) }
    private var response: NativeConnectionProbeOutcome { .response(statusCode: status, bytes: bodyBytes) }

    mutating func consume(_ input: ArraySlice<UInt8>) -> NativeConnectionProbeOutcome? {
        var index = input.startIndex
        while index < input.endIndex {
            switch phase {
            case .header:
                let byte = input[index]; index += 1
                guard addMetadata(1), byte == 9 || byte == 13 || byte == 10 || (32...126).contains(byte),
                      !(header.last == 13 && byte != 10),
                      !(byte == 10 && header.last != 13) else { return Self.failed }
                header.append(byte)
                if header.count >= 4 && header.suffix(4).elementsEqual([13, 10, 13, 10]) {
                    if let outcome = parseHeader() { return outcome }
                }
            case .fixed(let remaining):
                let count = min(remaining, input.endIndex - index)
                bodyBytes += count; index += count
                if count == remaining { phase = .complete; return response }
                phase = .fixed(remaining - count)
            case .untilEOF:
                let count = input.endIndex - index
                guard count <= 65536 - bodyBytes else { return .refused(.responseTooLarge) }
                bodyBytes += count; index = input.endIndex
            case .chunkSize:
                let byte = input[index]; index += 1
                guard addMetadata(1) else { return Self.failed }
                if chunkSizeSawCR {
                    guard byte == 10, chunkDigits > 0 else { return Self.failed }
                    let count = chunkLength
                    chunkLength = 0; chunkDigits = 0; chunkSizeSawCR = false
                    guard count <= 65536 - bodyBytes else { return .refused(.responseTooLarge) }
                    phase = count == 0 ? .terminalCR : .chunkData(count)
                } else if byte == 13 { chunkSizeSawCR = true }
                else {
                    guard let digit = Self.hexDigit(byte) else { return Self.failed }
                    let (times, multiplyOverflow) = chunkLength.multipliedReportingOverflow(by: 16)
                    let (next, addOverflow) = times.addingReportingOverflow(digit)
                    guard !multiplyOverflow, !addOverflow else { return Self.failed }
                    chunkLength = next; chunkDigits += 1
                }
            case .chunkData(let remaining):
                let count = min(remaining, input.endIndex - index)
                bodyBytes += count; index += count
                phase = count == remaining ? .chunkCR : .chunkData(remaining - count)
            case .chunkCR:
                guard addMetadata(1), input[index] == 13 else { return Self.failed }
                index += 1; phase = .chunkLF
            case .chunkLF:
                guard addMetadata(1), input[index] == 10 else { return Self.failed }
                index += 1; phase = .chunkSize
            case .terminalCR:
                guard addMetadata(1), input[index] == 13 else { return Self.failed }
                index += 1; phase = .terminalLF
            case .terminalLF:
                guard addMetadata(1), input[index] == 10 else { return Self.failed }
                phase = .complete; return response
            case .complete: return response
            }
        }
        return nil
    }

    mutating func endOfStream() -> NativeConnectionProbeOutcome {
        switch phase {
        case .untilEOF: phase = .complete; return response
        case .complete: return response
        default: return Self.failed
        }
    }
    private mutating func addMetadata(_ count: Int) -> Bool {
        guard count <= 8192 - metadataBytes else { return false }
        metadataBytes += count; return true
    }
    private mutating func parseHeader() -> NativeConnectionProbeOutcome? {
        // All octets have already passed ASCII and exact CRLF validation.
        let lines = String(decoding: header.dropLast(4), as: UTF8.self).components(separatedBy: "\r\n")
        header.removeAll()
        guard let first = lines.first else { return Self.failed }
        let statusLine = Array(first.utf8)
        guard statusLine.count >= 13, statusLine.prefix(9).elementsEqual("HTTP/1.1 ".utf8),
              statusLine[12] == 32, statusLine.allSatisfy({ (32...126).contains($0) }),
              statusLine[9...11].allSatisfy({ (48...57).contains($0) }) else { return Self.failed }
        status = Int(statusLine[9] - 48) * 100 + Int(statusLine[10] - 48) * 10 + Int(statusLine[11] - 48)
        guard (200...599).contains(status) else { return Self.failed }
        var contentLength: Int?
        var chunked = false
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return Self.failed }
            let name = line[..<colon]
            guard !name.isEmpty, name.utf8.allSatisfy(Self.tokenByte) else { return Self.failed }
            let rawValue = Array(line[line.index(after: colon)...].utf8)
            var lower = 0, upper = rawValue.count
            while lower < upper && (rawValue[lower] == 32 || rawValue[lower] == 9) { lower += 1 }
            while upper > lower && (rawValue[upper - 1] == 32 || rawValue[upper - 1] == 9) { upper -= 1 }
            let value = rawValue[lower..<upper]
            switch name.lowercased() {
            case "content-length":
                guard contentLength == nil, !value.isEmpty else { return Self.failed }
                var length = 0
                for byte in value {
                    guard (48...57).contains(byte) else { return Self.failed }
                    let (times, multiplyOverflow) = length.multipliedReportingOverflow(by: 10)
                    let (next, addOverflow) = times.addingReportingOverflow(Int(byte - 48))
                    guard !multiplyOverflow, !addOverflow else { return Self.failed }
                    length = next
                }
                contentLength = length
            case "transfer-encoding":
                guard !chunked, String(decoding: value, as: UTF8.self).lowercased() == "chunked" else {
                    return Self.failed
                }
                chunked = true
            case "content-encoding": return Self.failed
            default: break
            }
        }
        guard !chunked || contentLength == nil else { return Self.failed }
        if status == 401 || status == 407 { return .refused(.authenticationRequired) }
        if (300...399).contains(status) { return .refused(.unsupportedEndpoint) }
        if status == 204 { phase = .complete; return response }
        if let contentLength {
            guard contentLength <= 65536 else { return .refused(.responseTooLarge) }
            phase = contentLength == 0 ? .complete : .fixed(contentLength)
            if contentLength == 0 { return response }
        } else { phase = chunked ? .chunkSize : .untilEOF }
        return nil
    }
    private static func hexDigit(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: return Int(byte - 48)
        case 65...70: return Int(byte - 65 + 10)
        case 97...102: return Int(byte - 97 + 10)
        default: return nil
        }
    }
    private static func tokenByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
        [33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126].contains(byte)
    }
}
