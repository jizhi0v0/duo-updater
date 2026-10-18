import Foundation
import Testing
@testable import DuoUpdaterCore

/// The install path's child processes, run against invented bundles in scratch
/// directories — never a real app, never `/Applications`.
///
/// Mostly about the one behaviour `ChildProcess` could have changed: cancellation.
/// Most children on this path are `.runToCompletion`, because the old
/// `offCooperativePool` hop could not be cancelled and a half-done write is worse
/// than a finished one. The exceptions write only into the install's own work
/// directory, which is removed afterwards anyway: the extraction tools
/// (`ArchiveExtractor.run`) and the package copy (`PackageInstaller.run`), so
/// those are `.terminateChild`. The patch (`DeltaApplier.apply`) is not one of
/// them: a killed `BinaryDelta` leaves a temporary diff outside the work
/// directory, so it runs to completion. Each test here runs
/// the operation in a task that is cancelled BEFORE it starts. `.terminateChild` refuses to spawn into an
/// already-cancelled task, so a site that picked it throws `CancellationError`
/// before its tool ever runs — the mutations below fail by that, not by whether a
/// SIGKILL happened to beat a millisecond `chmod`. (Before `ChildProcess` had that
/// check, two of these depended on exactly that race.)
///
/// Each names the mutation that turns it red.
@Suite struct InstallChildProcessTests {

    // MARK: - Swap

    /// A cancelled rotation still carries the group-write bit onto the new
    /// `Contents`, all the way down — the `chmod -R g+w` ran to its end. The
    /// incoming bundle is 755 on purpose: a 775 fixture would already have the bit
    /// and could not tell a chmod that ran from one that did not.
    ///
    /// Mutation: the `chmod` in `rotateContents` becomes `.terminateChild` → it
    /// throws `CancellationError`, the bit is not carried, and `Contents/Resources`
    /// comes out 755.
    @Test func aCancelledRotationStillCarriesTheGroupWriteBit() async throws {
        let fm = FileManager.default
        let top = try scratch("rotate")
        defer { try? fm.removeItem(at: top) }
        let dir = top.appendingPathComponent("Library/Input Methods", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = try bundle(at: dir.appendingPathComponent("ZZFixture.app"), mode: 0o775, marker: "old")
        let incoming = try bundle(at: top.appendingPathComponent("ZZIncoming.app"), mode: 0o755, marker: "new")
        #expect(InPlaceSwap.usesContentsRotation(target: target), "fixture must take the rotation path")

        let outcome = try await cancelledBeforeStart {
            try await InPlaceSwap.replace(newApp: incoming, over: target)
        }

        #expect(outcome == .replaced)
        // Old or new, never a mixture.
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
        #expect(!fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
        for level in ["Contents", "Contents/Resources"] {
            let mode = try #require(
                try fm.attributesOfItem(atPath: target.appendingPathComponent(level).path)[.posixPermissions]
                    as? NSNumber).intValue
            #expect(mode & 0o020 != 0, "\(level) lost the group-write bit")
        }
    }

    /// A cancelled whole-bundle swap still strips the quarantine attribute from
    /// what it installs — `xattr -dr` ran to its end.
    ///
    /// Mutation: `stripQuarantine` becomes `.terminateChild` → the attribute is
    /// still on the installed bundle.
    @Test func aCancelledSwapStillStripsQuarantine() async throws {
        let fm = FileManager.default
        let top = try scratch("swap")
        defer { try? fm.removeItem(at: top) }
        let target = try bundle(at: top.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "old")
        let incoming = try bundle(at: top.appendingPathComponent("ZZIncoming.app"), mode: 0o755, marker: "new")
        let marker = incoming.appendingPathComponent("Contents/new")
        try setQuarantine(on: incoming)
        try setQuarantine(on: marker)
        #expect(hasQuarantine(incoming), "fixture must start quarantined")
        #expect(!InPlaceSwap.usesContentsRotation(target: target))

        let outcome = try await cancelledBeforeStart {
            try await InPlaceSwap.replace(newApp: incoming, over: target)
        }

        #expect(outcome == .replaced)
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
        #expect(!hasQuarantine(target))
        #expect(!hasQuarantine(target.appendingPathComponent("Contents/new")))
    }

    // MARK: - Extract

    /// A cancelled extraction is not run at all: `ditto -x -k` never spawns into a
    /// task that is already cancelled, the call throws `CancellationError`, and
    /// nothing is unpacked into the work directory.
    ///
    /// Mutation: `ArchiveExtractor.run` becomes `.runToCompletion` → `ditto` runs
    /// to its end, the call returns the app, and both expectations fail.
    @Test func aCancelledExtractionThrowsAndUnpacksNothing() async throws {
        let fm = FileManager.default
        let top = try scratch("extract")
        defer { try? fm.removeItem(at: top) }
        let source = try bundle(at: top.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "payload")
        let zip = top.appendingPathComponent("ZZFixture.zip")
        let made = try await ChildProcess.run(
            "/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, zip.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
        let work = top.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        await #expect(throws: CancellationError.self) {
            _ = try await cancelledBeforeStart {
                try await ArchiveExtractor.extractApp(from: zip, workDir: work)
            }
        }
        #expect(!fm.fileExists(atPath: work.appendingPathComponent("unzipped/ZZFixture.app").path))
    }

