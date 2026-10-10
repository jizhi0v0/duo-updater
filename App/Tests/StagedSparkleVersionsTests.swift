import Darwin
import Foundation
import Testing

/// The root helper's read of a Sparkle staging (`App/Helper/StagedSparkleVersions.swift`,
/// #588), run as this user against invented trees in a temporary directory. The
/// production prefix (`/var/root/Library/Caches`) is never read here: every case
/// passes its own `cachesDirectory`, and the one case that goes through
/// `HelperService` uses an identifier the allow-list refuses before any path
/// exists.
///
/// Each case names the mutation it was seen to fail under.
@Suite(.timeLimit(.minutes(1)))
struct StagedSparkleVersionsTests {

    static let bundleID = "com.zzfixture.staged"

    // MARK: allow-list

    /// Mutations, one at a time: drop the length cap (the 256-byte id passes);
    /// drop `!hasPrefix(".")` (`.zzfixture` passes); drop `!contains("..")`
    /// (`com..zzfixture` passes); widen the alphabet to anything (`/`, `_`, space,
    /// NUL and non-ASCII pass).
    @Test func theAllowListRefusesEverythingButAPlainIdentifier() {
        let refused = [
            "", "..", "../ZZFixture", "../../etc", "com/zzfixture", "/etc", ".zzfixture",
            "com..zzfixture", "com.zz_fixture", "com.zz fixture", "com.zzfixture.ü",
            "com.zz\u{0}fixture", "com.zzfixture\n", String(repeating: "a", count: 256),
        ]
        for id in refused {
            #expect(!StagedSparkleVersions.isAllowedBundleID(id), "\(id.debugDescription) must be refused")
        }
        let allowed = [Self.bundleID, "com.zzfixture.app", "ZZ-Fixture.9", String(repeating: "a", count: 255)]
        for id in allowed {
            #expect(StagedSparkleVersions.isAllowedBundleID(id), "\(id.debugDescription) must be allowed")
        }
    }

