import Foundation

/// Installs an Xcode from Settings → Xcode's download list as a NEW copy beside
/// the ones already there — `/Applications/Xcode-27.1-beta-1.app` — never over
/// one. The `.xcode` update route (`XcodeInstaller`) replaces an installed copy
/// in place; this one only ever adds.
///
/// The archive goes through the same steps as an update (`XcodeInstaller
/// .verifiedExpansion`: room, Apple's signature on the `.xip`, `xip --expand`,
/// one `.app`). There is no installed copy to compare the bundle against, so
/// the bundle gates pin it to Xcode itself instead: a valid deep code
/// signature, Apple's Team ID, the `com.apple.dt.Xcode` identifier, that it
/// can run on this Mac, and that this macOS does not block that Xcode version
/// from opening (`verifyNotBlockedByMacOS`). Every Xcode build measured carries the same Team ID
/// whatever its signing chain — developer-site betas and RCs and the App Store
/// GA alike (2026-09-22, and the two installed on the dev Mac, 2026-09-23).
///
/// The destination must not exist: a name already taken stops the install
/// before anything moves, and the move itself refuses to replace (it fails
/// when the destination appears meanwhile).
public enum XcodeSideBySideInstaller {
    public static let appleTeamID = "59GAB85EFG"
    public static let xcodeIdentifier = "com.apple.dt.Xcode"

    public enum InstallError: LocalizedError, Equatable {
        /// `name` is the bundle's file name ("Xcode-26.6.app").
        case destinationExists(name: String)
        case notXcode(String)
        /// `version` is Xcode's marketing version ("26.6").
        case blockedByMacOS(version: String)
        case moveFailed(String)

        public var errorDescription: String? {
            switch self {
            case .destinationExists(let name):
                return "Applications already has \(name). Nothing was changed — rename or remove that copy first."
            case .notXcode(let why):
                return "The archive did not contain Apple's Xcode (\(why)). Nothing was changed."
            case .blockedByMacOS(let version):
                return "This version of macOS won't open Xcode \(version) — Apple blocks it as incompatible. Nothing was installed; choose a newer Xcode."
            case .moveFailed(let why):
                return "Xcode could not be moved into Applications: \(why)"
            }
        }
    }

