import CryptoKit
import DuoUpdaterCore
import Foundation

/// Developer-only XPC verification client. It links the production runner and
/// is signed as our app so the daemon exercises its real peer gate. Not embedded
/// in DuoUpdater and not built by the shipping scheme.
@main struct PackageHelperVerification {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else { exit(64) }
        let mode = arguments[0]
        let output = URL(fileURLWithPath: arguments.last!)
        if mode == "catalog" {
            await catalog(to: output)
            return
        }
        let runner = HelperPackageRunner(connect: {
            guard let requirement = OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.helper") else { return nil }
            let connection = NSXPCConnection(machServiceName: "com.duoupdater.helper", options: .privileged)
            connection.setCodeSigningRequirement(requirement)
            return connection
        })
        var receipt: [String: Any] = ["mode": mode, "pid": ProcessInfo.processInfo.processIdentifier,
                                      "uid": getuid(), "date": ISO8601DateFormatter().string(from: Date())]
        if mode == "capability" {
            receipt["available"] = await runner.isAvailable()
            emit(receipt, to: output)
            return
        }
        guard arguments.count == 4 else { exit(64) }
        let package = URL(fileURLWithPath: arguments[1])
        let app = URL(fileURLWithPath: arguments[2])
        do {
            let info = try metadata(app)
            let selected = AppScanner().scan(bundlesAt: [app]).first
            guard let actualIdentifier = selected?.bundleID ?? info["CFBundleIdentifier"] as? String else { exit(65) }
            receipt["bundleIdentifier"] = actualIdentifier
            receipt["physicalBundleIdentifier"] = info["CFBundleIdentifier"]
            receipt["beforeProductVersion"] = selected?.shortVersion
            receipt["before"] = info["CFBundleShortVersionString"]
            receipt["beforeBuild"] = info["CFBundleVersion"]
            var fingerprint = Data(SHA256.hash(data: try Data(contentsOf: package)))
            if mode == "wrong-digest" { fingerprint[0] ^= 1 }
            let identifier = mode == "wrong-identity" ? actualIdentifier + ".wrong" : actualIdentifier
            try await AutomaticInstall.$active.withValue(mode == "automatic" || mode == "automatic-running") {
                try await runner.install(package: package, installedApp: app,
                    bundleIdentifier: identifier, fingerprint: fingerprint) { line in
                        try? FileHandle.standardOutput.write(contentsOf: Data("PROGRESS \(line)\n".utf8))
                    }
            }
            receipt["result"] = "installed"
            receipt["after"] = try metadata(app)["CFBundleShortVersionString"]
            receipt["afterBuild"] = try metadata(app)["CFBundleVersion"]
            emit(receipt, to: output)
        } catch {
            receipt["result"] = "refused"
            receipt["error"] = error.localizedDescription
            receipt["after"] = try? metadata(app)["CFBundleShortVersionString"]
            receipt["afterBuild"] = try? metadata(app)["CFBundleVersion"]
            emit(receipt, to: output)
            exit(1)
        }
    }

    private static func catalog(to output: URL) async {
        var rows: [[String: Any]] = []
        func row(_ bundleID: String, channel: String, remote: RemoteVersion?) -> [String: Any] {
            var value: [String: Any] = ["bundleID": bundleID, "channel": channel]
            value["pinnedTeam"] = PackageInstallTrust.teamIdentifier(for: bundleID)
            value["version"] = remote?.version
            value["shortVersion"] = remote?.shortVersion
            value["url"] = remote?.downloadURL?.absoluteString
            value["headers"] = remote?.downloadHeaders
            value["edSignature"] = remote?.edSignature
            value["source"] = remote?.sourceName
            return value
        }
        let vendor = VendorProbeSource()
        for recipe in VendorProbeRegistry.recipes where recipe.install?.kind == .pkg {
            let outcome = await vendor.probeDiagnostic(recipe)
            var value = row(recipe.bundleID, channel: recipe.channel.rawValue, remote: outcome.remote)
            value["warnings"] = outcome.warnings.map(\.display)
            value["resolved"] = outcome.succeeded
            rows.append(value)
        }
        let github = GitHubReleasesSource()
        for (id, name) in [("org.xquartz.X11", "XQuartz"),
                           ("io.nekohasekai.screensharing", "OpenScreenSharing")] {
            let app = InstalledApp(name: name, bundleID: id, shortVersion: "0", buildVersion: "0",
                path: URL(fileURLWithPath: "/Applications/\(name).app"), isMASApp: false, sparkleFeedURL: nil)
            let remote = try? await github.latestVersion(for: app)
            rows.append(row(id, channel: "stable", remote: remote))
        }
        let adguard = InstalledApp(name: "Adguard", bundleID: "com.adguard.mac.adguard",
            shortVersion: "0", buildVersion: "0",
            path: URL(fileURLWithPath: "/Applications/Adguard.app"), isMASApp: false,
            sparkleFeedURL: URL(string: "https://static.adtidy.org/mac/release/adguard-release-appcast.xml"))
        let remote = try? await SparkleAppcastSource().latestVersion(for: adguard)
        rows.append(row("com.adguard.mac.adguard", channel: "stable", remote: remote))
        emit(["date": ISO8601DateFormatter().string(from: Date()), "packages": rows], to: output)
    }

    private static func metadata(_ app: URL) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(
            from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
            options: [], format: nil) as? [String: Any] ?? [:]
    }

    private static func emit(_ receipt: [String: Any], to output: URL) {
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
            try FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8))
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("Receipt failed: \(error)\n".utf8))
            exit(74)
        }
    }
}
