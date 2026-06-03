import Testing
import Foundation
@testable import DuoUpdaterCore

/// The download TLS gate. Every installer routes its download through
/// `Downloader.download`, which calls `SecureScheme.requireSecureDownload` first,
/// so this is the one place a plaintext-http payload is refused.
struct SecureSchemeTests {

    @Test func httpsIsAllowed() throws {
        try SecureScheme.requireSecureDownload(URL(string: "https://example.com/app.zip")!)
        // Case-insensitive on the scheme.
        try SecureScheme.requireSecureDownload(URL(string: "HTTPS://example.com/app.zip")!)
    }

    @Test func plaintextHTTPIsRefused() {
        #expect(throws: SecureScheme.SchemeError.self) {
            try SecureScheme.requireSecureDownload(URL(string: "http://example.com/app.zip")!)
        }
    }

    @Test func otherSchemesAreRefused() {
        for raw in ["ftp://example.com/a.zip", "file:///tmp/a.zip", "data:text/plain,hi"] {
            #expect(throws: SecureScheme.SchemeError.self) {
                try SecureScheme.requireSecureDownload(URL(string: raw)!)
            }
        }
    }

    @Test func errorNamesTheHost() {
        do {
            try SecureScheme.requireSecureDownload(URL(string: "http://dl.example.com/x")!)
            Issue.record("expected a throw")
        } catch let error as SecureScheme.SchemeError {
            #expect(error.errorDescription?.contains("dl.example.com") == true)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
