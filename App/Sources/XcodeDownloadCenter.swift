import Foundation
import AppKit
import DuoUpdaterCore

/// Settings → Xcode's "Download Xcode" list: any build the xcodereleases index
/// (and, signed in, Apple's own list) has, fetched through the Apple Developer
/// session and either installed beside the Xcodes already there
/// (`XcodeSideBySideInstaller`: a new `/Applications/Xcode-<version>.app`,
/// marked Ignored, then opened) or saved as its `.xip` into Downloads. Nothing
/// installed is ever replaced.
///
/// A singleton so a download keeps going (and keeps its progress) when the
/// Settings window closes or moves to another page. One at a time: each is
/// 2–4 GB, and two would only split the same connection.
@MainActor
@Observable
final class XcodeDownloadCenter {
    static let shared = XcodeDownloadCenter()

    private(set) var items: [XcodeDownloadItem] = []
    private(set) var loading = false
    private(set) var loadError: String?
    /// What became of Apple's own list (`AppleDeveloperDownloadList`) on the
    /// last load. Recorded then, not derived from the session now, so the
    /// caption describes the list actually on screen.
    enum AppleListState { case included, unreadable, signedOut }
    private(set) var appleList: AppleListState?
    private(set) var lastLoaded: Date?

    /// What the active item is doing once its bytes are in.
    enum Phase: Equatable { case downloading, verifying, expanding, installing }

    private(set) var activeID: String?
    private(set) var progress: Double = 0
    private(set) var phase: Phase = .downloading
    /// Where each finished download landed, by item id.
    private(set) var finished: [String: URL] = [:]
    /// Where each installed copy now is, by item id.
    private(set) var installed: [String: URL] = [:]
    /// Xcodes already in Applications, by published build — re-read on every
    /// load and after an install.
    private(set) var installedBuilds: [String: URL] = [:]

