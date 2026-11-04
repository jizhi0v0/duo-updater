import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// terminal-mac: finding the copy its installer leaves, reading its version and
/// build out of the bundle, its verdict on the release tag, its one-click (the
/// pinned archive, checked against GitHub's digest, then its own `install.sh`).
///
/// "terminal-mac" here is a small `TerminalMac.app` with an `Info.plist`, and
/// the archive's installer copies it into the prefix's versioned directory and
/// repoints the launcher, as the real one does. The release answer and the
/// archive download are injected: nothing here reaches the network.
@Suite struct TerminalMacTests {

    static let bundleID = "dev.terminal-mac.host"
    static let digest = "0123456789ab"

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var library: URL { home.appendingPathComponent(".local/lib/terminal-mac") }
        var launcher: URL { bin.appendingPathComponent("terminal-mac") }

        init() throws {
            let made = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZZFixture-terminal-mac-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path)
            try? FileManager.default.removeItem(at: root)
        }

        var scanner: TerminalMacScanner { TerminalMacScanner(home: home) }

        /// A bundle the installer's layout names, and a launcher pointing into
        /// it. Blocking.
        @discardableResult
        func install(_ version: String, build: String, digest: String = TerminalMacTests.digest,
                     identifier: String = TerminalMacTests.bundleID, directory: String? = nil) throws -> URL {
            let bundle = library.appendingPathComponent(directory ?? "\(version)-\(build)-\(digest)")
                .appendingPathComponent("TerminalMac.app")
            try write(bundle: bundle, version: version, build: build, identifier: identifier)
            let executable = bundle.appendingPathComponent("Contents/MacOS/terminal-mac")
            try? FileManager.default.removeItem(at: launcher)
            try FileManager.default.createSymbolicLink(atPath: launcher.path, withDestinationPath: executable.path)
            return bundle
        }

        func write(bundle: URL, version: String, build: String, identifier: String) throws {
            let contents = bundle.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"),
                                                    withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": identifier,
                                        "CFBundleShortVersionString": version, "CFBundleVersion": build]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            try Data("terminal-mac \(version) \(build)".utf8)
                .write(to: contents.appendingPathComponent("MacOS/terminal-mac"))
        }

        /// One stable release as `releases/latest` answers it. The asset is the
        /// vendor's name for the version and build, and its address is the tag's.
        func release(marketing: String = "0.2.0", build: String = "6",
                     digest: String = String(repeating: "ab", count: 32),
                     tag: String? = nil, prerelease: Bool = false) -> Data {
            let tag = tag ?? "v\(marketing)-\(build)"
            let asset = "terminal-mac-\(marketing)-\(build)-macos-arm64.zip"
            return Data("""
                {"tag_name": "\(tag)", "prerelease": \(prerelease), "draft": false,
                 "assets": [{"name": "get.sh", "browser_download_url": "https://github.com/govijr/terminal-mac/releases/download/\(tag)/get.sh"},
                            {"name": "\(asset)", "digest": "sha256:\(digest)",
                             "browser_download_url": "https://github.com/govijr/terminal-mac/releases/download/\(tag)/\(asset)"}]}
                """.utf8)
        }

        func published(marketing: String = "0.2.0", build: String = "6",
                       digest: String = String(repeating: "ab", count: 32)) throws -> TerminalMacRelease.Published {
            try #require(TerminalMacRelease.parse(release(marketing: marketing, build: build, digest: digest)))
        }

        func check(marketing: String = "0.2.0", build: String = "6") -> TerminalMacCheck {
            let answer = try? published(marketing: marketing, build: build)
            return TerminalMacCheck(latest: { try #require(answer) })
        }

        /// A real zip of the archive's shape, with an `install.sh` that copies
        /// the bundle it ships and repoints the launcher (the vendor's own two
        /// effects; the rest is codesign and locking). Blocking.
        func archive(build: String = "6", leaves leavesBuild: String? = nil) async throws -> Data {
            let version = "0.2.0"
            let leaves = leavesBuild ?? build
            let stem = "terminal-mac-\(version)-\(build)-macos-arm64"
            let stage = root.appendingPathComponent("stage/\(stem)")
            let bundle = stage.appendingPathComponent("TerminalMac.app")
            try write(bundle: bundle, version: version, build: leaves, identifier: TerminalMacTests.bundleID)
            let script = """
                #!/bin/bash
                set -euo pipefail
                prefix="$HOME/.local"
                while [[ $# -gt 0 ]]; do
                  case "$1" in
                    --prefix) prefix="$2"; shift 2 ;;
                    *) shift ;;
                  esac
                done
                source_dir="${0%/*}"
                destination="$prefix/lib/terminal-mac/\(version)-\(leaves)-\(TerminalMacTests.digest)"
                mkdir -p "$prefix/bin" "$prefix/lib/terminal-mac"
                ditto "$source_dir/TerminalMac.app" "$destination/TerminalMac.app"
                ln -sfn "$destination/TerminalMac.app/Contents/MacOS/terminal-mac" "$prefix/bin/terminal-mac"
                """
            try Data(script.utf8).write(to: stage.appendingPathComponent("install.sh"))
            let zip = root.appendingPathComponent("\(stem).zip")
            let outcome = try await ChildProcess.run(
                "/usr/bin/ditto", ["-c", "-k", "--keepParent", stage.path, zip.path],
                environment: ["PATH": CLIToolCommandRunner.systemPath],
                standardOutput: .discard, standardError: .capture,
                deadline: ChildProcess.Deadline(terminateAfter: .seconds(60), killAfter: .seconds(65)),
                onCancel: .terminateChild)
            #expect(outcome.succeeded)
            return try Data(contentsOf: zip)
        }
    }

    // MARK: - The release

    @Test func parsesAStableRelease() throws {
        let box = try Sandbox()
        let json = box.release(digest: String(repeating: "ab", count: 32))
        let published = try #require(TerminalMacRelease.parse(json))
        #expect(published.marketing == "0.2.0")
        #expect(published.build == "6")
        #expect(published.tag == "v0.2.0-6")
        #expect(published.asset == "terminal-mac-0.2.0-6-macos-arm64.zip")
        #expect(published.digest == String(repeating: "ab", count: 32))
        #expect(published.zip.absoluteString
            == "https://github.com/govijr/terminal-mac/releases/download/v0.2.0-6/terminal-mac-0.2.0-6-macos-arm64.zip")
        #expect(published.displayVersion == "0.2.0 (6)")
    }

    /// Mutations: accept a bare `v0.2.0`, a prerelease, an asset without a
    /// digest, or an address outside the vendor's releases.
    @Test func rejectsWhatTheInstallerCouldNotUse() throws {
        let box = try Sandbox()
        let hex = String(repeating: "ab", count: 32)

        #expect(TerminalMacRelease.parse(box.release(digest: hex, tag: "v0.2.0")) == nil)
        #expect(TerminalMacRelease.parse(box.release(digest: hex, prerelease: true)) == nil)
        #expect(TerminalMacRelease.parse(Data(#"{"tag_name":"v0.2.0-6","assets":[]}"#.utf8)) == nil)
        #expect(TerminalMacRelease.parse(Data("""
            {"tag_name":"v0.2.0-6","draft":false,"prerelease":false,
             "assets":[{"name":"terminal-mac-0.2.0-6-macos-arm64.zip","digest":"sha256:short",
                        "browser_download_url":"https://github.com/govijr/terminal-mac/releases/download/v0.2.0-6/terminal-mac-0.2.0-6-macos-arm64.zip"}]}
            """.utf8)) == nil)
        #expect(TerminalMacRelease.parse(Data("""
            {"tag_name":"v0.2.0-6","draft":false,"prerelease":false,
             "assets":[{"name":"terminal-mac-0.2.0-6-macos-arm64.zip","digest":"sha256:\(hex)",
                        "browser_download_url":"https://example.com/terminal-mac-0.2.0-6-macos-arm64.zip"}]}
            """.utf8)) == nil)
    }

    @Test func tagNeedsBothMarketingAndBuild() {
        #expect(TerminalMacRelease.parseTag("v0.2.0-6")?.marketing == "0.2.0")
        #expect(TerminalMacRelease.parseTag("v0.2.0-6")?.build == "6")
        #expect(TerminalMacRelease.parseTag("0.2.0-6") == nil)
        #expect(TerminalMacRelease.parseTag("v0.2.0") == nil)
        #expect(TerminalMacRelease.parseTag("v0.2.0-0") == nil)
        #expect(TerminalMacRelease.parseTag("v0.2.0-6-rc1") == nil)
        #expect(TerminalMacRelease.digest("sha256:" + String(repeating: "AB", count: 32))
            == String(repeating: "ab", count: 32))
    }

    // MARK: - Finding it

    @Test func readsTheInstallerCopy() throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "6")
        let install = try #require(box.scanner.scan().first)
        #expect(install.version == "0.2.0")
        #expect(install.build == "6")
        #expect(install.displayVersion == "0.2.0 (6)")
        #expect(install.prefix == box.home.path + "/.local")
        #expect(install.problem == nil)
        #expect(install.linked)
        #expect(install.writable)
    }

    /// Mutations: accept a plain file, a link outside the installer's layout, a
    /// foreign bundle, a plist with no build, or a directory name that disagrees
    /// with the bundle.
    @Test func onlyTheInstallersLauncherIsItsOwn() throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "6")

        // A plain file where the launcher should be.
        try FileManager.default.removeItem(at: box.launcher)
        try Data("a person's own terminal-mac".utf8).write(to: box.launcher)
        #expect(box.scanner.scan().first?.problem == .notInstallerLayout)
        try FileManager.default.removeItem(at: box.launcher)

        // A link to a file outside the installer's layout.
        let outside = box.root.appendingPathComponent("elsewhere/terminal-mac")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("elsewhere".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(atPath: box.launcher.path,
                                                   withDestinationPath: outside.path)
        #expect(box.scanner.scan().first?.problem == .notInstallerLayout)

        // The installer's layout, but another product's bundle.
        try box.install("0.2.0", build: "6", identifier: "com.example.something-else")
        #expect(box.scanner.scan().first?.problem == .foreignBundle)

        // A directory name that says 5 while the bundle says 6.
        try box.install("0.2.0", build: "6", directory: "0.2.0-5-\(TerminalMacTests.digest)")
        #expect(box.scanner.scan().first?.problem == .notInstallerLayout)
    }

    /// `~/.local` can be a symlink (a home on a volume, a linked directory);
    /// the launcher is still the installer's. Mutation: compare the scanned
    /// path's spelling with the realpath-derived prefix.
    @Test func aSymlinkedLocalDirectoryStillFindsTheCopy() throws {
        let box = try Sandbox()
        let real = box.root.appendingPathComponent("real-local")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: box.home.appendingPathComponent(".local"))
        try FileManager.default.createSymbolicLink(
            atPath: box.home.appendingPathComponent(".local").path, withDestinationPath: real.path)
        try FileManager.default.createDirectory(at: box.bin, withIntermediateDirectories: true)
        try box.install("0.2.0", build: "6")
        let install = try #require(box.scanner.scan().first)
        #expect(install.problem == nil)
        #expect(install.build == "6")
    }

    @Test func aDanglingLauncherIsBroken() throws {
        let box = try Sandbox()
        try FileManager.default.createSymbolicLink(
            atPath: box.launcher.path, withDestinationPath: box.root.appendingPathComponent("gone").path)
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    @Test func nothingInstalledIsNothing() throws {
        let box = try Sandbox()
        #expect(box.scanner.scan().isEmpty)
    }

    // MARK: - The verdict

    /// Marketing first, then build: `0.2.0 (5)` → `0.2.0 (6)` is an update.
    /// Mutations: compare marketing only; get either ordering wrong.
    @Test func comparesMarketingThenBuild() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let install = try #require(box.scanner.scan().first)

        let update = await box.check(build: "6").status(of: install, busy: nil)
        #expect(update.state == .updateAvailable)
        #expect(update.installedVersion == "0.2.0 (5)")
        #expect(update.latestVersion == "0.2.0 (6)")
        #expect(update.oneClick != nil)

        let same = await box.check(build: "5").status(of: install, busy: nil)
        #expect(same.state == .upToDate)
        #expect(same.oneClick == nil)

        let ahead = await box.check(build: "4").status(of: install, busy: nil)
        #expect(ahead.state == .ahead)

        let nextMarketing = await box.check(marketing: "0.3.0", build: "1").status(of: install, busy: nil)
        #expect(nextMarketing.state == .updateAvailable)
    }

    @Test func theClickOffersThePinnedGetScript() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let install = try #require(box.scanner.scan().first)
        let status = await box.check(build: "6").status(of: install, busy: nil)
        #expect(status.oneClick?.display
            == "curl -fsSL https://github.com/govijr/terminal-mac/releases/download/v0.2.0-6/get.sh"
            + " | bash -s -- --prefix '\(box.home.path + "/.local")'")
    }

    /// A prefix can hold a space or a quote; the arguments are passed as one,
    /// and the line a person copies is quoted for a shell. Mutation: drop
    /// `shellLine`.
    @Test func quotesAPrefixWithSpaces() throws {
        let box = try Sandbox()
        let published = try box.published(build: "6")
        let command = TerminalMacCheck.installCommand(published: published,
                                                      prefix: "/Users/Test User/Sam's/.local")
        #expect(command.display.contains("--prefix '/Users/Test User/Sam'\\''s/.local'"))
    }

    /// Mutations: drop the busy or writable gate, or report a version that could
    /// not be read as an update.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let install = try #require(box.scanner.scan().first)

        let busy = await box.check(build: "6").status(of: install, busy: .lock)
        #expect(busy.state == .updateAvailable)
        #expect(busy.oneClick == nil)
        #expect(busy.withheld == .busy)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.library.path)
        let locked = try #require(box.scanner.scan().first)
        let readOnly = await box.check(build: "6").status(of: locked, busy: nil)
        #expect(readOnly.oneClick == nil)
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.manualCommand != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.library.path)
    }

    @Test func aBrokenLauncherIsReportedNotOffered() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        try FileManager.default.removeItem(at: box.launcher)
        try Data("not the installer's".utf8).write(to: box.launcher)
        let install = try #require(box.scanner.scan().first)
        let status = await box.check(build: "6").status(of: install, busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
    }

    @Test func channelFailuresAreNamed() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let install = try #require(box.scanner.scan().first)

        let limited = TerminalMacCheck(latest: { throw TerminalMacRelease.Failure.rateLimited(403) })
        let rate = await limited.status(of: install, busy: nil)
        #expect(rate.withheld == .rateLimited)

        let broken = TerminalMacCheck(latest: { throw TerminalMacRelease.Failure.unreadable })
        let unknown = await broken.status(of: install, busy: nil)
        #expect(unknown.withheld == .channelUnreadable)
    }

    // MARK: - Updating

    /// The archive's sha256 is GitHub's digest, then the archive's own installer
    /// runs with the prefix the copy lives under; the launcher must end up on
    /// exactly the release checked. Mutations: drop the digest gate; accept any
    /// newer version instead of the checked one; skip the argument.
    @Test func installsTheCheckedArchive() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let zip = try await box.archive(build: "6")
        let digest = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        let published = try box.published(build: "6", digest: digest)
        let status = await TerminalMacCheck(latest: { published }).status(
            of: try #require(box.scanner.scan().first), busy: nil)
        #expect(status.oneClick != nil)

        let updater = TerminalMacUpdater(
            busy: { _ in nil }, scanner: box.scanner,
            release: TerminalMacRelease(fetch: { _ in (box.release(build: "6", digest: digest), 200) }),
            download: { _ in zip }, environment: { ["KEEP": "1"] })
        let outcome = await updater.update(status)
        #expect(outcome == .updated(version: "0.2.0 (6)"))
        let after = try #require(box.scanner.scan().first)
        #expect(after.version == "0.2.0")
        #expect(after.build == "6")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.launcher.path)
            .contains("/0.2.0-6-"))
        // The vendor's installer leaves the old copy where it was.
        #expect(FileManager.default.fileExists(atPath: box.library
            .appendingPathComponent("0.2.0-5-\(Self.digest)").path))
    }

    /// The row offered 0.2.0 (6); by the click, latest is 0.2.0 (7). The
    /// updater must not install a release the row never showed. Mutation: use
    /// the fresh latest as the target.
    @Test func aMovedReleaseIsNotInstalled() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let offered = try box.published(build: "6")
        let status = await TerminalMacCheck(latest: { offered }).status(
            of: try #require(box.scanner.scan().first), busy: nil)

        final class Downloads: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            var value: Int { lock.withLock { count } }
            func bump() { lock.withLock { count += 1 } }
        }
        let downloads = Downloads()
        let updater = TerminalMacUpdater(
            busy: { _ in nil }, scanner: box.scanner,
            release: TerminalMacRelease(fetch: { _ in (box.release(build: "7"), 200) }),
            download: { _ in downloads.bump(); return Data() }, environment: { [:] })
        let outcome = await updater.update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(message.contains("is now 0.2.0 (7), not 0.2.0 (6)"))
        #expect(downloads.value == 0)
        #expect(box.scanner.scan().first?.build == "5")
    }

    @Test func refusesAnArchiveGitHubDidNotPublish() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        let zip = try await box.archive(build: "6")
        let published = try box.published(build: "6")
        let status = await TerminalMacCheck(latest: { published }).status(
            of: try #require(box.scanner.scan().first), busy: nil)

        let updater = TerminalMacUpdater(
            busy: { _ in nil }, scanner: box.scanner,
            release: TerminalMacRelease(fetch: { _ in (box.release(build: "6"), 200) }),
            download: { _ in zip }, environment: { [:] })
        let outcome = await updater.update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(message.contains("not the build GitHub published"))
        #expect(box.scanner.scan().first?.build == "5")
    }

    @Test func anInstallerThatLeavesAnotherVersionFails() async throws {
        let box = try Sandbox()
        try box.install("0.2.0", build: "5")
        // The archive claims 0.2.0 (6); its installer leaves 0.2.0 (5).
        let zip = try await box.archive(build: "6", leaves: "5")
        let digest = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        let published = try box.published(build: "6", digest: digest)
        let status = await TerminalMacCheck(latest: { published }).status(
            of: try #require(box.scanner.scan().first), busy: nil)
        let updater = TerminalMacUpdater(
            busy: { _ in nil }, scanner: box.scanner,
            release: TerminalMacRelease(fetch: { _ in (box.release(build: "6", digest: digest), 200) }),
            download: { _ in zip }, environment: { [:] })
        let outcome = await updater.update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(message.contains("is 0.2.0 (5), not terminal-mac 0.2.0 (6)"))
    }

    // MARK: - Busy

    @Test func theInstallersLockIsBusy() throws {
        let box = try Sandbox()
        let lock = box.library.appendingPathComponent(".install-lock")
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        let busy = TerminalMacActivity.busy(prefix: box.home.path + "/.local", processes: [])
        #expect(busy == .lock)
        #expect(TerminalMacActivity.busy(prefix: nil, processes: []) == nil)
    }
}
