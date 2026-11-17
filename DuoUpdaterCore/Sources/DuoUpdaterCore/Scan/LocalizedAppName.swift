import Foundation

/// The bundle's user-visible name, shared by scanning and App Store matching.
/// Match lprojs explicitly: Foundation maps legacy `zh_CN` to `zh-Hans`, while
/// a cached `localizedInfoDictionary` need not follow the caller's preferences.
enum LocalizedAppName {
    static func read(
        at path: URL, preferredLanguages: [String] = Locale.preferredLanguages,
        fallbackDisplayName: String? = nil
    ) -> String? {
        let wrapped = path.appendingPathComponent("WrappedBundle")
        let bundlePath = FileManager.default.fileExists(atPath: wrapped.path)
            ? wrapped.resolvingSymlinksInPath() : path
        guard let bundle = Bundle(url: bundlePath) else { return nil }
        let preferred = Bundle.preferredLocalizations(
            from: bundle.localizations, forPreferences: preferredLanguages)
        guard let localization = preferred.first,
              let url = bundle.url(forResource: "InfoPlist", withExtension: "strings",
                                   subdirectory: nil, localization: localization),
              let strings = NSDictionary(contentsOf: url) as? [String: Any]
        else { return nil }
        let name = AppScanner.firstUsableName(
            strings["CFBundleDisplayName"] as? String,
            fallbackDisplayName,
            strings["CFBundleName"] as? String)
        return name.isEmpty ? nil : name
    }
}
