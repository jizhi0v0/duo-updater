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
    /// Bundle paths (normalized through `runtimeBundlePath`, like
    /// `runningAppPaths`) whose install location we cannot write, so replacing
    /// them raises an administrator prompt. A filesystem fact, so it is observed
    /// by the host — via `InPlaceSwap.needsElevatedReplace`, the same predicate
    /// the swap itself branches on — and handed in, keeping the policy pure.
    public var elevationRequiredPaths: Set<String>
    /// Bundle identifiers with at least one live process — the running side for
    /// bundles whose running copy cannot be recognised by path.
    ///
    /// A wrapped iPhone/iPad app is the case that needs this. Its process reports
    /// a per-launch shadow container as its `bundleURL`, not the bundle the user
    /// installed: measured on macOS 26 (2026-08-29) for Aqara Home, `bundleURL`
    /// was `/private/var/folders/…/X/<uuid>/d/Wrapper/AqaraHome.app` while the
    /// install lives at `/Applications/Aqara Home.app`. No amount of symlink
    /// resolution turns one into the other, so `runningAppPaths` cannot contain
    /// a running wrapped app and every path-keyed "is it running?" answers no.
    /// The identifier is unaffected (`com.lumiunited.pre.homekit` either way).
    public var runningBundleIDs: Set<String>

    public init(
        isHelperEnabled: Bool,
        runningAppPaths: Set<String>,
        stagedSelfUpdates: [String: StagedSelfUpdate],
        elevationRequiredPaths: Set<String> = [],
        runningBundleIDs: Set<String> = []
    ) {
        self.isHelperEnabled = isHelperEnabled
        self.runningAppPaths = runningAppPaths
        self.stagedSelfUpdates = stagedSelfUpdates
        self.elevationRequiredPaths = elevationRequiredPaths
        self.runningBundleIDs = runningBundleIDs
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
        // The user was asked for an administrator password for this exact install
        // and said no. Keeping the Update button would re-raise that panel on every
        // release; this is the only branch here that turns a *previously offered*
        // one-click off, and only the user can turn it back on (row context menu).
        if elevationDeclined(result, settings: settings, environment: environment) { return false }
        // An input method is registered with the system, not merely copied: the
        // vendor's installer calls `TISRegisterInputSource` on the bundle PATH
        // (WeType's installer binary carries "Registered input source from
        // /Library/Input Methods/WeType.app, result:"). What that makes special is
        // the outer `.app` directory, not the code inside it — which is why both
        // vendors' own updaters keep that directory and rotate what is inside
        // (`WeType.app/.Contents.update` → `Contents` → `.Contents.old`;
        // DoubaoIme's `Contents_update` / `Contents_backup`), while only their
        // *installers* replace the whole bundle.
        //
        // So the one-click is allowed here exactly when the update can be applied
        // that same way — `InPlaceSwap.rotateContents`, reached with a plain app
        // bundle. A `.pkg`, a Homebrew cask re-run, or an App Store replay all
        // replace the outer directory instead, and none of them is a route any
        // input method on record actually has.
        //
        // History, because this was reversed once: the WeType one-click shipped in
        // 0.3.25 and was withdrawn the same day (2026-08-16) after a user's
        // settings went missing, and the evidence never convicted a specific step
        // — the elevated swap provably never ran on that machine. It came back on
        // 2026-08-28 with the two things that were actually missing: an install
        // shaped like the vendor's own update, and a snapshot of the user data the
        // incident was about (`InputMethodDataBackup`), taken with the bundle
        // rollback point and restorable with it.
        if isInputMethod(result.app.path), !isContentsRotatable(result) { return false }
        // The app's own updater already staged *the latest* for relaunch — installing
        // it ourselves would re-download the same bytes and collide with the pending
        // ShipIt swap. Defer to Relaunch. (A staged build that *trails* the latest
        // isn't actionable as Relaunch, so we still offer Update — a direct jump.)
        if actionableStaged(result, staged: environment.stagedSelfUpdates[result.id]) != nil { return false }
        switch result.remote?.sourceName {
        case "Sparkle":
            let ext = result.remote?.downloadURL?.pathExtension.lowercased()
            // A package is not an in-place archive. Signed Sparkle packages are
            // still installable, but `requiresInstaller` owns them so the download
            // is EdDSA-verified and then handed to macOS Installer. Keeping them out
            // of this branch prevents `SparkleInstaller` from feeding a `.pkg` to
            // `ArchiveExtractor`, which can never extract it.
            if Self.sparklePackageExtensions.contains(ext ?? "") { return false }
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
            return ext.map {
                Self.sparkleArchiveExtensions.contains($0)
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
            guard let info = result.remote?.appStore,
                  !info.isRegionMismatch, !info.isLatestMacIncompatible else { return false }
            switch settings.appStoreUpdateStrategy {
            // `.full` routes mas through the privileged helper — offered only once
            // the helper is approved (else the row falls back to an App Store
            // redirect). Reads the observable mirror so rows re-render the moment
            // it's approved.
            //
            // iOS-on-Mac apps (wrapped iPhone/iPad bundles) are excluded from *this*
            // route only: `mas` has no Mac-store entry for them and errors "No apps
            // found for ADAM ID".
            case .full:        return environment.isHelperEnabled && !result.app.isiOSAppOnMac
            // The AX route presses the product page's own Update button, and that
            // page is structurally what a native Mac app gets: one
            // `AppStore.productPage`, one `AppStore.shelfItem.ProductLockup…` hero
            // naming the app, one `AppStore.offerButton` titled "Update" inside it.
            // Probed live on macOS 26 (Nowdex, 2026-08-29): `heroOwnsPage` true and
            // `ownButtonCount` 1 — the pair `AppStoreAXInstaller.shouldPress`
            // requires — and driving it installed the update. "Designed for iPad.
            // Not verified for macOS." is a subtitle in that hero, not a barrier;
            // the developer-opted-out case is `isLatestMacIncompatible`, guarded
            // above for both routes.
            case .incremental: return true
            }
        default:
            return false
        }
    }

    /// Whether installing over *this exact install* has to go through an
    /// administrator prompt, because its enclosing directory is not ours to write
    /// (`/Library/Input Methods`, a root-owned `/Applications`). Matched on the
    /// bundle path, like `isRunning`, so a second copy of the same app elsewhere
    /// doesn't inherit the answer.
    public static func requiresElevatedInstall(
        _ result: UpdateResult,
        environment: InstallEnvironment
    ) -> Bool {
        environment.elevationRequiredPaths.contains(runtimeBundlePath(result.app.path))
    }

    /// The declined leg of the tri-state: this install needs an administrator
    /// prompt **and** the user has already refused one for it. Never asked and
    /// authorized both read false here, so the row keeps its Update button — we
    /// only ever demote a row the user personally said no to.
    ///
    /// Both halves are required. Without the first, a stale decline recorded when
    /// an app lived somewhere unwritable would keep suppressing its one-click
    /// after it moved somewhere we can write, with nothing in the UI explaining
    /// why. Without the second, this is just "needs a password", which is not a
    /// reason to withhold anything.
    public static func elevationDeclined(
        _ result: UpdateResult,
        settings: UpdateSettings,
        environment: InstallEnvironment
    ) -> Bool {
        requiresElevatedInstall(result, environment: environment)
            && ElevationRules.isDeclined(result.app, declinedKeys: settings.declinedElevationKeys)
    }

    /// Whether this update can be applied to an input method the only way we will
    /// apply one — by exchanging the bundle's `Contents`, which needs the download
    /// to *be* an app bundle. Deliberately stricter than the source branches
    /// below: those accept a `.pkg` for the Vendor route (`requiresInstaller` owns
    /// it), and a package is not something that can be rotated into place.
    static func isContentsRotatable(_ result: UpdateResult) -> Bool {
        switch result.remote?.sourceName {
        case "Vendor", "GitHub":
            guard let kind = result.remote?.vendorInstallerKind else { return false }
            return kind != .pkg
        case "Sparkle":
            let ext = result.remote?.downloadURL?.pathExtension.lowercased() ?? ""
            return Self.sparkleArchiveExtensions.contains(ext)
        default:
            return false
        }
    }

    /// Whether a bundle lives in one of macOS's input-method directories, whose
    /// contents are registered with the system rather than merely present on disk.
    /// Matched on the containing directory, not the app, so it holds for any
    /// vendor — `/Library/Input Methods` (system-wide) and its per-user twin.
    public static func isInputMethod(_ bundle: URL) -> Bool {
        let parent = bundle.deletingLastPathComponent().standardizedFileURL.path
        return parent.hasSuffix("/Library/Input Methods")
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
        // An input method is never handed to the system installer. This is not a
        // second opinion about the same question `canAutoInstall` answers — it is
        // the way AROUND that question: every caller offers the row on
        // `canAutoInstall || requiresInstaller`, so a gate that lives only in the
        // first is satisfied by the second being true. Today's two recipes are
        // both `.zip`, so nothing reaches here; the point is that a vendor
        // switching artifact, or a one-word `kind:` edit, would otherwise turn a
        // Contents rotation into a root-run vendor package over a registered input
        // source with no code change and no gate firing. `PackageInstaller`'s
        // destination check does not close it either — it hard-refuses only inside
        // `/Applications` and falls back to matching a bundle name anywhere else.
        if isInputMethod(result.app.path) { return false }
        switch result.remote?.sourceName {
        case "Homebrew":
            return result.remote?.requiresManualInstaller == true
        case "Vendor", "GitHub":
            return result.remote?.vendorInstallerKind == .pkg
        case "Sparkle":
            // Sparkle permits signed package enclosures. They must retain Gate 1
            // (EdDSA over the exact enclosure bytes) before PackageInstaller applies
            // its Developer ID Installer + Team-ID gate. An unsigned package stays
            // detection-only: unlike an extracted app, it has no bundle-id gate.
            guard let ext = result.remote?.downloadURL?.pathExtension.lowercased(),
                  Self.sparklePackageExtensions.contains(ext),
                  result.app.sparkleEdPublicKey?.isEmpty == false,
                  result.remote?.edSignature?.isEmpty == false else { return false }
            return true
        default:
            return false
        }
    }

    private static let sparkleArchiveExtensions: Set<String> = [
        "dmg", "zip", "gz", "bz2", "xz", "tar", "tbz", "tgz", "app",
    ]

    private static let sparklePackageExtensions: Set<String> = ["pkg", "mpkg"]

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
        // Path is the discriminator everywhere it can be: two copies of the same
        // app in different places are different installs, and only the one being
        // replaced should read as running.
        //
        // A wrapped iPhone/iPad app is the exception, and not by preference — its
        // running process reports a shadow container path that can never equal the
        // installed bundle (see `InstallEnvironment.runningBundleIDs`). Falling
        // back to the identifier costs nothing here: these are store-installed and
        // singular, so "another copy elsewhere" is not a state that arises.
        if result.app.isiOSAppOnMac, let bundleID = result.app.bundleID {
            return environment.runningBundleIDs.contains(bundleID)
        }
        return environment.runningAppPaths.contains(runtimeBundlePath(result.app.path))
    }

    /// The vendor's advertised version when it is strictly *older* than what is
    /// installed — the muted "you're ahead, nothing to do" note. Returns the older
    /// version to show, or nil when there is nothing to say.
    ///
    /// Gated to **stable** installs: a beta or canary build is expected to lead the
    /// stable feed, so flagging it would cry wolf on every beta user. Managed
    /// sources (App Store, TestFlight, Toolbox) answer through laggy or regional
    /// lookups where "installed > remote" is routinely just staleness, so they are
    /// excluded too.
    ///
    /// Builds settle it whenever both sides have one. `UpdateChecker.evaluate`
    /// already prefers the build there, and a source is free to put a human label
    /// in `shortVersion` — Xcode advertises "27.0 beta 5 (27A5237l)" against an
    /// installed "27.0", and `27.0` really is newer than `27.0 beta 5` under
    /// release-versus-prerelease ordering. Comparing those two strings therefore
    /// announced a downgrade for a copy sitting on the very same build.
    public static func laggingRemoteVersion(_ result: UpdateResult) -> String? {
        guard result.app.releaseChannel == .stable, !result.hasUpdate else { return nil }
        guard !result.app.isMASApp, !result.app.isTestFlightApp, !result.app.isToolboxManaged
        else { return nil }
        // Same build on both sides is the same release, whatever the labels read.
        // Read in the namespace the source declared: a build compared across
        // namespaces is never equal, so this early-out would simply stop firing.
        // Unreachable for the vendor namespace today — the only recipes in it are
        // pre-release and this is stable-only — and stated rather than left for
        // the first stable one to discover.
        if let remote = result.remote,
           let installedBuild = result.app.buildVersion(in: remote.buildNamespace),
           !installedBuild.isEmpty,
           let remoteBuild = remote.version, !remoteBuild.isEmpty,
           installedBuild == remoteBuild {
            return nil
        }
        guard let installed = result.app.shortVersion,
              let remoteShort = result.remote?.shortVersion,
              VersionComparator.isNewer(installed, than: remoteShort) else { return nil }
        return result.remote?.displayVersion ?? remoteShort
    }

    /// Which rows have *settled* — reached a state where anything we recorded
    /// about an attempt on them no longer describes something real, and so should
    /// be dropped when the row list is rebuilt.
    ///
    /// Two callers, one question. An install error is about one attempt at one
    /// version, and every place that writes one is the *start of another action on
    /// that row* — install, rollback, the helper buttons. Nothing on the refresh
    /// path cleared one, so a failure message outlived the failure: reported
    /// against the machine-wide install lock, where `duo install` finished the
    /// update, the row went to "up to date ✓", and "another DuoUpdater install is
    /// in progress (process 76712)" stayed under it through every rescan until the
    /// app was relaunched. The in-flight *notes* ("brought it to the front so its
    /// own updater applies the update") sit in the same place in the row and had
    /// the same defect.
    ///
    /// The discriminator is the row's own verdict, and specifically NOT "the row
    /// has no update pending": a networked refresh blanks every row to `.unknown`
    /// before the check repopulates it, so that reading would quietly wipe every
    /// error on every refresh — which is the behaviour this is meant to avoid. A
    /// row that still has its update pending keeps its reason (a background check
    /// must not erase "needs App Management permission" before it has been read),
    /// and a row mid-install has not settled yet whatever its last verdict says.
    ///
    /// Only `.upToDate` settles. Every other verdict is a non-answer wearing a
    /// different label: `UpdateChecker` reaches `.appStoreManaged`,
    /// `.toolboxManaged` and `.testFlightManaged` from the *same* "no source could
    /// answer" branch that produces `.unknown` for everything else, so treating
    /// them as settlements would delete a live error on nothing more than a
    /// transient lookup miss. That is not hypothetical for App Store rows, where
    /// the error text is also what gates the row's recovery buttons
    /// (`showsHelperApprovalFallback` and friends read `installErrors`): one
    /// unanswered check would take away the message *and* the only route to the
    /// fix, with the update still not installed.
    ///
    /// An id with no row at all is settled too — that app is no longer installed.
    public static func settledRowIDs(
        _ ids: some Sequence<String>,
        results: [UpdateResult],
        installing: Set<String>
    ) -> Set<String> {
        // No rows at all is the pre-first-scan state, not "every app vanished".
        guard !results.isEmpty else { return [] }
        let byID = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var settled: Set<String> = []
        for id in ids where !installing.contains(id) {
            guard let row = byID[id] else {
                settled.insert(id)   // the app is gone from disk
                continue
            }
            // Written out rather than `!hasUpdate` so a new status has to be
            // classified here instead of silently defaulting either way.
            switch row.status {
            case .upToDate:
                settled.insert(id)
            case .updateAvailable, .unknown, .error,
                 .appStoreManaged, .toolboxManaged, .testFlightManaged:
                break
            }
        }
        return settled
    }

    /// Which of the row notes this app wrote to describe *an action still in
    /// progress* should now be retracted.
    ///
    /// `installNotes` carries two kinds of text that read the same in the row but
    /// age in opposite directions:
    ///
    ///   * an action in flight — "brought it to the front so its own updater
    ///     applies the update", "opened the installer … finish it there". True
    ///     only until the thing it describes happens; afterwards it is a claim
    ///     about the present that the user has no way to dismiss.
    ///   * a standing fact about an install that already happened — "this update
    ///     was applied without a rollback point". The row settling is exactly when
    ///     that becomes *readable*, and clearing it then is how it once became
    ///     unreadable to everyone (see `AppListModel.inFlightNotes`).
    ///
    /// Nothing about the text distinguishes them, so the caller registers the
    /// in-flight ones as it writes them and passes that registry here. Matching on
    /// the text and not just the id is what keeps this from retracting a note some
    /// other writer put there in the meantime.
    public static func retractableNoteIDs(
        notes: [String: String],
        writtenByUs inFlight: [String: String],
        results: [UpdateResult],
        installing: Set<String>
    ) -> Set<String> {
        guard !inFlight.isEmpty else { return [] }
        let settled = settledRowIDs(inFlight.keys, results: results, installing: installing)
        return settled.filter { notes[$0] == inFlight[$0] }
    }

    /// The staged self-update that makes installing pointless right now, or nil.
    ///
    /// Distinct from `actionableStaged`, and deliberately laxer: that one asks "is
    /// a relaunch enough to get current?", which requires the staged build to be
    /// the latest. This asks "will anything we install survive?", and the answer is
    /// no for **any** staged build, including one that trails what is on disk. The
    /// parked installer applies it on the next quit regardless of which way the
    /// version comparison goes, so an install performed in the meantime is undone.
    ///
    /// That a trailing staged build still gets applied is established: on 2026-08-22
    /// the mini installed 6971 and ChatGPT's own updater applied 6962 at 14:53,
    /// finishing on the OLDER version. That particular collision was not preventable
    /// from here — the staging happened after our install, so nothing was visible to
    /// check — but it is why this must not filter on "newer": when a trailing build
    /// IS already staged, installing over it is just as futile.
    ///
    /// Callers pass the staged build from
    /// `SelfUpdaterStaging.staged(for:requireNewerThanInstalled: false)`.
    public static func stagedBlocksInstall(
        _ result: UpdateResult,
        staged: StagedSelfUpdate?
    ) -> StagedSelfUpdate? {
        guard let staged else { return nil }
        // A staged build EQUAL to what is on disk has already been applied; the
        // directory just hasn't been swept yet. Dropping the "must be newer" filter
        // to catch trailing builds would otherwise let such leftovers block installs
        // forever, which is worse than the collision this prevents. Trailing-but-
        // different still blocks: that one has not been applied and will be.
        let stagedV = staged.buildVersion ?? staged.version
        if let installedV = result.app.buildVersion ?? result.app.shortVersion,
           stagedV == installedV { return nil }
        // Nothing to protect on routes we do not swap ourselves — Homebrew, the App
        // Store and Toolbox hand the install to something that owns the bundle, so a
        // stale staging directory belonging to a different mechanism must not block
        // them.
        switch result.remote?.sourceName {
        case "Vendor", "GitHub", "Sparkle": return staged
        default:                            return nil
        }
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
        // Relaunching must move the app FORWARD. A staged build at or below what is
        // installed would apply a downgrade, and `relaunchStagedUpdate` waits for the
        // on-disk version to advance — so it would spin for its full timeout and
        // report failure for a swap that did happen.
        //
        // Callers have always filled the staged map through
        // `staged(requireNewerThanInstalled:)` at its default of `true`, which made
        // this true by construction. It is asserted here because that is no longer
        // the only way to get a `StagedSelfUpdate`: the install gate deliberately
        // asks for trailing builds too (`stagedBlocksInstall`), and handing one of
        // those to this function must not produce a Relaunch.
        if !result.app.versionSide.isEmpty,
           !VersionComparator.isNewer(staged.versionSide, than: result.app.versionSide) {
            return nil
        }
        // Compared as PAIRS, not as `displayVersion` against `staged.version`.
        // Both of those are marketing strings, so for an app that ships many
        // builds under one name they are equal every time and this gate passed a
        // staged build that trailed the latest — measured on Amp 2026-08-28,
        // which offered Relaunch to build 129 while 130 was out. See
        // `VersionComparator.isNewer(_:than:)` for why the build only decides
        // when the marketing versions tie.
        if let latest = result.remote?.versionSide, !latest.isEmpty,
           VersionComparator.isNewer(latest, than: staged.versionSide) {
            return nil  // staged trails the latest — show Update, not Relaunch
        }
        return staged
    }

    /// A staged self-update the user still wants to hear about.
    ///
    /// `actionableStaged` answers one question — is the staged build the latest?
    /// — and knows nothing about the user's own verdict on the app. The periodic
    /// "Relaunch to apply it" reminder used it directly, so an **ignored** app
    /// kept posting a banner every reminder tick while its row showed nothing but
    /// the Ignored tag: hidden in the app, still nagging in Notification Center.
    /// Ignore and skip both mean "stop telling me about this", so both are gates
    /// here, not just on the updates-available path.
    public static func nudgeableStaged(
        _ result: UpdateResult,
        staged: StagedSelfUpdate?,
        isIgnored: Bool,
        isVersionSkipped: (VersionSide) -> Bool
    ) -> StagedSelfUpdate? {
        guard !isIgnored else { return nil }
        guard let staged = actionableStaged(result, staged: staged) else { return nil }
        return isVersionSkipped(staged.versionSide) ? nil : staged
    }

    /// Normalize app bundle paths reported by running processes back to the live
    /// installed bundle. macOS can keep a process mapped to DuoUpdater's temporary
    /// `replaceItemAt` staging name after a hot swap; treating that hidden/deleted
    /// path as distinct makes running detection and Relaunch miss the exact app.
    ///
    /// Rewrites **every** component, not just the last one. An app nested inside
    /// another app's bundle — Surge ships `Surge.app/Contents/Applications/Surge
    /// Dashboard.app`, and it is a full app with its own bundle id, not a helper
    /// the parent process owns — reports a path whose staged component is in the
    /// middle:
    ///
    ///     /Applications/.duoupdater-staged-Surge.app/Contents/Applications/Surge Dashboard.app
    ///
    /// Normalising the leaf alone left that string untouched, so nothing could
    /// tell that the process belonged to Surge at all, and the nested app went on
    /// running the pre-swap binary out of a bundle that had been moved aside.
    public static func runtimeBundlePath(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        let stagedPrefix = ".duoupdater-staged-"
        var components = resolved.pathComponents
        var rewrote = false
        for index in components.indices {
            let name = components[index]
            if name.hasPrefix(stagedPrefix) {
                components[index] = String(name.dropFirst(stagedPrefix.count))
                rewrote = true
                continue
            }
            for suffix in [".duoupdater-old", ".duoupdater-new"] where name.hasSuffix(suffix) {
                components[index] = String(name.dropLast(suffix.count))
                rewrote = true
                break
            }
        }
        guard rewrote else { return resolved.path }
        return URL(fileURLWithPath: NSString.path(withComponents: components))
            .resolvingSymlinksInPath().path
    }
}
