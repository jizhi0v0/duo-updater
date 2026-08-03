import Testing
import Foundation
@testable import DuoUpdaterCore

/// The brew surface used to be `--formula` only, on the assumption that every cask
/// installs a `.app` the scanner would find and surface per-app. A cask that
/// installs only a CLI binary (`codex`), a font, or a driver breaks that: no bundle
/// to scan, so no app row — and no formula, so no brew row either. It fell through
/// both and was invisible.
///
/// These pin the two halves of the fix: parsing `outdated --json=v2`'s `casks`
/// array, and the Caskroom-shaped rule that decides which casks this surface owns.
@Suite struct BrewOutdatedCaskTests {

    /// Real `brew outdated --cask --json=v2` output (trimmed): the two app-less
    /// casks on the machine where this was found.
    private let payload = Data("""
    {"formulae":[],"casks":[
      {"name":"android-platform-tools","installed_versions":["37.0.0"],
       "current_version":"37.0.1","pinned":false,"pinned_version":null},
      {"name":"codex","installed_versions":["0.144.5"],
       "current_version":"0.146.0","pinned":false,"pinned_version":null}
    ]}
    """.utf8)

    @Test func parsesOutdatedCasksAndTagsThemAsCasks() {
        let casks = BrewFormulaService.parseCasks(payload)
        #expect(casks.count == 2)
        let codex = casks.first { $0.name == "codex" }
        #expect(codex?.installedVersion == "0.144.5")
        #expect(codex?.currentVersion == "0.146.0")
        // The tag is what routes the upgrade to `--cask <token>` instead of
        // `--formula`, so it has to survive parsing.
        #expect(codex?.kind == .cask)
    }

    /// `parse` reads `formulae`, `parseCasks` reads `casks`. Feeding one the other's
    /// payload must yield nothing rather than silently mixing the two channels.
    @Test func formulaParserIgnoresCasksAndViceVersa() {
        #expect(BrewFormulaService.parse(payload).isEmpty)
        let formulaPayload = Data("""
        {"formulae":[{"name":"cmake","installed_versions":["4.4.1"],
         "current_version":"4.4.2","pinned":false}],"casks":[]}
        """.utf8)
        #expect(BrewFormulaService.parseCasks(formulaPayload).isEmpty)
        #expect(BrewFormulaService.parse(formulaPayload).first?.kind == .formula)
    }

    /// A pinned cask is held back on purpose; offering to upgrade it would fight the
    /// user's own decision.
    @Test func skipsPinnedCasks() {
        let pinned = Data("""
        {"formulae":[],"casks":[
          {"name":"held","installed_versions":["1.0"],"current_version":"2.0",
           "pinned":true,"pinned_version":"1.0"}
        ]}
        """.utf8)
        #expect(BrewFormulaService.parseCasks(pinned).isEmpty)
    }

    /// The ownership rule, against a Caskroom laid out like the real one: a staged
    /// `.app` (or `.pkg`) means the app is on disk and already has its own row, so
    /// this surface must not list it too. A bare binary means nothing else can.
    @Test func caskOwnershipFollowsStagedArtifacts() throws {
        let fm = FileManager.default
        let caskroom = fm.temporaryDirectory
            .appendingPathComponent("BrewOutdatedCaskTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: caskroom) }

        func stage(_ token: String, version: String, artifact: String) throws {
            let dir = caskroom.appendingPathComponent(token).appendingPathComponent(version)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let entry = dir.appendingPathComponent(artifact)
            if entry.pathExtension.lowercased() == "app" {
                try fm.createDirectory(at: entry, withIntermediateDirectories: true)
            } else {
                try Data("x".utf8).write(to: entry)
            }
        }

        try stage("codex", version: "0.144.5", artifact: "codex-aarch64-apple-darwin")
        try stage("font-jetbrains-mono", version: "2.304", artifact: "JetBrainsMono.ttf")
        try stage("ghostty", version: "1.3.1", artifact: "Ghostty.app")
        try stage("some-pkg-cask", version: "3.0", artifact: "Installer.pkg")

        #expect(BrewFormulaService.installsAnApp(caskToken: "codex", caskroomPaths: [caskroom.path]) == false)
        #expect(BrewFormulaService.installsAnApp(caskToken: "font-jetbrains-mono", caskroomPaths: [caskroom.path]) == false)
        #expect(BrewFormulaService.installsAnApp(caskToken: "ghostty", caskroomPaths: [caskroom.path]) == true)
        #expect(BrewFormulaService.installsAnApp(caskToken: "some-pkg-cask", caskroomPaths: [caskroom.path]) == true)
        // A token with nothing staged reads as "no app" — it can't have an app row
        // either, so the conservative answer is the same one.
        #expect(BrewFormulaService.installsAnApp(caskToken: "absent", caskroomPaths: [caskroom.path]) == false)
    }
}
