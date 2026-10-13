import Foundation
import Testing
@testable import DuoUpdaterCore

/// `DiskImageMount.detach` when a detach by mount point unmounts the volume but
/// leaves the image's disk attached — seen on the hosted xcode-27 runner, where
/// the disk stayed busy for seconds and the image stayed attached with nothing
/// reported. The scripted cases replay that sequence step by step; the last case
/// makes the same state with real tools.
///
/// Each names the mutation that turns it red.
@Suite struct DiskImageMountDetachTests {

    enum Event: Equatable {
        case path(DiskImageMount.Tool)
        case pause(Duration)
        case lookUp
        case device(String, DiskImageMount.Tool)
    }

    /// Scripted answers, taken in order; the last one repeats. The clock only
    /// moves when `detach` pauses.
    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var byPath: [Bool]
        private var attachments: [DiskImageMount.Attachment]
        private var byDevice: [Bool]
        private var recorded: [Event] = []
        private var elapsed: Duration = .zero
        private let start = ContinuousClock.now

        init(byPath: [Bool], attachments: [DiskImageMount.Attachment] = [.unknown], byDevice: [Bool] = [false]) {
            self.byPath = byPath
            self.attachments = attachments
            self.byDevice = byDevice
        }

        var events: [Event] { lock.withLock { recorded } }

        var steps: DiskImageMount.DetachSteps {
            DiskImageMount.DetachSteps(
                byMountPoint: { _, tool in self.take(\.byPath, .path(tool)) },
                attachment: { _ in self.take(\.attachments, .lookUp) },
                byDevice: { device, tool in
                    // A bound for the mutation that drops the deadline: rather
                    // than hang, it "succeeds" — which the give-up case reads as red.
                    if self.events.filter({ if case .device = $0 { true } else { false } }).count >= 1000 {
                        return true
                    }
                    return self.take(\.byDevice, .device(device, tool))
                },
                pause: { duration in
                    self.lock.withLock {
                        self.recorded.append(.pause(duration))
                        self.elapsed += duration
                    }
                },
                now: { self.lock.withLock { self.start + self.elapsed } })
        }

