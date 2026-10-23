import Foundation

/// Which manager keeps a managed item — a value, not a type, so that adding a
/// manager adds an adapter and a registry line and no `switch` anywhere else
/// (plans/cli-managers-redesign.md §1).
///
/// The raw value is part of every managed row's identity
/// (`ManagedItem.identity`, "<manager>|<root>|<key>") and of its provider's id
/// ("managed:<manager>"), so it holds no `|`. Lower-case, hyphenated: "mise",
/// "uv-tool", "uv-python", "pipx", "nvm-node", "fnm-node", "pyenv", "rbenv",
/// "cargo", "go".
public struct ManagerID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.contains("|"), "a manager id is part of an identity split on |")
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) { self.init(rawValue: rawValue) }

    public var description: String { rawValue }

    /// The separator between the three parts of a managed row's identity.
    static let identitySeparator: Character = "|"
}
