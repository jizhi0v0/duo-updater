import Foundation

/// How Mac App Store updates are applied.
///
/// Both routes drive the store's own `storedownloadd`, so neither mixes
/// channels — they differ in dependency and bandwidth:
///   • `.full` — the `mas` CLI replays the store purchase and redownloads the
///     whole app. No extra permission, but needs `mas` (brew) and more traffic.
///   • `.incremental` — drives App Store.app's own Update button via the
///     Accessibility API, so the store fetches a delta. No `mas` needed and less
///     traffic, but requires an Accessibility grant (guided via PermissionFlow).
/// Default is `.full`: it asks for no sensitive permission up front.
public enum AppStoreUpdateStrategy: String, CaseIterable, Identifiable, Sendable {
    case full
    case incremental

    public var id: String { rawValue }

    /// What Settings offers. Only the predictable full-download path is listed:
    /// `.incremental` drives App Store's own UI and is still under evaluation, so it
    /// is reachable only by setting the default by hand —
    /// `defaults write com.duoupdater.app AppStoreUpdateStrategy incremental`.
    ///
    /// It is listed *while it is the active choice*, though, and that is the point of
    /// taking the current value: a picker whose selection is not among its own tags
    /// renders empty and silently rewrites the setting the moment it is touched. So
    /// whoever turned it on sees the truth in Settings and can turn it back off there,
    /// while everyone else is offered exactly one route.
    public static func visibleCases(current: Self) -> [Self] {
        var cases: [Self] = [.full]
        if !cases.contains(current) { cases.append(current) }
        return cases
    }

    /// Deliberately terse. These labels sit in a popup button whose slot is the
    /// settings row, and the sentence-length versions they replaced ("Full
    /// download (no extra permission)") could not be shown whole at the window's
    /// own minimum width in ANY language we ship — the popup truncated its own
    /// current selection, so the setting could not be read without opening the
    /// menu. Everything the parenthetical carried is in the description line under
    /// the picker, which has room for it.
    ///
    /// `.incremental` keeps its longer label. It is listed only for whoever turned it
    /// on by hand (see `visibleCases`), and naming the permission it needs is worth
    /// more to that reader than fitting the popup's narrowest slot.
    public var label: String {
        switch self {
        case .full:        return String(localized: "Full download")
        case .incremental: return String(localized: "Incremental (needs Accessibility)")
        }
    }
}

/// How to apply an update for a self-updating "vendor" app — the official-
/// website / self-baked-updater apps surfaced by `VendorProbeSource` (Office,
/// Teams, OneDrive, Edge, Chrome, VS Code, Tailscale, …). These all ship their
/// own updater (MAU, Keystone, a daemon, Sparkle), so we're only ever a
/// fallback — and how aggressively we step in is a user choice:
///   • `.deferWhenRunning` — respect the app's own updater. If it isn't running
///     we download and install over it in place (no live process to disturb);
///     if it IS running we don't swap the bundle under it — we open its own
///     update path instead (a deep link like Chrome's `chrome://settings/help`
///     when the recipe has one, otherwise just bring the app forward so its
///     built-in updater takes over).
///   • `.alwaysOverwrite` — always download and replace in place regardless of
///     whether it's running, then surface a Restart/Relaunch prompt.
///
/// Default `.alwaysOverwrite`, changed from `.deferWhenRunning`. Deferring reads
/// as the cautious choice, but the apps it applies to — Chrome, VS Code, Cursor,
/// the Electron ones — are the apps that are *always* running, so deferring meant
/// the common case never installed anything: the row offered "Open" forever and
/// the tool only ever reported. The reasons it is safe to overwrite instead:
///   • anything with sibling components to install (daemons, launch items) ships
///     a `.pkg` — Tailscale, all of Office — and a pkg goes to the system
///     installer, which places those components properly. Bundle replacement
///     only ever happens for dmg/zip apps, where the bundle *is* the product.
///   • the artifact is the vendor's own official installer, so this does what a
///     user doing it by hand would do.
///   • the quit is graceful — `terminate()`, never a force-kill, so save prompts
///     still run — and auto-restart is on by default, so in the normal case the
///     window where a live process runs beside a replaced bundle is short.
///     Be precise about the failure case though: the restart happens *after* the
///     swap, so an app that refuses to quit is left running old code beside a new
///     bundle until the user relaunches it. Nothing is lost and the row keeps a
///     Restart button, but the install is not rolled back and never was — there
///     is no pre-install quit to abort.
/// `.deferWhenRunning` remains for anyone who would rather we never touch a
/// running app.
public enum VendorInstallPolicy: String, CaseIterable, Identifiable, Sendable {
    case deferWhenRunning
    case alwaysOverwrite

