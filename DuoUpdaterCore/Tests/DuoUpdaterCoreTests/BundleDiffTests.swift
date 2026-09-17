import Testing
import Foundation
@testable import DuoUpdaterCore

/// `duo diff`'s rules, each against bytes the test wrote. Every noise class here was
/// hit on a real release pair while the command was being built; the doc comment on
/// `BundleDiff` names which.
@Suite struct BundleDiffTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    // MARK: Source paths

    @Test func sourcePathsAreFoundAndStrippedOfSwallowedWords() {
        let bytes = Data((
            "\0/ZZBuild/job/0/zzfixture/Module/Feature.swift\0"
            + "\0window ZZFixture/Window.swift\0"
            + "\0../../zzfixture/net/socket.cc\0"
            + "\0noslash.swift\0"            // no directory: not a path
            + "\0ZZFixture/Module.swiftmodule\0"  // the extension runs on
        ).utf8)
        let found = bytes.withUnsafeBytes { SourcePathScanner.paths(in: $0) }
        #expect(found == [
            "/ZZBuild/job/0/zzfixture/Module/Feature.swift",
            "ZZFixture/Window.swift",
            "../../zzfixture/net/socket.cc",
        ])
    }

    /// UU Remote 4.35 → 4.39: 215 files that only switched between `#filePath` and
    /// `#fileID`. Compared by full path they read as 215 removals and 215 additions.
    @Test func aRespelledSourcePathIsNoiseNotAChange() {
        let change = BundleDiff.sourcePathChange(
            ["/ZZBuild/job-a/zzfixture/Module/Feature.swift", "ZZFixture/Kept.swift"],
            ["ZZFixture/Feature.swift", "ZZFixture/Kept.swift", "ZZFixture/Added.swift"])
        #expect(change.added == ["ZZFixture/Added.swift"])
        #expect(change.removed.isEmpty)
        #expect(change.respelled == 1)
    }

    /// Baidu Netdisk 8.8.3 bundled GLib, and its source paths grouped under one
    /// directory made a 2,563-character line that the workbench could not draw.
    @Test func aLargeDirectoryIsSplitAcrossLinesWithoutLosingNames() {
        let names = (1...20).map { "zz\($0).c" }
        let lines = BundleDiff.groupedByDirectory(names.map { "../zzfixture/gio/" + $0 })
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.hasPrefix("../zzfixture/gio/{") })
        let listed = lines.flatMap { $0.dropFirst("../zzfixture/gio/{".count).dropLast().components(separatedBy: ", ") }
        #expect(Set(listed) == Set(names))
    }

    /// Review of #706: the cap counted lines once a directory spanned several, so
    /// one large directory used it all and the next directory was never shown.
    @Test func theCapCountsDirectoriesNotLines() {
        let big = (1...320).map { "../zzfixture/third_party/zz\($0).c" }
        let lines = BundleDiff.groupedByDirectory(big + ["ZZFixture/App/Feature/New.swift"], directoryLimit: 40)
        #expect(lines.contains("ZZFixture/App/Feature/{New.swift}"))
        #expect(lines.count == 41)

        let many = (1...45).map { "zz/dir\($0)/file.swift" }
        let capped = BundleDiff.groupedByDirectory(many, prefix: "  + ", directoryLimit: 40)
        #expect(capped.count == 41)
        #expect(capped.last == "  + … 5 more directories")
    }

    /// Review of #706: a backup skips unreadable runtime state inside the bundle
    /// (ToDesk's mmkv files), and without being told the diff listed those as added.
    @Test func filesTheBackupSkippedAreNotReportedAsAdded() {
        var old = BundleFacts(), new = BundleFacts()
        old.files = ["Contents/MacOS/zzfixture": FileFact(size: 1, digest: "a")]
        old.omittedByBackup = ["Contents/zz.mmkv"]
        new.files = old.files
        new.files["Contents/zz.mmkv"] = FileFact(size: 5, digest: "unreadable")
        new.files["Contents/Resources/zz-new.txt"] = FileFact(size: 5, digest: "n")
        let files = BundleDiff.filesSection(old: old, new: new)
        #expect(files.contains { $0.contains("1 added, 0 removed") })
        #expect(files.contains("  + Contents/Resources/zz-new.txt (5 bytes)"))
        #expect(!files.contains { $0.hasPrefix("  + Contents/zz.mmkv") })
        #expect(files.contains { $0.hasPrefix("  1 more only on the new side because the backup skipped them") })
        #expect(files.contains("      Contents/zz.mmkv"))
    }

    // MARK: Localization

    /// Mac Mouse Fix 3.1.0 moved keys under a new prefix with the same text.
    @Test func aKeyMovedWithItsValueIsARename() {
        let change = BundleDiff.localizationChange(
            ["zz.button-modifier.1": "Click %@ +", "zz.gone": "Removed text"],
            ["zz.trigger.button-modifier.1": "Click %@ +", "zz.new": "New text"])
        #expect(change.renamed.map(\.old) == ["zz.button-modifier.1"])
        #expect(change.renamed.map(\.new) == ["zz.trigger.button-modifier.1"])
        #expect(change.added == ["zz.new"])
        #expect(change.removed == ["zz.gone"])
    }

    private func facts(runs: [String]) -> BundleFacts {
        var facts = BundleFacts()
        facts.stringsBlob = Data(runs.map { $0 + "\n" }.joined().utf8)
        return facts
    }

    /// A key that is a whole string in the new binaries only; one that the old
    /// binaries carried inside a longer string, which the exact lookup alone would
    /// miss; and one found nowhere.
    @Test func keyEvidenceCoversWholeRunsSubstringsAndAbsence() {
        let old = facts(runs: ["prefix-ZZFixture.Shared.title-suffix"])
        let new = facts(runs: ["ZZFixture.New.title", "ZZFixture.Shared.title"])
        let found = BundleDiff.evidence(
            for: ["ZZFixture.New.title", "ZZFixture.Shared.title", "ZZFixture.Missing.title"], old: old, new: new)
        #expect(found["ZZFixture.New.title"] == .referencedByNewBinaries)
        #expect(found["ZZFixture.Shared.title"] == .referencedByBoth)
        #expect(found["ZZFixture.Missing.title"] == .notFound)
    }

    /// Review of #705: an app that uses English text as keys adds `OK`, and a
    /// substring search finds those two bytes inside unrelated strings.
    @Test func aShortKeyIsNotFoundInsideLongerStrings() {
        let old = facts(runs: ["SOK_STATE_ZZFIXTURE"])
        let new = facts(runs: ["SOK_STATE_ZZFIXTURE", "zz.Cancellation.reason"])
        let found = BundleDiff.evidence(for: ["OK", "Cancel"], old: old, new: new)
        #expect(found["OK"] == .notFound)
        #expect(found["Cancel"] == .notFound)
    }

    /// Review of #705: a nib's strings file is full of empty titles and repeated
    /// words; pairing those invents a rename and hides the real removal.
    @Test func blankOrRepeatedValuesAreNotPairedAsRenames() {
        let change = BundleDiff.localizationChange(
            ["zz-old-1.title": "", "zz-old-2.title": "OK", "zz-old-3.title": "OK"],
            ["zz-new-1.title": "", "zz-new-2.title": "OK"])
        #expect(change.renamed.isEmpty)
        #expect(change.removed == ["zz-old-1.title", "zz-old-2.title", "zz-old-3.title"])
        #expect(change.added == ["zz-new-1.title", "zz-new-2.title"])
    }

    @Test func nothingToCompareIsSaidRatherThanNoChange() {
        let empty = BundleFacts()
        #expect(BundleDiff.localizationSection(old: empty, new: empty)
            .contains("  NOT COMPARED — no en, Base or zh-Hans .strings file on either side"))
        #expect(BundleDiff.trustSection(old: empty, new: empty)
            .contains { $0.hasSuffix("NOT COMPARED — no bundle is at the same path on both sides") })
    }

    // MARK: Packages against everything else

    private func packageFacts(component: String) -> BundleFacts {
        var facts = BundleFacts()
        facts.isPackage = true
        facts.rootName = "expanded"
        let app = "\(component)/Payload/Applications/ZZFixture.app"
        facts.packageComponents = [component: ["identifier": "test.zzfixture"]]
        facts.bundles = [app: BundleFact(identifier: "test.zzfixture", shortVersion: "2.0")]
        facts.files = [
            "\(app)/Contents/MacOS/zzfixture": FileFact(size: 1, digest: "b"),
            "\(component)/Scripts/postinstall": FileFact(size: 1, digest: "s"),
            "\(component)/Payload/Library/LaunchDaemons/test.zzfixture.plist": FileFact(size: 1, digest: "d"),
        ]
        facts.scripts = ["\(component)/Scripts/postinstall": "#!/bin/sh\n"]
        return facts
    }

    /// Review of #705, reproduced on UU Remote 4.41: the pkg against the app taken out
    /// of that same pkg shared no path, and the trust line read "unchanged in all 0
    /// common bundles".
    @Test func aPackageLinesUpWithTheAppInsideIt() {
        var app = BundleFacts()
        app.rootName = "ZZFixture.app"
        app.bundles = [".": BundleFact(identifier: "test.zzfixture", shortVersion: "1.0")]
        app.files = ["Contents/MacOS/zzfixture": FileFact(size: 1, digest: "a")]

        let package = BundleDiff.aligned(packageFacts(component: "ZZFixture.pkg"))
        #expect(Set(package.bundles.keys) == ["."])
        #expect(package.rootName == "ZZFixture.app")
        #expect(package.files["Contents/MacOS/zzfixture"] != nil)
        #expect(package.files["<package>/<component>/Scripts/postinstall"] != nil)
        #expect(package.scripts.keys.sorted() == ["<package>/<component>/Scripts/postinstall"])
        #expect(BundleDiff.aligned(app).files == app.files)

        let trust = BundleDiff.trustSection(old: app, new: package)
        #expect(trust.contains { $0.hasSuffix("unchanged in all 1 common bundles") })
        // The app has no package to compare a signature or scripts with: named as
        // one-sided, not as a signature that CHANGED to nothing or a script deleted
        // line by line.
        #expect(trust.contains { $0.hasPrefix("  package signature (new only):") })
        #expect(trust.contains("  script <package>/<component>/Scripts/postinstall (new only): 1 lines"))
        #expect(!trust.contains { $0.contains("CHANGED") || $0.contains("REMOVED,") || $0.contains("ADDED,") })
        #expect(trust.contains("  package component <component> (new only): identifier=test.zzfixture"))
        #expect(!trust.contains { $0.hasPrefix("  package component ADDED") || $0.hasPrefix("  package component REMOVED") })
        #expect(trust.contains("  background/privileged component ADDED   <package>/<component>/Payload/Library/LaunchDaemons/test.zzfixture.plist"))
    }

    /// A lone component package named after its version lines up across versions.
    @Test func aVersionedComponentNameLinesUpAcrossPackages() {
        let old = BundleDiff.aligned(packageFacts(component: "zzfixture-1.0.pkg"))
        let new = BundleDiff.aligned(packageFacts(component: "zzfixture-2.0.pkg"))
        #expect(Set(old.files.keys) == Set(new.files.keys))
        #expect(Set(old.scripts.keys) == Set(new.scripts.keys))
        #expect(Set(old.packageComponents.keys) == ["<component>"])
    }

    // MARK: Electron

    /// Chatbox 1.23.3: 777 renames that were all hashes, including hashes of
    /// letters only, which a per-name guess reads inconsistently across builds.
    @Test func bundlerHashesAreRemovedUnderDist() {
        #expect(BundleDiff.withoutBundlerHash("dist/renderer/js/powerquery.Bpmcvcod.js")
            == BundleDiff.withoutBundlerHash("dist/renderer/js/powerquery.DFjrb-Ms.js"))
        #expect(BundleDiff.withoutBundlerHash("dist/renderer/js/index-BUjNd0yw.js.map") == "dist/renderer/js/index.js.map")
        // Outside dist/ an ordinary eight-letter word is left alone.
        #expect(BundleDiff.withoutBundlerHash("node_modules/zzfixture/lib/zz-renderer.js") == "node_modules/zzfixture/lib/zz-renderer.js")
    }

    /// An asar written by hand: pickle header, JSON, then the file bytes.
    private func asar(_ files: [String: Data], integrity: Bool = true) -> Data {
        var tree: [String: Any] = ["files": [String: Any]()]
        var body = Data()
        func insert(_ parts: ArraySlice<String>, _ entry: [String: Any], into node: inout [String: Any]) {
            var children = node["files"] as? [String: Any] ?? [:]
            if parts.count == 1 {
                children[parts.first!] = entry
            } else {
                var child = children[parts.first!] as? [String: Any] ?? ["files": [String: Any]()]
                insert(parts.dropFirst(), entry, into: &child)
                children[parts.first!] = child
            }
            node["files"] = children
        }
        for path in files.keys.sorted() {
            var entry: [String: Any] = ["size": files[path]!.count, "offset": String(body.count)]
            if integrity { entry["integrity"] = ["hash": "zz-\(path.hashValue)"] }
            insert(ArraySlice(path.split(separator: "/").map(String.init)), entry, into: &tree)
            body.append(files[path]!)
        }
        var json = try! JSONSerialization.data(withJSONObject: tree)
        let length = UInt32(json.count)
        while json.count % 4 != 0 { json.append(0) }
        var out = Data()
        func word(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        word(4)
        word(UInt32(8 + json.count))
        word(UInt32(4 + json.count))
        word(length)
        out.append(json)
        out.append(body)
        return out
    }

    @Test func anAsarIsReadWithoutUnpacking() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("app.asar")
        try write(asar([
            "package.json": Data(#"{"name":"zzfixture","version":"1.2.3","main":"dist/main.js"}"#.utf8),
            "node_modules/zzfixture-dep/package.json": Data(#"{"version":"4.5.6"}"#.utf8),
            "node_modules/@zz/scoped/package.json": Data(#"{"version":"7.8.9"}"#.utf8),
            // A manifest deep inside a package is a fixture of that package, not one.
            "node_modules/zzfixture-dep/test/fixtures/package.json": Data(#"{"version":"0.0.0"}"#.utf8),
            "dist/main.js.map": Data(#"{"sources":["../../src/main/zz.ts","../../node_modules/zzfixture-dep/index.js"]}"#.utf8),
        ]), to: archive)

        let fact = try BundleFactsReader.readAsar(at: archive)
        #expect(fact.files.count == 5)
        #expect(fact.rootPackage["version"] == "1.2.3")
        #expect(fact.packages == ["node_modules/zzfixture-dep": "4.5.6", "node_modules/@zz/scoped": "7.8.9"])
        #expect(fact.mapSources["dist/main.js.map"] == ["../../node_modules/zzfixture-dep/index.js", "../../src/main/zz.ts"])
    }

    @Test func aTruncatedAsarIsRefused() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("app.asar")
        try write(asar(["package.json": Data("{}".utf8)]).prefix(20), to: archive)
        #expect(throws: (any Error).self) { try BundleFactsReader.readAsar(at: archive) }
    }

    // MARK: Trust surface

    /// The package name and the signing timestamp differ on every build, and a
    /// certificate's fingerprint and expiry sit under its name.
    @Test func packageSignatureKeepsOnlyWhatIdentifiesTheSigner() {
        let text = """
            Package "zzfixture_1.0.pkg":
               Status: signed by a developer certificate issued by Apple for distribution
               Notarization: trusted by the Apple notary service
               Signed with a trusted timestamp on: 2026-09-16 13:08:02 +0000
               Certificate Chain:
                1. Developer ID Installer: ZZ Fixture (ZZFIXTURE1)
                   Expires: 2031-01-01 00:00:00 +0000
                   SHA256 Fingerprint:
                       00 11 22
                2. Developer ID Certification Authority
            """
        #expect(BundleFactsReader.packageSignatureLines(text) == [
            "Status: signed by a developer certificate issued by Apple for distribution",
            "Notarization: trusted by the Apple notary service",
            "1. Developer ID Installer: ZZ Fixture (ZZFIXTURE1)",
            "2. Developer ID Certification Authority",
        ])
    }

    private func summary(team: String?, entitlements: [String: String] = [:]) -> SignatureVerifier.SigningSummary {
        .init(identifier: "test.zzfixture", teamIdentifier: team,
              authorities: team.map { ["Developer ID Application: ZZ (\($0))"] } ?? [],
              flags: ["runtime"], runtimeVersion: "27.0.0", entitlements: entitlements)
    }

    @Test func aChangedTeamAndANewEntitlementAreBothReported() {
        let rows = BundleDiff.signatureChanges(
            summary(team: "ZZTEAMOLD1"),
            summary(team: "ZZTEAMNEW1", entitlements: ["com.apple.security.cs.disable-library-validation": "1"]))
        #expect(rows.contains("TEAM ID: ZZTEAMOLD1 -> ZZTEAMNEW1"))
        #expect(rows.contains("entitlement + com.apple.security.cs.disable-library-validation = 1"))
        #expect(BundleDiff.signatureChanges(summary(team: "ZZTEAM1"), summary(team: "ZZTEAM1")).isEmpty)
        #expect(BundleDiff.signatureChanges(summary(team: "ZZTEAM1"), nil) == ["signature: signed -> UNSIGNED or unreadable"])
    }

    /// Baidu Netdisk 8.8.3's image viewer went from an empty signed identifier to a
    /// real one, which printed as `signed identifier:  -> com.baidu…`.
    @Test func anEmptyIdentifierIsSpelledOut() {
        let empty = SignatureVerifier.SigningSummary(
            identifier: "", teamIdentifier: "ZZTEAM1", authorities: [], flags: [], runtimeVersion: nil, entitlements: [:])
        let named = SignatureVerifier.SigningSummary(
            identifier: "test.zzfixture", teamIdentifier: "ZZTEAM1", authorities: [], flags: [], runtimeVersion: nil, entitlements: [:])
        #expect(BundleDiff.signatureChanges(empty, named) == ["signed identifier: (empty) -> test.zzfixture"])
    }

    @Test func aNewLoginItemIsReportedOnceNotPerFile() {
        var old = BundleFacts(), new = BundleFacts()
        old.files = ["Contents/MacOS/zzfixture": FileFact(size: 1, digest: "a")]
        new.files = old.files
        for file in ["Contents/Info.plist", "Contents/MacOS/zzhelper"] {
            new.files["Contents/Library/LoginItems/ZZHelper.app/" + file] = FileFact(size: 1, digest: "b")
        }
        let (added, removed) = BundleDiff.privilegedComponents(old: old, new: new)
        #expect(added == ["Contents/Library/LoginItems/ZZHelper.app"])
        #expect(removed.isEmpty)
    }

    /// Re-review of #705: counting `Character("\n")` saw a CRLF `\r\n` as one
    /// grapheme that is not a newline, so a two-line script read as one.
    @Test func lineCountsMatchWcForCRLFAndAMissingFinalNewline() {
        #expect(BundleDiff.lineCount("a\r\nb\r\n") == 2)
        #expect(BundleDiff.lineCount("a\nb\n") == 2)
        #expect(BundleDiff.lineCount("a\nb") == 2)
        #expect(BundleDiff.lineCount("") == 0)
    }

    @Test func scriptChangesAreLineByLine() {
        let rows = BundleDiff.lineChanges("#!/bin/sh\nkeep\nold line\n", "#!/bin/sh\nkeep\nnew line\n")
        #expect(rows == ["- old line", "+ new line"])
    }

    // MARK: The public entry point

    private func minimalApp(in directory: URL) throws -> URL {
        let app = directory.appendingPathComponent("ZZFixture-report.app")
        try write(
            PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "test.zzfixture.report", "CFBundleShortVersionString": "3.0",
                                   "CFBundleVersion": "30"],
                format: .xml, options: 0),
            to: app.appendingPathComponent("Contents/Info.plist"))
        try write(Data("zz".utf8), to: app.appendingPathComponent("Contents/Resources/zz.txt"))
        return app
    }

    /// What the workbench and `duo diff` both call: the whole report, header to
    /// timings, as one string.
    @Test func theReportComparesTwoAppsEndToEnd() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try minimalApp(in: directory)
        let result = await BundleDiff.report(old: app.path, new: app.path, oldLabel: "backup", newLabel: "installed")
        let report = try result.get()
        #expect(report.hasPrefix("duo diff\n  old: backup  ZZFixture-report.app 3.0 (30)\n  new: installed  ZZFixture-report.app 3.0 (30)"))
        #expect(report.contains("\nTRUST SURFACE\n"))
        #expect(report.contains("\nTIMINGS (old and new are read concurrently)\n"))
    }

    /// Re-review of #706: the fix was tested by setting `omittedByBackup` directly,
    /// so nothing covered `report(omittedFromOld:)` handing the list to the old
    /// side — deleting that one line left every test green.
    @Test func theReportKeepsFilesTheBackupSkippedOutOfAdded() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backup = try minimalApp(in: directory.appendingPathComponent("backup"))
        let installed = try minimalApp(in: directory.appendingPathComponent("installed"))
        try write(Data("state".utf8), to: installed.appendingPathComponent("Contents/zz.mmkv"))

        let report = try await BundleDiff.report(
            old: backup.path, new: installed.path, omittedFromOld: ["Contents/zz.mmkv"]).get()
        #expect(report.contains("  1 more only on the new side because the backup skipped them"))
        #expect(report.contains("0 added, 0 removed"))
        #expect(!report.contains("  + Contents/zz.mmkv"))
    }

    @Test func aMissingInputIsAFailureNotAnEmptyReport() async throws {
        let result = await BundleDiff.report(old: "/ZZFixture-does-not-exist.app", new: "/ZZFixture-nor-this.app")
        #expect(throws: BundleDiff.Failure.self) { try result.get() }
    }

    /// The workbench cancels when the selection moves on; the walk must stop at the
    /// next file rather than hash the rest of a multi-gigabyte bundle.
    @Test func aStoppedWalkThrowsCancellation() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try minimalApp(in: directory)
        let stop = BundleDiff.StopFlag()
        stop.set()
        #expect(throws: CancellationError.self) { try BundleFactsReader.scan(root: app, stop: stop) }
        #expect(throws: Never.self) { try BundleFactsReader.scan(root: app) }
    }

    // MARK: Walking a bundle

    /// Mac Mouse Fix 3.0.8 has three symlinks, and `skipDescendants()` called on one
    /// skipped the rest of the directory holding it: 102 files seen instead of 280.
    /// The root bundle is also never yielded by the enumerator, so it is read
    /// separately and keyed `.`.
    @Test func aBundleWithSymlinksIsWalkedCompletely() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("ZZFixture.app")
        let contents = app.appendingPathComponent("Contents")
        try write(
            PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "test.zzfixture", "CFBundleShortVersionString": "1.0",
                                   "CFBundleVersion": "7", "CFBundleExecutable": "zzfixture"],
                format: .xml, options: 0),
            to: contents.appendingPathComponent("Info.plist"))
        // A framework shaped like Sparkle's: links first in listing order, files after.
        let framework = contents.appendingPathComponent("Frameworks/ZZKit.framework")
        for name in ["A", "B", "C", "D"] {
            try write(Data(name.utf8), to: framework.appendingPathComponent("Versions/A/Resources/\(name).txt"))
        }
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try FileManager.default.createSymbolicLink(
            atPath: framework.appendingPathComponent("Resources").path, withDestinationPath: "Versions/Current/Resources")
        try write(
            PropertyListSerialization.data(fromPropertyList: ["ZZ.greeting": "Hello"], format: .binary, options: 0),
            to: contents.appendingPathComponent("Resources/en.lproj/Localizable.strings"))
        // A thin arm64 header carrying one source path.
        var machO = Data()
        for word: UInt32 in [0xfeed_facf, 0x0100_000c, 0, 2, 0, 0, 0, 0] {
            withUnsafeBytes(of: word.littleEndian) { machO.append(contentsOf: $0) }
        }
        machO.append(Data("\0/ZZBuild/zzfixture/App/Main.swift\0".utf8))
        try write(machO, to: contents.appendingPathComponent("MacOS/zzfixture"))

        let facts = try BundleFactsReader.scan(root: app)
        let regular = facts.files.filter { !$0.value.digest.hasPrefix("symlink:") }
        #expect(regular.count == 7)
        #expect(facts.files.count == 9)
        #expect(facts.files["Contents/Frameworks/ZZKit.framework/Versions/Current"]?.digest == "symlink:A")
        #expect(facts.bundles["."]?.shortVersion == "1.0")
        #expect(facts.strings["Contents/Resources/en.lproj/Localizable.strings"] == ["ZZ.greeting": "Hello"])
        #expect(facts.machO["Contents/MacOS/zzfixture"]?.architectures == ["arm64"])
        #expect(facts.machO["Contents/MacOS/zzfixture"]?.sourcePaths == ["/ZZBuild/zzfixture/App/Main.swift"])
    }
}
