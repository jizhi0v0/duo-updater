import Testing
import Foundation
@testable import DuoUpdaterCore

/// Claude Code as a tracked command-line tool: where installs are found, which
/// settings are obeyed, what counts as an update already running, and when a
/// one-click update is offered.
///
/// Every test builds its own fake home in a temporary directory and injects the
/// signature check and the release lookups — nothing here reads the host's
/// `~/.local`, `~/.claude`, process table or network.
@Suite struct ClaudeCodeTests {

    // MARK: - Fixtures

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("claude-code-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A thin 64-bit Mach-O header for `cpu` (arm64 by default), `size` bytes long.
        @discardableResult
        func machO(_ path: String, size: Int = 64, cpu: UInt8 = 0x0C) throws -> URL {
            var bytes = [UInt8](repeating: 0, count: size)
            bytes[0] = 0xCF; bytes[1] = 0xFA; bytes[2] = 0xED; bytes[3] = 0xFE
            bytes[4] = cpu; bytes[7] = 0x01
            return try write(path, Data(bytes))
        }

        @discardableResult
        func write(_ path: String, _ data: Data) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        }

        func write(_ path: String, _ text: String) throws { try write(path, Data(text.utf8)) }

        func symlink(_ path: String, to destination: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        }

        /// An npm-style package directory at `package` (relative to root).
        func package(_ package: String, version: String, linked: Bool) throws {
            try write(package + "/package.json", #"{"name":"@anthropic-ai/claude-code","version":"\#(version)"}"#)
            if linked {
                try machO(package + "/bin/claude.exe")
            } else {
                try write(package + "/bin/claude.exe", "#!/bin/sh\necho 'Error: claude native binary not installed.' >&2\nexit 1\n")
            }
        }

        func scanner(prefixes: [String] = [], signature: ClaudeCodeInstall.Signature = .anthropic) -> ClaudeCodeScanner {
            ClaudeCodeScanner(
                home: home,
                systemPrefixes: prefixes.map { root.appendingPathComponent($0) },
                checkSignature: { _ in signature })
        }
    }

    // MARK: - Scanner: native

    @Test func nativeLauncherIsTheInstallAndItsTargetNamesTheVersion() throws {
        let box = try Sandbox()
        try box.machO("home/.local/share/claude/versions/2.1.266")
        try box.machO("home/.local/share/claude/versions/2.1.274")
        try box.symlink("home/.local/bin/claude", to: box.home.path + "/.local/share/claude/versions/2.1.274")

        let found = box.scanner().scan()
        #expect(found.count == 1)  // the older versions/ entry is a rollback copy, not an install
        let install = try #require(found.first)
        #expect(install.method == .native)
        #expect(install.version == "2.1.274")
        #expect(install.path == box.home.path + "/.local/bin/claude")
        #expect(install.signature == .anthropic)
        #expect(install.problem == nil)
    }

    /// What a failed native install leaves behind: `versions/<v>` as a zero-byte file.
    @Test func nativeLauncherToAnEmptyFileIsReportedAsMissing() throws {
        let box = try Sandbox()
        try box.write("home/.local/share/claude/versions/2.1.280", Data())
        try box.symlink("home/.local/bin/claude", to: box.home.path + "/.local/share/claude/versions/2.1.280")

        let install = try #require(box.scanner().scan().first)
        #expect(install.problem == .executableMissing)
        #expect(install.signature == nil)
    }

    /// A custom launcher (a regular file) decides its own version; without running
    /// it we cannot say which, so it is not claimed as a native install.
    @Test func customLauncherIsNotClaimed() throws {
        let box = try Sandbox()
        try box.machO("home/.local/share/claude/versions/2.1.274")
        try box.write("home/.local/bin/claude", "#!/bin/sh\nexec ~/.local/share/claude/versions/2.1.274 \"$@\"\n")
        #expect(box.scanner().scan().isEmpty)
    }

    // MARK: - Scanner: npm family

