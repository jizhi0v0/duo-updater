import Foundation

/// The signed package's channel, independent of the user's update subscription.
enum BuildReleaseChannel {
    static var isBeta: Bool { isBeta(info: Bundle.main.infoDictionary ?? [:]) }

    static func isBeta(info: [String: Any]) -> Bool {
        info["DuoReleaseChannel"] as? String == "beta"
    }

    static func permitsAutomaticUpdates(info: [String: Any], enabled: Bool) -> Bool {
        isBeta(info: info) && enabled
    }

    static func permitsAutomaticUpdates(enabled: Bool) -> Bool {
        permitsAutomaticUpdates(info: Bundle.main.infoDictionary ?? [:], enabled: enabled)
    }
}
