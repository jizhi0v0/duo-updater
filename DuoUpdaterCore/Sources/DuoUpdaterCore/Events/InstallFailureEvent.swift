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

    /// `arm64` or `x86_64`: what `uname` reports to this process.
    public static var machineArchitecture: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
