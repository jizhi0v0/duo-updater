import Foundation
import Testing
@testable import DuoUpdaterCore

struct LocalizedAppNameTests {
    private func fixture(
        rawName: String = "MediaCenter",
        names: [String: [String: String]], wrapped: Bool = false
    ) throws -> (root: URL, app: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Engine.app")
        let interior = wrapped ? app.appendingPathComponent("Wrapper/Inner.app")
            : app.appendingPathComponent("Contents")
        let resources = wrapped ? interior : interior.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: String] = [
            "CFBundleIdentifier": "com.example.localized-player",
            "CFBundleName": rawName, "CFBundleDisplayName": rawName,
            "CFBundleShortVersionString": "1.0", "CFBundleDevelopmentRegion": "en",
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: interior.appendingPathComponent("Info.plist"))
        for (language, values) in names {
            let lproj = resources.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
                .write(to: lproj.appendingPathComponent("InfoPlist.strings"))
        }
        if wrapped {
            try FileManager.default.createSymbolicLink(
                at: app.appendingPathComponent("WrappedBundle"), withDestinationURL: interior)
        }
        return (root, app)
    }

    private func scan(_ app: URL, languages: [String]) throws -> InstalledApp {
        try #require(AppScanner(
            locations: [], testflight: TestFlightInventory(macRows: []),
            preferredLanguages: languages).scan(bundlesAt: [app]).first)
    }

    @Test func localizedBrandOverridesTheInternalProjectName() throws {
        // Same metadata shape as the official VidHub package, deliberately using
        // a different bundle ID so this cannot pass through a product alias.
        let f = try fixture(names: ["en": ["CFBundleDisplayName": "VidHub"]])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(try scan(f.app, languages: ["en-US"]).name == "VidHub")
    }

    @Test func legacyChineseLocalizationFollowsTheRequestedLanguage() throws {
        // Official Baidu Netdisk uses zh_CN.lproj rather than zh-Hans.lproj.
        let f = try fixture(rawName: "BaiduNetdisk_mac", names: [
            "en": ["CFBundleDisplayName": "BaiduNetdisk"],
            "zh_CN": ["CFBundleDisplayName": "百度网盘"],
        ])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(try scan(f.app, languages: ["zh-Hans-US", "en"]).name == "百度网盘")
        #expect(try scan(f.app, languages: ["en-US"]).name == "BaiduNetdisk")
    }

    @Test func blankLocalizedDisplayNameFallsThroughToLocalizedBundleName() throws {
        let f = try fixture(rawName: "", names: ["en": [
            "CFBundleDisplayName": " \u{200E} ", "CFBundleName": "\u{200E}Readable",
        ]])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(try scan(f.app, languages: ["en"]).name == "Readable")
    }

    @Test func anUntranslatedDisplayNamePrecedesTheLocalizedShortName() throws {
        let f = try fixture(rawName: "Product Pro", names: [
            "en": ["CFBundleName": "Product"],
        ])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(try scan(f.app, languages: ["en"]).name == "Product Pro")
    }

    @Test func noUsableTranslationKeepsTheRawFallback() throws {
        let f = try fixture(names: ["en": ["CFBundleDisplayName": "  "]])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(try scan(f.app, languages: ["en"]).name == "MediaCenter")
    }

    @Test func missingTranslationsKeepTheRawFallback() throws {
        let f = try fixture(names: [:])
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(try scan(f.app, languages: ["zh-Hans"]).name == "MediaCenter")
    }

    @Test(arguments: ["Beta", "Canary", "Preview"])
    func localizationCannotHideTheInstalledChannel(word: String) throws {
        let f = try fixture(rawName: "Editor \(word)", names: [
            "zh-Hans": ["CFBundleDisplayName": "编辑器"],
        ])
        defer { try? FileManager.default.removeItem(at: f.root) }
        let app = try scan(f.app, languages: ["zh-Hans"])
        #expect(app.name == "编辑器")
        let expected: [String: ReleaseChannel] = ["Beta": .beta, "Canary": .canary, "Preview": .preview]
        #expect(app.releaseChannel == expected[word])
    }

    @Test func localizationCannotInventAChannel() throws {
        let f = try fixture(rawName: "Editor", names: [
            "en": ["CFBundleDisplayName": "Editor Beta"],
        ])
        defer { try? FileManager.default.removeItem(at: f.root) }
        let app = try scan(f.app, languages: ["en"])
        #expect(app.name == "Editor Beta")
        #expect(app.releaseChannel == .stable)
    }

    @Test func wrappedIOSBundleUsesItsInnerLocalizedName() throws {
        let f = try fixture(names: ["en": ["CFBundleDisplayName": "Wrapped Player"]], wrapped: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let app = try scan(f.app, languages: ["en"])
        #expect(app.name == "Wrapped Player")
        #expect(app.isiOSAppOnMac)
    }
}
