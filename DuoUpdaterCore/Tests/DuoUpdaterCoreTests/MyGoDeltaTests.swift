import Foundation
import Testing
@testable import DuoUpdaterCore

/// `MyGoDelta` against fixtures made by MyGo's own Go code
/// (`github.com/egoist/mygo` `internal/update`, commit 49b7a7f): `WriteDelta` and
/// `Diff` built them from the trees `Fixture` writes below, and the reference
/// `ApplyDelta` round-tripped the delta before it was copied here. So a pass
/// means this port reads what the real encoder writes, not what we think it does.
struct MyGoDeltaTests {

    /// `WriteDelta(w, "1.0", "2.0", old, new, nil)`.
    static let referenceDelta = Data(base64Encoded: [
        "bXlnbyBkZWx0YSAxCsYDjJLNbtRKEIXfpdZO0lX97+3VXSCBkGCJWFRXVSujZDwj2yFAlHdHCQoTCcOw",
        "siwfq7/vnH6APh/2MAJeOhjgi83L7jDBCPT8btM672yB8dMDHHm9hhH+O0yrTesCA+huhnGd7+xx+O3z",
        "1f/74/rtXOjN1A+Xx9vdssIA+4MajIHcAMvuu8FIdYDlmikmGKG55rovrVuiyEFZutRcC3JLvpk3Zk1B",
        "vWYv2SqSx6DkfaWOEas8ofDKMHraInm7m25ggNunxwgfbDnczWLL1Y3Z8XL9usLWT+9Y3n885/gcuuLj",
        "8aRY/YtiIaJXkhljxcxqCSVg70W5q8aQaiFhZ2zJu+gTk1Nl4tqypNazi5ZisALDy56bx/8sIOctzF/K",
        "53xO3bSZJ72Y7P65oBc7X8LmgFwDBq1cWyBTxSY9B/NCnKQWCjmVWNm1iugrOckh5aZCgWt0zZ0bcGOy",
        "jSuF4RVRwRi0arOcGnpuXnMK1VfuqfXgTTzXGHJSsdaiuoJKDgtFNBeVdKPtf7w4p9hk9xcT7+2PwPF1",
        "hdFcKVZ6ytGjM46YKEvDlEVEArbkwlMWRdDVoK6bipj1HFoT+ivw4VZPJI+fH38MACpLLSrOzM9TMNJR",
        "yMnPS08tUijJSMxTSEpNyy9KBQwAAQghanCQWxgJGADs0EENAAAIBCB/9m9sC3e3QQQGAACItw8sAwAA",
        "AEC3GwBKLChIzUtJTVEoSczMUchPUyjJSFXISy1XSCrNzEkBDABKVEjLzElVyM/LqVQoyUhVyEstV0gq",
        "zcxJUchILAYMAA==",
    ].joined())!

    /// `Diff(Fixture.binary, Fixture.binary2)`.
    static let referencePatch = Data(base64Encoded: [
        "AQghanCQWxgJGADs0EENAAAIBCB/9m9sC3e3QQQGAACItw8sAwAAAEC3GwBKLChIzUtJTVEoSczMUchP",
        "UyjJSFXISy1XSCrNzEkBDAA=",
    ].joined())!

    enum Fixture {
        /// The fixture's "executable": 8 KiB from the same LCG the Go generator used.
        static let binary: Data = {
            var x: UInt32 = 1
            return Data((0..<8192).map { _ in
                x = x &* 1664525 &+ 1013904223
                return UInt8(x >> 24)
            })
        }()

        /// The new build's: a changed stretch in the middle, and a tail.
        static let binary2: Data = {
            var b = [UInt8](binary)
            for i in 3000..<3100 { b[i] = b[i] &+ 7 }
            return Data(b) + Data("appended tail of the new build".utf8)
        }()

        /// The installed bundle the delta was cut against.
        static func writeOldApp(at root: URL) throws {
            try write(root, "Contents/Info.plist", "version 1", 0o644)
            try write(root, "Contents/MacOS/app", binary, 0o755)
            try write(root, "Contents/Resources/keep.txt", "unchanged file", 0o644)
            try write(root, "Contents/Resources/old-name.txt", "this file moves", 0o644)
        }

        static func write(_ root: URL, _ rel: String, _ text: String, _ mode: Int) throws {
            try write(root, rel, Data(text.utf8), mode)
        }

        static func write(_ root: URL, _ rel: String, _ data: Data, _ mode: Int) throws {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        }
    }

