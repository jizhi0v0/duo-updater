import AppKit
import DuoUpdaterCore
import Observation

@Observable @MainActor
final class PersonalSources {
    static let shared = PersonalSources()
    private static let registeredPersonalSourceConflicts = Set(
        GitHubReleaseRegistry.rules.map { $0.bundleID.lowercased() } +
        VendorProbeRegistry.recipes.map { $0.bundleID.lowercased() }
    )

    static func lacksBuiltInSource(_ result: UpdateResult) -> Bool {
        guard result.app.myGoUpdate == nil, result.app.electronUpdate == nil, result.app.sparkleFeedURL == nil,
              UpdateSourceGroup(result) == .other, !SetappCatalogSource.owns(result.app),
              !result.homebrewSelfUpdating, result.app.bundleID != XcodeReleasesSource.bundleID,
              !Self.registeredPersonalSourceConflicts.contains(result.app.recipeBundleID?.lowercased() ?? "")
        else { return false }
        return result.remote == nil && result.homebrewSourceIdentifier == nil && !result.app.isMASApp
            && OneClickGateRegistry.withholding(result.app, offering: result.remote) == nil
            && !result.app.isTestFlightApp && !result.app.isToolboxManaged && !result.app.isiOSAppOnMac
    }

    struct ReplacementGrant: Codable, Equatable {
        let id: UUID
        let path: String
        let requirement: String
    }

    struct BindingRecord: Codable, Equatable {
        var schema = 1
        var repository: PersonalGitHubSource.Repository
        var track: PersonalGitHubSource.Track
        // Existing records store the active channel here. Other channels only
        // need entries after a user gives them a nonempty filter.
        var filenameContains: String?
        var otherChannelFilters: [String: String]? = nil
        var channelFilters: [String: String] {
            var filters = otherChannelFilters ?? [:]
            filters[track.rawValue] = filenameContains
            return filters
        }
        var includeStable: Bool
        var anchor: PersonalSourceZIP.Identity
        var lastSuccessfulCheck: Date?
        var confirmedVersion: String?
        var highestInstalledVersion: String? = nil
        var replacementID: UUID? = nil
        var grant: ReplacementGrant? = nil
        var handoff: Handoff?

        func isKnownRollback(_ offered: String) -> Bool {
            guard let high = (highestInstalledVersion ?? confirmedVersion).flatMap(PersonalGitHubSource.Version.init),
                  let candidate = PersonalGitHubSource.Version(offered) else { return false }
            return candidate < high
        }
    }
    struct Handoff: Codable, Equatable, Sendable {
        let releaseID: Int64
        let tag: String
        let asset: PersonalGitHubSource.Asset
        let identity: PersonalSourceZIP.Identity
        let manifest: BackupManifest

        func matches(_ release: PersonalGitHubSource.Release) -> Bool {
            release.id == releaseID && release.tag_name == tag && release.assets.contains(asset)
        }

        func isInvalidated(by snapshot: PersonalGitHubSource.Snapshot) -> Bool {
            if let release = snapshot.releases.first(where: { $0.id == releaseID }) {
                return !matches(release)
            }
            // Releases outside the fetched pages can still be published.
            return !snapshot.truncated
        }
    }
    struct Checked {
        let release: PersonalGitHubSource.Release
        let asset: PersonalGitHubSource.Asset
        var replacementRequirement: String? = nil
        var replacementIssue: String? = nil
        let directory: URL
        let application: URL
        let identity: PersonalSourceZIP.Identity
        let manifest: BackupManifest

        func permitsReplacement(using binding: BindingRecord) -> Bool {
            replacementRequirement != nil && release.tagIssue == nil && !binding.isKnownRollback(identity.version)
        }
    }
    private let key = "personalGitHubSources"
    private let credentials: GitHubCredentials
    private let defaults: UserDefaults
    private(set) var records: [String: Data]
    private var snapshots: [String: PersonalGitHubSource.Snapshot] = [:]
    private(set) var credentialRevision = 0
    private(set) var repositoryRevision = 0
    private var deniedRepositoryIDs: [Int64: Int] = [:]
    private var deniedRepositoryNames: [String: Int] = [:]
    private(set) var needsGitHubSettings = Set<String>()
    var messages: [String: String] = [:]
    var busy = Set<String>()
    var checked: [String: Checked] = [:]
    // A revealed directory belongs to the pending Finder handoff, even when a
    // newer release replaces checked[path]. Only delete paths created in this process.
    private var revealedDirectories: [String: URL] = [:]
    var blocked: [String: [PersonalGitHubSource.Asset]] = [:]
    var manualOnly: [String: [PersonalGitHubSource.Asset]] = [:]
    var paused = Set<String>()
    init(defaults: UserDefaults = .standard, credentials: GitHubCredentials = .shared) {
        self.credentials = credentials
        self.defaults = defaults
        records = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
    }