    @Test func npmPackageUnderANodePrefixCarriesThatPrefix() throws {
        let box = try Sandbox()
        try box.package("brew/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)

        let install = try #require(box.scanner(prefixes: ["brew"]).scan().first)
        #expect(install.method == .npm)
        #expect(install.version == "2.1.280")
        #expect(install.nodePrefix == box.root.appendingPathComponent("brew").path)
        #expect(install.problem == nil)
    }

    @Test func everyNvmNodeVersionIsItsOwnInstall() throws {
        let box = try Sandbox()
        try box.package("home/.nvm/versions/node/v22.1.0/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.259", linked: true)
        try box.package("home/.nvm/versions/node/v24.13.0/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)

        let found = box.scanner().scan()
        #expect(found.map(\.version) == ["2.1.259", "2.1.280"])
        #expect(Set(found.compactMap(\.nodePrefix)).count == 2)
    }

    /// pnpm 10 skips postinstall by default: the package is there, the binary is not.
    @Test func placeholderScriptIsNotLinked() throws {
        let box = try Sandbox()
        try box.package("home/Library/pnpm/global/5/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: false)

        let install = try #require(box.scanner().scan().first)
        #expect(install.method == .pnpm)
        #expect(install.problem == .nativeBinaryNotLinked)
        #expect(install.signature == nil)
    }

    /// bun skips postinstall, so `bin/claude.exe` stays the placeholder — but its
    /// shim links straight to the platform package's binary, which runs (bun 1.4.2).
    @Test func bunShimToThePlatformBinaryIsTheExecutable() throws {
        let box = try Sandbox()
        let modules = "home/.bun/install/global/node_modules/@anthropic-ai"
        try box.package(modules + "/claude-code", version: "2.1.280", linked: false)
        let binary = try box.machO(modules + "/claude-code-darwin-arm64/claude")
        try box.symlink("home/.bun/bin/claude", to: "../install/global/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude")

        let install = try #require(box.scanner().scan().first)
        #expect(install.method == .bun)
        #expect(install.problem == nil)
        #expect(install.signature == .anthropic)
        #expect(install.executable == binary.resolvingSymlinksInPath().path)
    }

    @Test func bunWithoutItsShimFallsBackToThePackagesBinary() throws {
        let box = try Sandbox()
        try box.package("home/.bun/install/global/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: false)
        let install = try #require(box.scanner().scan().first)
        #expect(install.problem == .nativeBinaryNotLinked)
    }

    /// `BUN_INSTALL` moved somewhere else, added by hand: the same bun reading.
    @Test func userAddedBunGlobalUnderACustomRootIsBun() throws {
        let box = try Sandbox()
        let modules = "tools/bun/install/global/node_modules/@anthropic-ai"
        try box.package(modules + "/claude-code", version: "2.1.280", linked: false)
        try box.machO(modules + "/claude-code-darwin-arm64/claude")
        try box.symlink("tools/bun/bin/claude", to: "../install/global/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude")

        let package = box.root.appendingPathComponent(modules + "/claude-code").path
        let install = try #require(box.scanner().scan(userPaths: [package]).first)
        #expect(install.method == .bun)
        #expect(install.origin == .userAdded)
        #expect(install.problem == nil)
    }

    /// A shim pointing outside this install's `node_modules` is some other copy.
    @Test func bunShimPointingElsewhereIsNotBelieved() throws {
        let box = try Sandbox()
        try box.package("home/.bun/install/global/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: false)
        let other = try box.machO("elsewhere/claude")
        try box.symlink("home/.bun/bin/claude", to: other.path)
        let install = try #require(box.scanner().scan().first)
        #expect(install.problem == .nativeBinaryNotLinked)
    }

    @Test func aDifferentPackageInTheSamePlaceIsIgnored() throws {
        let box = try Sandbox()
        try box.write("brew/lib/node_modules/@anthropic-ai/claude-code/package.json", #"{"name":"not-claude","version":"1.0.0"}"#)
        #expect(box.scanner(prefixes: ["brew"]).scan().isEmpty)
    }

    // MARK: - Scanner: user-added paths

    @Test func userAddedPackageUnderAPrefixWithItsOwnNpmIsNpm() throws {
        let box = try Sandbox()
        try box.package("custom/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)
        try box.write("custom/bin/npm", "#!/usr/bin/env node\n")

        let install = try #require(box.scanner().scan(userPaths: [box.root.path + "/custom/lib/node_modules/@anthropic-ai/claude-code"]).first)
        #expect(install.origin == .userAdded)
        #expect(install.method == .npm)
        #expect(install.nodePrefix == box.root.appendingPathComponent("custom").standardizedFileURL.path)
    }

    @Test func userAddedPackageWithoutAnNpmIsUnknown() throws {
        let box = try Sandbox()
        try box.package("loose/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)

        let install = try #require(box.scanner().scan(userPaths: [box.root.path + "/loose/lib/node_modules/@anthropic-ai/claude-code"]).first)
        #expect(install.method == .unknown)
        #expect(install.nodePrefix == nil)
    }

    /// A bare file is only believed to be Claude Code on the strength of its signature.
    @Test func userAddedBinaryNeedsAnthropicsSignature() throws {
        let box = try Sandbox()
        let binary = try box.machO("elsewhere/claude")
        #expect(box.scanner(signature: .otherSigner).scan(userPaths: [binary.path]).isEmpty)
        #expect(box.scanner(signature: .anthropic).scan(userPaths: [binary.path]).count == 1)
    }

    /// Claude.app ships its own copy at `…/claude-code/<v>/claude.app/Contents/MacOS/claude`:
    /// signed by Anthropic, and still the app's to update, never ours.
    @Test func aBinaryInsideAnAppIsNeverAnInstall() throws {
        let box = try Sandbox()
        let bundled = try box.machO("support/claude-code/2.1.284/claude.app/Contents/MacOS/claude")
        #expect(box.scanner().scan(userPaths: [bundled.path]).isEmpty)
    }

    /// The `cua-driver` shape: a symlink outside, pointing into a bundle.
    @Test func aSymlinkIntoAnAppIsNeverAnInstall() throws {
        let box = try Sandbox()
        let bundled = try box.machO("Apps/Tool.app/Contents/MacOS/claude")
        try box.symlink("home/bin/claude", to: bundled.path)
        #expect(box.scanner().scan(userPaths: [box.home.path + "/bin/claude"]).isEmpty)
        #expect(ClaudeCodeScanner.owningApp(of: box.home.path + "/bin/claude")?.lastPathComponent == "Tool.app")
    }

    /// An app that embeds a whole node prefix, found through the conventional roots.
    @Test func anNpmPackageInsideAnAppIsNeverAnInstall() throws {
        let box = try Sandbox()
        try box.package("Host.app/Contents/Resources/node/lib/node_modules/@anthropic-ai/claude-code", version: "2.1.280", linked: true)
        #expect(box.scanner(prefixes: ["Host.app/Contents/Resources/node"]).scan().isEmpty)
    }

    /// `brew install --cask claude-code`: `<prefix>/bin/claude` links into the
    /// Caskroom. Homebrew updates it, and the Homebrew list already shows it.
    @Test func aHomebrewCaskCopyIsNeverAnInstall() throws {
        let box = try Sandbox()
        let binary = try box.machO("brew/Caskroom/claude-code@latest/2.1.285/claude")
        try box.symlink("brew/bin/claude", to: binary.path)
        let launcher = box.root.appendingPathComponent("brew/bin/claude").path
        #expect(box.scanner().scan(userPaths: [launcher]).isEmpty)
        #expect(ClaudeCodeScanner.homebrewCask(of: launcher) == "claude-code@latest")
        #expect(ClaudeCodeScanner.homebrewCask(of: "/Users/x/.local/share/claude/versions/2.1.274") == nil)
    }

    @Test func pathsOutsideAnyAppHaveNoOwner() {
        #expect(ClaudeCodeScanner.owningApp(of: "/Users/x/.local/share/claude/versions/2.1.274") == nil)
        #expect(ClaudeCodeScanner.owningApp(of: "/Users/x/.nvm/versions/node/v24/lib/node_modules/@anthropic-ai/claude-code") == nil)
        #expect(ClaudeCodeScanner.owningApp(of: nil) == nil)
    }

    @Test func userAddedDuplicateOfAConventionalInstallIsListedOnce() throws {
        let box = try Sandbox()
        try box.machO("home/.local/share/claude/versions/2.1.274")
        try box.symlink("home/.local/bin/claude", to: box.home.path + "/.local/share/claude/versions/2.1.274")
        #expect(box.scanner().scan(userPaths: [box.home.path + "/.local/bin/claude"]).count == 1)
    }

    // MARK: - Settings

    func locations(_ box: Sandbox) -> ClaudeCodeSettings.Locations {
        ClaudeCodeSettings.Locations(
            userSettings: box.root.appendingPathComponent("home/.claude/settings.json"),
            managedDirectory: box.root.appendingPathComponent("managed"),
            managedPreferences: [box.root.appendingPathComponent("prefs/com.anthropic.claudecode.plist")])
    }

    @Test func defaultsAreLatestWithAutoUpdateOn() throws {
        let box = try Sandbox()
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .latest)
        #expect(settings.autoUpdatesEnabled)
        #expect(settings.sources.isEmpty)
    }

    @Test func userSettingsAreRead() throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", #"{"autoUpdatesChannel":"stable","minimumVersion":"2.1.100","env":{"DISABLE_AUTOUPDATER":"1"}}"#)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)
        #expect(settings.minimumVersion == "2.1.100")
        #expect(settings.autoUpdatesDisabled)
        #expect(!settings.updatesDisabled)
        #expect(!settings.autoUpdatesEnabled)
    }

    @Test func managedSettingsBeatUserSettingsKeyByKey() throws {
        let box = try Sandbox()
        try box.write("home/.claude/settings.json", #"{"autoUpdatesChannel":"latest","minimumVersion":"2.1.1"}"#)
        try box.write("managed/managed-settings.json", #"{"autoUpdatesChannel":"stable","env":{"DISABLE_UPDATES":"1"}}"#)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)            // managed wins
        #expect(settings.minimumVersion == "2.1.1")    // unset in managed: user's stands
        #expect(settings.updatesDisabled)
    }

    /// `managed-settings.json` first, then `managed-settings.d/*.json` alphabetically;
    /// later files win, hidden files are skipped.
    @Test func managedDropInsMergeInOrder() throws {
        let box = try Sandbox()
        try box.write("managed/managed-settings.json", #"{"autoUpdatesChannel":"latest"}"#)
        try box.write("managed/managed-settings.d/10-a.json", #"{"autoUpdatesChannel":"stable","env":{"A":"1"}}"#)
        try box.write("managed/managed-settings.d/20-b.json", #"{"env":{"DISABLE_AUTOUPDATER":"1"}}"#)
        try box.write("managed/managed-settings.d/.30-hidden.json", #"{"autoUpdatesChannel":"latest"}"#)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)
        #expect(settings.autoUpdatesDisabled)
    }

    /// First-wins across managed sources: an MDM profile hides the managed files.
    @Test func mdmProfileWinsTheManagedTier() throws {
        let box = try Sandbox()
        try box.write("managed/managed-settings.json", #"{"env":{"DISABLE_UPDATES":"1"}}"#)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["autoUpdatesChannel": "stable"], format: .xml, options: 0)
        try box.write("prefs/com.anthropic.claudecode.plist", plist)
        let settings = ClaudeCodeSettings.read(from: locations(box))
        #expect(settings.channel == .stable)
        #expect(!settings.updatesDisabled)
    }

    @Test func unknownChannelFallsBackToLatest() {
        let settings = ClaudeCodeSettings.resolve([("x", ["autoUpdatesChannel": "beta"])])
        #expect(settings.channel == .latest)
    }

    @Test(arguments: [
        ("1", true), ("true", true), ("yes", true),
        ("0", false), ("false", false), ("", false), (" ", false),
    ])
    func switchValues(value: String, expected: Bool) {
        #expect(ClaudeCodeSettings.isSet(value) == expected)
    }

    // MARK: - Activity

    let native = ClaudeCodeInstall(
        path: "/h/.local/bin/claude", method: .native, origin: .conventional,
        executable: "/h/.local/share/claude/versions/2.1.274", version: "2.1.274",
        signature: .anthropic, problem: nil)

    let npm = ClaudeCodeInstall(
        path: "/p/lib/node_modules/@anthropic-ai/claude-code", method: .npm, origin: .conventional,
        executable: "/p/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe", version: "2.1.280",
        signature: .anthropic, problem: nil, nodePrefix: "/p")

    func emptyStaging() throws -> (Sandbox, URL) {
        let box = try Sandbox()
        let staging = box.root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return (box, staging)
    }

    @Test func runningClaudeUpdateMakesTheNativeInstallBusy() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        let processes = [
            ClaudeCodeActivity.Process(pid: 10, arguments: ["claude"]),  // an ordinary session
            ClaudeCodeActivity.Process(pid: 11, arguments: ["/h/.local/share/claude/versions/2.1.274", "update"]),
        ]
        #expect(ClaudeCodeActivity.busy(native, processes: processes, stagingDirectory: staging) == .updateCommand(11))
        #expect(ClaudeCodeActivity.busy(native, processes: [processes[0]], stagingDirectory: staging) == nil)
    }

    /// `staging/<version>.<pid>.<ms>` — busy only while that pid is alive; a failed
    /// install leaves the directory behind with a dead pid.
    @Test func stagingDirectoryCountsOnlyWhileItsProcessLives() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("2.1.280.1352.1790771006787"), withIntermediateDirectories: true)
        #expect(ClaudeCodeActivity.busy(native, processes: [], stagingDirectory: staging, isAlive: { $0 == 1352 })
            == .staging(version: "2.1.280", pid: 1352))
        #expect(ClaudeCodeActivity.busy(native, processes: [], stagingDirectory: staging, isAlive: { _ in false }) == nil)
    }

    /// 2.1.280 and later add a random suffix: `<version>.<pid>.<ms>.<8 hex>` —
    /// the shape a background `claude update` of today's releases leaves.
    @Test func stagingDirectoryWithARandomSuffixStillNamesItsProcess() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("2.1.285.14423.1790776714136.d3714f38"), withIntermediateDirectories: true)
        #expect(ClaudeCodeActivity.busy(native, processes: [], stagingDirectory: staging, isAlive: { $0 == 14423 })
            == .staging(version: "2.1.285", pid: 14423))
    }

    @Test(arguments: [
        ("2.1.280.1352.1790771006787", "2.1.280", Int32(1352)),
        ("2.1.285.14423.1790776714136.d3714f38", "2.1.285", 14423),
        ("2.1.285.14423.1790776714136.12345678", "2.1.285", 14423),  // an all-digit suffix
    ])
    func stagingNamesParse(name: String, version: String, pid: Int32) {
        let owner = ClaudeCodeActivity.stagingOwner(name)
        #expect(owner?.version == version)
        #expect(owner?.pid == pid)
    }

    /// The bare `<version>` shape carries no pid, so it cannot be tied to a process.
    /// Read loosely it would be "version 2, pid 1", and launchd is always alive.
    @Test func stagingNameWithoutAPidHasNoOwner() throws {
        #expect(ClaudeCodeActivity.stagingOwner("2.1.285") == nil)
        let (box, staging) = try emptyStaging()
        _ = box
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("2.1.285"), withIntermediateDirectories: true)
        #expect(ClaudeCodeActivity.busy(native, processes: [], stagingDirectory: staging, isAlive: { _ in true }) == nil)
    }

    @Test func npmInstallingThePackageMakesTheNpmInstallBusy() throws {
        let (box, staging) = try emptyStaging()
        _ = box
        let installing = ClaudeCodeActivity.Process(
            pid: 20, arguments: ["node", "/p/lib/node_modules/npm/bin/npm-cli.js", "install", "-g", "@anthropic-ai/claude-code@latest"])
        let unrelated = ClaudeCodeActivity.Process(pid: 21, arguments: ["node", "server.js"])
        #expect(ClaudeCodeActivity.busy(npm, processes: [unrelated, installing], stagingDirectory: staging) == .packageManager(20))
        #expect(ClaudeCodeActivity.busy(npm, processes: [unrelated], stagingDirectory: staging) == nil)
        // A running `claude` session whose argv mentions the package is not a package manager.
        let session = ClaudeCodeActivity.Process(pid: 22, arguments: ["/p/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"])
        #expect(ClaudeCodeActivity.busy(npm, processes: [session], stagingDirectory: staging) == nil)
    }

    @Test func processArgumentsOfThisProcessAreReadable() throws {
        let arguments = try #require(ClaudeCodeActivity.arguments(of: getpid()))
        #expect(arguments.first == CommandLine.arguments.first)
    }

    // MARK: - Check

    /// `manifest` maps a platform key to the size its entry gives.
    func check(latest: String, manifest: [String: Int] = [:]) -> ClaudeCodeCheck {
        ClaudeCodeCheck(
            latest: { _, _ in latest },
            manifest: { _, platform in
                guard let size = manifest[platform] else { throw ClaudeCodeRelease.Failure.unreadable }
                return .init(size: size, sha256: "")
            })
    }

    @Test func nativeUpdateIsOfferedAsClaudeUpdate() async {
        let status = await check(latest: "2.1.285").status(of: native, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == .init(executable: "/h/.local/bin/claude", arguments: ["update"], pathPrefix: nil))
        #expect(status.note == nil)
        #expect(status.withheld == nil)
    }

    @Test func autoUpdateOffMeansReportedButNotOffered() async {
        var settings = ClaudeCodeSettings()
        settings.autoUpdatesDisabled = true
        let status = await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.note?.contains("DISABLE_AUTOUPDATER") == true)
        #expect(status.withheld == .autoUpdateOff)
    }

    @Test func updatesDisabledMeansReportedButNotOffered() async {
        var settings = ClaudeCodeSettings()
        settings.updatesDisabled = true
        let status = await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.withheld == .updatesDisabled)
        // Both set: the stronger switch is the one named.
        settings.autoUpdatesDisabled = true
        #expect(await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil).withheld == .updatesDisabled)
    }

    @Test func anUpdateAlreadyRunningWithholdsOneClick() async {
        let status = await check(latest: "2.1.285").status(of: native, settings: ClaudeCodeSettings(), busy: .updateCommand(7))
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.note == ClaudeCodeActivity.Busy.updateCommand(7).description)
        #expect(status.withheld == .busy)
    }

    @Test func aChannelBelowTheFloorIsNotAnUpdate() async {
        var settings = ClaudeCodeSettings()
        settings.minimumVersion = "2.1.300"
        let status = await check(latest: "2.1.285").status(of: native, settings: settings, busy: nil)
        #expect(status.state == .upToDate)
        #expect(status.oneClick == nil)
        #expect(status.withheld == nil)  // nothing to offer is not something withheld
    }

    @Test func aheadOfTheChannelIsNotAnUpdate() async {
        let status = await check(latest: "2.1.270").status(of: native, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .ahead)
        #expect(status.oneClick == nil)
        #expect(status.withheld == nil)
    }

    /// The npm command names this prefix's own node and npm, pins `--prefix`, and
    /// asks for the dist-tag of the user's channel.
    @Test func npmUpdateUsesThePrefixesOwnNpmAndChannel() async throws {
        let box = try Sandbox()
        try box.write("p/bin/npm", "#!/usr/bin/env node\n")
        let node = try box.write("p/bin/node", Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let prefix = box.root.appendingPathComponent("p").path
        let install = ClaudeCodeInstall(
            path: prefix + "/lib/node_modules/@anthropic-ai/claude-code", method: .npm, origin: .conventional,
            executable: nil, version: "2.1.280", signature: .anthropic, problem: nil, nodePrefix: prefix)
        var settings = ClaudeCodeSettings()
        settings.channel = .stable

        let status = await check(latest: "2.1.285").status(of: install, settings: settings, busy: nil)
        let command = try #require(status.oneClick)
        #expect(command.executable == prefix + "/bin/node")
        #expect(command.arguments == [prefix + "/bin/npm", "install", "-g", "--prefix", prefix, "@anthropic-ai/claude-code@stable"])
        #expect(command.pathPrefix == prefix + "/bin")
        #expect(status.withheld == nil)
    }

    @Test func npmPrefixWithoutItsOwnNodeIsNotOffered() async {
        let status = await check(latest: "2.1.285").status(of: npm, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.withheld == .noOwnNpm)
    }

    @Test func pnpmAndUnknownInstallsAreDetectionOnly() async {
        for method in [ClaudeCodeInstall.Method.pnpm, .bun, .unknown] {
            let install = ClaudeCodeInstall(
                path: "/x", method: method, origin: .conventional, executable: nil, version: "2.1.280",
                signature: .anthropic, problem: nil)
            let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
            #expect(status.state == .updateAvailable)
            #expect(status.oneClick == nil, "\(method)")
            #expect(status.withheld == .unsupportedInstaller, "\(method)")
        }
    }

    @Test func aFileThatIsNotTheReleaseItsLayoutNamesIsNotOffered() async throws {
        let box = try Sandbox()
        let binary = try box.machO("home/.local/share/claude/versions/2.1.274", size: 100)
        let install = ClaudeCodeInstall(
            path: "/h/.local/bin/claude", method: .native, origin: .conventional,
            executable: binary.path, version: "2.1.274", signature: .anthropic, problem: nil)

        let mismatch = await check(latest: "2.1.285", manifest: ["darwin-arm64": 99]).status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(mismatch.versionConfirmed == false)
        #expect(mismatch.oneClick == nil)
        #expect(mismatch.withheld == .versionMismatch)

        let match = await check(latest: "2.1.285", manifest: ["darwin-arm64": 100]).status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(match.versionConfirmed == true)
        #expect(match.oneClick != nil)
        #expect(match.withheld == nil)
    }

    /// An x64 copy (npm under an Intel Homebrew node) is held against the
    /// `darwin-x64` entry whatever Mac it sits on — not against the host's.
    @Test func theManifestEntryIsTheBinarysOwnArchitecture() async throws {
        let box = try Sandbox()
        let binary = try box.machO("x64/claude.exe", size: 100, cpu: 0x07)
        let install = ClaudeCodeInstall(
            path: "/usr/local/lib/node_modules/@anthropic-ai/claude-code", method: .npm, origin: .conventional,
            executable: binary.path, version: "2.1.280", signature: .anthropic, problem: nil)
        let status = await check(latest: "2.1.285", manifest: ["darwin-arm64": 999, "darwin-x64": 100])
            .status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.versionConfirmed == true)
    }

    @Test func platformIsReadFromTheMachOHeader() throws {
        let box = try Sandbox()
        #expect(ClaudeCodeRelease.platform(of: try box.machO("a", cpu: 0x0C)) == "darwin-arm64")
        #expect(ClaudeCodeRelease.platform(of: try box.machO("b", cpu: 0x07)) == "darwin-x64")
        // Fat (universal) header: which slice runs is not ours to guess — unchecked.
        let fat = try box.write("c", Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2]))
        #expect(ClaudeCodeRelease.platform(of: fat) == nil)
        #expect(ClaudeCodeRelease.platform(of: box.root.appendingPathComponent("missing")) == nil)
    }

