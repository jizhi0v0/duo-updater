import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func scanFindsRealApps() {
    let apps = AppScanner().scan()
    #expect(!apps.isEmpty, "expected to find at least one app in /Applications")
}

@Test func cleansNoisyJetBrainsEAPVersion() {
    // A JetBrains EAP bundle reports "EAP IU-262.6653.22" as its marketing version;
    // with no Toolbox to supply a clean "2026.2" we reduce it to the bare build.
    #expect(AppScanner.cleanedJetBrainsVersion(
        "EAP IU-262.6653.22", bundleID: "com.jetbrains.intellij-EAP") == "262.6653.22")
    // A clean stable version (no "EAP "/product-code prefix) passes through.
    #expect(AppScanner.cleanedJetBrainsVersion(
        "2026.1.3", bundleID: "com.jetbrains.intellij") == "2026.1.3")
    // Non-JetBrains strings are never touched, even if oddly shaped.
    #expect(AppScanner.cleanedJetBrainsVersion(
        "EAP IU-1.2.3", bundleID: "com.example.app") == "EAP IU-1.2.3")
}
