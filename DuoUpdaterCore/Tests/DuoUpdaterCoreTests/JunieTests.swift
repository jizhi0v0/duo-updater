import Testing
import Foundation
@testable import DuoUpdaterCore

/// A Junie install built out of plain files in a temporary directory, laid out the
/// way `install.sh` lays it out (2026-10-02). Shared by the Junie suites.
final class JunieSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var data: URL { home.appendingPathComponent(".local/share/junie") }
    var launcher: URL { home.appendingPathComponent(".local/bin/junie") }

    /// The first lines of each shim generation, as the real ones begin.
    static let managedShim = "#!/bin/bash\n#\n# JUNIE_MANAGED_SHIM\n#\n# Junie CLI Shim\napply_pending_update() { :; }\n"
    static let legacyShim = "#!/bin/bash\n#\n# Junie CLI Shim\n#\napply_pending_update() { :; }\n"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("junie-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    func shim(_ text: String = JunieSandbox.managedShim) throws {
        try write(launcher, text, executable: true)
    }

    /// `versions/<version>` with a bundle whose Info.plist says `bundleVersion`,
    /// a `junie-<jarChannel>-<version>.jar` and, when given, a `channel` file. The
    /// launcher's text is what the injected signature check reads.
    func build(
        _ version: String, bundleVersion: String? = nil, jarChannel: String? = "release",
        channelFile: String? = nil, signer: String = "jetbrains"
    ) throws {
        let root = data.appendingPathComponent("versions/\(version)")
        let contents = root.appendingPathComponent("Applications/junie.app/Contents")
        try write(contents.appendingPathComponent("MacOS/junie"), signer, executable: true)
        let plist: [String: Any] = [
            "CFBundleShortVersionString": bundleVersion ?? version, "CFBundleVersion": bundleVersion ?? version,
        ]
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let jarChannel { try write(contents.appendingPathComponent("app/junie-\(jarChannel)-\(version).jar"), "jar") }
        try write(contents.appendingPathComponent("app/junie.cfg"), "cfg")
        if let channelFile { try write(root.appendingPathComponent("channel"), channelFile + "\n") }
    }

    func current(_ destination: String) throws {
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let link = data.appendingPathComponent("current")
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
    }

    /// A whole install of `version`: shim, build, `current` → it, `updates/`.
    func install(_ version: String = "3419.26", shim: String = JunieSandbox.managedShim, channelFile: String? = "release",
                 jarChannel: String? = "release", signer: String = "jetbrains") throws {
        try self.shim(shim)
        try build(version, jarChannel: jarChannel, channelFile: channelFile, signer: signer)
        try current(data.appendingPathComponent("versions/\(version)").path)
        try FileManager.default.createDirectory(at: data.appendingPathComponent("updates"), withIntermediateDirectories: true)
    }

    /// The signature is the bundle's launcher text: "jetbrains" → vendor, "adhoc"
    /// → ad hoc, anything else another signer.
    var scanner: JunieScanner {
        JunieScanner(home: home, checkSignature: { app in
            let text = (try? String(contentsOf: app.appendingPathComponent("Contents/MacOS/junie"), encoding: .utf8)) ?? ""
            switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "jetbrains": return .vendor
            case "adhoc": return .adHoc
            default: return .otherSigner
            }
        })
    }
}

/// Junie: finding the install, reading its settings and its channel's feed, the
/// verdict and the busy gate.
///
/// Installs are plain files in a temporary directory (`JunieSandbox`); the
/// signature check, the feed and the process table are injected, so nothing here
/// depends on what is installed on the host, runs Junie, or reaches the network.
@Suite struct JunieTests {

    // MARK: - Scanner

    @Test func readsAManagedInstall() throws {
        let box = try JunieSandbox()
        try box.install("3419.26", channelFile: "release")
        let install = try #require(box.scanner.scan().first)
        #expect(install.path == box.launcher.path)
        #expect(install.dataDirectory == box.data.path)
        #expect(install.shim == .managed)
        #expect(install.version == "3419.26")
        #expect(install.bundleVersion == "3419.26")
        #expect(install.channel == "release")
        #expect(install.problem == nil)
        #expect(install.pendingUpdate == nil)
        // The scan reads no signature; `withSignature` does.
        #expect(install.signature == nil)
        #expect(box.scanner.withSignature(install).signature == .vendor)
    }