        private func take<T>(_ answers: ReferenceWritableKeyPath<Script, [T]>, _ event: Event) -> T {
            lock.withLock {
                recorded.append(event)
                let answer = self[keyPath: answers][0]
                if self[keyPath: answers].count > 1 { self[keyPath: answers].removeFirst() }
                return answer
            }
        }
    }

    private let mountPoint = URL(fileURLWithPath: "/tmp/ZZFixture-mnt")
    private let image = URL(fileURLWithPath: "/tmp/ZZFixture.dmg")

    private func detach(_ script: Script, preferring tool: DiskImageMount.Tool = .hdiutil) async -> Bool {
        await DiskImageMount.$toolOverride.withValue(tool) {
            await DiskImageMount.detach(mountPoint, image: image, steps: script.steps)
        }
    }

    /// A detach that works by path costs nothing more: no `hdiutil info`.
    ///
    /// Mutation: look the image up before the first try by path → `lookUp` is
    /// among the events.
    @Test func aDetachByPathThatWorksLooksNothingUp() async {
        let script = Script(byPath: [true])
        #expect(await detach(script))
        #expect(script.events == [.path(.hdiutil)])
    }

    /// The other tool still gets its try by path, after the pause.
    ///
    /// Mutation: go by device straight after the first failure → the second
    /// `.path` is missing.
    @Test func theOtherToolStillTriesByPathFirst() async {
        let script = Script(byPath: [false, true])
        #expect(await detach(script))
        #expect(script.events == [.path(.hdiutil), .pause(.milliseconds(500)), .path(.diskutil)])
    }

    /// The runner's sequence: both tries by path fail, the image is still
    /// attached, and its disk is busy for two more tries. It comes off by device,
    /// with the preferred tool, a second apart.
    ///
    /// Mutation: return `false` after the second try by path (the old code) →
    /// red. Mutation: `byDevice(device, tools[1])` → the device events name the
    /// other tool, on both arguments.
    @Test(arguments: [DiskImageMount.Tool.hdiutil, .diskutil])
    func aDiskLeftAttachedIsDetachedByDevice(preferring tool: DiskImageMount.Tool) async {
        let other: DiskImageMount.Tool = tool == .hdiutil ? .diskutil : .hdiutil
        let script = Script(byPath: [false], attachments: [.disk("/dev/disk15")], byDevice: [false, false, true])
        #expect(await detach(script, preferring: tool))
        #expect(script.events == [
            .path(tool), .pause(.milliseconds(500)), .path(other),
            .lookUp, .device("/dev/disk15", tool), .pause(.seconds(1)),
            .lookUp, .device("/dev/disk15", tool), .pause(.seconds(1)),
            .lookUp, .device("/dev/disk15", tool),
        ])
    }

    /// Both tries by path failed but the image is gone (the first had taken it
    /// after all): detached, nothing to eject.
    ///
    /// Mutation: `case .none: return false` → red.
    @Test func anImageAlreadyGoneCountsAsDetached() async {
        let script = Script(byPath: [false], attachments: [.none])
        #expect(await detach(script))
        #expect(!script.events.contains { if case .device = $0 { true } else { false } })
    }

    /// The disk frees between tries and something else takes it: the next look
    /// finds it gone, which is a success, not one more eject.
    ///
    /// Mutation: look the image up once before the loop instead of on every try →
    /// the second look never happens and the retry keeps ejecting `/dev/disk15`
    /// until the bound, returning `false`.
    @Test func eachTryLooksTheImageUpAgain() async {
        let script = Script(byPath: [false], attachments: [.disk("/dev/disk15"), .none], byDevice: [false])
        #expect(await detach(script))
        #expect(script.events.filter { $0 == .device("/dev/disk15", .hdiutil) }.count == 1)
    }

    /// An `hdiutil info` that cannot be read is not taken as "detached".
    ///
    /// Mutation: `case .unknown: return true` → red.
    @Test func anUnreadableTableIsNotReportedAsDetached() async {
        let script = Script(byPath: [false], attachments: [.unknown])
        #expect(await !detach(script))
        #expect(!script.events.contains { if case .device = $0 { true } else { false } })
    }

    /// A disk that never frees: 31 tries, at 0 s and every second through 30 s,
    /// then `false`. The bound is checked here as a literal, and separately below.
    ///
    /// Mutation: drop the deadline guard → the script's 1000-try bound answers
    /// `true` → red. Mutation: `deviceRetryBound = .seconds(5)` → 6 tries.
    @Test func aDiskThatNeverFreesIsGivenUpAfterThirtySeconds() async {
        let script = Script(byPath: [false], attachments: [.disk("/dev/disk15")], byDevice: [false])
        #expect(await !detach(script))
        let tries = script.events.filter { $0 == .device("/dev/disk15", .hdiutil) }.count
        #expect(tries == 31)
        #expect(script.events.filter { $0 == .pause(.seconds(1)) }.count == 30)
    }

    @Test func theDeviceRetryBoundIsThirtySeconds() {
        #expect(DiskImageMount.deviceRetryBound == .seconds(30))
    }

    // MARK: - Real tools

    static func diagPoll(_ label: String, _ image: URL) async {
        for i in 0..<6 {
            let table = await TestDiskImages.attachments()
                .map { "\($0.imagePath)→\($0.device ?? "nil")" }.joined(separator: " | ")
            let raw = try? await ChildProcess.run("/usr/bin/hdiutil", ["info", "-plist"], onCancel: .runToCompletion)
            let lookup = await DiskImageMount.attachment(of: image)
            DiagDisk.line("POLL \(DiagDisk.stamp()) \(label) #\(i) lookup=\(lookup) rc=\(raw?.terminationStatus ?? -99) bytes=\(raw?.standardOutput.count ?? -1) table=\(table)")
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// The leaked state made on purpose with real tools: attach, then unmount the
    /// volume with `diskutil unmount`, which leaves the disk attached. Both tries
    /// by path then fail ("No such file or directory", "Failed to find disk" —
    /// measured on 27.2), and only the fallback by device takes the image off.
    /// The look-up must find the image under either spelling of `$TMPDIR`.
    ///
    /// Mutation: return `false` after the second try by path → the image is
    /// still attached. Mutation: `canonicalPath` returns its argument → the
    /// `/private` spelling is not found.
    @Test(arguments: InstallChildProcessTests.mountTools)
    func anImageWhoseVolumeIsAlreadyUnmountedIsDetached(tool: DiskImageMount.Tool) async throws {
        await TestDiskImages.sweepStaleOnce()
        let fm = FileManager.default
        let top = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-install-detach-\(UUID().uuidString)", isDirectory: true)
        let source = top.appendingPathComponent("src", isDirectory: true)
        let image = top.appendingPathComponent("ZZFixture.dmg")
        let mount = top.appendingPathComponent("mnt", isDirectory: true)
        defer {
            await TestDiskImages.detach(image)
            try? fm.removeItem(at: top)
        }
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: source.appendingPathComponent("payload"))
        let made = try await ChildProcess.run(
            "/usr/bin/hdiutil",
            ["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", "ZZFixture", "-o", image.path, source.path],
            onCancel: .runToCompletion)
        try #require(made.succeeded, "hdiutil makehybrid failed")

        try await DiskImageMount.$toolOverride.withValue(tool) {
            guard case .success = try await DiskImageMount.attach(image, at: mount) else {
                Issue.record("attach failed")
                return
            }
            let unmounted = try await ChildProcess.run(
                "/usr/sbin/diskutil", ["unmount", mount.path], onCancel: .runToCompletion)
            try #require(unmounted.succeeded, "diskutil unmount failed")

            DiagDisk.line("TEST \(DiagDisk.stamp()) \(tool) unmounted image=\(image.path)")
            let first = await DiskImageMount.attachment(of: image)
            DiagDisk.line("TEST \(DiagDisk.stamp()) \(tool) lookup1=\(first)")
            guard case .disk(let device) = first else {
                await Self.diagPoll("lookup1-miss \(tool)", image)
                Issue.record("the unmounted image is not listed as attached")
                return
            }
            let otherSpelling = image.path.hasPrefix("/private/")
                ? String(image.path.dropFirst("/private".count)) : "/private" + image.path
            let second = await DiskImageMount.attachment(of: URL(fileURLWithPath: otherSpelling))
            DiagDisk.line("TEST \(DiagDisk.stamp()) \(tool) lookup2(\(otherSpelling))=\(second)")
            if second != .disk(device) { await Self.diagPoll("lookup2-miss \(tool) \(device)", image) }
            #expect(second == .disk(device))

            #expect(await DiskImageMount.detach(mount, image: image))
            #expect(await !TestDiskImages.isAttached(image), "the image is still attached")
            #expect(await DiskImageMount.attachment(of: image) == DiskImageMount.Attachment.none)
        }
    }
}
