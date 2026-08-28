import Foundation
import Testing
@testable import DuoUpdaterCore

/// The two privileged shell transactions, each run end to end in a user-owned
/// scratch directory. Running the real command string — rather than asserting on
/// its text — is the point: these are the only tests that can catch a `&&` that
/// should have been a `;`, or an ordering that leaves the app missing.
@Suite struct PrivilegedReplacementShellTests {

    // MARK: - Whole-bundle replacement

    /// The modes an install was set up with survive being replaced — the bundle
    /// and `Contents`, in both directions, and no further.
    ///
    /// The limit is asserted as deliberately as the rule. Carrying the group-write
    /// bit down the whole tree is something the input methods need, and they are
    /// the only apps it was ever measured on; they no longer take this path at all
    /// (`rotateContents` does that, and does the recursion). Two apps here DO take
    /// it with a group-writable root — Microsoft Word and Excel, `root:wheel` 775 —
    /// and widening their interiors on a rule derived from an input method would
    /// be a change nobody asked for.
    @Test func aPrivilegedSwapPreservesTheInstalledDirectoryModes() throws {
        let fm = FileManager.default
        let parent = try scratch()
        defer { try? fm.removeItem(at: parent) }
        let target = try bundle(
            at: parent.appendingPathComponent("Fixture.app"), mode: 0o775, marker: "old")
        let incoming = try bundle(
            at: parent.appendingPathComponent("Incoming.app"), mode: 0o755, marker: "new")

        let shell = InPlaceSwap.privilegedReplacementShell(newApp: incoming, target: target)
        #expect(try run(shell) == 0)

        #expect(try mode(of: target) == 0o775)
        #expect(try mode(of: target.appendingPathComponent("Contents")) == 0o775)
        // Below `Contents`, the archive's own modes stand — the recursion lives in
        // `rotateContents`, not here.
        #expect(try mode(of: target.appendingPathComponent("Contents/Resources")) == 0o755)
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
        #expect(!fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
    }

    /// The same rule in the direction nobody would notice going wrong: a 755
    /// install must not come back group-writable because the archive it was
    /// replaced from happened to be.
    @Test func aPrivilegedSwapDoesNotWidenA755Install() throws {
        let fm = FileManager.default
        let parent = try scratch()
        defer { try? fm.removeItem(at: parent) }
        let target = try bundle(
            at: parent.appendingPathComponent("Fixture.app"), mode: 0o755, marker: "old")
        let incoming = try bundle(
            at: parent.appendingPathComponent("Incoming.app"), mode: 0o775, marker: "new")

        #expect(try run(InPlaceSwap.privilegedReplacementShell(
            newApp: incoming, target: target)) == 0)

        #expect(try mode(of: target) == 0o755)
        #expect(try mode(of: target.appendingPathComponent("Contents")) == 0o755)
        // The documented limit, asserted so it stays a decision rather than
        // becoming a surprise: the level below keeps what the archive shipped.
        #expect(try mode(of: target.appendingPathComponent("Contents/Resources")) == 0o775)
    }

    // MARK: - Helpers

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoSwapTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A bundle with a `Contents/Resources` level, because two levels is exactly
    /// what the version of this that shipped in #124 preserved — a fixture that
    /// stopped at `Contents` could not tell the two apart.
    private func bundle(at url: URL, mode: Int, marker: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/\(marker)"))
        for path in ["", "Contents", "Contents/Resources"] {
            try fm.setAttributes(
                [.posixPermissions: mode],
                ofItemAtPath: path.isEmpty ? url.path : url.appendingPathComponent(path).path)
        }
        return url
    }

    private func run(_ shell: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shell]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func mode(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o7777
    }

}

/// The unprivileged half of the rotation, its refusals, and the sweep that puts a
/// half-finished one back together.
@Suite struct ContentsRotationTests {

