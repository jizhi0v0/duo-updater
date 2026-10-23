import Foundation

/// What an adapter's check decided for one item, before the shared rules
/// (`ManagedCheck`) turn it into a `CLIToolStatus`.
public struct ManagedVerdict: Sendable, Equatable {
    public let item: ManagedItem
    /// The vendor's own notion of outdated: whether its upgrade command would
    /// move this item (mise's plain `outdated`; uv's `--outdated` for an
    /// unpinned tool; a newer patch in a line's index). Nil when the adapter
    /// could not tell — a ranged uv specifier before D9's matcher.
    public let vendorWouldUpgrade: Bool?
    public let blocker: Blocker?
    /// The manager's own install or upgrade already running on this item or
    /// root, by argv (`ManagedActivity`), in English.
    public let busy: String?

    public enum Blocker: Sendable, Equatable {
        /// mise lists it but no config requests it (`mise outdated` reports one
        /// request per tool, MISE-23).
        case notRequested(String)
        /// Not on an index the check can read: a git or path crate, an editable
        /// pipx venv, a `(devel)` or pseudo-version Go binary. The reason.
        case notIndexed(String)
        /// A version string the check cannot compare.
        case unknownVersionForm(String)
        /// The index or the manager's command did not answer. The reason.
        case channelUnreadable(String)
        case rateLimited
        case versionUnreadable
        /// The newest needs a newer runtime than the one here (a crate's
        /// `rust_version` above the toolchain's rustc). The requirement.
        case runtimeTooOld(String)

        var withheld: CLIToolWithheld {
            switch self {
            case .notRequested, .notIndexed, .unknownVersionForm: return .unsupportedInstaller
            case .channelUnreadable: return .channelUnreadable
            case .rateLimited: return .rateLimited
            case .versionUnreadable: return .versionUnreadable
            case .runtimeTooOld: return .runtimeTooOld
            }
        }

        var note: String {
            switch self {
            case .notRequested(let why): return "not checked: \(why)"
            case .notIndexed(let why): return "not on an index: \(why)"
            case .unknownVersionForm(let version): return "version \(version) is not a release the index names"
            case .channelUnreadable(let why): return "could not read the release channel: \(why)"
            case .rateLimited: return "GitHub's API rate limit"
            case .versionUnreadable: return "the installed version could not be read"
            case .runtimeTooOld(let requirement): return "the newest release needs \(requirement)"
            }
        }
    }

    public init(item: ManagedItem, vendorWouldUpgrade: Bool?, blocker: Blocker? = nil, busy: String? = nil) {
        self.item = item
        self.vendorWouldUpgrade = vendorWouldUpgrade
        self.blocker = blocker
        self.busy = busy
    }
}