    /// `claude update` writes to `~/.local/share/claude` whatever it is run from,
    /// so a native copy elsewhere must not be offered it: that would update a
    /// different place than the row shows.
    @Test func aUserAddedNativeBinaryElsewhereIsDetectionOnly() async throws {
        let box = try Sandbox()
        let binary = try box.machO("other/claude/versions/2.1.274")
        let install = try #require(box.scanner().scan(userPaths: [binary.path]).first)
        #expect(install.method == .unknown)
        #expect(install.version == "2.1.274")
        let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
    }

    @Test func notAnthropicsIsNeverCompared() async {
        let install = ClaudeCodeInstall(
            path: "/x", method: .native, origin: .conventional, executable: "/x", version: "2.1.1",
            signature: .otherSigner, problem: nil)
        let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.oneClick == nil)
        #expect(status.withheld == .notAnthropic)
    }

    /// A broken copy is reported as broken before anything else is asked of it —
    /// its signature included (a missing file has none).
    @Test func aBrokenInstallIsNeverCompared() async {
        let install = ClaudeCodeInstall(
            path: "/x", method: .native, origin: .conventional, executable: "/x", version: "2.1.280",
            signature: nil, problem: .executableMissing)
        let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .broken)
    }

    @Test func anUnreadableVersionIsNeverCompared() async {
        let install = ClaudeCodeInstall(
            path: "/x", method: .unknown, origin: .userAdded, executable: "/x", version: nil,
            signature: .anthropic, problem: nil)
        let status = await check(latest: "2.1.285").status(of: install, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .versionUnreadable)
    }

    @Test func anUnreadableChannelIsNotAVerdict() async {
        let check = ClaudeCodeCheck(
            latest: { _, _ in throw ClaudeCodeRelease.Failure.http(503) },
            manifest: { _, _ in throw ClaudeCodeRelease.Failure.unreadable })
        let status = await check.status(of: native, settings: ClaudeCodeSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.oneClick == nil)
        #expect(status.withheld == .channelUnreadable)
    }
}
