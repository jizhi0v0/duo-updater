import Foundation

/// The verdict for each Rust row, as every tool's verdict is shaped
/// (`CLIToolStatus`).
///
/// The rules, as agreed for Rust (2026-10-01):
/// 1. **rustup is run only when its sha256 is rust-lang's own for its version**
///    (`RustRelease.identify`): it is always ad hoc signed, so there is no
///    signature to go by. A rustup that matches nothing is reported and never
///    run — and since rustup is what updates the toolchains, their rows are not
///    offered either (`.unverified`, or `.updaterMissing` with no rustup at all).
/// 2. **rustup's one-click is `rustup self update`**, only while
///    `auto_self_update` is absent or `enable`; otherwise the update is
///    reported with that command for the user to run (`manualCommand`).
/// 3. **A toolchain's one-click is `rustup update <toolchain> --no-self-update`**:
///    the toolchain on its own channel, and nothing else — rustup's own update is
///    its row's, behind its own setting.
/// 4. **A toolchain is outdated when rustup would say so**: its
///    `update-hashes` entry differs from its channel's current hash. Only then is
///    the channel's version read, for the row to show.
/// 5. **Never race a rustup command already running** (`RustActivity`).
public struct RustCheck: Sendable {

    let release: RustRelease

    public init(release: RustRelease = RustRelease()) {
        self.release = release
    }

    /// The rustup row, and the trusted rustup the toolchain rows run with — nil
    /// when it was not proven rust-lang's, or when it is quarantined.
    func rustupStatus(
        _ rustup: RustScanner.Rustup, settings: RustupSettings, busy: RustActivity.Busy?
    ) async -> (status: CLIToolStatus, trusted: RustItem.TrustedRustup?) {
        func verdict(
            _ state: CLIToolState, version: String? = nil, latest: String? = nil,
            trusted: RustItem.TrustedRustup? = nil, oneClick: CLIToolCommand? = nil, note: String? = nil,
            withheld: CLIToolWithheld? = nil, manualCommand: CLIToolCommand? = nil
        ) -> (status: CLIToolStatus, trusted: RustItem.TrustedRustup?) {
            let status = CLIToolStatus(
                kind: .rust, path: rustup.path, installedVersion: version, latestVersion: latest, channel: nil,
                state: state, oneClick: oneClick, withheld: withheld, note: note, manualCommand: manualCommand,
                name: "rustup", releaseNotesKey: "rustup",
                detail: .rust(RustItem(path: rustup.path, version: version, kind: .rustup, trustedRustup: trusted)))
            return (status, trusted)
        }

        if rustup.problem != nil {
            return verdict(.unknown, note: "the path points at a missing or empty file", withheld: .broken)
        }
        let identity: RustRelease.Identity
        do {
            identity = try await release.identify(
                sha256: rustup.sha256, triple: rustup.hostTriple, claimed: rustup.claimedVersion)
        } catch {
            return verdict(.unknown, note: "could not read rustup's releases on static.rust-lang.org: \(error)",
                           withheld: .channelUnreadable)
        }
        guard let version = identity.verified, let sha256 = rustup.sha256, let triple = rustup.hostTriple else {
            let claim = rustup.claimedVersion.map { " (it calls itself \($0))" } ?? ""
            let note = rustup.hostTriple == nil
                ? "not a single-architecture arm64 or x86_64 build, so no published hash to compare: not run"
                : "its sha256 is not one rust-lang publishes for rustup\(claim): not run"
            return verdict(.unknown, latest: identity.latest, note: note, withheld: .unverified)
        }
        if rustup.quarantined {
            return verdict(.unknown, version: version, latest: identity.latest,
                           note: "quarantined (com.apple.quarantine), so not run", withheld: .unverified)
        }
        let trusted = RustItem.TrustedRustup(path: rustup.path, sha256: sha256, version: version, hostTriple: triple)

        let state: CLIToolState
        switch VersionComparator.compare(version, identity.latest) {
        case .orderedAscending: state = .updateAvailable
        case .orderedSame: state = .upToDate
        case .orderedDescending: state = .ahead
        }
        guard state == .updateAvailable else {
            return verdict(state, version: version, latest: identity.latest, trusted: trusted)
        }
        let command = Self.selfUpdate(rustup.path)
        if !settings.selfUpdateEnabled {
            return verdict(
                state, version: version, latest: identity.latest, trusted: trusted,
                note: "auto_self_update is \(settings.autoSelfUpdate ?? "enable") in rustup's settings: reported only",
                withheld: .autoUpdateOff, manualCommand: command)
        }
        if let busy {
            return verdict(state, version: version, latest: identity.latest, trusted: trusted,
                           note: busy.description, withheld: .busy)
        }
        return verdict(state, version: version, latest: identity.latest, trusted: trusted, oneClick: command)
    }