    /// The first-generation shim (this Mac's in May 2026) and 1543.24's layout: no
    /// `channel` file, the channel is in the jar's name.
    @Test func readsAFirstGenerationInstallFromItsJar() throws {
        let box = try JunieSandbox()
        try box.install("1543.24", shim: JunieSandbox.legacyShim, channelFile: nil, jarChannel: "release", signer: "adhoc")
        let install = try #require(box.scanner.scan().first)
        #expect(install.shim == .legacy)
        #expect(install.channel == "release")
        #expect(box.scanner.withSignature(install).signature == .adHoc)
    }

    @Test func eapAndNightlyAreSpelledAsJunieSpellsThem() throws {
        for channel in ["eap", "nightly"] {
            let box = try JunieSandbox()
            try box.install("3579.2", channelFile: channel, jarChannel: channel)
            #expect(box.scanner.scan().first?.channel == channel)
        }
    }

    /// Only Junie's shim makes an install: another program called `junie` is not
    /// reported. Mutation: dropping the marker test in `shimGeneration` reports the
    /// first two.
    @Test func anotherProgramNamedJunieIsNotReported() throws {
        let box = try JunieSandbox()
        try box.build("3419.26", channelFile: "release")
        try box.current(box.data.appendingPathComponent("versions/3419.26").path)
        try box.shim("#!/bin/sh\necho some other junie\n")
        #expect(box.scanner.scan().isEmpty)
        try box.shim("\u{CF}\u{FA}\u{ED}\u{FE} a Mach-O, not a shim")
        #expect(box.scanner.scan().isEmpty)
        try FileManager.default.removeItem(at: box.launcher)
        #expect(box.scanner.scan().isEmpty)
    }

    /// An IDE's own copy of Junie (its ACP agent) is the IDE's: nothing under
    /// `~/Library/Caches/JetBrains` is looked at.
    @Test func idesAcpCopiesAreNeverFound() throws {
        let box = try JunieSandbox()
        try box.write(
            box.home.appendingPathComponent("Library/Caches/JetBrains/IntelliJIdea2026.2/acp-agents/junie/3419.26/junie"),
            JunieSandbox.managedShim, executable: true)
        #expect(box.scanner.scan().isEmpty)
    }

    /// The shim runs `versions/<basename of current>`, wherever the link points;
    /// so is the install read.
    @Test func theBuildIsTheBasenameOfCurrentAsTheShimReadsIt() throws {
        let box = try JunieSandbox()
        try box.shim()
        try box.build("3419.26", channelFile: "release")
        try box.current("/ZZFixture-elsewhere/3419.26")
        #expect(!FileManager.default.fileExists(atPath: "/ZZFixture-elsewhere"))
        let install = try #require(box.scanner.scan().first)
        #expect(install.version == "3419.26")
        #expect(install.problem == nil)
    }

    @Test func brokenLayoutsAreProblems() throws {
        let box = try JunieSandbox()
        try box.shim()
        #expect(box.scanner.scan().first?.problem == .noCurrent)
        try box.current(box.data.appendingPathComponent("versions/latest").path)
        #expect(box.scanner.scan().first?.problem == .versionUnreadable)
        try box.current(box.data.appendingPathComponent("versions/3419.26").path)
        #expect(box.scanner.scan().first?.problem == .versionMissing)
        try FileManager.default.createDirectory(
            at: box.data.appendingPathComponent("versions/3419.26/Applications"), withIntermediateDirectories: true)
        #expect(box.scanner.scan().first?.problem == .appMissing)
        try box.build("3419.26", jarChannel: nil, channelFile: nil)
        #expect(box.scanner.scan().first?.problem == .channelUnknown)
        try box.build("3419.26", jarChannel: "release", channelFile: "eap")
        #expect(box.scanner.scan().first?.problem == .channelConflict)
    }

