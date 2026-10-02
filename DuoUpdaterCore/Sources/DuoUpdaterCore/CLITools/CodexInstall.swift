import Foundation

/// SKELETON — replaced by the Codex integration. One Codex install as the
/// scan finds it.
public struct CodexInstall: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

/// SKELETON — replaced by the Codex integration. Codex's own update settings.
public struct CodexSettings: Sendable, Equatable, Codable {
    public init() {}
}
