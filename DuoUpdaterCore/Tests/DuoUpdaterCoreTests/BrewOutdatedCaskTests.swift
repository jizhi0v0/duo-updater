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

    /// A Caskroom and a "scanned folder" in a temp directory, laid out the way
    /// brew leaves them (CLAUDE.md "测试不能问宿主"): a moved artifact is a
    /// symlink at its staged path to where it went (`moved.rb` `post_move`).
    private struct Disk {
        let root: URL
        var caskroom: URL { root.appendingPathComponent("Caskroom") }
        var scanned: URL { root.appendingPathComponent("Applications") }
        var elsewhere: URL { root.appendingPathComponent("Library/Application Support") }
        let fm = FileManager.default

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("BrewOutdatedCaskTests-\(UUID().uuidString)")
            for dir in [caskroom, scanned, elsewhere] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        func remove() { try? fm.removeItem(at: root) }

        func version(_ token: String) throws -> URL {
            let dir = caskroom.appendingPathComponent(token).appendingPathComponent("1.0")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        /// `staged` (relative to the version dir) linked to `target/<name>`, an
        /// app the scanner would list (`app`), or one with no version, or none.
        func moved(_ token: String, staged: String, to target: URL, app: AppOnDisk = .listed) throws {
            let link = try version(token).appendingPathComponent(staged)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            let destination = target.appendingPathComponent(link.lastPathComponent)
            try self.app(at: destination, app)
            try fm.createSymbolicLink(at: link, withDestinationURL: destination)
        }

        enum AppOnDisk { case listed, noVersion, gone }

        func app(at bundle: URL, _ state: AppOnDisk = .listed) throws {
            guard state != .gone else { return }
            let contents = bundle.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = state == .listed
                ? ["CFBundleShortVersionString": "1.0", "CFBundleIdentifier": "zz.fixture"]
                : ["CFBundleIdentifier": "zz.fixture"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }

        func file(_ token: String, _ name: String) throws {
            try Data("x".utf8).write(to: try version(token).appendingPathComponent(name))
        }

        func directory(_ token: String, _ name: String) throws {
            try fm.createDirectory(at: try version(token).appendingPathComponent(name), withIntermediateDirectories: true)
        }

        func receipt(_ token: String, _ json: String) throws {
            let metadata = caskroom.appendingPathComponent(token).appendingPathComponent(".metadata")
            try fm.createDirectory(at: metadata, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        }

        func facts(
            _ token: String, receipts: [String: [String]?] = [:], targets: [String]? = nil, extra: [String] = []
        ) async -> BrewFormulaService.CaskFacts {
            await BrewFormulaService.caskFacts(
                caskToken: token, appTargets: targets, extraFolders: extra,
                caskroomPaths: [caskroom.path], scannedFolders: [scanned.path],
                receiptApps: { receipts[$0] ?? nil })
        }
    }

    private static func pkgutilReceipt(_ pkgutil: String) -> String {
        #"{"uninstall_artifacts":[{"uninstall":[{"pkgutil":\#(pkgutil),"quit":"x"}]},{"zap":[{"trash":["~/x"]}]}]}"#
    }

    /// The rule is "the scanner shows it" (#1617): an app moved into a scanned
    /// folder is an app; one moved anywhere else, or an installer bundle left in
    /// the Caskroom, is not — those would otherwise be dropped from the Brew tree
    /// with no app row standing for them. A CLI or a font is no app either.
    ///
    /// Mutation: count any `.app` entry (the old rule) → `box-tools`,
    /// `voikkospellservice` and `battle-net` read as apps. Mutation: drop the
    /// walk below the top level → `nested-app` reads as no app. Mutation: take
    /// a link's folder without the bundle (the reviewed version) → `bartender`,
    /// whose app was deleted, and `noversion`, which the scanner drops, read as
    /// apps and show up nowhere.
    @Test func stagedAppsCountOnlyWhenTheScannerSeesThem() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        try disk.moved("ghostty", staged: "Ghostty.app", to: disk.scanned)
        try disk.moved("nested-app", staged: "Foo/Foo.app", to: disk.scanned)
        try disk.moved("bartender", staged: "Bartender 6.app", to: disk.scanned, app: .gone)
        try disk.moved("noversion", staged: "Helper.app", to: disk.scanned, app: .noVersion)
        try disk.moved("custom-folder", staged: "Mine.app", to: disk.elsewhere)
        try disk.moved("box-tools", staged: "Box Edit.app", to: disk.elsewhere)
        try disk.moved("voikkospellservice", staged: "VoikkoSpellService.app", to: disk.elsewhere)
        try disk.directory("battle-net", "Battle.net-Setup.app")
        try disk.file("codex", "codex-aarch64-apple-darwin")
        try disk.file("font-jetbrains-mono", "JetBrainsMono.ttf")

        #expect(await disk.facts("ghostty").installsAnApp == true)
        #expect(await disk.facts("nested-app").installsAnApp == true)
        #expect(await disk.facts("bartender").installsAnApp == false)
        #expect(await disk.facts("noversion").installsAnApp == false)
        // A folder the person added to the scan lists apps too.
        #expect(await disk.facts("custom-folder").installsAnApp == false)
        #expect(await disk.facts("custom-folder", extra: [disk.elsewhere.path]).installsAnApp == true)
        #expect(await disk.facts("box-tools").installsAnApp == false)
        #expect(await disk.facts("voikkospellservice").installsAnApp == false)
        #expect(await disk.facts("battle-net").installsAnApp == false)
        #expect(await disk.facts("codex") == .init(installsAnApp: false, needsSudo: false))
        #expect(await disk.facts("font-jetbrains-mono") == .init(installsAnApp: false, needsSudo: false))
        // Nothing staged: no app row either.
        #expect(await disk.facts("absent") == .init(installsAnApp: false, needsSudo: false))
    }

    /// A pkg is an app only when a receipt its `uninstall` names put a `.app` in
    /// a scanned folder. `zulu@25`'s JDK is not one, nor aTrust's app under
    /// `/Library/sangfor/SDP`; what can't be read counts as no app (a duplicate
    /// row at worst, never a cask shown nowhere). Every pkg cask needs sudo.
    ///
    /// Mutation: treat an unreadable receipt (nil) or a missing `pkgutil:` as an
    /// app → `zzfixture-unread`/`zzfixture-nostanza` vanish from the Brew tree.
    /// Mutation: accept a `.app` anywhere → `zzfixture-atrust` reads as an app.
    @Test func aPkgCaskIsAnAppOnlyWhenItsReceiptsPutOneWhereTheScannerLooks() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        for token in ["zzfixture-jdk", "zzfixture-pkgapp", "zzfixture-atrust", "zzfixture-unread", "zzfixture-nostanza", "zzfixture-noreceipt"] {
            try disk.file(token, "Install.pkg")
        }
        try disk.receipt("zzfixture-jdk", Self.pkgutilReceipt(#""com.zzfixture.jdk""#))
        try disk.receipt("zzfixture-pkgapp", Self.pkgutilReceipt(#"["com.zzfixture.helper","com.zzfixture.app"]"#))
        try disk.receipt("zzfixture-atrust", Self.pkgutilReceipt(#""com.zzfixture.atrust""#))
        try disk.receipt("zzfixture-unread", Self.pkgutilReceipt(#""com.zzfixture.gone""#))
        try disk.receipt("zzfixture-nostanza", #"{"uninstall_artifacts":[{"zap":[{"trash":["~/x"]}]}]}"#)

        try disk.app(at: disk.scanned.appendingPathComponent("ZZ.app"))
        let receipts: [String: [String]?] = [
            "com.zzfixture.jdk": [],
            "com.zzfixture.helper": [disk.elsewhere.appendingPathComponent("Helper.app").path],
            "com.zzfixture.app": [disk.scanned.appendingPathComponent("ZZ.app").path],
            "com.zzfixture.atrust": ["/Library/sangfor/SDP/aTrust.app"],
            "com.zzfixture.gone": nil,
        ]
        let sudo = { (app: Bool) in BrewFormulaService.CaskFacts(installsAnApp: app, needsSudo: true) }
        #expect(await disk.facts("zzfixture-jdk", receipts: receipts) == sudo(false))
        #expect(await disk.facts("zzfixture-pkgapp", receipts: receipts) == sudo(true))
        #expect(await disk.facts("zzfixture-atrust", receipts: receipts) == sudo(false))
        #expect(await disk.facts("zzfixture-unread", receipts: receipts) == sudo(false))
        #expect(await disk.facts("zzfixture-nostanza", receipts: receipts) == sudo(false))
        #expect(await disk.facts("zzfixture-noreceipt", receipts: receipts) == sudo(false))
    }

    /// The receipt's own `pkgutil:` shapes: one id, a list, beside other
    /// directives of the stanza in the same hash (`AbstractUninstall` keeps the
    /// stanza's directives as one hash, `abstract_uninstall.rb`).
    @Test func pkgutilPatternsReadEveryShapeOfTheUninstallStanza() {
        func patterns(_ json: String) -> [String] { BrewFormulaService.pkgutilPatterns(installReceipt: Data(json.utf8)) }
        #expect(patterns(Self.pkgutilReceipt(#""com.azulsystems.zulu.25""#)) == ["com.azulsystems.zulu.25"])
        #expect(patterns(Self.pkgutilReceipt(#"["a","b"]"#)) == ["a", "b"])
        #expect(patterns(#"{"uninstall_artifacts":[{"app":["X.app"]}]}"#).isEmpty)
        #expect(patterns("").isEmpty)
    }

    /// Real receipts, measured on this Mac with `pkgutil --pkg-info` and
    /// `--only-dirs --files` (trimmed). Mutation: ignore the install location →
    /// Tailscale, whose location IS the bundle, has no app. Mutation: keep the
    /// whole path, not the bundle → a `Contents/…` directory is taken for the
    /// app. Mutation: match `.app` as a substring → `Foo.appex` counts.
    @Test func appBundlesAreTheOutermostDotAppUnderTheVolume() {
        #expect(BrewFormulaService.appBundles(
            volume: "/", location: "Library/Java/JavaVirtualMachines/zulu-25.jdk",
            directories: ["Contents", "Contents/Home", "Contents/Home/bin"]).isEmpty)
        #expect(BrewFormulaService.appBundles(
            volume: "/", location: "Applications/Tailscale.app",
            directories: ["Contents", "Contents/Frameworks"]) == ["/Applications/Tailscale.app"])
        #expect(BrewFormulaService.appBundles(
            volume: "/", location: "Applications",
            directories: ["Keka.app", "Keka.app/Contents", "Keka.app/Contents/Library/Helper.app"]) == ["/Applications/Keka.app"])
        #expect(BrewFormulaService.appBundles(
            volume: "/", location: "",
            directories: ["Applications", "Applications/ToDesk.app", "Library/PlugIns/Foo.appex"]) == ["/Applications/ToDesk.app"])
    }

    /// `pkgutil --pkg-info` fields, as measured for a receipt at the volume's
    /// root (`location: ` then nothing), and without the trailing space too.
    /// Mutation: match `"location: "` with its space → the second is nil, and
    /// the cask's receipts read as unreadable.
    @Test func pkgInfoFieldsReadWithOrWithoutTheTrailingSpace() {
        let info = ["package-id: com.youqu.todesk.mac", "version: 4.3.0", "volume: /", "location: ", "install-time: 1"]
        #expect(BrewFormulaService.pkgInfoField("location", in: info) == "")
        #expect(BrewFormulaService.pkgInfoField("location", in: ["location:"]) == "")
        #expect(BrewFormulaService.pkgInfoField("volume", in: info) == "/")
        #expect(BrewFormulaService.pkgInfoField("location", in: ["location: Applications"]) == "Applications")
        #expect(BrewFormulaService.pkgInfoField("location", in: ["version: 1"]) == nil)
    }

    /// The Brew tree's cask rows come from the same `info --json=v2 --installed`
    /// read as everything else: casks with no app row only, a cask brew read from
    /// its Caskroom copy left to its unchecked row, version, lifecycle and sudo
    /// carried. Mutation: drop the `tap` guard → an untrusted cask gets two rows.
    @Test func appLessCasksAreTheInstalledCasksWithNoAppRow() {
        let info = Data(#"""
        {"formulae":[],"casks":[
          {"token":"zulu@25","tap":"homebrew/cask","installed":"25.0.4.1,25.36.205","deprecated":false,"disabled":false},
          {"token":"ghostty","tap":"homebrew/cask","installed":"1.3.1","deprecated":false,"disabled":false},
          {"token":"codex","tap":"homebrew/cask","installed":"0.163.0","deprecated":true,"deprecation_date":"2026-01-01","deprecation_reason":"unmaintained","disabled":false},
          {"token":"zzfixture-untrusted","tap":null,"installed":"1.0"}
        ]}
        """#.utf8)
        let facts: [String: BrewFormulaService.CaskFacts] = [
            "zulu@25": .init(installsAnApp: false, needsSudo: true),
            "ghostty": .init(installsAnApp: true, needsSudo: false),
            "codex": .init(installsAnApp: false, needsSudo: false),
            "zzfixture-untrusted": .init(installsAnApp: false, needsSudo: false),
        ]
        let casks = BrewFormulaService.appLessCasks(installedInfo: info, facts: facts)
        #expect(casks.map(\.name) == ["codex", "zulu@25"])
        #expect(casks.map(\.key) == ["cask:codex", "cask:zulu@25"])
        #expect(casks.map(\.installedVersion) == ["0.163.0", "25.0.4.1,25.36.205"])
        #expect(casks.map(\.needsSudo) == [false, true])
        #expect(casks.allSatisfy { $0.kind == .cask && $0.availableVersion == nil })
        #expect(casks.first?.lifecycle?.stage == .deprecated)
        #expect(BrewFormulaService.installedCaskTokens(installedInfo: info).count == 4)
    }

    /// A cask's token can be a formula's name (`codex` is both): each takes its
    /// own update line. Mutation: key `merge` by name alone → the formula row
    /// shows the cask's version.
    @Test func mergeKeepsAFormulaAndACaskOfTheSameNameApart() {
        let merged = BrewFormulaService.merge(
            [BrewInstalledFormula(name: "codex", installedVersion: "1.0", availableVersion: nil),
             BrewInstalledFormula(name: "codex", installedVersion: "0.163.0", availableVersion: nil, kind: .cask)],
            outdated: [BrewOutdatedFormula(name: "codex", installedVersion: "0.163.0", currentVersion: "0.164.0", kind: .cask)])
        #expect(merged.first { $0.kind == .cask }?.availableVersion == "0.164.0")
        #expect(merged.first { $0.kind == .formula }?.availableVersion == nil)
        #expect(Set(merged.map(\.id)).count == 2)
    }

    /// Where brew put the apps (`info --json` targets) decides when it is
    /// known: an app link inside an installer bundle (`kimi`), or deeper than
    /// the walk goes, is found there; a pkg nested in an installer bundle
    /// (`logitech-options`) still has its receipts read. Mutation: ignore the
    /// targets → `kimi` reads as no app and shows twice. Mutation: read
    /// receipts only for a pkg the walk found → `logitech-options` likewise.
    @Test func brewsRecordOfWhereAppsWentDecidesWhenItIsThere() async throws {
        let disk = try Disk()
        defer { disk.remove() }
        try disk.directory("kimi", "Kimi Installer.app/Contents/Resources")
        try disk.app(at: disk.scanned.appendingPathComponent("Kimi.app"))
        try disk.directory("logitech-options", "LogiOptionsInstaller.app/Contents/Resources/LogiMgr Installer.pkg")
        try disk.receipt("logitech-options", Self.pkgutilReceipt(#""com.logitech.manager.pkg""#))
        try disk.app(at: disk.scanned.appendingPathComponent("Logi Options.app"))

        #expect(await disk.facts("kimi").installsAnApp == false)
        #expect(await disk.facts("kimi", targets: [disk.scanned.appendingPathComponent("Kimi.app").path]).installsAnApp == true)
        #expect(await disk.facts("kimi", targets: [disk.scanned.appendingPathComponent("Gone.app").path]).installsAnApp == false)
        let logi = await disk.facts(
            "logitech-options",
            receipts: ["com.logitech.manager.pkg": [disk.scanned.appendingPathComponent("Logi Options.app").path]],
            targets: [])
        #expect(logi == .init(installsAnApp: true, needsSudo: true))
    }

    /// `installer manual:` casks: brew refuses to upgrade them, so their row
    /// shows the update with no Update. Mutation: drop the `manual` read →
    /// `figma-agent` gets an Update that always fails.
    @Test func aManualInstallerCaskIsMarked() {
        let info = Data(#"""
        {"formulae":[],"casks":[
          {"token":"figma-agent","tap":"homebrew/cask","installed":"1.0",
           "artifacts":[{"installer":[{"manual":"Install Figma Agent.app"}]}]},
          {"token":"zzfixture-script","tap":"homebrew/cask","installed":"1.0",
           "artifacts":[{"installer":[{"script":{"executable":"install.sh"}}]}]}
        ]}
        """#.utf8)
        let none = BrewFormulaService.CaskFacts(installsAnApp: false, needsSudo: false)
        let casks = BrewFormulaService.appLessCasks(installedInfo: info, facts: ["figma-agent": none, "zzfixture-script": none])
        #expect(casks.map(\.manualInstaller) == [true, false])
        var figma = casks[0]
        figma = BrewFormulaService.merge([figma], outdated: [BrewOutdatedFormula(name: "figma-agent", installedVersion: "1.0", currentVersion: "2.0", kind: .cask)])[0]
        #expect(figma.hasUpdate && !figma.canUpgrade)
    }

    /// The targets come from `info --json`'s `"target"` beside each relocated
    /// artifact; only `.app` ones. A read that fails is not "no casks".
    @Test func appTargetsAndTheFailedReadAreReadFromInfo() {
        let info = Data(#"""
        {"formulae":[],"casks":[
          {"token":"bartender","artifacts":[{"app":["Bartender 6.app"],"target":"/Applications/Bartender 6.app"},{"zap":[]}]},
          {"token":"voikko","artifacts":[{"service":["V.app"],"target":"/Users/x/Library/Services/V.app"}]},
          {"token":"font","artifacts":[{"font":["a.ttf"],"target":"/Users/x/Library/Fonts/a.ttf"}]}
        ]}
        """#.utf8)
        #expect(BrewFormulaService.appTargets(installedInfo: info) == [
            "bartender": ["/Applications/Bartender 6.app"],
            "voikko": ["/Users/x/Library/Services/V.app"],
            "font": [],
        ])
        #expect(BrewFormulaService.parsesCasks(installedInfo: info))
        #expect(!BrewFormulaService.parsesCasks(installedInfo: Data()))
    }
}