    public var id: String { rawValue }

    /// Terse for the same reason as `AppStoreUpdateStrategy.label`. What each one
    /// does is the description line Settings shows under the picker for the
    /// selected option.
    public var label: String {
        switch self {
        case .deferWhenRunning: return String(localized: "Defer while running")
        case .alwaysOverwrite:  return String(localized: "Always replace")
        }
    }
}

/// Whether the checker may ask the sources below Homebrew about a brew-installed
/// copy once brew has said it has no newer version, or its readable third-party
/// cask uses `:latest` without a comparable version. A brew update always wins.
///
/// Without a per-copy choice, an official cask marked `auto_updates` checks
/// other sources even with the Settings default off: the cask itself says the
/// app's own updater is its channel, and its version only records where brew
/// started (Postman's cask at 12.12.6 while the app had moved to 12.12.7). A
/// third-party tap's `auto_updates` does not count: such a tap often packages
/// its own build. The Settings default turns this on for every brew copy.
///
/// A per-copy choice beats the Settings default in both directions, so a copy
/// the user marked "Homebrew only" stays that way when the default is turned
/// on — the case for a cask that ships its own build (SourceGit's cask is a
/// signed rebuild from a separate repo) or a different edition under the same
/// bundle id (qBittorrent Enhanced Edition).
public struct BrewFallbackPolicy: Sendable, Equatable {
    /// One copy's own choice, if it has one.
    public enum Override: String, Sendable, Equatable, CaseIterable {
        case checkOtherSources
        case homebrewOnly
    }

    /// The Settings default for copies without their own choice.
    public var checksOtherSourcesByDefault: Bool
    /// Copies (`InstallPreferenceKey.key(for:)`) that check other sources.
    public var allowedKeys: Set<String>
    /// Copies that never check other sources.
    public var blockedKeys: Set<String>
    /// An install from another source refused because the build is signed by
    /// someone else (`isSigningRefusal`).
    public struct SigningRefusal: Sendable, Equatable {
        /// The installed copy's `signingStamp(team:)` at the time.
        public var team: String
        /// The refused release's marketing version and build ("" when the
        /// source gave none), compared like the checker compares a release.
        public var version: String
        public var build: String
        public init(team: String, version: String, build: String = "") {
            self.team = team
            self.version = version
            self.build = build
        }
        /// The release a source offered and the install refused.
        public init(team: String, refusing remote: RemoteVersion?) {
            self.init(team: team, version: remote?.shortVersion ?? "", build: remote?.version ?? "")
        }
    }

    /// Copies whose update from another source was refused for its signature.
    /// While the copy still carries that stamp, that release and older ones are
    /// skipped and the copy stays on Homebrew; a newer release is offered again
    /// (a vendor's one-off signing mistake does not hold the copy forever), and
    /// a copy replaced by a differently signed build is checked again. Not a
    /// user choice: any choice in the row menu clears it.
    public var signingRefusals: [String: SigningRefusal]

    public init(
        checksOtherSourcesByDefault: Bool = false,
        allowedKeys: Set<String> = [],
        blockedKeys: Set<String> = [],
        signingRefusals: [String: SigningRefusal] = [:]
    ) {
        self.checksOtherSourcesByDefault = checksOtherSourcesByDefault
        self.allowedKeys = allowedKeys
        self.blockedKeys = blockedKeys
        self.signingRefusals = signingRefusals
    }

