import Foundation

/// SKELETON — replaced by the rust integration. One rust install as the
/// scan finds it.
public struct RustItem: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

/// SKELETON — rustup's own settings that decide an offer (`auto_self_update`).
public struct RustupSettings: Sendable, Equatable {
    public init() {}
}
