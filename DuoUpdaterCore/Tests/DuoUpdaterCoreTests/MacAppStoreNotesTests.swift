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

/// The product-page scrape for an iOS-on-Mac app reads the latest Mac build's
/// version AND its "What's New" notes from the same `mostRecentVersion` shelf
/// item, so we can render the App Store changelog inline instead of a web view.
@Test func extractsMacVersionAndNotesFromShelf() {
    let src = MacAppStoreSource()
    let html = """
    <html><script type="application/json" id="shoebox">
    {"data":[{"data":{"shelfMapping":{"mostRecentVersion":{"items":[
      {"$kind":"TitledParagraph",
       "primarySubtitle":"Version 24.3.81",
       "secondarySubtitle":"Wed Mar 25 2026 15:05:17 GMT+0000",
       "text":"• Fixed a crash.\\n• Faster launch."}
    ]}}}}]}
    </script></html>
    """

    let info = src.extractMacVersionInfo(from: html)
    #expect(info?.version == "24.3.81")
    #expect(info?.notes == "• Fixed a crash.\n• Faster launch.")
}

/// The version is still extracted when the shelf carries no notes `text`, leaving
/// `notes` nil so the UI falls back gracefully.
@Test func extractsMacVersionWithoutNotes() {
    let src = MacAppStoreSource()
    let html = """
    <html><script type="application/json">
    {"data":[{"data":{"shelfMapping":{"mostRecentVersion":{"items":[
      {"primarySubtitle":"Version 1.0.0"}
    ]}}}}]}
    </script></html>
    """

    let info = src.extractMacVersionInfo(from: html)
    #expect(info?.version == "1.0.0")
    #expect(info?.notes == nil)
}

/// The "Version" label in the shelf is localized — a Chinese (or any non-English)
/// storefront returns "版本 16.109.3", which the old English-prefix strip left
/// unparsed (and so silently un-comparable). The numeric version must come out
/// regardless of the surrounding language.
@Test func extractsLocalizedVersionLabel() {
    let src = MacAppStoreSource()
    let html = """
    <html><script type="application/json" id="shoebox">
    {"data":[{"data":{"shelfMapping":{"mostRecentVersion":{"items":[
      {"primarySubtitle":"版本 16.109.3","text":"• 修复了若干问题。"}
    ]}}}}]}
    </script></html>
    """

    let info = src.extractMacVersionInfo(from: html)
    #expect(info?.version == "16.109.3")
    #expect(info?.notes == "• 修复了若干问题。")
}

/// `versionNumber(in:)` pulls a dotted-numeric run out of assorted localized
/// labels, and falls back to a bare integer for single-component versions.
@Test func parsesVersionNumberFromAssortedLabels() {
    #expect(MacAppStoreSource.versionNumber(in: "Version 26.21.73") == "26.21.73")
    #expect(MacAppStoreSource.versionNumber(in: "버전 1.2") == "1.2")
    #expect(MacAppStoreSource.versionNumber(in: "Versione 3") == "3")
    #expect(MacAppStoreSource.versionNumber(in: "no digits here") == nil)
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

/// The listing is localised, and two things read it: the "What's New" text we show,
/// and `AppStoreAXInstaller`, which must recognise the name App Store.app renders.
/// Without `lang` the API answers in the storefront's default — measured 2026-09-05,
/// same app and storefront: `country=us` gives "DingDing: Redefine Work in AI",
/// `country=us&lang=zh_cn` gives "钉钉 - AI时代的工作方式".
///
/// The API wants `language_region`, which is not the shape `Locale.preferredLanguages`
/// hands out. Chinese is the case that matters and the case that is easy to get wrong:
/// it is identified by *script* there, and the script — not the region — picks the
/// listing, so a Simplified-Chinese Mac in the US region still wants `zh_cn`.
@Test func asksTheLookupForTheUsersOwnLanguage() {
    #expect(MacAppStoreSource.storeLanguage(preferred: ["zh-Hans-US"], storefront: "us") == "zh_cn")
    #expect(MacAppStoreSource.storeLanguage(preferred: ["zh-Hans-CN"], storefront: "cn") == "zh_cn")
    #expect(MacAppStoreSource.storeLanguage(preferred: ["zh-Hant-TW"], storefront: "tw") == "zh_tw")
    #expect(MacAppStoreSource.storeLanguage(preferred: ["zh-Hant-HK"], storefront: "hk") == "zh_tw")
    #expect(MacAppStoreSource.storeLanguage(preferred: ["en-US"], storefront: "us") == "en_us")
    #expect(MacAppStoreSource.storeLanguage(preferred: ["ja-JP"], storefront: "jp") == "ja_jp")
    // No region of its own: ask in the storefront we are already asking.
    #expect(MacAppStoreSource.storeLanguage(preferred: ["fr"], storefront: "ca") == "fr_ca")
    // Nothing to name, nothing to send — which is exactly the old behaviour.
    #expect(MacAppStoreSource.storeLanguage(preferred: [], storefront: "us") == nil)
}
