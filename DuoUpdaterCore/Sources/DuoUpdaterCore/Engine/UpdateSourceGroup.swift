import Foundation

/// Which update source an app row is grouped under when the Apps list is grouped
/// by update source (`RowOrder.Grouping.source`, issue #1985).
///
/// The group is the source that acts for this row, and it matches how the
/// row's "via …" line names it (`UpdateSourceLabel` in the app):
///
/// - Most rows: the source that answered, `RemoteVersion.sourceName`.
/// - A Homebrew copy that brew had nothing newer for, where another source was
///   then checked (`homebrewSourceIdentifier` is set): if that source has an
///   update, the row goes under it, because that source is what Update uses. If
///   it has nothing newer either, the row goes under Homebrew, the source that
///   installed the app.
///
/// The cases are in the order the groups are listed.
public enum UpdateSourceGroup: String, CaseIterable, Sendable, Identifiable {
    case sparkle
    case gitHub
    /// The update feed the app itself reads: Electron's manifest, MyGo.
    case appFeed
    /// The developer's own site: a per-app vendor probe recipe, Alcove.
    case vendor
    case homebrew
    case appStore
    case setapp
    case testFlight
    case toolbox
    case xcodeReleases
    /// No source that could be named: the check failed or found none, or a
    /// source without a known name answered.
    case other

    public var id: String { rawValue }

    public init(_ result: UpdateResult) {
        // These statuses say who manages the app even when no remote came with
        // them.
        switch result.status {
        case .appStoreManaged: self = .appStore; return
        case .testFlightManaged: self = .testFlight; return
        case .toolboxManaged: self = .toolbox; return
        default: break
        }
        guard let source = result.remote?.sourceName else {
            self = .other
            return
        }
        // Brew had nothing newer and another source was checked. If that source
        // has nothing newer either, Homebrew is still the source for this copy.
        if source != "Homebrew", result.homebrewSourceIdentifier != nil,
           result.status == .upToDate {
            self = .homebrew
            return
        }
        self = Self(sourceName: source)
    }

    /// The group of a `RemoteVersion.sourceName`. The names are the ones
    /// `UpdateSourceLabel` in the app recognises; any other name is `.other`.
    public init(sourceName: String) {
        switch sourceName {
        case "Sparkle": self = .sparkle
        case "GitHub": self = .gitHub
        case "Electron", MyGoUpdateSource.sourceName: self = .appFeed
        case "Vendor": self = .vendor
        case "Homebrew": self = .homebrew
        case "App Store": self = .appStore
        case "Setapp": self = .setapp
        case "TestFlight": self = .testFlight
        case "Toolbox": self = .toolbox
        case "Xcode Releases": self = .xcodeReleases
        default: self = .other
        }
    }

    /// One group's rows, in the list's order.
    public struct Section: Sendable, Equatable, Identifiable {
        public let group: UpdateSourceGroup
        public let rows: [UpdateResult]
        public var id: UpdateSourceGroup { group }
    }

    /// `rows` split into groups, in `allCases` order. Rows keep their order
    /// within a group, so each group is still sorted by tier first and then by
    /// the chosen sort (`RowOrder.sorted`). Groups with no rows are left out.
    ///
    /// - Parameter group: the group of a row. The app passes one that keeps a
    ///   row's group while the row order is frozen, so a row that changes group
    ///   during an install does not move to another section.
    public static func sections(
        _ rows: [UpdateResult],
        group: (UpdateResult) -> UpdateSourceGroup = { UpdateSourceGroup($0) }
    ) -> [Section] {
        var byGroup: [UpdateSourceGroup: [UpdateResult]] = [:]
        for row in rows { byGroup[group(row), default: []].append(row) }
        return allCases.compactMap { key in
            byGroup[key].map { Section(group: key, rows: $0) }
        }
    }
}

extension RowOrder {
    /// Whether the Apps list is one list or split into sections.
    ///
    /// Separate from `SortOrder`: grouping never changes the order inside a
    /// section, which is still tiers first and then the chosen sort.
    public enum Grouping: String, CaseIterable, Sendable, Identifiable {
        /// One list, as it has always been.
        case none
        /// One section per `UpdateSourceGroup`.
        case source

        public var id: String { rawValue }
    }
}
