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
///
/// A package of bun's global install (`NpmInstall.bun`) is held to the same
/// rules, with bun where npm was (agreed 2026-10-04): its row is in bun's group;
/// it is installed by that bun, which must carry Oven's Team ID; and its
/// `engines.node` is held against the node found on disk (`BunPackages`),
/// without which it is reported only — its commands run on whatever node the
/// user's `PATH` names, which an app cannot see.
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
                // Filed against the package, not the provider: one request per package.
                do {
                    result = .success(try await RequestAttribution.withApp(name) { try await packument(name) })
                } catch { result = .failure(error) }
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
                kind: install.bun == nil ? .npm : .bun, path: install.path, installedVersion: install.version,
                latestVersion: pick.map { $0.offered ?? $0.tagVersion }, channel: pick?.tag, state: state,
                oneClick: oneClick, withheld: withheld, note: note, manualCommand: manual,
                name: install.name, releaseNotesKey: NpmChangelog.releaseNotesKey(name: install.name, installed: install.version),
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
            // Nothing above `installed` may be offered, and not for the runtime:
            // the tag names a prerelease this copy, on releases, does not follow,
            // or a version deprecated or missing from the registry.
            let why = NpmVersion(pick.tagVersion).map { $0.isPrerelease && !current.isPrerelease } == true
                ? "is a prerelease, and this copy follows releases"
                : "is deprecated or not in the registry's versions"
            return verdict(.upToDate, pick: pick, note: "\(pick.tag)'s \(pick.tagVersion) \(why)")
        }
        let alongside = pick.gap.map { "; \($0.version) \($0.requirement)" } ?? ""

        if let bun = install.bun {
            if let withheld = Self.bunGate(install, bun: bun, node: node, alongside: alongside) {
                return verdict(.updateAvailable, pick: pick, note: withheld.note, withheld: withheld.withheld)
            }
            return await finish(install, pick: pick, offered: offered, busy: busy, openclaw: openclaw, verdict: verdict)
        }

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
        case _ where install.runtime.nodeIsTrusted:
            break
        case .adHoc?, .unsigned?:
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node is neither signed by the Node.js Foundation (Team \(NpmScanner.nodeTeamIdentifier)) nor a Homebrew keg, so it is not run\(alongside)",
                           withheld: .unverified)
        case .vendor?, .otherSigner?, .invalid?, nil:
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node is not signed by the Node.js Foundation (Team \(NpmScanner.nodeTeamIdentifier))\(alongside)",
                           withheld: .wrongSigner)
        }
        guard node != nil else {
            return verdict(.updateAvailable, pick: pick,
                           note: "this prefix's node version could not be read, so engines cannot be checked\(alongside)",
                           withheld: .versionUnreadable)
        }
        return await finish(install, pick: pick, offered: offered, busy: busy, openclaw: openclaw, verdict: verdict)
    }

    /// Why a package of bun's global install gets no click, or nil: no node to
    /// hold its `engines` against, or a bun that may not be run.
    static func bunGate(
        _ install: NpmInstall, bun: BunManager, node: NpmVersion?, alongside: String
    ) -> (withheld: CLIToolWithheld, note: String)? {
        guard install.runtime.node != nil, node != nil else {
            return (.versionUnreadable,
                    "no node in /opt/homebrew or /usr/local to hold its engines against: reported only\(alongside)")
        }
        if bun.quarantined {
            return (.unverified, "\(bun.path) is quarantined, so it is not run\(alongside)")
        }
        guard bun.signature == .vendor else {
            return (.wrongSigner,
                    "\(bun.path) is not signed by Oven (Team \(BunScanner.teamIdentifier))\(alongside)")
        }
        return nil
    }

    /// The command and the last two gates — the package's own auto-update
    /// setting, then a change already running — once the runtime has passed.
    private func finish(
        _ install: NpmInstall, pick: NpmPick, offered: String, busy: NpmActivity.Busy?, openclaw: OpenClawSettings?,
        verdict: (CLIToolState, NpmPick?, CLIToolCommand?, NpmPackage.Updater?, String?, CLIToolWithheld?, CLIToolCommand?)
            -> CLIToolStatus
    ) async -> CLIToolStatus {
        let alongside = pick.gap.map { "; \($0.version) \($0.requirement)" } ?? ""
        let (command, updater, why) = Self.updateCommand(for: install, version: offered)
        if let openclaw, openclaw.autoUpdate == false {
            return verdict(.updateAvailable, pick, nil, updater,
                           "openclaw's own auto-update is off (update.auto.enabled: false): reported only\(alongside)",
                           .autoUpdateOff, command)
        }
        if let busy {
            return verdict(.updateAvailable, pick, nil, nil, busy.description + alongside, .busy, nil)
        }
        let notes = [why, pick.gap.map { "\($0.version) \($0.requirement)" }].compactMap { $0 }
        return verdict(.updateAvailable, pick, command, updater, notes.isEmpty ? nil : notes.joined(separator: "; "),
                       nil, nil)
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
    ///
    /// A package of bun's global install: `<bun> add -g <name>@<version>`, which
    /// writes that exact version into bun's global `package.json` as `openclaw
    /// update` does. openclaw keeps its own update, run by the node found on disk
    /// when that node may be run: with bun's `bin` and the system's on `PATH` and
    /// no npm or pnpm there, its `detectGlobalInstallManagerForRoot` finds the
    /// package under `~/.bun/install/global` and installs with `bun add -g
    /// openclaw@<version>` (2026.3.24's `dist`, read 2026-10-04).
    static func updateCommand(
        for install: NpmInstall, version: String
    ) -> (CLIToolCommand?, NpmPackage.Updater?, String?) {
        if let bun = install.bun { return bunUpdateCommand(for: install, bun: bun, version: version) }
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

    static func bunUpdateCommand(
        for install: NpmInstall, bun: BunManager, version: String
    ) -> (CLIToolCommand?, NpmPackage.Updater?, String?) {
        let bin = URL(fileURLWithPath: bun.path).deletingLastPathComponent().path
        var why: String?
        if case .openclaw(let settings) = install.ownUpdate {
            if settings.supportsTag, install.runtime.nodeIsTrusted, let node = install.runtime.node {
                let script = URL(fileURLWithPath: install.path).appendingPathComponent("openclaw.mjs").path
                return (CLIToolCommand(executable: node, arguments: [script, "update", "--tag", version], pathPrefix: bin),
                        .openclaw, nil)
            }
            why = settings.supportsTag
                ? "bun, not `openclaw update`: the node it would run on is neither Node.js's nor Homebrew's"
                : "bun, not `openclaw update`: this openclaw does not document --tag, which pins the version"
        }
        return (CLIToolCommand(executable: bun.path, arguments: ["add", "-g", "\(install.name)@\(version)"],
                               pathPrefix: bin), .bun, why)
    }
}
