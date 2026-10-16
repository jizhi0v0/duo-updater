import Foundation
import Testing
@testable import DuoUpdaterCore

/// A vendor that answers part of its requests with its home page (corkmac.app:
/// HTTP 200, the site's HTML, for any URL including the zip) gets the archive
/// download retried instead of handing the page to the extractor.
struct VendorArchiveHTMLRetryTests {
    private func file(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-retry-\(UUID().uuidString)")
        try Data(bytes).write(to: url)
        return url
    }

    private func file(_ text: String) throws -> URL { try file(Array(text.utf8)) }

    @Test func recognisesAWebPageButNotAnArchive() throws {
        // The shape corkmac.app serves, and the other common openings.
        #expect(VendorInstaller.isHTMLDocument(at: try file("<!DOCTYPE html>\n<html lang=\"en\"><head><title>Cork: The Homebrew GUI</title>")))
        #expect(VendorInstaller.isHTMLDocument(at: try file("\n  <html><head><title>Index</title>")))
        #expect(VendorInstaller.isHTMLDocument(at: try file([0xEF, 0xBB, 0xBF] + Array("<!doctype HTML>".utf8))))
        // Archives: zip local header, gzip, and a disk image's leading zeros.
        #expect(!VendorInstaller.isHTMLDocument(at: try file([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00])))
        #expect(!VendorInstaller.isHTMLDocument(at: try file([0x1F, 0x8B, 0x08, 0x00])))
        #expect(!VendorInstaller.isHTMLDocument(at: try file([UInt8](repeating: 0, count: 64))))
        // Not HTML just for mentioning it, and nothing to read is not HTML.
        #expect(!VendorInstaller.isHTMLDocument(at: try file("PK<html>")))
        #expect(!VendorInstaller.isHTMLDocument(at: try file([UInt8]())))
        #expect(!VendorInstaller.isHTMLDocument(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")))
    }

    @Test func aWebPageIsFetchedAgainAndDeleted() async throws {
        let page = try file("<!DOCTYPE html><title>Cork: …</title>")
        let zip = try file([0x50, 0x4B, 0x03, 0x04])
        var answers = [page, zip]
        var calls = 0
        let got = try await VendorInstaller.fetchArchive(maxAttempts: 4) {
            calls += 1
            return answers.removeFirst()
        }
        #expect(got == zip)
        #expect(calls == 2)
        #expect(!FileManager.default.fileExists(atPath: page.path))
    }

    @Test func givesUpAfterTheLastAttemptAndHandsBackThePage() async throws {
        var calls = 0
        var last: URL?
        let got = try await VendorInstaller.fetchArchive(maxAttempts: 4) {
            calls += 1
            last = try file("<!DOCTYPE html>")
            return last!
        }
        #expect(calls == 4)
        #expect(got == last)
        #expect(FileManager.default.fileExists(atPath: got.path))
    }

    @Test func oneAttemptMeansNoRetry() async throws {
        var calls = 0
        _ = try await VendorInstaller.fetchArchive(maxAttempts: 1) {
            calls += 1
            return try file("<!DOCTYPE html>")
        }
        #expect(calls == 1)
    }
}
