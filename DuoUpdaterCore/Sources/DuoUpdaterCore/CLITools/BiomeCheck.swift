import Foundation

/// Biome's verdict, as every tool's verdict is shaped (`CLIToolStatus`).
///
/// The rules:
/// 1. **Hashed, never run** (`BiomeScanner`): the file's version is the release
///    whose published digest its sha256 equals; DuoUpdater never runs Biome. A
///    file no release this Mac knows of matches makes the check read the
///    releases' digests once (`BiomeRelease.learnPublished`); one that still
///    matches none is not a published build, and is reported only.
/// 2. **Compared on `latest.txt`** (`BiomeRelease`), what the installer
///    installs, and only toward a newer version.
/// 3. **The update is the vendor's installer** — Biome has no self-update — run
///    with `--version` the version checked, `--no-modify-path` (no shell rc file
///    is touched) and `BIOME_INSTALL_DIR` the install's own directory
///    (`BiomeUpdater`).
/// 4. **The trust rule** (`CLIToolTrust`), on what the installer leaves: Biome is
///    only ever ad hoc signed, so the new file must be byte for byte its
///    version's published build (the release's GitHub `digest`, which the user
///    accepted as Biome's published hash on 2026-10-21). So a click is offered
///    only when the latest release carries a digest for this Mac's binary;
///    without one the update is reported with the command (`manualCommand`).
/// 5. **Never through `sudo`**: the installer has no `sudo` and fails in a
///    directory it cannot write. Such an install, and a link to a copy
///    elsewhere (which the installer's `mv` would replace with a file), are
///    reported with the command.
/// 6. **Never race the installer already running** (`BiomeActivity`).
public struct BiomeCheck: Sendable {

    let release: BiomeRelease

    public init(release: BiomeRelease = BiomeRelease()) {
        self.release = release
    }

    public func status(of install: BiomeInstall, busy: BiomeActivity.Busy?) async -> CLIToolStatus {
        var install = install
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .biome, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manualCommand, detail: .biome(install))
        }
        func failed(_ error: Error, reading what: String) -> CLIToolStatus {
            switch error {
            case BiomeRelease.Failure.rateLimited(let status):
                return verdict(.unknown, note: "\(BiomeRelease.Failure.rateLimited(status))", withheld: .rateLimited)
            case let refused as GitHubRateLimitGate.Refused:
                // Held back by the gate, unsent: the same budget, spent.
                return verdict(.unknown, note: refused.localizedDescription, withheld: .rateLimited)
            default:
                return verdict(.unknown, note: "could not read \(what): \(error)", withheld: .channelUnreadable)
            }
        }

        if install.problem == .executableMissing {
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        }
        let newest: String
        do {
            newest = try await release.latestVersion()
        } catch {
            return failed(error, reading: "Biome's latest version (\(BiomeRelease.latestURL.absoluteString))")
        }

        // Rule 1: a file not yet known is looked up among the published builds.
        if install.problem == .unrecognized, let sha256 = install.sha256, let target = install.target {
            do {
                try await release.learnPublished(through: newest)
            } catch {
                return failed(error, reading: "Biome's releases to identify \(install.path)")
            }
            let digests = release.digests
            if let version = await offCooperativePool({ digests.version(sha256: sha256, target: target) }) {
                install = install.identified(as: version)
            }
        }
        guard let installed = install.version else {
            return verdict(.unknown, latest: newest,
                           note: "\(install.path) is not a Biome build published on GitHub (its sha256 matches no \(install.target ?? "macOS") binary of the newest releases), so it is not run or replaced",
                           withheld: .unverified)
        }

        let state: CLIToolState
        switch VersionComparator.compare(installed, newest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else { return verdict(state, latest: newest) }

        let command = Self.installCommand(version: newest, installDirectory: Self.installDirectory(of: install))
        if install.linked {
            return verdict(state, latest: newest,
                           note: "\(install.path) links to \(install.binary ?? "?"), which the installer would replace with a file",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        if !install.writable {
            return verdict(state, latest: newest,
                           note: "the installer cannot write \(Self.installDirectory(of: install)) without sudo",
                           withheld: .unsupportedInstaller, manualCommand: command)
        }
        guard let target = install.target else {
            return verdict(state, latest: newest, note: "not an arm64 or x86_64 Biome", withheld: .unverified,
                           manualCommand: command)
        }
        // Rule 4: what the installer leaves could not be checked.
        let digest: String?
        do {
            digest = try await release.digest(version: newest, target: target)
        } catch BiomeRelease.Failure.http(404) {
            digest = nil
        } catch {
            return failed(error, reading: "the Biome \(newest) release")
        }
        guard digest != nil else {
            return verdict(state, latest: newest,
                           note: "the Biome \(newest) release names no digest for its \(BiomeRelease.assetName(target: target)), so what the installer leaves could not be checked",
                           withheld: .unverified, manualCommand: command)
        }
        if let busy {
            return verdict(state, latest: newest, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: newest, oneClick: command)
    }

    /// The directory the installer is pointed at: the one holding the path the
    /// scan found (`~/.local/bin`, its default).
    static func installDirectory(of install: BiomeInstall) -> String {
        (install.path as NSString).deletingLastPathComponent
    }

    /// The installer as Biome's site gives it, `curl -fsSL https://biomejs.dev/install
    /// | bash -s -- --version <v>`, with the install's own directory and
    /// `--no-modify-path` spelled out. What `BiomeUpdater` runs is its equivalent
    /// without the pipe (the script downloaded whole, then run).
    static func installCommand(version: String, installDirectory: String) -> CLIToolCommand {
        CLIToolCommand(
            executable: "curl",
            arguments: ["-fsSL", BiomeUpdater.installer.absoluteString, "|", "BIOME_INSTALL_DIR=\(installDirectory)",
                        "bash", "-s", "--", "--version", version, "--no-modify-path"],
            pathPrefix: nil)
    }
}
