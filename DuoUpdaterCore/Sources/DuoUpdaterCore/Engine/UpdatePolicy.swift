import Foundation

/// The non-preference facts an install-policy decision needs from its host —
/// helper approval, which bundle paths are running, what self-updates are
/// staged. Passed in explicitly (never reached for) so `UpdatePolicy` stays
/// pure and side-effect-free; the app snapshots its live state into one of
/// these per call, and a CLI builds the same value from its own observations.
public struct InstallEnvironment: Sendable {
    /// Whether the privileged helper (root daemon that runs `mas`) is approved.
    /// The gate for the App Store `.full` route — without it that route is
    /// offered only as a deep link, never as a one-click.
    public var isHelperEnabled: Bool
    /// Bundle paths with at least one live process, normalized through
    /// `UpdatePolicy.runtimeBundlePath` — the running side of the
    /// `defersToSelfUpdater` / running-dot decisions.
    public var runningAppPaths: Set<String>
    /// Raw staged self-updates (Squirrel ShipIt / Spotify), keyed by app id
    /// (the install path, like `InstalledApp.id`). The policy computes
    /// "actionable" itself: only a staged build that IS the latest is
    /// relaunch-only; one that trails it still gets a normal Update.
    public var stagedSelfUpdates: [String: StagedSelfUpdate]

    public init(
        isHelperEnabled: Bool,
        runningAppPaths: Set<String>,
        stagedSelfUpdates: [String: StagedSelfUpdate]
    ) {
        self.isHelperEnabled = isHelperEnabled
        self.runningAppPaths = runningAppPaths
        self.stagedSelfUpdates = stagedSelfUpdates
    }
}

/// The shared install-eligibility rules: which updates install seamlessly in
/// place, which need the system installer, and which are handed to the app's
/// own updater. Moved out of the app so the CLI and the menu bar decide with
/// one copy of the rules. Every function is a pure decision over
/// `(UpdateResult, UpdateSettings, InstallEnvironment)` — no I/O, no globals.
public enum UpdatePolicy {

    /// True when this update installs seamlessly in place (Sparkle EdDSA, or a
    /// drag-to-Applications Homebrew cask). Excludes `pkg` casks, which need the
    /// system installer — see `requiresInstaller`.
    ///
    /// A Homebrew result only ever reaches us when the app was *actually*
    /// installed via Homebrew (the source gates on the local Caskroom), so
    /// `brew install --cask --force` here updates through the app's real
    /// channel — no cross-channel mixing.
    public static func canAutoInstall(
        _ result: UpdateResult,
        settings: UpdateSettings,
        environment: InstallEnvironment
    ) -> Bool {
        // The app's own updater already staged *the latest* for relaunch — installing
        // it ourselves would re-download the same bytes and collide with the pending
        // ShipIt swap. Defer to Relaunch. (A staged build that *trails* the latest
        // isn't actionable as Relaunch, so we still offer Update — a direct jump.)
        if actionableStaged(result, staged: environment.stagedSelfUpdates[result.id]) != nil { return false }
        switch result.remote?.sourceName {
        case "Sparkle":
            // Signed feed: the full EdDSA path — needs both the app's SUPublicEDKey
            // and a signature in the item.
            if result.app.sparkleEdPublicKey?.isEmpty == false {
                return result.remote?.edSignature != nil
            }
            // Unsigned feed (no SUPublicEDKey, e.g. Fork): best-effort one-click.
            // `SparkleInstaller` gates the download on code signature + same Team +
            // same bundle id instead of EdDSA (identical to Vendor/GitHub). Offer it
            // only when the enclosure is an archive we can extract and swap in place
            // — a `.pkg` is a system-installer payload, not an in-place archive, and
            // a missing URL leaves nothing to install.
            let ext = result.remote?.downloadURL?.pathExtension.lowercased()
            return ext.map {
                ["dmg", "zip", "gz", "bz2", "xz", "tar", "tbz", "tgz", "app"].contains($0)
            } ?? false
        case "Homebrew":
            return result.remote?.sourceIdentifier != nil
                && result.remote?.requiresManualInstaller == false
        case "Vendor", "GitHub":
            // A vendor-website or GitHub-release app with a resolved installer
            // archive (zip/dmg/tar.gz). We download it, verify the code signature
            // matches the installed app's Team ID, then swap in place — same
            // channel, no mix. GitHub rules without an asset pattern stay
            // detection-only (vendorInstallerKind nil), so they fall through here.
            return result.remote?.vendorInstallerKind != nil
                && result.remote?.requiresManualInstaller == false
        case "App Store":
            // Requires the adamID, and that the app is installable here: not
            // region-locked and not a newer build that dropped Mac support. Both
            // routes replay the store's own download, so it's the app's real update
            // channel — no mixing. Which route depends on the user's preference:
            //   • full        → mas CLI; offered only when mas is actually installed
            //     (else we fall through to the App Store deep link).
            //   • incremental → AX-driven; needs no mas. Accessibility is requested
            //     on demand at install time (mirroring App Management), so we don't
            //     gate the offer on it here.
            // iOS-on-Mac apps (wrapped iPhone/iPad bundles) are never a one-click:
            // `mas` has no Mac-store entry to install (it errors "No apps found for
            // ADAM ID"), and the AX route is too unreliable for them. Only the App
            // Store app itself updates these, so the row offers an "Open in App
            // Store" redirect instead (see the App Store branch in both row views).
            guard let info = result.remote?.appStore,
                  !info.isRegionMismatch, !info.isLatestMacIncompatible,
                  !result.app.isiOSAppOnMac else { return false }
            switch settings.appStoreUpdateStrategy {
            // `.full` now routes mas through the privileged helper — offered only
            // once the helper is approved (else the row falls back to App Store "Get").
            // Reads the observable mirror so rows re-render the moment it's approved.
            case .full:        return environment.isHelperEnabled
            case .incremental: return true
            }
        default:
            return false
        }
    }