    /// Read from the keys the app writes, so the CLI follows the same choices.
    public init(defaults: UserDefaults) {
        self.init(
            checksOtherSourcesByDefault: defaults.bool(forKey: UpdateSettings.brewFallbackByDefaultKey),
            allowedKeys: Set(defaults.stringArray(forKey: UpdateSettings.brewFallbackKeysKey) ?? []),
            blockedKeys: Set(defaults.stringArray(forKey: UpdateSettings.brewFallbackBlockedKeysKey) ?? []),
            signingRefusals: Self.decodeRefusals(
                defaults.dictionary(forKey: UpdateSettings.brewFallbackSigningRefusalsKey)))
    }

    /// The defaults form of `signingRefusals`: copy key → {team, version}.
    public static func encodeRefusals(_ refusals: [String: SigningRefusal]) -> [String: [String: String]] {
        refusals.mapValues { ["team": $0.team, "version": $0.version, "build": $0.build] }
    }

    /// Write `signingRefusals` where `init(defaults:)` reads it, for the app
    /// and `duo install` alike.
    public static func storeRefusals(_ refusals: [String: SigningRefusal], in defaults: UserDefaults) {
        defaults.set(encodeRefusals(refusals), forKey: UpdateSettings.brewFallbackSigningRefusalsKey)
    }

    static func decodeRefusals(_ stored: [String: Any]?) -> [String: SigningRefusal] {
        (stored ?? [:]).compactMapValues { value in
            guard let fields = value as? [String: String],
                  let team = fields["team"], let version = fields["version"] else { return nil }
            return SigningRefusal(team: team, version: version, build: fields["build"] ?? "")
        }
    }

    /// Record one copy's own choice; nil returns it to the default. Any choice
    /// also forgets a recorded signing refusal, so the row menu is the way to
    /// have that copy checked against other sources again.
    public mutating func set(_ choice: Override?, for key: String) {
        signingRefusals.removeValue(forKey: key)
        if choice == .checkOtherSources { allowedKeys.insert(key) } else { allowedKeys.remove(key) }
        if choice == .homebrewOnly { blockedKeys.insert(key) } else { blockedKeys.remove(key) }
    }

    /// Carry one copy's choice and refusal to its new key (a bundle renamed in
    /// place), as `Preferences.migrateInstallPreferences` does for the rest.
    public mutating func migrate(from oldKey: String, to newKey: String) {
        guard oldKey != newKey else { return }
        if allowedKeys.remove(oldKey) != nil { allowedKeys.insert(newKey) }
        if blockedKeys.remove(oldKey) != nil { blockedKeys.insert(newKey) }
        if let refusal = signingRefusals.removeValue(forKey: oldKey) { signingRefusals[newKey] = refusal }
    }

    /// What a signing refusal is recorded against: the installed copy's Team ID,
    /// or "" for a copy without one (ad-hoc, self-signed or unreadable).
    public static func signingStamp(team: String?) -> String { team ?? "" }

    /// The installed copy's stamp, read off the cooperative pool (a Security call).
    public static func signingStamp(of app: InstalledApp) async -> String {
        let path = app.path
        return signingStamp(team: await offCooperativePool { try? SignatureVerifier.teamIdentifier(at: path) })
    }

    /// Whether an install from another source was refused because the download
    /// is not signed by whoever signed the installed copy — the shape of a cask
    /// that ships its own build (a re-signed rebuild, another edition). Those
    /// refusals repeat on every attempt, unlike a failed download or checksum.
    public static func isSigningRefusal(_ error: any Error) -> Bool {
        guard let error = error as? SignatureVerifier.VerifyError else { return false }
        switch error {
        case .noTeamIdentifier, .teamIdentifierMismatch, .teamIdentifierAppeared,
             .notAdHocSigned, .signingKindChanged, .designatedRequirementNotSatisfied,
             .bundleIdentifierMismatch:
            return true
        default:
            return false
        }
    }

    /// Whether this install was a brew copy taking another source's update —
    /// the only installs a signing refusal is recorded for.
    public static func isFallbackInstall(_ result: UpdateResult) -> Bool {
        result.homebrewSourceIdentifier != nil && result.remote != nil
            && result.remote?.sourceName != "Homebrew"
    }

