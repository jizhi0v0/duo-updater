import Foundation

/// The release channel an app is distributed on. Many apps ship the same product
/// on several parallel tracks (Stable, Beta, Dev, Canary, …). When two channels
/// share one `CFBundleIdentifier` (e.g. Android Studio's stable and Canary both
/// carry `com.google.android.studio`), keying an update purely by bundle id would
/// let a stable-channel recipe overwrite a Canary install. We detect the
/// installed app's channel and refuse any source whose channel doesn't match.
///
/// Detection is deliberately conservative: only a confident signal flips an app
/// off `.stable`. A false positive merely makes us skip the probe (the app shows
/// "unknown"), which is harmless; a false negative would let a cross-channel
/// package through, which is exactly what we must never do — so when unsure we
/// stay `.stable`, the channel every current recipe targets.
public enum ReleaseChannel: String, Sendable, Hashable, CaseIterable {
    case stable
    case beta
    case dev
    case canary
    case nightly
    case alpha
    /// Insiders / EAP / Tech-Preview / "Preview" builds.
    case preview
    /// Firefox/Thunderbird Extended Support Release — its own long-lived train,
    /// distinct from Stable. Shares a bundle id with Release/Beta, so it's
    /// detected from the `esr` suffix in the version string.
    case esr

    /// Detect the channel of an installed app from the strongest signals
    /// available, in priority order:
    ///   1. Chrome/Keystone's explicit `KSChannelID` plist key (the cleanest
    ///      signal — empty/`extended` mean stable; `beta`/`dev`/`canary` are
    ///      authoritative).
    ///   2. A channel suffix on the bundle id (`com.google.Chrome.canary`).
    ///   3. A standalone channel word in the display name ("Google Chrome Dev").
    ///   4. A Mozilla-style pre-release/esr suffix in the version string
    ///      ("152.0b6" → beta, "153.0a1" → nightly, "140.11.0esr" → esr) — the
    ///      ONLY signal that separates Firefox Release/Beta/ESR, which all share
    ///      `org.mozilla.firefox`.
    /// Nothing matched → `.stable`.
    public static func detect(
        name: String,
        bundleID: String?,
        keystoneChannel: String?,
        version: String? = nil
    ) -> ReleaseChannel {
        // 1. Keystone's own channel id — authoritative when present.
        if let ks = keystoneChannel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ks.isEmpty {
            switch ks.lowercased() {
            case "beta": return .beta
            case "dev": return .dev
            case "canary": return .canary
            // "extended" is a slower stable track; treat as stable.
            case "stable", "extended": return .stable
            default: break  // unknown id → fall through to name/bundle heuristics
            }
        }

        // 2. A channel suffix on the bundle id, separated by `.` or `-`, e.g.
        //    `com.google.Chrome.canary` or Warp's `dev.warp.Warp-Preview`.
        if let bundleID = bundleID?.lowercased() {
            for channel in nonStable
            where bundleID.hasSuffix("." + channel.rawValue)
               || bundleID.hasSuffix("-" + channel.rawValue) {
                return channel
            }
            if bundleID.hasSuffix(".insiders") || bundleID.hasSuffix("-insiders") {
                return .preview
            }
        }

        // 3. A standalone channel word in the display name. Word-boundary matched
        //    so "Codealpha.app" or a product literally named "Canary" code editor
        //    isn't swept up — only a separate token like "… Beta" / "… Canary".
        if let word = channelWord(in: name) { return word }

        // 4. A Mozilla-style pre-release/esr suffix in the version string. Tightly
        //    anchored (whole-string match) so an ordinary "1.2.3" stable version
        //    can never trip it — only the exact "<maj>.<min>b<n>" / "a<n>" / "esr"
        //    shapes Firefox & Thunderbird use.
        if let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
           !version.isEmpty {
            if version.lowercased().contains("esr") { return .esr }
            if fullyMatches(#"[0-9]+\.[0-9]+b[0-9]+"#, version) { return .beta }
            if fullyMatches(#"[0-9]+\.[0-9]+a[0-9]+"#, version) { return .nightly }
        }

        return .stable
    }

    /// True if `text` matches `pattern` in its entirety (anchored both ends).
    private static func fullyMatches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static let nonStable: [ReleaseChannel] =
        [.canary, .nightly, .preview, .beta, .alpha, .dev]

    /// Map a recognized standalone word in `text` to its channel, or nil.
    private static func channelWord(in text: String) -> ReleaseChannel? {
        // Order matters: more specific first (so "canary" wins before a generic).
        let table: [(word: String, channel: ReleaseChannel)] = [
            ("canary", .canary),
            ("nightly", .nightly),
            ("insiders", .preview),
            ("preview", .preview),
            ("beta", .beta),
            ("alpha", .alpha),
            ("dev", .dev),
        ]
        for (word, channel) in table where hasStandaloneWord(word, in: text) {
            return channel
        }
        return nil
    }

    /// True if `word` appears in `text` as a separate, case-insensitive token
    /// (bounded by non-alphanumeric characters or the string ends).
    private static func hasStandaloneWord(_ word: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9])\(word)(?![A-Za-z0-9])",
            options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
