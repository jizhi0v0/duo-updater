import Foundation

/// A vendor's published end of an app: the day the vendor says it stops working,
/// and that announcement. Hand-curated in `Recipes/<family>.swift` (`sunsets`),
/// only from the vendor's own words — never inferred from a feed gone quiet.
///
/// Purely a notice: it changes nothing about checking or installing updates. It is
/// shown from the day it is recorded, and stays after the date, worded as ended.
public struct ProductSunset: Sendable, Equatable {
    /// `yyyy-MM-dd`: the first day the vendor says the app can no longer be used.
    public let endDate: String
    /// The vendor's announcement.
    public let announcement: URL

    public init(endDate: String, announcement: URL) {
        self.endDate = endDate
        self.announcement = announcement
    }

    public enum Phase: Sendable, Equatable {
        case upcoming
        case ended
    }

    /// `today` as `yyyy-MM-dd` (`ProductSunsetCatalog.today()`); ISO dates compare
    /// as strings. The end date itself is already `.ended`.
    public func phase(today: String) -> Phase {
        today < endDate ? .upcoming : .ended
    }
}

public enum ProductSunsetCatalog {
    /// bundleID (lowercased) → sunset.
    public static let sunsets: [String: ProductSunset] = Dictionary(
        uniqueKeysWithValues: AppRecipeIndex.merged(\.sunsets, into: "ProductSunsetCatalog.sunsets")
            .map { ($0.key.lowercased(), $0.value) })

    /// Case-insensitive on bundleID, like `ChangelogCatalog.url(forBundleID:)`.
    public static func sunset(forBundleID bundleID: String?) -> ProductSunset? {
        guard let bundleID else { return nil }
        return sunsets[bundleID.lowercased()]
    }

    /// Today as `yyyy-MM-dd` in the user's calendar day.
    public static func today(_ now: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