    // SwiftUI observes this revision because the Core credential state is lock-backed.
    func accessible(_ snapshot: PersonalGitHubSource.Snapshot?, since revision: Int) -> PersonalGitHubSource.Snapshot? {
        _ = credentialRevision
        guard let snapshot, snapshot.isAccessibleWithCurrentCredentials,
              accessUnchanged(name: snapshot.repository.full_name, id: snapshot.repository.id, since: revision) else { return nil }
        return snapshot
    }

    func snapshot(for path: String) -> PersonalGitHubSource.Snapshot? {
        accessible(snapshots[path], since: repositoryRevision)
    }

    private func accessUnchanged(name: String, id: Int64?, since revision: Int) -> Bool {
        deniedRepositoryNames[name.lowercased(), default: 0] <= revision
            && (id.flatMap { deniedRepositoryIDs[$0] } ?? 0) <= revision
    }

    func repositoryDenied(_ input: String, id: Int64?, since revision: Int, message: String) {
        guard let name = PersonalGitHubSource.slug(input)?.lowercased(),
              accessUnchanged(name: name, id: id, since: revision) else { return }
        let bindings = records.keys.compactMap { path in record(path).map { (path, $0.repository) } }
        var repositoryIDs = Set(bindings.filter { $0.1.full_name.lowercased() == name }.map { $0.1.id })
        if let id { repositoryIDs.insert(id) }
        repositoryRevision &+= 1
        deniedRepositoryNames[name] = repositoryRevision
        for repositoryID in repositoryIDs { deniedRepositoryIDs[repositoryID] = repositoryRevision }
        for (path, repository) in bindings where repositoryIDs.contains(repository.id) {
            deniedRepositoryNames[repository.full_name.lowercased()] = repositoryRevision
            clear(path)
            paused.insert(path)
            needsGitHubSettings.insert(path)
            messages[path] = message
        }
    }

    /// A current request can prove repository-wide denial even if the user
    /// edited or removed the originating binding while the request was in flight.
    private func handleFailure(_ error: Error, for binding: BindingRecord, path: String,
                               generation: Int, revision: Int) -> Bool {
        let repo = binding.repository
        guard credentials.generation == generation, accessUnchanged(name: repo.full_name, id: repo.id, since: revision) else {
            return false
        }
        if (error as? PersonalGitHubSource.Failure)?.confirmsRepositoryDenial == true {
            repositoryDenied(repo.full_name, id: repo.id, since: revision, message: error.localizedDescription)
        }
        return record(path) == binding
    }

    func credentialsDidChange(rejected: Bool = false) {
        credentialRevision &+= 1
        // A rejected token can still yield a public result or an access error
        // through the in-flight query’s anonymous retry.
        if !rejected { busy.removeAll() }
        for path in records.keys where snapshots[path]?.isAccessibleWithCurrentCredentials == false {
            // An open Settings request belongs to the error's button. Keep that
            // button mounted while its credential resolution and retry complete.
            let requestedSettings = needsGitHubSettings.contains(path)
            clear(path)
            if requestedSettings { needsGitHubSettings.insert(path) }
        }
    }

    func record(_ path: String) -> BindingRecord? {
        guard let data = records[path], let record = try? JSONDecoder().decode(BindingRecord.self, from: data), (1...2).contains(record.schema) else { return nil }
        return record
    }

    func record(_ path: String, matchingRepository input: String) -> BindingRecord? {
        guard let record = record(path), let slug = PersonalGitHubSource.slug(input),
              slug.lowercased() == record.repository.full_name.lowercased() else { return nil }
        return record
    }

