import Foundation
import DuoUpdaterCore

// feed-discover — work out which update manifest a bundle reads, and say whether
// that address is safe to adopt. Covers both families: a Sparkle appcast the app
// keeps in code rather than in `SUFeedURL`, and an electron-builder
// `latest-mac.yml` named by the `app-update.yml` inside the bundle.
//
// It runs the PRODUCTION discovery gates (`FeedDiscovery`) and the production
// appcast parser against a real bundle, so an `adopt` here is evidence that the
// address resolves — not a claim.
//
// This proposes; it never writes. The registry stays a closed, reviewed set (see
// `FeedDiscovery`'s doc comment for why that is a feature and not an oversight),
// so the output of a run is something a person reads and commits.
//
// Usage:
//   swift run --package-path application-test feed-discover <path-to-.app/.dmg/.zip>
//   swift run --package-path application-test feed-discover --scan [--gaps]
//
// `--scan` walks the installed apps; `--gaps` narrows that to the ones that ship
// an updater we recognise but name no address we already resolve — the coverage
// holes.
//
// Exit codes: 0 = ran; 2 = bad input.

@discardableResult
func sh(_ launchPath: String, _ args: [String]) -> (code: Int32, out: Data) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, Data()) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, data)
}

func die(_ msg: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(code)
}

let argv = CommandLine.arguments
guard argv.count >= 2 else {
    die("usage: feed-discover <path-to-.app/.dmg/.zip>\n"
        + "       feed-discover --scan [--gaps]", code: 2)
}

// MARK: - rendering

func describe(_ f: FeedDiscovery.Finding) -> String {
    let p = f.probe
    let name = f.bundlePath.deletingPathExtension().lastPathComponent
    let id = p.bundleID ?? "?"
    var lines = ["\(name)  [\(id)]  \(p.installed.text(withBuild: true))"]
    switch f.verdict {
    case .noKnownUpdater:
        lines.append("   —  no Sparkle and no electron-builder update config")
    case .declared(let url):
        lines.append("   declared  \(url.absoluteString)")
        lines.append("      (Info.plist names it; SparkleAppcastSource already resolves this app)")
    case .superseded(let declared, let live):
        lines.append("   SUPERSEDED \(declared.absoluteString)")
        lines.append("      the address the Info.plist names — SparkleFeedCatalog replaces it with")
        lines.append("      \(live.absoluteString), which is what production actually reads")
    case .adopt(let url):
        lines.append("   ADOPT     \(url.absoluteString)")
        switch p.family {
        case .electron:
            lines.append("      electron-builder manifest — propose a VendorProbeRecipe over it")
        default:
            lines.append("      SparkleFeedCatalog entry: \"\(id.lowercased())\": \(url.absoluteString)")
        }
    case .review(let blocker, let url):
        lines.append("   review    \(blocker.rawValue)")
        // Print the RAW literal, not the URL: a template's `%s` survives here and
        // is escaped to `%25s` there, and the whole point of this line is to show
        // a person the shape of what the binary actually holds.
        if url != nil, p.candidates.count == 1, let c = p.candidates.first {
            lines.append("      candidate: \(c.raw)  (\(c.origin.rawValue))")
        } else {
            for c in p.candidates { lines.append("      candidate: \(c.raw)  (\(c.origin.rawValue))") }
        }
    }
    return lines.joined(separator: "\n")
}

// MARK: - --electron

// Run the PRODUCTION `ElectronManifestSource` over the real `AppScanner` output,
// so what prints is what a check would resolve — not a re-implementation of it.
// This is how a hand-written electron recipe gets retired: confirm the generic
// source answers with the same version and a sane artifact for that app, then
// delete the recipe.
if argv[1] == "--electron" {
    let source = ElectronManifestSource()
    for app in AppScanner().scan() {
        guard let cfg = app.electronUpdate else { continue }
        let where_ = cfg.manifestURL?.absoluteString
            ?? "(provider \(cfg.provider) states no address)"
        print("\(app.name)  [\(app.bundleID ?? "?")]  installed \(app.versionSide.text(withBuild: true))")
        print("   manifest  \(where_)")
        do {
            if let remote = try await source.latestVersion(for: app) {
                let kind = remote.vendorInstallerKind.map { "\($0)" } ?? "?"
                print("   resolved  \(remote.shortVersion ?? "?")  [\(kind)]"
                    + (remote.expectedSHA512 == nil ? "  sha512✗" : "  sha512✓"))
                print("   artifact  \(remote.downloadURL?.absoluteString ?? "(none)")")
            } else {
                print("   resolved  (nothing)")
            }
        } catch {
            print("   ERROR     \(error.localizedDescription)")
        }
    }
    exit(0)
}

