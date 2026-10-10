import Foundation

/// How a command-line tool's row is worded wherever it is shown: who signs a
/// tool's releases, and why an install has no one-click. The menu-bar app words
/// its rows with these (`CLIToolsModel`, `CLIToolPresentation`) and `duo` its
/// lines, so the two say the same thing about the same copy.
///
/// `String(localized:)` with no bundle reads the main bundle's table: the
/// app's `Localizable.xcstrings` in the app, none in `duo`, which therefore
/// prints the English source.
public enum CLIToolWording {

    /// Who signs `kind`'s releases, as `wrongSigner` names them; nil for a tool
    /// whose releases carry no signature to check (bub, a Python package).
    ///
    /// uv's builds from 0.12.12 carry the certificate of "OpenAI OpCo, LLC"
    /// (`UvInstall`); the short reason still names Astral, whose tool it is, and
    /// the detail pane's signature fact says who signed it. rustup is only ever
    /// ad hoc or unsigned — trusted by its published sha256 — and an npm
    /// package by the registry's integrity hash. Boat is only ever ad hoc, and
    /// trusted by its release's `SHA256SUMS`. Codex is signed by OpenAI OpCo, LLC —
    /// the certificate uv's builds carry too, here under its own vendor's name.
    public static func vendor(of kind: CLIToolKind) -> String? {
        switch kind {
        case .claudeCode: return "Anthropic"
        case .fx: return "Vercel"
        case .uv: return "Astral"
        case .junie: return "JetBrains"
        case .codex: return "OpenAI"
        case .bun: return "Oven"
        case .opencode: return "Anomaly"
        case .cursorAgent: return "Anysphere"
        case .amp: return "Amp Frontier"
        case .deno: return "Deno Land"
        case .mise: return "Jeffrey Dickey"
        case .bub, .rust, .npm, .boat, .vitePlus, .herdr, .luvus, .lorca, .zoxide, .nvm, .atuin, .ghcup, .flyctl, .helm, .starship: return nil
        }
    }

    /// Why an install has no one-click, in the user's terms rather than the gate's.
    public static func reason(_ withheld: CLIToolWithheld, of kind: CLIToolKind) -> String {
        let tool = kind.displayName
        switch withheld {
        case .autoUpdateOff:
            return String(localized: "Auto-update is off in \(tool)’s settings")
        case .updatesDisabled:
            return String(localized: "Updates are turned off in \(tool)’s settings")
        case .busy:
            return String(localized: "\(tool) is already being updated")
        case .versionMismatch:
            return String(localized: "Can’t confirm which version is installed")
        case .unsupportedInstaller:
            return String(localized: "No one-click update for this kind of install")
        case .noOwnNpm:
            return String(localized: "Can’t tell which npm installed it")
        case .updaterMissing:
            // Today only bub's: `bub update` runs uv, which the GUI may not find.
            return kind == .bub
                ? String(localized: "bub updates with uv, and uv wasn’t found")
                : String(localized: "The program that updates it wasn’t found")
        case .broken:
            return String(localized: "An install is broken")
        case .channelUnsigned:
            guard let vendor = vendor(of: kind) else {
                return String(localized: "Builds on this channel aren’t signed by its developer")
            }
            return String(localized: "Builds on this channel aren’t signed by \(vendor)")
        case .unverified:
            switch kind {
            case .rust:
                // The rustup row's; a toolchain's is worded from its status.
                return String(localized: "Not a published rustup build")
            case .npm:
                // What is run is the prefix's node: trusted when the Node.js
                // Foundation signed it or a Homebrew keg installed it
                // (`NpmRuntime.nodeIsTrusted`). A quarantined one is worded from
                // its status.
                return String(localized: "Its node is neither Node.js’s nor Homebrew’s")
            default:
                guard let vendor = vendor(of: kind) else {
                    return String(localized: "Not the build its developer published")
                }
                return String(localized: "Not the build \(vendor) published")
            }
        case .runtimeTooOld:
            return String(localized: "Needs a newer Node")
        case .staged:
            return String(localized: "\(tool) installs its downloaded update at its next launch")
        case .projectIncomplete:
            return String(localized: "\(tool)’s project doesn’t list \(tool)")
        case .wrongSigner:
            guard let vendor = vendor(of: kind) else {
                return String(localized: "Not signed by its developer")
            }
            return String(localized: "Not signed by \(vendor)")
        case .versionUnreadable:
            return String(localized: "Couldn’t read the installed version")
        case .channelUnreadable:
            return String(localized: "Couldn’t reach \(tool)’s release channel")
        case .rateLimited:
            // The popover banner's own title: the same problem, the same words.
            return String(localized: "Hitting GitHub’s rate limit")
        }
    }

