import Foundation

/// One update on offer outside the app list — an install of a command-line
/// tool, an outdated Homebrew package — as the "updates available" banner
/// announces it.
public struct UpdateAnnouncementItem: Sendable, Equatable {
    /// What stays the same across versions: "claude-code:/Users/…/claude",
    /// "formula:jq".
    public let key: String
    /// What the banner calls it.
    public let name: String
    /// The version on offer.
    public let version: String

    public init(key: String, name: String, version: String) {
        self.key = key
        self.name = name
        self.version = version
    }
}

/// The apps' announcement rules (`AppListModel.notifyNewUpdates`), for one more
/// category: which offers have been announced (`NotifiedUpdateVersions`, so an
/// endpoint flapping between two versions is not announced every check), and
/// whether the silent baseline has been taken.
public struct UpdateAnnouncementLedger: Sendable, Equatable {
    public private(set) var versions: NotifiedUpdateVersions
    public private(set) var seeded: Bool

    public init(versions: NotifiedUpdateVersions = NotifiedUpdateVersions(), seeded: Bool = false) {
        self.versions = versions
        self.seeded = seeded
    }

    /// One look at what is on offer now. Returns the names of the offers not
    /// announced before, in `offered` order, each once.
    ///
    /// - With the category's switch off, nothing is announced and nothing
    ///   recorded, as for apps: the switch stops the bookkeeping too.
    /// - The first pass ever announces nothing and records everything: the user
    ///   can already see what is pending, and a DuoUpdater update must not post
    ///   a banner for every update that was already there.
    /// - `liveKeys`: the items that still exist, to forget the rest. nil keeps
    ///   every entry, for a category whose read cannot tell "gone" from "not read".
    public mutating func pass(
        enabled: Bool, offered: [UpdateAnnouncementItem], liveKeys: Set<String>?
    ) -> [String] {
        guard enabled else { return [] }
        guard seeded else {
            for item in offered { versions.record(Self.side(item), under: item.key) }
            seeded = true
            return []
        }
        let newly = offered.filter { !versions.wasAnnounced(Self.side($0), under: [$0.key]) }
        if let liveKeys { versions.prune(liveKeys: liveKeys) }
        for item in offered { versions.record(Self.side(item), under: item.key) }
        var seen = Set<String>()
        return newly.map(\.name).filter { seen.insert($0).inserted }
    }

    private static func side(_ item: UpdateAnnouncementItem) -> VersionSide {
        VersionSide(marketing: item.version)
    }
}

/// The one "updates available" banner a round posts, across the categories
/// whose switch is on.
public enum UpdateBanner {

    public enum Category: Int, Sendable, CaseIterable {
        case apps, commandLineTools, homebrew
    }

    /// One category's part of a round.
    public struct Part: Sendable, Equatable {
        public let category: Category
        /// Its switch in Settings › Notifications.
        public let enabled: Bool
        /// What it newly offers this round.
        public let newly: [String]
        /// Everything it offers now, new or not.
        public let pending: Int

        public init(category: Category, enabled: Bool, newly: [String], pending: Int) {
            self.category = category
            self.enabled = enabled
            self.newly = newly
            self.pending = pending
        }
    }

    public struct Content: Sendable, Equatable {
        /// What every enabled category offers now: the title's count.
        public let total: Int
        /// What is new, apps first, then command-line tools, then Homebrew.
        public let names: [String]
        /// Everything new is an app, so "Update All" — which updates apps — does
        /// what it says.
        public let appsOnly: Bool

        public init(total: Int, names: [String], appsOnly: Bool) {
            self.total = total
            self.names = names
            self.appsOnly = appsOnly
        }
    }

    /// nil when nothing in an enabled category is new: the banner is for what
    /// appeared, never a reminder of what was already there.
    public static func compose(_ parts: [Part]) -> Content? {
        let on = parts.filter(\.enabled).sorted { $0.category.rawValue < $1.category.rawValue }
        var seen = Set<String>()
        let names = on.flatMap(\.newly).filter { seen.insert($0).inserted }
        guard !names.isEmpty else { return nil }
        return Content(
            total: on.reduce(0) { $0 + $1.pending },
            names: names,
            appsOnly: on.allSatisfy { $0.category == .apps || $0.newly.isEmpty })
    }
}
