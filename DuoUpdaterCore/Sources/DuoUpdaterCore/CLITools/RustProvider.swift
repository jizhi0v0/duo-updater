import Foundation

/// rustup and the toolchains it keeps on a channel, as one of the app's
/// command-line tools: one group, a row for rustup and one for each toolchain
/// that follows a channel (`Rust*`), seen through `CLIToolProvider`.
public struct RustProvider: CLIToolProvider {
    public var kind: CLIToolKind { .rust }

    let scanner: RustScanner
    let release: RustRelease
    let processes: @Sendable () -> [ClaudeCodeActivity.Process]

    public init() {
        self.init(scanner: RustScanner(), release: RustRelease())
    }

    /// The seam for tests and for a scratch install: other homes, another
    /// server reader, another process table.
    init(
        scanner: RustScanner, release: RustRelease,
        processes: @escaping @Sendable () -> [ClaudeCodeActivity.Process] = { ClaudeCodeActivity.runningProcesses() }
    ) {
        self.scanner = scanner
        self.release = release
        self.processes = processes
    }

    /// Reads rustup's binary (for its hash and the version it claims) and each
    /// toolchain's manifest; runs nothing.
    public func scan() async -> [CLIToolSighting] {
        let scanner = self.scanner
        let (rustup, toolchains) = await offCooperativePool { (scanner.rustup(), scanner.toolchains()) }
        return Self.sightings(rustup: rustup, toolchains: toolchains)
    }

    /// What a verdict rests on besides the version: rustup's sha256 and
    /// quarantine; a toolchain's recorded channel hash.
    static func sightings(rustup: RustScanner.Rustup?, toolchains: [RustScanner.Toolchain]) -> [CLIToolSighting] {
        let first = rustup.map {
            CLIToolSighting(
                kind: .rust, path: $0.path, version: $0.claimedVersion,
                state: [$0.sha256, $0.quarantined ? "quarantined" : nil, $0.problem?.rawValue]
                    .map { $0 ?? "-" }.joined(separator: "|"))
        }
        return [first].compactMap { $0 } + toolchains.map {
            CLIToolSighting(kind: .rust, path: $0.path, version: $0.version?.display,
                            state: [$0.updateHash, $0.problem?.rawValue].map { $0 ?? "-" }.joined(separator: "|"))
        }
    }

    public func check() async -> CLIToolReport {
        let (scanner, processes) = (self.scanner, self.processes)
        let (rustup, toolchains, settings, running) = await offCooperativePool {
            (scanner.rustup(), scanner.toolchains(), RustupSettings.read(rustupHome: scanner.rustupHome), processes())
        }
        return await Self.report(
            rustup: rustup, toolchains: toolchains, settings: settings,
            busy: RustActivity.busy(processes: running), check: RustCheck(release: release))
    }

    static func report(
        rustup: RustScanner.Rustup?, toolchains: [RustScanner.Toolchain], settings: RustupSettings,
        busy: RustActivity.Busy?, check: RustCheck
    ) async -> CLIToolReport {
        var statuses: [CLIToolStatus] = []
        var rustupStatus: CLIToolStatus?
        var trusted: RustItem.TrustedRustup?
        if let rustup {
            let row = await check.rustupStatus(rustup, settings: settings, busy: busy)
            (rustupStatus, trusted) = (row.status, row.trusted)
            statuses.append(row.status)
        }
        let updater = RustCheck.Updater(rustup: rustup, status: rustupStatus, trusted: trusted)
        for toolchain in toolchains {
            statuses.append(await check.toolchainStatus(toolchain, updater: updater, busy: busy))
        }
        return CLIToolReport(
            kind: .rust, statuses: statuses, context: .rust(settings),
            sightings: sightings(rustup: rustup, toolchains: toolchains))
    }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        let scanner = self.scanner
        let processes = self.processes
        return await RustUpdater(
            scanner: scanner, release: release,
            busy: { RustActivity.busy(processes: processes()) },
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            settings: { RustupSettings.read(rustupHome: scanner.rustupHome) }
        ).update(status, progress: progress)
    }

    /// rustup's `CHANGELOG.md` for the rustup row, Rust's `RELEASES.md` for a
    /// toolchain's (`RustChangelog`), by the status's `releaseNotesKey`.
    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        // A beta or nightly toolchain: no document has its sections.
        guard status.releaseNotesKey == "rustup" || status.releaseNotesKey == "rust" else {
            return Changelog(entries: [])
        }
        let isRustup = status.releaseNotesKey == "rustup"
        var request = URLRequest(url: isRustup ? RustChangelog.rustupSource : RustChangelog.rustSource)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.http(http.statusCode)
        }
        let parsed = await offCooperativePool {
            let text = String(decoding: data, as: UTF8.self)
            return isRustup ? RustChangelog.parseRustup(text) : RustChangelog.parseRust(text)
        }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
