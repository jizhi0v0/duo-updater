import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func catalogResolvesCuratedBundleIDs() {
    #expect(ChangelogCatalog.url(forBundleID: "com.mitchellh.ghostty")?.host == "ghostty.org")
    #expect(ChangelogCatalog.url(forBundleID: "com.electron.ollama")?
        .absoluteString == "https://github.com/ollama/ollama/releases")
    #expect(ChangelogCatalog.url(forBundleID: "com.steipete.codexbar")?
        .absoluteString == "https://github.com/steipete/CodexBar/releases")
    #expect(ChangelogCatalog.url(forBundleID: "com.nssurge.surge-mac")?
        .absoluteString == "https://nssurge.com/support/mac/release-notes")
}

@Test func catalogLookupIsCaseInsensitive() {
    // Bundle ids are conventionally lowercase but not guaranteed; match anyway.
    #expect(ChangelogCatalog.url(forBundleID: "com.steipete.CodexBar") != nil)
    #expect(ChangelogCatalog.url(forBundleID: "COM.MITCHELLH.GHOSTTY") != nil)
}

@Test func catalogMissesUnknownAndNil() {
    #expect(ChangelogCatalog.url(forBundleID: "com.example.nope") == nil)
    #expect(ChangelogCatalog.url(forBundleID: nil) == nil)
}
