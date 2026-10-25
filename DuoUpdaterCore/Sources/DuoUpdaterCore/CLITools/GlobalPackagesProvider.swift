import Foundation

/// The packages of pnpm's or Yarn's global install as one of the app's
/// command-line tools: one group per tool, a row per package. Read by
/// `PnpmPackages` and `YarnPackages`, then checked, updated and annotated by the
/// npm group's code (`NpmCheck`, `NpmUpdater`, `NpmChangelog`), which knows them
/// by `NpmInstall.global` — as bun's packages are, without a row for the tool
/// itself: pnpm and Yarn are wherever their installers put them.
public struct GlobalPackagesProvider: CLIToolProvider {
    public let tool: GlobalPackageManager.Tool
    public var kind: CLIToolKind { tool == .pnpm ? .pnpm : .yarn }

    let home: URL

    public init(_ tool: GlobalPackageManager.Tool, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.tool = tool
        self.home = home
    }

    /// The packages, each against the copy of the tool that reads its install. Blocking.
    static func installs(_ tool: GlobalPackageManager.Tool, home: URL) -> [NpmInstall] {
        let managers = GlobalPackageManagers(home: home).discover(tool)
        switch tool {
        case .pnpm: return PnpmPackages(home: home).scan(managers: managers)
        case .yarn: return YarnPackages(home: home).scan(managers: managers)
        }
    }

    public func scan() async -> [CLIToolSighting] {
        let (tool, home, kind) = (self.tool, self.home, self.kind)
        return await offCooperativePool { Self.installs(tool, home: home) }.map { Self.sighting($0, kind: kind) }
    }

    /// The npm group's rule, under this tool's kind.
    static func sighting(_ install: NpmInstall, kind: CLIToolKind) -> CLIToolSighting {
        let npm = NpmProvider.sighting(install)
        return CLIToolSighting(kind: kind, path: npm.path, version: npm.version, state: npm.state)
    }

    public func check() async -> CLIToolReport {
        let (tool, home, kind) = (self.tool, self.home, self.kind)
        let (scanned, processes) = await offCooperativePool {
            (Self.installs(tool, home: home), NpmActivity.runningProcesses())
        }
        let installs = await NpmProvider.withNodeVersions(scanned)
        return await Self.report(kind: kind, installs: installs, sightings: scanned, processes: processes, npm: NpmCheck())
    }

    static func report(
        kind: CLIToolKind, installs: [NpmInstall], sightings: [NpmInstall], processes: [NpmActivity.Process], npm: NpmCheck
    ) async -> CLIToolReport {
        let busy = installs.reduce(into: [String: NpmActivity.Busy]()) {
            $0[$1.path] = GlobalPackageActivity.busy($1, processes: processes)
        }
        let statuses = await npm.statuses(of: installs) { busy[$0.path] }
        return CLIToolReport(
            kind: kind, statuses: statuses, context: kind == .pnpm ? .pnpm : .yarn,
            sightings: sightings.map { sighting($0, kind: kind) })
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        await NpmUpdater(
            busy: { GlobalPackageActivity.busy($0, processes: NpmActivity.runningProcesses()) },
            trustsNode: { NpmUpdater.nodeIsTrustedNow($0) },
            trustsManager: { NpmUpdater.managerIsTrustedNow($0) },
            environment: { ProcessInfo.processInfo.childEnvironmentWithSystemProxy }
        ).update(status, progress: progress)
    }

    /// A package's GitHub Releases, as the npm group reads them.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        guard case .npm(let package) = status.detail else { throw CLIToolReleaseNotesError.noSections }
        return try await NpmChangelog.fetch(
            repository: package.install.repository, name: package.install.manifestName ?? package.install.name,
            versions: package.pending, force: force)
    }
}
