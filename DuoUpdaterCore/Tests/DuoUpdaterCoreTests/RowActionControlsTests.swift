import Foundation
import Testing
@testable import DuoUpdaterCore

/// What each window's row controls draw, from one set of facts.
///
/// Every case gives one `Facts` value and the output of BOTH windows for it, so
/// a difference between the two is written down where it can be read, rather
/// than being whatever two views happened to do. The expected values are what
/// the two views on main drew before these decisions moved here, with one
/// exception, the reason this type exists: a detection-only row whose page is
/// an app's own deep link. The popover handed it to the app; the workbench gave
/// it to a plain `NSWorkspace.open`. Both now hand it to the app.
struct RowActionControlsTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let state: RowActionState
        let facts: RowActionControls.Facts
        let popover: RowActionControls
        let workbench: RowActionControls
        var testDescription: String { name }

        /// The two windows draw the same.
        init(_ name: String, _ state: RowActionState, _ facts: RowActionControls.Facts = .init(),
             both: RowActionControls) {
            self.name = name
            self.state = state
            self.facts = facts
            self.popover = both
            self.workbench = both
        }

        init(_ name: String, _ state: RowActionState, _ facts: RowActionControls.Facts = .init(),
             popover: RowActionControls, workbench: RowActionControls) {
            self.name = name
            self.state = state
            self.facts = facts
            self.popover = popover
            self.workbench = workbench
        }
    }

    static let page = URL(string: "https://example.com/download")!
    static let deepLink = URL(string: "chrome://settings/help")!
    static let paused = Date(timeIntervalSince1970: 2_000_000_000)

    /// Everything a row's controls can read, switched on. A state that carries
    /// none of these must come out empty even so.
    static let everything = RowActionControls.Facts(
        installCancel: .available, retryPausedUntil: paused, keepBackups: false,
        helperEnabled: false, channelSwitch: .nightly, pageURL: deepLink)

    static let cases: [Case] = [
        // MARK: The Cancel and the progress beside it
        Case("downloading, Cancel live", .installing(.downloading(fraction: 0.42)),
             .init(installCancel: .available),
             both: .init(cancel: .available, progress: .fraction(0.42))),
        // Accepted: "Cancelling…" replaces the Cancel AND the bar, which would
        // only freeze on a download that stopped.
        Case("downloading, cancel accepted", .installing(.downloading(fraction: 0.42)),
             .init(installCancel: .cancelling),
             both: .init(progress: .spinner)),
        Case("extracting, committing", .installing(.extracting),
             .init(installCancel: .committing),
             both: .init(cancel: .committing, progress: .spinner)),
        Case("installing, cancel came too late", .installing(.installing),
             .init(installCancel: .tooLate),
             both: .init(cancel: .tooLate, progress: .spinner)),
        // No install of ours on the row — a rollback, a re-check: no Cancel.
        Case("downloading, no install of ours", .installing(.downloading(fraction: 0.1)),
             both: .init(progress: .fraction(0.1))),
        Case("queued, no install of ours", .installing(.queued),
             both: .init(progress: .spinner)),

        // MARK: Retry
        Case("rate-limited, budget closed", .checkFailed(message: "403", rateLimited: true),
             .init(retryPausedUntil: paused),
             both: .init(offersRetry: false)),
        Case("rate-limited, budget open", .checkFailed(message: "403", rateLimited: true),
             both: .init(offersRetry: true)),
        // A closed budget is GitHub's; a check that failed some other way is
        // retried through no gate.
        Case("failed otherwise, budget closed", .checkFailed(message: "timed out", rateLimited: false),
             .init(retryPausedUntil: paused),
             both: .init(offersRetry: true)),

        // MARK: The channel-switch hint, and the major-upgrade confirmation
        Case("auto-install switching channel", .updateAvailable(.autoInstall),
             .init(channelSwitch: .nightly),
             both: .init(channelSwitch: .init(channel: .nightly, placement: .besideControl))),
        Case("installer switching channel", .updateAvailable(.installer(stagedFileName: "Lapce.pkg")),
             .init(channelSwitch: .beta),
             both: .init(channelSwitch: .init(channel: .beta, placement: .besideControl))),
        Case("auto-install, same channel", .updateAvailable(.autoInstall),
             both: .init()),
        // The deliberate difference: the popover confirms in a panel of its own,
        // which carries the reminder and, with backups off, Back Up & Update;
        // the workbench names it beside the hint and points there.
        Case("major upgrade switching channel, backups off", .updateAvailable(.majorUpgrade),
             .init(keepBackups: false, channelSwitch: .nightly),
             popover: .init(
                offersBackUpOnce: true,
                channelSwitch: .init(channel: .nightly, placement: .inConfirmation)),
             workbench: .init(channelSwitch: .init(channel: .nightly, placement: .besideControl))),
        Case("major upgrade, backups on", .updateAvailable(.majorUpgrade),
             .init(keepBackups: true),
             both: .init()),
        // A redirect installs nothing here, so there is nothing to remind about.
        Case("self-updater switching channel", .updateAvailable(.selfUpdater),
             .init(channelSwitch: .nightly),
             both: .init()),

        // MARK: The App Store redirect
        Case("iPhone app, helper off", .updateAvailable(.appStore(managedHere: true, gate: .none)),
             .init(helperEnabled: false),
             both: .init(appStoreRedirect: .iPhoneApp)),
        Case("store app, helper off", .updateAvailable(.appStore(managedHere: false, gate: .none)),
             .init(helperEnabled: false),
             both: .init(appStoreRedirect: .helperOff)),
        Case("store app, helper on", .updateAvailable(.appStore(managedHere: false, gate: .none)),
             .init(helperEnabled: true),
             both: .init(appStoreRedirect: .openStore)),
        // A gated listing is a badge or a label, not a redirect.
        Case("region-locked", .updateAvailable(.appStore(managedHere: false, gate: .region)),
             .init(helperEnabled: false),
             both: .init()),

        // MARK: Detection-only
        Case("detection-only, web page", .updateAvailable(.detectionOnly),
             .init(pageURL: page),
             both: .init(detectionOnly: .openPage(page))),
        // The divergence: the workbench used to open this with a plain
        // `NSWorkspace.open`. The popover's hand-off to the app is kept.
        Case("detection-only, app deep link", .updateAvailable(.detectionOnly),
             .init(pageURL: deepLink),
             both: .init(detectionOnly: .openInApp(deepLink))),
        Case("detection-only, no page", .updateAvailable(.detectionOnly),
             both: .init(detectionOnly: .revealInFinder)),

        // MARK: States that carry none of it, whatever the facts say
        Case("relaunch prompt", .awaitingQuitConfirm("Example"), everything, both: .init()),
        Case("just updated", .justUpdated, everything, both: .init()),
        Case("ignored", .ignored, everything, both: .init()),
        Case("staged relaunch", .relaunchToApplyStaged(to: "2.0"), everything, both: .init()),
        Case("toolbox route", .updateAvailable(.toolbox), everything, both: .init()),
        Case("TestFlight route", .updateAvailable(.testFlight), everything, both: .init()),
        Case("Apple sign-in route", .updateAvailable(.appleSignIn(.expired)), everything, both: .init()),
        Case("no source", .noSourceCovers(hint: .sparkle), everything, both: .init()),
        Case("managed by Toolbox", .managedElsewhere(.toolbox), everything, both: .init()),
        Case("up to date", .upToDate(channel: .none), everything, both: .init()),
    ]

    /// Mutation: in `resolve`, drop `rateLimited &&` from the Retry → "failed
    /// otherwise, budget closed" red; drop `!cancelling` from the Cancel →
    /// "downloading, cancel accepted" red; place the popover's major-upgrade
    /// hint `.besideControl` → its case red.
    @Test(arguments: cases)
    func eachWindowDrawsItsControls(_ c: Case) {
        #expect(RowActionControls.resolve(c.state, facts: c.facts, surface: .popover) == c.popover)
        #expect(RowActionControls.resolve(c.state, facts: c.facts, surface: .workbench) == c.workbench)
    }

    /// The windows differ where `Surface` says they do — the major-upgrade
    /// confirmation — and nowhere else. A view-side `if` that one window grew
    /// and the other did not is exactly what this type replaced.
    @Test(arguments: cases)
    func theWindowsAgreeOutsideTheConfirmation(_ c: Case) {
        var popover = RowActionControls.resolve(c.state, facts: c.facts, surface: .popover)
        let workbench = RowActionControls.resolve(c.state, facts: c.facts, surface: .workbench)
        if case .updateAvailable(.majorUpgrade) = c.state {
            popover.offersBackUpOnce = false
            popover.channelSwitch?.placement = .besideControl
        }
        #expect(popover == workbench)
    }

    /// The facts a row view builds read the row's own channel switch and page.
    /// Mutation: leave `channelSwitch` or `pageURL` out of `Facts(result:…)` → red.
    @Test func factsFromARowReadItsChannelSwitchAndPage() {
        var remote = RemoteVersion(
            shortVersion: "0.4.6", version: nil,
            downloadURL: URL(string: "https://example.com/Lapce.dmg"),
            pageURL: Self.page,
            sourceName: "Homebrew", sourceIdentifier: "lapce")
        remote.offeredChannel = .stable
        let result = UpdateResult(
            app: InstalledApp(
                name: "Lapce", bundleID: "io.lapce", shortVersion: "0.4.5", buildVersion: "1",
                path: URL(fileURLWithPath: "/Applications/Lapce.app"),
                isMASApp: false, sparkleFeedURL: nil, releaseChannel: .nightly),
            remote: remote, status: .updateAvailable(latest: "0.4.6"))

        let facts = RowActionControls.Facts(
            result: result, installCancel: nil, retryPausedUntil: nil, helperEnabled: true)

        #expect(facts.channelSwitch == .nightly)
        #expect(facts.pageURL == Self.page)
        #expect(RowActionControls.resolve(.updateAvailable(.autoInstall), facts: facts, surface: .workbench)
                .channelSwitch == ChannelSwitchHint(channel: .nightly, placement: .besideControl))
    }
}