    /// Whether a recorded refusal still covers what a source offers now: the
    /// same release or an older one. A newer release gets another try — a newer
    /// marketing version, or the same one with a newer build (a vendor that
    /// fixes its signing in a rebuild, an app whose marketing string never moves).
    /// What cannot be told apart stays covered.
    static func refusalCovers(_ refusal: SigningRefusal, _ remote: RemoteVersion) -> Bool {
        let short = remote.shortVersion ?? "", build = remote.version ?? ""
        if !short.isEmpty, !refusal.version.isEmpty {
            switch VersionComparator.compare(short, refusal.version) {
            case .orderedDescending: return false
            case .orderedAscending: return true
            case .orderedSame: break
            }
        }
        if !build.isEmpty, !refusal.build.isEmpty {
            return VersionComparator.compare(build, refusal.build) != .orderedDescending
        }
        if short.isEmpty || refusal.version.isEmpty {
            // One side spells only a build: compare what each side has.
            let offered = short.isEmpty ? build : short
            let refused = refusal.version.isEmpty ? refusal.build : refusal.version
            guard !offered.isEmpty, !refused.isEmpty else { return true }
            return VersionComparator.compare(offered, refused) != .orderedDescending
        }
        return true
    }

    /// Whether `remote` is visibly signed another way than the installed copy,
    /// before anything is downloaded: the copy has a Team ID and the rule says
    /// the release has none. Gate 3 would refuse it at install anyway.
    static func signingDiffers(installedTeam: String?, remote: RemoteVersion) -> Bool {
        installedTeam != nil && remote.installTrust != .developerID
    }

    public func override(for key: String) -> Override? {
        // Blocked first: if both sets ever hold a key, the safer answer wins.
        if blockedKeys.contains(key) { return .homebrewOnly }
        if allowedKeys.contains(key) { return .checkOtherSources }
        return nil
    }

    /// Whether a row-menu choice does anything. Re-choosing the current option
    /// still counts while a signing refusal holds the copy: it is how the user
    /// asks for other sources again. The stored record decides as well as the
    /// row's flag, because a refusal just recorded (by the app or `duo install`)
    /// reaches the row only with its next check.
    public func takesChoice(_ choice: Override?, for key: String, rowWithheld: Bool) -> Bool {
        choice != override(for: key) || rowWithheld || signingRefusals[key] != nil
    }

    /// What a copy without its own choice does: `selfUpdating` is an official
    /// cask marked `auto_updates` (`UpdateResult.homebrewSelfUpdating`).
    public func checksOtherSourcesByDefault(selfUpdating: Bool) -> Bool {
        checksOtherSourcesByDefault || selfUpdating
    }

    public func checksOtherSources(_ key: String, selfUpdating: Bool) -> Bool {
        switch override(for: key) {
        case .checkOtherSources: return true
        case .homebrewOnly: return false
        case nil: return checksOtherSourcesByDefault(selfUpdating: selfUpdating)
        }
    }
}

/// The user preference values `UpdatePolicy` consults when deciding how an
/// update may be installed. A plain value so the policy stays pure — the
/// `@MainActor` app reads these out of its settings object and hands them in;
/// a CLI reads the same UserDefaults keys and builds the same value, so both
/// share one set of rules.
public struct UpdateSettings: Sendable {
    /// Per-install-path opt-in after no brew update or a readable `:latest` cask.
    public static let brewFallbackKeysKey = "BrewFallbackKeys"
    /// Per-install-path "Homebrew only", which holds even when the default is on.
    public static let brewFallbackBlockedKeysKey = "BrewFallbackBlockedKeys"
    /// The Settings default for brew copies without their own choice. Absent is off.
    public static let brewFallbackByDefaultKey = "BrewFallbackByDefault"
    /// Copies kept on Homebrew after another source's build was refused for its
    /// signature: copy key → {team, version} (`BrewFallbackPolicy.encodeRefusals`).
    public static let brewFallbackSigningRefusalsKey = "BrewFallbackSigningRefusals"
    /// Which route to use for Mac App Store updates. See `AppStoreUpdateStrategy`.
    public var appStoreUpdateStrategy: AppStoreUpdateStrategy
    /// How to apply self-updating vendor-app updates. See `VendorInstallPolicy`.
    public var vendorInstallPolicy: VendorInstallPolicy
    /// Installs whose administrator prompt the user dismissed, keyed by
    /// `InstallPreferenceKey.key(for:)` — an install PATH, never a bundle id.
    /// See `ElevationRules` for why this is remembered at all.
    public var declinedElevationKeys: Set<String>
    /// Whether an ad-hoc signed app may be updated in one click on the strength of
    /// the file hash GitHub publishes alone — see `InstallTrust.publishedDigestOnly`.
    /// Off unless the user turns it on: a hash proves the bytes are the ones on the
    /// release page, not who put them there.
    public var allowsDigestOnlyInstalls: Bool

