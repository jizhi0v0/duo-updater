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
        // Seven is a real version, not a runaway pattern: Warp stamps
        // `0.YYYY.MM.DD.HH.MM.NN` and the app reports every one of those segments.
        // Eight has never been seen on a healthy recipe.
        if components.count > 7 {
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
    /// - Parameter installedBuild: the bundle's `CFBundleVersion`.
    /// - Parameter installedVendorBuild: the vendor's own build id, where the
    ///   bundle keeps one (`InstalledApp.vendorBuildVersion`). Which of the two is
    ///   used is decided by `remote.buildNamespace`, never by which is non-nil:
    ///   handing this check a `CFBundleVersion` against a Mozilla `BuildID` does
    ///   not make it complain, it makes it answer "not behind" forever — the
    ///   silent-guard shape it was written to catch, arriving through its own
    ///   parameter list.
    public static func remoteBehindInstalled(
        remote: RemoteVersion, installedMarketing: String?, installedBuild: String?,
        installedVendorBuild: String? = nil
    ) -> String? {
        let remoteValue: String
        let installedValue: String
        let comparableBuild = remote.buildNamespace == .vendor
            ? installedVendorBuild : installedBuild
        if let rv = remote.version, let iv = comparableBuild {
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

    /// A recipe that only DETECTS, whose own response already names a
    /// downloadable artifact — "this one could probably install, and nobody has
    /// said why it doesn't".
    ///
    /// This exists because the sweep had no way to ask that question, and the gap
    /// is not hypothetical. Wispr Flow, AionUi and Devin sat detection-only for
    /// twelve days behind a stated blocker — "the vendor splits Intel and arm64
    /// and the install spec cannot choose" — that was false for all three: each
    /// probe URL was already the arm64 one. Nothing could have caught it. The
    /// registry-derived tests assert what a recipe DOES, and "no install spec" is
    /// a legal state indistinguishable from a deliberate one; `duo verify` swept
    /// them green every night because detecting was all they claimed to do; and
    /// none of the three was installed on any machine that would have shown a
    /// missing Update button. A false justification in a comment is invisible to
    /// every check that reads code.
    ///
    /// Advisory, and deliberately a *note* rather than a warning: several recipes
    /// are detection-only for reasons that are real and permanent — LibreWolf is
    /// ad-hoc signed, Alcove's public artifact is a stale trial build, Sogou's
    /// installer does far more than rotate a bundle — and this must never file an
    /// issue against them. It says "look once, then record the answer", and the
    /// place to record it is the recipe's own comment (plus the sweep baseline,
    /// which is what stops a settled answer from being asked again).
    ///
    /// False negatives are fine and false positives are not, so the match is
    /// narrow: an absolute `https` URL ending in an installer extension. The
    /// sample it reads is head-and-tail condensed, so an artifact buried in the
    /// middle of a long feed simply goes unreported rather than guessed at.
    public static func oneClickCandidate(
        recipe: VendorProbeRecipe, bodySample: String?
    ) -> String? {
        guard recipe.install == nil, let body = bodySample,
              let artifact = firstArtifactURL(in: body)
        else { return nil }
        return "detection-only, but the response names an installable artifact"
            + " (\(artifact)) — if that is deliberate, say so in the recipe"
    }

    /// First artifact URL in `text` that a one-click could plausibly fetch.
    ///
    /// Three rules, each of which a live sweep on 2026-08-29 had to teach this
    /// function — the first version got LibreWolf wrong and Sogou missing:
    ///
    ///  - **Source archives are not artifacts.** A forge's release JSON always
    ///    carries `tarball_url` / `zipball_url` pointing at `/archive/<tag>.tar.gz`,
    ///    and on LibreWolf's Codeberg release that is the FIRST match in the body —
    ///    so the note pointed at the project's source instead of the
    ///    `…-macos-arm64-package.dmg` sitting further down the same response.
    ///  - **`http` counts.** Sogou's update endpoint answers
    ///    `update_pack_url=http://pro.cdn.ime.sogou.com/autosetup….zip`, and an
    ///    https-only match reported nothing for the one recipe in the registry
    ///    whose vendor still serves plain http. `VendorProbeSource.preferHTTPS`
    ///    upgrades such a URL at install time, so refusing to see it here only
    ///    hides a real candidate.
    ///  - **Stop at quotes and brackets.** The character class excludes `"` and
    ///    `'` so a match cannot run out of one JSON string and across the next
    ///    keys — the failure that makes a "URL" hundreds of characters long.
    ///  - **The extension must END its path component.** The match is lazy, so
    ///    without the boundary `…/App-1.0.dmg.sig` yields `…/App-1.0.dmg` — a URL
    ///    this function never saw, invented by truncating a detached signature.
    ///    Feeds publish `.dmg.sig` and `.dmg.sha256sum` beside every build, and
    ///    the sample window can hold the sibling while missing the artifact. With
    ///    the boundary such a body reports nothing, which is the direction this
    ///    function is supposed to fail in.
    ///
    /// Two kinds of candidate stay invisible, both deliberately. A vendor that
    /// publishes only asset NAMES (Alcove lists `Alcove.dmg` with no URL) has
    /// nothing to match. And the text this reads is the head-and-tail condensed
    /// sample, so a long feed that buries the mac build in the middle goes
    /// unreported — measured on LibreWolf, whose Codeberg release is 21,300 bytes
    /// with the first `…-macos-arm64-package.dmg` at offset 11,217, past both
    /// ends of the window. Reading whole bodies here would mean carrying every
    /// swept feed in memory and through redaction to raise an advisory note.
    /// Silence costs a note nobody reads; a wrong URL costs somebody an
    /// investigation.
    static func firstArtifactURL(in text: String) -> String? {
        let pattern = #"https?://[^\s"'<>)\]}]+?\.(?:dmg|pkg|zip|tar\.gz)(?![A-Za-z0-9.])(?:\?[^\s"'<>)\]}]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let full = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: full) {
            guard let range = Range(match.range, in: text) else { continue }
            let candidate = String(text[range])
            if Self.sourceArchivePaths.contains(where: candidate.contains) { continue }
            return candidate
        }
        return nil
    }

    /// Path fragments that mean "this is the repository's source, not a build".
    /// Codeberg and GitHub both mint these for every release, whether or not the
    /// project ships a binary.
    private static let sourceArchivePaths = ["/archive/", "/tarball", "/zipball"]
}
