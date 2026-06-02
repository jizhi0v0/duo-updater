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

        public var errorDescription: String? {
            switch self {
            case .noURL: return "This update has no download URL."
            case .downloadFailed(let m): return "Could not prepare the installer: \(m)"
            }
        }
    }

    /// Download `url` and open the resulting installer (or the disk image that
    /// contains it). Returns once the installer has been launched — the actual
    /// install happens in macOS's installer, under the user's control.
    public func downloadAndOpen(
        url: URL?,
        headers: [String: String] = [:],
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
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

        onStage(.installing)
        let toOpen = try resolveInstaller(from: file, workDir: workDir)
        await open(toOpen)
        onStage(.done)
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
        guard attach == 0 else { return file }  // fall back to opening the dmg
        defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        guard let pkg = firstPackage(in: mountPoint) else { return file }
        let dest = workDir.appendingPathComponent(pkg.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard run("/usr/bin/ditto", [pkg.path, dest.path]) == 0 else { return file }
        return dest
    }

    private func firstPackage(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries.first { ["pkg", "mpkg"].contains($0.pathExtension.lowercased()) }
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
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
