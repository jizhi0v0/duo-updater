import Foundation
import Testing
@testable import DuoKit
@testable import DuoUpdaterCore

/// `duo verify --mygo`: the verdicts, offline (`Verify.classifyMyGo`), and the
/// catalog the sweep walks.
struct MyGoVerifyTests {

    static let archive = URL(string: "https://github.com/acme/app/releases/download/v1.2.0/app-1.2.0-darwin-arm64.tar.gz")!
    static let patch = URL(string: "https://github.com/acme/app/releases/download/v1.2.0/app-1.1.0-to-1.2.0-darwin-arm64.delta")!

    static func read(
        enclosure: SparkleEnclosureAnswer? = .answered(status: 206, bytesRead: 1),
        key: MyGoKeyCheck? = .verified(file: patch, bytes: 1301845)
    ) -> MyGoObservation {
        MyGoObservation(resolve: .read(version: "1.2.0", archive: archive), enclosure: enclosure, key: key)
    }

    @Test func aHealthyFeedIsOK() {
        let verdict = Verify.classifyMyGo(Self.read())
        #expect(verdict.status == .ok)
        #expect(verdict.version == "1.2.0")
        #expect(verdict.warnings.isEmpty)
    }

    /// The one failure nothing else would notice. Mutation: treat `.invalid`
    /// like `.verified` → a rotated key reads as healthy every night.
    @Test func aKeyThatNoLongerVerifiesIsBroken() {
        let verdict = Verify.classifyMyGo(Self.read(key: .invalid(file: Self.patch)))
        #expect(verdict.status == .broken)
        #expect(verdict.warnings.last?.hasPrefix("mygoKeyMismatch — ") == true)
        let unsigned = Verify.classifyMyGo(Self.read(key: .noSignedFile))
        #expect(unsigned.status == .broken)
        #expect(unsigned.warnings.last?.hasPrefix("mygoNothingSigned — ") == true)
    }

    /// The vendor's doing is broken; the network's is infra until the baseline
    /// says otherwise.
    @Test func aFeedThatDoesNotResolveIsBrokenOnlyWhenTheVendorSaidSo() {
        for failure: MyGoUpdateSource.Failure in [
            .manifestIncomplete, .manifestUnreadable, .noTaggedRelease(prefix: "v"), .taggedFeedMalformed,
        ] {
            let verdict = Verify.classifyMyGo(MyGoObservation(resolve: .failed(failure, detail: "x")))
            #expect(verdict.status == .broken, "\(failure)")
            #expect(verdict.warnings.first?.hasPrefix("mygoFeedUnusable — ") == true)
        }
        for failure: MyGoUpdateSource.Failure? in [.manifestStatus(503), .manifestStatus(404), .releasesStatus(403), nil] {
            let verdict = Verify.classifyMyGo(MyGoObservation(resolve: .failed(failure, detail: "x")))
            #expect(verdict.status == .infra, "\(String(describing: failure))")
            #expect(verdict.warnings.first?.hasPrefix("mygoFeedUnreachable — ") == true)
        }
    }

    /// The archive refused is actionable; a moment's trouble, with it or with
    /// the key check's download, is not.
    @Test func theArchiveAndTheKeyCheckAnswerLikeTheOtherSweeps() {
        #expect(Verify.classifyMyGo(Self.read(enclosure: .answered(status: 404, bytesRead: 0))).status == .warn)
        #expect(Verify.classifyMyGo(Self.read(enclosure: .answered(status: 503, bytesRead: 0))).status == .ok)
        #expect(Verify.classifyMyGo(Self.read(enclosure: .noAnswer(detail: "timeout"))).status == .ok)
        let unreachable = Verify.classifyMyGo(Self.read(key: .unreachable(file: Self.patch, detail: "timeout")))
        #expect(unreachable.status == .ok)
        #expect(!unreachable.warnings.isEmpty)
        #expect(Verify.classifyMyGo(Self.read(key: .tooLarge(file: Self.archive, bytes: 1 << 30))).status == .warn)
    }

    /// Every entry is a feed and key the sweep can use, with an audit behind it.
    @Test func theCatalogHoldsWhatTheSourceWouldReadOutOfABinary() throws {
        let entries = MyGoFeedCatalog.entries
        #expect(!entries.isEmpty)
        #expect(Set(entries.map(\.recipeID)).count == entries.count)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for entry in entries {
            #expect(Data(base64Encoded: entry.publicKey)?.count == 32, "\(entry.bundleID)")
            #expect(entry.feed.hasPrefix("https://"), "\(entry.bundleID)")
            #expect(entry.feed.contains("/update-darwin-") && entry.feed.hasSuffix(".json"), "\(entry.bundleID)")
            let audit = root.appendingPathComponent(
                "docs/app-audits/\(entry.bundleID.replacingOccurrences(of: ".", with: "-")).md")
            #expect(FileManager.default.fileExists(atPath: audit.path), "no audit for \(entry.bundleID)")
        }
        // Swept, and kept in the baseline.
        #expect(Set(entries.map(\.recipeID)).isSubset(of: Verify.liveRecipeIDs()))
        #expect(Registry.swept.contains(.myGo))
    }
}
