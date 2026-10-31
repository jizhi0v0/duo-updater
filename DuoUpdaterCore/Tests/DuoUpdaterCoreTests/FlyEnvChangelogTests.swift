import Foundation
import Testing

@testable import DuoUpdaterCore

/// FlyEnv writes its release bodies as a formatted notes document — a title, then
/// `## **🚀 New Features**` / `## **🛠️ Improvements & Bug Fixes**`, then numbered
/// `### **1. <title>**` subsections. This is the head of the real `v4.20.2` body,
/// cut after the second subsection's bullets.
@Suite struct FlyEnvChangelogTests {

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == "phpstudy.xpfme.com"
        })
    }

    @Test func readsTheReleaseBodiesAsStructuredMarkdown() throws {
        let r = try recipe()
        #expect(r.structuredFormat == .gitHubReleases)
        #expect(r.source.absoluteString.contains("xpf0000/FlyEnv"))
    }

    /// The document's own title never becomes a change line, and each `- **…**`
    /// bullet under the numbered subsections does. Mutation: parse without the
    /// markdown parser (a `- `-only regex) → the count and the first item fail.
    @Test func theNotesDocumentBecomesItsBullets() throws {
        let body = """
        # **FlyEnv v4.20.2 Update Release Notes**

        ## **🚀 New Features**

        ### **1. Added Windows Project Environment Support for Git Bash**

        FlyEnv's Windows shell initialization now integrates with **Git Bash**, allowing configured projects to use their selected runtime paths automatically in the terminal.

        This integration provides:

        - **Automatic Project PATH Loading**: Load runtime paths from a configured project's `.flyenv` file when opening Git Bash in that directory or navigating into it
        - **Environment Switching**: Remove the previous project's injected paths when switching projects or leaving a configured directory
        - **Shell Profile Integration**: Configure interactive and login shells while preserving existing profile content and prompt handlers
        - **Setup Feedback**: Report Git Bash setup problems while allowing PowerShell initialization to complete

        Run **Shell Initialization** in FlyEnv and open a new Git Bash session to activate the integration.

        ### **2. Added a Windows PHP Extension Installer**

        The PHP Extensions page now includes an **Install extensions** view for the selected Windows PHP version.

        - **Extension Search and Status**: Search online packages alongside locally configured extensions, with loaded, not loaded, and not configured states
        - **Build Matching**: Select compatible binaries from PHP's official Windows extension archive by PHP version, thread safety, compiler, and architecture
        - **Installation Progress and Backups**: View installer output, retain the operation result for each PHP version, and locate the `php.ini` backup
        - **Configuration Controls**: Repair configured extensions that are not loading or disable supported entries in the selected `php.ini`
        """
        let entry = try #require(GitHubMarkdownParser.parse(
            body: body, version: "4.20.2", date: nil)?.entries.first)
        #expect(entry.items.count == 8)
        #expect(entry.items.first?.hasPrefix("**Automatic Project PATH Loading**") == true)
        #expect(!entry.items.contains { $0.contains("Update Release Notes") })
        #expect(!entry.items.contains { $0.contains("This integration provides") })
    }
}
