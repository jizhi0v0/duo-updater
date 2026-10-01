import Foundation

/// One uv install's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules, as agreed for uv:
/// 1. **Only the standalone installer's copy is updated, by uv's own `uv self
///    update`** — a regular file in the directory its official receipt names
///    (`UvInstall.Layout.standalone`). A link (`uv tool install uv`, pipx) or a
///    copy no receipt names is reported only: `uv self update` refuses both.
/// 2. **The trust rule** (`CLIToolTrust`): a copy signed by Astral's Team is run;
///    an unsigned one (every release up to 0.12.11) is run only once a click has
///    found it byte for byte the published release (`UvVerifier`). A copy found
///    not to be is withheld as `.unverified`, and stays so until the file
///    changes.
/// 3. **What the file is must be what the receipt says.** `uv self update`
///    trusts its own compiled version over the receipt's, so a disagreement does
///    not misdirect the update — but it means the copy is not the release the
///    receipt recorded, which is what the hash check compares against.
/// 4. **Never race an update already running** (`UvActivity`).
///
/// uv has no auto-update and no setting that turns `self update` off, so there is
/// no settings gate.
public struct UvCheck: Sendable {

    /// The newest release with an archive for an architecture (`UvRelease`).
    typealias Latest = @Sendable (String) async throws -> String
    /// An executable's architecture, in uv's archive spelling. Blocking.
    typealias Architecture = @Sendable (URL) -> String?

    let latest: Latest
    let architecture: Architecture

    public init(release: UvRelease = UvRelease()) {
        self.init(latest: { try await release.latest(arch: $0) }, architecture: UvScanner.architecture)
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, architecture: @escaping Architecture = { _ in "aarch64" }) {
        self.latest = latest
        self.architecture = architecture
    }

    /// Every install's status, asking the manifest at most once per architecture.
    public func statuses(of installs: [UvInstall], busy: UvActivity.Busy?) async -> [CLIToolStatus] {
        var cached: [String: Result<String, Error>] = [:]
        var statuses: [CLIToolStatus] = []
        for install in installs {
            let architecture = self.architecture
            let arch = await offCooperativePool {
                install.executable.flatMap { architecture(URL(fileURLWithPath: $0)) }
            } ?? "aarch64"
            statuses.append(await status(of: install, busy: busy) {
                if let hit = cached[arch] { return try hit.get() }
                let result: Result<String, Error>
                do { result = .success(try await latest(arch)) } catch { result = .failure(error) }
                cached[arch] = result
                return try result.get()
            })
        }
        return statuses
    }

    func status(
        of install: UvInstall, busy: UvActivity.Busy?, latest: () async throws -> String
    ) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .uv, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .uv(install))
        }
        /// The channel, compared — for a copy that is reported whatever happens.
        func compared(_ installed: String) async -> (CLIToolState, String)? {
            guard let newest = try? await latest() else { return nil }
            switch VersionComparator.compare(installed, newest) {
            case .orderedAscending: return (.updateAvailable, newest)
            case .orderedSame: return (.upToDate, newest)
            case .orderedDescending: return (.ahead, newest)
            }
        }

        if install.problem == .executableMissing {
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        }
        switch install.layout {
        case .standalone:
            break
        case .link, .unreceipted:
            let how = install.layout == .link
                ? "a link (uv tool install or pipx), which uv self update does not update"
                : "not the copy the standalone installer's receipt names, so uv self update would refuse it"
            guard let installed = install.version, let result = await compared(installed) else {
                return verdict(.unknown, note: "\(how): reported only", withheld: .unsupportedInstaller)
            }
            return verdict(result.0, latest: result.1, note: "\(how): reported only", withheld: .unsupportedInstaller)
        }

        if install.quarantined {
            return verdict(.unknown, note: "quarantined, so not run", withheld: .versionUnreadable)
        }
        let installed: String
        if install.isVendorSigned {
            guard let ran = install.version else {
                return verdict(.unknown, note: "uv --version printed no version", withheld: .versionUnreadable)
            }
            if let receipt = install.receiptVersion, receipt != ran {
                return verdict(.unknown, note: "the file is uv \(ran) but its install receipt says \(receipt)",
                               withheld: .versionMismatch)
            }
            installed = ran
        } else if install.needsHash {
            guard let receipt = install.receiptVersion else {
                return verdict(.unknown, note: "the install receipt names no version", withheld: .versionUnreadable)
            }
            // Every release from 0.12.12 is Developer ID signed, so an unsigned
            // file cannot be the one the receipt names.
            if VersionComparator.compare(receipt, UvScanner.firstSignedVersion) != .orderedAscending {
                return verdict(.unknown,
                               note: "the receipt says uv \(receipt), which Astral signs, but this file is not signed",
                               withheld: .versionMismatch)
            }
            installed = receipt
        } else {
            return verdict(.unknown,
                           note: "not signed by Astral (Team \(UvScanner.teamIdentifier)) and not an unsigned release build: not run",
                           withheld: .wrongSigner)
        }

        let newest: String
        do {
            newest = try await latest()
        } catch {
            return verdict(.unknown, note: "could not read uv's versions manifest: \(error)", withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.hashVerdict == .differs {
            return verdict(state, latest: newest,
                           note: "not signed, and not byte for byte the uv \(installed) Astral published: not run",
                           withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: Self.updateCommand(for: install))
    }

    /// `<dir>/uv self update`, with `<dir>` first on `PATH`: the installer `uv
    /// self update` runs appends `. "$HOME/.local/bin/env"` to the shell profiles
    /// when the install directory is not on `PATH` and the receipt's
    /// `modify_path` is true (this Mac's is) — a GUI process's `PATH` never has
    /// it.
    static func updateCommand(for install: UvInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["self", "update"], pathPrefix: install.directory)
    }
}
