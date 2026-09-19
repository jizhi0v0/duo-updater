import Testing
import Foundation
@testable import DuoUpdaterCore

/// What a comparison reads instead of the backup, and the two things it must never
/// do: answer for a copy it does not describe, or let the report make a claim the
/// stored facts cannot support.
@Suite struct BackupFactsLibraryTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-facts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A bundle with something in every part of the facts the report compares: a
    /// real Mach-O (architectures, linked libraries, printable runs), a localization
    /// file, a symlink and a plain resource. `/bin/echo` is copied rather than
    /// fabricated because a hand-written header would exercise the byte test and
    /// nothing below it.
    private func fixtureApp(in directory: URL) throws -> URL {
        let fm = FileManager.default
        let app = directory.appendingPathComponent("ZZFixture-facts.app")
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: contents.appendingPathComponent("Resources/en.lproj"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "test.zzfixture.facts", "CFBundleShortVersionString": "4.0",
                "CFBundleVersion": "40", "CFBundleExecutable": "zzfixture",
            ], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try fm.copyItem(
            at: URL(fileURLWithPath: "/bin/echo"),
            to: contents.appendingPathComponent("MacOS/zzfixture"))
        try Data("\"zz.title\" = \"ZZ Fixture\";\n".utf8)
            .write(to: contents.appendingPathComponent("Resources/en.lproj/Localizable.strings"))
        try Data("zz".utf8).write(to: contents.appendingPathComponent("Resources/zz.txt"))
        try fm.createSymbolicLink(
            at: contents.appendingPathComponent("Resources/zz-link.txt"),
            withDestinationURL: URL(fileURLWithPath: "zz.txt"))
        return app
    }

    private func reference(_ fingerprint: String = "zz-fingerprint") -> BackupFactsLibrary.Reference {
        BackupFactsLibrary.Reference(key: "zzfixture.facts-zzzz", fingerprint: fingerprint)
    }

    @discardableResult
    private func record(_ facts: BundleFacts, _ reference: BackupFactsLibrary.Reference) -> Bool {
        BackupFactsLibrary.store(facts, at: BackupFactsLibrary.entry(for: reference))
    }

    private func held(_ reference: BackupFactsLibrary.Reference) -> BundleFacts? {
        BackupFactsLibrary.facts(at: BackupFactsLibrary.entry(for: reference))
    }

    /// Everything the report says above the timings, except the LOCALIZATION
    /// section — which is the one place a recorded side is meant to read
    /// differently, because it has no strings index to search. Asserted on its own
    /// below, and in `BundleDiffTests`.
    private func substanceOutsideLocalization(of report: String) -> [String] {
        var out: [String] = []
        var inLocalization = false
        for line in report.components(separatedBy: "\n") {
            if line.hasPrefix("TIMINGS") { break }
            if line.hasPrefix("LOCALIZATION") { inLocalization = true; continue }
            if inLocalization {
                guard line.isEmpty else { continue }
                inLocalization = false
            }
            out.append(line)
        }
        return out
    }

    /// The whole claim this feature rests on: a report built from what was recorded
    /// when the backup was written says the same things as one built by reading the
    /// backup. Anything dropped from `BundleFacts.CodingKeys` shows up here as a
    /// section that lost its content.
    @Test func whatWasRecordedSaysTheSameAsReadingTheBackup() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureApp(in: directory)
        let reference = reference()

        try await BackupFactsLibrary.$rootOverride.withValue(directory.appendingPathComponent("library")) {
            let facts = try BundleFactsReader.scan(root: app)
            #expect(record(facts, reference))

            let read = try await BundleDiff.report(
                old: app.path, new: app.path, oldLabel: "backup", newLabel: "installed").get()
            let fromLibrary = try await BundleDiff.report(
                old: app.path, new: app.path, oldLabel: "backup", newLabel: "installed",
                recordedOld: reference).get()

            // Vacuity guard: without this the two reports are equal because both
            // walked the bundle, and deleting the whole lookup leaves this green.
            #expect(fromLibrary.contains("read the recorded facts"))
            #expect(!read.contains("read the recorded facts"))
            #expect(substanceOutsideLocalization(of: fromLibrary)
                == substanceOutsideLocalization(of: read))

            // And in LOCALIZATION: the same finding, plus the reason the recorded
            // side cannot speak for the old binaries.
            #expect(fromLibrary.contains("  no change in 1 strings files"))
            #expect(read.contains("  no change in 1 strings files"))
            #expect(fromLibrary.contains("does not keep the strings index"))
            #expect(!read.contains("does not keep the strings index"))
        }
    }

    /// An entry answers for the copy it was written from and for no other. The
    /// fingerprint is the backup's manifest digest, so a re-taken backup of a
    /// changed app has a different one and the old entry is simply not found.
    @Test func anEntryIsNotFoundForADifferentCopy() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureApp(in: directory)

        try await BackupFactsLibrary.$rootOverride.withValue(directory.appendingPathComponent("library")) {
            let facts = try BundleFactsReader.scan(root: app)
            #expect(record(facts, reference("zz-first")))
            #expect(held(reference("zz-first")) != nil)
            #expect(held(reference("zz-second")) == nil)

            // …and a comparison asking with the wrong one reads the backup, rather
            // than failing or reporting nothing.
            let report = try await BundleDiff.report(
                old: app.path, new: app.path, oldLabel: "backup", newLabel: "installed",
                recordedOld: reference("zz-second")).get()
            #expect(!report.contains("read the recorded facts"))
            #expect(report.contains("\nTRUST SURFACE\n"))
        }
    }

    /// The format version is in the file's name, so entries written by a different
    /// one are not found rather than decoded and half-understood.
    @Test func anEntryFromAnotherFormatVersionIsNotFound() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureApp(in: directory)
        let reference = reference()

        try await BackupFactsLibrary.$rootOverride.withValue(directory.appendingPathComponent("library")) {
            let facts = try BundleFactsReader.scan(root: app)
            #expect(record(facts, reference))
            let entry = BackupFactsLibrary.entry(for: reference)
            #expect(entry.lastPathComponent
                == "\(reference.fingerprint).v\(BackupFactsLibrary.formatVersion).facts")

            let renamed = entry.deletingLastPathComponent().appendingPathComponent(
                "\(reference.fingerprint).v\(BackupFactsLibrary.formatVersion + 1).facts")
            try FileManager.default.moveItem(at: entry, to: renamed)
            #expect(held(reference) == nil)
        }
    }

    /// Retention is one, like the backups themselves.
    @Test func recordingACopySupersedesThePreviousOne() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureApp(in: directory)

        try await BackupFactsLibrary.$rootOverride.withValue(directory.appendingPathComponent("library")) {
            let facts = try BundleFactsReader.scan(root: app)
            #expect(record(facts, reference("zz-first")))
            #expect(record(facts, reference("zz-second")))
            let onDisk = try FileManager.default.contentsOfDirectory(
                at: BackupFactsLibrary.directory(forKey: reference().key), includingPropertiesForKeys: nil)
            #expect(onDisk.count == 1)
            #expect(held(reference("zz-first")) == nil)
            #expect(held(reference("zz-second")) != nil)

            BackupFactsLibrary.drop(forKey: reference().key)
            #expect(held(reference("zz-second")) == nil)
        }
    }

    /// The blob is the reason this is worth doing at all: it is what is left out,
    /// and what is read back must say so rather than present an empty index as a
    /// search that found nothing.
    @Test func theStringsIndexIsNotKeptAndTheFactsSayThatItIsNot() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureApp(in: directory)
        let reference = reference()

        try await BackupFactsLibrary.$rootOverride.withValue(directory.appendingPathComponent("library")) {
            let scanned = try BundleFactsReader.scan(root: app)
            #expect(scanned.stringsIndexed)
            #expect(!scanned.stringsBlob.isEmpty)
            #expect(record(scanned, reference))

            let stored = try #require(held(reference))
            #expect(stored.stringsBlob.isEmpty)
            #expect(!stored.stringsIndexed)
            // The parts that are kept, so a change that quietly drops one of them
            // from `CodingKeys` fails here as well as in the report comparison.
            #expect(stored.rootName == scanned.rootName)
            #expect(stored.files == scanned.files)
            #expect(stored.machO == scanned.machO)
            #expect(stored.bundles == scanned.bundles)
            #expect(stored.strings == scanned.strings)
            #expect(stored.bytesHashed == scanned.bytesHashed)

            let size = try FileManager.default.attributesOfItem(
                atPath: BackupFactsLibrary.entry(for: reference).path)[.size] as? Int ?? 0
            #expect(size < scanned.stringsBlob.count)
        }
    }
}
