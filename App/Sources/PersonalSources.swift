import AppKit
import DuoUpdaterCore
import Observation

@Observable @MainActor
final class PersonalSources {
    static let shared = PersonalSources()
    struct BindingRecord: Codable, Equatable {
        var schema = 1
        var repository: PersonalGitHubSource.Repository
        let track: PersonalGitHubSource.Track
        let filenameContains: String?
        let includeStable: Bool
        var anchor: PersonalSourceZIP.Identity
        var lastSuccessfulCheck: Date?
        var confirmedVersion: String?
        var handoff: Handoff?
    }
    struct Handoff: Codable, Equatable, Sendable {
        let releaseID: Int64
        let tag: String
        let asset: PersonalGitHubSource.Asset
        let identity: PersonalSourceZIP.Identity
        let manifest: BackupManifest

        func isPublished(in snapshot: PersonalGitHubSource.Snapshot) -> Bool {
            snapshot.releases.contains { $0.id == releaseID && $0.tag_name == tag && $0.assets.contains(asset) }
        }
    }
    struct Checked {
        let release: PersonalGitHubSource.Release
        let asset: PersonalGitHubSource.Asset
        let directory: URL
        let application: URL
        let identity: PersonalSourceZIP.Identity
        let manifest: BackupManifest
    }
    private let key = "personalGitHubSources"
    private let defaults: UserDefaults
    private(set) var records: [String: Data]
    var snapshots: [String: PersonalGitHubSource.Snapshot] = [:]
    var anonymousLimited = Set<String>()
    var messages: [String: String] = [:]
    var busy = Set<String>()
    var checked: [String: Checked] = [:]
    var blocked: [String: [PersonalGitHubSource.Asset]] = [:]
    var manualOnly: [String: [PersonalGitHubSource.Asset]] = [:]
    var paused = Set<String>()
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
    }

    func record(_ path: String) -> BindingRecord? {
        guard let data = records[path], let record = try? JSONDecoder().decode(BindingRecord.self, from: data), record.schema == 1 else { return nil }
        return record
    }

    func save(_ record: BindingRecord, path: String) throws {
        records[path] = try JSONEncoder().encode(record)
        defaults.set(records, forKey: key)
    }

    func remove(_ path: String) {
        records.removeValue(forKey: path)
        defaults.set(records, forKey: key)
        clear(path)
    }

    func clear(_ path: String, preservingReleaseHistory: Bool = false) {
        if let old = checked.removeValue(forKey: path) { try? FileManager.default.removeItem(at: old.directory) }
        if !preservingReleaseHistory { snapshots[path] = nil }
        paused.remove(path)
        blocked[path] = nil
        manualOnly[path] = nil
        anonymousLimited.remove(path)
        messages[path] = nil
    }

    /// One result per repository in a scan, including failures. A second local
    /// installation can choose another track without spending another request.
    func refreshRegistered(_ apps: [InstalledApp]) async {
        var round: [String: Result<PersonalGitHubSource.Snapshot, Error>] = [:]
        for app in apps {
            await refresh(app) { slug in
                let key = slug.lowercased()
                if let result = round[key] { return try result.get() }
                do {
                    let result = try await PersonalGitHubClient.shared.fetch(slug)
                    round[key] = .success(result)
                    return result
                } catch {
                    round[key] = .failure(error)
                    throw error
                }
            }
        }
    }

    func refresh(_ app: InstalledApp, fetch: @MainActor (String) async throws -> PersonalGitHubSource.Snapshot = {
        try await PersonalGitHubClient.shared.fetch($0)
    }) async {
        let path = app.path.path
        guard var record = record(path), busy.insert(path).inserted else { return }
        defer { busy.remove(path) }
        do {
            guard let continued = try await reconcileInstallation(app.path, record: record) else { return }
            record = continued
            let snapshot = try await fetch(record.repository.full_name)
            guard self.record(path) == record else { return }
            try validateRepository(snapshot, record: record)
            var updated = record
            updated.lastSuccessfulCheck = snapshot.checked
            updated.repository = snapshot.repository
            if let handoff = updated.handoff, !handoff.isPublished(in: snapshot) { updated.handoff = nil }
            try save(updated, path: path)
            anonymousLimited.remove(path)
            paused.remove(path)
            if let old = checked[path] {
                let latest = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable).first
                if latest?.id != old.release.id || latest?.tag_name != old.release.tag_name || latest?.assets.contains(old.asset) != true {
                    clear(path)
                }
            }
            snapshots[path] = snapshot
            if updated.handoff != nil {
                messages[path] = "Waiting for manual installation at \(path)."
            } else {
                messages[path] = updated.confirmedVersion.map { String(localized: "Confirmed installation of \($0).") }
            }
        } catch {
            guard self.record(path) == record else { return }
            let last = record.lastSuccessfulCheck
            if (error as? PersonalGitHubSource.Failure)?.disposition == .reviewSource { clear(path) }
            anonymousLimited.remove(path)
            if (error as? PersonalGitHubSource.Failure)?.disposition == .anonymousLimit { anonymousLimited.insert(path) }
            paused.insert(path)
            messages[path] = error.localizedDescription + (last.map { " Last successful check: " + $0.formatted() } ?? "")
        }
    }

    /// Called from the existing local rescan as well as a repository refresh.
    /// Reading a manual handoff does not depend on network access.
    func reconcileLocal(_ app: InstalledApp) async {
        let path = app.path.path
        guard let record = record(path), !busy.contains(path) else { return }
        do {
            _ = try await reconcileInstallation(app.path, record: record)
        } catch {
            guard self.record(path) == record else { return }
            clear(path)
            messages[path] = error.localizedDescription
        }
    }

    private func reconcileInstallation(_ url: URL, record: BindingRecord) async throws -> BindingRecord? {
        let path = url.path
        let (actual, verified) = try await offCooperativePool {
            let current = try PersonalSourceZIP.Identity(at: url)
            guard current != record.anchor, let expected = record.handoff?.identity, expected.code != nil,
                  current.code == expected.code, current.team == expected.team, current.bundle == expected.bundle,
                  current.build == expected.build, current.version == expected.version else { return (current, false) }
            try SignatureVerifier.verifyCodeSignature(appAt: url)
            guard BackupManifest.compute(for: url) == record.handoff?.manifest else { return (current, false) }
            return (current, try PersonalSourceZIP.Identity(at: url) == current)
        }
        guard self.record(path) == record else { return nil }
        if actual == record.anchor { return record }
        clear(path, preservingReleaseHistory: verified)
        guard verified else {
            messages[path] = "The installation changed (now \(actual.version)). Review the source to continue."
            return nil
        }
        var continued = record
        continued.anchor = actual
        continued.confirmedVersion = actual.version
        continued.handoff = nil
        try save(continued, path: path)
        messages[path] = String(localized: "Confirmed installation of \(actual.version).")
        return continued
    }

    private func validateRepository(_ snapshot: PersonalGitHubSource.Snapshot, record: BindingRecord) throws {
        guard snapshot.repository.id == record.repository.id, snapshot.repository.owner.id == record.repository.owner.id else {
            throw PersonalGitHubSource.Failure("Repository or owner identity changed. Review the source to continue.", .reviewSource)
        }
    }

    func check(_ result: UpdateResult, release: PersonalGitHubSource.Release, asset: PersonalGitHubSource.Asset,
               reveal: Bool, eligible: @escaping @MainActor () -> Bool) async {
        let path = result.app.path.path
        guard let record = record(path), eligible(), busy.insert(path).inserted else { return }
        defer { busy.remove(path) }
        anonymousLimited.remove(path)
        var localInspection = false
        var scratch: URL?
        do {
            let fresh = try await PersonalGitHubClient.shared.fetch(record.repository.full_name)
            try validateRepository(fresh, record: record)
            guard let latest = fresh.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable).first,
                  latest.id == release.id, latest.tag_name == release.tag_name, latest.assets.contains(asset) else {
                throw PersonalGitHubSource.Failure("The release or asset changed. Check the source again.")
            }
            let directory: URL
            let candidate: URL
            if reveal {
                guard let previous = checked[path], previous.asset == asset, previous.release.id == release.id else { return }
                directory = previous.directory
                candidate = previous.application
            } else {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("DuoSource-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                scratch = directory
                candidate = try await PersonalGitHubClient.shared.downloadZIP(repository: fresh.repository, asset: asset, into: directory)
            }
            localInspection = true
            let identity = try await PersonalSourceZIP.inspect(app: candidate, installed: result.app.path, anchor: record.anchor, tag: release.tag_name)
            guard let manifest = await offCooperativePool({ BackupManifest.compute(for: candidate) }) else {
                throw PersonalGitHubSource.Failure("Cannot read all verified package contents.", .blocked)
            }
            guard self.record(path) == record, eligible() else { throw PersonalGitHubSource.Failure("The source or update route changed.") }
            if reveal {
                guard identity == checked[path]?.identity, manifest == checked[path]?.manifest else { throw PersonalGitHubSource.Failure("The staged package changed.") }
                var pending = record
                pending.handoff = Handoff(releaseID: release.id, tag: release.tag_name, asset: asset, identity: identity, manifest: manifest)
                try save(pending, path: path)
                NSWorkspace.shared.activateFileViewerSelecting([candidate])
                messages[path] = "Waiting for manual installation at \(path)."
            } else {
                if let previous = checked[path] { try? FileManager.default.removeItem(at: previous.directory) }
                checked[path] = Checked(release: release, asset: asset, directory: directory, application: candidate, identity: identity, manifest: manifest)
                scratch = nil
                messages[path] = "Verified \(identity.version) · \(identity.team ?? "") · SHA-256 matched."
            }
        } catch {
            guard self.record(path) == record else {
                if let scratch { try? FileManager.default.removeItem(at: scratch) }
                return
            }
            switch (error as? PersonalGitHubSource.Failure)?.disposition {
            case .anonymousLimit: anonymousLimited.insert(path)
            case .releasePage: manualOnly[path, default: []].append(asset)
            case .reviewSource: snapshots[path] = nil
            case .blocked: blocked[path, default: []].append(asset)
            default:
                if localInspection { blocked[path, default: []].append(asset) }
            }
            if let previous = checked.removeValue(forKey: path) { try? FileManager.default.removeItem(at: previous.directory) }
            messages[path] = error.localizedDescription
        }
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    enum ManualAction {
        case page(String), blocked, verify([PersonalGitHubSource.Asset]), reveal(Checked)
    }

    func action(for release: PersonalGitHubSource.Release, path: String, record: BindingRecord) -> ManualAction {
        let matches = release.assets.filter { $0.matchesMac && $0.matches(filename: record.filenameContains) }
        guard record.anchor.team != nil else { return .page(String(localized: "No Developer ID identity for this installation. Use the release page.")) }
        guard !matches.isEmpty else { return .page(String(localized: "No compatible package matched the filename filter. Use the release page.")) }
        let packages = matches.filter(\.supportsLocalCheck)
        guard !packages.isEmpty else { return .page(String(localized: "Use the release page. Local checks require a ZIP up to 256 MiB with a published SHA-256 digest.")) }
        let safe = packages.filter { !(blocked[path] ?? []).contains($0) }
        guard !safe.isEmpty else { return .blocked }
        let available = safe.filter { !(manualOnly[path] ?? []).contains($0) }
        guard !available.isEmpty else { return .page(String(localized: "Use the vendor’s installation instructions on the release page.")) }
        if let previous = checked[path], previous.release.id == release.id, previous.release.tag_name == release.tag_name, available.contains(previous.asset) {
            return .reveal(previous)
        }
        return .verify(available)
    }

    func candidate(_ result: UpdateResult) -> PersonalGitHubSource.Release? {
        let path = result.app.path.path
        guard !paused.contains(path), let snapshot = snapshots[path], let record = record(path), let local = PersonalGitHubSource.Version(record.anchor.version),
              let candidate = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable).first,
              let offered = PersonalGitHubSource.Version(candidate.tag_name), offered > local else { return nil }
        return candidate
    }
}
