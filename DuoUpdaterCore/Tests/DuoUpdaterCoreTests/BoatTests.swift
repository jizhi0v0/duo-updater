import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// The Boat CLI: reading the install off the disk without running it, the
/// channel and hash Boat publishes, and the verdict built from them. Nothing here
/// reaches the network or runs a Boat build: the fetches are injected, and an
/// "executable" is bytes written to a temporary HOME.
@Suite struct BoatTests {

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var boat: URL { home.appendingPathComponent(".ascii/bin/boat") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("boat-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: boat.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A Mach-O arm64 header, then filler with the version literal in it, as
        /// the real binary carries it (`…/api/boat/cli/version?platform=…&current=1.0.38`).
        static func binary(version: String?, cpu: [UInt8] = [0x0C, 0x00, 0x00, 0x01]) -> Data {
            var data = Data([0xCF, 0xFA, 0xED, 0xFE] + cpu)
            data.append(Data(repeating: 0, count: 64))
            if let version { data.append(Data("/api/boat/cli/version?platform=\u{0}&current=\(version)\u{0}".utf8)) }
            data.append(Data(repeating: 0xAB, count: 64))
            return data
        }

        func write(version: String?) throws {
            try Self.binary(version: version).write(to: boat)
        }

        func config(_ json: String) throws {
            let url = BoatSettings.location(home: home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url)
        }

        var scanner: BoatScanner {
            BoatScanner(home: home, checkSignature: { _ in .adHoc }, isQuarantined: { _ in false })
        }

        var sha256: String {
            let data = (try? Data(contentsOf: boat)) ?? Data()
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    // MARK: - Reading the file

    @Test func versionIsTheOneCompiledInLiteral() {
        #expect(BoatScanner.compiledVersion(in: Sandbox.binary(version: "1.0.38")) == "1.0.38")
        #expect(BoatScanner.compiledVersion(in: Sandbox.binary(version: "1.0.34-staging1")) == "1.0.34-staging1")
        #expect(BoatScanner.compiledVersion(in: Sandbox.binary(version: nil)) == nil)
        // Two that disagree: not a build this code knows how to read.
        var two = Sandbox.binary(version: "1.0.38")
        two.append(Data("&current=1.0.37 ".utf8))
        #expect(BoatScanner.compiledVersion(in: two) == nil)
        // The same one twice is still one version.
        var same = Sandbox.binary(version: "1.0.38")
        same.append(Data("&current=1.0.38\u{0}".utf8))
        #expect(BoatScanner.compiledVersion(in: same) == "1.0.38")
        // The next literal starts right after the number: it is not part of it.
        #expect(BoatScanner.compiledVersion(in: Data("&current=1.0.38Docs: https".utf8)) == "1.0.38")
        #expect(BoatScanner.compiledVersion(in: Data("&current=1.0.34-staging1".utf8)) == "1.0.34-staging1")
        // Something after the marker that is not a version.
        #expect(BoatScanner.compiledVersion(in: Data("&current={}".utf8)) == nil)
    }

    @Test func architectureFromTheMachOHeader() {
        #expect(BoatScanner.architecture(Sandbox.binary(version: nil)) == "arm64")
        #expect(BoatScanner.architecture(Sandbox.binary(version: nil, cpu: [0x07, 0x00, 0x00, 0x01])) == "x64")
        #expect(BoatScanner.architecture(Data("#!/bin/sh\n".utf8)) == nil)
    }

    @Test func versionShapes() {
        for good in ["1.0.38", "1.0.0", "1.0.34-staging1", "1.0.6-anicet1", "1.0.10-amsterdam1"] {
            #expect(BoatRelease.isVersion(good), "\(good)")
        }
        for bad in ["", "1.0", "1.0.38-", "1.0.38-a/b", "1.0.38?x=1", "v1.0.38", "1.0.38-staging.1", "1..38"] {
            #expect(!BoatRelease.isVersion(bad), "\(bad)")
        }
    }

    /// The real config also carries the session token; only the two keys are read.
    @Test func settingsFromBoatsOwnConfig() throws {
        let fresh = #"{"api_url":null,"token":"ZZFixture-token","channel":null,"last_update_check":1791104898}"#
        #expect(BoatSettings.parse(Data(fresh.utf8)) == BoatSettings(channel: "prod", customAPI: nil))
        #expect(BoatSettings.parse(Data(#"{"channel":"staging"}"#.utf8)).channel == "staging")
        #expect(BoatSettings.parse(Data(#"{"api_url":"https://boat.dev/"}"#.utf8)).customAPI == nil)
        #expect(BoatSettings.parse(Data(#"{"api_url":"https://staging.ascii.dev"}"#.utf8)).customAPI
                == "https://staging.ascii.dev")
        #expect(BoatSettings.parse(Data("not json".utf8)) == BoatSettings())

        let box = try Sandbox()
        #expect(BoatSettings.read(home: box.home) == BoatSettings())
        try box.config(#"{"channel":"staging","api_url":null}"#)
        #expect(BoatSettings.read(home: box.home).channel == "staging")
    }

    /// The installer's `~/.config/ascii/boat/config.json` is not what the macOS
    /// binary reads, so it decides nothing.
    @Test func installersXDGConfigIsNotRead() throws {
        let box = try Sandbox()
        let xdg = box.home.appendingPathComponent(".config/ascii/boat/config.json")
        try FileManager.default.createDirectory(at: xdg.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"api_url":"https://elsewhere.example","channel":"staging"}"#.utf8).write(to: xdg)
        #expect(BoatSettings.read(home: box.home) == BoatSettings())
    }

    @Test func scannerFindsTheInstallersFile() async throws {
        let box = try Sandbox()
        #expect(await box.scanner.scan().isEmpty)

        try Data().write(to: box.boat)
        #expect(await box.scanner.scan().first?.problem == .executableMissing)

        try box.write(version: nil)
        #expect(await box.scanner.scan().first?.problem == .versionUnreadable)

        try box.write(version: "1.0.37")
        try box.config(#"{"channel":"staging"}"#)
        let install = try #require(await box.scanner.scan().first)
        #expect(install.path == box.boat.path)
        #expect(install.version == "1.0.37")
        #expect(install.platform == "darwin-arm64")
        #expect(install.signature == .adHoc)
        #expect(install.settings.channel == "staging")
        #expect(install.problem == nil)
    }

    @Test func sightingChangesWithWhatTheVerdictRestsOn() {
        let base = BoatProvider.sighting(BoatInstall(path: "/h/.ascii/bin/boat", version: "1.0.38"))
        let staging = BoatProvider.sighting(BoatInstall(
            path: "/h/.ascii/bin/boat", version: "1.0.38", settings: BoatSettings(channel: "staging")))
        let quarantined = BoatProvider.sighting(BoatInstall(path: "/h/.ascii/bin/boat", version: "1.0.38", quarantined: true))
        #expect(base.kind == .boat)
        #expect(base != staging)
        #expect(base != quarantined)
    }

    // MARK: - What Boat publishes

    final class Fetched: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URL] = []
        func add(_ url: URL) { lock.withLock { items.append(url) } }
        var all: [URL] { lock.withLock { items } }
    }

    /// The answer measured on 2026-10-04, and the server's error for a channel
    /// with no release.
    @Test func latestFromTheVersionEndpoint() async throws {
        let fetched = Fetched()
        let release = BoatRelease(fetch: { url in
            fetched.add(url)
            let body = #"{"requestedChannel":"prod","channel":"prod","platform":"darwin-arm64","current":"","version":"1.0.38","tag":"boat-cli-v1.0.38","updateAvailable":false,"downloadUrl":"https://github.com/ariana-dot-dev/agent-server/releases/download/boat-cli-v1.0.38/boat-darwin-arm64"}"#
            return (Data(body.utf8), 200)
        })
        #expect(try await release.latest(channel: "prod", platform: "darwin-arm64") == .init(version: "1.0.38"))
        #expect(fetched.all.map(\.absoluteString)
                == ["https://boat.dev/api/boat/cli/version?platform=darwin-arm64&channel=prod"])

        let none = BoatRelease(fetch: { _ in
            (Data(#"{"requestedChannel":"beta","channel":"beta","platform":"darwin-arm64","current":"","error":"No Boat CLI release found for channel beta"}"#.utf8), 404)
        })
        await #expect(throws: BoatRelease.Failure.server("No Boat CLI release found for channel beta")) {
            try await none.latest(channel: "beta", platform: "darwin-arm64")
        }
        let odd = BoatRelease(fetch: { _ in (Data(#"{"version":"1.0.38/../x"}"#.utf8), 200) })
        await #expect(throws: BoatRelease.Failure.unreadable) {
            try await odd.latest(channel: "prod", platform: "darwin-arm64")
        }
        let down = BoatRelease(fetch: { _ in (Data("<html>".utf8), 502) })
        await #expect(throws: BoatRelease.Failure.http(502)) {
            try await down.latest(channel: "prod", platform: "darwin-arm64")
        }
    }

    /// 1.0.38's `SHA256SUMS`, verbatim.
    static let sums = """
        64ed164b6b566dcb0520ae685f42c8a5ff6d7b00db00ceb80d6a7da6b1d9b0c9  boat-darwin-arm64
        dc558466c5d55e833011f669776753abcefc6598e8dd64614e3521e1d5198fd6  boat-darwin-x64
        24d5571d9d48a8a472b56e3f9ab5a69542855b98af0cad03418ea2c009fbf40f  boat-linux-arm64
        755ca53ef460897d58f79cd094fe334b22160bd76168212d100e9474e99a1f8c  boat-linux-x64
        06f7088639c3a1724b217803a34a88a7153cca6b2f06286c850f6ecc34c81bad  boat-windows-x64.exe

        """

    @Test func digestFromTheReleasesSHA256SUMS() async throws {
        #expect(BoatRelease.digest(in: Self.sums, asset: "boat-darwin-arm64")
                == "64ed164b6b566dcb0520ae685f42c8a5ff6d7b00db00ceb80d6a7da6b1d9b0c9")
        #expect(BoatRelease.digest(in: Self.sums, asset: "boat-darwin-x64")
                == "dc558466c5d55e833011f669776753abcefc6598e8dd64614e3521e1d5198fd6")
        #expect(BoatRelease.digest(in: Self.sums, asset: "boat-windows-x64") == nil)
        #expect(BoatRelease.digest(in: "\(String(repeating: "a", count: 64)) *boat-darwin-arm64\n", asset: "boat-darwin-arm64")
                == String(repeating: "a", count: 64))

        let fetched = Fetched()
        let release = BoatRelease(fetch: { url in fetched.add(url); return (Data(Self.sums.utf8), 200) })
        #expect(try await release.publishedDigest(version: "1.0.38", platform: "darwin-arm64").hasPrefix("64ed164b"))
        #expect(fetched.all.map(\.absoluteString)
                == ["https://github.com/ariana-dot-dev/agent-server/releases/download/boat-cli-v1.0.38/SHA256SUMS"])
        await #expect(throws: BoatRelease.Failure.noDigest) {
            try await release.publishedDigest(version: "1.0.38", platform: "darwin-riscv")
        }
        await #expect(throws: BoatRelease.Failure.unreadable) {
            try await release.publishedDigest(version: "../../x", platform: "darwin-arm64")
        }
    }

    // MARK: - The verdict

    static func check(
        _ latest: String = "1.0.38", digest: String? = "match", hash: String = "match",
        asked: Fetched? = nil
    ) -> BoatCheck {
        BoatCheck(
            latest: { channel, platform in
                asked?.add(URL(string: "latest:\(channel):\(platform)")!)
                if latest == "fail" { throw BoatRelease.Failure.server("No Boat CLI release found for channel \(channel)") }
                return latest
            },
            digest: { version, platform in
                asked?.add(URL(string: "digest:\(version):\(platform)")!)
                guard let digest else { throw BoatRelease.Failure.http(404) }
                return digest == "match" ? String(repeating: "a", count: 64) : digest
            },
            hash: { _ in hash == "match" ? String(repeating: "a", count: 64) : hash })
    }

    static func install(
        version: String? = "1.0.37", settings: BoatSettings = BoatSettings(), quarantined: Bool = false,
        problem: BoatInstall.Problem? = nil
    ) -> BoatInstall {
        BoatInstall(path: "/h/.ascii/bin/boat", version: version, quarantined: quarantined, settings: settings,
                    problem: problem)
    }

    @Test func publishedBuildBehindItsChannelGetsSelfUpdate() async {
        let asked = Fetched()
        let status = await Self.check(asked: asked).status(of: Self.install(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "1.0.38")
        #expect(status.channel == "prod")
        #expect(status.oneClick == CLIToolCommand(executable: "/h/.ascii/bin/boat", arguments: ["self-update"], pathPrefix: nil))
        // The hash looked up is the INSTALLED version's, not the channel's.
        #expect(asked.all.map(\.absoluteString) == ["latest:prod:darwin-arm64", "digest:1.0.37:darwin-arm64"])
    }

    /// Kills: offering the click on a file whose hash is not the published one,
    /// or treating an unreadable SHA256SUMS as a match.
    @Test func noClickUnlessTheFileIsThePublishedBuild() async {
        let differs = await Self.check(hash: String(repeating: "b", count: 64)).status(of: Self.install(), busy: nil)
        #expect(differs.state == .updateAvailable)
        #expect(differs.oneClick == nil)
        #expect(differs.withheld == .unverified)

        let unreadable = await Self.check(digest: nil).status(of: Self.install(), busy: nil)
        #expect(unreadable.oneClick == nil)
        #expect(unreadable.withheld == .channelUnreadable)

        let quarantined = await Self.check().status(of: Self.install(quarantined: true), busy: nil)
        #expect(quarantined.oneClick == nil)
        #expect(quarantined.withheld == .unverified)
    }

    /// The hash is asked only when a click would be offered.
    @Test func upToDateAndAheadAskNoHash() async {
        let asked = Fetched()
        let same = await Self.check(asked: asked).status(of: Self.install(version: "1.0.38"), busy: nil)
        #expect(same.state == .upToDate)
        #expect(same.oneClick == nil)
        #expect(asked.all.count == 1)
    }

    /// The server says "update available" for anything that differs, so
    /// `self-update` would DOWNGRADE a copy newer than its channel. Kills: using
    /// the server's flag, or offering a click on `.ahead`.
    @Test func newerThanTheChannelIsAheadNotADowngrade() async {
        let staging = await Self.check("1.0.34-staging1")
            .status(of: Self.install(version: "1.0.38", settings: BoatSettings(channel: "staging")), busy: nil)
        #expect(staging.state == .ahead)
        #expect(staging.oneClick == nil)
        #expect(staging.channel == "staging")

        let newer = await Self.check("1.0.38").status(of: Self.install(version: "1.0.39"), busy: nil)
        #expect(newer.state == .ahead)
        #expect(newer.oneClick == nil)
    }

    @Test func withheldVerdicts() async {
        let busy = await Self.check().status(of: Self.install(), busy: .selfUpdate(42))
        #expect(busy.state == .updateAvailable)
        #expect(busy.withheld == .busy)
        #expect(busy.oneClick == nil)

        let channel = await Self.check("fail").status(of: Self.install(settings: BoatSettings(channel: "beta")), busy: nil)
        #expect(channel.state == .unknown)
        #expect(channel.withheld == .channelUnreadable)
        #expect(channel.note?.contains("No Boat CLI release found for channel beta") == true)

        let asked = Fetched()
        let custom = await Self.check(asked: asked).status(
            of: Self.install(settings: BoatSettings(customAPI: "https://staging.ascii.dev")), busy: nil)
        #expect(custom.withheld == .unsupportedInstaller)
        #expect(asked.all.isEmpty)

        let broken = await Self.check().status(of: Self.install(version: nil, problem: .executableMissing), busy: nil)
        #expect(broken.withheld == .broken)
        let unreadable = await Self.check().status(of: Self.install(version: nil, problem: .versionUnreadable), busy: nil)
        #expect(unreadable.withheld == .versionUnreadable)
    }

    @Test func activitySeesSelfUpdateOnly() {
        func process(_ pid: pid_t, _ args: String...) -> ClaudeCodeActivity.Process {
            ClaudeCodeActivity.Process(pid: pid, arguments: args)
        }
        #expect(BoatActivity.busy(processes: [process(1, "/h/.ascii/bin/boat", "self-update")]) == .selfUpdate(1))
        #expect(BoatActivity.busy(processes: [process(2, "boat", "--json", "self-update")]) == .selfUpdate(2))
        #expect(BoatActivity.busy(processes: [process(3, "/h/.ascii/bin/boat", "ssh", "abc")]) == nil)
        #expect(BoatActivity.busy(processes: [process(4, "/x/notboat", "self-update")]) == nil)
    }

    @Test func reportHasOneRowPerInstallAndNoProcessesWithoutOne() async {
        let asked = Fetched()
        let empty = await BoatProvider.report(installs: [], processes: { asked.add(URL(string: "ps:")!); return [] },
                                              check: Self.check())
        #expect(empty.statuses.isEmpty)
        #expect(asked.all.isEmpty)
        let one = await BoatProvider.report(installs: [Self.install()], processes: { [] }, check: Self.check())
        #expect(one.kind == .boat)
        #expect(one.context == .boat)
        #expect(one.statuses.map(\.path) == ["/h/.ascii/bin/boat"])
    }

    @Test func noReleaseNotes() async throws {
        let notes = try await BoatProvider().releaseNotes(
            for: await Self.check().status(of: Self.install(), busy: nil), force: false)
        #expect(notes.entries.isEmpty)
    }
}