    /// The UserDefaults key the app persists `appStoreUpdateStrategy` under.
    /// Shared here (not in the app) so a CLI reading the same suite can never
    /// drift onto a differently-named key.
    public static let appStoreUpdateStrategyKey = "AppStoreUpdateStrategy"
    /// The UserDefaults key the app persists `vendorInstallPolicy` under.
    public static let vendorInstallPolicyKey = "VendorInstallPolicy"
    /// The UserDefaults key the app persists `TestFlightDetection` under. Shared
    /// for the same reason as the two above, and with one more: the CLI reads
    /// TestFlight's store too, so a drifted name would leave "off" true in the
    /// menu bar and false for `duo check` on the same Mac.
    ///
    /// No shared default beside it on purpose — the value is written on the first
    /// launch that finds the key absent (`TestFlightDetection.firstRunDefault`),
    /// so a reader that finds nothing is reading a Mac the app has not started on
    /// yet. `TestFlightDetection.off` is the right answer for such a reader.
    public static let testFlightDetectionKey = "TestFlightDetection"

    /// What `vendorInstallPolicy` resolves to when the key is absent.
    ///
    /// Shared for the same reason the key names are: the app and the CLI each
    /// resolve this independently, and a default that drifted between them would
    /// mean `duo install` and the menu bar routing the same app differently — a
    /// difference nothing would report, since both answers are individually valid.
    public static let vendorInstallPolicyDefault: VendorInstallPolicy = .alwaysOverwrite

    /// Where the ignore list and the per-app skipped version live. Shared
    /// because `duo ignore` and `duo skip` **write** these: a name that drifted
    /// would not read as empty, it would silently create a second, invisible
    /// ignore list while the app kept using the first.
    public static let ignoredKeysKey = "IgnoredApps"
    public static let skippedVersionsKey = "SkippedVersions"
    /// Where the declined administrator prompts live. Shared for the same reason
    /// as the two above: the CLI resolves this independently, and a drifted name
    /// would not read as empty — it would silently keep offering a one-click the
    /// user already refused in the menu bar.
    public static let declinedElevationKeysKey = "DeclinedElevatedInstalls"
    /// Where `allowsDigestOnlyInstalls` lives. Shared for the reason the policy
    /// keys above are: `duo install` must not one-click what the menu bar would
    /// refuse, or the reverse. Absent reads as false in both.
    public static let allowsDigestOnlyInstallsKey = "AllowDigestOnlyInstalls"

    /// Where rollback backups are kept, and how they are packed. See
    /// ``BackupDestination`` and ``BundleArchive/Compression``.
    ///
    /// Shared for a sharper reason than the keys above. `duo backups` reads and
    /// writes the same store the menu bar does, so a drifted name here would not
    /// read as "unset and therefore local" in any visible way — the CLI would
    /// keep writing backups to the boot volume while the app wrote them to the
    /// external disk, each product listing a store the other cannot see. The
    /// first symptom would be a rollback offered in one place and missing in the
    /// other, long after the divergence started.
    /// Renamed from `BackupDestinationPath`, which stored the folder the user
    /// picked rather than the store directory inside it. Any value under the old
    /// name points at somewhere that belongs to the user, so it is ignored
    /// outright instead of migrated — re-picking is one click, and silently
    /// repointing a store at someone's Documents folder is not a risk worth
    /// taking to save it.
    public static let backupDestinationPathKey = "BackupDestinationFolder"
    public static let backupDestinationIdentityKey = "BackupDestinationIdentity"
    public static let backupDestinationVolumeNameKey = "BackupDestinationVolumeName"
    /// Whether backups currently go to that folder.
    ///
    /// Separate from the folder itself so switching back to "on this Mac" is a
    /// switch and not an erasure: the disk stays remembered, and turning it on
    /// again does not mean finding it in a file picker a second time.
    public static let backupDestinationEnabledKey = "BackupsGoToAnotherDisk"
    /// Every disk that has ever been adopted as a destination, so the settings
    /// page can offer them instead of sending the user back through a file
    /// picker for a disk they already set up.
    ///
    /// A list rather than one remembered folder because switching between two
    /// disks stopped being an odd thing to do the moment backups became
    /// readable from all of them at once: without the list, the second disk is
    /// reachable only by re-picking it, and the picker cannot name a disk it has
    /// no record of while that disk is unplugged.
    public static let backupDestinationHistoryKey = "BackupDestinationHistory"
    public static let backupCompressionKey = "BackupCompression"

