import Foundation
import Testing
@testable import DuoUpdaterCore

/// `ContentsPayload`, the shape a vendor update takes when it ships the INSIDE
/// of an input method rather than the app: a zip of scripts wrapped around a
/// second zip holding a bare `Contents<version>` directory.
///
/// The fixtures here are built to the layout measured on SogouInput 6.25.1.11973
/// — three sibling scripts beside the payload archive, one directory inside it.
/// What the real package cannot give a test is the ways it could be malformed,
/// and those are what the guards are for, so most of this suite is refusals.
@Suite struct ContentsPayloadTests {

    // MARK: - The happy shape

    /// The measured layout, end to end: two levels of zip, and out of it a
    /// bundle whose `Contents` is the directory the inner archive held — under
    /// the name the INSTALLED app has, not one the archive chose.
    @Test func assemblesABundleFromTheVendorsDoubleZip() async throws {
        try await withScratch { dir in
            let outer = try await makeVendorPackage(
                in: dir, contentsDirectory: "Contents6.25.1.11973",
                payloadFiles: ["Info.plist": "<plist/>", "MacOS/SogouInput": "x"],
                siblings: ["pre.sh", "post.sh", "switch.sh"])

            let app = try await ContentsPayload.assemble(
                outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))

            #expect(app.lastPathComponent == "SogouInput.app")
            let contents = app.appendingPathComponent("Contents")
            #expect(FileManager.default.fileExists(
                atPath: contents.appendingPathComponent("Info.plist").path))
            #expect(FileManager.default.fileExists(
                atPath: contents.appendingPathComponent("MacOS/SogouInput").path))
            // The versioned name is gone: what a bundle's interior is called is
            // not the vendor's to decide, and `rotateContents` reads `Contents`.
            #expect(!FileManager.default.fileExists(
                atPath: app.appendingPathComponent("Contents6.25.1.11973").path))
        }
    }

    /// The vendor's scripts are expected company in the outer archive and must
    /// not make it ambiguous — only the MATCH has to be unique there. This is the
    /// half of the pair below: tightening the outer lookup to "one entry" would
    /// refuse every real package.
    @Test func theVendorsScriptsBesideThePayloadAreNotAnObstacle() async throws {
        try await withScratch { dir in
            let outer = try await makeVendorPackage(
                in: dir, contentsDirectory: "Contents6.25.1.11973",
                payloadFiles: ["Info.plist": "<plist/>"],
                siblings: ["pre.sh", "post.sh", "switch.sh", "unzip", "notes.txt"])
            let app = try await ContentsPayload.assemble(
                outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            #expect(FileManager.default.fileExists(
                atPath: app.appendingPathComponent("Contents/Info.plist").path))
        }
    }

    // MARK: - Refusals

    /// The inner archive carries the replacement bundle's interior and nothing
    /// else. A second member means the package is not the shape the recipe
    /// describes, and taking the match anyway would install a `Contents` while
    /// silently dropping whatever was meant to go with it.
    @Test func refusesAnInnerArchiveHoldingMoreThanTheContentsDirectory() async throws {
        try await withScratch { dir in
            let outer = try await makeVendorPackage(
                in: dir, contentsDirectory: "Contents6.25.1.11973",
                payloadFiles: ["Info.plist": "<plist/>"],
                siblings: ["pre.sh"],
                extraInnerEntries: ["Resources/extra.bin": "x"])
            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    /// Two members match the pattern: the package has changed shape under a
    /// recipe that still describes the old one. Picking either would be a guess
    /// about which is the update.
    @Test func refusesTwoArchivesMatchingTheInnerPattern() async throws {
        try await withScratch { dir in
            let outer = try await makeVendorPackage(
                in: dir, contentsDirectory: "Contents6.25.1.11973",
                payloadFiles: ["Info.plist": "<plist/>"],
                siblings: ["pre.sh"],
                decoyArchiveNamed: "Contents6.24.1.11676.zip")
            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    /// Nothing matches — the vendor renamed the payload, or the recipe's pattern
    /// was wrong from the start. Either way it is a refusal with the names in it,
    /// not an install.
    @Test func refusesWhenNothingMatchesTheInnerPattern() async throws {
        try await withScratch { dir in
            let outer = try await makeVendorPackage(
                in: dir, contentsDirectory: "Contents6.25.1.11973",
                payloadFiles: ["Info.plist": "<plist/>"], siblings: ["pre.sh"])
            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^payload\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    /// The directory that becomes a bundle's interior is chosen by an anchored
    /// name, so a longer one that merely starts `Contents` is not it. Without the
    /// anchor this directory would be adopted as the app's insides.
    ///
    /// The archive around it keeps a name the recipe's pattern accepts, which is
    /// the whole point of the fixture: a first version of this test named the
    /// archive after the directory, so it was the OUTER lookup that refused and
    /// the anchor was never exercised — it passed with the anchors removed.
    @Test func refusesADirectoryWhoseNameOnlyStartsWithContents() async throws {
        try await withScratch { dir in
            let outer = try await makeVendorPackage(
                in: dir, contentsDirectory: "Contents6.25.1.11973.attacker",
                innerArchiveName: "Contents6.25.1.11973.zip",
                payloadFiles: ["Info.plist": "<plist/>"], siblings: ["pre.sh"])
            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    /// A symlink named like the payload. Accepted, it would make the assembled
    /// bundle's `Contents` a link to somewhere else on disk — two steps upstream
    /// of a swap into `/Library/Input Methods`.
    @Test func refusesASymlinkStandingInForThePayload() async throws {
        try await withScratch { dir in
            let staging = dir.appendingPathComponent("inner-staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let elsewhere = dir.appendingPathComponent("elsewhere")
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: staging.appendingPathComponent("Contents6.25.1.11973"), withDestinationURL: elsewhere)
            let innerZip = dir.appendingPathComponent("Contents6.25.1.11973.zip")
            try await zip(directory: staging, into: innerZip)

            let outerStaging = dir.appendingPathComponent("outer-staging")
            try FileManager.default.createDirectory(at: outerStaging, withIntermediateDirectories: true)
            try FileManager.default.moveItem(
                at: innerZip, to: outerStaging.appendingPathComponent("Contents6.25.1.11973.zip"))
            try Data("#!/bin/sh\n".utf8).write(to: outerStaging.appendingPathComponent("pre.sh"))
            let outer = dir.appendingPathComponent("autosetup.zip")
            try await zip(directory: outerStaging, into: outer)

            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    /// A plain FILE where the bundle's interior should be. Reachable without any
    /// symlink — a vendor could ship `Contents6.25` as a file — and the only
    /// thing that catches it is the kind check: the name matches and the
    /// containment check is happy.
    @Test func refusesAFileNamedLikeTheContentsDirectory() async throws {
        try await withScratch { dir in
            let fm = FileManager.default
            let innerStaging = dir.appendingPathComponent("inner-staging")
            try fm.createDirectory(at: innerStaging, withIntermediateDirectories: true)
            try Data("not a directory".utf8).write(
                to: innerStaging.appendingPathComponent("Contents6.25.1.11973"))

            let outerStaging = dir.appendingPathComponent("outer-staging")
            try fm.createDirectory(at: outerStaging, withIntermediateDirectories: true)
            try await zip(
                directory: innerStaging,
                into: outerStaging.appendingPathComponent("Contents6.25.1.11973.zip"))
            try Data("#!/bin/sh\n".utf8).write(to: outerStaging.appendingPathComponent("pre.sh"))
            let outer = dir.appendingPathComponent("autosetup.zip")
            try await zip(directory: outerStaging, into: outer)

            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    /// A symlink at the OUTER level, pointing at a real archive that IS inside
    /// the extraction — so containment has nothing to say and the symlink guard
    /// is the only thing left standing.
    ///
    /// Its sibling above (`refusesASymlinkStandingInForThePayload`) is caught by
    /// the containment check instead, because its target is outside; with the
    /// symlink guard removed that test still passes and this one does not.
    @Test func refusesASymlinkedInnerArchive() async throws {
        try await withScratch { dir in
            let fm = FileManager.default
            let innerStaging = dir.appendingPathComponent("inner-staging")
            let payload = innerStaging.appendingPathComponent("Contents6.25.1.11973")
            try fm.createDirectory(at: payload, withIntermediateDirectories: true)
            try Data("<plist/>".utf8).write(to: payload.appendingPathComponent("Info.plist"))

            let outerStaging = dir.appendingPathComponent("outer-staging")
            let hidden = outerStaging.appendingPathComponent("stuff")
            try fm.createDirectory(at: hidden, withIntermediateDirectories: true)
            try await zip(directory: innerStaging, into: hidden.appendingPathComponent("real.zip"))
            try fm.createSymbolicLink(
                atPath: outerStaging.appendingPathComponent("Contents6.25.1.11973.zip").path,
                withDestinationPath: "stuff/real.zip")
            try Data("#!/bin/sh\n".utf8).write(to: outerStaging.appendingPathComponent("pre.sh"))
            let outer = dir.appendingPathComponent("autosetup.zip")
            try await zip(directory: outerStaging, into: outer)

            await #expect(throws: ContentsPayload.PayloadError.self) {
                try await ContentsPayload.assemble(
                    outerArchive: outer, innerArchivePattern: #"^Contents[0-9.]+\.zip$"#,
                    bundleName: "SogouInput", workDir: dir.appendingPathComponent("work"))
            }
        }
    }

    // MARK: - Fixtures

    /// Build the measured package shape: `<contentsDirectory>/` zipped into
    /// `<contentsDirectory>.zip`, that archive zipped again beside `siblings`.
    /// Returns the outer archive.
    private func makeVendorPackage(
        in dir: URL,
        contentsDirectory: String,
        innerArchiveName: String? = nil,
        payloadFiles: [String: String],
        siblings: [String],
        extraInnerEntries: [String: String] = [:],
        decoyArchiveNamed decoy: String? = nil
    ) async throws -> URL {
        let fm = FileManager.default
        let innerStaging = dir.appendingPathComponent("inner-staging")
        let payload = innerStaging.appendingPathComponent(contentsDirectory)
        for (relative, body) in payloadFiles {
            let file = payload.appendingPathComponent(relative)
            try fm.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(body.utf8).write(to: file)
        }
        for (relative, body) in extraInnerEntries {
            let file = innerStaging.appendingPathComponent(relative)
            try fm.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(body.utf8).write(to: file)
        }

        let outerStaging = dir.appendingPathComponent("outer-staging")
        try fm.createDirectory(at: outerStaging, withIntermediateDirectories: true)
        // The archive's name and the directory it holds are set separately: the
        // recipe's pattern selects the former and the guard inside reads the
        // latter, so a fixture that moved them together could not tell which of
        // the two refused a malformed package.
        let innerName = innerArchiveName ?? "\(contentsDirectory).zip"
        try await zip(
            directory: innerStaging, into: outerStaging.appendingPathComponent(innerName))
        if let decoy {
            try fm.copyItem(
                at: outerStaging.appendingPathComponent(innerName),
                to: outerStaging.appendingPathComponent(decoy))
        }
        for sibling in siblings {
            try Data("#!/bin/sh\n".utf8).write(to: outerStaging.appendingPathComponent(sibling))
        }
        let outer = dir.appendingPathComponent("autosetup.zip")
        try await zip(directory: outerStaging, into: outer)
        return outer
    }

    /// Zip a directory's CONTENTS (not the directory itself), which is how both
    /// of the vendor's archives are built.
    private func zip(directory: URL, into archive: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", "-X", "--symlinks", archive.path, "."]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func withScratch(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentsPayloadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }
}