    /// A scratch directory with the old bundle in it, and where the new one goes.
    private func scratch() throws -> (dir: URL, old: URL, new: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyGoDeltaTests-\(UUID().uuidString)")
        let old = dir.appendingPathComponent("Old.app")
        try Fixture.writeOldApp(at: old)
        return (dir, old, dir.appendingPathComponent("New.app"))
    }

    private func writeDelta(_ data: Data, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("update.delta")
        try data.write(to: url)
        return url
    }

    private func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }

    @Test func rebuildsTheTreeTheReferenceEncoderDescribes() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        try MyGoDelta.apply(
            patchFile: try writeDelta(Self.referenceDelta, in: s.dir), from: "1.0", to: "2.0",
            installedApp: s.old, destination: s.new)

        func read(_ rel: String) throws -> Data {
            try Data(contentsOf: s.new.appendingPathComponent(rel))
        }
        // Each kind of entry: whole (new), patched, copied, moved, new with its
        // own mode, directory, link.
        #expect(try read("Contents/Info.plist") == Data("version 2, longer than before".utf8))
        #expect(try read("Contents/MacOS/app") == Fixture.binary2)
        #expect(try read("Contents/Resources/keep.txt") == Data("unchanged file".utf8))
        #expect(try read("Contents/Resources/new-name.txt") == Data("this file moves".utf8))
        #expect(try read("Contents/Resources/brand-new.txt") == Data("a file only the new build has".utf8))
        #expect(!FileManager.default.fileExists(
            atPath: s.new.appendingPathComponent("Contents/Resources/old-name.txt").path))
        #expect(try mode(s.new.appendingPathComponent("Contents/MacOS/app")) == 0o755)
        #expect(try mode(s.new.appendingPathComponent("Contents/Resources/brand-new.txt")) == 0o600)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: s.new.appendingPathComponent("Contents/Empty").path, isDirectory: &isDir) && isDir.boolValue)
        #expect(try FileManager.default.destinationOfSymbolicLink(
            atPath: s.new.appendingPathComponent("Contents/Link").path) == "Resources/keep.txt")
        // The installed bundle is read, never written.
        #expect(try Data(contentsOf: s.old.appendingPathComponent("Contents/MacOS/app")) == Fixture.binary)
    }

    @Test func patchMatchesTheReferenceDiff() throws {
        let out = try MyGoDelta.patch(
            old: Fixture.binary, size: Int64(Fixture.binary2.count), patch: Self.referencePatch)
        #expect(out == Fixture.binary2)
        // A size the patch does not make is refused, not padded or cut.
        #expect(throws: MyGoDelta.Failure.damaged) {
            try MyGoDelta.patch(
                old: Fixture.binary, size: Int64(Fixture.binary2.count) - 1, patch: Self.referencePatch)
        }
    }

    /// A delta for other versions is refused before anything is made.
    @Test func refusesADeltaForOtherVersions() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let file = try writeDelta(Self.referenceDelta, in: s.dir)
        #expect(throws: MyGoDelta.Failure.wrongVersions(patchFrom: "1.0", patchTo: "2.0", from: "1.1", to: "2.0")) {
            try MyGoDelta.apply(patchFile: file, from: "1.1", to: "2.0", installedApp: s.old, destination: s.new)
        }
        #expect(throws: MyGoDelta.Failure.wrongVersions(patchFrom: "1.0", patchTo: "2.0", from: "1.0", to: "3.0")) {
            try MyGoDelta.apply(patchFile: file, from: "1.0", to: "3.0", installedApp: s.old, destination: s.new)
        }
        #expect(!FileManager.default.fileExists(atPath: s.new.path))
    }

    /// The case that happens: the installed copy is not byte for byte the one the
    /// delta was cut from (Moshi Go's dmg lacks a file its tarball has). The
    /// failure names the file, and the installer then takes the full archive.
    @Test func refusesAnInstalledAppItWasNotCutFrom() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        let file = try writeDelta(Self.referenceDelta, in: s.dir)
        try Fixture.write(s.old, "Contents/Resources/keep.txt", "changed since install", 0o644)
        #expect(throws: MyGoDelta.Failure.madeWrong("Contents/Resources/keep.txt")) {
            try MyGoDelta.apply(patchFile: file, from: "1.0", to: "2.0", installedApp: s.old, destination: s.new)
        }

        // Same length, other bytes: only the SHA-256 tells them apart — for a
        // copied file, and for a patched one.
        let same = try scratch()
        defer { try? FileManager.default.removeItem(at: same.dir) }
        try Fixture.write(same.old, "Contents/Resources/keep.txt", "UNCHANGED FILE", 0o644)
        #expect(throws: MyGoDelta.Failure.madeWrong("Contents/Resources/keep.txt")) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(Self.referenceDelta, in: same.dir), from: "1.0", to: "2.0",
                installedApp: same.old, destination: same.new)
        }
        let patched = try scratch()
        defer { try? FileManager.default.removeItem(at: patched.dir) }
        var bin = [UInt8](Fixture.binary)
        bin[100] &+= 1
        try Fixture.write(patched.old, "Contents/MacOS/app", Data(bin), 0o755)
        #expect(throws: MyGoDelta.Failure.madeWrong("Contents/MacOS/app")) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(Self.referenceDelta, in: patched.dir), from: "1.0", to: "2.0",
                installedApp: patched.old, destination: patched.new)
        }

        let s2 = try scratch()
        defer { try? FileManager.default.removeItem(at: s2.dir) }
        try FileManager.default.removeItem(at: s2.old.appendingPathComponent("Contents/Resources/old-name.txt"))
        #expect(throws: MyGoDelta.Failure.madeWrong("Contents/Resources/old-name.txt")) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(Self.referenceDelta, in: s2.dir), from: "1.0", to: "2.0",
                installedApp: s2.old, destination: s2.new)
        }
    }

    @Test func refusesWhatIsNotAnIntactDelta() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        #expect(throws: MyGoDelta.Failure.notADelta) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(Data("PK\u{3}\u{4} a zip".utf8), in: s.dir), from: "1.0", to: "2.0",
                installedApp: s.old, destination: s.new)
        }
        // Bytes past the data the index accounts for.
        #expect(throws: MyGoDelta.Failure.damaged) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(Self.referenceDelta + Data("junk".utf8), in: s.dir), from: "1.0", to: "2.0",
                installedApp: s.old, destination: s.new)
        }
        // Truncated: the index's data no longer adds up to the file.
        #expect(throws: MyGoDelta.Failure.damaged) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(Self.referenceDelta.dropLast(10), in: s.dir), from: "1.0", to: "2.0",
                installedApp: s.old, destination: s.new)
        }
    }

    /// A delta with this index and no data — for the checks that read the index alone.
    private func craftedDelta(_ entries: String) -> Data {
        let js = Data(#"{"from":"1.0","version":"2.0","entries":"#.utf8) + Data(entries.utf8) + Data("}".utf8)
        let compressed = try! (js as NSData).compressed(using: .zlib) as Data
        var out = Data(MyGoDelta.magic)
        var n = UInt64(compressed.count)
        while n >= 0x80 { out.append(UInt8(n & 0x7f) | 0x80); n >>= 7 }
        out.append(UInt8(n))
        return out + compressed
    }

    @Test func keepsEveryPathInsideTheApp() throws {
        let s = try scratch()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        // The crafted index is read by the same code as a real one.
        try MyGoDelta.apply(
            patchFile: try writeDelta(craftedDelta(#"[{"path":"Contents","dir":true}]"#), in: s.dir),
            from: "1.0", to: "2.0", installedApp: s.old, destination: s.new)
        try FileManager.default.removeItem(at: s.new)

        #expect(throws: MyGoDelta.Failure.linkOutsideApp("Contents/Link")) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(craftedDelta(#"[{"path":"Contents/Link","link":"../../outside"}]"#), in: s.dir),
                from: "1.0", to: "2.0", installedApp: s.old, destination: s.new)
        }
        #expect(throws: MyGoDelta.Failure.linkOutsideApp("Contents/Link")) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(craftedDelta(#"[{"path":"Contents/Link","link":"/etc"}]"#), in: s.dir),
                from: "1.0", to: "2.0", installedApp: s.old, destination: s.new)
        }
        for path in ["../escape", "/etc/x", "a//b", "a/./b", "."] {
            #expect(throws: MyGoDelta.Failure.damaged, "\(path)") {
                try MyGoDelta.apply(
                    patchFile: try writeDelta(craftedDelta(#"[{"path":"\#(path)","dir":true}]"#), in: s.dir),
                    from: "1.0", to: "2.0", installedApp: s.old, destination: s.new)
            }
        }
        // A copy whose source climbs out of the installed bundle.
        #expect(throws: MyGoDelta.Failure.damaged) {
            try MyGoDelta.apply(
                patchFile: try writeDelta(craftedDelta(
                    #"[{"path":"x","size":1,"sha256":"00","from":"../Old.app/Contents/Info.plist"}]"#), in: s.dir),
                from: "1.0", to: "2.0", installedApp: s.old, destination: s.new)
        }
        #expect(!FileManager.default.fileExists(atPath: s.new.path))
    }

    @Test func goPathRules() {
        #expect(MyGoDelta.isValidPath("Contents/MacOS/app"))
        #expect(MyGoDelta.isValidPath("."))
        #expect(!MyGoDelta.isValidPath(""))
        #expect(!MyGoDelta.isValidPath("a/"))
        #expect(!MyGoDelta.isValidPath("a/../b"))
        #expect(MyGoDelta.cleanJoin("Contents", "Resources/keep.txt") == "Contents/Resources/keep.txt")
        #expect(MyGoDelta.cleanJoin("Contents", "../Info.plist") == "Info.plist")
        #expect(MyGoDelta.cleanJoin(".", "..") == "..")
        #expect(MyGoDelta.parent(of: "Contents/Link") == "Contents")
        #expect(MyGoDelta.parent(of: "Contents") == ".")
    }
}

