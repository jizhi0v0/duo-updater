import Foundation

/// One copy of fx on this Mac, identified by where it is.
///
/// SKELETON — filled in by the fx work: the scanner, the check, the updater and
/// the release notes live beside this file as `Fx*.swift`.
public struct FxInstall: Sendable, Equatable, Codable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

/// fx's user-wide settings that govern its updates (`~/.fx/settings.json`).
///
/// SKELETON — filled in by the fx work.
public struct FxSettings: Sendable, Equatable, Codable {
    public init() {}
}
