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

/// The detector only ever runs when something calls it, and until 2026-08-23 the
/// only two callers were "a bound app launched or quit" and "a DuoUpdater *window*
/// appeared". Both miss the ordinary flow: flip the toggle inside the vendor app,
/// leave it running, and look at the menu-bar popover — which is not a window. Surge
/// made it worse by writing `KDDefaults.plist` lazily (relaunch at 13:03:40, plist
/// at 13:08), so even the launch event read the pre-flip value off disk. The row
/// stayed on the beta build for minutes after the user had moved to release.
///
/// The fix is a filesystem watcher, and its whole correctness rests on one thing:
/// the roots it watches must contain the files the resolvers actually read. That is
/// the discriminator, and a watcher aimed one directory away would look completely
/// healthy while never firing. So this asks the resolvers for their own paths
/// (`SurgeChannel.defaultsFileURL`, `AlfredChannel.preferencesBaseURL`) rather than
/// restating them, and covers every bound id rather than a hand-picked few.
@Test func everyChannelPreferenceSitsUnderAWatchedRoot() {
    let roots = ChannelBinding.preferenceWatchCandidates.map(\.standardizedFileURL.path)
    #expect(!roots.isEmpty)

    func isWatched(_ path: String) -> Bool {
        roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    // The two resolvers that read a path directly rather than through CFPreferences.
    #expect(
        isWatched(SurgeChannel.defaultsFileURL.standardizedFileURL.path),
        "Surge's KDDefaults.plist — the file its resolver reads — is not under any watched root")
    if let alfred = AlfredChannel.preferencesBaseURL {
        #expect(
            isWatched(alfred.standardizedFileURL.path),
            "Alfred's preferences tree is not under any watched root")
    }

    // Everyone else resolves through `CFPreferencesCopyAppValue`, backed by
    // `~/Library/Preferences/<domain>.plist` for an unsandboxed app.
    //
    // Be honest about what this half proves: it builds the expected path from the
    // same `~/Library/Preferences` the source lists as a root, so it catches that
    // root being dropped or narrowed, and nothing else. It does NOT ask
    // `DuoPasteChannel` & co. where they actually read — they don't expose that the
    // way `SurgeChannel` and `AlfredChannel` now do — so a bound app that turned out
    // to be sandboxed (domain under `~/Library/Containers/…`) would slip past. Giving
    // every resolver a `preferenceURL` is what would close it; until then those two
    // assertions above are the only ones here with a real discriminator.
    let prefsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences", isDirectory: true)
    for id in ChannelBinding.boundBundleIDs {
        let domain = prefsDir.appendingPathComponent("\(id).plist").standardizedFileURL.path
        #expect(isWatched(domain), "\(id)'s preference domain is not under any watched root")
    }

    // What the stream is actually built from: a subset of the candidates, each one
    // real. FSEvents takes a fixed path list, so a non-existent entry is dead weight.
    let watched = ChannelBinding.preferenceWatchPaths
    #expect(Set(watched).isSubset(of: Set(roots)))
    #expect(watched.count == Set(watched).count, "duplicate root in the watch list")
    for path in watched {
        #expect(FileManager.default.fileExists(atPath: path), "\(path) does not exist")
    }
}

// MARK: - booked(): a superseded pass must not claim the ids it never reached

/// The regression behind issue #74, as a sequence. A flip lands while an earlier
/// pass is still on the network; the earlier pass is cancelled before it reaches
/// that id. Booking `current` wholesale (what `changes` hands back, and what the
/// caller used to store) would record the new fingerprint as already seen, so the
/// next pass finds nothing changed and the row keeps the superseded track.
@Test func aCancelledPassLeavesItsUnfinishedIDsLookingChanged() {
    let stable = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let beta = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    let lastSeen = ["a": stable, "b": stable]
    let current = ["a": beta, "b": beta]
    let (changed, wholesale) = ChannelSwitchDetector.changes(current: current, lastSeen: lastSeen)
    #expect(changed == ["a", "b"])

    // "a" finished before the cancellation, "b" did not.
    let next = ChannelSwitchDetector.booked(
        current: current, lastSeen: lastSeen, changed: changed, completed: ["a"])
    #expect(next["a"] == beta, "the id we acted on is booked")
    #expect(next["b"] == stable, "the id we never reached is rewound, so it reads as changed again")

    // The next pass picks "b" up. Booking wholesale would have lost it.
    #expect(ChannelSwitchDetector.changes(current: current, lastSeen: next).changed == ["b"])
    #expect(ChannelSwitchDetector.changes(current: current, lastSeen: wholesale).changed.isEmpty,
            "this is the old behaviour, kept here as the thing that must not come back")
}

