import Foundation
import Testing
@testable import DuoUpdaterCore

/// The install path's child processes, run against invented bundles in scratch
/// directories — never a real app, never `/Applications`.
///
/// Mostly about the one behaviour `ChildProcess` could have changed: cancellation.
/// Every child on this path is `.runToCompletion`, because the old
/// `offCooperativePool` hop could not be cancelled and a half-done write is worse
/// than a finished one. Each test here runs the operation in a task that is
/// cancelled BEFORE it starts. `.terminateChild` refuses to spawn into an
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

    /// A cancelled extraction still produces the app — `ditto -x -k` ran to its end.
    ///
    /// Mutation: `ArchiveExtractor.run` becomes `.terminateChild` → `ditto` is never
    /// allowed to finish and the call throws `CancellationError`.
    @Test func aCancelledExtractionStillUnpacksTheApp() async throws {
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

        let app = try await cancelledBeforeStart {
            try await ArchiveExtractor.extractApp(from: zip, workDir: work)
        }

        #expect(app.lastPathComponent == "ZZFixture.app")
        #expect(fm.fileExists(atPath: app.appendingPathComponent("Contents/payload").path))
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

    /// A cancelled DMG extraction still unmounts the image, on the exit that
    /// copied the app out and on the one that found none. The unmount sits in a
    /// `defer { await … }`, which sees the task as cancelled (SE-0493) — so this
    /// is also what pins `hdiutil detach` to `.runToCompletion` there.
    ///
    /// Mutation: drop the `defer { await detach(mountPoint) }` in `fromDMG` → both
    /// mount points are still mounted when the call returns or throws.
    @Test func aCancelledDMGExtractionUnmountsOnBothExits() async throws {
        let fm = FileManager.default
        let top = try scratch("dmg")
        let images = try await diskImages(in: top)
        let withApp = top.appendingPathComponent("work-app", isDirectory: true)
        let without = top.appendingPathComponent("work-none", isDirectory: true)
        let mounts = [withApp, without].map { $0.appendingPathComponent("mnt-ZZFixture.dmg") }
        defer {
            for mount in mounts { await forceDetach(mount) }
            try? fm.removeItem(at: top)
        }

        try fm.createDirectory(at: withApp, withIntermediateDirectories: true)
        try fm.copyItem(at: images.full, to: withApp.appendingPathComponent("ZZFixture.dmg"))
        let app = try await cancelledBeforeStart {
            try await ArchiveExtractor.extractApp(
                from: withApp.appendingPathComponent("ZZFixture.dmg"), workDir: withApp)
        }
        #expect(app.lastPathComponent == "ZZFixture.app")
        #expect(fm.fileExists(atPath: app.appendingPathComponent("Contents/payload").path))
        #expect(!isMountPoint(mounts[0]), "the image stayed mounted after the app was copied out")

        try fm.createDirectory(at: without, withIntermediateDirectories: true)
        try fm.copyItem(at: images.empty, to: without.appendingPathComponent("ZZFixture.dmg"))
        await #expect(throws: ArchiveExtractor.ExtractError.self) {
            _ = try await cancelledBeforeStart {
                try await ArchiveExtractor.extractApp(
                    from: without.appendingPathComponent("ZZFixture.dmg"), workDir: without)
            }
        }
        #expect(!isMountPoint(mounts[1]), "the image stayed mounted after no app was found")
    }

    /// The package route's DMG, same two exits: a `.pkg` copied out, and none.
    ///
    /// Mutation: drop the `defer { _ = await run("/usr/bin/hdiutil", ["detach", …]) }`
    /// in `resolveInstaller` → both mount points are still mounted.
    @Test func aCancelledPackageImageUnmountsOnBothExits() async throws {
        let fm = FileManager.default
        let top = try scratch("pkgdmg")
        let images = try await diskImages(in: top)
        let withPkg = top.appendingPathComponent("work-pkg", isDirectory: true)
        let without = top.appendingPathComponent("work-none", isDirectory: true)
        let mounts = [withPkg, without].map { $0.appendingPathComponent("mnt") }
        defer {
            for mount in mounts { await forceDetach(mount) }
            try? fm.removeItem(at: top)
        }
        let installer = PackageInstaller(opener: { _ in })
        let installedApp = top.appendingPathComponent("ZZFixture.app")

        try fm.createDirectory(at: withPkg, withIntermediateDirectories: true)
        let copied = try await cancelledBeforeStart {
            try await installer.resolveInstaller(
                from: images.full, workDir: withPkg, installedApp: installedApp)
        }
        #expect(copied == withPkg.appendingPathComponent("ZZFixture.pkg"))
        #expect(fm.fileExists(atPath: copied.path))
        #expect(!isMountPoint(mounts[0]), "the image stayed mounted after the package was copied out")

        try fm.createDirectory(at: without, withIntermediateDirectories: true)
        await #expect(throws: PackageInstaller.PackageError.self) {
            _ = try await cancelledBeforeStart {
                try await installer.resolveInstaller(
                    from: images.empty, workDir: without, installedApp: installedApp)
            }
        }
        #expect(!isMountPoint(mounts[1]), "the image stayed mounted after no package was found")
    }

    /// Two images: `full` holds `ZZFixture.app` and `ZZFixture.pkg` (a plain file
    /// is enough — nothing here opens it), `empty` holds neither. `makehybrid`
    /// rather than `create -srcfolder`: the same attachable HFS image in ~30 ms
    /// instead of ~5 s (measured on macOS 27).
    private func diskImages(in top: URL) async throws -> (full: URL, empty: URL) {
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

    /// Test-side cleanup, so a red run does not leave an image attached.
    private func forceDetach(_ mount: URL) async {
        guard isMountPoint(mount) else { return }
        _ = try? await ChildProcess.run(
            "/usr/bin/hdiutil", ["detach", mount.path, "-force"], onCancel: .runToCompletion)
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

    /// A cancelled patch still finishes — a `BinaryDelta` killed partway leaves a
    /// half-written bundle at the destination.
    ///
    /// Mutation: `DeltaApplier.apply` becomes `.terminateChild` → the call throws
    /// `CancellationError` and the destination is never created.
    @Test func aCancelledPatchStillFinishes() async throws {
        let fm = FileManager.default
        let top = try scratch("delta-cancel")
        defer { try? fm.removeItem(at: top) }
        // `apply <old> <new> <patch>`: $3 is the destination.
        let host = try toolBundle(in: top, script: """
            sleep 0.2
            mkdir -p "$3/Contents"
            """)
        let out = top.appendingPathComponent("ZZNew.app")

        try await cancelledBeforeStart {
            try await DeltaApplier.apply(
                installedApp: top, patch: top, destination: out, bundle: host)
        }

        #expect(fm.fileExists(atPath: out.appendingPathComponent("Contents").path))
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
