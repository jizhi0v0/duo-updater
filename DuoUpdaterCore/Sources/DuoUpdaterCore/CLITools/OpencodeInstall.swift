import Foundation

/// SKELETON — replaced by the opencode integration. One opencode install as the
/// scan finds it.
public struct OpencodeInstall: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

/// SKELETON — replaced by the opencode integration. opencode's own update settings.
public struct OpencodeSettings: Sendable, Equatable, Codable {
    public init() {}
}