// MARK: - --scan

if argv[1] == "--scan" {
    let gapsOnly = argv.contains("--gaps")
    let fm = FileManager.default
    let roots = [
        URL(fileURLWithPath: "/Applications"),
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]
    var apps: [URL] = []
    for root in roots {
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        apps += entries.filter { $0.pathExtension == "app" }
    }
    apps.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

    var counts: [String: Int] = [:]
    for app in apps {
        let finding = await FeedDiscovery.examine(bundleAt: app)
        switch finding.verdict {
        case .noKnownUpdater:
            counts["noKnownUpdater", default: 0] += 1
            if gapsOnly { continue }
        case .declared:
            counts["declared", default: 0] += 1
            if gapsOnly { continue }
        case .superseded:
            // Not skipped under `--gaps`. The flag means "show me what is not
            // covered", and an app whose declared address is dead is the one
            // kind of declared feed that is a coverage question rather than an
            // answer to one.
            counts["superseded", default: 0] += 1
        case .adopt:
            counts["adopt", default: 0] += 1
        case .review(let b, _):
            counts["review:\(b.rawValue)", default: 0] += 1
        }
        print(describe(finding))
    }
    print("\n— \(apps.count) bundles —")
    for (k, v) in counts.sorted(by: { $0.key < $1.key }) { print("  \(v)  \(k)") }
    exit(0)
}

// MARK: - single bundle (mounting/expanding as needed)

let input = URL(fileURLWithPath: argv[1])
var mountPoint: String?
var tempDir: URL?

@MainActor func cleanup() {
    if let mp = mountPoint { sh("/usr/bin/hdiutil", ["detach", mp, "-quiet"]) }
    if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
}

func firstApp(under root: String) -> String? {
    FileManager.default.enumerator(atPath: root)?
        .compactMap { $0 as? String }
        .first { $0.hasSuffix(".app") && !$0.dropLast(4).contains(".app/") }
}

let appPath: URL
switch input.pathExtension.lowercased() {
case "dmg":
    let (code, out) = sh("/usr/bin/hdiutil",
        ["attach", "-nobrowse", "-readonly", "-plist", input.path])
    guard code == 0,
          let plist = try? PropertyListSerialization.propertyList(
            from: out, options: [], format: nil) as? [String: Any],
          let entities = plist["system-entities"] as? [[String: Any]],
          let mp = entities.compactMap({ $0["mount-point"] as? String }).first
    else { die("failed to mount DMG: \(input.path)", code: 2) }
    mountPoint = mp
    guard let found = firstApp(under: mp) else {
        cleanup(); die("no .app inside DMG at \(mp)", code: 2)
    }
    appPath = URL(fileURLWithPath: mp).appendingPathComponent(found)
case "zip":
    // Sparkle's most common enclosure format, so this is how a not-installed app
    // gets verified: fetch the enclosure, point this at it, keep the disk clean.
    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("feed-discover-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    tempDir = temp
    let (code, _) = sh("/usr/bin/ditto", ["-x", "-k", input.path, temp.path])
    guard code == 0, let found = firstApp(under: temp.path) else {
        cleanup(); die("failed to expand zip: \(input.path)", code: 2)
    }
    appPath = temp.appendingPathComponent(found)
default:
    appPath = input
}

guard FileManager.default.fileExists(atPath: appPath.appendingPathComponent("Contents/Info.plist").path)
else { cleanup(); die("not an app bundle: \(appPath.path)", code: 2) }

let finding = await FeedDiscovery.examine(bundleAt: appPath)
print(describe(finding))
cleanup()
exit(0)
