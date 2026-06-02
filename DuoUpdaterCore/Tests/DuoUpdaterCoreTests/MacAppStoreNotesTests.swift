import Testing
import Foundation
@testable import DuoUpdaterCore

/// Decoding coverage for the iTunes lookup payload's `releaseNotes` field — the
/// "What's New" text we surface as App Store changelogs. The newline-delimited
/// layout must survive decoding intact (we render it as plain text, not HTML).
@Test func decodesReleaseNotesPreservingNewlines() throws {
    let json = """
    { "version": "1.2.3",
      "trackViewUrl": "https://apps.apple.com/app/id123",
      "trackId": 123,
      "kind": "mac-software",
      "releaseNotes": "Bug fixes:\\n• Fixed a crash\\n• Faster launch" }
    """.data(using: .utf8)!

    let result = try JSONDecoder().decode(MacAppStoreSource.LookupResult.self, from: json)

    #expect(result.isNativeMac)
    #expect(result.releaseNotes == "Bug fixes:\n• Fixed a crash\n• Faster launch")
}

/// The product-page scrape reads Apple's `isIOSBinaryMacOSCompatible` flag for a
/// wrapped iPhone/iPad app, so we can warn when the latest build dropped Mac
/// support (e.g. Aqara Home: a newer version exists but won't install here).
@Test func extractsMacCompatibilityFlag() {
    let src = MacAppStoreSource()
    let incompatible = """
    <html><script type="application/json" id="shoebox">
    {"data":[{"data":{"lockup":{"isIOSBinaryMacOSCompatible":false}}}]}
    </script></html>
    """
    let compatible = incompatible.replacingOccurrences(of: "false", with: "true")
    let missing = "<html><script type=\"application/json\">{\"data\":[{\"data\":{}}]}</script></html>"

    #expect(src.extractMacCompatible(from: incompatible) == false)
    #expect(src.extractMacCompatible(from: compatible) == true)
    #expect(src.extractMacCompatible(from: missing) == nil)  // unknown ⇒ assume compatible
}

/// A listing with no `releaseNotes` key decodes fine, leaving the field nil so the
/// UI falls back to "no changelog".
@Test func releaseNotesAbsentDecodesToNil() throws {
    let json = """
    { "version": "1.0", "trackId": 1, "kind": "mac-software" }
    """.data(using: .utf8)!

    let result = try JSONDecoder().decode(MacAppStoreSource.LookupResult.self, from: json)

    #expect(result.releaseNotes == nil)
}
