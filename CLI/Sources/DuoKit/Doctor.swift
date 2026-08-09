import Foundation
import DuoUpdaterCore

/// `duo doctor` — answer "why can't it install that?" before the user has to
/// guess.
///
/// Every check here corresponds to something that otherwise fails late, in the
/// middle of an install, with an errno. App Management denial in particular
/// reads as an ordinary permissions error, and the fix (a System Settings
/// toggle, granted per binary *and per path*) is not one anybody guesses.
public enum Doctor {

    struct Report: Encodable {
        var executable: String
        var appManagement: String
        /// nil when the SPI could not answer — reported as "can't tell", never
        /// collapsed into either answer.
        var isResponsibleForItself: Bool?
        var installedApp: String?
        var privilegedHelper: String
        var githubToken: String
        var alcoveCredentials: Bool
        var masInstalled: Bool
        var brewInstalled: Bool
        var stateDirectory: String
        var installLockHolder: Int32?
    }

    public static func run(json: Bool) -> Int32 {
        let settings = Settings.load()
        let report = Report(
            executable: CommandLine.arguments[0],
            appManagement: String(describing: TCCPreflight.appManagementStatus()),
            // Asked of the kernel, not inferred from whether there is a tty:
            // a CLI run from a non-interactive shell has no tty and still
            // inherits that shell's responsibility, so the tty heuristic
            // reports a grant duo does not hold.
            isResponsibleForItself: TCCPreflight.isResponsibleForItself(),
            installedApp: installedAppPath(),
            privilegedHelper: helperStatus(),
            githubToken: tokenDescription(settings),
            alcoveCredentials: settings.alcove != nil,
            masInstalled: which("mas") != nil,
            brewInstalled: which("brew") != nil,
            stateDirectory: DuoStateDirectory.base.path,
            installLockHolder: InstallLock.currentHolder())

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report) {
                print(String(decoding: data, as: UTF8.self))
            }
        } else {
            emitText(report)
        }
        // Only App Management gates the in-place routes; everything else here
        // degrades to a narrower set of routes rather than to failure.
        return report.appManagement == "granted" ? 0 : 3
    }

    static func emitText(_ report: Report) {
        func line(_ ok: Bool?, _ label: String, _ detail: String) {
            let mark = ok.map { $0 ? "✓" : "✗" } ?? "·"
            print("  \(mark) \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(detail)")
        }
        print("\n  duo doctor\n  ─────────────────────────────────────────────")
        line(report.appManagement == "granted", "App Management",
             report.appManagement == "granted"
                ? "granted"
                : "\(report.appManagement) — in-place installs will fail with EPERM. "
                  + "Add \(report.executable) in System Settings ▸ Privacy & "
                  + "Security ▸ App Management. The grant is bound to this exact "
                  + "path; moving the binary starts over.")
        switch report.isResponsibleForItself {
        case false:
            line(nil, "responsible process",
                 "another process is responsible for this one, so the line above "
                 + "is its grant, not duo's. The same binary can fail from "
                 + "launchd or cron. Grant duo itself to be sure.")
        case nil:
            line(nil, "responsible process", "could not be determined")
        case true?:
            break  // the status above is duo's own; nothing to caveat.
        }
        line(report.installedApp != nil, "menu-bar app",
             report.installedApp ?? "not installed — settings fall back to defaults")
        line(report.privilegedHelper == "registered", "privileged helper", report.privilegedHelper)
        line(report.githubToken != "none", "GitHub token", report.githubToken)
        line(report.alcoveCredentials, "Alcove licence",
             report.alcoveCredentials ? "present" : "absent — Alcove stays detection-only")
        line(report.masInstalled, "mas",
             report.masInstalled ? "installed" : "absent — App Store updates need the app")
        line(report.brewInstalled, "brew",
             report.brewInstalled ? "installed" : "absent — cask updates unavailable")
        line(nil, "state directory", report.stateDirectory)
        if let holder = report.installLockHolder {
            line(false, "install lock", "held by pid \(holder) — installs will be refused")
        }
        print("""

          Reading the shared GitHub/Alcove secrets raises a one-time Keychain
          prompt: they were stored by DuoUpdater.app, and macOS scopes a generic
          password to the program that created it. Answer Always Allow once.

        """)
    }

    // MARK: - Probes

    /// `SMAppService.daemon` reads the *calling* bundle's
    /// `Contents/Library/LaunchDaemons`, which a standalone binary does not
    /// have, so the CLI can only observe the helper — never register it.
    ///
    /// Observed through launchd rather than the filesystem: `SMAppService`
    /// submits the job through `smd` and writes nothing to
    /// `/Library/LaunchDaemons`, so a file check reports "not registered" for a
    /// helper that is registered and running. (It did, on a machine where it
    /// was.)
    static func helperStatus() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/com.duoupdater.helper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
            ? "registered"
            : "not registered — approve it once in the menu-bar app; the CLI cannot register it"
    }

    static func installedAppPath() -> String? {
        let candidates = ["/Applications/DuoUpdater.app",
                          NSHomeDirectory() + "/Applications/DuoUpdater.app"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func tokenDescription(_ settings: Settings) -> String {
        guard let token = settings.githubToken, !token.isEmpty else {
            return "none — GitHub-sourced apps share the 60 requests/hour anonymous budget"
        }
        return "present (\(token.prefix(4))…, \(token.count) chars)"
    }

    static func which(_ tool: String) -> String? {
        let roots = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        return roots.map { $0 + "/" + tool }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