    /// What the rustup row found, as far as the toolchain rows care: which
    /// rustup, if any, may run their updates.
    enum Updater: Sendable, Equatable {
        case missing
        /// Its hash matched nothing rust-lang publishes, it is broken, or it is
        /// quarantined.
        case untrusted
        /// rust-lang's server could not be read to tell.
        case unchecked
        case trusted(RustItem.TrustedRustup)

        init(rustup: RustScanner.Rustup?, status: CLIToolStatus?, trusted: RustItem.TrustedRustup?) {
            if let trusted {
                self = .trusted(trusted)
            } else if rustup == nil {
                self = .missing
            } else {
                self = status?.withheld == .channelUnreadable ? .unchecked : .untrusted
            }
        }

        var trusted: RustItem.TrustedRustup? {
            if case .trusted(let rustup) = self { return rustup }
            return nil
        }
    }

    /// One toolchain's row.
    func toolchainStatus(
        _ toolchain: RustScanner.Toolchain, updater: Updater, busy: RustActivity.Busy?
    ) async -> CLIToolStatus {
        let name = toolchain.name
        func verdict(
            _ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil, note: String? = nil,
            withheld: CLIToolWithheld? = nil
        ) -> CLIToolStatus {
            CLIToolStatus(
                kind: .rust, path: toolchain.path, installedVersion: toolchain.version?.display, latestVersion: latest,
                channel: name.channel, state: state, oneClick: oneClick, withheld: withheld, note: note,
                name: name.name, releaseNotesKey: RustChangelog.releaseNotesKey(channel: name.channel),
                detail: .rust(RustItem(
                    path: toolchain.path, version: toolchain.version?.display, kind: .toolchain(name),
                    trustedRustup: oneClick == nil ? nil : updater.trusted)))
        }

        guard let installed = toolchain.version else {
            return verdict(.unknown, note: "no [pkg.rust] version in its multirust-channel-manifest.toml",
                           withheld: .versionUnreadable)
        }
        let latest: RustToolchainVersion
        do {
            let hash = try await release.channelHash(name.channel)
            // rustup's own test (`UPDATE_HASH_LEN`): the first 20 digits.
            if let recorded = toolchain.updateHash, recorded == String(hash.lowercased().prefix(20)) {
                return verdict(.upToDate, latest: installed.display)
            }
            latest = try await release.channelVersion(name.channel, hash: hash)
        } catch {
            return verdict(.unknown, note: "could not read the \(name.channel) channel: \(error)",
                           withheld: .channelUnreadable)
        }

        // The channel's manifest moved. The same Rust in it (a manifest re-issued
        // for another target) is no update; `rustup update` would say "unchanged".
        guard latest.label != installed.label else { return verdict(.upToDate, latest: latest.display) }
        if VersionComparator.compare(installed.number, latest.number) == .orderedDescending {
            return verdict(.ahead, latest: latest.display)
        }
        let state = CLIToolState.updateAvailable
        let rustup: RustItem.TrustedRustup
        switch updater {
        case .missing:
            return verdict(state, latest: latest.display,
                           note: "no rustup at ~/.cargo/bin/rustup to update it with", withheld: .updaterMissing)
        case .untrusted:
            return verdict(state, latest: latest.display,
                           note: "rustup, which would update it, is not verified as rust-lang's: not run",
                           withheld: .unverified)
        case .unchecked:
            return verdict(state, latest: latest.display,
                           note: "rustup, which would update it, could not be checked against rust-lang's hashes",
                           withheld: .channelUnreadable)
        case .trusted(let verified):
            rustup = verified
        }
        if let busy {
            return verdict(state, latest: latest.display, note: busy.description, withheld: .busy)
        }
        return verdict(state, latest: latest.display, oneClick: Self.toolchainUpdate(rustup.path, name.name))
    }

    /// `rustup self update`, by the verified file's own path.
    public static func selfUpdate(_ rustup: String) -> CLIToolCommand {
        CLIToolCommand(executable: rustup, arguments: ["self", "update"], pathPrefix: nil)
    }

    /// `--no-self-update`: without it `rustup update` also replaces rustup when
    /// `auto_self_update` is `enable` — the rustup row's update, not this one's.
    public static func toolchainUpdate(_ rustup: String, _ toolchain: String) -> CLIToolCommand {
        CLIToolCommand(executable: rustup, arguments: ["update", toolchain, "--no-self-update"], pathPrefix: nil)
    }
}
