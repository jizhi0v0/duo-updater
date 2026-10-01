import Foundation

/// SKELETON — replaced by the uv integration. One uv install as the
/// scan finds it.
public struct UvInstall: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}
