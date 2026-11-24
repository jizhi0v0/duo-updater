import Foundation
import Testing
import DuoUpdaterCore

/// A Homebrew copy that another source answered for is asked there only after
/// Homebrew said it has nothing newer (`UpdateChecker`), so the label credits
/// Homebrew unless that source really offers an update.
struct UpdateSourceLabelTests {
    private func row(source: String, status: UpdateStatus, brewToken: String?) -> UpdateResult {
        let app = InstalledApp(
            name: "Ghostty", bundleID: "com.mitchellh.ghostty", shortVersion: "1.2.0", buildVersion: "1.2.0",
            path: URL(fileURLWithPath: "/Applications/Ghostty.app"), isMASApp: false, sparkleFeedURL: nil)
        var result = UpdateResult(
            app: app, remote: RemoteVersion(shortVersion: "1.3.0", version: nil, downloadURL: nil, sourceName: source),
            status: status)
        result.homebrewSourceIdentifier = brewToken
        return result
    }

    /// Mutation: drop the Homebrew branch → "via Sparkle" on a copy Sparkle gave nothing new.
    @Test func upToDateBrewCopyIsHomebrews() {
        let label = UpdateSourceLabel(row(source: "Sparkle", status: .upToDate, brewToken: "ghostty"))
        #expect(label?.phrase == "via Homebrew")
        #expect(label?.sidebarName == "Homebrew")
    }

    /// Mutation: credit Homebrew for every brew copy → an update Sparkle installs reads as brew's.
    @Test func updateFromElsewhereSaysBrewHadNone() {
        let label = UpdateSourceLabel(row(source: "Sparkle", status: .updateAvailable(latest: "1.3.0"), brewToken: "ghostty"))
        #expect(label?.phrase == "no Homebrew update · via Sparkle")
        #expect(label?.sidebarName == nil)
    }

    /// Mutation: key the branch on status alone → a copy brew never answered for says Homebrew.
    @Test func copyBrewDidNotAnswerKeepsItsSource() {
        #expect(UpdateSourceLabel(row(source: "Sparkle", status: .upToDate, brewToken: nil))?.phrase == "via Sparkle")
    }

    @Test func homebrewItselfIsUnchanged() {
        let label = UpdateSourceLabel(row(source: "Homebrew", status: .updateAvailable(latest: "1.3.0"), brewToken: "ghostty"))
        #expect(label?.phrase == "via Homebrew")
    }

    @Test(arguments: [ReleaseChannel.stable, .preview])
    func ollamaOnlyAsksToQuitForAPreviewOffer(channel: ReleaseChannel) {
        let app = InstalledApp(
            name: "Ollama", bundleID: OllamaUpdateChannel.bundleID,
            shortVersion: "0.40.17", buildVersion: "0.40.17",
            path: URL(fileURLWithPath: "/Applications/Ollama.app"), isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: channel, channelIsAuthoritative: true)
        let offer = remoteOffer(app: app, source: "Vendor")
        let help = ollamaPreviewQuitHelp(for: offer)
        #expect(help == (channel == .preview ? "Quit Ollama before installing this Preview update." : nil))
        #expect(ollamaPreviewQuitHelp(for: remoteOffer(app: app, source: "Homebrew")) == nil)

        var brewCopy = offer
        brewCopy.homebrewSourceIdentifier = "ollama-app"
        if channel == .preview {
            #expect(UpdateSourceLabel(brewCopy)?.phrase == "via the developer’s site")
        } else {
            #expect(UpdateSourceLabel(brewCopy)?.phrase == "no Homebrew update · via the developer’s site")
        }
    }

    private func remoteOffer(app: InstalledApp, source: String) -> UpdateResult {
        UpdateResult(
            app: app, remote: RemoteVersion(shortVersion: "0.40.18", version: nil, downloadURL: nil, sourceName: source),
            status: .updateAvailable(latest: "0.40.18"))
    }

    @Test(arguments: ["racket", "example/tap/racket"])
    func suiteMemberNamesItsExactParentWithoutARemote(cask: String) {
        let ordinary = row(source: "Sparkle", status: .upToDate, brewToken: nil)
        let member = UpdateResult(app: ordinary.app, remote: nil, status: .homebrewSuiteManaged(cask: cask))
        let label = UpdateSourceLabel(member)
        #expect(label?.phrase == "part of \(cask)")
        #expect(label?.sidebarName == "Homebrew")
        #expect(label?.detail.contains(cask) == true)
        #expect(label?.detail.contains("package row") == true)
        #expect(!member.hasUpdate)
    }

    @Test func ordinaryHomebrewUpdateNamesBrew() {
        let result = row(source: "Homebrew", status: .updateAvailable(latest: "1.3.0"), brewToken: "ghostty")
        #expect(UpdateSourceLabel(result, action: .install)?.detail.contains("runs brew") == true)
    }

    @Test func homebrewManualInstallerNamesTheHandoff() {
        let base = row(source: "Homebrew", status: .updateAvailable(latest: "1.3.0"), brewToken: "ghostty")
        var remote = RemoteVersion(shortVersion: "1.3.0", version: nil, downloadURL: nil,
                                   sourceName: "Homebrew", requiresManualInstaller: true)
        remote.homebrewManualInstaller = "Install Ghostty.app"
        let result = UpdateResult(app: base.app, remote: remote, status: base.status)
        let detail = UpdateSourceLabel(result, action: .installer)?.detail ?? ""
        #expect(detail.contains("Homebrew downloads and verifies"))
        #expect(detail.contains("Finish the update"))
        #expect(!detail.contains("macOS’s installer"))
        for staged in [nil, "Install Ghostty.app"] as [String?] {
            let help = installerHandoffHelp(for: result, stagedFileName: staged)
            #expect(help.contains("Finish the update"))
            #expect(!help.contains("asks for admin"))
            #expect(!help.contains("Nothing is downloaded again"))
        }
    }

    /// Mutation: describe the route whatever the action → a detection-only row's
    /// help promises an install it has no button for.
    @Test func noActionPromisesNoInstall() {
        let plain = UpdateSourceLabel(row(source: "GitHub", status: .updateAvailable(latest: "1.3.0"), brewToken: nil))
        #expect(plain?.detail == "Updates come from the project’s GitHub Releases.")
        let brewCopy = UpdateSourceLabel(row(source: "GitHub", status: .updateAvailable(latest: "1.3.0"), brewToken: "zed"))
        #expect(brewCopy?.detail.contains("replaces the app") == false)
        #expect(brewCopy?.detail.contains("record") == false)
        let installs = UpdateSourceLabel(
            row(source: "GitHub", status: .updateAvailable(latest: "1.3.0"), brewToken: "zed"), action: .install)
        #expect(installs?.detail.contains("replaces the app") == true)
        #expect(installs?.detail.contains("record") == true)
    }
}
