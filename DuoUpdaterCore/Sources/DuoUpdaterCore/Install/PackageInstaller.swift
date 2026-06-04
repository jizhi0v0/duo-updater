import Foundation
import AppKit

/// Handles updates that ship as an installer package (`pkg` casks like AweSun,
/// Tailscale). We can't swap those in place, and a non-interactive `brew` can't
/// elevate to run the installer — so we download the official package (the same
/// URL Homebrew would use) and hand it to macOS's own installer, which prompts
/// for admin itself. The user confirms the install in a trusted, native UI.
public actor PackageInstaller {

    public init() {}

    public enum PackageError: LocalizedError {
        case noURL
        case downloadFailed(String)
        case unsignedPackage
        case noInstallablePackage
        case packageTeamIdentifierMissing
        case packageTeamIdentifierMismatch(installed: String, package: String)

        public var errorDescription: String? {
            switch self {
            case .noURL: return "This update has no download URL."
            case .downloadFailed(let m): return "Could not prepare the installer: \(m)"
            case .unsignedPackage:
                return "The downloaded installer package isn't signed by a valid Developer ID — it may be corrupt or tampered. Nothing was installed."
            case .noInstallablePackage:
                return "The downloaded disk image did not contain an installer package DuoUpdater could verify. Nothing was opened."
            case .packageTeamIdentifierMissing:
                return "Could not read the installer package's Developer ID team. Nothing was opened."
            case .packageTeamIdentifierMismatch(let installed, let package):
                return "Installer Team Identifier mismatch: installed “\(installed)” vs package “\(package)”. Refusing to open it."
            }
        }
    }

    /// Download `url` and open the resulting installer (or the disk image that
    /// contains it). Returns once the installer has been launched — the actual
    /// install happens in macOS's installer, under the user's control.
    /// Returns the exact number of bytes downloaded for the installer package,
    /// for per-app traffic accounting.
    @discardableResult
    public func downloadAndOpen(
        url: URL?,
        installedApp: URL,
        headers: [String: String] = [:],
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> Int64 {
        guard let url else { throw PackageError.noURL }

        // Keep the download where the system installer can read it for the whole
        // session; we drop stale copies on the next run rather than mid-install.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdater-pkg")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let downloader = Downloader(destinationDir: workDir) { fraction in
            onStage(.downloading(fraction: fraction))
        }
        let file = try await downloader.download(url, headers: headers)
        let bytesDownloaded = downloader.bytesDownloaded

        onStage(.installing)
        let toOpen = try resolveInstaller(from: file, workDir: workDir)
        // Gate: a `.pkg`/`.mpkg` runs install scripts (often with admin rights) the
        // moment the user confirms in the system installer. A hijacked download URL
        // could otherwise serve an arbitrary package. Refuse to open one that isn't
        // signed by a valid Developer ID / notarized. (A bare `.dmg` fallback can't
        // be pkg-checked — the user still drives that one manually.)
        let ext = toOpen.pathExtension.lowercased()
        if ext == "pkg" || ext == "mpkg" {
            guard let installedTeam = try SignatureVerifier.teamIdentifier(at: installedApp) else {
                throw SignatureVerifier.VerifyError.noTeamIdentifier(which: "installed")
            }
            let packageSignature = packageSignature(toOpen)
            guard packageSignature.isValid else {
                throw PackageError.unsignedPackage
            }
            guard let packageTeam = packageSignature.teamIdentifier else {
                throw PackageError.packageTeamIdentifierMissing
            }
            guard packageTeam == installedTeam else {
                throw PackageError.packageTeamIdentifierMismatch(
                    installed: installedTeam,
                    package: packageTeam)
            }
        }
        await open(toOpen)
        onStage(.done)
        return bytesDownloaded
    }

    /// Given a downloaded file, return the thing to hand to the system installer.
    /// For a `.dmg` we mount it, copy the contained `.pkg` out (so the installer
    /// keeps working after we unmount), and return that; otherwise we open the
    /// file itself (a bare `.pkg`, or the `.dmg`/folder as a fallback).
    private func resolveInstaller(from file: URL, workDir: URL) throws -> URL {
        guard file.pathExtension.lowercased() == "dmg" else { return file }

        let mountPoint = workDir.appendingPathComponent("mnt")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = run("/usr/bin/hdiutil", [
            "attach", file.path, "-nobrowse", "-readonly", "-noverify",
            "-mountpoint", mountPoint.path
        ])
        guard attach == 0 else { throw PackageError.noInstallablePackage }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        guard let pkg = firstPackage(in: mountPoint) else {
            throw PackageError.noInstallablePackage
        }
        let dest = workDir.appendingPathComponent(pkg.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard run("/usr/bin/ditto", [pkg.path, dest.path]) == 0 else {
            throw PackageError.downloadFailed("Could not copy the installer package out of the disk image.")
        }
        return dest
    }

    /// `pkgutil --check-signature` validates the package chain and prints the
    /// Developer ID Installer certificate, whose parenthesized OU is the Team ID.
    private func packageSignature(_ pkg: URL) -> (isValid: Bool, teamIdentifier: String?) {
        let result = runCapturingOutput("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
        guard result.code == 0 else { return (false, nil) }
        return (true, Self.packageTeamIdentifier(fromPkgutilOutput: result.output))
    }

    private func firstPackage(in dir: URL) -> URL? {
        let fm = FileManager.default
        let dirBase = dir.resolvingSymlinksInPath().standardizedFileURL.path
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { Self.isPackageEntry($0, insideResolvedPath: dirBase) }
    }

    static func isPackageEntry(_ url: URL, insideResolvedPath dirBase: String) -> Bool {
        guard ["pkg", "mpkg"].contains(url.pathExtension.lowercased()) else {
            return false
        }
        let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if vals?.isSymbolicLink == true { return false }
        guard vals?.isDirectory == true || vals?.isRegularFile == true else { return false }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved == dirBase || resolved.hasPrefix(dirBase + "/")
    }

    @MainActor
    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        // We use only the exit status, so discard output to /dev/null rather than to
        // undrained `Pipe()`s — an unread pipe deadlocks once the child fills its
        // ~64KB buffer (the child blocks on write(), we block in waitUntilExit()).
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    @discardableResult
    private func runCapturingOutput(_ launchPath: String, _ args: [String]) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func packageTeamIdentifier(fromPkgutilOutput output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard line.range(of: "Developer ID Installer:", options: .caseInsensitive) != nil,
                  let open = line.lastIndex(of: "("),
                  let close = line[open...].firstIndex(of: ")") else {
                continue
            }
            let team = line[line.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil {
                return team
            }
        }
        return nil
    }
}
