import Foundation

/// Reads which Mac App Store storefront the user is currently signed into, so we
/// can tell when an app simply isn't available in their region (and thus can't
/// be updated without switching Apple ID).
public enum AppStoreStorefront {

    /// ISO country code (lowercased, e.g. "us") of the signed-in App Store
    /// account, or nil if it can't be read or maps to an unknown storefront.
    ///
    /// `itunesstored` rewrites this preference whenever the account/region
    /// changes, so a fresh read reflects a region switch without restarting our
    /// app — we synchronize first to bypass any cached value.
    public static func currentCountry() -> String? {
        let domain = "com.apple.itunesstored" as CFString
        CFPreferencesAppSynchronize(domain)
        guard let raw = CFPreferencesCopyAppValue(
            "AccountsNotificationPlugin.ActiveStorefrontIdentifier" as CFString, domain
        ) as? String else { return nil }
        // The value looks like "143441-1,42"; the leading number is the
        // storefront id.
        let digits = raw.prefix { $0.isNumber }
        guard let id = Int(digits) else { return nil }
        return countryByStorefront[id]
    }

    /// Common iTunes storefront IDs → country code. Partial by design; an
    /// unmapped storefront just means we skip the region-mismatch hint rather
    /// than guess wrong.
    static let countryByStorefront: [Int: String] = [
        143441: "us", 143442: "fr", 143443: "de", 143444: "gb",
        143450: "it", 143452: "nl", 143454: "es", 143455: "ca",
        143460: "au", 143462: "jp", 143463: "hk", 143464: "sg",
        143465: "cn", 143466: "kr", 143468: "mx", 143469: "ru",
        143470: "tw"
    ]
}
