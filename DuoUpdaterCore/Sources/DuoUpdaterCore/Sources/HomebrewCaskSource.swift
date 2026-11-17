import Foundation

/// Update source for apps Homebrew actually installed. Matches the installed
/// bundle to a Homebrew cask by its `.app` filename (falling back to bundle
/// identifier for `pkg` casks that declare no `.app` artifact, and then to the
/// cask whose installed package receipt lists this exact bundle), then — crucially
/// — only resolves when that cask is present in the local Caskroom.
///
/// The catalog match alone is not enough: many apps share a filename with a cask
/// but were installed straight from the vendor or the App Store. Updating those
/// through `brew` would mix distribution channels — different signing, possibly
/// different data locations — so we gate on `BrewLocalInventory` (provenance).
/// Apps that match a cask but weren't brew-installed simply fall through to the
/// next source (and, lacking one, end up "unknown" until a vendor rule covers
/// them) rather than being silently adopted by Homebrew.
public actor HomebrewCaskSource: UpdateSource {
    public nonisolated let name = "Homebrew"

    private let catalog: HomebrewCaskCatalog
    private let inventory: BrewLocalInventory
    private var ownershipTask: Task<[ThirdPartyCaskSource.Ownership], Never>?
    /// Injected like `SignatureVerifier`'s `osVersion`, and for the same reason:
    /// the pick below must be testable off whatever Mac the tests run on.
    private let hostOSVersion: String
    /// Which cask installed which bundles, from the Caskroom's links and the
    /// packages' receipts. Injected so a test need not read this Mac's `pkgutil`.
    private let readOwnership: @Sendable ([String]) async -> [ThirdPartyCaskSource.Ownership]

    public init(
        catalog: HomebrewCaskCatalog = .shared,
        inventory: BrewLocalInventory = BrewLocalInventory(),
        hostOSVersion: String = HostOS.numericVersion()
    ) {
        self.init(catalog: catalog, inventory: inventory, hostOSVersion: hostOSVersion) {
            await ThirdPartyCaskSource.ownership(in: $0, includeOfficial: true)
        }
    }

    init(
        catalog: HomebrewCaskCatalog,
        inventory: BrewLocalInventory,
        hostOSVersion: String = HostOS.numericVersion(),
        ownership: @escaping @Sendable ([String]) async -> [ThirdPartyCaskSource.Ownership]
    ) {
        self.catalog = catalog
        self.inventory = inventory
        self.hostOSVersion = hostOSVersion
        self.readOwnership = ownership
    }

    public func prewarm(_ apps: [InstalledApp]) async { ownershipTask = nil }
    public func invalidateMemo(for apps: [InstalledApp]) async { ownershipTask = nil }

    private func owners(of app: InstalledApp) async -> [ThirdPartyCaskSource.Ownership] {
        if ownershipTask == nil {
            let roots = inventory.caskroomPaths
            let read = readOwnership
            ownershipTask = Task { await read(roots) }
        }
        let path = app.path.standardizedFileURL.resolvingSymlinksInPath().path
        return await ownershipTask!.value.filter { $0.tap == "homebrew/cask" && $0.paths.contains(path) }
    }

    func ownsInstalledPath(_ app: InstalledApp) async -> Bool {
        !(await owners(of: app)).isEmpty
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        // App Store apps are managed by the store; a same-named/-id cask is a
        // different distribution channel (often with an unrelated version
        // scheme), so never resolve a MAS app to Homebrew.
        guard !app.isMASApp else { return nil }

        // Nothing in the Caskroom → the provenance gate below can never pass, so
        // decline before pulling the ~2 MB catalog over the network.
        guard !inventory.isEmpty else { return nil }

        let filename = app.path.lastPathComponent  // e.g. "TablePlus.app"
        var candidates = try await catalog.entries(forAppFilename: filename)
        if candidates.isEmpty, let bundleID = app.bundleID {
            candidates = try await catalog.entries(forBundleID: bundleID)
        }
        // A pkg cask may name neither: `karabiner-elements` installs
        // Karabiner-Elements.pkg, and its catalog entry has no `app` artifact and
        // no `uninstall: quit:` id. Its package's receipt does list the app, and
        // `owners(of:)` already reads it, so the cask is found by token from there.
        var foundByReceipt = false
        if candidates.isEmpty, !inventory.caskroomPaths.isEmpty {
            for owner in await owners(of: app) {
                if let entry = try await catalog.entry(forToken: owner.token) { candidates.append(entry) }
            }
            foundByReceipt = !candidates.isEmpty
        }
        guard !candidates.isEmpty else { return nil }

        // Provenance gate: only adopt this app if Homebrew actually installed one
        // of the matching casks here. A filename/id collision with an uninstalled
        // cask is not ours to update.
        //
        // Ask every candidate rather than only the one this Mac could install.
        // When a vendor splits an `.app` across two casks by macOS (`onyx`
        // `== 11…26`, `onyx@beta` `>= 27` — issue #638), the cask this Mac *can*
        // install and the cask it *did* install disagree for anyone who upgraded
        // macOS without switching casks, and answering "no cask" for them would
        // replace a correct row with `.unknown`. Installed beats runnable; among
        // several installed (not a shape brew allows for one `.app`, but the index
        // cannot know that) the host breaks the tie, via the one shared copy of
        // that rule.
        // Synthetic token-only inventories are a test seam. Real inventories
        // must associate this exact copy with the candidate, not just find a
        // same-named cask somewhere else on the machine.
        let owners = inventory.caskroomPaths.isEmpty ? [] : await owners(of: app)
        let installed = candidates.filter { entry in
            let names = Set(([entry.token] + entry.oldTokens).map { $0.lowercased() })
            if inventory.caskroomPaths.isEmpty {
                return names.contains { inventory.isOfficialCandidate(caskToken: $0) }
            }
            return owners.contains { names.contains($0.token.lowercased()) }
        }
        guard let entry = CaskEntry.preferred(among: installed, hostOSVersion: hostOSVersion)
        else { return nil }
        let names = Set(([entry.token] + entry.oldTokens).map { $0.lowercased() })
        let matchingOwners = owners.filter { names.contains($0.token.lowercased()) }
        for owner in matchingOwners { try HomebrewInstaller.validateOwnerPrefix(owner.brewPrefix) }
        // A real owner supplies its historical token and prefix. Never read a
        // same-token record from another Brew when matching an exact app path.
        let owner = matchingOwners.first
        let installedToken = owner?.token
            ?? ([entry.token] + entry.oldTokens).first { inventory.isOfficialCandidate(caskToken: $0) }
            ?? entry.token
        let recorded = inventory.installedVersion(caskToken: installedToken, brewPrefix: owner?.brewPrefix)
        // A receipt lists every app a package wrote, helpers included, and a
        // helper's version need not follow the cask's: one below the version
        // Homebrew recorded installing would be offered the cask's version as an
        // update it can never reach, so it is left alone. One at or past the
        // record is the cask's app. Past it is the ordinary state after an update
        // that did not go through brew — the app's own updater, or this source's
        // own `.installer` route for a package cask, which leaves the Caskroom
        // record behind. Requiring equality dropped Karabiner back to "no source"
        // after the first update DuoUpdater installed (real machine, 2026-11-09).
        // A copy past the catalog reads as up to date (`evaluate`), never as a
        // downgrade; Upgrade All's safety net still requires the record exactly
        // (`BrewAppCask.isAtRecord`).
        if foundByReceipt {
            guard let installedVersion = app.shortVersion,
                  let recorded = recorded?
                    .split(whereSeparator: { $0 == "," || $0 == ":" }).first,
                  VersionComparator.compare(String(recorded), installedVersion) != .orderedDescending
            else { return nil }
        }

        // Cask versions are sometimes "version,revision" or "version:build";
        // keep the leading marketing portion for bundle comparison. The complete
        // identity below drives Brew record decisions and suffix-only displays. Split on BOTH
        // separators — keying only on "," left the ":build" form (e.g. "1.2.3:456")
        // intact, which then mis-compares against the bare installed "1.2.3" and can
        // surface a spurious update.
        var marketing = entry.version
            .split(whereSeparator: { $0 == "," || $0 == ":" }).first
            .map(String.init) ?? entry.version

        // A packaging revision the bundle never carries (#1553): MKVToolNix's
        // cask is "102.0-2" while the app inside reads 102.0 / 102.0, so no
        // install can ever reach "102.0-2" and the row offers it forever. Once
        // Homebrew records that exact cask version as installed — `brew
        // outdated`'s own test — the bundle's spelling is the release, so offer
        // that instead. Before then the revision still shows as an update, as
        // it does in `brew outdated`.
        if let installed = app.shortVersion,
           recorded == entry.version,
           let dash = marketing.lastIndex(of: "-"),
           VersionComparator.compare(String(marketing[..<dash]), installed) == .orderedSame {
            marketing = String(marketing[..<dash])
        }

        var remote = RemoteVersion(
            shortVersion: marketing,
            version: nil,
            // No URL is what keeps a detection-only cask off the package route
            // (`UpdatePolicy.requiresInstaller`), the same way Xcode Releases
            // marks one: the download would be fetched in full only to be refused.
            downloadURL: entry.installKind == .detectionOnly ? nil : entry.url,
            // `entry.url` is the cask's artifact (a dmg/pkg on the vendor's CDN),
            // so the user-facing page is the cask's own listing instead.
            pageURL: URL(string: "https://formulae.brew.sh/cask/\(entry.token)"),
            sourceName: name,
            sourceIdentifier: entry.token,
            requiresManualInstaller: entry.installKind != .brew
        )
        // What brew will put on disk, for the reminder when that is not the
        // copy's own channel (`UpdateResult.replacesChannelWithStable`). This
        // source still answers for a nightly copy, on purpose: the user chose a
        // reminder over a gate, and the cask is what brew updates either way.
        if entry.isStandardStableCask { remote.offeredChannel = .stable }
        remote.homebrewSelfUpdating = entry.autoUpdates
        // Marketing baseline for downstream sources allowed by Brew fallback.
        // Brew itself compares the complete identities stored separately below.
        remote.homebrewRecordedVersion = recorded?
            .split(whereSeparator: { $0 == "," || $0 == ":" }).first
            .map(String.init)
        remote.homebrewCaskVersion = entry.version
        remote.homebrewInstalledCaskVersion = recorded
        remote.homebrewPinned = inventory.isPinned(caskToken: installedToken, brewPrefix: owner?.brewPrefix)
        return remote
    }
}