    /// Why `status` has no one-click, with what its own tool's payload adds: the
    /// version Junie staged, the Node a newer npm release needs, which row of the
    /// Rust group, where an npm package came from. Every other case is the
    /// tool-wide wording above.
    public static func reason(_ withheld: CLIToolWithheld, of status: CLIToolStatus) -> String {
        let quarantined = String(localized: "Quarantined, so not run")
        switch (withheld, status.detail) {
        case (.staged, .junie(let junie)):
            if let pending = junie.pendingUpdate {
                return String(localized: "Junie installs the downloaded \(pending) at its next launch")
            }
        case (.runtimeTooOld, .npm(let package)):
            if let gap = package.gap { return requirement(gap, of: "\(package.install.name) \(gap.version)") }
        case (.unverified, .rust(let item)):
            switch item.kind {
            // A rustup whose hash did match carries its version: only the
            // quarantine flag held it back (`RustCheck.rustupStatus`).
            case .rustup where item.version != nil: return quarantined
            case .rustup: break
            // Its rustup matched nothing published, is broken or quarantined —
            // the rustup row says which.
            case .toolchain: return String(localized: "Its rustup isn’t verified")
            }
        // A package of bun's global install: bun installs it, and its node is the
        // one found on disk (`NpmCheck.bunGate`).
        case (.unverified, .npm(let package)) where package.install.bun?.quarantined == true:
            return String(localized: "Its bun is quarantined, so not run")
        case (.wrongSigner, .npm(let package)) where package.install.bun != nil:
            let vendor = "Oven"
            return String(localized: "Its bun isn’t signed by \(vendor)")
        case (.versionUnreadable, .npm(let package)) where package.install.bun != nil && package.install.runtime.node == nil:
            return String(localized: "No node found to check its engines against")
        case (.busy, .npm(let package)) where package.install.bun != nil:
            return String(localized: "bun is already changing its global packages")
        case (.unverified, .npm(let package)) where package.install.runtime.nodeQuarantined:
            return String(localized: "Its node is quarantined, so not run")
        case (.wrongSigner, .npm):
            return String(localized: "Its node isn’t signed by the Node.js Foundation")
        case (.versionUnreadable, .uv(let uv)) where uv.quarantined:
            return quarantined
        case (.unverified, .boat(let boat)) where boat.quarantined:
            return quarantined
        case (.unverified, .herdr(let herdr)) where herdr.quarantined:
            return quarantined
        case (.unverified, .codex(let codex)) where codex.quarantined:
            return quarantined
        case (.unverified, .bun(let bun)) where bun.quarantined:
            return quarantined
        case (.unverified, .luvus(let luvus)) where luvus.quarantined:
            return quarantined
        case (.unverified, .lorca(let lorca)) where lorca.quarantined:
            return quarantined
        case (.unverified, .atuin(let atuin)) where atuin.quarantined:
            return quarantined
        case (.unverified, .ghcup(let ghcup)) where ghcup.quarantined:
            return quarantined
        case (.autoUpdateOff, .atuin):
            // Atuin's `update_check = false`: its background check only ever
            // tells the user, so the check is what was turned off.
            return String(localized: "Atuin’s update check is off in its config")
        case (.unverified, .flyctl(let flyctl)) where flyctl.quarantined:
            return quarantined
        case (.unverified, .helm(let helm)) where helm.quarantined:
            return quarantined
        case (.unverified, .starship(let starship)) where starship.quarantined:
            return quarantined
        case (.unverified, .deno(let deno)) where deno.quarantined:
            return quarantined
        case (.unverified, .mise(let mise)) where mise.quarantined:
            return quarantined
        case (.unsupportedInstaller, .bun):
            // A canary: `bun upgrade` installs the newest canary, with no version.
            return String(localized: "A canary build, which has no version to compare")
        // Which part of Codex's standalone install is missing, rather than "An
        // install is broken": seen on 2026-10-06, `current` was a directory left
        // by a removed Codex.app, and the codex on PATH was Homebrew's, unharmed.
        case (.broken, .codex(let codex)) where codex.problem == .noCurrent:
            return String(localized: "Its standalone install has no current release")
        case (.broken, .codex(let codex)) where codex.problem == .binaryMissing:
            let version = codex.version ?? "?"
            return String(localized: "Codex \(version) is missing its program file")
        case (.autoUpdateOff, .codex):
            // Codex has no auto-update to turn off: its `check_for_update_on_startup`
            // is the prompt, set false "only if your Codex updates are centrally managed".
            return String(localized: "Codex’s update check is off in its config")
        case (.autoUpdateOff, .herdr):
            // herdr's `version_check = false`: its background check only ever
            // tells the user, so the check is what was turned off.
            return String(localized: "Herdr’s update check is off in its config")
        case (.updaterMissing, .rust):
            return String(localized: "No rustup in ~/.cargo/bin")
        case (.autoUpdateOff, .rust):
            // Only the rustup row: its `auto_self_update`.
            let rustup = "rustup"
            return String(localized: "Auto-update is off in \(rustup)’s settings")
        case (.autoUpdateOff, .npm(let package)):
            // openclaw's own `update.auto.enabled`.
            return String(localized: "Auto-update is off in \(package.install.name)’s settings")
        case (.busy, .rust):
            // One gate for every Rust row (`RustActivity`).
            return String(localized: "rustup is already running")
        case (.busy, .npm):
            // Attributed by the node running it (`NpmActivity`): any package of
            // the prefix, or the package's own updater, which runs npm too.
            return String(localized: "npm is busy in this prefix")
        case (.unsupportedInstaller, .uv(let uv)):
            switch uv.layout {
            case .link: return String(localized: "A uv tool or pipx link")
            case .unreceipted: return String(localized: "Not the copy uv’s installer recorded")
            case .standalone: break
            }
        case (.unsupportedInstaller, .junie(let junie)):
            // Only `experimental` today: release, eap and nightly have installers.
            if let channel = junie.channel { return String(localized: "The \(channel) channel has no installer") }
        case (.unsupportedInstaller, .npm(let package)):
            return origin(of: package)
        case (.unsupportedInstaller, .boat):
            // Its config's `api_url` names another server than boat.dev.
            return String(localized: "Boat’s config points at another server")
        case (.unsupportedInstaller, .codex):
            // `~/.local/bin/codex` is not the standalone install's launcher.
            let launcher = "~/.local/bin/codex"
            return String(localized: "\(launcher) isn’t this install’s launcher")
        // In `LuvusCheck`'s order: a link elsewhere, a release before the
        // command, a folder only `sudo` could write to.
        case (.unsupportedInstaller, .luvus(let luvus)):
            let command = "luvus update"
            if luvus.problem == .unknownLocation { return String(localized: "A link \(command) won’t replace") }
            if !luvus.hasUpdateCommand { return String(localized: "This version has no \(command)") }
            if !luvus.writable { return String(localized: "Updating it needs administrator rights") }
        // In `LorcaCheck`'s order: a release before the command, a folder it
        // cannot write to.
        case (.unsupportedInstaller, .lorca(let lorca)):
            let command = "lorca update"
            if !lorca.hasUpdateCommand { return String(localized: "This version has no \(command)") }
            if !lorca.writable { return String(localized: "Updating it needs administrator rights") }
        // In `ZoxideCheck`'s order: a link elsewhere (the generic reason), a
        // folder only `sudo` could write to; then a release without a digest.
        case (.unsupportedInstaller, .zoxide(let zoxide)):
            if !zoxide.linked, !zoxide.writable { return String(localized: "Updating it needs administrator rights") }
        case (.unverified, .zoxide):
            return String(localized: "The new release can’t be checked against a published digest")
        case (.unsupportedInstaller, .atuin(let atuin)) where atuin.problem == nil && !atuin.writable:
            return String(localized: "Updating it needs administrator rights")
        case (.unsupportedInstaller, .ghcup(let ghcup)) where ghcup.problem == nil && !ghcup.writable:
            return String(localized: "Updating it needs administrator rights")
        // A folder only `sudo` could write to: the row offers the vendor's command.
        case (.unsupportedInstaller, .helm(let helm)):
            if helm.problem == nil, !helm.writable { return String(localized: "Updating it needs administrator rights") }
        case (.unsupportedInstaller, .starship(let starship)):
            if starship.problem == nil, !starship.writable {
                return String(localized: "Updating it needs administrator rights")
            }
        // A folder this user cannot write to — only once `DenoCheck` got past the
        // build's channel, which it asks first: an RC, LTS or canary build keeps
        // the generic wording even in a read-only folder, since fixing the folder
        // would not give it a one-click. Likewise `MiseCheck`'s packager marker.
        case (.unsupportedInstaller, .deno(let deno))
            where !deno.writable && !deno.isPrerelease && deno.reported?.channel == "stable":
            return String(localized: "Updating it needs administrator rights")
        case (.unsupportedInstaller, .mise(let mise)) where !mise.writable && mise.selfUpdateDisabledBy == nil:
            return String(localized: "Updating it needs administrator rights")
        // nvm's only copy-command case (`NvmCheck`): a directory this user
        // cannot write to.
        case (.unsupportedInstaller, .nvm(let nvm)) where !nvm.writable:
            return String(localized: "Updating it needs administrator rights")
        default:
            break
        }
        return reason(withheld, of: status.kind)
    }

