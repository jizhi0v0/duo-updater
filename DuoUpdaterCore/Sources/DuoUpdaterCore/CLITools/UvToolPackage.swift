import Foundation

/// SKELETON — replaced by the uv tool integration. One uv tool install as the
/// scan finds it.
public struct UvToolPackage: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}
