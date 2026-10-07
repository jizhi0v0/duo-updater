import Foundation

/// herdr's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **The installed build is its sha256.** The file is hashed and looked up in
///    herdr's manifests and its GitHub releases (`HerdrRelease.resolve`): a match
///    names the build and proves it is the vendor's, in one step. herdr is only
///    ever ad hoc signed, so a file that matches nothing is `.unverified`, its
///    version unknown, and nothing of it is run (`CLIToolTrust`).
/// 2. **The update is herdr's own `herdr update`**, on the installer's file. It
///    reads the channel herdr's config names, downloads that channel's build for
///    this Mac and checks it against the manifest's sha256 before renaming it
///    into place.
/// 3. **Never downgrade.** `herdr update` installs the preview manifest's build
///    whenever its id differs from the running one's, and on `stable` installs
///    the newest release over any preview build — both can be older
///    (`HerdrBuild.compare`). Only a build newer than the file's gets a click;
///    an older one reads as `.ahead`.
/// 4. **`version_check = false`** in herdr's config reports the update with the
///    command, as a tool's update check turned off does (`HerdrSettings`).
public struct HerdrCheck: Sendable {

    typealias Resolve = @Sendable (_ channel: String, _ target: String, _ sha256: String) async throws
        -> HerdrRelease.Resolution
    /// The file's sha256. Blocking.
    typealias Hash = @Sendable (URL) -> String?

    let resolve: Resolve
    let hash: Hash

    public init(release: HerdrRelease = HerdrRelease()) {
        self.init(
            resolve: { try await release.resolve(channel: $0, target: $1, sha256: $2) },
            hash: { CLIToolTrust.sha256(of: $0) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(resolve: @escaping Resolve, hash: @escaping Hash) {
        self.resolve = resolve
        self.hash = hash
    }

    /// The file hashed, and the channel asked which build it is and what it
    /// offers. Throws what the channel's manifest throws.
    func resolution(of install: HerdrInstall) async throws -> HerdrRelease.Resolution {
        guard let target = install.target else { throw HerdrRelease.Failure.unreadable }
        let hash = self.hash
        guard let sha256 = await offCooperativePool({ hash(URL(fileURLWithPath: install.path)) }) else {
            throw CocoaError(.fileReadUnknown)
        }
        return try await resolve(install.settings.channel, target, sha256)
    }

    public func status(of install: HerdrInstall, busy: HerdrActivity.Busy?) async -> CLIToolStatus {
        let channel = install.settings.channel
        func verdict(
            _ state: CLIToolState, installed: String? = nil, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .herdr, path: install.path, installedVersion: installed, latestVersion: latest,
                channel: channel, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .herdr(install))
        }

        switch install.problem {
        case .executableMissing:
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        case .linkedElsewhere:
            return verdict(.unknown, note: "a link to \(install.linkTarget ?? "?"), not the installer's file",
                           withheld: .unsupportedInstaller)
        case nil:
            break
        }
        guard install.target != nil else {
            return verdict(.unknown, note: "not an arm64 or x86_64 executable", withheld: .versionUnreadable)
        }
        guard install.settings.channelIsKnown else {
            return verdict(.unknown, note: "herdr's config names the channel \"\(channel)\", which herdr does not know",
                           withheld: .channelUnreadable)
        }

        let resolution: HerdrRelease.Resolution
        do {
            resolution = try await self.resolution(of: install)
        } catch {
            return verdict(.unknown, note: "could not read herdr's \(channel) channel: \(error)",
                           withheld: .channelUnreadable)
        }
        let latest = resolution.offered.version
        let installed: HerdrBuild
        switch resolution.installed {
        case .published(let build):
            installed = build
        case .unpublished:
            return verdict(.unknown, latest: latest,
                           note: "its sha256 is no build herdr published (herdr.dev's manifests, its GitHub releases): not run",
                           withheld: .unverified)
        case .couldNotVerify(let reason):
            return verdict(.unknown, latest: latest, note: reason, withheld: .channelUnreadable)
        }

        let state: CLIToolState
        switch HerdrBuild.compare(installed, resolution.offered) {
        case .orderedAscending?: state = .updateAvailable
        case .orderedSame?: state = .upToDate
        case .orderedDescending?: state = .ahead
        case nil:
            return verdict(.unknown, installed: installed.version, latest: latest,
                           note: "two preview builds of one day, and no build time to order them by",
                           withheld: .versionUnreadable)
        }
        guard state == .updateAvailable else { return verdict(state, installed: installed.version, latest: latest) }

        if install.quarantined {
            return verdict(state, installed: installed.version, latest: latest, note: "quarantined, so not run",
                           withheld: .unverified)
        }
        if !install.settings.versionCheck {
            return verdict(state, installed: installed.version, latest: latest,
                           note: "version_check = false in herdr's config", withheld: .autoUpdateOff,
                           manualCommand: Self.updateCommand(for: install))
        }
        if let busy {
            return verdict(state, installed: installed.version, latest: latest, note: busy.description, withheld: .busy)
        }
        return verdict(state, installed: installed.version, latest: latest, oneClick: Self.updateCommand(for: install))
    }

    /// `~/.local/bin/herdr update`, without `--handoff`: a running session is
    /// never handed over or stopped by DuoUpdater (`HerdrUpdater`).
    static func updateCommand(for install: HerdrInstall) -> CLIToolCommand {
        CLIToolCommand(executable: install.path, arguments: ["update"], pathPrefix: nil)
    }
}