    func saveConfiguration(
        for app: URL, repository input: String, track: PersonalGitHubSource.Track,
        filters: [String: String], includeStable: Bool,
        validation: (snapshot: PersonalGitHubSource.Snapshot, anchor: PersonalSourceZIP.Identity, revision: Int)? = nil
    ) throws {
        let path = app.path
        let previous = record(path)
        guard previous?.replacementID == nil else { throw PersonalGitHubSource.Failure("Review the pending installation first.") }
        var updated: BindingRecord
        if let validation {
            guard accessible(validation.snapshot, since: validation.revision) != nil else {
                throw PersonalGitHubSource.Failure("GitHub credentials changed. Try again.")
            }
            if let previous, previous.anchor == validation.anchor,
               previous.repository.id == validation.snapshot.repository.id,
               previous.repository.owner.id == validation.snapshot.repository.owner.id {
                updated = previous
            } else {
                updated = BindingRecord(
                    repository: validation.snapshot.repository, track: track, filenameContains: nil,
                    includeStable: false, anchor: validation.anchor)
            }
            if let previous, previous.repository.id == updated.repository.id,
               previous.repository.owner.id == updated.repository.owner.id,
               previous.anchor.bundle == updated.anchor.bundle, previous.anchor.team == updated.anchor.team {
                updated.highestInstalledVersion = previous.highestInstalledVersion ?? previous.confirmedVersion
            }
            updated.repository = validation.snapshot.repository
            updated.lastSuccessfulCheck = validation.snapshot.checked
            if let pending = updated.handoff, pending.isInvalidated(by: validation.snapshot) { updated.handoff = nil }
        } else {
            guard let saved = record(path, matchingRepository: input) else {
                throw PersonalGitHubSource.Failure("Validate the repository before saving.")
            }
            updated = saved
        }
        guard try PersonalSourceZIP.Identity(at: app) == updated.anchor else {
            throw PersonalGitHubSource.Failure("Installation changed. Validate again.")
        }
        let nonemptyFilters = filters.filter { !$0.value.isEmpty }
        updated.track = track
        updated.filenameContains = nonemptyFilters[track.rawValue]
        updated.otherChannelFilters = nonemptyFilters.filter { $0.key != track.rawValue }
        updated.includeStable = track != .stable && includeStable
        if previous?.track != updated.track || previous?.filenameContains != updated.filenameContains ||
            previous?.includeStable != updated.includeStable {
            updated.grant = nil
        }
        try save(updated, path: path)
        if let validation {
            if updated.handoff == nil {
                clear(path)
            } else {
                paused.remove(path)
                needsGitHubSettings.remove(path)
            }
            snapshots[path] = validation.snapshot
        }
    }

    func save(_ record: BindingRecord, path: String) throws {
        records[path] = try JSONEncoder().encode(record)
        defaults.set(records, forKey: key)
        if record.handoff == nil { releaseFinderDirectory(path) }
    }

    func remove(_ path: String) {
        guard record(path)?.replacementID == nil else { return }
        records.removeValue(forKey: path)
        defaults.set(records, forKey: key)
        clear(path)
        releaseFinderDirectory(path)
    }

    private func discardChecked(_ path: String) {
        if let old = checked.removeValue(forKey: path), old.directory != revealedDirectories[path] {
            try? FileManager.default.removeItem(at: old.directory)
        }
    }