    /// What the compression setting resolves to when its key is absent.
    /// Shared for the same reason ``vendorInstallPolicyDefault`` is: the app and
    /// the CLI resolve it independently, and a default that drifted would mean
    /// the same update archived two different ways depending on who ran it.
    public static let backupCompressionDefault: BundleArchive.Compression = .fast

    public static let keepBackupsKey = "KeepBackups"
    /// Set by the welcome window's Get Started button.
    public static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// Whether to take a rollback point before each update, as the app and the
    /// CLI both read it.
    ///
    /// Off unless chosen: a new user opts in from the welcome window. A Mac
    /// that finished onboarding before that choice existed never saw it, and
    /// has had backups on all along — so an absent key reads as on there, and
    /// as off everywhere else. The app writes the answer on launch, which pins
    /// it; this rule is for the CLI run before that, and for the first launch.
    public static func keepBackups(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: keepBackupsKey) as? Bool
            ?? defaults.bool(forKey: hasCompletedOnboardingKey)
    }

    public init(
        appStoreUpdateStrategy: AppStoreUpdateStrategy,
        vendorInstallPolicy: VendorInstallPolicy,
        declinedElevationKeys: Set<String> = [],
        allowsDigestOnlyInstalls: Bool = false
    ) {
        self.appStoreUpdateStrategy = appStoreUpdateStrategy
        self.vendorInstallPolicy = vendorInstallPolicy
        self.declinedElevationKeys = declinedElevationKeys
        self.allowsDigestOnlyInstalls = allowsDigestOnlyInstalls
    }
}

/// The stable per-install identity for an app's preferences (ignore, skip,
/// notification baseline). Keys on the on-disk path — exactly like
/// `InstalledApp.id`, and deliberately NOT the bundle id: several installed
/// apps can legitimately share one (the JetBrains-Toolbox Android Studio
/// channels, Thunderbird stable/esr, …), and a bundle-id key collapses them
/// so ignoring/skipping one applied to every copy. Kept separate from
/// `BackupStore.key`: rollback storage has its own compatibility and
/// collision-avoidance rules, while preferences must preserve old ignore/skip
/// identities exactly.
///
/// Not named `PreferenceKey`: SwiftUI exports a protocol under that name and
/// this module is imported by the views, so the bare name would shadow it in
/// unqualified lookup in every file that imports both.
public enum InstallPreferenceKey {
    public static func key(for app: InstalledApp) -> String {
        preferenceKey(app.path.path)
    }

    /// The previous bundle-id-preferred identity. Entries written before the
    /// switch to per-path keys live under this; we still honour them on read so
    /// an existing ignore/skip never silently resurfaces, and migrate them to the
    /// new key the next time the app is toggled.
    public static func legacyKey(for app: InstalledApp) -> String {
        preferenceKey(app.bundleID ?? app.path.path)
    }

    /// Sanitise an install identity down to characters that are safe as a
    /// UserDefaults key: letters, digits, `.`, `-`, `_`; everything else
    /// (slashes, spaces, colons) becomes `_`. A key that is empty or only dots
    /// — a path like `/.` — would otherwise collide with the "unset" sentinel,
    /// so it falls back to the literal `"app"`.
    public static func preferenceKey(_ raw: String) -> String {
        let safe = raw.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == "." || c == "-" || c == "_" { return c }
            return "_"
        }
        let joined = String(safe)
        return joined.isEmpty || joined.allSatisfy { $0 == "." } ? "app" : joined
    }
}