    /// A cancelled extraction that is already running is torn down, not waited on.
    /// The archive is a FIFO with no writer, so `ditto` parks inside its own `open`
    /// and cannot finish by itself. Cancelling must kill it, return promptly, and
    /// leave no `ditto` behind.
    ///
    /// The watchdog is armed only after the cancel, and it fires 60 s later. It is a
    /// hang detector, not a timing assertion. With `.terminateChild` the call returns
    /// at once and the watchdog is a no-op. With `.runToCompletion` the call blocks
    /// on the FIFO, and the watchdog writes a real archive into it, so `ditto`
    /// finishes and the call returns the app, which the switch below records as a
    /// failure instead of leaving the suite hung.
    ///
    /// Mutation: `ArchiveExtractor.run` becomes `.runToCompletion` → the call blocks
    /// until the watchdog feeds the FIFO, then returns the app and the test fails.
    @Test func aCancelledExtractionKillsTheRunningTool() async throws {
        let fm = FileManager.default
        let top = try scratch("extract-running")
        defer { try? fm.removeItem(at: top) }
        let source = try bundle(at: top.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "payload")
        let realZip = top.appendingPathComponent("ZZReal.zip")
        let made = try await ChildProcess.run(
            "/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, realZip.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
        let fifo = top.appendingPathComponent("ZZFixture.zip")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let work = top.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let finished = FinishFlag()
        let task = Task { try await ArchiveExtractor.extractApp(from: fifo, workDir: work) }
        // `ditto` is running once `pgrep -f` can see it on the FIFO's path.
        var running = false
        for _ in 0..<100 where !running {
            running = try await ChildProcess.run(
                "/usr/bin/pgrep", ["-f", fifo.path], onCancel: .runToCompletion).succeeded
            if !running { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(running, "ditto never started on the FIFO")

        task.cancel()
        // Armed only now, after the cancel: see the doc comment above.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            guard !finished.isSet, let bytes = try? Data(contentsOf: realZip) else { return }
            // Blocks until `ditto` opens the read end, which only a still-running
            // `ditto` does; a torn-down one never does, so this is skipped above.
            let fd = open(fifo.path, O_WRONLY)
            guard fd >= 0 else { return }
            _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }
        let result = await task.result
        finished.set()

        switch result {
        case .success(let app):
            Issue.record("the extraction returned \(app.lastPathComponent) after the cancel")
        case .failure(let error):
            #expect(error is CancellationError, "expected CancellationError, got \(error)")
        }
        let leftover = try await ChildProcess.run(
            "/usr/bin/pgrep", ["-f", fifo.path], onCancel: .runToCompletion)
        #expect(!leftover.succeeded, "a ditto is still running on the archive after the cancel")
    }

    /// A tool's failure reaches the error with its exit status and its stderr,
    /// condensed: "tar failed (1): …". Both halves come from `ChildProcess` now.
    ///
    /// Mutation: `run` returns `outcome.standardOutput` in the `err` slot → the
    /// message carries "(no output)" instead of tar's complaint.
    @Test func aFailingToolReportsItsStatusAndStderr() async throws {
        let fm = FileManager.default
        let top = try scratch("tar")
        defer { try? fm.removeItem(at: top) }
        let bogus = top.appendingPathComponent("ZZFixture.tar.gz")
        try Data("not a tarball".utf8).write(to: bogus)

        do {
            _ = try await ArchiveExtractor.extractApp(from: bogus, workDir: top)
            Issue.record("a corrupt tarball extracted")
        } catch let ArchiveExtractor.ExtractError.toolFailed(tool, code, message) {
            #expect(tool == "tar")
            #expect(code != 0)
            #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let described = ArchiveExtractor.ExtractError.toolFailed(tool, code, message).errorDescription ?? ""
            #expect(described.hasPrefix("tar failed (\(code)): "))
            #expect(!described.contains("(no output)"))
        }
    }

    // MARK: - Disk images

    /// The mount tools a test can force on this Mac: `hdiutil` always, and
    /// `diskutil image` from 26 (measured on 26.7; production only prefers it
    /// from 27.2, see `DiskImageMount`). A version rather than a probe, so the
    /// list can be a plain `static let`; `theDiskutilImageVerbExistsWhereTheTestsAssumeIt`
    /// checks the assumption.
    static let mountTools: [DiskImageMount.Tool] =
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        ? [.hdiutil, .diskutil] : [.hdiutil]

    /// Where `mountTools` lists `diskutil`, the verb must really be there —
    /// otherwise every `diskutil` case here fails on an unknown verb rather than
    /// testing the route 27.2 uses in production.
    @Test(.enabled(if: InstallChildProcessTests.mountTools.contains(.diskutil)))
    func theDiskutilImageVerbExistsWhereTheTestsAssumeIt() async throws {
        let probe = try await ChildProcess.run(
            "/usr/sbin/diskutil", ["image", "attach", "--help"], onCancel: .runToCompletion)
        #expect(probe.succeeded, "`diskutil image attach --help` failed on this Mac")
    }

    /// A cancelled DMG extraction still unmounts the image, on the exit that
    /// copied the app out and on the one that found none, with either mount
    /// tool. The unmount sits in a `defer { await … }`, which sees the task as
    /// cancelled (SE-0493) — so this is also what pins the detach to
    /// `.runToCompletion` there.
    ///
    /// Mutation: drop the `defer { await DiskImageMount.detach(mountPoint, image: …) }` in
    /// `fromDMG` → both mount points are still mounted when the call returns or
    /// throws.
    @Test(arguments: InstallChildProcessTests.mountTools)
    func aCancelledDMGExtractionUnmountsOnBothExits(tool: DiskImageMount.Tool) async throws {
        try await DiskImageMount.$toolOverride.withValue(tool) {
            try await cancelledDMGExtractionUnmountsOnBothExits()
        }
    }

    private func cancelledDMGExtractionUnmountsOnBothExits() async throws {
        let fm = FileManager.default
        let top = try scratch("dmg")
        let images = try await diskImages(in: top)
        let withApp = top.appendingPathComponent("work-app", isDirectory: true)
        let without = top.appendingPathComponent("work-none", isDirectory: true)
        let mounts = [withApp, without].map { $0.appendingPathComponent("mnt-ZZFixture.dmg") }
        let copies = [withApp, without].map { $0.appendingPathComponent("ZZFixture.dmg") }
        defer {
            for (mount, image) in zip(mounts, copies) { await forceDetach(mount, image: image) }
            try? fm.removeItem(at: top)
        }

        try fm.createDirectory(at: withApp, withIntermediateDirectories: true)
        try fm.copyItem(at: images.full, to: withApp.appendingPathComponent("ZZFixture.dmg"))
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledBeforeStart {
                try await ArchiveExtractor.extractApp(
                    from: withApp.appendingPathComponent("ZZFixture.dmg"), workDir: withApp)
            }
        }
        #expect(!fm.fileExists(atPath: withApp.appendingPathComponent("ZZFixture.app").path),
                "the copy out of the image ran although the task was cancelled")
        #expect(!isMountPoint(mounts[0]), "the image stayed mounted after the copy was cancelled")
        #expect(await !TestDiskImages.isAttached(copies[0]), "the image stayed attached after the copy was cancelled")

        try fm.createDirectory(at: without, withIntermediateDirectories: true)
        try fm.copyItem(at: images.empty, to: without.appendingPathComponent("ZZFixture.dmg"))
        await #expect(throws: ArchiveExtractor.ExtractError.self) {
            _ = try await cancelledBeforeStart {
                try await ArchiveExtractor.extractApp(
                    from: without.appendingPathComponent("ZZFixture.dmg"), workDir: without)
            }
        }
        #expect(!isMountPoint(mounts[1]), "the image stayed mounted after no app was found")
        #expect(await !TestDiskImages.isAttached(copies[1]), "the image stayed attached after no app was found")
    }

    /// The package route's DMG, same two exits: a `.pkg` copied out, and none.
    ///
    /// Mutation: drop the `defer { await DiskImageMount.detach(mountPoint, image: …) }`
    /// in `resolveInstaller` → both mount points are still mounted.
    @Test(arguments: InstallChildProcessTests.mountTools)
    func aCancelledPackageImageUnmountsOnBothExits(tool: DiskImageMount.Tool) async throws {
        try await DiskImageMount.$toolOverride.withValue(tool) {
            try await cancelledPackageImageUnmountsOnBothExits()
        }
    }

    private func cancelledPackageImageUnmountsOnBothExits() async throws {
        let fm = FileManager.default
        let top = try scratch("pkgdmg")
        let images = try await diskImages(in: top)
        let withPkg = top.appendingPathComponent("work-pkg", isDirectory: true)
        let without = top.appendingPathComponent("work-none", isDirectory: true)
        let mounts = [withPkg, without].map { $0.appendingPathComponent("mnt") }
        defer {
            for (mount, image) in zip(mounts, [images.full, images.empty]) {
                await forceDetach(mount, image: image)
            }
            try? fm.removeItem(at: top)
        }
        let installer = PackageInstaller(opener: { _ in })
        let installedApp = top.appendingPathComponent("ZZFixture.app")

        try fm.createDirectory(at: withPkg, withIntermediateDirectories: true)
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledBeforeStart {
                try await installer.resolveInstaller(
                    from: images.full, workDir: withPkg, installedApp: installedApp)
            }
        }
        #expect(!fm.fileExists(atPath: withPkg.appendingPathComponent("ZZFixture.pkg").path),
                "the copy out of the image ran although the task was cancelled")
        #expect(!isMountPoint(mounts[0]), "the image stayed mounted after the copy was cancelled")
        #expect(await !TestDiskImages.isAttached(images.full), "the image stayed attached after the copy was cancelled")

        try fm.createDirectory(at: without, withIntermediateDirectories: true)
        await #expect(throws: PackageInstaller.PackageError.self) {
            _ = try await cancelledBeforeStart {
                try await installer.resolveInstaller(
                    from: images.empty, workDir: without, installedApp: installedApp)
            }
        }
        #expect(!isMountPoint(mounts[1]), "the image stayed mounted after no package was found")
        #expect(await !TestDiskImages.isAttached(images.empty), "the image stayed attached after no package was found")
    }

    /// A cancel that lands while `ditto` is still copying the app out of the mounted
    /// image tears the copy down and throws `CancellationError`, and the image is
    /// still detached: the unmount is in a `defer`, and it is `.runToCompletion`.
    /// Nothing here asserts a duration, and nothing asserts that the copy was caught
    /// mid-way: the test waits (bounded) for `ditto` with `pgrep` and then cancels,
    /// whether or not it saw one. What is asserted is the detach, read three times
    /// from `hdiutil info`, and that a failure is `CancellationError`.
    ///
    /// Mutation: drop the `defer { await DiskImageMount.detach(…) }` in `fromDMG` →
    /// the image is still attached after the cancelled copy.
    @Test(arguments: InstallChildProcessTests.mountTools)
    func aCancelledDMGCopyOutStillUnmountsTheImage(tool: DiskImageMount.Tool) async throws {
        try await DiskImageMount.$toolOverride.withValue(tool) {
            try await cancelledDMGCopyOutStillUnmountsTheImage()
        }
    }

    private func cancelledDMGCopyOutStillUnmountsTheImage() async throws {
        let fm = FileManager.default
        let top = try scratch("dmg-copy")
        let work = top.appendingPathComponent("work", isDirectory: true)
        let mount = work.appendingPathComponent("mnt-ZZFixture.dmg")
        let image = work.appendingPathComponent("ZZFixture.dmg")
        defer {
            await forceDetach(mount, image: image)
            try? fm.removeItem(at: top)
        }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // A payload big enough that the copy is still running when the cancel
        // lands. It is zeros, so the image is small on disk.
        let source = top.appendingPathComponent("src-big", isDirectory: true)
        let app = try bundle(at: source.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "payload")
        let big = app.appendingPathComponent("Contents/Resources/ZZBig.bin")
        try fm.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        let zeros = try await ChildProcess.run(
            "/bin/dd", ["if=/dev/zero", "of=\(big.path)", "bs=1048576", "count=300"],
            onCancel: .runToCompletion)
        #expect(zeros.succeeded, "dd could not write the payload")
        let made = try await ChildProcess.run(
            "/usr/bin/hdiutil",
            ["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", "ZZFixture",
             "-o", image.path, source.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded, "hdiutil makehybrid failed")

        let task = Task { try await ArchiveExtractor.extractApp(from: image, workDir: work) }
        // `ditto` is copying once it is running on the mount's app, not merely
        // attaching the image (an `hdiutil attach` also names the mount point).
        let pattern = "/usr/bin/ditto .*\(mount.path)"
        // Bounded wait. On a Mac fast enough to finish the copy between two polls,
        // the cancel lands after it and the copy completes: the detach below is
        // still checked, but the copy was not caught mid-way. Nothing asserts
        // which of the two happened.
        for _ in 0..<400 {
            if try await ChildProcess.run(
                "/usr/bin/pgrep", ["-f", pattern], onCancel: .runToCompletion).succeeded { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        task.cancel()
        let result = await task.result
        if case .failure(let error) = result {
            #expect(error is CancellationError, "expected CancellationError, got \(error)")
        }
        // Read `hdiutil info` three times before concluding the image is gone.
        for _ in 0..<3 {
            #expect(!isMountPoint(mount), "the image stayed mounted after the cancelled copy")
            #expect(await !TestDiskImages.isAttached(image), "the image stayed attached after the cancelled copy")
        }
    }

    /// The tools that answer a license agreement from stdin on this Mac:
    /// `hdiutil` always, `diskutil image` from 27.2 — on 26.7 it ignores stdin
    /// and blocks on such an image (the reason `DiskImageMount` waits for 27.2).
    static let licenseTools: [DiskImageMount.Tool] = mountTools.filter {
        $0 == .hdiutil || ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0))
    }

    /// A vendor image wrapped in a license agreement installs: the attach
    /// answers `yes`, where an unanswered prompt cancels it (exit 1) and the
    /// update could never install.
    ///
    /// Mutation: drop `standardInput: licenseAnswer` from `DiskImageMount`'s
    /// attach → `toolFailed(…, 1, "…canceled…")`.
    @Test(arguments: InstallChildProcessTests.licenseTools)
    func aLicenseAgreementImageIsAcceptedAndMounts(tool: DiskImageMount.Tool) async throws {
        let fm = FileManager.default
        let top = try scratch("dmgsla")
        let work = top.appendingPathComponent("work", isDirectory: true)
        let mount = work.appendingPathComponent("mnt-ZZFixture.dmg")
        defer {
            await forceDetach(mount, image: work.appendingPathComponent("ZZFixture.dmg"))
            try? fm.removeItem(at: top)
        }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let image = try await licensedImage(in: top)
        try fm.copyItem(at: image, to: work.appendingPathComponent("ZZFixture.dmg"))

        let app = try await DiskImageMount.$toolOverride.withValue(tool) {
            try await ArchiveExtractor.extractApp(
                from: work.appendingPathComponent("ZZFixture.dmg"), workDir: work)
        }
        #expect(app.lastPathComponent == "ZZFixture.app")
        #expect(fm.fileExists(atPath: app.appendingPathComponent("Contents/payload").path))
        #expect(!isMountPoint(mount), "the image stayed mounted after the app was copied out")
    }

    /// `full.dmg` from `diskImages`, converted to UDIF (`udifrez` refuses
    /// `makehybrid`'s output) and given an English license agreement — the
    /// `LPic`/`STR#`/`TEXT` resources a vendor's image carries.
    private func licensedImage(in top: URL) async throws -> URL {
        let images = try await diskImages(in: top)
        let image = top.appendingPathComponent("licensed.dmg")
        let converted = try await ChildProcess.run(
            "/usr/bin/hdiutil",
            ["convert", "-quiet", images.full.path, "-format", "UDRO", "-o", image.path],
            onCancel: .runToCompletion)
        #expect(converted.succeeded, "hdiutil convert failed")
        let resources = top.appendingPathComponent("sla.xml")
        try Data(Self.licenseResources.utf8).write(to: resources)
        let added = try await ChildProcess.run(
            "/usr/bin/hdiutil", ["udifrez", "-xml", resources.path, "", "-quiet", image.path],
            onCancel: .runToCompletion)
        #expect(added.succeeded, "hdiutil udifrez failed")
        return image
    }

    /// Region 0 (English) → `STR#` 5000 (button labels) and `TEXT` 5000
    /// ("LICENSE TEXT").
    private static let licenseResources = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>LPic</key><array><dict><key>Attributes</key><string>0x0000</string>\
        <key>Data</key><data>AAAAAQAAAAAAAAAA</data><key>ID</key><string>5000</string>\
        <key>Name</key><string></string></dict></array>
        <key>STR#</key><array><dict><key>Attributes</key><string>0x0000</string>\
        <key>Data</key><data>AAYHRW5nbGlzaAVBZ3JlZQhEaXNhZ3JlZQVQcmludAdTYXZlLi4uDklmIHlvdSBhZ3JlZS4u</data>\
        <key>ID</key><string>5000</string><key>Name</key><string>English</string></dict></array>
        <key>TEXT</key><array><dict><key>Attributes</key><string>0x0000</string>\
        <key>Data</key><data>TElDRU5TRSBURVhU</data><key>ID</key><string>5000</string>\
        <key>Name</key><string>English SLA</string></dict></array>
        </dict></plist>
        """

    /// `diskutil image attach --mountPoint` refuses an image with two mountable
    /// volumes, where `hdiutil` mounts one; `DiskImageMount` must fall back
    /// rather than fail the install, and still detach afterwards.
    ///
    /// Mutation: return `first` without the `hdiutil` retry in
    /// `DiskImageMount.attach` → the extraction throws `toolFailed`.
    @Test(.enabled(if: InstallChildProcessTests.mountTools.contains(.diskutil)))
    func aTwoVolumeImageFallsBackToHdiutilUnderDiskutil() async throws {
        let fm = FileManager.default
        let top = try scratch("dmg2vol")
        let work = top.appendingPathComponent("work", isDirectory: true)
        let mount = work.appendingPathComponent("mnt-two.dmg")
        defer {
            await forceDetach(mount, image: work.appendingPathComponent("two.dmg"))
            // The fixture's own disk, should it have failed before detaching it.
            await TestDiskImages.detach(top.appendingPathComponent("two-rw.dmg"))
            try? fm.removeItem(at: top)
        }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let image = try await twoVolumeImage(in: top)
        try fm.copyItem(at: image, to: work.appendingPathComponent("two.dmg"))

        let app = try await DiskImageMount.$toolOverride.withValue(.diskutil) {
            try await ArchiveExtractor.extractApp(
                from: work.appendingPathComponent("two.dmg"), workDir: work)
        }
        #expect(app.lastPathComponent == "ZZFixture.app")
        #expect(!isMountPoint(mount), "the image stayed mounted after the fallback attach")
    }

    /// A UDZO image whose GPT holds two HFS+ volumes, `ZZFixture.app` on each.
    private func twoVolumeImage(in top: URL) async throws -> URL {
        struct FixtureFailed: Error {}
        // Every child is bounded: on the hosted xcode-27 runner one of them once
        // never returned, and the suite hung on this test until the job was
        // cancelled (diag run 39108932547, 2026-10-18). A minute and a half is
        // well past the slowest of these steps seen there.
        let bound = ChildProcess.Deadline(terminateAfter: .seconds(90), killAfter: .seconds(95))
        func launch(_ path: String, _ args: [String]) async throws -> ChildProcess.Outcome {
            let r = try await ChildProcess.run(path, args, deadline: bound, onCancel: .runToCompletion)
            if r.timedOut {
                Issue.record("\((path as NSString).lastPathComponent) \(args.first ?? "") did not exit in 90 s")
            }
            return r
        }
        func sh(_ path: String, _ args: [String]) async throws -> ChildProcess.Outcome {
            let r = try await launch(path, args)
            #expect(r.succeeded, """
                \((path as NSString).lastPathComponent) \(args.first ?? "") failed: \
                \(String(decoding: r.standardError, as: UTF8.self))
                """)
            return r
        }
        // The steps that need the disk to themselves. Right after `attach` and
        // after `partitionDisk`, something can still hold it for seconds — on the
        // hosted xcode-27 runner (macOS 27.0.1) `storagekitd` had /dev/rdiskN open
        // and `detach -force` failed "Resource busy" (exit 16) twice, then
        // succeeded 5 s after the first try (run 38239351399); `partitionDisk`
        // once failed "-69877: Couldn't open device" (run 38204609229). In the
        // full suite on that runner this fixture failed in every main run from
        // #1211 to 2026-10-12 (38160281041 … 38233464165). Not reproduced on a
        // 27.2 dev Mac. A retried `partitionDisk` that left a partial map would
        // show as `volumes.count != 2` below.
        func retrying(_ path: String, _ args: [String], for limit: Duration) async throws -> String? {
            let deadline = ContinuousClock.now + limit
            while true {
                let r = try await launch(path, args)
                if r.succeeded { return nil }
                guard ContinuousClock.now < deadline else {
                    return String(decoding: r.standardError, as: UTF8.self)
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
        let raw = top.appendingPathComponent("two-rw.dmg")
        // `partitionDisk` has also gone on failing -69877 for the whole minute it
        // was given, three times in ~200 full suites there (runs 39108932547,
        // 39111286040, 2026-10-18; 128 full suites), and what holds the disk
        // then is unknown. So after 30 s the disk is given up: detached, deleted,
        // made again, up to three times.
        var device = ""
        var partitionError: String?
        for round in 1...3 {
            if round > 1 {
                await TestDiskImages.detach(raw)
                try? FileManager.default.removeItem(at: raw)
            }
            _ = try await sh("/usr/bin/hdiutil", [
                "create", "-quiet", "-size", "40m", "-layout", "GPTSPUD", "-fs", "HFS+",
                "-volname", "V1", raw.path])
            let attached = try await sh("/usr/bin/hdiutil", ["attach", "-nomount", raw.path])
            device = String(decoding: attached.standardOutput, as: UTF8.self)
                .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            partitionError = try await retrying("/usr/sbin/diskutil", [
                "partitionDisk", device, "GPT", "HFS+", "V1", "20M", "HFS+", "V2", "R"],
                for: .seconds(30))
            if partitionError == nil { break }
        }
        if let partitionError {
            Issue.record("diskutil partitionDisk still failing on a third fresh disk: \(partitionError)")
            throw FixtureFailed()
        }
        // Mount both, drop the app on each, and detach. `mountDisk` has failed
        // there too, right after a `partitionDisk` that succeeded (run
        // 39108932547).
        if let mountError = try await retrying(
            "/usr/sbin/diskutil", ["mountDisk", device], for: .seconds(30)) {
            Issue.record("diskutil mountDisk still failing after 30 s: \(mountError)")
            throw FixtureFailed()
        }
        let listing = try await sh("/usr/sbin/diskutil", ["list", "-plist", device])
        let plist = try PropertyListSerialization.propertyList(
            from: listing.standardOutput, format: nil) as? [String: Any]
        let volumes = (plist?["AllDisksAndPartitions"] as? [[String: Any]])?
            .flatMap { $0["Partitions"] as? [[String: Any]] ?? [] }
            .compactMap { $0["MountPoint"] as? String } ?? []
        #expect(volumes.count == 2, "expected two mounted volumes, got \(volumes)")
        for volume in volumes {
            _ = try bundle(
                at: URL(fileURLWithPath: volume).appendingPathComponent("ZZFixture.app"),
                mode: 0o755, marker: "payload")
        }
        // Unmounted before the detach, so the apps just written are on the image:
        // once the image came out with no app on the volume the extraction
        // mounted (`noAppFound`, run 39111286040), and a forced detach of a
        // volume written a moment ago is the suspect (unverified).
        if let unmountError = try await retrying(
            "/usr/sbin/diskutil", ["unmountDisk", device], for: .seconds(30)) {
            Issue.record("diskutil unmountDisk still failing after 30 s: \(unmountError)")
            throw FixtureFailed()
        }
        if let detachError = try await retrying(
            "/usr/bin/hdiutil", ["detach", device, "-force"], for: .seconds(60)) {
            Issue.record("hdiutil detach still failing after 60 s: \(detachError)")
        }
        let image = top.appendingPathComponent("two.dmg")
        _ = try await sh("/usr/bin/hdiutil", [
            "convert", "-quiet", raw.path, "-format", "UDZO", "-o", image.path])
        return image
    }

    /// Two images: `full` holds `ZZFixture.app` and `ZZFixture.pkg` (a plain file
    /// is enough — nothing here opens it), `empty` holds neither. `makehybrid`
    /// rather than `create -srcfolder`: the same attachable HFS image in ~30 ms
    /// instead of ~5 s (measured on macOS 27).
    private func diskImages(in top: URL) async throws -> (full: URL, empty: URL) {
        await TestDiskImages.sweepStaleOnce()
        let fm = FileManager.default
        let fullSource = top.appendingPathComponent("src-full", isDirectory: true)
        _ = try bundle(at: fullSource.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "payload")
        try Data("pkg".utf8).write(to: fullSource.appendingPathComponent("ZZFixture.pkg"))
        let emptySource = top.appendingPathComponent("src-empty", isDirectory: true)
        try fm.createDirectory(at: emptySource, withIntermediateDirectories: true)
        try Data("nothing".utf8).write(to: emptySource.appendingPathComponent("README.txt"))

        var made: [URL] = []
        for (source, name) in [(fullSource, "full.dmg"), (emptySource, "empty.dmg")] {
            let image = top.appendingPathComponent(name)
            let result = try await ChildProcess.run(
                "/usr/bin/hdiutil",
                ["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", "ZZFixture",
                 "-o", image.path, source.path],
                onCancel: .runToCompletion)
            #expect(result.succeeded, "hdiutil makehybrid \(name) failed")
            made.append(image)
        }
        return (made[0], made[1])
    }

    /// A directory is a mount point when it sits on a different device from its
    /// parent. A missing directory is not one.
    private func isMountPoint(_ url: URL) -> Bool {
        var mine = stat(), parent = stat()
        guard stat(url.path, &mine) == 0,
              stat(url.deletingLastPathComponent().path, &parent) == 0 else { return false }
        return mine.st_dev != parent.st_dev
    }

    /// Test-side cleanup, so a red run does not leave an image attached — by its
    /// mount point while it has one, then by device for one left attached unmounted.
    private func forceDetach(_ mount: URL, image: URL) async {
        if isMountPoint(mount) {
            _ = try? await ChildProcess.run(
                "/usr/bin/hdiutil", ["detach", mount.path, "-force"], onCancel: .runToCompletion)
        }
        await TestDiskImages.detach(image)
    }

    // MARK: - Delta

    /// `BinaryDelta` is replaced by an invented tool inside an invented bundle, so
    /// this runs without Sparkle's binary and without asking the host for one. The
    /// tool writes more than a pipe buffer to stdout before failing — the old
    /// site sent stdout to `/dev/null` for exactly that reason — and the error
    /// must carry its exit status and the LAST line of its stderr.
    ///
    /// Mutation: take `.first` instead of `.last` of the stderr lines → the
    /// message is "first line". (A stdout drain that wedges the tool is
    /// `ChildProcessTests`' job, not repeated here.)
    @Test func aFailedPatchReportsTheToolsStatusAndLastStderrLine() async throws {
        let fm = FileManager.default
        let top = try scratch("delta")
        defer { try? fm.removeItem(at: top) }
        let host = try toolBundle(in: top, script: """
            head -c 200000 /dev/zero
            echo "first line" >&2
            echo "the real reason" >&2
            exit 4
            """)
        let out = top.appendingPathComponent("ZZNew.app")

        do {
            try await DeltaApplier.apply(
                installedApp: top, patch: top, destination: out, bundle: host)
            Issue.record("a failing tool applied a patch")
        } catch let DeltaApplier.DeltaError.applyFailed(code, message) {
            #expect(code == 4)
            #expect(message == "the real reason")
        }
    }

    /// A patch that is running when its task is cancelled runs to its end. The
    /// stand-in does what Sparkle's `BinaryDelta` does: it makes an
    /// `apply-binary-delta.*` file under `$TMPDIR`, works a while, then deletes that
    /// file and writes the destination. It also drops a `started` marker beside the
    /// destination, so the test can wait for it without listing `$TMPDIR`, which is
    /// large on a developer's Mac. The test cancels after the marker appears. The
    /// patch finishes, `apply` returns normally, and nothing is left in the
    /// process's temporary directory.
    ///
    /// Mutation: `DeltaApplier.apply` becomes `.terminateChild` → the stand-in is
    /// killed mid-work, `apply` throws `CancellationError`, the destination is never
    /// written, and the temporary diff stays in the process's temporary directory.
    @Test func aCancelledPatchRunsToEndAndLeavesNoTemporaryDiff() async throws {
        let fm = FileManager.default
        let top = try scratch("delta-cancel")
        defer { try? fm.removeItem(at: top) }
        // `apply <old> <new> <patch>`: $3 is the destination.
        let host = try toolBundle(in: top, script: """
            touch "$(dirname "$3")/started"
            f=$(mktemp "${TMPDIR:-/tmp}/apply-binary-delta.XXXXXXXXXX")
            printf 'diff' > "$f"
            sleep 0.5
            rm -f "$f"
            mkdir -p "$3/Contents"
            """)
        let out = top.appendingPathComponent("ZZNew.app")
        let started = top.appendingPathComponent("started")
        let processTemp = fm.temporaryDirectory
        let before = temporaryDiffs(in: processTemp)

        let task = Task {
            try await DeltaApplier.apply(installedApp: top, patch: top, destination: out, bundle: host)
        }
        // Bounded wait for the stand-in to be running, then cancel mid-work.
        for _ in 0..<400 where !fm.fileExists(atPath: started.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fm.fileExists(atPath: started.path), "the stand-in never started")
        task.cancel()
        let result = await task.result
        let left = temporaryDiffs(in: processTemp).subtracting(before)
        // Clean up only what this test made in the process's directory.
        for name in left { try? fm.removeItem(at: processTemp.appendingPathComponent(name)) }

        if case .failure(let error) = result {
            Issue.record("the patch was torn down by the cancel: \(error)")
        }
        #expect(fm.fileExists(atPath: out.appendingPathComponent("Contents").path),
                "the patch did not finish after the cancel")
        #expect(left.isEmpty, "a cancelled patch left \(left.sorted()) in the process's temporary directory")
    }

    /// Names of Sparkle's `apply-binary-delta.*` temporary files in `directory`.
    private func temporaryDiffs(in directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("apply-binary-delta.") })
    }

    // MARK: - Delta route

    /// A cancellation is the caller stopping the install, not the patch failing,
    /// so it never earns a second, full-size download.
    ///
    /// Mutation: delete the `CancellationError` guard in
    /// `deltaRouteFailureIsWorthRetrying` → it answers true.
    @Test func aCancellationIsNeverWorthRetrying() {
        #expect(!deltaRouteFailureIsWorthRetrying(CancellationError()))
    }

    /// A cancel that lands during the patch on the real Sparkle patch route does not
    /// stop the install there. The patch runs to its end (`DeltaApplier.apply` is
    /// `.runToCompletion`), and then the route goes on to the bundle gate, which
    /// refuses this fixture. That refusal is a `SignatureVerifier.VerifyError`, which
    /// the patch route wraps as `DeltaRouteFailure`. The test pins what is true
    /// today: no `CancellationError` comes out of the route, and the gate ran. There
    /// is no checkpoint between the patch and the swap, so a checkpoint added there
    /// changes this test on purpose.
    ///
    @Test func aCancelledPatchRouteRunsThePatchAndReachesTheGate() async throws {
        let fm = FileManager.default
        let top = try scratch("delta-route")
        defer { try? fm.removeItem(at: top) }
        // `apply <old> <new> <patch>`: $3 is the destination.
        let host = try toolBundle(in: top, script: """
            mkdir -p "$3/Contents"
            """)
        let tool = try #require(DeltaApplier.toolURL(bundle: host))

        // The installed app, at the build the patch was cut against.
        let installed = top.appendingPathComponent("ZZInstalled.app", isDirectory: true)
        try fm.createDirectory(at: installed.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>com.example.zzfixture.delta</string>
            <key>CFBundleVersion</key><string>1.1.0</string>
            </dict></plist>
            """.utf8).write(to: installed.appendingPathComponent("Contents/Info.plist"))
        let app = InstalledApp(
            name: "ZZInstalled", bundleID: "com.example.zzfixture.delta", shortVersion: "1.1",
            buildVersion: "1.1.0", path: installed, isMASApp: false,
            sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
            hasSelfUpdater: false, hasSparkleUpdater: true)
        let patchFile = top.appendingPathComponent("ZZPatch.delta")
        try Data("patch".utf8).write(to: patchFile)
        let patch = DeltaPatch(
            fromBuild: "1.1.0", url: URL(string: "https://example.com/1.1.0-1.2.0.delta")!,
            size: 5, edSignature: nil)
        let download = DownloadedUpdate(
            archiveURL: patchFile, bytesDownloaded: 5, workDir: top, appliedPatch: patch)
        let remote = RemoteVersion(
            shortVersion: "1.2", version: "1.2.0",
            downloadURL: URL(string: "https://example.com/ZZInstalled-1.2.zip"),
            sourceName: "Sparkle")
        let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "1.2.0"))

        var routeError: Error?
        do {
            try await DeltaApplier.$toolOverride.withValue(tool) {
                try await cancelledBeforeStart {
                    try await SparkleInstaller().apply(result, download: download, onStage: { _ in })
                }
            }
        } catch { routeError = error }

        #expect(fm.fileExists(atPath: top.appendingPathComponent("patched-ZZInstalled.app/Contents").path),
                "the patch did not run to its end")
        #expect(!(routeError is CancellationError), "the cancel stopped the route before the gate")
        let refusal = (routeError as? DeltaRouteFailure)?.underlying
        #expect(refusal is SignatureVerifier.VerifyError, "the bundle gate did not run: \(String(describing: routeError))")
    }

    // MARK: - Backups

    /// A cancelled backup stores nothing: it comes before the install's commit
    /// point, so its `ditto` is stopped (here: never started) and its staging
    /// removed — plans/update-cancellation.md §2.3 D2. A rollback cancelled
    /// before it starts stops at its point of no return (`InstallCommit`) and
    /// leaves the live app as it is; run uncancelled, it puts the copy back.
    ///
    /// Mutations: drop the `!ditto.ok, Task.isCancelled` branch in
    /// `BackupStore.write` → `save` throws `copyFailed`, red; drop the restore's
    /// `InstallCommit` → the cancelled rollback swaps, red.
    @Test func aCancelledBackupKeepsNothingAndACancelledRollbackStopsAtItsCommit() async throws {
        let fm = FileManager.default
        let top = try scratch("backup")
        defer { try? fm.removeItem(at: top) }
        let store = top.appendingPathComponent("store", isDirectory: true)
        let app = try bundle(at: top.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "v1")

        try await BackupStore.$rootOverride.withValue(store) {
            await #expect(throws: CancellationError.self) {
                _ = try await cancelledBeforeStart {
                    try await BackupStore.save(
                        appPath: app, key: "zzfixture", version: "1.0", bundleID: nil)
                }
            }
            #expect(BackupStore.backup(forKey: "zzfixture") == nil)
            #expect(((try? fm.contentsOfDirectory(atPath: store.path)) ?? []).isEmpty)

            let saved = try await BackupStore.save(
                appPath: app, key: "zzfixture", version: "1.0", bundleID: nil)
            #expect(fm.fileExists(atPath: saved.bundlePath.appendingPathComponent("Contents/v1").path))

            // The update lands.
            try fm.removeItem(at: app.appendingPathComponent("Contents/v1"))
            try Data("v2".utf8).write(to: app.appendingPathComponent("Contents/v2"))

            await #expect(throws: CancellationError.self) {
                _ = try await cancelledBeforeStart {
                    try await BackupStore.restore(forKey: "zzfixture", over: app)
                }
            }
            #expect(fm.fileExists(atPath: app.appendingPathComponent("Contents/v2").path))
            #expect(!fm.fileExists(atPath: app.appendingPathComponent("Contents/v1").path))

            let restored = try await BackupStore.restore(forKey: "zzfixture", over: app)
            #expect(restored == "1.0")
            #expect(fm.fileExists(atPath: app.appendingPathComponent("Contents/v1").path))
            #expect(!fm.fileExists(atPath: app.appendingPathComponent("Contents/v2").path))
        }
    }

    // MARK: - Package gate

    /// The destination gate's `xar -tf`, `xar -xf` (in a working directory) and
    /// `lsbom`, against a real flat package built here with `pkgbuild` — and in a
    /// cancelled task, which must not turn "could not read" into the fail-closed
    /// answer. An empty set is exactly what a killed `xar` would produce, and the
    /// gate refuses the package on it.
    ///
    /// Mutations: (a) `PackageInstaller.runCapturing` becomes `.terminateChild` →
    /// the set is empty; (b) drop `workingDirectory: cwd` → `xar -xf` writes
    /// `PackageInfo` and `Bom` somewhere other than the scratch directory, neither
    /// is read back, and the set is empty.
    @Test func aCancelledPackageGateStillReadsTheDeclaredDestinations() async throws {
        let fm = FileManager.default
        let top = try scratch("pkg")
        defer { try? fm.removeItem(at: top) }
        let payload = top.appendingPathComponent("root", isDirectory: true)
        _ = try bundle(
            at: payload.appendingPathComponent("Applications/ZZFixture.app"), mode: 0o755, marker: "bin")
        let pkg = top.appendingPathComponent("ZZFixture.pkg")
        let built = try await ChildProcess.run(
            "/usr/bin/pkgbuild",
            ["--root", payload.path, "--identifier", "com.example.zzfixture",
             "--version", "1.0", "--install-location", "/", pkg.path],
            onCancel: .runToCompletion)
        #expect(built.succeeded, "\(String(decoding: built.standardError, as: UTF8.self))")

        let destinations = await cancelledBeforeStartNonThrowing {
            await PackageInstaller.declaredDestinations(pkg)
        }

        #expect(destinations.contains("/Applications/ZZFixture.app"))
    }

    // MARK: - Helpers

    /// Run `body` in a task that is already cancelled when it starts.
    private func cancelledBeforeStart<T: Sendable>(
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let task = Task { () async throws -> T in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(Task.isCancelled, "the fixture task must really be cancelled")
            return try await body()
        }
        return try await task.value
    }

    private func cancelledBeforeStartNonThrowing<T: Sendable>(
        _ body: @escaping @Sendable () async -> T
    ) async -> T {
        let task = Task { () async -> T in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(Task.isCancelled, "the fixture task must really be cancelled")
            return await body()
        }
        return await task.value
    }

    private func scratch(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-install-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `Contents/<marker>` and a `Contents/Resources` level, every directory at
    /// `mode`. Nothing else at the top, so it also qualifies for a rotation.
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

    /// An invented app bundle whose `Contents/MacOS/BinaryDelta` is `script`, so
    /// `DeltaApplier.toolURL(bundle:)` finds it there before it ever looks at the
    /// installed DuoUpdater.
    private func toolBundle(in dir: URL, script: String) throws -> Bundle {
        let fm = FileManager.default
        let app = dir.appendingPathComponent("ZZToolHost.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>com.example.zzfixture.toolhost</string>
            <key>CFBundleExecutable</key><string>ZZToolHost</string>
            </dict></plist>
            """
        try Data(info.utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let tool = macOS.appendingPathComponent("BinaryDelta")
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: tool)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let bundle = try #require(Bundle(url: app))
        #expect(DeltaApplier.toolURL(bundle: bundle)?.standardizedFileURL == tool.standardizedFileURL,
                "the fixture tool must be the one found, not an installed BinaryDelta")
        return bundle
    }

    private static let quarantine = "com.apple.quarantine"

    private func setQuarantine(on url: URL) throws {
        let value = Array("0081;00000000;ZZFixture;".utf8)
        let status = value.withUnsafeBytes {
            setxattr(url.path, Self.quarantine, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
        }
        #expect(status == 0)
    }

    private func hasQuarantine(_ url: URL) -> Bool {
        getxattr(url.path, Self.quarantine, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}

/// Set once a test has its answer, so a watchdog on another thread can tell that
/// the answer is in and it has nothing to unblock.
private final class FinishFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
