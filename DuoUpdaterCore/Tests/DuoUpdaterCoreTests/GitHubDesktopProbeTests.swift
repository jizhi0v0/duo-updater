import Testing
@testable import DuoUpdaterCore

@Test func githubDesktopStableProbeReadsTheProductionArm64Redirect() throws {
    let recipe = try #require(VendorProbeRegistry.recipes.first {
        $0.bundleID == "com.github.GitHubClient" && $0.channel == .stable
    })
    let location = "https://desktop.githubusercontent.com/releases/3.7.0-f13859b6/GitHubDesktop-arm64.zip"

    #expect(recipe.runs(onOS: "15.0", arch: .arm64))
    #expect(!recipe.runs(onOS: "15.0", arch: .x86_64))
    #expect(!recipe.followRedirects)
    #expect(VendorProbeRecipe.extractVersion(from: location, pattern: recipe.versionPattern) == "3.7.0")
    let install = try #require(recipe.install)
    guard case .bodyPattern(let pattern) = install.urlSource else {
        Issue.record("the one-click URL must come from the same redirect as the version")
        return
    }
    #expect(install.kind == .zip)
    #expect(VendorProbeRecipe.extractVersion(from: location, pattern: pattern) == location)

    for otherLocation in [
        "https://desktop.githubusercontent.com/releases/3.7.0-beta1-f13859b6/GitHubDesktop-arm64.zip",
        "https://desktop.githubusercontent.com/releases/3.7.0-f13859b6/GitHubDesktop-x64.zip",
        "https://other.example/releases/3.7.0-f13859b6/GitHubDesktop-arm64.zip",
    ] {
        #expect(VendorProbeRecipe.extractVersion(from: otherLocation, pattern: recipe.versionPattern) == nil)
    }
}
