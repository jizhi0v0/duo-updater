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
/// (`ArchiveExtractor.run`), the patch (`DeltaApplier.apply`) and the package copy
/// (`PackageInstaller.run`), so those are `.terminateChild`. Each test here runs
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
    /// A watchdog writes a real archive into the FIFO six seconds after `ditto`
    /// starts, if the call has not returned yet. That keeps the `.runToCompletion`
    /// mutation a failure rather than a hang: it lets `ditto` finish and returns the
    /// app, which fails both expectations below.
    ///
    /// Mutation: `ArchiveExtractor.run` becomes `.runToCompletion` → the call waits
    /// for the watchdog and returns the app.
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
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            guard !finished.isSet, let bytes = try? Data(contentsOf: realZip) else { return }
            // Blocks until `ditto` opens the read end, which only a still-running
            // `ditto` does; a torn-down one never does, so this is skipped above.
            let fd = open(fifo.path, O_WRONLY)
            guard fd >= 0 else { return }
            _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }

        let task = Task { try await ArchiveExtractor.extractApp(from: fifo, workDir: work) }
        // `ditto` is running once `pgrep -f` can see it on the FIFO's path.
        var running = false
        for _ in 0..<100 where !running {
            running = try await ChildProcess.run(
                "/usr/bin/pgrep", ["-f", fifo.path], onCancel: .runToCompletion).succeeded
            if !running { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(running, "ditto never started on the FIFO")

        let cancelledAt = ContinuousClock.now
        task.cancel()
        let result = await task.result
        finished.set()
        let returnedIn = ContinuousClock.now - cancelledAt

        switch result {
        case .success(let app):
            Issue.record("the extraction returned \(app.lastPathComponent) after the cancel")
        case .failure(let error):
            #expect(error is CancellationError, "expected CancellationError, got \(error)")
        }
        #expect(returnedIn < .seconds(3), "the cancelled extraction took \(returnedIn) to return")
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
        func sh(_ path: String, _ args: [String]) async throws -> ChildProcess.Outcome {
            let r = try await ChildProcess.run(path, args, onCancel: .runToCompletion)
            #expect(r.succeeded, "\((path as NSString).lastPathComponent) \(args.first ?? "") failed")
            return r
        }
        // The two steps that need the disk to themselves. Right after `attach` and
        // after `partitionDisk`, something can still hold it for seconds — on the
        // hosted xcode-27 runner (macOS 27.0.1) `storagekitd` had /dev/rdiskN open
        // and `detach -force` failed "Resource busy" (exit 16) twice, then
        // succeeded 5 s after the first try (run 38239351399); `partitionDisk`
        // once failed "-69877: Couldn't open device" (run 38204609229). In the
        // full suite on that runner this fixture failed in every main run from
        // #1211 to 2026-10-12 (38160281041 … 38233464165). Not reproduced on a
        // 27.2 dev Mac. A retried `partitionDisk` that left a partial map would
        // show as `volumes.count != 2` below.
        func retrying(_ path: String, _ args: [String]) async throws {
            let deadline = ContinuousClock.now + .seconds(60)
            while true {
                let r = try await ChildProcess.run(path, args, onCancel: .runToCompletion)
                if r.succeeded { return }
                guard ContinuousClock.now < deadline else {
                    Issue.record("""
                        \((path as NSString).lastPathComponent) \(args.first ?? "") still \
                        failing after 60 s: \(String(decoding: r.standardError, as: UTF8.self))
                        """)
                    return
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
        let raw = top.appendingPathComponent("two-rw.dmg")
        _ = try await sh("/usr/bin/hdiutil", [
            "create", "-quiet", "-size", "40m", "-layout", "GPTSPUD", "-fs", "HFS+",
            "-volname", "V1", raw.path])
        let attached = try await sh("/usr/bin/hdiutil", ["attach", "-nomount", raw.path])
        let device = String(decoding: attached.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        try await retrying("/usr/sbin/diskutil", [
            "partitionDisk", device, "GPT", "HFS+", "V1", "20M", "HFS+", "V2", "R"])
        // Mount both, drop the app on each, and detach.
        _ = try await sh("/usr/sbin/diskutil", ["mountDisk", device])
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
        try await retrying("/usr/bin/hdiutil", ["detach", device, "-force"])
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

    /// A cancelled patch is not applied: `BinaryDelta` never spawns into a task that
    /// is already cancelled, the call throws `CancellationError`, and the destination
    /// (in the install's own work directory) is never written. The destination lives
    /// in a work directory the install deletes afterwards, so a `BinaryDelta` killed
    /// partway would leave nothing that outlives the install.
    ///
    /// Mutation: `DeltaApplier.apply` becomes `.runToCompletion` → the tool runs to
    /// its end, the destination is created, and the call returns normally.
    @Test func aCancelledPatchIsNotAppliedAndThrows() async throws {
        let fm = FileManager.default
        let top = try scratch("delta-cancel")
        defer { try? fm.removeItem(at: top) }
        // `apply <old> <new> <patch>`: $3 is the destination.
        let host = try toolBundle(in: top, script: """
            sleep 0.2
            mkdir -p "$3/Contents"
            """)
        let out = top.appendingPathComponent("ZZNew.app")

        await #expect(throws: CancellationError.self) {
            try await cancelledBeforeStart {
                try await DeltaApplier.apply(
                    installedApp: top, patch: top, destination: out, bundle: host)
            }
        }

        #expect(!fm.fileExists(atPath: out.appendingPathComponent("Contents").path))
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

    /// A cancelled patch apply on the real Sparkle patch route surfaces as
    /// `CancellationError` itself. It is not wrapped in `DeltaRouteFailure`, which
    /// is the only error `InstallCoordinator` answers with a full-archive retry.
    /// The `BinaryDelta` is a fixture (`DeltaApplier.$toolOverride`), and it must
    /// not run: the destination is never written.
    ///
    /// Mutation: delete the `CancellationError` guard in
    /// `deltaRouteFailureIsWorthRetrying` → the call throws `DeltaRouteFailure`
    /// and this fails.
    @Test func aCancelledSparklePatchRouteThrowsCancellationNotARetry() async throws {
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

        await #expect(throws: CancellationError.self) {
            try await DeltaApplier.$toolOverride.withValue(tool) {
                try await cancelledBeforeStart {
                    try await SparkleInstaller().apply(result, download: download, onStage: { _ in })
                }
            }
        }
        #expect(!fm.fileExists(atPath: top.appendingPathComponent("patched-ZZInstalled.app/Contents").path),
                "the patch tool ran although the task was cancelled")
    }

    // MARK: - Backups

    /// A cancelled backup still stores a complete copy, and a cancelled rollback
    /// still puts it back — both `ditto`s (and the swap under the rollback) ran to
    /// their end.
    ///
    /// Mutation: `BackupStore.runDitto` becomes `.terminateChild` → `save` throws
    /// `copyFailed` with nothing stored.
    @Test func aCancelledBackupAndRollbackStillComplete() async throws {
        let fm = FileManager.default
        let top = try scratch("backup")
        defer { try? fm.removeItem(at: top) }
        let store = top.appendingPathComponent("store", isDirectory: true)
        let app = try bundle(at: top.appendingPathComponent("ZZFixture.app"), mode: 0o755, marker: "v1")

        try await BackupStore.$rootOverride.withValue(store) {
            let saved = try await cancelledBeforeStart {
                try await BackupStore.save(
                    appPath: app, key: "zzfixture", version: "1.0", bundleID: nil)
            }
            #expect(fm.fileExists(atPath: saved.bundlePath.appendingPathComponent("Contents/v1").path))

            // The update lands.
            try fm.removeItem(at: app.appendingPathComponent("Contents/v1"))
            try Data("v2".utf8).write(to: app.appendingPathComponent("Contents/v2"))

            let restored = try await cancelledBeforeStart {
                try await BackupStore.restore(forKey: "zzfixture", over: app)
            }
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
