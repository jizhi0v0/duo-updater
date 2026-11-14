import Foundation

/// Kuvo Code (`run.kuvo.code`) keeps stable and beta releases in its own Sparkle
/// feed. Its `updates.betas` UserDefaults Bool opts into the `beta` tag; before
/// the user chooses, `AppInfo.isBeta` defaults to whether the installed short
/// version contains `-beta`. See docs/app-audits/run-kuvo-code.md.
///
/// Explicit false is authoritative even on a beta build, so feed inference does
/// not keep offering betas after the user turns them off. The feed itself stays
/// the bundle's own: Kuvo Box is a separate product with a different bundle id.
enum KuvoCodeChannel {
    static let bundleID = "run.kuvo.code"
    static let preferenceKey = "updates.betas"

    static func resolve(includeBetas: Bool?, bundleStrings: [String: String] = [:]) -> ResolvedChannel? {
        if let includeBetas {
            return ResolvedChannel(channel: includeBetas ? .beta : .stable)
        }
        guard let version = bundleStrings["CFBundleShortVersionString"] else {
            // The preference watcher has no bundle. Preserve absence as nil so
            // an explicit false differs from the default-on beta's absent key.
            return nil
        }
        return ResolvedChannel(channel: version.contains("-beta") ? .beta : .stable)
    }

    static func resolveCurrent(bundleStrings: [String: String]) -> ResolvedChannel? {
        CFPreferencesAppSynchronize(bundleID as CFString)
        let includeBetas = CFPreferencesCopyAppValue(
            preferenceKey as CFString, bundleID as CFString) as? Bool
        return resolve(includeBetas: includeBetas, bundleStrings: bundleStrings)
    }
}
