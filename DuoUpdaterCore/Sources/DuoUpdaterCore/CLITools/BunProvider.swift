import Foundation

/// bun as one of the app's command-line tools: one group, bun's own row and a
/// row per package its global install holds. bun's row is `BunScanner`,
/// `BunCheck` and `BunUpdater`'s; the packages' rows are read by `BunPackages`
/// and checked, updated and annotated by the npm group's code (`NpmCheck`,
/// `NpmUpdater`, `NpmChangelog`), which knows them by `NpmInstall.bun`.
public struct BunProvider: CLIToolProvider {
    public var kind: CLIToolKind { .bun }

    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan() async -> [CLIToolSighting] {
        let home = self.home
        return await offCooperativePool {
            guard let bun = BunScanner(home: home).scan() else { return [] }
            return [Self.sighting(bun)] + BunPackages(home: home).scan(bun: bun).map(Self.sighting)
        }
    }

    /// What bun's verdict rests on besides the version: quarantine and a problem.
    static func sighting(_ install: BunInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .bun, path: install.path, version: install.version,
            state: [install.revision, install.quarantined ? "quarantined" : nil, install.problem?.rawValue]
                .map { $0 ?? "-" }.joined(separator: "|"))
    }

    /// A package's: the npm group's rule, under bun's kind.
    static func sighting(_ install: NpmInstall) -> CLIToolSighting {
        let npm = NpmProvider.sighting(install)
        return CLIToolSighting(kind: .bun, path: npm.path, version: npm.version, state: npm.state)
    }

    public func check() async -> CLIToolReport {
        let home = self.home
        let (bun, packages, processes) = await offCooperativePool { () -> (BunInstall?, [NpmInstall], [NpmActivity.Process]) in
            let scanner = BunScanner(home: home)
            guard let bun = scanner.scan().map(scanner.withSignature) else { return (nil, [], []) }
            return (bun, BunPackages(home: home).scan(bun: bun), NpmActivity.runningProcesses())
        }
        // A node from the nodejs.org installer names no version in its layout.
        let versioned = await NpmProvider.withNodeVersions(packages)
        return await Self.report(bun: bun, packages: versioned, processes: processes, check: BunCheck(), npm: NpmCheck())
    }

    static func report(
        bun: BunInstall?, packages: [NpmInstall], processes: [NpmActivity.Process], check: BunCheck, npm: NpmCheck
    ) async -> CLIToolReport {
        guard let bun else { return CLIToolReport(kind: .bun, statuses: [], context: .bun, sightings: []) }
        var statuses = [await check.status(of: bun, busy: BunActivity.upgrading(bun: bun.path, processes: processes))]
        let busy = packages.reduce(into: [String: NpmActivity.Busy]()) {
            $0[$1.path] = BunActivity.busy($1, processes: processes)
        }
        statuses += await npm.statuses(of: packages) { busy[$0.path] }
        return CLIToolReport(
            kind: .bun, statuses: statuses, context: .bun, sightings: [sighting(bun)] + packages.map(sighting))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        switch status.detail {
        case .bun:
            return await BunUpdater().update(status, progress: progress)
        case .npm:
            return await NpmUpdater(
                busy: { BunActivity.busy($0, processes: NpmActivity.runningProcesses()) },
                trustsNode: { NpmUpdater.nodeIsTrustedNow($0) },
                trustsBun: { NpmUpdater.bunIsTrustedNow($0) },
                environment: { ProcessInfo.processInfo.environmentWithSystemProxy }
            ).update(status, progress: progress)
        default:
            return .notOffered
        }
    }

    /// A package's GitHub Releases, as the npm group reads them. bun's own
    /// releases carry no notes — each `bun-v` release's body is the same install
    /// and upgrade commands, and the notes are posts on bun.com's blog — so its
    /// row has an empty changelog, which the pane words as such.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard case .npm(let package) = status.detail else { return Changelog(entries: []) }
        return try await NpmChangelog.fetch(
            repository: package.install.repository, name: package.install.manifestName ?? package.install.name,
            versions: package.pending, force: force)
    }
}
