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
}
