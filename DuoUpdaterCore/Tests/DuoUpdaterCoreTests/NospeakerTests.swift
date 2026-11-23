import CryptoKit
import Darwin
import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct NospeakerTests {
    private enum FixtureError: Error { case zip, unexpectedRequest(URL) }

    // ZIP fixtures still spawn tar under the fully parallel Core suite. Keep
    // the production refresh deadline out of tests that assert lookup results.
    private let fixtureLookupBudget: Duration = .seconds(300)

    private func release(_ tag: String, zip: Data, includesDigest: Bool = true) throws -> Data {
        let sha = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        var asset = ["name": "nospeaker.zip"]
        if includesDigest { asset["digest"] = "sha256:\(sha)" }
        return try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": false, "prerelease": false, "assets": [asset],
            "body": "Initial release.\n\n- Release note", "published_at": "2026-11-22T12:06:00Z"
        ])
    }

    private func archive(in root: URL, name: String, binary: Data) async throws -> Data {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try binary.write(to: folder.appendingPathComponent("nospeaker"))
        let archive = folder.appendingPathComponent("fixture.zip")
        let result = try await ChildProcess.run(
            "/usr/bin/zip", ["-q", archive.path, "nospeaker"], workingDirectory: folder,
            standardOutput: .discard, standardError: .discard, onCancel: .terminateChild)
        guard result.succeeded else { throw FixtureError.zip }
        return try Data(contentsOf: archive)
    }

    @Test func numericStableTagsAndStructuredNotes() async throws {
        for tag in ["v1.0", "v1.0.1", "v2.0"] {
            #expect(NospeakerRelease.isStableTag(tag))
        }
        for tag in ["1.0", "v1", "v1.0-rc.1", "v1.0.0.1", "v1.0\n", "v1.0/extra"] {
            #expect(!NospeakerRelease.isStableTag(tag))
        }
        let payload = try release("v1.0", zip: Data())
        let notes = try await NospeakerRelease(fetch: { _, _, _, _ in
            Data("[".utf8) + payload + Data("]".utf8)
        }).notes(force: false)
        #expect(notes.entries.map(\.version) == ["1.0"])
    }

    @Test func identifiesAnUnversionedBinaryThenUpdatesWithAPinnedVerifiedZip() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installed = home.appendingPathComponent(".local/bin/nospeaker")
        let old = Data("first signed binary fixture".utf8)
        let new = Data("second signed binary fixture".utf8)
        let managed = home.appendingPathComponent("managed")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
        let acl = try await ChildProcess.run(
            "/bin/chmod", ["+a", "everyone deny execute,file_inherit,only_inherit", managed.path],
            onCancel: .terminateChild)
        try #require(acl.succeeded)
        let inherited = managed.appendingPathComponent("nospeaker")
        try old.write(to: inherited)
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: inherited.path)
        try FileManager.default.moveItem(at: inherited, to: installed)
        let originalACL = try await aclEntries(at: installed)
        try #require(originalACL.contains { $0.contains("inherited") && $0.contains("deny execute") })
        let oldZIP = try await archive(in: home, name: "old", binary: old)
        let newZIP = try await archive(in: home, name: "new", binary: new)
        let oldRelease = try release("v1.1", zip: oldZIP)
        let newRelease = try release("v1.2", zip: newZIP)
        let missingDigest = try release("v1.2", zip: newZIP, includesDigest: false)
        let fingerprints = home.appendingPathComponent("fingerprints")

        let original = NospeakerProvider(home: home, fingerprints: fingerprints, release: NospeakerRelease(
            fetch: { url, purpose, _, _ in
                switch url.lastPathComponent {
                case "latest": return oldRelease
                case "nospeaker.zip":
                    #expect(purpose == .versionCheck)
                    return oldZIP
                default: throw FixtureError.unexpectedRequest(url)
                }
            }, isVendorBinary: { _ in true }), lookupBudget: fixtureLookupBudget)
        let sighting = try #require(await original.scan().first)
        #expect(sighting.version == nil)
        let current = try #require(await original.check().statuses.first)
        #expect(current.state == .upToDate)
        #expect(current.installedVersion == "1.1")
        #expect(await original.scan().first?.version == "1.1")

        let noChecksum = NospeakerProvider(home: home, fingerprints: fingerprints, release: NospeakerRelease(
            fetch: { url, _, _, _ in
                guard url.lastPathComponent == "latest" else { throw FixtureError.unexpectedRequest(url) }
                return missingDigest
            }, isVendorBinary: { _ in true }))
        let withheld = try #require(await noChecksum.check().statuses.first)
        #expect(withheld.state == .updateAvailable)
        #expect(withheld.oneClick == nil)
        #expect(withheld.withheld == .unverified)

        for validDownload in [false, true] {
            let provider = NospeakerProvider(home: home, fingerprints: fingerprints, release: NospeakerRelease(
                fetch: { url, purpose, force, _ in
                    if url.lastPathComponent == "latest" { return newRelease }
                    #expect(url.absoluteString == "https://github.com/os6/nospeaker/releases/download/v1.2/nospeaker.zip")
                    #expect(purpose == .install)
                    #expect(force)
                    return validDownload ? newZIP : oldZIP
                }, isVendorBinary: { _ in true }))
            let offer = try #require(await provider.check().statuses.first)
            #expect(offer.state == .updateAvailable)
            #expect(offer.oneClick?.arguments == ["install", installed.path])
            if validDownload {
                try await expectRefusalWhileLocked(installed, provider: provider, offer: offer)
                #expect(try Data(contentsOf: installed) == old)

                let digest = SHA256.hash(data: new).map { String(format: "%02x", $0) }.joined()
                let unusableRecord = fingerprints.appendingPathComponent(digest)
                try FileManager.default.createDirectory(at: unusableRecord, withIntermediateDirectories: false)
                let blocked = await provider.update(offer) { _ in }
                guard case .failed = blocked else {
                    Issue.record("Expected fingerprint persistence to block replacement, got \(blocked)")
                    return
                }
                #expect(try Data(contentsOf: installed) == old)
                try FileManager.default.removeItem(at: unusableRecord)
            }

            let result = await provider.update(offer) { _ in }
            if validDownload {
                #expect(result == .updated(version: "1.2"))
                #expect(try Data(contentsOf: installed) == new)
                #expect(await provider.scan().first?.version == "1.2")
                let attributes = try FileManager.default.attributesOfItem(atPath: installed.path)
                #expect(attributes[.posixPermissions] as? Int == 0o750)
                #expect(try await aclEntries(at: installed) == originalACL)
                #expect(await provider.update(offer) { _ in } != .updated(version: "1.2"))
            } else {
                #expect(result == .failed(message: "The nospeaker download did not match its published checksum.", output: ""))
                #expect(try Data(contentsOf: installed) == old)
            }
        }
    }

    @Test func aManualOlderCopyIsIdentifiedFromReleaseHistory() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let manualBin = home.appendingPathComponent("manual-bin")
        try FileManager.default.createDirectory(at: manualBin, withIntermediateDirectories: false)
        let manual = manualBin.appendingPathComponent("nospeaker")
        let old = Data("official historical fixture".utf8)
        let new = Data("official latest fixture".utf8)
        try old.write(to: manual)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manual.path)
        let oldZIP = try await archive(in: home, name: "old", binary: old)
        let newZIP = try await archive(in: home, name: "new", binary: new)
        let oldRelease = try release("v1.1", zip: oldZIP)
        let newRelease = try release("v1.2", zip: newZIP)
        let fingerprints = home.appendingPathComponent("fingerprints")
        let provider = NospeakerProvider(home: home, fingerprints: fingerprints, release: NospeakerRelease(
            fetch: { url, _, _, _ in
                switch url.path {
                case "/repos/os6/nospeaker/releases/latest": return newRelease
                case "/repos/os6/nospeaker/releases":
                    return Data("[".utf8) + newRelease + Data(",".utf8) + oldRelease + Data("]".utf8)
                case "/os6/nospeaker/releases/download/v1.2/nospeaker.zip": return newZIP
                case "/os6/nospeaker/releases/download/v1.1/nospeaker.zip": return oldZIP
                default: throw FixtureError.unexpectedRequest(url)
                }
            }, isVendorBinary: { _ in true }), manualBin: manualBin, lookupBudget: fixtureLookupBudget)
        let offer = try #require(await provider.check().statuses.first)
        #expect(offer.path == manual.path)
        #expect(offer.installedVersion == "1.1")
        #expect(offer.latestVersion == "1.2")
        #expect(offer.state == .updateAvailable)
        #expect(offer.oneClick != nil)
        #expect(await provider.scan().first?.version == "1.1")

        let vendorBin = home.appendingPathComponent(".local/bin")
        try FileManager.default.removeItem(at: vendorBin)
        try FileManager.default.createSymbolicLink(at: vendorBin, withDestinationURL: manualBin)
        let aliased = await provider.check().statuses
        #expect(aliased.count == 1)
        let aliasedOffer = try #require(aliased.first)
        #expect(aliasedOffer.path == vendorBin.appendingPathComponent("nospeaker").path)
        #expect(await provider.update(aliasedOffer) { _ in } == .updated(version: "1.2"))
        #expect(try Data(contentsOf: manual) == new)

        // A vendor-bin alias that ultimately reaches a file symlink may show a
        // version, but the updater must leave the link and its target alone.
        let outside = home.appendingPathComponent("unpacked")
        try FileManager.default.moveItem(at: manual, to: outside)
        try FileManager.default.createSymbolicLink(at: manual, withDestinationURL: outside)
        let laterRelease = try release("v1.3", zip: newZIP)
        let linkedProvider = NospeakerProvider(home: home, fingerprints: fingerprints, release: NospeakerRelease(
            fetch: { url, _, _, _ in
                guard url.lastPathComponent == "latest" else { throw FixtureError.unexpectedRequest(url) }
                return laterRelease
            }, isVendorBinary: { _ in true }), manualBin: manualBin)
        let linked = try #require(await linkedProvider.check().statuses.first)
        #expect(linked.state == .updateAvailable)
        #expect(linked.installedVersion == "1.2")
        #expect(linked.withheld == .unsupportedInstaller)
        #expect(linked.oneClick == nil)
    }

    @Test func historyRateLimitPreservesTheCopyAlreadyMatchedToLatest() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let vendor = home.appendingPathComponent(".local/bin/nospeaker")
        try Data("uncached older fixture".utf8).write(to: vendor)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vendor.path)
        let manualBin = home.appendingPathComponent("manual-bin")
        try FileManager.default.createDirectory(at: manualBin, withIntermediateDirectories: false)
        let manual = manualBin.appendingPathComponent("nospeaker")
        let new = Data("latest fixture".utf8)
        try new.write(to: manual)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manual.path)
        let zip = try await archive(in: home, name: "latest", binary: new)
        let payload = try release("v1.2", zip: zip)
        let provider = NospeakerProvider(home: home, fingerprints: home.appendingPathComponent("fingerprints"),
            release: NospeakerRelease(fetch: { url, _, _, _ in
                switch url.lastPathComponent {
                case "latest": return payload
                case "nospeaker.zip": return zip
                case "releases": throw CLIToolReleaseNotesError.rateLimited
                default: throw FixtureError.unexpectedRequest(url)
                }
            }, isVendorBinary: { _ in true }), manualBin: manualBin, lookupBudget: fixtureLookupBudget)
        let statuses = await provider.check().statuses
        #expect(statuses.first { $0.path == manual.path }?.state == .upToDate)
        #expect(statuses.first { $0.path == vendor.path }?.withheld == .rateLimited)
    }

    @Test func doesNotStartHistoricalRequestsWhenTheLookupBudgetIsExhausted() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".local/bin/nospeaker")
        try Data("unrecognized official fixture".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let payload = try release("v1.2", zip: Data())
        let provider = NospeakerProvider(home: home, fingerprints: home.appendingPathComponent("fingerprints"),
            release: NospeakerRelease(fetch: { url, _, _, _ in
                guard url.lastPathComponent == "latest" else {
                    Issue.record("Started a lookup after its deadline: \(url)")
                    throw FixtureError.unexpectedRequest(url)
                }
                return payload
            }, isVendorBinary: { _ in true }), lookupBudget: .zero)
        let status = try #require(await provider.check().statuses.first)
        #expect(status.latestVersion == "1.2")
        #expect(status.withheld == .versionUnreadable)
    }

    @Test func aSameNamedExecutableDoesNotCreateARow() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent(".local/bin/nospeaker")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: path)
        let provider = NospeakerProvider(home: home, fingerprints: home.appendingPathComponent("fingerprints"),
            release: NospeakerRelease(fetch: { url, _, _, _ in
                Issue.record("Unexpected network request to \(url)")
                throw FixtureError.unexpectedRequest(url)
            }))
        #expect(await provider.scan().isEmpty)
        #expect(await provider.check().statuses.isEmpty)
    }

    private func expectRefusalWhileLocked(
        _ installed: URL, provider: NospeakerProvider, offer: CLIToolStatus
    ) async throws {
        let fd = open(installed.path, O_RDONLY)
        try #require(fd >= 0)
        defer { close(fd) }
        try #require(flock(fd, LOCK_EX | LOCK_NB) == 0)
        let result = await provider.update(offer) { _ in }
        #expect(result == .busy("Another update is replacing this executable. Try again once it finishes."))
    }

    private func aclEntries(at file: URL) async throws -> [Substring] {
        let result = try await ChildProcess.run("/bin/ls", ["-le", file.path], onCancel: .terminateChild)
        try #require(result.succeeded)
        return Array(String(decoding: result.standardOutput, as: UTF8.self).split(separator: "\n").dropFirst())
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("duo-nospeaker-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/bin"), withIntermediateDirectories: true)
        return URL(fileURLWithPath: try #require(CLIToolProcesses.realpath(home.path)), isDirectory: true)
    }
}
