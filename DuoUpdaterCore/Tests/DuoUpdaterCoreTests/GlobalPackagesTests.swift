import Testing
import Foundation
@testable import DuoUpdaterCore

/// A scratch home holding pnpm's and Yarn's global installs and the copies of
/// the tools that change them, laid out as each one leaves them (measured
/// 2026-10-13: pnpm 10.33.2, 11.28.4, 12.9.1; Yarn 1.22.22; corepack's cache).
///
/// Every node here is a shell script: one whose text says `SIGNER:node` reads as
/// signed by the Node.js Foundation, any other as ad hoc. A "node" runs its
/// script argument with `/bin/sh`, so a fake pnpm or Yarn is a shell script too.
/// Nothing reaches the network or runs a real package manager.
final class GlobalSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var homebrew: URL { root.appendingPathComponent("homebrew") }
    var nvm: URL { home.appendingPathComponent(".nvm/versions/node/v24.13.0") }
    var pnpmHome: URL { home.appendingPathComponent("Library/pnpm") }
    var yarnGlobal: URL { home.appendingPathComponent(".config/yarn/global") }
    var corepack: URL { home.appendingPathComponent(".cache/node/corepack") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("global-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var checkSignature: NpmScanner.SignatureCheck {
        { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return text.contains("SIGNER:node") ? .vendor : .adHoc
        }
    }

    var managers: GlobalPackageManagers {
        GlobalPackageManagers(
            home: home, prefixes: [NodePrefix(path: nvm.path, source: .nvm, layoutNodeVersion: "24.13.0")],
            homebrewRoots: [homebrew], checkSignature: checkSignature)
    }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    func link(_ url: URL, to destination: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    /// nvm's node 24.13.0, signed by the Node.js Foundation unless `signed` is
    /// false: it runs its first argument with `/bin/sh`.
    func nvmNode(signed: Bool = true) throws {
        try write(nvm.appendingPathComponent("bin/node"),
                  "#!/bin/sh\n# SIGNER:\(signed ? "node" : "nobody")\nexec /bin/sh \"$@\"\n", executable: true)
    }

    /// corepack's shim for `tool` in nvm's prefix, and its cache of `version`
    /// as the Last Known Good one, the script being `body`.
    func corepackShim(_ tool: String, version: String, script: String, body: String = "exit 0\n") throws {
        try write(nvm.appendingPathComponent("lib/node_modules/corepack/dist/\(tool).js"), "// corepack\n")
        try link(nvm.appendingPathComponent("bin/\(tool)"), to: "../lib/node_modules/corepack/dist/\(tool).js")
        let goodFile = corepack.appendingPathComponent("lastKnownGood.json")
        var good = ((try? Data(contentsOf: goodFile)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }) ?? [:]
        good[tool] = "\(version)+sha512.abc"
        try FileManager.default.createDirectory(at: corepack, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: good).write(to: goodFile)
        try write(corepack.appendingPathComponent("v1/\(tool)/\(version)/bin/\(script)"), body, executable: true)
    }

    /// `npm install -g <tool>@<version>` in nvm's prefix.
    func npmInstalled(_ tool: String, version: String, bin: String) throws {
        let package = nvm.appendingPathComponent("lib/node_modules/\(tool)")
        try write(package.appendingPathComponent("package.json"),
                  #"{"name":"\#(tool)","version":"\#(version)","bin":{"\#(tool)":"\#(bin)"}}"#)
        try write(package.appendingPathComponent(bin), "exit 0\n", executable: true)
        try link(nvm.appendingPathComponent("bin/\(tool)"), to: "../lib/node_modules/\(tool)/\(bin)")
    }

    /// Homebrew's pnpm formula: a binary in its keg, beside the receipt.
    func homebrewPnpm(_ version: String = "12.11.2") throws {
        let keg = homebrew.appendingPathComponent("Cellar/pnpm/\(version)")
        try write(keg.appendingPathComponent("bin/pnpm"), "#!/bin/sh\nexit 0\n", executable: true)
        try write(keg.appendingPathComponent("INSTALL_RECEIPT.json"), "{}")
        try link(homebrew.appendingPathComponent("opt/pnpm"), to: "../Cellar/pnpm/\(version)")
        try link(homebrew.appendingPathComponent("bin/pnpm"), to: "../Cellar/pnpm/\(version)/bin/pnpm")
    }

    /// pnpm's standalone binary in its home (pnpm 10's layout).
    func standalonePnpm() throws {
        try write(pnpmHome.appendingPathComponent("pnpm"), "#!/bin/sh\nexit 0\n", executable: true)
    }

    /// A package's own directory: its `package.json` with a `bin`.
    func package(_ directory: URL, name: String, version: String) throws {
        try write(directory.appendingPathComponent("package.json"),
                  #"{"name":"\#(name)","version":"\#(version)","bin":{"\#(name)":"cli.js"}}"#)
    }

    /// pnpm 10's shared project `global/5`: `name` linked into its `.pnpm`.
    func pnpm10Project(_ name: String = "cowsay", version: String = "1.5.0", specifier: String = "^1.5.0") throws {
        let project = pnpmHome.appendingPathComponent("global/5")
        try write(project.appendingPathComponent("package.json"), #"{"dependencies":{"\#(name)":"\#(specifier)"}}"#)
        let real = project.appendingPathComponent("node_modules/.pnpm/\(name)@\(version)/node_modules/\(name)")
        try package(real, name: name, version: version)
        try link(project.appendingPathComponent("node_modules/\(name)"), to: ".pnpm/\(name)@\(version)/node_modules/\(name)")
    }

    /// pnpm 11's project for `name`: the group `global/v11/<group>`, its hash
    /// link, and `node_modules/<name>` linked into the home's store.
    @discardableResult
    func pnpm11Project(
        _ name: String = "cowsay", version: String = "1.5.0", specifier: String = "^1.5.0", group: String = "86ea-1"
    ) throws -> URL {
        let v11 = pnpmHome.appendingPathComponent("global/v11")
        let directory = v11.appendingPathComponent(group)
        try write(directory.appendingPathComponent("package.json"), #"{"dependencies":{"\#(name)":"\#(specifier)"}}"#)
        let store = "store/v11/links/@/\(name)/\(version)/abc/node_modules/\(name)"
        try package(pnpmHome.appendingPathComponent(store), name: name, version: version)
        try link(directory.appendingPathComponent("node_modules/\(name)"), to: "../../../../\(store)")
        let hash = v11.appendingPathComponent("hash-\(name)")
        try? FileManager.default.removeItem(at: hash)
        try link(hash, to: group)
        return hash
    }

    /// Yarn 1's global folder holding `name`, its `yarn.lock` keyed by `specifier`.
    func yarnGlobalFolder(_ name: String = "cowsay", version: String = "1.5.0", specifier: String = "^1.5.0") throws {
        try write(yarnGlobal.appendingPathComponent("package.json"), "{\n  \"dependencies\": {\n    \"\(name)\": \"\(specifier)\"\n  }\n}\n")
        try write(yarnGlobal.appendingPathComponent("yarn.lock"), Self.yarnLock(name, key: specifier, version: version))
        try package(yarnGlobal.appendingPathComponent("node_modules/\(name)"), name: name, version: version)
    }

    static func yarnLock(_ name: String, key: String, version: String) -> String {
        "# THIS IS AN AUTOGENERATED FILE. DO NOT EDIT THIS FILE DIRECTLY.\n# yarn lockfile v1\n\n\n\(name)@\(key):\n  version \"\(version)\"\n  resolved \"https://registry.yarnpkg.com/\(name)/-/\(name)-\(version).tgz\"\n"
    }

    var pnpmPackages: PnpmPackages {
        PnpmPackages(home: home, systemPrefixes: [homebrew], checkNodeSignature: checkSignature)
    }

    var yarnPackages: YarnPackages {
        YarnPackages(home: home, systemPrefixes: [homebrew], checkNodeSignature: checkSignature)
    }
}

@Suite struct GlobalPackagesTests {

    static let packument = NpmPackument(distTags: ["latest": "1.6.0"], versions: ["1.5.0": .init(), "1.6.0": .init()])

    static func status(_ install: NpmInstall) async -> CLIToolStatus {
        await NpmCheck(packument: { _ in packument }).status(of: install, busy: nil)
    }

    // MARK: - Finding pnpm and Yarn

    /// Each source as its installer leaves it. Mutations: read the corepack
    /// version from anywhere but Last Known Good; trust the standalone binary;
    /// take a shim whose version is not cached.
    @Test func findsEachCopyOfPnpm() throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.homebrewPnpm()
        try box.standalonePnpm()
        let found = box.managers.discover(.pnpm)
        #expect(found.map(\.source) == [.corepack, .homebrew, .standalone])
        let corepack = try #require(found.first)
        #expect(corepack.version == "10.33.2")
        #expect(corepack.executable == box.nvm.appendingPathComponent("bin/node").path)
        #expect(corepack.script == box.corepack.appendingPathComponent("v1/pnpm/10.33.2/bin/pnpm.cjs").path)
        #expect(corepack.isTrusted)
        #expect(found[1].version == "12.11.2" && found[1].script == nil && found[1].isTrusted)
        #expect(found[2].version == nil && !found[2].isTrusted)

        let uncached = try GlobalSandbox()
        try uncached.nvmNode()
        try uncached.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try FileManager.default.removeItem(at: uncached.corepack.appendingPathComponent("v1"))
        #expect(uncached.managers.discover(.pnpm).isEmpty)
    }

    /// npm's own install, run by the prefix's node; its trust is the node's.
    @Test func npmsInstallRunsOnItsPrefixsNode() throws {
        let box = try GlobalSandbox()
        try box.nvmNode(signed: false)
        try box.npmInstalled("yarn", version: "1.22.22", bin: "bin/yarn.js")
        let yarn = try #require(box.managers.discover(.yarn).first)
        #expect(yarn.source == .npm)
        #expect(yarn.script == box.nvm.appendingPathComponent("lib/node_modules/yarn/bin/yarn.js").path)
        #expect(!yarn.isTrusted)
    }

    /// The layout decides which pnpm reads it, and a trusted copy beats one that
    /// is not. Mutations: ignore the layout; prefer the untrusted copy.
    @Test func picksThePnpmThatReadsTheLayout() throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.homebrewPnpm("12.11.2")
        try box.standalonePnpm()
        let all = box.managers.discover(.pnpm)
        let shared = GlobalPackageManagers.pick(all) { $0.major.map { $0 <= 10 } ?? true }
        let isolated = GlobalPackageManagers.pick(all) { $0.major.map { $0 >= 11 } ?? true }
        #expect(shared?.version == "10.33.2")
        #expect(isolated?.version == "12.11.2")
        let onlyStandalone = GlobalPackageManagers.pick(all.filter { $0.source == .standalone }) { _ in true }
        #expect(onlyStandalone?.source == .standalone)
    }

    // MARK: - Reading the global installs

    /// pnpm 10's links into `.pnpm` are how it installs, not `pnpm link`; a link
    /// out of the store is. Mutation: drop the store roots (every row linked).
    @Test func pnpm10ProjectIsReadThroughItsLinks() throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.pnpm10Project()
        let elsewhere = box.root.appendingPathComponent("work/mytool")
        try box.package(elsewhere, name: "mytool", version: "0.1.0")
        let manifest = box.pnpmHome.appendingPathComponent("global/5/package.json")
        try box.write(manifest, #"{"dependencies":{"cowsay":"^1.5.0","mytool":"link:\#(elsewhere.path)"}}"#)
        try box.link(box.pnpmHome.appendingPathComponent("global/5/node_modules/mytool"), to: elsewhere.path)

        let installs = box.pnpmPackages.scan(managers: box.managers.discover(.pnpm))
        #expect(installs.map(\.name) == ["cowsay", "mytool"])
        let cowsay = installs[0]
        #expect(cowsay.version == "1.5.0")
        #expect(cowsay.linkTarget == nil)
        #expect(cowsay.specifier == "^1.5.0")
        #expect(cowsay.global?.isolated == false)
        #expect(cowsay.global?.manager?.source == .corepack)
        #expect(cowsay.global?.manifest == manifest.path)
        #expect(installs[1].linkTarget != nil)
    }

    /// pnpm 11's hash link is the package's path: it stays while each update
    /// moves it to a new project.
    @Test func pnpm11ProjectIsReadThroughItsHashLink() throws {
        let box = try GlobalSandbox()
        try box.homebrewPnpm()
        let hash = try box.pnpm11Project()
        let installs = box.pnpmPackages.scan(managers: box.managers.discover(.pnpm))
        let cowsay = try #require(installs.first)
        #expect(cowsay.path == hash.appendingPathComponent("node_modules/cowsay").path)
        #expect(cowsay.linkTarget == nil)
        #expect(cowsay.global?.isolated == true)
        #expect(cowsay.global?.manager?.source == .homebrew)
        #expect(cowsay.global?.manifest == hash.appendingPathComponent("package.json").path)
    }

    @Test func yarnGlobalFolderIsRead() throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("yarn", version: "1.22.22", script: "yarn.js")
        try box.yarnGlobalFolder()
        let cowsay = try #require(box.yarnPackages.scan(managers: box.managers.discover(.yarn)).first)
        #expect(cowsay.specifier == "^1.5.0")
        #expect(cowsay.global?.tool == .yarn)
        #expect(cowsay.global?.manager?.version == "1.22.22")
        #expect(cowsay.prefix.path == box.yarnGlobal.path)
    }

    // MARK: - The check

    /// Each tool's command for the checked version, with its node first on `PATH`.
    /// Mutations: `add` for pnpm 10 (writes the exact version); `update` for
    /// pnpm 11 (changes nothing); the npm group's kind.
    @Test func eachToolsCommandKeepsTheUsersSpecifier() async throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.corepackShim("yarn", version: "1.22.22", script: "yarn.js")
        try box.pnpm10Project()
        try box.yarnGlobalFolder()
        let node = box.nvm.appendingPathComponent("bin/node").path
        let bin = box.nvm.appendingPathComponent("bin").path

        let pnpm = await Self.status(try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first))
        #expect(pnpm.kind == .pnpm)
        #expect(pnpm.oneClick == CLIToolCommand(
            executable: node,
            arguments: [box.corepack.appendingPathComponent("v1/pnpm/10.33.2/bin/pnpm.cjs").path, "update", "-g", "cowsay@1.6.0"],
            pathPrefix: bin))

        let yarn = await Self.status(try #require(box.yarnPackages.scan(managers: box.managers.discover(.yarn)).first))
        #expect(yarn.kind == .yarn)
        #expect(yarn.oneClick?.arguments.suffix(3) == ["global", "add", "cowsay@1.6.0"])

        let isolated = try GlobalSandbox()
        try isolated.homebrewPnpm()
        try isolated.homebrewNode()
        try isolated.pnpm11Project()
        let eleven = await Self.status(try #require(isolated.pnpmPackages.scan(managers: isolated.managers.discover(.pnpm)).first))
        #expect(eleven.oneClick == CLIToolCommand(
            executable: isolated.homebrew.appendingPathComponent("Cellar/pnpm/12.11.2/bin/pnpm").path,
            arguments: ["add", "-g", "cowsay@1.6.0"], pathPrefix: nil))
    }

    /// An exact specifier is the user's pin in pnpm's and Yarn's lists too, and
    /// the command to copy is the tool's own add without a version.
    @Test func anExactSpecifierIsAPinForPnpmAndYarn() async throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.pnpm10Project(specifier: "1.5.0")
        let status = await Self.status(try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first))
        #expect(status.state == .pinned)
        #expect(status.oneClick == nil)
        #expect(status.commandToCopy == CLIToolCommand(
            executable: box.nvm.appendingPathComponent("bin/pnpm").path, arguments: ["add", "-g", "cowsay"], pathPrefix: nil))
    }

    /// Only pnpm's standalone binary reads the layout: reported, with the command
    /// for the user to run. None at all: reported, without one. Mutations: run
    /// the standalone binary; offer the command without a pnpm.
    @Test func gatesWithoutARunnablePnpm() async throws {
        let box = try GlobalSandbox()
        try box.homebrewNode()
        try box.standalonePnpm()
        try box.pnpm10Project()
        let standalone = await Self.status(try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first))
        #expect(standalone.state == .updateAvailable)
        #expect(standalone.oneClick == nil)
        #expect(standalone.withheld == .unverified)
        #expect(standalone.commandToCopy == CLIToolCommand(
            executable: box.pnpmHome.appendingPathComponent("pnpm").path, arguments: ["update", "-g", "cowsay@1.6.0"],
            pathPrefix: nil))
        #expect(CLIToolWording.reason(.unverified, of: standalone).contains("pnpm"))

        let none = try GlobalSandbox()
        try none.homebrewNode()
        try none.pnpm11Project()
        let missing = await Self.status(try #require(none.pnpmPackages.scan(managers: none.managers.discover(.pnpm)).first))
        #expect(missing.withheld == .updaterMissing)
        #expect(missing.commandToCopy == nil)
    }

    /// A pnpm whose node is not trusted is not run. Mutation: skip the node in
    /// the gate.
    @Test func anUntrustedNodeHoldsBackItsPnpm() async throws {
        let box = try GlobalSandbox()
        try box.nvmNode(signed: false)
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.pnpm10Project()
        let status = await Self.status(try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first))
        #expect(status.oneClick == nil)
        #expect(status.withheld == .unverified)
        #expect(status.note?.contains("neither signed by the Node.js Foundation nor a Homebrew keg") == true)
    }

    // MARK: - Running the update

    /// pnpm needs its home in a GUI app's environment; the shell's settings that
    /// would send it elsewhere are dropped. Homebrew's Yarn gets its `PREFIX`.
    @Test func environmentForPnpmAndYarn() throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.pnpm10Project()
        let install = try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first)
        let command = CLIToolCommand(executable: "/n/bin/node", arguments: [], pathPrefix: "/n/bin")
        let environment = NpmUpdater.childEnvironment(
            ["HOME": box.home.path, "PNPM_HOME": "/elsewhere", "npm_config_global_dir": "/x"], command: command,
            global: install.global)
        #expect(environment["PNPM_HOME"] == box.pnpmHome.path)
        #expect(environment["npm_config_global_dir"] == nil)
        #expect(environment["PATH"] == "/n/bin:\(box.pnpmHome.path):\(box.pnpmHome.path)/bin:" + CLIToolCommandRunner.systemPath)

        let yarn = GlobalInstall(
            tool: .yarn,
            manager: GlobalPackageManager(tool: .yarn, version: "1.22.22", source: .homebrew, path: "/h/bin/yarn",
                                          executable: "/h/bin/node", script: "/h/Cellar/yarn/1.22.22/libexec/bin/yarn.js",
                                          runtime: nil, homebrewKeg: "/h/Cellar/yarn/1.22.22", homebrewRoot: "/h"),
            home: "/g", manifest: "/g/package.json", isolated: false)
        #expect(NpmUpdater.childEnvironment([:], command: command, global: yarn)["PREFIX"] == "/h")
    }

    /// Yarn refuses a `package.json` its lock does not match: the new range is
    /// added to the key line beside the exact one — quoted as Yarn quotes a
    /// scoped name — on a line of its own and on one shared with another
    /// package's range alike. A lock that does not name it once: nothing.
    /// Mutation: replace the exact pattern (a shared line loses the other
    /// package's pattern too, if it was the same).
    @Test func yarnLockKeys() {
        let lock = GlobalSandbox.yarnLock("cowsay", key: "1.6.0", version: "1.6.0")
        #expect(NpmUpdater.rewrittenYarnLockKey(lock, name: "cowsay", version: "1.6.0", to: "^1.6.0")
            == GlobalSandbox.yarnLock("cowsay", key: "1.6.0, cowsay@^1.6.0", version: "1.6.0"))
        let scoped = "\"@scope/tool@2.0.0\":\n  version \"2.0.0\"\n"
        #expect(NpmUpdater.rewrittenYarnLockKey(scoped, name: "@scope/tool", version: "2.0.0", to: "~2.0.0")
            == "\"@scope/tool@2.0.0\", \"@scope/tool@~2.0.0\":\n  version \"2.0.0\"\n")
        let shared = "cowsay@1.6.0, cowsay@^1.0.0:\n  version \"1.6.0\"\n"
        #expect(NpmUpdater.rewrittenYarnLockKey(shared, name: "cowsay", version: "1.6.0", to: "^1.6.0")
            == "cowsay@1.6.0, cowsay@^1.0.0, cowsay@^1.6.0:\n  version \"1.6.0\"\n")
        let other = "cowsay@^1.0.0:\n  version \"1.6.0\"\n"
        #expect(NpmUpdater.rewrittenYarnLockKey(other, name: "cowsay", version: "1.6.0", to: "^1.6.0") == nil)
    }

    /// End to end with a fake Yarn that does what `yarn global add <name>@<version>`
    /// does: the exact version in `package.json`, the lock's key and the package.
    /// Both come back in the user's style. Mutation: restore only `package.json`.
    @Test func yarnUpdateKeepsTheUsersRangeInBothFiles() async throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        let fake = """
            spec="$3"; name="${spec%@*}"; version="${spec##*@}"
            g="$HOME/.config/yarn/global"
            printf '{\\n  "dependencies": {\\n    "%s": "%s"\\n  }\\n}\\n' "$name" "$version" > "$g/package.json"
            printf '# yarn lockfile v1\\n\\n\\n%s@%s:\\n  version "%s"\\n' "$name" "$version" "$version" > "$g/yarn.lock"
            printf '{"name":"%s","version":"%s","bin":{"%s":"cli.js"}}' "$name" "$version" "$name" > "$g/node_modules/$name/package.json"
            """
        try box.corepackShim("yarn", version: "1.22.22", script: "yarn.js", body: fake)
        try box.yarnGlobalFolder()
        let status = await Self.status(try #require(box.yarnPackages.scan(managers: box.managers.discover(.yarn)).first))
        let home = box.home.path
        let outcome = await NpmUpdater(busy: { _ in nil }, environment: { ["HOME": home] }).update(status)
        #expect(outcome == .updated(version: "1.6.0"))
        let manifest = try String(contentsOf: box.yarnGlobal.appendingPathComponent("package.json"), encoding: .utf8)
        #expect(manifest.contains(#""cowsay": "^1.6.0""#))
        let lock = try String(contentsOf: box.yarnGlobal.appendingPathComponent("yarn.lock"), encoding: .utf8)
        #expect(lock.contains("\ncowsay@1.6.0, cowsay@^1.6.0:\n"))
    }

    /// End to end with a fake pnpm 11: `add -g` makes a new project with the
    /// exact version and moves the hash link to it. The version is read through
    /// the links, and the range comes back in the new project. Mutations: read
    /// the version without following links (unreadable); restore in the old
    /// project's file.
    @Test func pnpm11UpdateFollowsTheHashLink() async throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        let v11 = box.pnpmHome.appendingPathComponent("global/v11").path
        let store = box.pnpmHome.appendingPathComponent("store/v11/links/@").path
        let fake = """
            spec="$3"; name="${spec%@*}"; version="${spec##*@}"
            new="\(v11)/new-group"
            mkdir -p "$new/node_modules" "\(store)/$name/$version/def/node_modules/$name"
            printf '{"name":"%s","version":"%s","bin":{"%s":"cli.js"}}' "$name" "$version" "$name" > "\(store)/$name/$version/def/node_modules/$name/package.json"
            ln -s "../../../../store/v11/links/@/$name/$version/def/node_modules/$name" "$new/node_modules/$name"
            printf '{"dependencies":{"%s":"%s"}}' "$name" "$version" > "$new/package.json"
            rm "\(v11)/hash-$name"; ln -s new-group "\(v11)/hash-$name"
            """
        try box.corepackShim("pnpm", version: "11.28.4", script: "pnpm.cjs", body: fake)
        try box.pnpm11Project()
        let status = await Self.status(try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first))
        #expect(status.oneClick?.arguments.suffix(3) == ["add", "-g", "cowsay@1.6.0"])
        let home = box.home.path
        let outcome = await NpmUpdater(busy: { _ in nil }, environment: { ["HOME": home] }).update(status)
        #expect(outcome == .updated(version: "1.6.0"))
        let manifest = try String(contentsOf: URL(fileURLWithPath: v11).appendingPathComponent("new-group/package.json"), encoding: .utf8)
        #expect(manifest == #"{"dependencies":{"cowsay":"^1.6.0"}}"#)
    }

    /// Mutation: dropping the click-time re-check runs a pnpm that has gone.
    @Test func aPnpmNoLongerTrustedRunsNothing() async throws {
        let box = try GlobalSandbox()
        try box.nvmNode()
        try box.corepackShim("pnpm", version: "10.33.2", script: "pnpm.cjs")
        try box.pnpm10Project()
        let status = await Self.status(try #require(box.pnpmPackages.scan(managers: box.managers.discover(.pnpm)).first))
        let outcome = await NpmUpdater(busy: { _ in nil }, trustsManager: { _ in false }, environment: { [:] }).update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("ran"); return }
        #expect(message.contains("no longer a pnpm DuoUpdater may run"))
    }

    // MARK: - Busy

    @Test func pnpmAndYarnChangingTheirGlobalPackagesAreBusy() throws {
        let box = try GlobalSandbox()
        try box.homebrewNode()
        try box.pnpm10Project()
        try box.yarnGlobalFolder()
        let pnpm = try #require(box.pnpmPackages.scan(managers: []).first)
        let yarn = try #require(box.yarnPackages.scan(managers: []).first)
        func process(_ arguments: [String]) -> NpmActivity.Process {
            NpmActivity.Process(pid: 7, arguments: arguments, executable: nil)
        }
        #expect(GlobalPackageActivity.busy(pnpm, processes: [process(["node", "/c/pnpm.js", "add", "-g", "x"])]) != nil)
        #expect(GlobalPackageActivity.busy(pnpm, processes: [process(["/h/bin/pnpm", "up", "--global"])]) != nil)
        #expect(GlobalPackageActivity.busy(pnpm, processes: [process(["pnpm", "add", "x"])]) == nil)
        #expect(GlobalPackageActivity.busy(pnpm, processes: [process(["node", "/c/pnpm.cjs", "list", "-g"])]) == nil)
        #expect(GlobalPackageActivity.busy(yarn, processes: [process(["node", "/y/yarn.js", "global", "add", "x"])]) != nil)
        #expect(GlobalPackageActivity.busy(yarn, processes: [process(["yarn", "add", "x"])]) == nil)
        #expect(GlobalPackageActivity.busy(yarn, processes: [process(["node", "/c/pnpm.js", "add", "-g", "x"])]) == nil)
    }
}

extension GlobalSandbox {
    /// Homebrew's node, ad hoc signed as Homebrew's is, trusted as its keg.
    func homebrewNode(_ version: String = "26.8.2") throws {
        let keg = homebrew.appendingPathComponent("Cellar/node/\(version)")
        try write(keg.appendingPathComponent("bin/node"), "#!/bin/sh\nexec /bin/sh \"$@\"\n", executable: true)
        try write(keg.appendingPathComponent("INSTALL_RECEIPT.json"), "{}")
        try link(homebrew.appendingPathComponent("bin/node"), to: "../Cellar/node/\(version)/bin/node")
    }
}