/// Whether the user has told us to stop showing an update. Shared because the
/// legacy-key fallbacks are not symmetric between the two rules, and a
/// re-derived copy gets them subtly wrong: skip falls back to the legacy key
/// only when the per-path key is **absent**, so an app skipped at 2.0 and then
/// skipped again at 3.0 must not stay hidden via a stale legacy entry — while
/// ignore matches either key, so un-ignoring has to clear both.
public enum VisibilityRules {

    /// Whether this app is worth spending a network check on.
    ///
    /// Ignoring an app means "stop telling me about this one" — nothing will be
    /// said about the answer however it comes back, so the request is pure cost.
    /// On an unauthenticated GitHub budget (60 requests an hour) it is cost that
    /// pushes apps the user *does* watch out of the hour.
    ///
    /// A **skipped version** is deliberately not covered here and must keep being
    /// checked: whether the version being offered is still the one the user
    /// skipped is knowable only by asking. Skipping 3.3 hides 3.3, not 3.4.
    public static func deservesCheck(_ app: InstalledApp, ignoredKeys: Set<String>) -> Bool {
        !isIgnored(app, ignoredKeys: ignoredKeys)
    }

    public static func isIgnored(_ app: InstalledApp, ignoredKeys: Set<String>) -> Bool {
        ignoredKeys.contains(InstallPreferenceKey.key(for: app))
            || ignoredKeys.contains(InstallPreferenceKey.legacyKey(for: app))
    }

    /// How a skipped version is written down.
    ///
    /// Carries the build when there is one — `"1.0 (130)"` — because the
    /// marketing string alone cannot say WHICH build was skipped. Amp ships every
    /// build as "1.0", so a bare "1.0" recorded once matched every release after
    /// it and silenced the app permanently, persisted across restarts.
    public static func skipKey(_ version: VersionSide) -> String {
        version.text(withBuild: true)
    }

    /// Whether the user has skipped exactly this version.
    ///
    /// **Legacy entries are honoured only when there is no build to disambiguate.**
    /// A value written before `skipKey` carried a build is a bare marketing
    /// string; for an app that has a `CFBundleVersion` that string cannot identify
    /// a build, and honouring it is precisely the permanent-silencing bug. So such
    /// an entry stops matching once the app has a build — the user sees that one
    /// version offered again and their next skip rewrites the entry in the current
    /// format. For an app with no build at all the marketing string IS the whole
    /// identity, and the legacy entry keeps working unchanged.
    public static func isVersionSkipped(
        _ app: InstalledApp, version: VersionSide?, skippedVersions: [String: String]
    ) -> Bool {
        guard let version, !version.isEmpty else { return false }
        guard let skipped = skippedVersions[InstallPreferenceKey.key(for: app)]
            ?? skippedVersions[InstallPreferenceKey.legacyKey(for: app)]
        else { return false }
        if skipped == skipKey(version) { return true }
        guard version.build == nil else { return false }
        return skipped == version.marketing
    }
}

/// Whether the user has refused to let us install into a location we cannot
/// write, and so should stop being offered a one-click Update for it.
///
/// This is remembered rather than re-asked because the alternative is worse in
/// both directions: an app in `/Library/Input Methods` or an admin-owned
/// `/Applications` needs a password on *every* install, so a row that keeps its
/// Update button turns one refusal into a password panel on every future
/// release — while pre-emptively demoting such a row to "Open" would deny the
/// user a working one-click they never said no to. Hence a tri-state: never
/// asked keeps Update, declined falls back to Open, and the user can retire the
/// refusal from the row's context menu.
///
/// Keyed exactly like ignore, and matched against **either** key form for the
/// same reason: several installed apps legitimately share a bundle id (the
/// Toolbox-managed Android Studio channels, Thunderbird stable/esr), so a
/// bundle-id key would silence a channel the user never declined. Clearing must
/// therefore drop both forms — see `Preferences.setElevationDeclined`.
public enum ElevationRules {

    public static func isDeclined(_ app: InstalledApp, declinedKeys: Set<String>) -> Bool {
        declinedKeys.contains(InstallPreferenceKey.key(for: app))
            || declinedKeys.contains(InstallPreferenceKey.legacyKey(for: app))
    }
}
