import Foundation

/// Each global npm package's verdict: is there a newer version on its track, can
/// this prefix's node run it, and may DuoUpdater install it — and if so, with
/// exactly which command.
///
/// The rules, as the user agreed them (2026-10-01):
/// 1. **CLIs only**, never npm, corepack or Claude Code (`NpmScanner`).
/// 2. **An exact version this prefix's node runs** (`NpmPick`): never `@latest`,
///    so what is installed is what was checked. A newer version that needs a
///    newer node is said alongside (`NpmPackage.gap`), or is the whole verdict
///    (withheld `.runtimeTooOld`).
/// 3. **Registry releases only.** A linked package (`npm link`, `npm i -g ./dir`)
///    and a version the registry does not list (a git URL, a tarball, a fork) are
///    reported, never updated (`.unsupportedInstaller`): npm reinstalling the
///    registry's version over them would replace the user's own build. npm 7+
///    writes no `_resolved` into `package.json` and keeps no global lockfile, so
///    these two checks are all there is to tell the origin by.
/// 4. **The vendor's own command where there is one**: `openclaw update --tag
///    <version>`. `agent-browser upgrade` is not run — see `updateCommand`.
/// 5. **The prefix's own node and npm**, Node.js-signed (the trust rule): they
///    are what runs.
/// 6. **Never race a change already running** (`NpmActivity`).
///
/// A package's own files are not held to the Developer-ID rule: npm packages are
/// unsigned scripts (agent-browser's and openclaw's native parts are ad hoc). The
/// anchor is the registry: npm verifies each tarball against the packument's
/// `dist.integrity`, and rule 3 keeps everything else out — which is also why a
/// package's own updater runs only for an install that passed it.
public struct NpmCheck: Sendable {

    typealias Packument = @Sendable (String) async throws -> NpmPackument

    let packument: Packument

    public init(registry: NpmRegistry = NpmRegistry()) {
        self.init(packument: { try await registry.packument($0) })
    }

    /// The seam tests use, so no verdict depends on the network.
    init(packument: @escaping Packument) {
        self.packument = packument
    }

    /// Every install's status, each package asked of the registry at most once.
    public func statuses(of installs: [NpmInstall], busy: (NpmInstall) -> NpmActivity.Busy?) async -> [CLIToolStatus] {
        var cache: [String: Result<NpmPackument, Error>] = [:]
        var statuses: [CLIToolStatus] = []
        for install in installs {
            let busy = busy(install)
            let packument = self.packument
            statuses.append(await status(of: install, busy: busy) { name in
                if let cached = cache[name] { return try cached.get() }
                let result: Result<NpmPackument, Error>
                do { result = .success(try await packument(name)) } catch { result = .failure(error) }
                cache[name] = result
                return try result.get()
            })
        }
        return statuses
    }

    func status(of install: NpmInstall, busy: NpmActivity.Busy?) async -> CLIToolStatus {
        await status(of: install, busy: busy, packument: packument)
    }