/// `MyGoManifestDeltas` on the shape of a real `update-darwin-arm64.json`
/// (Moshi Go's, trimmed: one release, its deltas, and a `previous` entry).
struct MyGoManifestDeltasTests {

    static let feed = URL(string: "https://cdn.example.com/app/update-darwin-arm64.json")!

    static let body = #"""
    {
      "version": "0.5.3",
      "notes": "- A note mentioning \"deltas\" and \"previous\".",
      "date": "2026-10-07T10:16:16Z",
      "url": "https://cdn.example.com/app/app-0.5.3-darwin-arm64.tar.gz",
      "size": 15227087,
      "signature": "QY4f",
      "deltas": [
        {"from": "0.5.2", "url": "https://cdn.example.com/app/app-0.5.2-to-0.5.3-darwin-arm64.delta", "size": 891233, "signature": "PN59"},
        {"from": "0.5.1", "url": "app-0.5.1-to-0.5.3-darwin-arm64.delta", "size": 1188675, "signature": "GocN"},
        {"from": "0.5.0", "url": "http://cdn.example.com/app/app-0.5.0-to-0.5.3-darwin-arm64.delta", "size": 1119373, "signature": "Ps6x"}
      ],
      "previous": [
        {"version": "0.5.2", "url": "https://cdn.example.com/app/app-0.5.2-darwin-arm64.tar.gz", "size": 15235667, "signature": "nNro"}
      ]
    }
    """#

    @Test func readsThePatchesOfTheResolvedVersion() {
        let patches = MyGoManifestDeltas.patches(inBody: Self.body, forVersion: "0.5.3", feedURL: Self.feed)
        // The plain-http one is dropped; the relative one resolves against the feed.
        #expect(patches.map(\.fromBuild) == ["0.5.2", "0.5.1"])
        #expect(patches.map(\.url.absoluteString) == [
            "https://cdn.example.com/app/app-0.5.2-to-0.5.3-darwin-arm64.delta",
            "https://cdn.example.com/app/app-0.5.1-to-0.5.3-darwin-arm64.delta",
        ])
        #expect(patches.map(\.size) == [891233, 1188675])
        #expect(patches.allSatisfy { $0.format == .myGo && $0.toVersion == "0.5.3" && $0.edSignature == nil })
        #expect(DeltaApplier.canApply(.myGo))
    }

    /// A probe that resolved another version must not be handed these patches.
    @Test func refusesAManifestForAnotherVersion() {
        #expect(MyGoManifestDeltas.patches(inBody: Self.body, forVersion: "0.5.2", feedURL: Self.feed).isEmpty)
    }

    @Test func ignoresBodiesOfOtherShapes() {
        #expect(MyGoManifestDeltas.patches(
            inBody: #"<rss><channel><item><sparkle:deltas/></item></channel></rss>"#, forVersion: "1.0").isEmpty)
        #expect(MyGoManifestDeltas.patches(
            inBody: #"{"version":"1.0","platforms":{}}"#, forVersion: "1.0").isEmpty)
        #expect(MyGoManifestDeltas.patches(
            inBody: #"{"version":"1.0","deltas":"none"}"#, forVersion: "1.0").isEmpty)
    }
}