    /// Rotation is chosen by install LOCATION, the same way the policy gate is, so
    /// the next input method inherits it without anyone registering it.
    @Test func rotationIsChosenByLocationNotByBundle() {
        for parent in ["/Library/Input Methods", NSHomeDirectory() + "/Library/Input Methods"] {
            #expect(InPlaceSwap.usesContentsRotation(
                target: URL(fileURLWithPath: parent + "/Anything.app")))
        }
        #expect(!InPlaceSwap.usesContentsRotation(
            target: URL(fileURLWithPath: "/Applications/Input Methods Helper.app")))
    }

    /// A rotation must never be routed through the administrator prompt, and the
    /// row must not promise one. `/Library/Input Methods` is `root:wheel` 755, so
    /// the general predicate — which asks about the enclosing directory — says
    /// "needs a password" for every input method; the exception asks about the
    /// bundle, which is the only thing a rotation writes.
    ///
    /// This is not a cosmetic difference. Measured 2026-08-28 in one root shell,
    /// same directory: `ditto` BESIDE the bundle succeeded, `ditto` INSIDE it
    /// returned EPERM — App Management gates the bundle interior and root does not
    /// lift it. So an elevated rotation is not merely unnecessary, it cannot work,
    /// and a row promising a password panel would be promising the one route that
    /// is guaranteed to fail.
    @Test func aRotationTargetIsNeverRoutedThroughTheAdministratorPrompt() throws {
        let fm = FileManager.default
        let root = try inputMethodsScratch()
        defer { try? fm.removeItem(at: root.top) }
        let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
        // The enclosing directory is made unwritable, exactly as the real one is.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.dir.path) }

        #expect(!InPlaceSwap.needsElevatedReplace(target: target))
        #expect(InPlaceSwap.elevationRequiredPaths(for: [target]).isEmpty)

        // An ordinary app in that same unwritable directory still needs elevation:
        // the exception must be the rotation, not the location.
        let ordinary = root.top.appendingPathComponent("Elsewhere.app")
        try fm.createDirectory(at: ordinary, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ordinary.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ordinary.path) }
        #expect(InPlaceSwap.needsElevatedReplace(target: ordinary))
    }

    /// The one permission a rotation actually uses. Refused up front, with a
    /// sentence, rather than by a half-finished rename — and deliberately NOT by
    /// escalating, which is the move that cannot work here.
    @Test func aRotationRefusesWhenTheBundleItselfIsNotWritable() throws {
        let fm = FileManager.default
        let root = try inputMethodsScratch()
        defer { try? fm.removeItem(at: root.top) }
        let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
        let incoming = try bundle(at: root.top.appendingPathComponent("Incoming.app"), marker: "new")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path) }

        #expect(throws: (any Error).self) {
            try InPlaceSwap.rotateContents(newApp: incoming, over: target)
        }
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
    }

    @Test func anUnprivilegedRotationExchangesContentsInPlace() throws {
        let fm = FileManager.default
        let root = try inputMethodsScratch()
        defer { try? fm.removeItem(at: root.top) }
        let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
        let incoming = try bundle(at: root.top.appendingPathComponent("Incoming.app"), marker: "new")
        let outerBefore = try #require(
            (try fm.attributesOfItem(atPath: target.path))[.systemFileNumber] as? NSNumber)

        try InPlaceSwap.rotateContents(newApp: incoming, over: target)

        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
        #expect(!fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
        let outerAfter = try #require(
            (try fm.attributesOfItem(atPath: target.path))[.systemFileNumber] as? NSNumber)
        #expect(outerBefore == outerAfter, "the registered .app must survive the exchange")
        // The vendor's own updater has to be able to delete the Contents it
        // displaces next time, which needs write on every directory inside it.
        for level in ["Contents", "Contents/Resources"] {
            let attrs = try fm.attributesOfItem(atPath: target.appendingPathComponent(level).path)
            let mode = try #require(attrs[.posixPermissions] as? NSNumber).intValue
            #expect(mode & 0o020 != 0, "\(level) lost the group-write bit")
        }
    }

    /// Rotation replaces `Contents` and nothing else, so a bundle holding anything
    /// else at its top level would come out as new code beside the old copy's
    /// leftovers — a state no gate downstream looks at. Refuse instead.
    @Test func aRotationRefusesABundleThatHoldsMoreThanContents() throws {
        let fm = FileManager.default
        let root = try inputMethodsScratch()
        defer { try? fm.removeItem(at: root.top) }
        let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
        let incoming = try bundle(at: root.top.appendingPathComponent("Incoming.app"), marker: "new")
        try fm.createDirectory(
            at: target.appendingPathComponent("Extras"), withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try InPlaceSwap.rotateContents(newApp: incoming, over: target)
        }
        // And the refusal changed nothing.
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
    }

    /// Both vendors' updaters stage their own next `Contents` inside the bundle.
    /// Seeing one of their staging directories means that update is in flight, and
    /// rotating underneath it would race a process about to rename `Contents`
    /// itself.
    @Test func aRotationRefusesWhileTheVendorsOwnUpdateIsInFlight() throws {
        let fm = FileManager.default
        for staging in [".Contents.update", "Contents_update"] {
            let root = try inputMethodsScratch()
            defer { try? fm.removeItem(at: root.top) }
            let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
            let incoming = try bundle(
                at: root.top.appendingPathComponent("Incoming.app"), marker: "new")
            try fm.createDirectory(
                at: target.appendingPathComponent(staging), withIntermediateDirectories: true)

            // The MESSAGE is part of the assertion. `Contents_update` is not
            // hidden, so the top-level check would also reject it — with a sentence
            // about the bundle's layout rather than about the update that is
            // actually running. A bare "it threw" cannot tell those apart.
            var reason = ""
            #expect(throws: (any Error).self, "\(staging) means their updater is mid-exchange") {
                do { try InPlaceSwap.rotateContents(newApp: incoming, over: target) }
                catch { reason = error.localizedDescription; throw error }
            }
            #expect(reason.contains("still in flight"), "\(staging) → \(reason)")
            #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
        }
    }

    /// The other side of that guard, and the one that would have made the
    /// one-click permanently unavailable: `.Contents.old`, `.Contents.abandoned`
    /// and `Contents_backup` are what a FINISHED vendor update leaves behind — its
    /// own updater carries `cleanup old Contents failed:` for exactly that — so
    /// finding one means an update ran, not that one is running.
    @Test func aRotationProceedsWhenOnlyTheVendorsLeftoversArePresent() throws {
        let fm = FileManager.default
        for leftover in [".Contents.old", ".Contents.abandoned", "Contents_backup"] {
            let root = try inputMethodsScratch()
            defer { try? fm.removeItem(at: root.top) }
            let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
            let incoming = try bundle(
                at: root.top.appendingPathComponent("Incoming.app"), marker: "new")
            try fm.createDirectory(
                at: target.appendingPathComponent(leftover), withIntermediateDirectories: true)

            try InPlaceSwap.rotateContents(newApp: incoming, over: target)
            #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path),
                    "\(leftover) is a leftover, not a reason to refuse forever")
        }
    }

    /// The state a rotation killed between its two renames leaves behind: no
    /// `Contents` at all, which is an input method the system can no longer load.
    /// The launch sweep has to put it back.
    @Test func anInterruptedRotationIsRecoveredBySweep() throws {
        let fm = FileManager.default
        let root = try inputMethodsScratch()
        defer { try? fm.removeItem(at: root.top) }
        let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
        // Exactly what `replaceItemAt(…, backupItemName: rotationBackupName, …)`
        // leaves if it is cut off after moving the original aside. Reachable only
        // because the name is ours: with `backupItemName: nil` the displaced copy
        // would be under a name FileManager picked, and this state would be
        // unrecoverable rather than merely interrupted.
        try fm.moveItem(
            at: target.appendingPathComponent("Contents"),
            to: target.appendingPathComponent(InPlaceSwap.rotationBackupName))
        #expect(!fm.fileExists(atPath: target.appendingPathComponent("Contents").path))

        InPlaceSwap.recoverInterruptedSwaps(in: root.dir)

        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
        #expect(!fm.fileExists(
            atPath: target.appendingPathComponent(InPlaceSwap.rotationBackupName).path))
    }

    /// The other half of the sweep: once the real `Contents` is back, a leftover
    /// staging copy is a full second copy of the bundle parked inside an input
    /// method, and nobody goes looking for those.
    /// Not housekeeping. Measured on a copy of the real DoubaoIme bundle: an empty
    /// hidden `.Contents.duoupdater-new` at the bundle root takes
    /// `codesign --verify --strict` from "valid on disk" to "unsealed contents
    /// present in the bundle root", and removing it restores it. (`.DS_Store` is
    /// exempt by the signing rules; ours is not.) A leftover nothing clears is an
    /// input method that fails Gatekeeper.
    @Test func aStaleRotationLeftoverIsCleared() throws {
        let fm = FileManager.default
        let root = try inputMethodsScratch()
        defer { try? fm.removeItem(at: root.top) }
        let target = try bundle(at: root.dir.appendingPathComponent("Fixture.app"), marker: "old")
        for name in [InPlaceSwap.rotationStagedName, InPlaceSwap.rotationBackupName] {
            try fm.createDirectory(
                at: target.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        InPlaceSwap.recoverInterruptedSwaps(in: root.dir)

        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
        for name in [InPlaceSwap.rotationStagedName, InPlaceSwap.rotationBackupName] {
            #expect(!fm.fileExists(atPath: target.appendingPathComponent(name).path))
        }
    }

    // MARK: - Helpers

    /// A scratch tree whose leaf directory really is called `Library/Input
    /// Methods`, because that name is the whole discriminator — a fixture
    /// somewhere else would exercise none of this.
    private func inputMethodsScratch() throws -> (top: URL, dir: URL) {
        let top = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoRotateTest-\(UUID().uuidString)")
        let dir = top.appendingPathComponent("Library/Input Methods", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (top, dir)
    }

    /// Structurally valid but unsigned, so the recovery sweep's signature check
    /// reports `errSecCSUnsigned` (allowed) rather than the bad-bundle-format a
    /// bare directory would give.
    private func bundle(at url: URL, marker: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/\(marker)"))
        // 775 at every level, like both real installs, so the group-write rules
        // are exercised rather than assumed away by a permissive umask.
        for path in ["", "Contents", "Contents/Resources"] {
            try fm.setAttributes(
                [.posixPermissions: 0o775],
                ofItemAtPath: path.isEmpty ? url.path : url.appendingPathComponent(path).path)
        }
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.example.fixture</string>
        <key>CFBundleName</key><string>Fixture</string>
        <key>CFBundleExecutable</key><string>Fixture</string>
        </dict></plist>
        """
        try Data(info.utf8).write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }
}
