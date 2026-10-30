import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Signed appcasts (`SURequireSignedFeed`, Sparkle 2.9+). An app that opts in
/// has its own Sparkle reject a feed whose `<!-- sparkle-signatures:` block does
/// not verify against `SUPublicEDKey`; our Sparkle route must too, or a feed host
/// could relabel channels, move `minimumAutoupdateVersion` or swap the notes of an
/// app whose vendor asked for exactly that to be impossible. On this Mac on
/// 2026-10-18 one app of 60 opted in: Shotbase.
@Suite struct SparkleSignedFeedTests {

    private static let feedBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><title>Subject</title>
        <item><title>2.0</title><sparkle:version>200</sparkle:version>
        <sparkle:shortVersionString>2.0</sparkle:shortVersionString>
        <enclosure url="https://example.com/Subject-2.0.zip" length="10" type="application/octet-stream" sparkle:edSignature="AAAA"/>
        </item></channel></rss>

        """

    /// The feed as `generate_appcast` writes it (`common_cli/Signing.swift`,
    /// `signAppcast`): the content, then a block signing every byte before it.
    private static func signed(_ content: String, with key: Curve25519.Signing.PrivateKey) throws -> Data {
        let data = Data(content.utf8)
        let signature = try key.signature(for: data).base64EncodedString()
        return data + Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(data.count)\n-->\n".utf8)
    }

    /// An installed copy on disk with `info` as its Info.plist — the check reads
    /// the plist fresh, as Sparkle does.
    private static func app(_ info: [String: Any], sparkle frameworks: [Framework] = []) throws -> InstalledApp {
        let bundle = TestScratch.directory("SparkleSignedFeedTests")
            .appendingPathComponent("Subject.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        for framework in frameworks { try framework.write(into: bundle) }
        return InstalledApp(
            name: "Subject", bundleID: "com.example.subject", shortVersion: "1.0",
            buildVersion: "100", path: bundle, isMASApp: false,
            sparkleFeedURL: URL(string: "https://signed-feed.test/\(UUID().uuidString)/appcast.xml"))
    }

    /// An Info.plist value for `SURequireSignedFeed`, in each type a vendor writes.
    enum Flag: Sendable, CustomTestStringConvertible {
        case absent, bool(Bool), number(Int), string(String)
        var value: Any? {
            switch self {
            case .absent: nil
            case .bool(let b): b
            case .number(let n): n
            case .string(let s): s
            }
        }
        var testDescription: String { "\(self)" }
    }

    /// A bundled `Sparkle.framework`, laid out as Sparkle ships it: the plist in
    /// `Versions/B/Resources`, reached through the `Versions/Current` and
    /// `Resources` symlinks.
    struct Framework: Sendable, CustomTestStringConvertible {
        enum Version: Sendable { case short(String), noVersionKey, noPlist }
        var version: Version
        /// Helium's layout: inside another framework rather than at the top.
        var nested = false

        static func sparkle(_ v: String, nested: Bool = false) -> Framework {
            Framework(version: .short(v), nested: nested)
        }

        func write(into bundle: URL) throws {
            let fm = FileManager.default
            let framework = nested
                ? bundle.appendingPathComponent("Contents/Frameworks/Host Framework.framework/Frameworks/Sparkle.framework")
                : bundle.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
            let resources = framework.appendingPathComponent("Versions/B/Resources")
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try fm.createSymbolicLink(
                atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "B")
            try fm.createSymbolicLink(
                atPath: framework.appendingPathComponent("Resources").path,
                withDestinationPath: "Versions/Current/Resources")
            var info: [String: Any] = ["CFBundleIdentifier": "org.sparkle-project.Sparkle"]
            switch version {
            case .noPlist: return
            case .noVersionKey: break
            case .short(let v): info["CFBundleShortVersionString"] = v
            }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: resources.appendingPathComponent("Info.plist"))
        }

        var testDescription: String { "\(version)\(nested ? " nested" : "")" }
    }

    private static func requiring(_ key: Curve25519.Signing.PrivateKey, flag: Flag = .bool(true)) -> [String: Any] {
        var info: [String: Any] = ["SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()]
        info["SURequireSignedFeed"] = flag.value
        return info
    }

    /// `body` must throw `expected`.
    private static func expectRefusal(
        _ expected: SparkleAppcastSource.SparkleError, sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            Issue.record("expected \(expected), got no error", sourceLocation: sourceLocation)
        } catch let error as SparkleAppcastSource.SparkleError {
            #expect(error.errorDescription == expected.errorDescription, sourceLocation: sourceLocation)
        } catch {
            Issue.record("expected \(expected), got \(error)", sourceLocation: sourceLocation)
        }
    }

    private static func source() -> SparkleAppcastSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedProtocol.self]
        return SparkleAppcastSource(session: URLSession(configuration: config))
    }

    // MARK: Valid

    /// Mutation: verify over the whole body instead of the bytes before the
    /// block → red (the block is not part of what was signed).
    @Test func aValidlySignedFeedIsOffered() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        FeedProtocol.serve(try Self.signed(Self.feedBody, with: key), at: app.sparkleFeedURL!)
        let remote = try await Self.source().latestVersion(for: app)
        #expect(remote?.version == "200")
        #expect(remote?.shortVersion == "2.0")
    }

    /// Only the signed bytes are handed on; the block and anything after it are not.
    @Test func onlyTheSignedBytesAreReturned() throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        let body = try Self.signed(Self.feedBody, with: key) + Data("<!-- trailing -->\n".utf8)
        let content = try SparkleAppcastSource.verifiedFeedContent(body, for: app)
        #expect(content == Data(Self.feedBody.utf8))
    }

    /// Bytes after the block are not signed, so they must not reach the parser:
    /// a second feed appended there offers nothing. Not a mutation guard for
    /// parsing `content` rather than `data` in `latestVersion`: measured
    /// 2026-10-18, that mutant passes too, because `XMLParser` stops at the second
    /// root element. Parsing `content` mirrors Sparkle and does not lean on that.
    @Test func aFeedAppendedAfterTheBlockIsNotRead() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        let appended = Self.feedBody
            .replacingOccurrences(of: "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n", with: "")
            .replacingOccurrences(of: "200", with: "300")
        FeedProtocol.serve(try Self.signed(Self.feedBody, with: key) + Data(appended.utf8), at: app.sparkleFeedURL!)
        let remote = try await Self.source().latestVersion(for: app)
        #expect(remote?.version == "200")
    }

    /// Sparkle's bool rules: a string `"YES"` (Helium spells its sibling key so)
    /// and a number both opt in.
    @Test(arguments: [Flag.bool(true), .string("YES"), .string("true"), .number(1)])
    func everySpellingOfTrueRequiresASignature(_ flag: Flag) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key, flag: flag))
        await Self.expectRefusal(.feedSignatureMissing) {
            _ = try SparkleAppcastSource.verifiedFeedContent(Data(Self.feedBody.utf8), for: app)
        }
    }

    // MARK: Missing

    /// Mutation: drop the `signature != nil` / nil-parts throw → red.
    @Test func aRequiredSignatureThatIsMissingRefusesTheFeed() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        FeedProtocol.serve(Data(Self.feedBody.utf8), at: app.sparkleFeedURL!)
        await Self.expectRefusal(.feedSignatureMissing) {
            _ = try await Self.source().latestVersion(for: app)
        }
        // Through the checker the row is `.error` — tried and failed, no offer.
        let result = await UpdateChecker(sources: [Self.source()]).check(app)
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)")
            return
        }
    }

    /// A block with no `edSignature:` line, or one never closed by `-->`, is no
    /// signature (Sparkle hands its verifier nil in both cases).
    @Test(arguments: [
        "<!-- sparkle-signatures:\nlength: 10\n-->\n",
        "<!-- sparkle-signatures:\nedSignature: AAAA\n",
    ])
    func anIncompleteBlockIsAMissingSignature(_ block: String) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        await Self.expectRefusal(.feedSignatureMissing) {
            _ = try SparkleAppcastSource.verifiedFeedContent(Data((Self.feedBody + block).utf8), for: app)
        }
    }

    // MARK: Tampered

    /// One byte of the signed content changed → refused. Mutation: drop the
    /// `verifyEdSignature` call (return `content` unverified) → red.
    @Test func oneFlippedByteRefusesTheFeed() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        var body = try Self.signed(Self.feedBody, with: key)
        let at = body.range(of: Data("200".utf8))!.lowerBound
        body[at] = UInt8(ascii: "9")
        FeedProtocol.serve(body, at: app.sparkleFeedURL!)
        await Self.expectRefusal(.feedSignatureInvalid) {
            _ = try await Self.source().latestVersion(for: app)
        }
    }

    /// Signed, but by someone else's key.
    @Test func aSignatureByAnotherKeyRefusesTheFeed() async throws {
        let app = try Self.app(Self.requiring(Curve25519.Signing.PrivateKey()))
        let body = try Self.signed(Self.feedBody, with: Curve25519.Signing.PrivateKey())
        await Self.expectRefusal(.feedSignatureInvalid) {
            _ = try SparkleAppcastSource.verifiedFeedContent(body, for: app)
        }
    }

    /// The LAST block counts (Sparkle searches backwards): a valid block followed
    /// by a forged one is refused.
    @Test func aLaterForgedBlockWins() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        let body = try Self.signed(Self.feedBody, with: key)
            + Data("<!-- sparkle-signatures:\nedSignature: AAAA\n-->\n".utf8)
        await Self.expectRefusal(.feedSignatureInvalid) {
            _ = try SparkleAppcastSource.verifiedFeedContent(body, for: app)
        }
    }

    /// Two `edSignature:` lines in one block: the last one counts, as in
    /// `SPUExtractAppcastContent`. A line whose key is followed by a combining
    /// mark still counts — NSString matches the prefix in UTF-16 units. Mutation:
    /// first line wins, or Swift's character-wise `hasPrefix` → red.
    @Test(arguments: ["", "\u{0301}", "\u{200D}"])
    func theLastSignatureLineWins(_ afterColon: String) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key))
        let content = Data(Self.feedBody.utf8)
        let good = try key.signature(for: content).base64EncodedString()
        let goodThenBad = content + Data(
            "<!-- sparkle-signatures:\nedSignature: \(good)\nedSignature:\(afterColon)AAAA\n-->\n".utf8)
        await Self.expectRefusal(.feedSignatureInvalid) {
            _ = try SparkleAppcastSource.verifiedFeedContent(goodThenBad, for: app)
        }
        let badThenGood = content + Data(
            "<!-- sparkle-signatures:\nedSignature:\(afterColon)AAAA\nedSignature: \(good)\n-->\n".utf8)
        #expect(try SparkleAppcastSource.verifiedFeedContent(badThenGood, for: app) == content)
    }

    // MARK: Not required / key absent

    /// No `SUPublicEDKey`: Sparkle could not start for this app, so there is no
    /// vendor check to mirror and the feed is read as before. Mutation: require
    /// the key's presence no longer (verify with an empty key) → red.
    @Test func keyAbsentReadsTheUnsignedFeedAsBefore() async throws {
        let app = try Self.app(["SURequireSignedFeed": true])
        FeedProtocol.serve(Data(Self.feedBody.utf8), at: app.sparkleFeedURL!)
        let remote = try await Self.source().latestVersion(for: app)
        #expect(remote?.version == "200")
    }

    /// Not opted in (absent, false, `"NO"`): an unsigned feed is read as before,
    /// and a signed one is passed through whole. Mutation: drop the
    /// `requiresSignedFeed` guard → red.
    @Test(arguments: [Flag.absent, .bool(false), .string("NO"), .number(0)])
    func anAppThatDoesNotOptInIsUnchanged(_ flag: Flag) throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key, flag: flag))
        let unsigned = Data(Self.feedBody.utf8)
        #expect(try SparkleAppcastSource.verifiedFeedContent(unsigned, for: app) == unsigned)
        let signed = try Self.signed(Self.feedBody, with: key)
        #expect(try SparkleAppcastSource.verifiedFeedContent(signed, for: app) == signed)
    }

    // MARK: Bundled Sparkle older than 2.9

    /// Sparkle before 2.9 has no feed signing at all (tag 2.8.1 has no
    /// `SURequireSignedFeed` anywhere), so its updater reads the feed unchecked
    /// and so do we. Mutation: drop the `predatesSignedFeeds` guard → red.
    @Test(arguments: [
        [Framework.sparkle("2.8.1")],
        [.sparkle("1.27.3")],
        [.sparkle("2.8.1"), .sparkle("2.6.4", nested: true)],
    ])
    func anAppOnSparkleOlderThan29IsNotChecked(_ frameworks: [Framework]) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key), sparkle: frameworks)
        FeedProtocol.serve(Data(Self.feedBody.utf8), at: app.sparkleFeedURL!)
        let remote = try await Self.source().latestVersion(for: app)
        #expect(remote?.version == "200")
    }

    /// 2.9 and later, the 2.9.0 betas included (`SPUExtractSignedFeed.m` is in
    /// 2.9.0-beta.1), are checked; so is a mix where any one framework is 2.9+.
    /// Mutation: compare against "2.9" with `VersionComparator` (a beta sorts
    /// below it), or skip when ANY framework is old → red.
    @Test(arguments: [
        [Framework.sparkle("2.9.0-beta.1")],
        [.sparkle("2.9.0")],
        [.sparkle("2.9.5")],
        [.sparkle("2.10.0")],
        [.sparkle("3.0")],
        [.sparkle("2.8.1"), .sparkle("2.9.5", nested: true)],
        [.sparkle("2.9.5", nested: true)],
    ])
    func anAppOnSparkle29OrLaterIsChecked(_ frameworks: [Framework]) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key), sparkle: frameworks)
        await Self.expectRefusal(.feedSignatureMissing) {
            _ = try SparkleAppcastSource.verifiedFeedContent(Data(Self.feedBody.utf8), for: app)
        }
    }

    /// No framework found, or a version that cannot be read, is not evidence the
    /// app's updater skips the check: checked. Mutation: treat an unreadable
    /// version as old → red.
    @Test(arguments: [
        [Framework](),
        [Framework(version: .noPlist)],
        [Framework(version: .noVersionKey)],
        [.sparkle("")],
        [.sparkle("2")],
        [.sparkle("beta")],
        [.sparkle("2.8.1"), Framework(version: .noVersionKey, nested: true)],
    ])
    func anUnreadableSparkleVersionIsChecked(_ frameworks: [Framework]) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let app = try Self.app(Self.requiring(key), sparkle: frameworks)
        await Self.expectRefusal(.feedSignatureMissing) {
            _ = try SparkleAppcastSource.verifiedFeedContent(Data(Self.feedBody.utf8), for: app)
        }
    }

    // MARK: Fixture server

    /// Serves a body per feed URL; each test uses its own URL, so parallel tests
    /// do not see each other's bodies.
    private final class FeedProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) private static var bodies: [URL: Data] = [:]
        private static let lock = NSLock()

        static func serve(_ body: Data, at url: URL) {
            lock.withLock { bodies[url] = body }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let url = request.url!
            let body = Self.lock.withLock { Self.bodies[url] }
            let response = HTTPURLResponse(
                url: url, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
