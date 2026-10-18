import Foundation

/// RuntimeViewer (`com.JH.RuntimeViewer`) — a channel-tag Sparkle app: one feed,
/// prereleases tagged `<sparkle:channel>beta`, stable items untagged.
///
/// Settled from source (MxIris-Reverse-Engineering/RuntimeViewer, `main`):
/// Settings ▸ Updates ▸ "Include pre-release versions" is
/// `Settings.Update.includePrereleases` (`RuntimeViewerSettings/Settings+Update.swift`),
/// default `false`, and `allowedChannels` maps it to `["beta"]` or `[]`, which
/// `UpdaterService` hands to Sparkle. `Settings` is a `Codable` saved as JSON by
/// `SettingsFileSystemStorage` to Application Support/`RuntimeViewer`/`settings.json`
/// (the app is not sandboxed), nested as `update.includePrereleases`. The file is
/// written only after some setting changes; until then the app runs on the
/// defaults.
///
/// Why a binding: a beta build carries no channel mark. `v3.0.0-beta.7` reads
/// `CFBundleShortVersionString` `3.0.0`, the same string the 3.0.0 release will
/// carry, so `ReleaseChannel.detect` calls every copy stable. The feed-side
/// inference in `SparkleAppcastSource` only finds a beta whose build is still
/// listed, and the vendor prunes old items.
///
/// Off, absent or unreadable resolves to `.stable`, authoritatively, the Mac Mouse
/// Fix shape: that is the app's own default, and with it Sparkle in the app
/// offers only the untagged items. A beta copy whose owner left the box unticked
/// is offered the next stable release and no further beta, as the app's own
/// updater would. No `detect()` signal is suppressed, because there is none.
///
/// The feed address, for copies that state none: everything before v2.0.0-RC.6
/// (the 1.x releases, the 2.0.0 betas up to RC.3) ships no Sparkle and no
/// `SUFeedURL`. Same bundle id and Team (D5Q73692VW) on every release from 1.1.0,
/// and builds only grow (1 → 12/13 → `YYYYMMDD.HH.MM`). It cannot be a
/// `SparkleFeedCatalog` fill-in, because this binding exists
/// (`noEntryIsAlsoManagedByAChannelBinding`), so it rides here, and only when
/// the bundle names no feed of its own. It is the address every later copy
/// declares, so it carries no channel decision: both tracks read the same feed
/// and the channel is the derived `beta` tag, which is why
/// `channelBindingsNeedingProof` has nothing to hold.
///
/// Not watched for changes (`ChannelBinding.preferenceWatchCandidates`): the same
/// directory holds the app's other state. A flip is picked up on the next scan or
/// on the app's own launch or quit.
enum RuntimeViewerChannel {
    static let bundleID = "com.JH.RuntimeViewer"

    static let feed = URL(string: "https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml")!

    /// What a copy from v2.0.0-RC.6 on declares, for `ChannelBinding.allResolutions`,
    /// which enumerates without a bundle.
    static let declaringBundleFeeds: [String: URL] = ["SUFeedURL": feed]

    static var settingsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RuntimeViewer", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    static func resolve(includePrereleases: Bool, bundleFeeds: [String: URL]) -> ResolvedChannel {
        ResolvedChannel(
            channel: includePrereleases ? .beta : .stable,
            feedOverride: bundleFeeds["SUFeedURL"] == nil ? feed : nil)
    }

    static func resolveCurrent(bundleFeeds: [String: URL]) -> ResolvedChannel {
        resolve(
            includePrereleases: includesPrereleases(settings: readSettings(at: settingsFileURL)),
            bundleFeeds: bundleFeeds)
    }

    /// The parsing half: `update.includePrereleases`, a JSON boolean. Anything
    /// else is false, which is what the app's own decoder falls back to.
    static func includesPrereleases(settings data: Data?) -> Bool {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let update = object["update"] as? [String: Any],
              let number = update["includePrereleases"] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return false }
        return number.boolValue
    }

    /// The settings file is a few kilobytes; the cap keeps a path that turns out
    /// to be something else from being read wholesale.
    static func readSettings(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count <= 1024 * 1024 else { return nil }
        return data
    }
}
