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
public enum ReleaseChannel: String, Codable, Sendable, Hashable, CaseIterable {
    case stable
    case beta
    /// A "release candidate" train that is its own published channel, not a tag on
    /// a beta build: WeChat DevTools ships 稳定版 / 预发布版(RC) / 开发版(Nightly) as
    /// three parallel downloads, and the RC one is what its own `package.json`
    /// calls `versionType=1`. Modelled separately from `.beta` so the row label
    /// matches what the vendor calls the track the user actually installed.
    ///
    /// Deliberately absent from `nonStable` and `channelWord`: no vendor we cover
    /// spells this channel in a bundle id suffix or an app name, and "rc" is short
    /// enough that a generic word/suffix match would be a false-positive machine.
    /// It is only ever set by an explicit, app-scoped signal.
    case rc
    /// Discord's "Public Test Build" — a distinct public pre-release track that
    /// ships as its own bundle id (`com.hnc.DiscordPTB`). No `<sparkle:channel>`
    /// tag or version suffix carries it, so it's detected from the standalone
    /// "PTB" word in the app's display name ("Discord PTB").
    case ptb
    case dev
    case canary
    case nightly
    case alpha
    /// Insiders / EAP / Tech-Preview / "Preview" builds.
    case preview
    /// Tailscale's rolling pre-release train (`pkgs.tailscale.com/unstable`),
    /// distinct from its `rc` and stable tracks. Shares the macsys bundle id
    /// `io.tailscale.ipn.macsys` with Stable, so it can't be told apart by name,
    /// bundle suffix, or version shape — only by the app's own opt-in preference
    /// `UnstableUpdatesEnabled` (read via `TailscaleChannel`/`ChannelBinding`).
    /// Tailscale's even/odd-minor convention (stable 1.98.x, unstable 1.99.x)
    /// corroborates but isn't used as a detection signal.
    case unstable
    /// Firefox/Thunderbird Extended Support Release — its own long-lived train,
    /// distinct from Stable. Shares a bundle id with Release/Beta, so it's
    /// detected from the `esr` suffix in the version string.
    case esr