    /// True when this update is a `pkg` (a `pkg` cask, or a vendor pkg): we
    /// download the official package and open it in the system installer (which
    /// prompts for admin itself).
    ///
    /// For Vendor we key strictly on a `.pkg` install spec — NOT on
    /// `requiresManualInstaller`, which a *detection-only* vendor recipe also
    /// sets (meaning "send the user to download by hand"). Conflating the two
    /// made detection-only apps (LM Studio, Chrome, …) wrongly show an installer
    /// button pointed at their version-check endpoint.
    public static func requiresInstaller(
        _ result: UpdateResult,
        environment: InstallEnvironment
    ) -> Bool {
        // Same as `canAutoInstall`: only a staged build that *is* the latest is
        // relaunch-only; one that trails the latest still gets a normal installer.
        if actionableStaged(result, staged: environment.stagedSelfUpdates[result.id]) != nil { return false }
        switch result.remote?.sourceName {
        case "Homebrew":
            return result.remote?.requiresManualInstaller == true
        case "Vendor", "GitHub":
            return result.remote?.vendorInstallerKind == .pkg
        default:
            return false
        }
    }

    /// Whether, per the user's `vendorInstallPolicy`, this update should be handed
    /// to the app's OWN updater rather than installed over by us right now. True for
    /// running self-updating apps when the policy is `.deferWhenRunning`. A
    /// not-running app (nothing to disturb) or the `.alwaysOverwrite` policy installs
    /// in place as usual. Detection-only vendor apps (no installable spec) already
    /// just "Open" their update path, so they're excluded here.
    public static func defersToSelfUpdater(
        _ result: UpdateResult,
        settings: UpdateSettings,
        environment: InstallEnvironment
    ) -> Bool {
        guard settings.vendorInstallPolicy == .deferWhenRunning,
              isRunning(result, environment: environment),
              canAutoInstall(result, settings: settings, environment: environment)
                || requiresInstaller(result, environment: environment)
        else { return false }
        switch result.remote?.sourceName {
        case "Vendor":
            return true
        case "Sparkle":
            return result.app.sparkleFeedURL != nil
        case "GitHub":
            // GitHub-sourced apps ship their own updaters just as much as the
            // vendor-probed ones do — the recipes say so themselves (Zed: "has a
            // robust built-in updater, so this is a fallback"; Zen: "a Firefox
            // fork with its own updater"; GitHub Desktop: Squirrel; Ollama:
            // "ships its own updater"). They were absent from this switch, so
            // they fell to `default: false` and had their bundles swapped under
            // them while running even when the user had explicitly asked us not
            // to — the one thing this setting exists to promise.
            return true
        default:
            // Homebrew (auto_updates casks are excluded upstream), App Store and
            // Toolbox all hand the install to something that manages the app
            // itself, so there is no bundle of ours to defer.
            return false
        }
    }

    /// Whether *this exact install* currently has a running process — drives the
    /// green "live" dot in the menu and workbench, and the defer-to-self-updater
    /// decision. Matched on the bundle path so a second copy of the same app
    /// (same bundle id, different path) doesn't falsely light up when only the
    /// other copy is open.
    public static func isRunning(_ result: UpdateResult, environment: InstallEnvironment) -> Bool {
        environment.runningAppPaths.contains(runtimeBundlePath(result.app.path))
    }

    /// The staged self-update to surface as **Relaunch** — but only when the staged
    /// build is actually the version the app's channel now offers. Apps download
    /// releases one at a time, so a staged build can already trail a newer release;
    /// relaunching to it would still leave the user a download behind. In that case
    /// we return nil so the row falls back to the normal **Update** (a direct jump
    /// to the latest) instead of a Relaunch that doesn't get you current. "Relaunch"
    /// thus means exactly: the latest is already downloaded, just restart — zero
    /// extra download.
    public static func actionableStaged(
        _ result: UpdateResult,
        staged: StagedSelfUpdate?
    ) -> StagedSelfUpdate? {
        guard let staged else { return nil }
        if let latest = result.remote?.displayVersion,
           VersionComparator.isNewer(latest, than: staged.version) {
            return nil  // staged trails the latest — show Update, not Relaunch
        }
        return staged
    }

    /// Normalize app bundle paths reported by running processes back to the live
    /// installed bundle. macOS can keep a process mapped to DuoUpdater's temporary
    /// `replaceItemAt` staging name after a hot swap; treating that hidden/deleted
    /// path as distinct makes running detection and Restart miss the exact app.
    public static func runtimeBundlePath(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        let name = resolved.lastPathComponent
        let parent = resolved.deletingLastPathComponent()
        let stagedPrefix = ".duoupdater-staged-"

        if name.hasPrefix(stagedPrefix) {
            let original = String(name.dropFirst(stagedPrefix.count))
            return parent.appendingPathComponent(original).resolvingSymlinksInPath().path
        }
        for suffix in [".duoupdater-old", ".duoupdater-new"] where name.hasSuffix(suffix) {
            let original = String(name.dropLast(suffix.count))
            return parent.appendingPathComponent(original).resolvingSymlinksInPath().path
        }
        return resolved.path
    }
}
