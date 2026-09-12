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

/// The product-page scrape decides whether a wrapped iPhone/iPad app's latest
/// build can be installed on a Mac at all, so we can warn when one really did
/// drop Mac support instead of offering an update the store will refuse.
///
/// The three payloads below are the three live shapes measured 2026-09-12 (see
/// `MacAppStoreSource.MacCompatibilityReading` for the full 18-listing table);
/// each is the real `data[0].data` key layout, trimmed to the two fields the
/// parser reads.
///
/// The middle one is the regression: `isIOSBinaryMacOSCompatible` answers "does
/// the *iOS binary* run on macOS", so a developer who ADDS a native Mac build
/// flips it to `false` — indistinguishable, on that field alone, from one who
/// drops Mac support. Reading the flag by itself told a nowdex 1.1.0 user their
/// 1.1.2 update was impossible, on the day the vendor shipped the Mac build that
/// made it possible.
@Test func extractsMacCompatibilityVerdict() {
    let src = MacAppStoreSource()
    func page(_ inner: String) -> String {
        """
        <html><script type="application/json" id="shoebox">
        {"data":[{"data":\(inner)}]}
        </script></html>
        """
    }
    // Discord, us: no Mac binary, and the iOS binary is opted out of Mac.
    let noMacAtAll = page(
        """
        {"appPlatforms":["phone","pad"],"lockup":{"isIOSBinaryMacOSCompatible":false}}
        """)
    // nowdex, cn: ships its own Mac build, so the wrapper flag reads false.
    let nativeMacBuild = page(
        """
        {"appPlatforms":["mac","phone","pad"],"lockup":{"isIOSBinaryMacOSCompatible":false}}
        """)
    // Overcast, us: no Mac binary, but the iOS binary runs on Apple Silicon.
    let wrappedOnMac = page(
        """
        {"appPlatforms":["watch","phone","pad"],"lockup":{"isIOSBinaryMacOSCompatible":true}}
        """)
    let missing = page("{}")

    #expect(src.extractMacCompatibility(from: noMacAtAll).macSupported == false)
    #expect(src.extractMacCompatibility(from: nativeMacBuild).macSupported == true)
    #expect(src.extractMacCompatibility(from: wrappedOnMac).macSupported == true)
    #expect(src.extractMacCompatibility(from: missing).macSupported == nil)  // unknown ⇒ assume compatible
}

/// A `false` verdict takes both signals. With `appPlatforms` gone — Apple
/// renaming it, or a page shape we haven't seen — the flag alone is the majority
/// shape of Mac-SUPPORTED listings, so concluding "incompatible" from it would
/// hide real updates for every app that ships a native Mac build. Fail open.
@Test func aLoneIncompatibleFlagIsNotEnoughToRefuseAnUpdate() {
    let src = MacAppStoreSource()
    let flagOnly = """
    <html><script type="application/json" id="shoebox">
    {"data":[{"data":{"lockup":{"isIOSBinaryMacOSCompatible":false}}}]}
    </script></html>
    """
    #expect(src.extractMacCompatibility(from: flagOnly).macSupported == nil)
    #expect(src.extractMacCompatibility(from: flagOnly).readBothSignals == false)
}

/// `duo verify`'s wrapped-iOS sweep asks for BOTH shapes, not merely a usable
/// verdict. Either signal surviving alone still answers most listings, so a
/// sweep that settled for `macSupported != nil` would stay green through exactly
/// the half-drift it exists to catch.
@Test func theSweepDemandsBothCompatibilitySignals() {
    let src = MacAppStoreSource()
    func page(_ inner: String) -> String {
        "<html><script type=\"application/json\">{\"data\":[{\"data\":\(inner)}]}</script></html>"
    }
    let both = page(
        """
        {"appPlatforms":["mac","phone","pad"],"lockup":{"isIOSBinaryMacOSCompatible":false}}
        """)
    let platformsOnly = page(
        """
        {"appPlatforms":["mac","phone","pad"]}
        """)

    #expect(src.extractMacCompatibility(from: both).readBothSignals)
    // Still a verdict, but no longer a shape the sweep should call healthy.
    #expect(src.extractMacCompatibility(from: platformsOnly).macSupported == true)
    #expect(src.extractMacCompatibility(from: platformsOnly).readBothSignals == false)
}

/// A product page carries more than one lockup: `moreByDeveloper` items have the
/// same flag, for other apps entirely. Measured on nowdex's page 2026-09-12 —
/// four occurrences, three of them the developer's three other apps, all `true`
/// while nowdex's own is `false`. Anchoring at `data[0].data` is what keeps the
/// verdict about the app being checked; a looser search would read a neighbour.
@Test func readsThisListingsLockupNotTheDevelopersOtherApps() {
    let src = MacAppStoreSource()
    let html = """
    <html><script type="application/json" id="shoebox">
    {"data":[{"data":{
      "appPlatforms":["phone","pad"],
      "lockup":{"adamId":"1","isIOSBinaryMacOSCompatible":false},
      "shelfMapping":{"moreByDeveloper":{"items":[
        {"adamId":"2","isIOSBinaryMacOSCompatible":true},
        {"adamId":"3","isIOSBinaryMacOSCompatible":true}
      ]}}
    }}]}
    </script></html>
    """
    #expect(src.extractMacCompatibility(from: html).macSupported == false)
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
