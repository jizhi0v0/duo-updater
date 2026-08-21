import Testing
import Foundation
@testable import DuoUpdaterCore

/// `ChannelSwitchDetector` is the pure comparison behind "recheck a
/// `ChannelBinding` app the moment its own channel toggle flips" (the Tailscale
/// Unstable→Stable bug: switching in Tailscale's own Settings left the row
/// pinned to the old unstable target until the next scheduled check). These pin
/// down: a real flip is reported, the first-ever sighting of an id never counts
/// as one, a feed-only change (no `.channel` change) is still caught, and the
/// fingerprint never leaks the raw feed/license data it's built from.

@Test func detectsAFlippedChannel() {
    let last = ["io.tailscale.ipn.macsys": ChannelSwitchDetector.fingerprint(.init(channel: .unstable))]
    let current = ["io.tailscale.ipn.macsys": ChannelSwitchDetector.fingerprint(.init(channel: .stable))]
    let (changed, next) = ChannelSwitchDetector.changes(current: current, lastSeen: last)
    #expect(changed == ["io.tailscale.ipn.macsys"])
    #expect(next == current)
}

@Test func noChangeReportsNothing() {
    let fp = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    let last = ["com.nssurge.surge-mac": fp]
    let current = ["com.nssurge.surge-mac": fp]
    let (changed, next) = ChannelSwitchDetector.changes(current: current, lastSeen: last)
    #expect(changed.isEmpty)
    #expect(next == current)
}

/// First-ever observation of an id (fresh install, first scan after relaunch,
/// or the id just entering `ChannelBinding`'s registry) must never read as a
/// "switch" — otherwise every bound app would trigger one needless recheck the
/// moment the menu-bar app (re)starts.
@Test func firstObservationIsNotAChange() {
    let fp = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    let (changed, next) = ChannelSwitchDetector.changes(
        current: ["com.colliderli.iina": fp], lastSeen: [:])
    #expect(changed.isEmpty)
    #expect(next == ["com.colliderli.iina": fp])
}

/// Covers every id `ChannelBinding` currently registers, so a channel added to
/// the registry later is automatically exercised here too — same "derive from
/// the registry, don't hand-write a list that drifts" rule the recipe/proof
/// tests already follow.
@Test func everyBoundIDFlipIsDetected() {
    let before = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let after = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    for id in ChannelBinding.boundBundleIDs {
        let (changed, _) = ChannelSwitchDetector.changes(
            current: [id: after], lastSeen: [id: before])
        #expect(changed == [id], "bound id \(id) should report its own flip")
    }
}

@Test func stalePrunedWhenAppDisappearsFromScan() {
    let fp = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let last = [
        "io.tailscale.ipn.macsys": fp,
        "com.uninstalled.app": ChannelSwitchDetector.fingerprint(.init(channel: .beta)),
    ]
    let current = ["io.tailscale.ipn.macsys": fp]
    let (changed, next) = ChannelSwitchDetector.changes(current: current, lastSeen: last)
    #expect(changed.isEmpty)
    #expect(next["com.uninstalled.app"] == nil)
}

/// The whole point of fingerprinting rather than caching `ResolvedChannel`
/// itself: a feed-swap change (e.g. CleanShot's licensed-feed URL rotating)
/// must be caught even though `.channel` alone never changes for that app.
@Test func feedOnlyChangeIsDetectedEvenWhenChannelStaysStable() {
    let licensedFeedA = URL(string: "https://legit.maketheweb.io/api/v1/appcast?key=AAA")!
    let licensedFeedB = URL(string: "https://legit.maketheweb.io/api/v1/appcast?key=BBB")!
    let before = ChannelSwitchDetector.fingerprint(.init(channel: .stable, feedOverride: licensedFeedA))
    let after = ChannelSwitchDetector.fingerprint(.init(channel: .stable, feedOverride: licensedFeedB))
    let (changed, _) = ChannelSwitchDetector.changes(
        current: ["pl.maketheweb.cleanshotx": after],
        lastSeen: ["pl.maketheweb.cleanshotx": before])
    #expect(changed == ["pl.maketheweb.cleanshotx"])
}

/// A header-only change (TablePlus's `X-Tiny-Beta-Update` toggle) must also be
/// caught — the fingerprint has to fold in `feedHTTPHeaders`, not just the feed
/// URL and channel.
@Test func headerOnlyChangeIsDetected() {
    let before = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let after = ChannelSwitchDetector.fingerprint(
        .init(channel: .beta, feedHTTPHeaders: ["X-Tiny-Beta-Update": "true"]))
    let (changed, _) = ChannelSwitchDetector.changes(
        current: ["com.tinyapp.tableplus": after],
        lastSeen: ["com.tinyapp.tableplus": before])
    #expect(changed == ["com.tinyapp.tableplus"])
}

/// The fingerprint is a SHA-256 hex digest — fixed-length, and must never embed
/// the license key (or any other feed content) verbatim, since it's the thing we
/// actually persist/compare/log.
@Test func fingerprintNeverLeaksTheRawFeed() {
    let secret = "super-secret-license-key-should-never-appear"
    let feed = URL(string: "https://legit.maketheweb.io/api/v1/appcast?key=\(secret)")!
    let fp = ChannelSwitchDetector.fingerprint(.init(channel: .stable, feedOverride: feed))
    #expect(fp.count == 64, "SHA-256 hex digest is 64 characters")
    #expect(!fp.contains(secret))
    #expect(fp.allSatisfy { $0.isHexDigit })
}

/// The launch/terminate gate. Derived from the registry, not a hand-written list,
/// so a tenth bound app is covered the day it is added.
@Test func onlyBoundAppsAreWorthRecheckingOnLaunchOrQuit() {
    for id in ChannelBinding.boundBundleIDs {
        #expect(ChannelSwitchDetector.isWorthRecheckingAfterLaunchOrQuit(of: id))
        // Bundle ids are case-insensitive, and TablePlus really does ship
        // `com.tinyapp.TablePlus` while its prefs live under the lowercased
        // domain — a case-sensitive gate would silently skip it.
        #expect(ChannelSwitchDetector.isWorthRecheckingAfterLaunchOrQuit(of: id.uppercased()))
    }
    // The overwhelming majority of these notifications: some other app entirely.
    for other in ["com.apple.finder", "com.apple.Safari", "com.googlecode.iterm2"] {
        #expect(!ChannelSwitchDetector.isWorthRecheckingAfterLaunchOrQuit(of: other),
                "\(other) has no channel binding — resolving nine prefs for it is waste")
    }
    // Fail toward doing the work when the notification carries no id: a wasted
    // pass is cheap, a missed switch is the bug this detector exists to fix.
    #expect(ChannelSwitchDetector.isWorthRecheckingAfterLaunchOrQuit(of: nil))
}
