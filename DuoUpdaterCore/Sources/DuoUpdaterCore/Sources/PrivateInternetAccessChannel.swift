import Foundation

enum PrivateInternetAccessChannel {
    static let bundleID = "com.privateinternetaccess.vpn"

    // The vendor's root-owned settings document is readable by the client.
    // Read only update settings. The account data lives in a separate file.
    private static let settingsURL = URL(
        fileURLWithPath: "/Library/Preferences/com.privateinternetaccess.vpn/settings.json")

    private struct Settings: Decodable {
        let updateChannel: String?
        let betaUpdateChannel: String?
        let offerBetaUpdates: Bool?
    }

    static func resolveCurrent() -> ResolvedChannel? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return resolve(settings: data)
    }

    static func resolve(settings data: Data) -> ResolvedChannel {
        guard let settings = try? JSONDecoder().decode(Settings.self, from: data),
              (settings.updateChannel ?? "release") == "release"
        else { return ResolvedChannel(channel: .undetermined) }
        guard settings.offerBetaUpdates == true else {
            return ResolvedChannel(channel: .stable)
        }
        return ResolvedChannel(channel: (settings.betaUpdateChannel ?? "beta") == "beta"
            ? .beta : .undetermined)
    }
}