/// A pass that finished everything books exactly what `changes` would have.
@Test func aCompletePassBooksEverything() {
    let stable = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let beta = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    let lastSeen = ["a": stable]
    let current = ["a": beta]
    let (changed, wholesale) = ChannelSwitchDetector.changes(current: current, lastSeen: lastSeen)
    #expect(ChannelSwitchDetector.booked(
        current: current, lastSeen: lastSeen, changed: changed, completed: ["a"]) == wholesale)
}

/// Booking still seeds ids seen for the first time and prunes ids that dropped out
/// of the scan — the bookkeeping `changes` did by returning `current` — even on a
/// pass where nothing flipped or nothing completed.
@Test func bookingStillSeedsAndPrunes() {
    let beta = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    let next = ChannelSwitchDetector.booked(
        current: ["new": beta], lastSeen: ["gone": beta], changed: [], completed: [])
    #expect(next == ["new": beta])
}

/// Rapid flipping, end to end: flips that supersede one another must never let the
/// cache settle on a state the user has already left.
@Test func repeatedFlipsAlwaysConvergeOnTheLatestState() {
    let stable = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let beta = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    let unstable = ChannelSwitchDetector.fingerprint(.init(channel: .unstable))
    var lastSeen = ["app": stable]

    // Each flip supersedes the pass before it, so no pass completes its id.
    for fingerprint in [beta, unstable] {
        let current = ["app": fingerprint]
        let (changed, _) = ChannelSwitchDetector.changes(current: current, lastSeen: lastSeen)
        #expect(changed == ["app"])
        lastSeen = ChannelSwitchDetector.booked(
            current: current, lastSeen: lastSeen, changed: changed, completed: [])
        #expect(lastSeen["app"] == stable, "a superseded pass books nothing")
    }

    // The pass that finally runs to completion acts on where the user landed.
    let settled = ["app": unstable]
    let (changed, _) = ChannelSwitchDetector.changes(current: settled, lastSeen: lastSeen)
    #expect(changed == ["app"])
    lastSeen = ChannelSwitchDetector.booked(
        current: settled, lastSeen: lastSeen, changed: changed, completed: ["app"])
    #expect(ChannelSwitchDetector.changes(current: settled, lastSeen: lastSeen).changed.isEmpty,
            "once a pass completes, the settled state stops re-triggering")
}

/// Flipping away and straight back, with nothing booked in between, correctly asks
/// for no work at all: the state we last acted on IS the state the user ended in,
/// so there is nothing to recheck. Rewinding an unfinished id restores the old
/// fingerprint rather than clearing it, which is what makes this hold — clearing
/// would make the id look new, and a first sighting seeds silently, which happens
/// to reach the same place here but would not if the row on screen had meanwhile
/// been written from the superseded verdict.
@Test func aRoundTripBackToTheOriginalNeedsNoRecheck() {
    let stable = ChannelSwitchDetector.fingerprint(.init(channel: .stable))
    let beta = ChannelSwitchDetector.fingerprint(.init(channel: .beta))
    var lastSeen = ["app": stable]

    let (awayChanged, _) = ChannelSwitchDetector.changes(
        current: ["app": beta], lastSeen: lastSeen)
    lastSeen = ChannelSwitchDetector.booked(
        current: ["app": beta], lastSeen: lastSeen, changed: awayChanged, completed: [])

    #expect(ChannelSwitchDetector.changes(current: ["app": stable], lastSeen: lastSeen)
        .changed.isEmpty)
}
