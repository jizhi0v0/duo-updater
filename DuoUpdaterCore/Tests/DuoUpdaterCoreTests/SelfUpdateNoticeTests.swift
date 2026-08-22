import Testing
@testable import DuoUpdaterCore

/// A silent self-update is the point of the design, so the ONLY thing standing
/// between the user and "my tool changed and never said so" is this decision.

@Test func aSilentUpdateIsAnnouncedOnce() {
    #expect(SelfUpdateNotice.announcement(running: "0.3.51", lastSeen: "0.3.50") == "0.3.51")
    // Several silent updates between launches: announce where they landed, which
    // is what the notes window opens on.
    #expect(SelfUpdateNotice.announcement(running: "0.3.53", lastSeen: "0.3.50") == "0.3.53")
}

/// A fresh install must not be told it was updated — nobody was, and on day one
/// that reads as the tool lying about its own history.
@Test func aFreshInstallIsSeededNotAnnounced() {
    #expect(SelfUpdateNotice.announcement(running: "0.3.51", lastSeen: nil) == nil)
    #expect(SelfUpdateNotice.shouldSeedSilently(running: "0.3.51", lastSeen: nil))
}

@Test func anUnchangedVersionSaysNothingAndNeedsNoSeed() {
    #expect(SelfUpdateNotice.announcement(running: "0.3.51", lastSeen: "0.3.51") == nil)
    #expect(!SelfUpdateNotice.shouldSeedSilently(running: "0.3.51", lastSeen: "0.3.51"))
}

/// Going backwards is a rollback or a deliberate older build. "Updated to 0.3.40"
/// would be wrong, and the record has to follow or the next real update is missed.
@Test func aRollbackIsReseededSilently() {
    #expect(SelfUpdateNotice.announcement(running: "0.3.40", lastSeen: "0.3.51") == nil)
    #expect(SelfUpdateNotice.shouldSeedSilently(running: "0.3.40", lastSeen: "0.3.51"))
    // …and the next genuine update from there is announced normally.
    #expect(SelfUpdateNotice.announcement(running: "0.3.41", lastSeen: "0.3.40") == "0.3.41")
}

/// Missing or blank input says nothing rather than guessing.
@Test func missingVersionsAreSilent() {
    #expect(SelfUpdateNotice.announcement(running: nil, lastSeen: "0.3.50") == nil)
    #expect(SelfUpdateNotice.announcement(running: "  ", lastSeen: "0.3.50") == nil)
    #expect(!SelfUpdateNotice.shouldSeedSilently(running: nil, lastSeen: nil))
}

/// The two helpers must never both fire: seeding means "say nothing", announcing
/// means "the record stays until the user has read it". Treating one as the other
/// is how an announcement gets cleared before it is shown.
@Test func announcingAndSeedingAreMutuallyExclusive() {
    for (running, seen) in [("0.3.51", "0.3.50"), ("0.3.51", nil), ("0.3.40", "0.3.51"),
                            ("0.3.51", "0.3.51")] as [(String, String?)] {
        let announces = SelfUpdateNotice.announcement(running: running, lastSeen: seen) != nil
        let seeds = SelfUpdateNotice.shouldSeedSilently(running: running, lastSeen: seen)
        #expect(!(announces && seeds), "running=\(running) lastSeen=\(seen ?? "nil")")
    }
}
