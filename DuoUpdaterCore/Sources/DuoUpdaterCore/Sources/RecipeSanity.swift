import Foundation

/// Deterministic checks for the failure class a "did the probe return something?"
/// sweep is blind to: **the pattern matched, and the answer is still wrong.**
///
/// `ProbeFailure` covers the loud half — the endpoint moved, the regex matched
/// nothing. The quiet half is worse, because nothing fails: a recipe reads a
/// number in the wrong scheme, or off the wrong element, and the app confidently
/// reports "up to date" forever.
///
/// These live in the core, next to the recipes they judge, rather than in the
/// verification tool — a second copy of the rules in a CLI would drift from the
/// registry it is supposed to be guarding.
public enum RecipeSanity {

    /// Shape checks on an extracted version string. No baseline, no network, no
    /// installed copy required — safe to run anywhere, including CI.
    ///
    /// Tuned to stay quiet on healthy recipes: several capture a deliberate
    /// non-numeric prefix (Sublime's `Build 4200`), so the test is "contains no
    /// digits at all", not "doesn't start with a digit". A check that cries wolf
    /// on working recipes gets ignored, which costs more than it catches.
    public static func complaints(version: String, recipe: VendorProbeRecipe) -> [String] {
        var complaints: [String] = []

        if !version.contains(where: \.isNumber) {
            complaints.append("version contains no digits: '\(version)'")
        }
        if let first = version.first, !first.isLetter, !first.isNumber {
            complaints.append("version starts with punctuation: '\(version)'")
        }
        let components = version.split(separator: ".")
        if components.count > 6 {
            complaints.append("version has \(components.count) dot-components: '\(version)'")
        }
        if version.count > 40 {
            complaints.append("version is \(version.count) characters long")
        }
        if version.range(of: #"^(19|20)\d\d$"#, options: .regularExpression) != nil {
            complaints.append("version looks like a year: '\(version)'")
        }
        // Only meaningful for body-parsing recipes: a `.redirectFilename` recipe
        // reads the version out of a URL on purpose, so this would always fire.
        if case .responseBody = recipe.mode, recipe.url.absoluteString.contains(version) {
            complaints.append(
                "version appears verbatim in the request URL — the pattern may be "
                + "matching the URL rather than the response")
        }
        return complaints
    }

    /// The check that catches a probe reading a version in a *different scheme*
    /// than the app reports.
    ///
    /// Brave Beta shipped this for months. The appcast's `shortVersionString` is
    /// Brave's own `1.94.104.0`; the installed bundle reports a Chromium-prefixed
    /// `151.1.94.104`. That puts 1 against 151, the engine reads the *installed*
    /// copy as newer, and the row settles on "up to date" — permanently, silently.
    /// No pattern missed, no source errored, so every other check passes.
    ///
    /// The tell needs no baseline: a vendor's own feed should not be *behind* the
    /// copy you have installed. Advisory rather than fatal, because there are
    /// honest causes — Mozilla's `140.11.1esr` sorts below the suffix-less
    /// `140.11.1` the bundle reports, and running a hand-installed build ahead of
    /// the feed is legitimate.
    ///
    /// Comparison mirrors `UpdateChecker.evaluate` field for field — build
    /// against build when both sides have one (with the same JetBrains
    /// product-code normalization), marketing otherwise. Getting this wrong in
    /// either direction is fatal to the check's usefulness: comparing the fixed
    /// Brave recipe's *display* string against the bundle's marketing version
    /// re-flags the very recipe the fix repaired.
    public static func remoteBehindInstalled(
        remote: RemoteVersion, installedMarketing: String?, installedBuild: String?
    ) -> String? {
        let remoteValue: String
        let installedValue: String
        if let rv = remote.version, let iv = installedBuild {
            remoteValue = UpdateChecker.normalizedBuild(rv)
            installedValue = UpdateChecker.normalizedBuild(iv)
        } else if let rs = remote.shortVersion, let isv = installedMarketing {
            remoteValue = rs
            installedValue = isv
        } else {
            return nil
        }
        guard remoteValue != installedValue,
              VersionComparator.isNewer(installedValue, than: remoteValue)
        else { return nil }
        return "remote is BEHIND the installed copy (\(remoteValue) < \(installedValue)) — "
            + "the recipe may be reading a different version scheme than the app reports"
    }
}
