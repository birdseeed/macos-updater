// Pure synthetic configuration values; validation performs no platform lookup.
public enum NetworkPrincipal: String, Equatable, Sendable { case fixtureOwner, fixtureOther }
public enum NetworkMode: String, Equatable, Sendable { case system, direct, manualHTTP }
public enum NetworkConfigurationResult: Equatable, Sendable {
    case refused(NetworkRefusal)
    case syntheticValid
}
public struct NetworkConfiguration: Equatable, Sendable {
    public let principal: NetworkPrincipal
    public let revision: UInt64
    public let mode: NetworkMode
    public let host: String?
    public let port: Int?
    public let credentialReference: String?
    public init(principal: NetworkPrincipal = .fixtureOwner, revision: UInt64 = 1,
                mode: NetworkMode = .system, host: String? = nil, port: Int? = nil,
                credentialReference: String? = nil) {
        self.principal = principal; self.revision = revision; self.mode = mode
        self.host = host; self.port = port; self.credentialReference = credentialReference
    }
    public func validate() -> NetworkConfigurationResult {
        guard revision > 0 else { return .refused(.invalidConfiguration) }
        switch mode {
        case .system, .direct:
            guard host == nil, port == nil, credentialReference == nil else {
                return .refused(.invalidConfiguration)
            }
        case .manualHTTP:
            guard let host, let port, (1...65535).contains(port), Self.validHost(host) else {
                return .refused(.invalidConfiguration)
            }
            if let credentialReference {
                guard Self.validReference(credentialReference) else { return .refused(.invalidConfiguration) }
            }
        }
        return .syntheticValid
    }

    private static func alphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func validReference(_ value: String) -> Bool {
        let length = value.utf8.prefix(65).count
        return (1...64).contains(length) && value.utf8.allSatisfy {
            alphanumeric($0) || $0 == 95 || $0 == 45
        }
    }

    private static func validHost(_ host: String) -> Bool {
        // Bound bytes before allocating any parser arrays, including for hostile input.
        guard (1...253).contains(host.utf8.prefix(254).count) else { return false }
        let bytes = Array(host.utf8)
        if bytes.first == 91 {
            guard bytes.last == 93 else { return false }
            return validIPv6(Array(bytes.dropFirst().dropLast()))
        }
        if bytes.allSatisfy({ (48...57).contains($0) || $0 == 46 }) {
            let octets = bytes.split(separator: 46, omittingEmptySubsequences: false)
            guard octets.count == 4 else { return false }
            return octets.allSatisfy { octet in
                guard (1...3).contains(octet.count), octet.count == 1 || octet.first != 48 else { return false }
                return octet.reduce(0) { $0 * 10 + Int($1 - 48) } <= 255
            }
        }
        let labels = bytes.split(separator: 46, omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.count), let first = label.first, let last = label.last,
                  alphanumeric(first), alphanumeric(last) else { return false }
            return label.allSatisfy { alphanumeric($0) || $0 == 45 }
        }
    }

    private static func validIPv6(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty, bytes.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 58
        }) else { return false }
        var compression: Int?
        for index in bytes.indices.dropLast() where bytes[index] == 58 && bytes[index + 1] == 58 {
            guard compression == nil else { return false }
            compression = index
        }
        func validGroups(_ side: ArraySlice<UInt8>) -> Int? {
            if side.isEmpty { return 0 }
            let groups = side.split(separator: 58, omittingEmptySubsequences: false)
            guard groups.allSatisfy({ (1...4).contains($0.count) }) else { return nil }
            return groups.count
        }
        if let compression {
            guard let left = validGroups(bytes[..<compression]),
                  let right = validGroups(bytes[(compression + 2)...]) else { return false }
            return left + right < 8
        }
        return validGroups(bytes[...]) == 8
    }
}