    private func status(
        of install: NpmInstall, busy: NpmActivity.Busy?, packument: (String) async throws -> NpmPackument
    ) async -> CLIToolStatus {
        func verdict(
            _ state: CLIToolState, pick: NpmPick? = nil, oneClick: CLIToolCommand? = nil, updater: NpmPackage.Updater? = nil,
            note: String? = nil, withheld: CLIToolWithheld? = nil, manual: CLIToolCommand? = nil
        ) -> CLIToolStatus {
            let pending = pick.map { $0.pending.isEmpty ? [install.version].compactMap { $0 } : $0.pending } ?? []
            return CLIToolStatus(
                kind: .npm, path: install.path, installedVersion: install.version,
                latestVersion: pick.map { $0.offered ?? $0.tagVersion }, channel: pick?.tag, state: state,
                oneClick: oneClick, withheld: withheld, note: note, manualCommand: manual,
                name: install.name, releaseNotesKey: "npm:\(install.name)",
                detail: .npm(NpmPackage(
                    install: install, tag: pick?.tag, newest: pick?.tagVersion, offered: pick?.offered,
                    gap: pick?.gap, pending: pending, updater: updater)))
        }

        guard let installed = install.version else {
            return verdict(.unknown, note: "package.json has no version", withheld: .versionUnreadable)
        }
        if let target = install.linkTarget {
            return verdict(.unknown, note: "linked to \(target) (npm link or a local directory), not installed from the registry: reported only",
                           withheld: .unsupportedInstaller)
        }
        if let manifestName = install.manifestName, manifestName != install.name {
            return verdict(.unknown, note: "installed as an alias of \(manifestName): reported only",
                           withheld: .unsupportedInstaller)
        }
        if let registry = install.customRegistry {
            return verdict(.unknown,
                           note: "uses the registry \(registry.url) (\(registry.file)), whose credentials DuoUpdater does not read: reported only",
                           withheld: .unsupportedInstaller)
        }
        let document: NpmPackument
        do {
            document = try await packument(install.name)
        } catch NpmRegistry.Failure.notFound {
            return verdict(.unknown, note: "\(install.name) is not on the npm registry: reported only",
                           withheld: .unsupportedInstaller)
        } catch {
            return verdict(.unknown, note: "could not read the npm registry: \(error)", withheld: .channelUnreadable)
        }
        guard document.versions[installed] != nil else {
            return verdict(.unknown,
                           note: "\(installed) is not a version on the npm registry (installed from git, a tarball or a fork): reported only",
                           withheld: .unsupportedInstaller)
        }
        guard let current = NpmVersion(installed) else {
            return verdict(.unknown, note: "\(installed) is not a semver version", withheld: .versionUnreadable)
        }

        var openclaw: OpenClawSettings?
        if case .openclaw(let settings) = install.ownUpdate { openclaw = settings }
        let tag: String?
        if let openclaw {
            if openclaw.effectiveChannel == "dev" {
                return verdict(.unknown, note: "openclaw's update channel is dev (a git checkout of main): reported only",
                               withheld: .unsupportedInstaller)
            }
            tag = NpmPick.openclawTag(channel: openclaw.effectiveChannel, distTags: document.distTags)
        } else {
            tag = NpmPick.track(installed: current, distTags: document.distTags)
        }
        let node = install.runtime.nodeVersion.flatMap(NpmVersion.init)
        let npm = install.runtime.npmVersion.flatMap(NpmVersion.init)
        guard let tag, let pick = NpmPick.pick(document, installed: installed, tag: tag, node: node, npm: npm),
              let newest = NpmVersion(pick.tagVersion)
        else {
            return verdict(.unknown, note: "the registry has no usable dist-tag for \(install.name)",
                           withheld: .channelUnreadable)
        }
        guard current < newest else {
            return verdict(current == newest ? .upToDate : .ahead, pick: pick)
        }
        guard let offered = pick.offered else {
            if let gap = pick.gap {
                return verdict(.updateAvailable, pick: pick,
                               note: "\(gap.version) \(gap.requirement)\(gap.nodeVersion.map { " (this prefix has \($0))" } ?? ""): no version above \(installed) runs here",
                               withheld: .runtimeTooOld)
            }
            return verdict(.upToDate, pick: pick, note: "\(pick.tagVersion) is deprecated")
        }
        let alongside = pick.gap.map { "; \($0.version) \($0.requirement)" } ?? ""

        // The command, then the gates in the order a user can act on them.
        guard install.runtime.npm != nil, install.runtime.node != nil else {
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix has no node and npm of its own: reported only\(alongside)",
                           withheld: .noOwnNpm)
        }
        if install.runtime.nodeQuarantined {
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node is quarantined, so it is not run\(alongside)", withheld: .unverified)
        }
        switch install.runtime.nodeSignature {
        case .vendor?:
            break
        case .adHoc?, .unsigned?:
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node is not signed by the Node.js Foundation (Team \(NpmScanner.nodeTeamIdentifier)) — Homebrew's is ad hoc — so it is not run\(alongside)",
                           withheld: .unverified)
        case .otherSigner?, .invalid?, nil:
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node is not signed by the Node.js Foundation (Team \(NpmScanner.nodeTeamIdentifier))\(alongside)",
                           withheld: .wrongSigner)
        }
        guard node != nil else {
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node version could not be read, so engines cannot be checked\(alongside)",
                           withheld: .versionUnreadable)
        }
        let (command, updater, why) = Self.updateCommand(for: install, version: offered)
        if let openclaw, openclaw.autoUpdate == false {
            return verdict(.updateAvailable, pick: pick, updater: updater,
                           note: "openclaw's own auto-update is off (update.auto.enabled: false): reported only\(alongside)",
                           withheld: .autoUpdateOff, manual: command)
        }
        if let busy {
            return verdict(.updateAvailable, pick: pick, note: busy.description + alongside, withheld: .busy)
        }
        let notes = [why, pick.gap.map { "\($0.version) \($0.requirement)" }].compactMap { $0 }
        return verdict(.updateAvailable, pick: pick, oneClick: command, updater: updater,
                       note: notes.isEmpty ? nil : notes.joined(separator: "; "))
    }

    /// The command that installs exactly `version`, and why it is that one when
    /// the package has its own updater that is not used.
    ///
    /// - openclaw: `openclaw update --tag <version>`, run by this prefix's node
    ///   with its `bin` first on `PATH` (openclaw runs the `npm` it finds there,
    ///   `npm i -g openclaw@<version>`). It keeps `update.channel` — only
    ///   `--channel` writes it — then runs `openclaw doctor` non-interactively and
    ///   restarts its gateway if one is loaded, and syncs its npm plugins (all in
    ///   2026.3.28's `update-cli`). Without a TTY its only prompt, a downgrade
    ///   confirmation, exits 1 instead (we never ask for a downgrade), and the
    ///   shell-completion offer is skipped. Exit 0 on success, 1 on a failed step.
    ///   Falls back to npm when the installed openclaw does not document `--tag`,
    ///   or when an npmrc `prefix=` would send openclaw's bare `npm i -g` to
    ///   another prefix than this one.
    /// - agent-browser: its `upgrade` (0.34.0's binary) runs `npm install -g
    ///   agent-browser@latest` — never an exact version, so not the one this check
    ///   found the prefix's node can run — and picks the installer from markers in
    ///   its own path, `/homebrew/` among them, so a copy under Homebrew's node
    ///   prefix would be "upgraded" with `brew upgrade agent-browser`. npm's own
    ///   command does what its npm branch does, pinned.
    /// - everything else: npm.
    static func updateCommand(
        for install: NpmInstall, version: String
    ) -> (CLIToolCommand?, NpmPackage.Updater?, String?) {
        guard let node = install.runtime.node, let npm = install.runtime.npm else { return (nil, nil, nil) }
        let bin = URL(fileURLWithPath: install.prefix.path).appendingPathComponent("bin").path
        var why: String?
        switch install.ownUpdate {
        case .openclaw(let settings):
            let redirected = install.npmrcPrefixElsewhere
            if settings.supportsTag, redirected == nil {
                let script = URL(fileURLWithPath: install.path).appendingPathComponent("openclaw.mjs").path
                return (CLIToolCommand(executable: node, arguments: [script, "update", "--tag", version], pathPrefix: bin),
                        .openclaw, nil)
            }
            why = settings.supportsTag
                ? "npm, not `openclaw update`: \(redirected!) sets another prefix, where openclaw's npm would install"
                : "npm, not `openclaw update`: this openclaw does not document --tag, which pins the version"
        case .agentBrowser:
            why = "npm, not `agent-browser upgrade`: it installs @latest, whatever node this prefix runs"
        case nil:
            break
        }
        return (CLIToolCommand(
            executable: node,
            arguments: [npm, "install", "-g", "--prefix", install.prefix.path, "--engine-strict", "\(install.name)@\(version)"],
            pathPrefix: bin), .npm, why)
    }
}
