import Foundation

/// A deferral reason in the viewer's language. Rows store the English text the
/// pass wrote (they are shared with `duo events` and the sanitized report's
/// counts), so the known ones are translated here, when shown. Anything else —
/// an installer's own error, a note already localized when it was written — is
/// shown as stored.
enum AutomaticUpdateReasonText {
    /// Whether `display` has a translation for this reason (for tests).
    static func isKnown(_ reason: String) -> Bool {
        fixed[reason] != nil || patterns.contains { text(in: reason, $0) != nil }
    }

    private static let patterns = [
        #"^The app is running, and its update has been waiting less than (\d+) minutes\.$"#,
        #"^The app is running, and it was quit for an update less than (\d+) minutes ago\.$"#,
        #"^The app did not quit, or updating it failed (\d+) times\. Waiting for a newer version\.$"#,
        #"^Updating it failed (\d+) times\. Waiting for a newer version\.$"#,
        #"^The app is running and busy \((.+)\)\.$"#,
        #"^Background processes are still running \((.+)\)\. Automatic updating is paused for this app\.$"#,
    ]

    static func display(_ reason: String) -> String {
        if let fixed = fixed[reason] { return fixed }
        if let n = number(in: reason, patterns[0]) {
            return String(localized: "The app is running, and its update has been waiting less than \(n) minutes.")
        }
        if let n = number(in: reason, patterns[1]) {
            return String(localized: "The app is running, and it was quit for an update less than \(n) minutes ago.")
        }
        if let n = number(in: reason, patterns[2]) {
            return String(localized: "The app did not quit, or updating it failed \(n) times. Waiting for a newer version.")
        }
        if let n = number(in: reason, patterns[3]) {
            return String(localized: "Updating it failed \(n) times. Waiting for a newer version.")
        }
        if let name = text(in: reason, patterns[4]) {
            return String(localized: "The app is running and busy (\(name)).")
        }
        if let names = text(in: reason, patterns[5]) {
            return String(localized: "Background processes are still running (\(names)). Automatic updating is paused for this app.")
        }
        return reason
    }

    private static let fixed: [String: String] = [
        "Excluded from automatic updates in Settings.":
            String(localized: "Excluded from automatic updates in Settings."),
        "Updating it needs administrator authorization.":
            String(localized: "Updating it needs administrator authorization."),
        "Requires an interactive or externally managed installation.":
            String(localized: "Requires an interactive or externally managed installation."),
        "Updating it failed in the last day. Trying again after that.":
            String(localized: "Updating it failed in the last day. Trying again after that."),
        "The app or one of its helpers is running.":
            String(localized: "The app or one of its helpers is running."),
        "The app did not quit, most likely to ask about unsaved work. It will not be asked again for this version.":
            String(localized: "The app did not quit, most likely to ask about unsaved work. It will not be asked again for this version."),
        "The app’s own updater has an update waiting for it to quit.":
            String(localized: "The app’s own updater has an update waiting for it to quit."),
        "The app did not quit, or updating it failed, in the last day. Trying again after that.":
            String(localized: "The app did not quit, or updating it failed, in the last day. Trying again after that."),
        "The app is running and in front.":
            String(localized: "The app is running and in front."),
        "The app is running and was used in the last hour.":
            String(localized: "The app is running and was used in the last hour."),
        "The app is running, and the Mac is in use.":
            String(localized: "The app is running, and the Mac is in use."),
        "The app is running a process of its own, such as a shell or a build.":
            String(localized: "The app is running a process of its own, such as a shell or a build."),
        "The app is running, and one of its helpers keeps running when it quits.":
            String(localized: "The app is running, and one of its helpers keeps running when it quits."),
        "Automatic updates are paused.":
            String(localized: "Automatic updates are paused."),
        "Automatic update deferred: running processes could not be checked completely.":
            String(localized: "Automatic update deferred: running processes could not be checked completely."),
        "Automatic update deferred: the app or one of its helpers is running.":
            String(localized: "Automatic update deferred: the app or one of its helpers is running."),
        "Automatic update requires an interactive installer.":
            String(localized: "Automatic update requires an interactive installer."),
        "Automatic update needs administrator authorization.":
            String(localized: "Automatic update needs administrator authorization."),
        "Automatic update deferred: a complete backup could not be created.":
            String(localized: "Automatic update deferred: a complete backup could not be created."),
        "Automatic update eligibility changed before installation.":
            String(localized: "Automatic update eligibility changed before installation."),
        "Automatic update deferred: another installation is already in progress.":
            String(localized: "Automatic update deferred: another installation is already in progress."),
        "Automatic update deferred: the app is running its own updater.":
            String(localized: "Automatic update deferred: the app is running its own updater."),
        "Automatic update deferred: the app’s own installer is active.":
            String(localized: "Automatic update deferred: the app’s own installer is active."),
    ]

    private static func text(in reason: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: reason, range: NSRange(reason.startIndex..., in: reason)),
              let range = Range(match.range(at: 1), in: reason) else { return nil }
        return String(reason[range])
    }

    private static func number(in reason: String, _ pattern: String) -> Int? {
        text(in: reason, pattern).flatMap(Int.init)
    }
}
