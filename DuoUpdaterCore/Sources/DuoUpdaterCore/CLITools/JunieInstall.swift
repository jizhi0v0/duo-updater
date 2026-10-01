import Foundation

/// SKELETON — replaced by the junie integration. One junie install as the
/// scan finds it.
public struct JunieInstall: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

/// SKELETON — Junie's own settings that decide an offer (`auto-update`).
public struct JunieSettings: Sendable, Equatable {
    public init() {}
}
