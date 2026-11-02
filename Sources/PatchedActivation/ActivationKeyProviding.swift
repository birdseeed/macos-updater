import Foundation

public protocol ActivationKeyProviding {
    func existingPublicKey() throws -> Data
    func signPossessionMessage(_ message: Data) throws -> Data
}

/// Always refuses. A1 adds no native generation, storage, helper or key adapter.
public struct UnavailableActivationKeyProvider: ActivationKeyProviding {
    public init() {}
    public func existingPublicKey() throws -> Data { throw ActivationError.keyUnavailable }
    public func signPossessionMessage(_ message: Data) throws -> Data { throw ActivationError.keyUnavailable }
}
