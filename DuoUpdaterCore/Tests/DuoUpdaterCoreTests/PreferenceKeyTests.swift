import Testing
import Foundation
@testable import DuoUpdaterCore

/// Characterisation tests for the per-install preference key derivation, moved
/// verbatim from `Preferences.key(for:)` / `legacyKey(for:)` / `preferenceKey(_:)`.
///
/// Getting this subtly wrong would silently reset every user's ignore and skip
/// list (entries are keyed by these strings and nothing else in the system
/// would notice), so the sanitisation and the legacy bundle-id fallback are
/// locked down exactly as the app produced them.

private func app(path: String, bundleID: String?) -> InstalledApp {
    InstalledApp(
        name: "Fixture",
        bundleID: bundleID,
        shortVersion: "1.0",
        buildVersion: "1",
        path: URL(fileURLWithPath: path),
        isMASApp: false,
        sparkleFeedURL: nil)
}

@Test func keySanitisesThePath() {
    // Slashes and spaces become underscores; dots survive.
    #expect(InstallPreferenceKey.key(for: app(path: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome"))
            == "_Applications_Google_Chrome.app")
    #expect(InstallPreferenceKey.key(for: app(path: "/Applications/Xcode.app", bundleID: "com.apple.dt.Xcode"))
            == "_Applications_Xcode.app")
}

@Test func legacyKeyPrefersTheBundleIDThenFallsBackToThePath() {
    #expect(InstallPreferenceKey.legacyKey(for: app(path: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome"))
            == "com.google.Chrome")
    // Bundle-less installs (rare, malformed) keyed on the path instead.
    let noBundle = app(path: "/Applications/Google Chrome.app", bundleID: nil)
    #expect(InstallPreferenceKey.legacyKey(for: noBundle) == InstallPreferenceKey.key(for: noBundle))
}

@Test func sanitisationKeepsOnlySafeCharacters() {
    #expect(InstallPreferenceKey.preferenceKey("App (Beta): Test") == "App__Beta___Test")
    #expect(InstallPreferenceKey.preferenceKey("my-app_1.2") == "my-app_1.2")
    #expect(InstallPreferenceKey.preferenceKey("123") == "123")
    #expect(InstallPreferenceKey.preferenceKey("中文.app") == "中文.app", "letters are kept, including CJK")
    #expect(InstallPreferenceKey.preferenceKey("🚀") == "_", "emoji is not a letter")
}

@Test func emptyOrDotOnlyKeysFallBackToApp() {
    #expect(InstallPreferenceKey.preferenceKey("") == "app")
    #expect(InstallPreferenceKey.preferenceKey("...") == "app")
    #expect(InstallPreferenceKey.preferenceKey("..a..") == "..a..")
}