    /// Detect the channel of an installed app from the strongest signals
    /// available, in priority order:
    ///   0. Mozilla's per-channel `RemotingName` from `application.ini`
    ///      (`firefox-esr`, `thunderbird-beta`, …) — authoritative for
    ///      Firefox/Thunderbird, and the ONLY reliable signal for them: the
    ///      installed `CFBundleShortVersionString` DROPS the `b`/`esr` suffix
    ///      (`152.0b7`→`152.0`, `140.11.0esr`→`140.11.0`), and Beta/ESR can share
    ///      `org.mozilla.firefox` with Stable. Verified against real bundles
    ///      2026-06-04; the version-suffix heuristic below silently misclassified
    ///      them (an ESR install read as `.stable`, then offered the stable build).
    ///   1. Chrome/Keystone's explicit `KSChannelID` plist key (the cleanest
    ///      signal — empty/`extended` mean stable; `beta`/`dev`/`canary` are
    ///      authoritative).
    ///   2. A channel suffix on the bundle id (`com.google.Chrome.canary`).
    ///   3. A standalone channel word in the display name ("Google Chrome Dev").
    ///   4. A Mozilla-style pre-release suffix in the version string
    ///      ("153.0a1" → nightly) — survives only for Nightly; Beta/ESR strip it.
    /// Nothing matched → `.stable`.
    public static func detect(
        name: String,
        bundleID: String?,
        keystoneChannel: String?,
        version: String? = nil,
        mozillaRemotingName: String? = nil,
        bundleFileName: String? = nil
    ) -> ReleaseChannel {
        // 0. Mozilla `RemotingName` — authoritative for Firefox/Thunderbird.
        if let remoting = mozillaRemotingName?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !remoting.isEmpty,
           let channel = mozillaChannel(fromRemoting: remoting) {
            return channel
        }

        // 0.5 Android Studio — Stable, Canary, and Beta ALL ship one bundle id
        //     (`com.google.android.studio`) with the same `CFBundleName`
        //     ("Android Studio") and a marketing version truncated to "2026.1"
        //     (no channel suffix). The only on-disk channel signal is the app's
        //     BUNDLE FILENAME, which Homebrew's casks set per channel
        //     ("Android Studio Preview Canary" / "… Beta"; Stable stays
        //     "Android Studio"). It can't go through the display-name `channelWord`
        //     path below: the scanner's display name is `CFBundleName`
        //     ("Android Studio" — no word), and the filename also carries Google's
        //     umbrella "Preview" token, which `channelWord` ranks ABOVE "beta", so
        //     "… Preview Beta" would mis-resolve to `.preview`. Hence this scoped
        //     canary>beta>preview match. A bare "Android Studio Preview.app" (the
        //     raw DMG name — channel-ambiguous, could be either track) maps to
        //     `.preview`: no recipe targets it, so it's safely skipped rather than
        //     misdetected as Stable and offered a cross-channel Stable build.
        if bundleID == "com.google.android.studio",
           let fn = bundleFileName?.lowercased() {
            if fn.contains("canary") { return .canary }
            if fn.contains("beta") { return .beta }
            if fn.contains("preview") { return .preview }
            return .stable
        }

        // 0.6 DB Browser for SQLite — its nightly is the second app whose only
        //     on-disk channel signal is the BUNDLE FILENAME. It ships the stable
        //     bundle id (`net.sourceforge.sqlitebrowser`), a clean `CFBundleName`
        //     ("DB Browser for SQLite" — the scanner's display name, so
        //     `channelWord` sees no word), and a version that is not a channel
        //     token. Homebrew's `@nightly` cask installs it as
        //     "DB Browser for SQLite Nightly.app", alongside stable rather than
        //     over it (cask artifact read 2026-08-27).
        //
        //     Why this matters even though we can never UPDATE a nightly: the
        //     vendor hardcodes `CFBundleShortVersionString`/`CFBundleVersion` to
        //     `3.13.99` in the checked-in `src/app.plist`, and has since
        //     2023-11-11 ("Update version number to 3.13.99 (new nightly)"). The
        //     build date lives in a separate `BUILD_VERSION` compile define that
        //     never reaches the plist, which is why even Homebrew has to version
        //     that cask by the asset date. So a nightly's version never moves and
        //     no update can be offered for it — but STABLE is covered here with a
        //     one-click install spec, and a nightly install currently reads as
        //     `.stable`, which puts it in that recipe's reach. It is masked today
        //     only by the accident that the frozen `3.13.99` sorts above stable's
        //     `3.13.1`; the day stable ships 3.14.x the stable dmg starts being
        //     offered — and installed — over a nightly.
        //
        //     Unlike Android Studio above this does NOT return `.stable` in the
        //     negative case. Android Studio has to, because its other signals are
        //     actively misleading; DB Browser's are merely absent, so falling
        //     through keeps the normal path available to a track we have not
        //     characterised yet (the repo's `continuous` prereleases ship as
        //     `DB.Browser.for.SQLite-dev-<sha>.dmg` — unverified, see #94).
        if bundleID == "net.sourceforge.sqlitebrowser",
           bundleFileName?.lowercased().contains("nightly") == true {
            return .nightly
        }

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
            // JetBrains ships Early Access Program builds under a `-EAP` bundle-id
            // suffix (`com.jetbrains.intellij-EAP`) — its own pre-release track,
            // which we model as `.preview` (alongside Insiders/Tech-Preview). The
            // generic loop above misses it because the channel word is "preview",
            // not "eap".
            if bundleID.hasSuffix(".eap") || bundleID.hasSuffix("-eap") {
                return .preview
            }
            // Vivaldi Snapshot ships under `com.vivaldi.Vivaldi.snapshot` — a
            // pre-release track distinct from Stable. The channel word is "snapshot",
            // not "preview", so the generic loop above misses it.
            if bundleID.hasSuffix(".snapshot") || bundleID.hasSuffix("-snapshot") {
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
            // GitHub Desktop-style explicit `-betaN` suffix on a full semver
            // (`3.5.12-beta2`): same bundle id (`com.github.GitHubClient`) and app
            // name as Stable, so the version string is the ONLY channel signal.
            // Require the trailing digits to be the whole tail (`-beta[0-9]+$`) so
            // build-metadata shapes other apps use for non-channel builds —
            // `0.3.377-beta.1429+sha`, `0.1.1251-beta+sha` — don't trip it (verified
            // against the real installed bundles 2026-06-06).
            if fullyMatches(#"[0-9]+(\.[0-9]+)+-beta[0-9]+"#, version) { return .beta }

            // A prerelease WORD in the version's dash-separated tail — the only
            // local channel signal some nightly/snapshot builds have. Freelens
            // nightly (`2.0.0-0-nightly-2026-08-26`), VLC nightly (`4.0.0-dev`)
            // and the KeePassXC snapshot (`2.8.0-snapshot`) each ship the STABLE
            // bundle id, the stable app filename and a clean `CFBundleName`, so
            // steps 0–3 all see nothing and every one of them used to read as
            // `.stable` (measured off the real packages 2026-08-27).
            //
            // Anchored the same way the rules above are, and for the same reason:
            // the tail may contain only the word itself plus numeric components,
            // so build metadata that is NOT a channel keeps reading as stable —
            // `0.3.377-beta.1429+sha` (the shape the `-betaN` rule above already
            // guards), `2026.8.190756-latest`, `6.5.2-366`, `3.22.3+105`. The
            // word must also be a whole dash-delimited component, so
            // `1.2.3-development` and `4.0.0-devmate` do not trip it.
            //
            // `dev` is the risky one — short, and a common non-channel token —
            // which is why `ChannelProofRegistry.preReleaseTokens` deliberately
            // spells it `devedition` rather than matching it bare. It is safe
            // HERE only because this pattern is anchored to a whole version
            // string with a dotted-numeric prefix, not matched as a substring.
            //
            // Verified before landing: replayed over every version in
            // `verify/baseline.json` (272 covered recipes, swept 2026-08-27) and
            // over the short AND build version of all 205 apps installed on the
            // dev machine (406 strings). Zero of them change classification.
            let lowered = version.lowercased()
            for (word, channel) in versionTailChannelWords
            where fullyMatches(versionTailPattern(word), lowered) {
                return channel
            }
        }

        return .stable
    }

    /// Map a Mozilla `RemotingName` (from `application.ini`) to its channel.
    /// Real values seen 2026-06-04: `firefox` / `thunderbird` (stable),
    /// `firefox-esr`, `firefox-beta`, `firefox-dev` (Developer Edition),
    /// `firefox-nightly`, and the `thunderbird-*` equivalents. A present name with
    /// no recognized channel suffix is the release build → `.stable`. Returns nil
    /// only for an empty/garbage value so the caller falls through to other signals.
    private static func mozillaChannel(fromRemoting name: String) -> ReleaseChannel? {
        if name.hasSuffix("-esr") { return .esr }
        if name.hasSuffix("-beta") { return .beta }
        if name.hasSuffix("-nightly") { return .nightly }
        if name.hasSuffix("-dev") { return .dev }
        // A bare product name ("firefox"/"thunderbird"/"librewolf"/…) is stable.
        return name.allSatisfy { $0.isLetter || $0 == "." } ? .stable : nil
    }

    /// True if `text` matches `pattern` in its entirety (anchored both ends).
    private static func fullyMatches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$") else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Prerelease words recognized in a version string's dash-separated tail
    /// (step 4). `snapshot` maps to `.preview` to agree with the two places that
    /// already rule on that word — `channelWord`'s table and the
    /// `.snapshot`/`-snapshot` bundle-id suffix (Vivaldi Snapshot) — so a build
    /// cannot land on a different channel depending on which signal saw it first.
    /// Ordered most-specific-first like `channelWord` for the same reason.
    private static let versionTailChannelWords: [(word: String, channel: ReleaseChannel)] = [
        ("nightly", .nightly),
        ("snapshot", .preview),
        ("dev", .dev),
    ]

    /// Whole-string pattern for `<dotted numeric>[-<digits>…]-<word>[-<digits>…]`.
    private static func versionTailPattern(_ word: String) -> String {
        #"[0-9]+(\.[0-9]+)+(-[0-9]+)*-"# + word + #"(-[0-9]+)*"#
    }

    private static let nonStable: [ReleaseChannel] =
        [.canary, .nightly, .preview, .beta, .alpha, .dev, .ptb]

    /// Map a recognized standalone word in `text` to its channel, or nil.
    private static func channelWord(in text: String) -> ReleaseChannel? {
        // Order matters: more specific first (so "canary" wins before a generic).
        let table: [(word: String, channel: ReleaseChannel)] = [
            ("canary", .canary),
            ("nightly", .nightly),
            ("insiders", .preview),
            ("preview", .preview),
            ("snapshot", .preview),
            ("ptb", .ptb),
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