    /// A refused identifier never reaches the filesystem, even where the path it
    /// spells exists and holds a staging whose plist claims that very identifier
    /// (so the identifier match, a third layer, cannot be what stops it).
    ///
    /// Mutation: drop the `isAllowedBundleID` guard in `read` AND the
    /// `contains("/")` check in `openDirectory` — the escape then resolves. (Either
    /// alone still refuses it: they are two layers.)
    @Test func aRefusedIdentifierReadsNothing() throws {
        try withCaches { caches in
            try stageTwoLevel(in: caches, identifier: "../" + Self.bundleID)
            let nested = caches.appendingPathComponent("ZZFixture-inner")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            #expect(StagedSparkleVersions.read(
                bundleID: "../" + Self.bundleID, cachesDirectory: nested.path) == nil)
        }
    }

    // MARK: cache folder

    /// Sparkle ≤ 2.9.2 uses the identifier verbatim; 2.9.3–2.9.6 append
    /// `.sparkle` after `.app`/`.APP`; 2.10 after eight suffixes, case-insensitively.
    ///
    /// Mutations: drop `lowercased()` (`.App` loses its second spelling); cut the
    /// list down to `.app` (`.xpc` loses it).
    @Test func suffixedIdentifiersGetBothSpellings() {
        #expect(StagedSparkleVersions.cacheFolderNames(for: Self.bundleID) == [Self.bundleID])
        #expect(StagedSparkleVersions.cacheFolderNames(for: "com.zzfixture.apple") == ["com.zzfixture.apple"])
        for id in ["com.zzfixture.app", "com.zzfixture.APP", "com.zzfixture.App",
                   "com.zzfixture.xpc", "com.zzfixture.kext", "com.zzfixture.Service"] {
            #expect(StagedSparkleVersions.cacheFolderNames(for: id) == [id, id + ".sparkle"], "\(id)")
        }
    }

    /// Mutation: return `[bundleID]` from `cacheFolderNames` — the renamed folder
    /// is never visited.
    @Test func readsTheSparkleSuffixedFolder() throws {
        try withCaches { caches in
            let id = "com.zzfixture.staged.app"
            try stageTwoLevel(in: caches, folder: id + ".sparkle", identifier: id)
            let fields = StagedSparkleVersions.read(bundleID: id, cachesDirectory: caches.path)
            #expect(fields == .init(identifier: id, shortVersion: "1.102.4", buildVersion: "101.102.4"))
        }
    }

    // MARK: layouts

    /// Sparkle ≥ 2.6.1: `Installation/<rand>/<rand>/<Name>.app`, beside the archive.
    @Test func readsTheTwoLevelLayout() throws {
        try withCaches { caches in
            try stageTwoLevel(in: caches)
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path)
                == .init(identifier: Self.bundleID, shortVersion: "1.102.4", buildVersion: "101.102.4"))
        }
    }

    /// Sparkle 2.0.0–2.6.0: `Installation/<rand>/<Name>.app`.
    ///
    /// Mutation: drop the `innerName.hasSuffix(".app")` branch.
    @Test func readsTheOneLevelLayout() throws {
        try withCaches { caches in
            let attempt = installation(caches).appendingPathComponent("ZZr1")
            try makeApp(at: attempt.appendingPathComponent("ZZFixture.app"))
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path)?
                .shortVersion == "1.102.4")
        }
    }

    /// Nothing deeper than the two layouts is visited.
    ///
    /// Mutation: recurse into `extraction`'s non-`.app` entries.
    @Test func nothingDeeperIsRead() throws {
        try withCaches { caches in
            let deep = installation(caches).appendingPathComponent("ZZr1/ZZr2/ZZr3/ZZFixture.app")
            try makeApp(at: deep)
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    /// Sparkle's own `Updater.app` (or anything else) in the same tree is not a
    /// staged copy of this app and is skipped, not reported.
    @Test func anotherBundleIsSkipped() throws {
        try withCaches { caches in
            let attempt = installation(caches).appendingPathComponent("ZZr1/ZZr2")
            try makeApp(at: attempt.appendingPathComponent("Updater.app"),
                        identifier: "org.sparkle-project.Sparkle.Updater", short: "2.8.0", build: "2048")
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
            try makeApp(at: attempt.appendingPathComponent("ZZFixture.app"))
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path)?
                .shortVersion == "1.102.4")
        }
    }

    /// Two staged copies that disagree — a live one and one abandoned by a killed
    /// installer, which Sparkle keeps for ten days — cannot be told apart here.
    ///
    /// Mutation: return `found.first` without the agreement check.
    @Test func disagreeingCopiesAreUnknownAgreeingOnesAreNot() throws {
        try withCaches { caches in
            let base = installation(caches)
            try makeApp(at: base.appendingPathComponent("ZZa/ZZb/ZZFixture.app"))
            try makeApp(at: base.appendingPathComponent("ZZc/ZZd/ZZFixture.app"))
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) != nil)
            try makeApp(at: base.appendingPathComponent("ZZe/ZZf/ZZFixture.app"),
                        short: "1.102.2", build: "101.102.2")
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    /// Mutation: drop the `names.count > maxEntriesPerDirectory` check.
    @Test func aCrowdedDirectoryIsRefused() throws {
        try withCaches { caches in
            try stageTwoLevel(in: caches)
            for n in 0..<StagedSparkleVersions.maxEntriesPerDirectory {
                try FileManager.default.createDirectory(
                    at: installation(caches).appendingPathComponent("ZZpad\(n)"),
                    withIntermediateDirectories: true)
            }
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    // MARK: symlinks

    /// A link at ANY level below the prefix is not followed, even when it leads to
    /// a perfectly valid staging. Each level is linked in turn to a complete copy
    /// of the same tree outside the caches.
    ///
    /// Mutations: drop `O_NOFOLLOW` from `openDirectory` (every directory level
    /// goes red); drop it from the `Info.plist` open (the last level goes red).
    @Test(arguments: [
        "com.zzfixture.staged", "org.sparkle-project.Sparkle", "Installation",
        "ZZr1", "ZZr2", "ZZFixture.app", "Contents", "Info.plist",
    ])
    func aLinkAtAnyLevelIsNotFollowed(level: String) throws {
        try withCaches { caches in
            let outside = caches.deletingLastPathComponent().appendingPathComponent("ZZFixture-outside")
            try stageTwoLevel(in: outside)
            let relative = [Self.bundleID, "org.sparkle-project.Sparkle", "Installation",
                            "ZZr1", "ZZr2", "ZZFixture.app", "Contents", "Info.plist"]
            let depth = try #require(relative.firstIndex(of: level))
            let parts = relative[...depth]
            // The real tree up to the parent of `level`, then a link in its place.
            let parent = parts.dropLast().reduce(caches) { $0.appendingPathComponent($1) }
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let target = parts.reduce(outside) { $0.appendingPathComponent($1) }
            try FileManager.default.createSymbolicLink(
                at: parent.appendingPathComponent(level), withDestinationURL: target)
            // Sanity: following the link WOULD have found it.
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: outside.path) != nil)
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    /// The issue's literal case: `Installation/x` → `/etc`.
    @Test func aLinkToEtcReadsNothing() throws {
        try withCaches { caches in
            let base = installation(caches)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: base.appendingPathComponent("x"), withDestinationURL: URL(fileURLWithPath: "/etc"))
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    // MARK: Info.plist

    /// What comes back is the three fields and nothing else, whatever else the
    /// plist carries.
    ///
    /// Mutation: add a stored property to `Fields` (the shape check goes red).
    @Test func onlyTheThreeFieldsComeBack() throws {
        try withCaches { caches in
            try stageTwoLevel(in: caches, extra: [
                "SUFeedURL": "https://example.invalid/appcast.xml",
                "NSHumanReadableCopyright": "ZZFixture", "LSMinimumSystemVersion": "12.0",
            ])
            let fields = try #require(StagedSparkleVersions.read(
                bundleID: Self.bundleID, cachesDirectory: caches.path))
            #expect(fields == .init(identifier: Self.bundleID, shortVersion: "1.102.4", buildVersion: "101.102.4"))
            #expect(Mirror(reflecting: fields).children.map(\.label) == ["identifier", "shortVersion", "buildVersion"])
        }
    }

    /// Mutations: drop the `maxVersionLength` check (the long version passes);
    /// drop the control-character check (the newline passes); replace the
    /// present-but-unusable `CFBundleVersion` rejection with `build = nil` (the
    /// numeric build passes); drop `identifier == bundleID`.
    @Test func unusableFieldsRejectTheBundle() {
        func plist(_ dict: [String: Any]) -> Data {
            // swiftlint:disable:next force_try
            try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        }
        let good: [String: Any] = [
            "CFBundleIdentifier": Self.bundleID,
            "CFBundleShortVersionString": "1.102.4", "CFBundleVersion": "101.102.4",
        ]
        #expect(StagedSparkleVersions.fields(fromInfoPlist: plist(good), bundleID: Self.bundleID) != nil)
        var noBuild = good; noBuild["CFBundleVersion"] = nil
        #expect(StagedSparkleVersions.fields(fromInfoPlist: plist(noBuild), bundleID: Self.bundleID)?
            .buildVersion == nil)

        var long = good; long["CFBundleShortVersionString"] = String(repeating: "9", count: 129)
        var control = good; control["CFBundleVersion"] = "101\n102"
        var numeric = good; numeric["CFBundleVersion"] = 101
        var blank = good; blank["CFBundleShortVersionString"] = "  "
        var other = good; other["CFBundleIdentifier"] = "com.zzfixture.other"
        for (name, dict) in [("long", long), ("control", control), ("numeric", numeric),
                             ("blank", blank), ("other", other)] {
            #expect(StagedSparkleVersions.fields(fromInfoPlist: plist(dict), bundleID: Self.bundleID) == nil, "\(name)")
        }
        #expect(StagedSparkleVersions.fields(fromInfoPlist: Data("not a plist".utf8), bundleID: Self.bundleID) == nil)
    }

    /// Mutation: pass `Int.max` instead of `maxInfoPlistBytes` to `readRegularFile`.
    @Test func anOversizedInfoPlistIsRefused() throws {
        try withCaches { caches in
            try stageTwoLevel(in: caches, extra: [
                "ZZPadding": String(repeating: "z", count: StagedSparkleVersions.maxInfoPlistBytes),
            ])
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    /// A FIFO where `Info.plist` should be: refused, and without waiting for a
    /// writer that never comes.
    ///
    /// Mutation: drop `O_NONBLOCK` — the open blocks and the suite's time limit
    /// fails it.
    ///
    /// Known gap: dropping the `S_IFREG` check leaves this green (an empty read
    /// is no plist), and no case here isolates that check — a directory in
    /// `Info.plist`'s place fails `read` with `EISDIR` anyway, and a device node
    /// cannot be made without root.
    @Test func aFIFOInfoPlistIsRefusedWithoutBlocking() throws {
        try withCaches { caches in
            let contents = installation(caches).appendingPathComponent("ZZr1/ZZr2/ZZFixture.app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try #require(mkfifo(contents.appendingPathComponent("Info.plist").path, 0o600) == 0)
            #expect(StagedSparkleVersions.read(bundleID: Self.bundleID, cachesDirectory: caches.path) == nil)
        }
    }

    // MARK: through the service

    /// The XPC method answers nil for a refused identifier, on its own queue.
    @Test func theServiceAnswersNilForARefusedIdentifier() async {
        let service = HelperService(clientIdentity: HelperClientIdentity(
            uid: 4242, gid: 4343, userName: "zzfixture"))
        let reply: [String?] = await withCheckedContinuation { cont in
            service.stagedSparkleBundleVersions(bundleID: "../ZZFixture") { a, b, c in
                cont.resume(returning: [a, b, c])
            }
        }
        #expect(reply == [nil, nil, nil])
    }

    // MARK: fixtures

    private func withCaches(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-StagedSparkle-\(UUID().uuidString)")
        let caches = root.appendingPathComponent("Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(caches)
    }

    private func installation(_ caches: URL, folder: String = bundleID) -> URL {
        caches.appendingPathComponent(folder)
            .appendingPathComponent("org.sparkle-project.Sparkle")
            .appendingPathComponent("Installation")
    }

    /// `Installation/ZZr1/ZZr2/ZZFixture.app` plus the archive beside `ZZr2`, as
    /// on the mini.
    private func stageTwoLevel(
        in caches: URL, folder: String = bundleID, identifier: String = bundleID,
        extra: [String: Any] = [:]
    ) throws {
        let attempt = installation(caches, folder: folder).appendingPathComponent("ZZr1")
        try makeApp(at: attempt.appendingPathComponent("ZZr2/ZZFixture.app"),
                    identifier: identifier, extra: extra)
        try Data("zz".utf8).write(to: attempt.appendingPathComponent("ZZFixture-1.102.4.zip"))
    }

    private func makeApp(
        at url: URL, identifier: String = bundleID, short: String = "1.102.4",
        build: String = "101.102.4", extra: [String: Any] = [:]
    ) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": short,
            "CFBundleVersion": build,
        ]
        info.merge(extra) { _, new in new }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }
}