    static var applicationFolders: [URL] {
        [applications, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }
    private(set) var errors: [String: String] = [:]

    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {}

    /// Fetch the list again. Called each time the page appears: the index is
    /// fetched with `versionFeedCachePolicy` on `URLSession.updates`, whose
    /// in-memory cache keeps it, so a repeat within a launch is a conditional
    /// request. Measured 2026-09-23 with task metrics: the first fetch received
    /// 33,459 bytes (gzip; 381,308 decoded), the repeat sent `If-None-Match` and
    /// got 304 with 0 body bytes. The list on screen stays while it runs, and a
    /// failed refresh keeps it.
    func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        installedBuilds = await Self.readInstalledBuilds()
        // Signed in: Apple's own list too, merged by archive path. It is
        // no-store (~190 KB each time), so it is asked only here — on opening the
        // page, pressing refresh or signing in — never on a timer.
        let signedIn = AppleDeveloperSession.shared.signInNeed == nil
        let appleData = await AppleDeveloperSession.shared.fetchDownloadList()
        let appleUsable = appleData.map { !AppleDeveloperDownloadList.parse($0).isEmpty } ?? false
        do {
            items = if let appleData, appleUsable {
                try await XcodeDownloadCatalog.load(mergingAppleList: appleData)
            } else {
                try await XcodeDownloadCatalog.load()
            }
            appleList = appleUsable ? .included : signedIn ? .unreadable : .signedOut
            loadError = nil
            lastLoaded = Date()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Download `item` into Downloads. Not signed in, or Apple ended the
    /// session: the sign-in window opens first — the user just asked for this
    /// download by name, unlike an update the app found on its own.
    func download(_ item: XcodeDownloadItem) {
        start(item, install: false)
    }

    /// Download `item`, install it as a new copy in Applications, and open it.
    func install(_ item: XcodeDownloadItem) {
        start(item, install: true)
    }

    private func start(_ item: XcodeDownloadItem, install: Bool) {
        guard activeID == nil else { return }
        activeID = item.id
        progress = 0
        phase = .downloading
        errors[item.id] = nil
        task = Task { [weak self] in
            await self?.run(item, install: install)
            self?.activeID = nil
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(_ item: XcodeDownloadItem, install: Bool) async {
        let session = AppleDeveloperSession.shared
        await session.restore()
        await session.refreshSignedInState()
        // Ended on Apple's side: `check()` tries to get a new session without
        // the user before the sign-in window is put in front of them.
        if session.signInNeed == .expired { await session.check() }
        if session.signInNeed != nil {
            guard await AppleDeveloperSignInWindow().present(), !Task.isCancelled else { return }
        }
        let fm = FileManager.default
        do {
            let target = install
                ? Self.applications
                : try fm.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // Staged on the target's volume and moved in only once whole, so a
            // half-written archive or a half-expanded Xcode never sits there under
            // its real name, and the downloader's "replace what is at the
            // destination" can only ever touch this scratch folder — never a file
            // the user already has.
            let staging = try fm.url(
                for: .itemReplacementDirectory, in: .userDomainMask,
                appropriateFor: target, create: true)
            defer { try? fm.removeItem(at: staging) }
            let result = try await WebKitXcodeDownloader().downloadXcodeArchive(
                from: item.authorizedURL, into: staging
            ) { fraction in
                Task { @MainActor in XcodeDownloadCenter.shared.progress = fraction }
            }
            if install {
                try await installCopy(of: item, archive: result.fileURL, staging: staging)
            } else {
                let destination = Self.freeName(for: item.fileName, in: target)
                try fm.moveItem(at: result.fileURL, to: destination)
                finished[item.id] = destination
            }
        } catch is CancellationError {
            return
        } catch {
            errors[item.id] = error.localizedDescription
        }
    }

    static let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)

    private static func readInstalledBuilds() async -> [String: URL] {
        let folders = applicationFolders
        return await Task.detached { XcodeSideBySideInstaller.installedBuilds(in: folders) }.value
    }

    /// The ignore key this install added, until the new copy is in place — so a
    /// failed or cancelled move takes back only what it put there.
    @ObservationIgnored private var addedIgnore: URL?

    private func installCopy(of item: XcodeDownloadItem, archive: URL, staging: URL) async throws {
        let name = XcodeSideBySideInstaller.bundleName(forVersion: item.displayVersion)
        addedIgnore = nil
        do {
            let app = try await XcodeSideBySideInstaller.install(
                archive: archive, workDir: staging, into: Self.applications, name: name,
                willMove: { destination in
                    await XcodeDownloadCenter.shared.ignoreBeforeMove(destination)
                },
                onStage: { stage in
                    Task { @MainActor in XcodeDownloadCenter.shared.show(stage) }
                })
            addedIgnore = nil
            installed[item.id] = app
            installedBuilds = await Self.readInstalledBuilds()
            Log.app.notice("xcode side-by-side install: \(app.path, privacy: .public)")
            // First launch asks for the license and installs Xcode's components
            // itself — the rest of "installing Xcode" that no archive carries.
            NSWorkspace.shared.open(app)
        } catch {
            if let added = addedIgnore,
               (try? FileManager.default.attributesOfItem(atPath: added.path)) == nil {
                Preferences.shared.removeIgnored(key: InstallPreferenceKey.preferenceKey(added.path))
            }
            addedIgnore = nil
            throw error
        }
    }

    /// Marked before the copy appears, so no scan can see it un-ignored and
    /// offer it an update to the release channel's newest Xcode: the user
    /// picked this version on purpose. Library → Ignored lists it and takes it
    /// back.
    private func ignoreBeforeMove(_ destination: URL) {
        if Preferences.shared.ignore(path: destination) { addedIgnore = destination }
    }

    private func show(_ stage: InstallStage) {
        switch stage {
        case .verifyingSignature, .verifyingCodeSignature: phase = .verifying
        case .extracting: phase = .expanding
        case .installing: phase = .installing
        default: break
        }
    }

    /// `name`, or "name 2", "name 3"… — the first that does not exist yet.
    static func freeName(for name: String, in directory: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
