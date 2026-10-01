import Foundation

/// One copy of bub on this Mac, identified by where it is.
///
/// SKELETON — filled in by the bub work: the scanner, the check, the updater and
/// the release notes live beside this file as `Bub*.swift`.
public struct BubInstall: Sendable, Equatable, Codable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}
