import Foundation

enum DockerDesktopChannel {
    static let bundleID = "com.docker.docker"

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/group.com.docker/settings-store.json")
    }

    private struct Settings: Decodable {
        let useNightlyBuildUpdates: Bool?

        enum CodingKeys: String, CodingKey {
            case useNightlyBuildUpdates = "UseNightlyBuildUpdates"
        }
    }

    /// Both tracks share `channelID=main` and the same per-user settings.
    /// The channel selects a vendor probe; it supplies no Sparkle feed.
    static func resolve(settingsURL: URL = Self.settingsURL) -> ResolvedChannel {
        let settings = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        return ResolvedChannel(
            channel: settings?.useNightlyBuildUpdates == true ? .nightly : .stable,
            feedOverride: nil)
    }
}
