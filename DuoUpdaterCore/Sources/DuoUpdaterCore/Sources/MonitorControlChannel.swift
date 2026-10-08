import Foundation

/// MonitorControl (`app.monitorcontrol.MonitorControl`) — a channel-tag Sparkle
/// app with a beta switch and, so far, no UI for it.
///
/// What MonitorControl does (read from `MonitorControl/MonitorControl`,
/// `UpdaterDelegate.allowedChannels`): `UserDefaults.standard` `isBetaChannel`
/// true → `["beta"]`, otherwise no extra channel. `PrefKey.swift` says the key is
/// "not added to Settings yet". The app is not sandboxed, so the domain is
/// `~/Library/Preferences/app.monitorcontrol.MonitorControl.plist`.
///
/// The feed (`appcast2.xml`) carries no `<sparkle:channel>` item today, so this
/// changes no answer yet. It exists so the first tagged beta item reaches a copy
/// whose owner set the key, the way MonitorControl's own updater would — the
/// same shape as OBS, caught before it could bite.
///
/// Off or unreadable → nil: the build-inferred channel already keeps a stable
/// copy on the untagged items, which is all MonitorControl's own updater allows.
/// The beta tag is derived (`ReleaseChannel.beta.rawValue`), the spelling the
/// source uses, so no tag is declared by hand.
enum MonitorControlChannel {
    static let bundleID = "app.monitorcontrol.MonitorControl"

    static func resolve(isBetaChannel: Bool) -> ResolvedChannel? {
        isBetaChannel ? ResolvedChannel(channel: .beta) : nil
    }

    static func resolveCurrent() -> ResolvedChannel? {
        resolve(isBetaChannel: readIsBetaChannel())
    }

    static func readIsBetaChannel() -> Bool {
        CFPreferencesAppSynchronize(bundleID as CFString)
        guard let value = CFPreferencesCopyAppValue(
            "isBetaChannel" as CFString, bundleID as CFString
        ) else { return false }
        // `UserDefaults.bool(forKey:)`, which MonitorControl reads it with, also
        // accepts the strings "YES"/"true"/"1".
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["yes", "true", "1"].contains(text.lowercased()) }
        return false
    }
}
