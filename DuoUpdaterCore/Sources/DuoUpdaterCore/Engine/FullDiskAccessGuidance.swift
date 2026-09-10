#if os(macOS)
import Foundation

/// What only Full Disk Access can read — one case per read.
///
/// Measured 2026-09-10 on macOS 27 with a never-granted probe: TestFlight's store
/// and another app's container were refused (EPERM), while other apps' preferences
/// through `CFPreferences` and files under Application Support or `~/Movies` read
/// fine. So these two are the whole list today.
///
/// Adding a read that needs it means adding a case here and sending the read
/// through ``FullDiskAccessNeeds/mayRead(_:for:fullDiskAccess:)``. The explanation
/// the menu shows switches over this type, so a new case does not compile until it
/// says what it is for; the Welcome card, the Diagnostics row, the README and the
/// site's permissions page name these reads in prose and have to be edited by hand.
public enum FullDiskAccessNeed: String, CaseIterable, Sendable {
    /// TestFlight's own store: the builds it offers, for a beta installed from it.
    case testFlight
    /// CotEditor's update channel, which the sandboxed app keeps in its container.
    case cotEditorChannel

    /// Whether this read, turned away, can change what a row says about a copy on
    /// `releaseChannel` — as detected from the copy's own version, since the read
    /// that could have said otherwise was not taken. Decides whether the row's name
    /// line carries a mark.
    ///
    /// TestFlight: never — its row already says it cannot tell, with its own
    /// question mark. CotEditor: only a stable copy; a prerelease is recognized
    /// from its version, so the setting could not change the answer.
    public func mayAffect(releaseChannel: ReleaseChannel) -> Bool {
        switch self {
        case .testFlight: false
        case .cotEditorChannel: releaseChannel == .stable
        }
    }
}

/// The gate every read that only Full Disk Access can reach goes through, and the
/// record of the apps it turned away this launch — which is what the menu's
/// explanation names, so it never guesses from a list of apps that might need it.
///
/// Recording only: the explanation is shown when the menu opens
/// (`FullDiskAccessGuidance`), never from here — most of these reads happen in a
/// background check, and a dialog then would interrupt whatever the user is doing.
public final class FullDiskAccessNeeds: @unchecked Sendable {
    public static let shared = FullDiskAccessNeeds()

    private let lock = NSLock()
    private var refusedApps: [FullDiskAccessNeed: Set<String>] = [:]

    public init() {}

    /// Whether `need` may be read now for `apps` (bundle ids, or paths when there
    /// is none). Yes with Full Disk Access, or when its status cannot be read
    /// (`TCCPreflight.admitsOtherAppsData`); otherwise no, and the apps are
    /// remembered.
    public func mayRead(
        _ need: FullDiskAccessNeed, for apps: [String],
        fullDiskAccess: TCCAuthStatus = TCCPreflight.fullDiskAccessStatus()
    ) -> Bool {
        let admitted = TCCPreflight.admitsOtherAppsData(fullDiskAccess: fullDiskAccess)
        if !admitted { recordRefusal(need, for: apps) }
        return admitted
    }

    /// For a read decided before the apps it serves are known: a round decides
    /// whether to read TestFlight's store before its scan says which apps are
    /// TestFlight betas, so it records them once the scan has.
    public func recordRefusal(_ need: FullDiskAccessNeed, for apps: [String]) {
        guard !apps.isEmpty else { return }
        lock.withLock { refusedApps[need, default: []].formUnion(apps) }
    }

    /// Everything turned away since launch, by read.
    public func refused() -> [FullDiskAccessNeed: Set<String>] {
        lock.withLock { refusedApps }
    }
}

/// When the menu explains Full Disk Access — the one permission macOS never asks
/// about on anyone's behalf.
///
/// At most twice. The second time only when an app that needs it has appeared
/// since the first: the first "Not Now" may have been a slip, but asking again
/// about the same apps is nagging. After the second, never again — the Diagnostics
/// row stays for anyone who changes their mind.
public enum FullDiskAccessGuidance {
    public static let maximumAsks = 2

    /// What has been asked so far, kept across launches.
    public struct State: Equatable, Sendable {
        public var timesAsked: Int
        /// The apps (bundle id, or path when there is none) named the last time.
        public var appsWhenLastAsked: Set<String>

        public init(timesAsked: Int = 0, appsWhenLastAsked: Set<String> = []) {
            self.timesAsked = timesAsked
            self.appsWhenLastAsked = appsWhenLastAsked
        }
    }

    /// Whether to explain it now, to someone looking at the menu, given the apps
    /// a read has turned away (`FullDiskAccessNeeds`).
    ///
    /// Not when it is granted, and not when the status cannot be read: that is no
    /// evidence it is missing, and the explanation would be a guess.
    public static func shouldAsk(
        fullDiskAccess: TCCAuthStatus, needing: Set<String>, state: State
    ) -> Bool {
        switch fullDiskAccess {
        case .granted, .unknown: return false
        case .denied, .notDetermined: break
        }
        guard !needing.isEmpty, state.timesAsked < maximumAsks else { return false }
        return state.timesAsked == 0 || !needing.isSubset(of: state.appsWhenLastAsked)
    }

    /// The state after asking about `needing`. Every showing counts, whichever
    /// button closed it: "Grant…" that never reaches the switch in System Settings
    /// is not a reason to ask forever.
    public static func recordingAsk(_ state: State, needing: Set<String>) -> State {
        State(timesAsked: state.timesAsked + 1, appsWhenLastAsked: needing)
    }
}
#endif