    /// Only a jar of the build itself names the channel: one left from another
    /// build does not.
    @Test func aJarOfAnotherBuildSaysNothing() throws {
        let box = try JunieSandbox()
        try box.install("3419.26", channelFile: nil, jarChannel: nil)
        try box.write(
            box.data.appendingPathComponent("versions/3419.26/Applications/junie.app/Contents/app/junie-eap-3579.2.jar"), "")
        #expect(box.scanner.scan().first?.problem == .channelUnknown)
    }

    /// A staged update counts only when the shim would act on it: `version`,
    /// `zipPath`, and the zip there. Mutation: dropping the zip's existence check
    /// makes the second manifest staged.
    @Test func aStagedUpdateIsOneTheShimWouldApply() throws {
        let box = try JunieSandbox()
        try box.install()
        let updates = box.data.appendingPathComponent("updates")
        let zip = try box.write(updates.appendingPathComponent("junie-3579.2.zip"), "zip")
        try box.write(updates.appendingPathComponent("pending-update.json"),
                      #"{"version":"3579.2","zipPath":"\#(zip.path)","sha256":"ab","previousVersion":"3419.26"}"#)
        #expect(box.scanner.scan().first?.pendingUpdate == "3579.2")
        try FileManager.default.removeItem(at: zip)
        #expect(box.scanner.scan().first?.pendingUpdate == nil)
        try box.write(updates.appendingPathComponent("pending-update.json"), #"{"zipPath":"\#(zip.path)"}"#)
        #expect(box.scanner.scan().first?.pendingUpdate == nil)
        try box.write(updates.appendingPathComponent("pending-update.json"), "")
        #expect(box.scanner.scan().first?.pendingUpdate == nil)
    }

    @Test func theDataDirectoryDefaultsToTheInstallersPair() {
        let install = JunieInstall(path: "/ZZFixture-junie/home/.local/bin/junie", version: "3419.26")
        #expect(install.dataDirectory == "/ZZFixture-junie/home/.local/share/junie")
        #expect(install.bundle == "/ZZFixture-junie/home/.local/share/junie/versions/3419.26/Applications/junie.app")
    }

    // MARK: - Settings

    /// Only a JSON `false` turns auto-update off. Mutation: dropping the CFBoolean
    /// type test reads `0` as off.
    @Test func autoUpdateIsOffOnlyForAJSONFalse() {
        func read(_ text: String) -> Bool { JunieSettings.parse(Data(text.utf8)).autoUpdate }
        #expect(read(#"{"auto-update": false}"#) == false)
        #expect(read(#"{"auto-update": true}"#) == true)
        #expect(read(#"{"model": "x"}"#) == true)
        #expect(read(#"{"auto-update": 0}"#) == true)
        #expect(read(#"{"auto-update": "false"}"#) == true)
        #expect(read("not json") == true)
    }

    @Test func settingsComeFromTheUsersConfigFile() throws {
        let box = try JunieSandbox()
        #expect(JunieSettings.read(home: box.home).autoUpdate)
        try box.write(box.home.appendingPathComponent(".junie/config.json"), #"{"auto-update": false}"#)
        #expect(JunieSettings.read(home: box.home).autoUpdate == false)
    }

    // MARK: - Feed

    /// Lines as `update-info.jsonl` has them (2026-10-02): every platform, not in
    /// version order, `marketing` only on newer lines.
    static let feed = """
        {"version":"888.12","platform":"macos-aarch64","downloadUrl":"https://example.invalid/888.12.zip","sha256":"aa","size":1}
        {"version":"3419.26","marketing":"26.9.22","platform":"macos-aarch64","downloadUrl":"https://example.invalid/3419.26.zip","sha256":"bb","size":2}
        {"version":"3419.26","marketing":"26.9.22","platform":"windows-amd64","downloadUrl":"https://example.invalid/w.zip","sha256":"cc","size":3}
        {"version":"3419.7","marketing":"26.9.22","platform":"macos-aarch64","downloadUrl":"https://example.invalid/3419.7.zip","sha256":"dd","size":4}
        {"version":"3419.19","platform":"macos-aarch64","downloadUrl":"https://example.invalid/3419.19.zip","sha256":"ee","size":5}
        {"version":"9999.1","platform":"macos-amd64","downloadUrl":"https://example.invalid/intel.zip","sha256":"ff","size":6}
        not a line
        {"version":"latest","platform":"macos-aarch64","downloadUrl":"https://example.invalid/x.zip"}

        """

    /// Newest by number, part by part — `3419.26` above `3419.7` — for this
    /// Mac's platform only. Mutation: comparing as strings puts `3419.7` first.
    @Test func feedIsReadNumericallyForThisPlatform() {
        let builds = JunieRelease.parse(Data(Self.feed.utf8), platform: "macos-aarch64")
        #expect(builds.map(\.version) == ["3419.26", "3419.19", "3419.7", "888.12"])
        #expect(builds.first?.marketing == "26.9.22")
        #expect(builds.first?.downloadURL == "https://example.invalid/3419.26.zip")
        #expect(JunieRelease.parse(Data(Self.feed.utf8), platform: "macos-amd64").map(\.version) == ["9999.1"])
    }

    @Test func channelsMapToTheVendorsFeedsAndInstallers() {
        let base = "https://raw.githubusercontent.com/jetbrains-junie/junie/main/"
        #expect(JunieRelease.feed(channel: "release")?.absoluteString == base + "update-info.jsonl")
        #expect(JunieRelease.feed(channel: "eap")?.absoluteString == base + "update-info-eap.jsonl")
        #expect(JunieRelease.feed(channel: "nightly")?.absoluteString == base + "update-info-nightly.jsonl")
        #expect(JunieRelease.feed(channel: "experimental")?.absoluteString == base + "update-info-experimental.jsonl")
        #expect(JunieRelease.feed(channel: "beta") == nil)
        #expect(JunieRelease.installer(channel: "release")?.absoluteString == "https://junie.jetbrains.com/install.sh")
        #expect(JunieRelease.installer(channel: "eap")?.absoluteString == "https://junie.jetbrains.com/install-eap.sh")
        #expect(JunieRelease.installer(channel: "nightly")?.absoluteString == "https://junie.jetbrains.com/install-nightly.sh")
        #expect(JunieRelease.installer(channel: "experimental") == nil)
        #expect(JunieRelease.platform(.arm64) == "macos-aarch64")
        #expect(JunieRelease.platform(.x86_64) == "macos-amd64")
    }

    // MARK: - Verdict

    static let home = "/ZZFixture-junie/home"

    static func install(
        version: String? = "1543.24", bundleVersion: String? = nil, channel: String? = "release",
        signature: CLIToolTrust.Signature? = .adHoc, pending: String? = nil, problem: JunieInstall.Problem? = nil
    ) -> JunieInstall {
        JunieInstall(
            path: home + "/.local/bin/junie", dataDirectory: home + "/.local/share/junie", shim: .legacy,
            version: version, bundleVersion: bundleVersion ?? version, channel: channel, signature: signature,
            pendingUpdate: pending, problem: problem)
    }

    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    static func check(_ latest: String = "3419.26", asked: Asked = Asked()) -> JunieCheck {
        JunieCheck(latest: { channel in
            asked.add(channel)
            return JunieRelease.Build(version: latest, marketing: nil, platform: "macos-aarch64",
                                      downloadURL: "https://example.invalid", sha256: nil)
        })
    }

    @Test func fixturesAreNotOnTheHost() {
        #expect(!FileManager.default.fileExists(atPath: "/ZZFixture-junie"))
    }

    /// The installer for the install's own channel, with `~/.local/bin` first on
    /// `PATH`. An ad hoc install is offered too: Junie is never run, and the
    /// build the installer leaves is checked (`JunieUpdater`) — the user's call,
    /// 2026-10-01.
    @Test func anOutdatedInstallIsOfferedItsChannelsInstaller() async {
        let asked = Asked()
        let status = await Self.check(asked: asked).status(of: Self.install(), settings: JunieSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "1543.24")
        #expect(status.latestVersion == "3419.26")
        #expect(status.channel == "release")
        #expect(status.withheld == nil)
        #expect(status.oneClick?.display == "curl -fsSL https://junie.jetbrains.com/install.sh | bash")
        #expect(status.oneClick?.pathPrefix == Self.home + "/.local/bin")
        #expect(asked.all == ["release"])
    }

    @Test func eapAndNightlyAreOfferedLikeRelease() async {
        for channel in ["eap", "nightly"] {
            let asked = Asked()
            let status = await Self.check("3612.1", asked: asked)
                .status(of: Self.install(version: "3579.2", channel: channel), settings: JunieSettings(), busy: nil)
            #expect(status.oneClick?.display == "curl -fsSL https://junie.jetbrains.com/install-\(channel).sh | bash")
            #expect(asked.all == [channel])
            #expect(status.channel == channel)
        }
    }

    @Test func upToDateAndAheadOfferNothing() async {
        let same = await Self.check("1543.24").status(of: Self.install(), settings: JunieSettings(), busy: nil)
        #expect(same.state == .upToDate)
        #expect(same.oneClick == nil)
        let ahead = await Self.check("1543.9").status(of: Self.install(), settings: JunieSettings(), busy: nil)
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    @Test func experimentalHasNoInstaller() async {
        let status = await Self.check("3336.1")
            .status(of: Self.install(version: "133.2", channel: "experimental"), settings: JunieSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
    }

    /// Mutation: dropping the setting's guard offers the click.
    @Test func autoUpdateOffIsReportedWithTheCommand() async {
        let status = await Self.check().status(
            of: Self.install(), settings: JunieSettings(autoUpdate: false), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .autoUpdateOff)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand?.display == "curl -fsSL https://junie.jetbrains.com/install.sh | bash")
    }

    /// An update Junie has downloaded is Junie's to install at the next launch.
    /// Mutation: dropping the `pendingUpdate` guard offers the click.
    @Test func aStagedUpdateIsLeftToJunie() async {
        let status = await Self.check().status(
            of: Self.install(pending: "3419.22"), settings: JunieSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .staged)
        #expect(status.oneClick == nil)
        #expect(status.note?.contains("3419.22") == true)
    }

    @Test func busyWithholdsTheClick() async {
        let status = await Self.check().status(
            of: Self.install(), settings: JunieSettings(), busy: .installer(42))
        #expect(status.withheld == .busy)
        #expect(status.oneClick == nil)
        #expect(status.note == "the Junie installer is running (pid 42)")
    }

    /// Mutation: dropping the bundle-version comparison offers an update to a
    /// build directory that holds another build.
    @Test func aBundleThatIsNotItsBuildIsAMismatch() async {
        let status = await Self.check().status(
            of: Self.install(version: "1543.24", bundleVersion: "1500.1"), settings: JunieSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .versionMismatch)
        #expect(status.oneClick == nil)
    }

    @Test func problemsAreBrokenAndAFeedFailureIsChannelUnreadable() async {
        let broken = await Self.check().status(
            of: Self.install(channel: nil, problem: .channelConflict), settings: JunieSettings(), busy: nil)
        #expect(broken.withheld == .broken)
        #expect(broken.state == .unknown)
        let unreadable = await JunieCheck(latest: { _ in throw JunieRelease.Failure.http(503) })
            .status(of: Self.install(), settings: JunieSettings(), busy: nil)
        #expect(unreadable.withheld == .channelUnreadable)
        #expect(unreadable.latestVersion == nil)
    }

    // MARK: - Busy

    func busy(_ box: JunieSandbox, processes: [ClaudeCodeActivity.Process] = [], alive: Set<pid_t> = [],
              now: Date = Date()) throws -> JunieActivity.Busy? {
        let install = try #require(box.scanner.scan().first)
        return JunieActivity.busy(install, processes: processes, now: now, isAlive: { alive.contains($0) })
    }

    @Test func installerProcessesAreSeen() throws {
        let box = try JunieSandbox()
        try box.install()
        func process(_ arguments: [String]) -> [ClaudeCodeActivity.Process] { [.init(pid: 7, arguments: arguments)] }
        #expect(try busy(box, processes: process([
            "curl", "-fSL", "--progress-bar", "-o", "/tmp/tmp.x",
            "https://github.com/JetBrains/junie/releases/download/3419.26/junie-release-3419.26-macos-aarch64.zip",
        ])) == .installer(7))
        #expect(try busy(box, processes: process(["curl", "-fsSL", "https://junie.jetbrains.com/install-eap.sh"])) == .installer(7))
        #expect(try busy(box, processes: process(["/bin/bash", "/tmp/duo-junie-x/junie-install-release.sh"])) == .installer(7))
        #expect(try busy(box, processes: process(["curl", "-fsSL", "https://example.invalid/install.sh"])) == nil)
    }

