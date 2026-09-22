import Foundation
import DuoUpdaterCore

/// Settings → Xcode's "Download Xcode" list: any build the xcodereleases index
/// lists, fetched as its `.xip` into Downloads through the Apple Developer
/// session. A download only — nothing is expanded, installed or replaced.
///
/// A singleton so a download keeps going (and keeps its progress) when the
/// Settings window closes or moves to another page. One download at a time: each
/// is 2–4 GB, and two would only split the same connection.
@MainActor
@Observable
final class XcodeDownloadCenter {
    static let shared = XcodeDownloadCenter()

    private(set) var items: [XcodeDownloadItem] = []
    private(set) var loading = false
    private(set) var loadError: String?

    private(set) var activeID: String?
    private(set) var progress: Double = 0
    /// Where each finished download landed, by item id.
    private(set) var finished: [String: URL] = [:]
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
        do {
            items = try await XcodeDownloadCatalog.load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Download `item` into Downloads. Not signed in, or Apple ended the
    /// session: the sign-in window opens first — the user just asked for this
    /// download by name, unlike an update the app found on its own.
    func download(_ item: XcodeDownloadItem) {
        guard activeID == nil else { return }
        activeID = item.id
        progress = 0
        errors[item.id] = nil
        task = Task { [weak self] in
            await self?.run(item)
            self?.activeID = nil
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(_ item: XcodeDownloadItem) async {
        let session = AppleDeveloperSession.shared
        await session.restore()
        await session.refreshSignedInState()
        if session.signInNeed != nil {
            guard await AppleDeveloperSignInWindow().present(), !Task.isCancelled else { return }
        }
        let fm = FileManager.default
        do {
            let downloads = try fm.url(
                for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // Staged beside Downloads (same volume) and moved in only once whole,
            // so a half-written archive never sits there under its real name, and
            // the downloader's "replace what is at the destination" can only ever
            // touch this scratch folder — never a file the user already has.
            let staging = try fm.url(
                for: .itemReplacementDirectory, in: .userDomainMask,
                appropriateFor: downloads, create: true)
            defer { try? fm.removeItem(at: staging) }
            let result = try await WebKitXcodeDownloader().downloadXcodeArchive(
                from: item.authorizedURL, into: staging
            ) { fraction in
                Task { @MainActor in XcodeDownloadCenter.shared.progress = fraction }
            }
            let destination = Self.freeName(for: item.fileName, in: downloads)
            try fm.moveItem(at: result.fileURL, to: destination)
            finished[item.id] = destination
        } catch is CancellationError {
            return
        } catch {
            errors[item.id] = error.localizedDescription
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
