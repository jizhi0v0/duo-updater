import Foundation

/// One update that did not happen: which app, which versions, at which stage,
/// and the error the row showed.
///
/// Kept on this Mac only, like every other event. DuoUpdater has no telemetry,
/// so a failure the user never reports is a failure nobody hears about; this is
/// what lets them report one later, after the red line on the row has been
/// cleared by a retry or a relaunch. Nothing reads it but the Diagnostics page
/// and `duo events`.
///
/// Pruned with the request log (``EventStore/retentionDays``), not kept forever
/// like ``InstallEvent``: a month-old failure is history, not something to report.
public struct InstallFailureEvent: Codable, Sendable, Hashable {

    /// Where in the update the failure surfaced.
    public enum Stage: String, Codable, Sendable {
        /// Download, verify or swap: the install DuoUpdater runs itself.
        case install
        /// The app's own updater was asked to apply a staged update and the
        /// app came back on the old build.
        case relaunch
    }

    /// Same identity rule as ``InstallEvent/appID``: the bundle's path.
    public let appID: String
    public let appName: String
    public let bundleID: String?
    public let fromVersion: String?
    public let toVersion: String?
    /// Update source that was being installed from ("Sparkle", "GitHub", …).
    public let sourceName: String?
    public let stage: Stage
    /// The error exactly as the row showed it.
    public let message: String

    public init(
        appID: String, appName: String, bundleID: String?,
        fromVersion: String?, toVersion: String?, sourceName: String?,
        stage: Stage, message: String
    ) {
        self.appID = appID
        self.appName = appName
        self.bundleID = bundleID
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.sourceName = sourceName
        self.stage = stage
        self.message = message
    }
}

/// The text a user pastes into an issue or an email about one failure.
///
/// Built here rather than in the app so `duo` can produce the same report. Only
/// what the failure needs: no list of installed apps, and the home directory is
/// abbreviated to `~` so the account name does not ride along in a path.
public enum InstallFailureReport {

    public static func text(
        for failure: InstallFailureEvent, at date: Date,
        duoUpdaterVersion: String,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String = InstallFailureReport.machineArchitecture,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        let versions = "\(failure.fromVersion ?? "?") → \(failure.toVersion ?? "?")"
        var lines = [
            "DuoUpdater: \(duoUpdaterVersion)",
            "macOS: \(osVersion) (\(architecture))",
            "App: \(failure.appName)" + (failure.bundleID.map { " (\($0))" } ?? ""),
            "Update: \(versions)" + (failure.sourceName.map { " via \($0)" } ?? ""),
            "Stage: \(failure.stage.rawValue)",
            "When: \(ISO8601DateFormatter().string(from: date))",
            "",
            "Error:",
            failure.message,
        ]
        if !homeDirectory.isEmpty {
            lines = lines.map { $0.replacingOccurrences(of: homeDirectory, with: "~") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Sending

    /// Where a report goes. Nothing is sent from here: these are only the
    /// addresses of the page and the message the user opens and sends themselves.
    public static let issueRepository = "jizhi0v0/duo-updater"
    public static let emailRecipient = "jizhiovo@gmail.com"

    /// Issue title and email subject.
    public static func title(for failure: InstallFailureEvent) -> String {
        "Update failed: \(failure.appName) \(failure.fromVersion ?? "?") → \(failure.toVersion ?? "?")"
    }

    /// The longest new-issue link this builds. GitHub answered 200 up to a URL of
    /// about 8,190 characters and 414 past it (measured 2026-10-15, signed in);
    /// this leaves room under that.
    public static let maxIssueURLLength = 7_500

    /// Appended when the body had to be cut to fit the link.
    public static let shortenedMarker = "\n\n[Shortened to fit the link.]"

    /// A new-issue page with the title and body filled in, for the user to read,
    /// edit and submit in their browser. A body too long for a link is cut from
    /// the end and marked, so the page still opens.
    public static func issueURL(title: String, body: String, maxLength: Int = maxIssueURLLength) -> URL {
        func url(_ body: String) -> URL {
            var components = URLComponents(string: "https://github.com/\(issueRepository)/issues/new")!
            components.queryItems = [URLQueryItem(name: "title", value: title),
                                     URLQueryItem(name: "body", value: body)]
            // URLComponents leaves a `+` in a query value as is, and GitHub reads a
            // bare `+` as a space, so encode it.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            return components.url!
        }
        let full = url(body)
        guard full.absoluteString.count > maxLength else { return full }
        // Longest prefix that fits: encoding makes the length per character vary.
        let characters = Array(body)
        var low = 0, high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if url(String(characters[..<mid]) + shortenedMarker).absoluteString.count <= maxLength {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return url(String(characters[..<low]) + shortenedMarker)
    }

    /// True for an error the user can fix on their own Mac — no disk space,
    /// Accessibility not granted, the App Store helper's hints, a nested app or
    /// VMPal VM still open — where a report
    /// would only tell the developer what the row already told the user.
    /// Matches the English text Core produces; the app's own translated copies
    /// of these are its to recognise.
    public static func isUserFixable(_ message: String) -> Bool {
        let fragments = [
            "not enough free space", "not enough disk space", "not enough space",
            AppStoreAXInstaller.AXError.notTrusted.errorDescription ?? "",
            MASInstaller.MASError.appStoreUpdatesHint,
            MASInstaller.MASError.helperApprovalHint,
            MASInstaller.MASError.helperRestartHint,
        ] + NestedAppRunningError.userFixableFragments
        return fragments.contains { !$0.isEmpty && message.localizedCaseInsensitiveContains($0) }
    }

    /// What "ask at most once" is keyed on: the app, the version it was going
    /// to, and the error. A new version or a different error asks again.
    public static func promptKey(for failure: InstallFailureEvent) -> String {
        [failure.bundleID ?? failure.appID, failure.toVersion ?? "", failure.message]
            .joined(separator: "\u{1F}")
    }

    /// `arm64` or `x86_64`: what `uname` reports to this process.
    public static var machineArchitecture: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