    private func releaseFinderDirectory(_ path: String) {
        if let directory = revealedDirectories.removeValue(forKey: path), directory != checked[path]?.directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // A failed lookup invalidates the current results. The file already shown
    // in Finder lives as long as its saved handoff, including during outages.
    private func clear(_ path: String, preservingReleaseHistory: Bool = false) {
        discardChecked(path)
        if !preservingReleaseHistory { snapshots[path] = nil }
        paused.remove(path)
        blocked[path] = nil
        manualOnly[path] = nil
        needsGitHubSettings.remove(path)
        messages[path] = nil
    }

    /// One result per repository and credential generation in a scan, including
    /// failures. Another local installation can choose a track from the same result.
    func refreshRegistered(_ apps: [InstalledApp]) async {
        var round: [String: (result: Result<PersonalGitHubSource.Snapshot, Error>, revision: Int)] = [:]
        var generation = credentialRevision
        for app in apps {
            await refresh(app) { slug in
                let currentGeneration = credentialRevision
                if generation != currentGeneration {
                    round.removeAll()
                    generation = currentGeneration
                }
                let key = slug.lowercased()
                if let cached = round[key] {
                    switch cached.result {
                    case .success(let snapshot):
                        if accessible(snapshot, since: cached.revision) != nil { return snapshot }
                    case .failure(let error):
                        // A confirmed denial was already applied to every bound
                        // copy. Replaying it must not revoke a later validation.
                        if let failure = error as? PersonalGitHubSource.Failure, failure.confirmsRepositoryDenial {
                            if let recovered = snapshot(for: app.path.path) { return recovered }
                            throw PersonalGitHubSource.Failure(failure.localizedDescription, .repositoryAccess)
                        }
                        throw error
                    }
                }
                let revision = repositoryRevision
                do {
                    let result = try await PersonalGitHubClient.shared.fetch(slug)
                    round[key] = (.success(result), revision)
                    return result
                } catch {
                    round[key] = (.failure(error), revision)
                    throw error
                }
            }
        }
    }

    func refresh(_ app: InstalledApp, fetch: @MainActor (String) async throws -> PersonalGitHubSource.Snapshot = {
        try await PersonalGitHubClient.shared.fetch($0)
    }) async {
        let path = app.path.path
        guard !recovering.contains(path), !installing.contains(path), var record = record(path),
              record.replacementID == nil, busy.insert(path).inserted else { return }
        let generation = credentials.generation
        let revision = repositoryRevision
        defer { if credentials.generation == generation { busy.remove(path) } }
        do {
            guard let continued = try await reconcileInstallation(app.path, record: record) else { return }
            record = continued
            guard credentials.generation == generation else { return }
            let snapshot = try await fetch(record.repository.full_name)
            guard credentials.generation == generation, accessible(snapshot, since: revision) != nil, self.record(path) == record else { return }
            try validateRepository(snapshot, record: record)
            var updated = record
            updated.lastSuccessfulCheck = snapshot.checked
            updated.repository = snapshot.repository
            if let handoff = updated.handoff, handoff.isInvalidated(by: snapshot) { updated.handoff = nil }
            try save(updated, path: path)
            needsGitHubSettings.remove(path)
            paused.remove(path)
            if let old = checked[path] {
                let latest = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable).first
                if latest?.id != old.release.id || latest?.tag_name != old.release.tag_name || latest?.assets.contains(old.asset) != true {
                    discardChecked(path)
                }
            }
            snapshots[path] = snapshot
            if updated.handoff != nil {
                messages[path] = "Waiting for manual installation at \(path)."
            } else {
                messages[path] = updated.confirmedVersion.map { String(localized: "Confirmed installation of \($0).") }
            }
        } catch {
            guard handleFailure(error, for: record, path: path, generation: generation, revision: revision) else { return }
            let last = record.lastSuccessfulCheck
            let disposition = (error as? PersonalGitHubSource.Failure)?.disposition
            if disposition == .reviewSource || disposition == .repositoryAccess { clear(path) }
            needsGitHubSettings.remove(path)
            if disposition?.needsGitHubSettings == true { needsGitHubSettings.insert(path) }
            paused.insert(path)
            messages[path] = error.localizedDescription + (last.map { " Last successful check: " + $0.formatted() } ?? "")
        }
    }

