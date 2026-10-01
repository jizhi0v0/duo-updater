import Foundation

/// SKELETON — replaced by the npm integration. One npm install as the
/// scan finds it.
public struct NpmPackage: Sendable, Equatable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}