    /// A running session runs its own `versions/<build>`, which the installer
    /// never touches: not a reason to wait.
    @Test func aRunningSessionIsNotBusy() throws {
        let box = try JunieSandbox()
        try box.install()
        let session = box.data.appendingPathComponent("versions/3419.26/Applications/junie.app/Contents/MacOS/junie").path
        #expect(try busy(box, processes: [.init(pid: 9, arguments: [session])]) == nil)
        #expect(try busy(box, processes: [.init(pid: 9, arguments: ["/bin/bash", box.launcher.path])]) == nil)
    }

    /// A `.download` is live for ten minutes, Junie's own threshold. Mutation:
    /// dropping the age test keeps a left-behind file busy forever.
    @Test func aDownloadIsLiveForTenMinutes() throws {
        let box = try JunieSandbox()
        try box.install()
        let file = try box.write(box.data.appendingPathComponent("updates/junie-3579.2.zip.download"), "part")
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: file.path)
        #expect(try busy(box, now: now) == .downloading("junie-3579.2.zip.download"))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-11 * 60)], ofItemAtPath: file.path)
        #expect(try busy(box, now: now) == nil)
        let processing = try box.write(box.data.appendingPathComponent("updates/pending-update.json.processing"), "{}")
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: processing.path)
        #expect(try busy(box, now: now) == .applying)
    }

    /// A staging directory counts while the bash that owns it lives. Mutation:
    /// dropping the pid test makes a SIGKILLed install's leftover busy forever.
    @Test func aStagingDirectoryIsBusyWhileItsOwnerLives() throws {
        let box = try JunieSandbox()
        try box.install()
        try FileManager.default.createDirectory(
            at: box.data.appendingPathComponent("versions/.3579.2.tmp.4242"), withIntermediateDirectories: true)
        #expect(try busy(box, alive: [4242]) == .extracting(version: "3579.2", pid: 4242))
        #expect(try busy(box, alive: []) == nil)
        #expect(JunieActivity.stagingOwner(".3419.26.old.77")?.version == "3419.26")
        #expect(JunieActivity.stagingOwner(".DS_Store") == nil)
        #expect(JunieActivity.stagingOwner("3419.26") == nil)
    }

    // MARK: - Provider

    @Test func sightingCarriesWhatTheVerdictRestsOn() {
        let sighting = JunieProvider.sighting(Self.install(pending: "3419.22"))
        #expect(sighting.kind == .junie)
        #expect(sighting.version == "1543.24")
        #expect(sighting.state == "release|1543.24|3419.22|-|legacy")
    }

    @Test func reportCarriesTheSettings() async throws {
        let box = try JunieSandbox()
        try box.install("1543.24", shim: JunieSandbox.legacyShim, channelFile: nil, signer: "adhoc")
        let installs = box.scanner.scan().map(box.scanner.withSignature)
        let report = await JunieProvider.report(
            installs: installs, settings: JunieSettings(autoUpdate: false), processes: [], check: Self.check())
        #expect(report.context == .junie(JunieSettings(autoUpdate: false)))
        #expect(report.statuses.first?.withheld == .autoUpdateOff)
        #expect(report.sightings.first?.path == box.launcher.path)
        if case .junie(let install)? = report.statuses.first?.detail {
            #expect(install.signature == .adHoc)
        } else {
            Issue.record("no Junie detail")
        }
    }
}