    /// Called from the existing local rescan as well as a repository refresh.
    /// Reading a manual handoff does not depend on network access.
    func reconcileLocal(_ app: InstalledApp) async {
        let path = app.path.path
        guard !recovering.contains(path), !installing.contains(path), let record = record(path),
              record.replacementID == nil, !busy.contains(path) else { return }
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
        if !continued.isKnownRollback(actual.version) { continued.highestInstalledVersion = actual.version }
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
        guard !installing.contains(path), !recovering.contains(path), let record = record(path), record.replacementID == nil, eligible(), busy.insert(path).inserted else { return }
        let generation = credentials.generation
        let revision = repositoryRevision
        defer { if credentials.generation == generation { busy.remove(path) } }
        needsGitHubSettings.remove(path)
        var localInspection = false
        var scratch: URL?
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        do {
            let fresh = try await PersonalGitHubClient.shared.fetch(record.repository.full_name)
            guard credentials.generation == generation, accessible(fresh, since: revision) != nil else { return }
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
            localInspection = false
            guard credentials.generation == generation, accessible(fresh, since: revision) != nil, self.record(path) == record, eligible() else { throw PersonalGitHubSource.Failure("The source or update route changed.") }
            if reveal {
                guard let previousCheck = checked[path], identity == previousCheck.identity, manifest == previousCheck.manifest else { throw PersonalGitHubSource.Failure("The staged package changed.") }
                try recordHandoff(record, checked: previousCheck, path: path)
                NSWorkspace.shared.activateFileViewerSelecting([candidate])
                messages[path] = "Waiting for manual installation at \(path)."
            } else {
                discardChecked(path)
                let route = await offCooperativePool { () -> Result<String, Error> in
                    Result {
                        let requirement = try PersonalSourceReplacement.signingRequirement(at: result.app.path)
                        try PersonalSourceReplacement.verifyRoute(installed: result.app.path, candidate: candidate,
                                                                 requirement: record.grant?.requirement ?? requirement)
                        return requirement
                    }
                }
                guard credentials.generation == generation, accessible(fresh, since: revision) != nil,
                      self.record(path) == record, eligible() else { throw PersonalGitHubSource.Failure("The source changed.") }
                var package = Checked(release: release, asset: asset, directory: directory, application: candidate,
                                      identity: identity, manifest: manifest)
                switch route {
                case .success(let requirement): package.replacementRequirement = requirement
                case .failure(let error): package.replacementIssue = error.localizedDescription
                }
                checked[path] = package
                scratch = nil
                messages[path] = "Verified \(identity.version) · \(identity.team ?? "") · SHA-256 matched."
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled,
                  handleFailure(error, for: record, path: path, generation: generation, revision: revision) else { return }
            switch (error as? PersonalGitHubSource.Failure)?.disposition {
            case .anonymousLimit: needsGitHubSettings.insert(path)
            case .repositoryAccess:
                clear(path)
                needsGitHubSettings.insert(path)
                paused.insert(path)
            case .releasePage: manualOnly[path, default: []].append(asset)
            case .reviewSource: snapshots[path] = nil
            case .blocked: blocked[path, default: []].append(asset)
            default:
                if localInspection { blocked[path, default: []].append(asset) }
            }
            discardChecked(path)
            messages[path] = error.localizedDescription
        }
    }

    private var installing = Set<String>()
    var recovering = Set<String>()
    private var installTasks: [String: Task<Void, Never>] = [:]

    func setReplacement(_ enabled: Bool, path: String, expected: BindingRecord? = nil) throws {
        guard var record = record(path) else { return }
        if enabled {
            guard record.replacementID == nil, record == expected, let checked = checked[path], checked.permitsReplacement(using: record), let requirement = checked.replacementRequirement,
                  try PersonalSourceZIP.Identity(at: URL(fileURLWithPath: path)) == record.anchor else {
                throw PersonalGitHubSource.Failure("Verify the current package before enabling replacement.")
            }
            // V1 preserves unknown schemas without rewriting them. Once this
            // copy can have a transaction, its recovery pointer must survive a downgrade.
            record.schema = 2
            record.grant = ReplacementGrant(id: UUID(), path: path, requirement: requirement)
        } else { record.grant = nil }
        try save(record, path: path)
    }

    func cancelReplacement(_ path: String) {
        guard record(path)?.replacementID == nil else { return }
        installTasks[path]?.cancel()
    }
    func replacing(_ path: String) -> Bool { installing.contains(path) }

    func startReplacement(_ result: UpdateResult, package: Checked, installed: @escaping @MainActor () async -> Void,
                          eligible: @escaping @MainActor () -> Bool) {
        let path = result.app.path.path
        guard let binding = record(path), binding.replacementID == nil, let grant = binding.grant, grant.path == path,
              !recovering.contains(path),
              !busy.contains(path), installing.insert(path).inserted else { return }
        busy.insert(path)
        installTasks[path] = Task {
            defer { installing.remove(path); busy.remove(path); installTasks[path] = nil }
            do {
                if try await replace(result, binding: binding, grant: grant, package: package, eligible: eligible) {
                    await installed()
                }
            } catch {
                messages[path] = error is CancellationError ? String(localized: "Update canceled.") : error.localizedDescription
            }
        }
    }

    private func replace(_ result: UpdateResult, binding: BindingRecord, grant: ReplacementGrant, package: Checked,
                         eligible: @escaping @MainActor () -> Bool) async throws -> Bool {
        let target = result.app.path
        let path = target.path
        guard package.permitsReplacement(using: binding) else { return false }
        let generation = credentials.generation
        let revision = repositoryRevision
        func validateLocal() throws {
            try Task.checkCancellation()
            guard record(path) == binding, eligible(), checked[path]?.identity == package.identity,
                  credentials.generation == generation, candidate(result)?.id == package.release.id,
                  !recovering.contains(path) else { throw PersonalGitHubSource.Failure("The source or authorization changed.") }
        }
        func validateRelease() async throws {
            let fresh: PersonalGitHubSource.Snapshot
            do { fresh = try await PersonalGitHubClient.shared.fetch(binding.repository.full_name) }
            catch {
                _ = handleFailure(error, for: binding, path: path, generation: generation, revision: revision)
                throw error
            }
            try validateLocal()
            try validateRepository(fresh, record: binding)
            guard accessible(fresh, since: revision) != nil,
                  let latest = fresh.matches(track: binding.track, installed: binding.anchor.version, includeStable: binding.includeStable).first,
                  latest.id == package.release.id, latest.tag_name == package.release.tag_name, latest.tagIssue == nil,
                  latest.assets.contains(package.asset), package.asset.matches(filename: binding.filenameContains) else {
                throw PersonalGitHubSource.Failure("The release or asset changed. Verify it again.")
            }
        }
        try validateLocal()
        let lock = try InstallLock.acquire()
        defer { lock.release() }
        try await validateRelease()
        // A personal source must never close a running app during preparation.
        // The install path checks this again immediately before moving it.
        try await offCooperativePool { try PersonalSourceReplacement.checkStopped(target) }
        let plan = try await offCooperativePool {
            try PersonalSourceReplacement.prepare(target: target, app: package.application, anchor: binding.anchor,
                checked: package.identity, manifest: package.manifest, authorization: grant.id,
                repository: binding.repository, track: binding.track, release: package.release, asset: package.asset)
        }
        let directory = plan.preparationDirectory
        defer { try? FileManager.default.removeItem(at: directory) }
        try validateLocal()
        let staged = directory.appendingPathComponent("Candidate.app")
        let inspected = try await PersonalSourceZIP.inspect(app: staged, installed: target, anchor: binding.anchor, tag: package.release.tag_name)
        guard inspected == plan.candidate else { throw PersonalGitHubSource.Failure("The staged app changed.") }
        try await offCooperativePool {
            try PersonalSourceReplacement.verifyRoute(installed: target, candidate: staged, requirement: grant.requirement)
        }
        try await validateRelease()
        try validateLocal()
        return try await InstallCommit.run("personal GitHub update", landed: { $0 }) { @MainActor in
            guard self.record(path) == binding, eligible(), self.checked[path]?.identity == package.identity,
                  self.credentials.generation == generation, self.accessible(self.snapshots[path], since: revision) != nil,
                  self.installTasks[path]?.isCancelled == false else { throw CancellationError() }
            var committingBinding = binding
            committingBinding.replacementID = plan.preparationID
            try self.save(committingBinding, path: path)
            do {
                guard self.defaults.synchronize() else { throw PersonalGitHubSource.Failure("Cannot save the recovery record.") }
                try await offCooperativePool { try plan.commit() }
            } catch {
                switch await self.reconcileReplacement(target) {
                case .installed: return true
                case .needsReview: return false
                case .original: throw error
                }
            }
            return await self.reconcileReplacement(target) == .installed
        }
    }

    enum ReplacementSettlement { case installed, original, needsReview }

    @discardableResult
    func reconcileReplacement(
        _ target: URL,
        reconcile: @MainActor (PersonalSourceReplacement) async throws -> PersonalSourceReplacement.Outcome = { plan in
            try await offCooperativePool { try plan.reconcile() }
        }
    ) async -> ReplacementSettlement {
        let path = target.path
        do {
            guard var saved = record(path), let transaction = saved.replacementID else { return .needsReview }
            guard let plan = try PersonalSourceReplacement.load(for: target) else {
                guard try PersonalSourceZIP.Identity(at: target) == saved.anchor else {
                    throw PersonalGitHubSource.Failure("Recovery record is missing. Review the installation.")
                }
                saved.replacementID = nil
                try save(saved, path: path)
                recovering.remove(path)
                return .original
            }
            guard plan.preparationID == transaction, saved.repository.id == plan.repositoryID,
                  saved.repository.owner.id == plan.ownerID, [plan.original, plan.candidate, plan.backupIdentity].contains(saved.anchor) else {
                throw PersonalGitHubSource.Failure("The recovery record does not match this installation.")
            }
            let outcome = try await reconcile(plan)
            guard var current = record(path), current.replacementID == transaction,
                  current.repository.id == plan.repositoryID, current.repository.owner.id == plan.ownerID,
                  [plan.original, plan.candidate, plan.backupIdentity].contains(current.anchor) else {
                throw PersonalGitHubSource.Failure("Source changed during recovery. Review the installation.")
            }
            switch outcome {
            case .installed:
                current.anchor = plan.candidate
                current.confirmedVersion = plan.candidate.version
                current.highestInstalledVersion = plan.candidate.version
                current.handoff = nil
            case .restoredBackup:
                current.anchor = plan.backupIdentity
            case .original:
                current.anchor = plan.original
            case .needsReview:
                throw PersonalGitHubSource.Failure("Installation changed during recovery. Review the installed app and recovery files.")
            }
            try save(current, path: path)
            guard defaults.synchronize() else { throw PersonalGitHubSource.Failure("Cannot save the installation result.") }
            try FileManager.default.removeItem(at: PersonalSourceReplacement.directory(for: target))
            current.replacementID = nil
            try save(current, path: path)
            discardChecked(path)
            recovering.remove(path)
            if outcome == .installed {
                messages[path] = String(localized: "Confirmed installation of \(plan.candidate.version).")
                return .installed
            }
            messages[path] = String(localized: "The original app is in place. Verify the update again.")
            return .original
        } catch {
            recovering.insert(path)
            messages[path] = error.localizedDescription
            return .needsReview
        }
    }

    func recoverReplacements() async {
        for path in Array(records.keys) where !busy.contains(path) && !installing.contains(path) {
            guard record(path)?.replacementID != nil,
                  let lock = try? InstallLock.acquire() else { continue }
            defer { lock.release() }
            busy.insert(path)
            await reconcileReplacement(URL(fileURLWithPath: path))
            busy.remove(path)
        }
    }

    func keepCurrentApp(_ target: URL) throws -> URL? {
        let path = target.path
        guard recovering.contains(path), !busy.contains(path), !installing.contains(path),
              var binding = record(path), binding.replacementID != nil else { return nil }
        let lock = try InstallLock.acquire()
        defer { lock.release() }
        let actual = try PersonalSourceZIP.Identity(at: target)
        let archive = try PersonalSourceReplacement.archiveRecovery(for: target)
        binding.replacementID = nil
        binding.grant = nil
        binding.handoff = nil
        try save(binding, path: path)
        recovering.remove(path)
        clear(path)
        if actual != binding.anchor {
            messages[path] = "The installation changed (now \(actual.version)). Review the source to continue."
        }
        return archive
    }

    func recordHandoff(_ record: BindingRecord, checked: Checked, path: String) throws {
        var pending = record
        pending.handoff = Handoff(releaseID: checked.release.id, tag: checked.release.tag_name, asset: checked.asset,
                                  identity: checked.identity, manifest: checked.manifest)
        try save(pending, path: path)
        releaseFinderDirectory(path)
        revealedDirectories[path] = checked.directory
    }

    func needsAction(_ result: UpdateResult) -> Bool {
        guard let release = candidate(result) else { return false }
        return record(result.app.path.path)?.handoff?.matches(release) != true
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

    enum ReleaseState: Equatable {
        case unavailable
        case current
        case update(PersonalGitHubSource.Release)
    }

    func releaseState(for result: UpdateResult) -> ReleaseState {
        let path = result.app.path.path
        guard !recovering.contains(path), !paused.contains(path), let snapshot = snapshot(for: path), let record = record(path), let local = PersonalGitHubSource.Version(record.anchor.version),
              let candidate = snapshot.matches(track: record.track, installed: record.anchor.version, includeStable: record.includeStable).first,
              let offered = PersonalGitHubSource.Version(candidate.tag_name) else { return .unavailable }
        if offered > local { return .update(candidate) }
        if offered == local, record.handoff == nil { return .current }
        return .unavailable
    }

    func candidate(_ result: UpdateResult) -> PersonalGitHubSource.Release? {
        guard case .update(let release) = releaseState(for: result) else { return nil }
        return release
    }
}
