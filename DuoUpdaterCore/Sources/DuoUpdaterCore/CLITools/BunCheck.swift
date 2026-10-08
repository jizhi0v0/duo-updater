import Foundation

/// bun's own row, as every tool's verdict is shaped (`CLIToolStatus`). Its
/// packages' rows are `NpmCheck`'s.
///
/// The rules:
/// 1. **The update is bun's own `bun upgrade`**, on the installer's file. It
///    installs what `BunRelease`'s channel names.
/// 2. **The trust rule** (`CLIToolTrust`): bun is Developer ID signed by Oven,
///    and the file is run only with that Team ID and no quarantine.
/// 3. **Never downgrade.** `bun upgrade` stops only when the channel's version is
///    the installed one; a build newer than the channel would be replaced by the
///    older one, so it reads as `.ahead` and gets no click.
/// 4. **A canary build is reported only**: `bun upgrade` on one installs the
///    newest canary, which has no version to compare with.
///
/// bun has no setting that turns its own update off — it never updates itself —
/// so there is no settings gate.
public struct BunCheck: Sendable {

    typealias Latest = @Sendable () async throws -> String

    let latest: Latest

    public init(release: BunRelease = BunRelease()) {
        self.init(latest: { try await release.latest() })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest) {
        self.latest = latest
    }

    public func status(of install: BunInstall, busy: BunActivity.Busy?) async -> CLIToolStatus {
        let channel = install.isCanary ? "canary" : "stable"
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .bun, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: channel, state: state, oneClick: oneClick, withheld: withheld, note: note,
                name: "bun", detail: .bun(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no version is compiled into the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version else {
            return verdict(.unknown, note: "no version to read", withheld: .versionUnreadable)
        }
        if install.isCanary {
            return verdict(.unknown, note: "a canary build: `bun upgrade` installs the newest canary, which has no version to compare",
                           withheld: .unsupportedInstaller)
        }
        let newest: String
        do {
            newest = try await latest()
        } catch {
            let limited = if case .rateLimited? = error as? BunRelease.Failure { true } else { false }
            return verdict(.unknown, note: "could not read bun's release channel: \(error)",
                           withheld: limited ? .rateLimited : .channelUnreadable)
        }
        let state: CLIToolState
        switch BunRelease.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        guard install.signature == .vendor else {
            return verdict(
                state, latest: newest,
                note: "not signed by Oven (Team \(BunScanner.teamIdentifier)): " + (install.signature?.rawValue ?? "unchecked"),
                withheld: .wrongSigner)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(for: install))
    }

    /// `~/.bun/bin/bun upgrade`. Nothing is put on `PATH` but the system's: it
    /// runs `unzip`, which is `/usr/bin/unzip`.
    static func updateCommand(for install: BunInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["upgrade"], pathPrefix: nil)
    }
}
