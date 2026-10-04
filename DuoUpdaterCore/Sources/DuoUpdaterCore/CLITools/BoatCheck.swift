import Foundation

/// The Boat CLI's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **The update is Boat's own `boat self-update`**, on the installer's file.
///    It asks the channel Boat's config names and swaps in that release after
///    checking its `SHA256SUMS`.
/// 2. **The trust rule** (`CLIToolTrust`): Boat is only ever ad hoc signed, so
///    the file is run only when its sha256 is the one the release of its
///    compiled-in version publishes. A file that is not is withheld as
///    `.unverified`. The hash is asked only when an update would be offered:
///    nothing of the file runs otherwise.
/// 3. **Never downgrade.** The server answers "update available" for any
///    version that differs from the channel's (`BoatRelease`), so a copy newer
///    than its channel — a staging build on `prod`, a `prod` build after
///    switching to `staging` — reads as `.ahead` here and gets no click.
/// 4. **Only boat.dev.** A config whose `api_url` names another server sends
///    `self-update` there; that is reported, not checked.
///
/// Boat has no setting that turns its own update off — every command checks
/// at startup unless given `--no-update` — so there is no settings gate.
public struct BoatCheck: Sendable {

    typealias Latest = @Sendable (_ channel: String, _ platform: String) async throws -> String
    typealias Digest = @Sendable (_ version: String, _ platform: String) async throws -> String
    /// The file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let latest: Latest
    let digest: Digest
    let hash: Hash

    public init(release: BoatRelease = BoatRelease()) {
        self.init(
            latest: { try await release.latest(channel: $0, platform: $1).version },
            digest: { try await release.publishedDigest(version: $0, platform: $1) },
            hash: { CLIToolTrust.sha256(of: $0.resolvingSymlinksInPath()) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(latest: @escaping Latest, digest: @escaping Digest, hash: @escaping Hash) {
        self.latest = latest
        self.digest = digest
        self.hash = hash
    }

    public enum Trust: Sendable, Equatable {
        case published
        case differs
        case couldNotVerify(String)
    }

    /// Whether the file is byte for byte the build Boat published for
    /// `install.version`.
    func trust(of install: BoatInstall) async -> Trust {
        guard let version = install.version, let platform = install.platform else {
            return .couldNotVerify("no version or platform to look up")
        }
        let published: String
        do {
            published = try await digest(version, platform)
        } catch {
            return .couldNotVerify("could not read SHA256SUMS of boat \(version): \(error)")
        }
        let hash = self.hash
        let actual = await offCooperativePool { hash(URL(fileURLWithPath: install.path)) }
        return CLIToolTrust.matches(actual, published: published) ? .published : .differs
    }

    public func status(of install: BoatInstall, busy: BoatActivity.Busy?) async -> CLIToolStatus {
        let channel = install.settings.channel
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .boat, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: channel, state: state, oneClick: oneClick, withheld: withheld, note: note,
                detail: .boat(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .versionUnreadable:
            return verdict(.unknown, note: "no version is compiled into the file", withheld: .versionUnreadable)
        case nil:
            break
        }
        guard let installed = install.version, let platform = install.platform else {
            return verdict(.unknown, note: "not an arm64 or x86_64 executable", withheld: .versionUnreadable)
        }
        if let api = install.settings.customAPI {
            return verdict(.unknown, note: "Boat's config points at \(api), not boat.dev: not checked",
                           withheld: .unsupportedInstaller)
        }

        let newest: String
        do {
            newest = try await latest(channel, platform)
        } catch {
            return verdict(.unknown, note: "could not read Boat's \(channel) channel: \(error)",
                           withheld: .channelUnreadable)
        }
        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        if install.quarantined {
            return verdict(state, latest: newest, note: "quarantined, so not run", withheld: .unverified)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        switch await trust(of: install) {
        case .published:
            return verdict(state, latest: newest, oneClick: Self.updateCommand(for: install))
        case .differs:
            return verdict(state, latest: newest,
                           note: "not byte for byte the boat \(installed) published in its SHA256SUMS: not run",
                           withheld: .unverified)
        case .couldNotVerify(let reason):
            return verdict(state, latest: newest, note: reason, withheld: .channelUnreadable)
        }
    }

    /// `~/.ascii/bin/boat self-update`. Nothing is put on `PATH`: the update
    /// runs no other program.
    static func updateCommand(for install: BoatInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["self-update"], pathPrefix: nil)
    }
}
