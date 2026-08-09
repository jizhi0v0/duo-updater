import Foundation

/// Performs the fetch-and-apply half of an install, for every route that does
/// not need a GUI.
///
/// This is the part the menu-bar app and `duo install` must not each have a copy
/// of: which installer handles which source, when the download and apply permits
/// are taken and — the subtle one — when they are *given back*. The apply permit
/// is released the instant the swap lands, because everything after it (waiting
/// for a process to quit, asking for a relaunch) is user time, and a permit held
/// through user time throttles the whole queue for nothing.
///
/// What stays with the caller: progress display, traffic accounting, backups,
/// restart bookkeeping, and turning an error into a permission prompt. Those are
/// all things the two hosts legitimately do differently.
///
/// The App Store route is deliberately absent. It needs either the privileged
/// helper (whose `SMAppService.daemon` registration requires an app bundle) or
/// the Accessibility API driving App Store.app, so it cannot be honestly shared
/// with a command-line tool. `duo install` refuses it with a message rather than
/// half-doing it.
public actor InstallCoordinator {

    /// Which installer applies this update. Derived from the source name rather
    /// than chosen by the caller, so both hosts route identically.
    public enum Route: String, Sendable, CaseIterable {
        case homebrew
        /// A `.pkg`: downloaded, then handed to the system installer, which the
        /// user finishes. We never see it land.
        case installer
        case vendor
        case sparkle
        case appStore
    }

    public enum CoordinatorError: LocalizedError {
        case routeNotSupportedHere(Route)
        case missingCaskToken
        case notAnUpdate

        public var errorDescription: String? {
            switch self {
            case .routeNotSupportedHere(let route):
                return "the \(route.rawValue) route cannot be driven from here"
            case .missingCaskToken:
                return "the Homebrew source did not name a cask to upgrade"
            case .notAnUpdate:
                return "this app has no update to install"
            }
        }
    }

    /// What an install produced, for the caller's bookkeeping.
    public struct Outcome: Sendable {
        /// Bytes we measured ourselves. Zero for routes where another tool does
        /// the fetching (Homebrew, the App Store) — deliberately not estimated,
        /// so every recorded number is one we actually counted.
        public let bytesDownloaded: Int64
        /// The host the download ended on after redirects, for the traffic log.
        public let finalHost: String?
        /// Where the downloaded `.pkg` was left. The system installer owns the
        /// finish, so the caller offers "Install" (re-open this exact file)
        /// rather than downloading it again.
        public let stagedPackageURL: URL?
        /// Whether the new version is on disk now. False for `.installer`, where
        /// the user still has a window to click through.
        public let applied: Bool
    }

    /// How many downloads and applies may run at once. Shared by both hosts, but
    /// per-process: two processes installing at the same time is what
    /// ``InstallLock`` prevents, not this.
    private let permits: InstallPermits
    private let vendor = VendorInstaller()
    private let sparkle = SparkleInstaller()
    private let homebrew = HomebrewInstaller()
    private let packages = PackageInstaller()

    public init(permits: InstallPermits = InstallPermits(downloads: 4, applies: 2)) {
        self.permits = permits
    }

    /// The route an update takes.
    ///
    /// Total on purpose, with `.sparkle` as the fallback rather than a nil that
    /// would mean "unroutable": that is what the menu-bar app's switch has
    /// always done, and an appcast is the right guess for a source we do not
    /// otherwise recognise. It is not a licence to call this for anything —
    /// callers must still gate on `UpdatePolicy.canAutoInstall` /
    /// `requiresInstaller`, which is what keeps detection-only apps out.
    public static func route(for result: UpdateResult, requiresInstaller: Bool) -> Route {
        if requiresInstaller { return .installer }
        switch result.remote?.sourceName {
        case "Homebrew":          return .homebrew
        case "Vendor", "GitHub":  return .vendor
        case "App Store":         return .appStore
        default:                  return .sparkle
        }
    }

    /// Fetch and apply `result` by `route`.
    ///
    /// - Parameter releaseAfterDownload: called once, as soon as the bytes are
    ///   down (or as soon as a tool that fetches on our behalf finishes), so a
    ///   per-host gate the caller holds can be handed to the next app rather
    ///   than spanning the extract and swap too. Must be idempotent — it is not
    ///   called at all on paths that never reach a download.
    public func perform(
        _ result: UpdateResult,
        route: Route,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void = {}
    ) async throws -> Outcome {
        switch route {
        case .appStore:
            throw CoordinatorError.routeNotSupportedHere(.appStore)

        case .installer:
            progress(.downloading(fraction: 0))
            let opened = try await permits.withDownloadPermit {
                // Cancelled while parked on the permit: don't start the fetch.
                try Task.checkCancellation()
                return try await packages.downloadAndOpen(
                    url: result.remote?.downloadURL,
                    installedApp: result.app.path,
                    headers: result.remote?.downloadHeaders ?? [:],
                    onStage: progress)
            }
            await releaseAfterDownload()
            return Outcome(
                bytesDownloaded: opened.bytesDownloaded, finalHost: opened.finalHost,
                stagedPackageURL: opened.packageURL, applied: false)

        case .homebrew:
            guard let token = result.remote?.sourceIdentifier else {
                throw CoordinatorError.missingCaskToken
            }
            progress(.runningCommand("starting brew…"))
            // brew's fetch and swap are one command we cannot split, so the whole
            // run takes the apply permit — and brew does its own downloading, so
            // those bytes are never counted rather than estimated.
            await permits.waitForApply()
            var applyHeld = true
            defer { if applyHeld { permits.signalApply() } }
            try Task.checkCancellation()
            try await homebrew.upgrade(caskToken: token) { line in
                progress(.runningCommand(line))
            }
            permits.signalApply()
            applyHeld = false
            await releaseAfterDownload()
            return Outcome(
                bytesDownloaded: 0, finalHost: nil, stagedPackageURL: nil, applied: true)

        case .vendor:
            return try await fetchThenSwap(
                result, progress: progress, releaseAfterDownload: releaseAfterDownload,
                download: { try await self.vendor.download($0, onStage: $1) },
                apply: { _ = try await self.vendor.apply($0, download: $1, onStage: $2) })

        case .sparkle:
            return try await fetchThenSwap(
                result, progress: progress, releaseAfterDownload: releaseAfterDownload,
                download: { try await self.sparkle.download($0, onStage: $1) },
                apply: { _ = try await self.sparkle.apply($0, download: $1, onStage: $2) })
        }
    }

    /// The shape both archive routes share: download under a download permit,
    /// hand the host gate back, then swap under an apply permit.
    ///
    /// The scratch directory is removed on every exit — including an apply
    /// failure and a cancellation landing between the two phases, which is why
    /// the `defer` is here and not at the call sites.
    private func fetchThenSwap(
        _ result: UpdateResult,
        progress: @Sendable @escaping (InstallStage) -> Void,
        releaseAfterDownload: @Sendable () async -> Void,
        download: @Sendable (UpdateResult, @Sendable @escaping (InstallStage) -> Void) async throws -> DownloadedUpdate,
        apply: @Sendable (UpdateResult, DownloadedUpdate, @Sendable @escaping (InstallStage) -> Void) async throws -> Void
    ) async throws -> Outcome {
        progress(.downloading(fraction: 0))
        let downloaded = try await permits.withDownloadPermit {
            try Task.checkCancellation()
            return try await download(result, progress)
        }
        await releaseAfterDownload()
        defer { try? FileManager.default.removeItem(at: downloaded.workDir) }

        await permits.waitForApply()
        var applyHeld = true
        defer { if applyHeld { permits.signalApply() } }
        try Task.checkCancellation()
        try await apply(result, downloaded, progress)
        permits.signalApply()
        applyHeld = false

        return Outcome(
            bytesDownloaded: downloaded.bytesDownloaded, finalHost: downloaded.finalHost,
            stagedPackageURL: nil, applied: true)
    }
}