    /// Where an npm package that is only reported came from, in `NpmCheck`'s
    /// order. The registry's two answers — no such package, no such version —
    /// leave nothing in the payload apart, and both mean the same thing here.
    private static func origin(of package: NpmPackage) -> String {
        let install = package.install
        if install.linkTarget != nil {
            return String(localized: "Linked to a local folder")
        }
        if let manifest = install.manifestName, manifest != install.name {
            return String(localized: "Installed as an alias of \(manifest)")
        }
        if install.customRegistry != nil {
            return String(localized: "From a registry other than npm’s")
        }
        if case .openclaw(let settings) = install.ownUpdate, settings.effectiveChannel == "dev" {
            return String(localized: "openclaw is on its dev channel")
        }
        return String(localized: "Not a release from the npm registry")
    }

    /// "openclaw 2026.9.7 needs Node ≥ 24.16.0": what a newer npm release asks of
    /// the runtime, `label` naming the release. The lowest Node above the
    /// prefix's when the range has one; else the range as written, or npm's.
    public static func requirement(_ gap: NpmPackage.RuntimeGap, of label: String) -> String {
        if let minimum = gap.minimumNode { return String(localized: "\(label) needs Node ≥ \(minimum)") }
        if let node = gap.node { return String(localized: "\(label) needs Node \(node)") }
        if let npm = gap.npm { return String(localized: "\(label) needs npm \(npm)") }
        return String(localized: "\(label) needs a newer Node")
    }
}
