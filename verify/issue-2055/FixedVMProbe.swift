import Foundation
import CryptoKit
@testable import DuoUpdaterCore

@main struct FixedVMProbe {
    actor Fallback: UpdateSource {
        nonisolated let name = "Vendor"
        var calls = 0
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            calls += 1
            return RemoteVersion(shortVersion: "999.0", version: nil, downloadURL: nil, sourceName: name)
        }
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
        print("PASS: \(message)")
    }
    static func app(_ name: String, at path: URL? = nil) throws -> InstalledApp {
        let labels = ["fullcomma":"FullComma", "fullcolon":"FullColon", "old":"Old", "pin":"Pin", "var":"Var", "intel":"Intel", "thirdintel":"ThirdIntel"]
        let url = path ?? URL(fileURLWithPath: "/Applications/Duo2055VM\(labels[name]!).app")
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        return InstalledApp(name: url.deletingPathExtension().lastPathComponent,
            bundleID: plist["CFBundleIdentifier"] as? String,
            shortVersion: plist["CFBundleShortVersionString"] as? String,
            buildVersion: plist["CFBundleVersion"] as? String,
            path: url, isMASApp: false, sparkleFeedURL: nil)
    }
    static func source(_ work: URL) throws -> HomebrewCaskSource {
        let data = try Data(contentsOf: work.appendingPathComponent("catalog.json"))
        let index = try HomebrewCaskCatalog.index(fromCatalogJSON: data)
        return HomebrewCaskSource(catalog: HomebrewCaskCatalog(testIndex: index), inventory: BrewLocalInventory())
    }
    static func remote(_ name: String, _ work: URL) async throws -> RemoteVersion {
        let installed = try app(name)
        guard let remote = try await source(work).latestVersion(for: installed) else {
            throw Failure(message: "Fixture \(name) must resolve before its verdict is asserted")
        }
        return remote
    }
    static func update(_ name: String, _ work: URL, expected: Bool, latest: String? = nil) async throws {
        let installed = try app(name)
        let release = try await remote(name, work)
        let status = UpdateChecker.evaluate(installed: installed, remote: release)
        if expected {
            guard case .updateAvailable(let value) = status else {
                throw Failure(message: "\(name): expected update, got \(status)")
            }
            if let latest { try require(value == latest, "\(name) displays complete version \(latest)") }
        } else {
            try require(status == .upToDate, "\(name): expected current/held, got \(status)")
        }
        print("PASS: \(name) status=\(status), marketing=\(release.shortVersion ?? "nil"), build=\(release.version ?? "nil")")
    }
    static func fingerprint(_ paths: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        let fm = FileManager.default
        for path in paths {
            let root = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: path) else { result[path] = "absent"; continue }
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else {
                throw Failure(message: "Cannot snapshot \(path)")
            }
            while let file = walk.nextObject() as? URL {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    result[file.path] = "link:" + (try fm.destinationOfSymbolicLink(atPath: file.path))
                } else if values.isRegularFile == true {
                    result[file.path] = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
                }
            }
        }
        return result
    }
    static func refuses(_ label: String, action: () async throws -> Void) async throws {
        do {
            try await action()
            throw Failure(message: "\(label): foreign prefix was accepted")
        } catch let error as Failure { throw error }
        catch {
            try require(String(reflecting: type(of: error)).contains("UnsupportedPrefix"),
                "\(label): explicit UnsupportedPrefix, got \(type(of: error)): \(error)")
        }
    }
    static func environment(_ work: URL) async {
        let output = work.appendingPathComponent("env-result.json")
        var record: [String: Any] = [:]
        do {
            try require(ProcessInfo.processInfo.environment["HOMEBREW_NO_AUTO_UPDATE"] == nil,
                "LaunchServices initial environment does not inherit shell HOMEBREW_NO_AUTO_UPDATE")
            let shell = await LoginShellEnvironment.resolveHomebrewVariables()
            try require(shell?["HOMEBREW_NO_AUTO_UPDATE"] == "1", "login shell resolves NO_AUTO_UPDATE")
            try require(shell?["HOMEBREW_AUTO_UPDATE_SECS"] == "2055", "login shell resolves update interval")
            try require(shell?["HOMEBREW_FIXTURE_TOKEN"] == "synthetic-2055-token", "synthetic Homebrew token is retained by resolver")
            try require(shell?["DUO2055_UNRELATED_SECRET"] == nil && shell?["PATH"] == nil, "resolver excludes unrelated secret and PATH")
            guard let config = await HomebrewConfig.read(environment: shell ?? [:]) else {
                throw Failure(message: "Actual Brew config did not resolve")
            }
            try require(config.autoUpdateDisabled && config.autoUpdateSeconds == 2055,
                "actual Brew config receives shell settings")
            let logger = work.appendingPathComponent("brew-log").path
            let executor = BrewFormulaService.executor(brewPath: { logger })
            guard let result = try await executor(["config"]), result.status == 0 else {
                throw Failure(message: "ordinary executor did not run logger")
            }
            try await HomebrewInstaller.$brewPathOverride.withValue(logger) {
                try await HomebrewInstaller().fetch(caskToken: "duo2055vm-fullcomma", onOutput: { _ in })
            }
            let log = try String(contentsOf: work.appendingPathComponent("env-commands.txt"), encoding: .utf8)
            let lines = log.split(separator: "\n").map(String.init)
            try require(lines.count == 3, "ordinary read, preliminary dry run and fetch all execute")
            try require(lines.contains { $0.hasPrefix("config|") }, "ordinary read captured")
            try require(lines.contains { $0.hasPrefix("install --cask --force --dry-run -- duo2055vm-fullcomma|") }, "preliminary dry run captured")
            try require(lines.contains { $0.hasPrefix("fetch --cask -- duo2055vm-fullcomma|") }, "fetch captured")
            try require(lines.allSatisfy { $0.hasSuffix("|1|2055|synthetic-2055-token|unset|clean") }, "all commands forward synthetic Homebrew token but exclude unrelated secret and shell PATH")
            record = ["passed": true, "configAutoUpdateDisabled": config.autoUpdateDisabled,
                      "configAutoUpdateSeconds": config.autoUpdateSeconds ?? -1, "commands": lines]
        } catch { record = ["passed": false, "error": String(describing: error)] }
        do { try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic) }
        catch { print("Could not write environment verdict: \(error)") }
    }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { throw Failure(message: "Usage: FixedVMProbe <work> <mode>") }
        let work = URL(fileURLWithPath: args[1]), mode = args[2]
        if mode == "env" { await environment(work); return }
        switch mode {
        case "initial":
            let release = try await remote("var", work)
            try require(release.shortVersion == "1.0", "platform variation selects actual ARM version")
            try require(release.downloadURL?.lastPathComponent == "var-101.tar.gz", "platform variation selects matching URL")
            try await update("var", work, expected: false)
            let old = try await remote("old", work)
            try require(old.sourceIdentifier == "duo2055vm-new", "old receipt resolves canonical current token")
            try await update("old", work, expected: true)
            try await update("fullcomma", work, expected: true, latest: "1.0,102")
            try await update("fullcolon", work, expected: true, latest: "1.0:102")
            let pinned = try await remote("pin", work)
            try require(pinned.homebrewPinned, "app source reads real cask pin state")
            try await update("pin", work, expected: false)
            let formula = try Data(contentsOf: work.appendingPathComponent("formula-outdated.json"))
            let cask = try Data(contentsOf: work.appendingPathComponent("cask-outdated.json"))
            // Verify input identity first: an empty fixture must never pass pin filtering.
            let fjson = try JSONSerialization.jsonObject(with: formula) as! [String: Any]
            let formulae = fjson["formulae"] as! [[String: Any]]
            try require(formulae.contains { ($0["name"] as? String)?.hasSuffix("duo2055vm-formula") == true && ($0["pinned"] as? Bool) == true }, "actual pinned formula exists in Brew JSON")
            try require(!BrewFormulaService.parse(formula).contains { $0.name.hasSuffix("duo2055vm-formula") }, "formula parser excludes pinned formula")
            try require(!BrewFormulaService.parseCasks(cask).contains { $0.name == "duo2055vm-pin" }, "package cask parser excludes pinned cask")
        case "unpinned":
            let release = try await remote("pin", work)
            try require(!release.homebrewPinned, "live unpin is visible")
            try await update("pin", work, expected: true)
        case "upgraded":
            for name in ["fullcomma", "fullcolon"] {
                let updatedApp = try app(name)
                try require(updatedApp.buildVersion == "102", "\(name) upgrade changed actual bundle build")
                try await update(name, work, expected: false)
            }
        case "unowned":
            let copy = try app("old", at: work.appendingPathComponent("unowned/Duo2055VMOld.app"))
            let release = try await source(work).latestVersion(for: copy)
            try require(release == nil, "same filename/bundle ID unowned copy is not adopted")
        case "other-tap":
            let release = try await source(work).latestVersion(for: app("old"))
            try require(release == nil, "official catalog does not adopt a different originating tap")
        case "receipt-only":
            let link = "/opt/homebrew/Caskroom/duo2055vm-var/1.0/Duo2055VMVar.app"
            try require(!FileManager.default.fileExists(atPath: link), "official staged link is absent before receipt-only assertion")
            let release = try await remote("var", work)
            try require(release.sourceIdentifier == "duo2055vm-var", "official saved receipt target retains exact-copy owner")
            try await update("var", work, expected: false)
        case "selfupdated":
            let installed = try app("pin")
            let release = try await remote("pin", work)
            try require(installed.shortVersion == "2.0" && installed.buildVersion == "102", "self-updated app is genuinely at offered payload")
            try require(release.homebrewInstalledCaskVersion == "1.0", "Brew record deliberately remains stale after external app update")
            try require(!release.homebrewPinned, "self-updated control is not being hidden by pin")
            try await update("pin", work, expected: false)
        case "renamed-pinned", "renamed-unpinned":
            let installed = try app("old")
            let release = try await remote("old", work)
            try require(installed.shortVersion == "2.0", "actual old-token Brew upgrade installed version 2.0")
            try require(release.sourceIdentifier == "duo2055vm-new", "legacy directory alias does not replace canonical token")
            try require(release.homebrewInstalledCaskVersion == "2.0" && release.homebrewCaskVersion == "3.0", "full canonical installed and current cask identities are preserved")
            let alias = URL(fileURLWithPath: "/opt/homebrew/Caskroom/duo2055vm-old")
            let aliasValues = try alias.resourceValues(forKeys: [.isSymbolicLinkKey])
            try require(aliasValues.isSymbolicLink == true, "old-token directory symlink remains for canonical pin attack")
            try require(release.homebrewPinned == (mode == "renamed-pinned"), "canonical pin state remains live despite legacy alias")
            try await update("old", work, expected: mode == "renamed-unpinned")
        case "foreign":
            for name in ["intel", "thirdintel"] {
                let installed = try app(name)
                let token = "duo2055vm-" + name
                var paths = ["/opt/homebrew/Caskroom/"+token, "/usr/local/Caskroom/"+token, installed.path.path]
                if name == "intel" { paths.append("/Applications/Duo2055VMIntelHelper.app") }
                let before = try fingerprint(paths)
                try require(before["/opt/homebrew/Caskroom/"+token] == "absent", "\(name): no ARM installation before refusal")
                if name == "intel" {
                    try await refuses("official source") { _ = try await source(work).latestVersion(for: installed) }
                } else {
                    try await refuses("third-party source") { _ = try await ThirdPartyCaskSource().latestVersion(for: installed) }
                }
                let fallback = Fallback()
                let ownerSource: any UpdateSource
                if name == "intel" { ownerSource = try source(work) }
                else { ownerSource = ThirdPartyCaskSource() }
                let verdict = await UpdateChecker(sources: [ownerSource, fallback]).check(installed)
                guard case .error = verdict.status else { throw Failure(message: "foreign owner checker must stop with error") }
                let fallbackCalls = await fallback.calls
                try require(fallbackCalls == 0 && verdict.remote == nil, "\(name): terminal refusal prevents other-source adoption")
                try await refuses("\(name) fetch") {
                    try await HomebrewInstaller().fetch(caskToken: token, app: installed.path, onOutput: { print($0) })
                }
                try await refuses("\(name) upgrade") {
                    try await HomebrewInstaller().upgrade(caskToken: token, app: installed.path, onOutput: { print($0) })
                }
                let after = try fingerprint(paths)
                try require(after == before, "\(name): neither prefix record nor installed app changes")
            }
        default: throw Failure(message: "Unknown mode \(mode)")
        }
        print("PASS: mode \(mode)")
    }
}