    /// "27.1 beta 1 (27A9269)" → "Xcode-27.1-beta-1.app"; "26.6 (17F113)" →
    /// "Xcode-26.6.app". The build in parentheses, which the list shows, is
    /// left out. One path component whatever the version says.
    public static func bundleName(forVersion displayVersion: String) -> String {
        let version = displayVersion.replacingOccurrences(
            of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        let words = version.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        return "Xcode-\(words.filesystemSafeToken).app"
    }

    /// Verify and expand `archive` inside `workDir`, gate the bundle, then move it
    /// to `directory/name`. `willMove` runs after every check has passed and
    /// right before the move — the caller records anything that must already be
    /// in place when the new copy appears (DuoUpdater marks it Ignored). Returns
    /// where the app now is.
    ///
    /// `workDir` is the caller's: it is neither created nor removed here.
    public static func install(
        archive: URL,
        workDir: URL,
        into directory: URL,
        name: String,
        host: HostArch = .current,
        osVersion: String = HostOS.numericVersion(),
        exceptions: URL = launchExceptions,
        willMove: @Sendable (URL) async -> Void,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> URL {
        let destination = directory.appendingPathComponent(name, isDirectory: true)
        // Asked first as well as last, so a taken name costs no download check
        // and no minute of expanding.
        try checkFree(destination)

        let newApp = try await XcodeInstaller.verifiedExpansion(
            of: archive, in: workDir, onStage: onStage)

        onStage(.verifyingCodeSignature)
        try await offCooperativePool {
            try verifyIsXcode(newApp, host: host, osVersion: osVersion)
            try verifyNotBlockedByMacOS(newApp, exceptions: exceptions)
        }

        onStage(.installing)
        try checkFree(destination)
        await InPlaceSwap.stripQuarantine(newApp)
        await willMove(destination)
        do {
            // A rename when the scratch dir shares the volume, a copy otherwise;
            // either way it fails rather than replace something at `destination`.
            try await offCooperativePool {
                try FileManager.default.moveItem(at: newApp, to: destination)
            }
        } catch {
            throw InstallError.moveFailed(error.localizedDescription)
        }
        onStage(.done)
        return destination
    }

    /// Whether Install is offered for an Xcode on this Mac, decided from the list
    /// alone — before 2 GB are downloaded. What is not installable is still
    /// offered as Download Only.
    public enum Installability: Sendable, Equatable {
        case installable
        /// This macOS is newer than any this Xcode supports ("27").
        case tooOldForMacOS(String)
        /// This Xcode needs a newer macOS ("26.6").
        case needsMacOS(String)
    }

    /// Apple's published ranges (developer.apple.com/xcode/system-requirements,
    /// read 2026-09-23) end each Xcode at the macOS it was made for: 26.x at
    /// "macOS Tahoe 26.x", 16.x at "macOS Sequoia 15.x", 15.x at "macOS Sonoma
    /// 14.x" — while a new Xcode runs one macOS back (27 on "Tahoe 26.6 or
    /// later"). So an Xcode whose macOS generation — its major version from 26
    /// on, one less before the renumbering (16 → 15) — is older than this
    /// macOS's major is refused; a newer one is fine as long as this macOS meets
    /// its "Requires". macOS 27 agrees on its own: its launch list hard-disables
    /// every Xcode up to `CFBundleVersion` 24999, and 26.6 is 24959.
    ///
    /// One published exception is left conservative: 16.4 lists "Tahoe 26.1.x",
    /// and on 26.0–26.1 is still offered as Download Only. The check after
    /// expanding (`verifyNotBlockedByMacOS`) stays the last word.
    public static func installability(
        displayVersion: String, requiresMacOS: String?, macOSVersion: String
    ) -> Installability {
        let hostMajor = Int(macOSVersion.split(separator: ".").first ?? "") ?? 0
        if let range = displayVersion.range(of: #"^[0-9]+"#, options: .regularExpression),
           let major = Int(displayVersion[range]) {
            let generation = major >= 26 ? major : major - 1
            if generation < hostMajor {
                return .tooOldForMacOS(String(hostMajor))
            }
        }
        if let requires = requiresMacOS,
           VersionComparator.compare(macOSVersion, requires) == .orderedAscending {
            return .needsMacOS(requires)
        }
        return .installable
    }

    /// The Xcodes already in `directories` (top level only), by published build
    /// (`ProductBuildVersion`, what the list shows — `27A266a`). The list offers
    /// Download Only for these instead of Install: a second copy of the same
    /// build is only 4 GB more. An RC and its GA share a build (27.0 RC 1 and
    /// 27.0 are both `27A266a`, 2026-09-22) and are the same bytes, so either
    /// counts as installed. Where two copies share a build, the first by name
    /// wins.
    public static func installedBuilds(in directories: [URL]) -> [String: URL] {
        let fm = FileManager.default
        var found: [String: URL] = [:]
        for directory in directories {
            let apps = ((try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for app in apps {
                guard Bundle(url: app)?.bundleIdentifier == xcodeIdentifier,
                      let build = AppScanner.productBuildVersion(in: app),
                      found[build] == nil
                else { continue }
                found[build] = app
            }
        }
        return found
    }

    static func checkFree(_ destination: URL) throws {
        // `lstat`, not `fileExists`: a dangling symlink at the name is taken too.
        if (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil {
            throw InstallError.destinationExists(name: destination.lastPathComponent)
        }
    }

    /// The bundle gates, with Xcode's own identity standing in for the installed
    /// copy an update would be compared with.
    static func verifyIsXcode(_ app: URL, host: HostArch, osVersion: String) throws {
        try SignatureVerifier.verifyCodeSignature(appAt: app)
        let team = try SignatureVerifier.teamIdentifier(at: app)
        guard team == appleTeamID else {
            throw InstallError.notXcode("signed by team \(team ?? "none"), not Apple's \(appleTeamID)")
        }
        let identifier = try SignatureVerifier.signingIdentifier(at: app)
        guard identifier == xcodeIdentifier else {
            throw InstallError.notXcode("its identifier is \(identifier ?? "missing"), not \(xcodeIdentifier)")
        }
        try SignatureVerifier.verifyRunnableArchitecture(appAt: app, host: host)
        try SignatureVerifier.verifyRunnableSystemVersion(appAt: app, osVersion: osVersion)
    }

    /// macOS's own list of app versions it refuses to open. Undocumented; read
    /// from the running system so it is always this macOS's answer.
    public static let launchExceptions = URL(
        fileURLWithPath: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Exceptions.plist")

    /// Refuse an Xcode this macOS will not open. Found 2026-09-23: Xcode 26.6
    /// installed fine and then would not launch on macOS 27 ("…is not compatible
    /// with macOS…"); the list's `LaunchOverrides` holds `com.apple.dt.Xcode`
    /// with `HardDisabled` up to `HighVersion` 24999, and that Xcode's
    /// `CFBundleVersion` is 24959 (27.0 is 25183.107.5, 27.2 beta 25400.27.8 —
    /// both open). A list that cannot be read passes: it only ever adds a refusal
    /// the system would make anyway.
    static func verifyNotBlockedByMacOS(_ app: URL, exceptions: URL = launchExceptions) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let bundleVersion = info["CFBundleVersion"] as? String,
              let list = NSDictionary(contentsOf: exceptions) as? [String: Any]
        else { return }
        if isHardDisabled(bundleID: xcodeIdentifier, bundleVersion: bundleVersion, exceptions: list) {
            throw InstallError.blockedByMacOS(
                version: info["CFBundleShortVersionString"] as? String ?? bundleVersion)
        }
    }

    /// Whether `exceptions` (Exceptions.plist) hard-disables this version: an
    /// entry under `LaunchOverrides[bundleID]` with `HardDisabled` whose
    /// `LowVersion`…`HighVersion` (both inclusive; a missing bound is open)
    /// holds it. Pure.
    static func isHardDisabled(bundleID: String, bundleVersion: String, exceptions: [String: Any]) -> Bool {
        guard let overrides = exceptions["LaunchOverrides"] as? [String: Any],
              let entries = overrides[bundleID] as? [[String: Any]]
        else { return false }
        return entries.contains { entry in
            guard entry["HardDisabled"] as? Bool == true else { return false }
            if let low = entry["LowVersion"] as? String,
               VersionComparator.compare(bundleVersion, low) == .orderedAscending { return false }
            if let high = entry["HighVersion"] as? String,
               VersionComparator.compare(bundleVersion, high) == .orderedDescending { return false }
            return true
        }
    }
}
