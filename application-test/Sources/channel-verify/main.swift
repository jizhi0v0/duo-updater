import Foundation
import DuoUpdaterCore

// channel-verify — strict, on-machine verification that a real app bundle is
// classified onto the channel its VendorProbe recipe expects, and that the probe
// actually answers for that (bundleID, channel) pair.
//
// It runs the PRODUCTION code paths (`ReleaseChannel.detect`, `VendorProbeSource`)
// against a real Info.plist, so a green run is evidence — not a claim — that a
// recipe will fire for that install. Accepts either an installed `.app` or a
// `.dmg` (mounted read-only, inspected, then detached — verify without installing).
//
// Usage:
//   swift run --package-path application-test channel-verify <path-to-.app-or-.dmg> [--expect <channel>]
//
// Exit codes: 0 = detection matched --expect (or none given); 1 = mismatch /
// probe miss; 2 = bad input.

// MARK: - shell helper

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

// MARK: - args

let argv = CommandLine.arguments
guard argv.count >= 2 else {
    die("usage: channel-verify <path-to-.app-or-.dmg> [--expect <channel>]\n"
        + "       channel-verify --scan <bundleID> [--expect <channel>]", code: 2)
}

// --scan mode: run the REAL production AppScanner.scan() over the default
// locations (/Applications, ~/Applications) and report what it tags an installed
// app — the full end-to-end path the menu-bar app uses, not just detect() on one
// bundle. Proves the install is classified correctly by the shipping code.
if argv[1] == "--scan" {
    guard argv.count >= 3 else { die("usage: channel-verify --scan <bundleID> [--expect <channel>]", code: 2) }
    let wantBundle = argv[2]
    var want: String? = nil
    if let i = argv.firstIndex(of: "--expect"), i + 1 < argv.count { want = argv[i + 1].lowercased() }

    let installed = AppScanner().scan()
    guard let app = installed.first(where: { $0.bundleID == wantBundle }) else {
        die("AppScanner.scan() did not find an installed app with bundle id \(wantBundle)", code: 1)
    }
    print("""

  AppScanner.scan() — production path
    app             \(app.name)
    bundle id       \(app.bundleID ?? "<none>")
    short version   \(app.shortVersion ?? "<none>")
    ─────────────────────────────────────────────
    detected channel → \(app.releaseChannel.rawValue)
""")
    var code: Int32 = 0
    if let want, want != app.releaseChannel.rawValue {
        print("    ✗ MISMATCH: expected \(want)"); code = 1
    } else if want != nil {
        print("    ✓ matches --expect \(want!)")
    }
    let remote = try? await VendorProbeSource().latestVersion(for: app)
    if let remote {
        let latest = remote.displayVersion ?? "<nil>"
        let inst = remote.shortVersion != nil ? app.shortVersion : app.buildVersion
        let newer = (remote.shortVersion ?? remote.version).map {
            VersionComparator.isNewer($0, than: inst ?? "") } ?? false
        print("    VendorProbe → \(latest) · \(newer ? "UPDATE \(inst ?? "?") → \(latest)" : "up to date (not newer)")")
    } else {
        print("    VendorProbe → no version (channel \(app.releaseChannel.rawValue) recipe miss)")
    }
    exit(code)
}

let inputPath = argv[1]
var expected: String? = nil
if let i = argv.firstIndex(of: "--expect"), i + 1 < argv.count {
    expected = argv[i + 1].lowercased()
}

// MARK: - resolve the .app (mounting a DMG read-only if needed)

let input = URL(fileURLWithPath: inputPath)
var mountPoint: String? = nil
let appPath: URL

if input.pathExtension.lowercased() == "dmg" {
    let (code, out) = sh("/usr/bin/hdiutil",
        ["attach", "-nobrowse", "-readonly", "-plist", input.path])
    guard code == 0,
          let plist = try? PropertyListSerialization.propertyList(
            from: out, options: [], format: nil) as? [String: Any],
          let entities = plist["system-entities"] as? [[String: Any]],
          let mp = entities.compactMap({ $0["mount-point"] as? String }).first
    else { die("failed to mount DMG: \(input.path)", code: 2) }
    mountPoint = mp
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: mp)) ?? []
    guard let appName = entries.first(where: { $0.hasSuffix(".app") }) else {
        sh("/usr/bin/hdiutil", ["detach", mp, "-quiet"])
        die("no .app found inside DMG at \(mp)", code: 2)
    }
    appPath = URL(fileURLWithPath: mp).appendingPathComponent(appName)
    print("mounted DMG read-only → \(appPath.path)")
} else {
    appPath = input
}

@MainActor func cleanup() { if let mp = mountPoint { sh("/usr/bin/hdiutil", ["detach", mp, "-quiet"]) } }

// MARK: - read identity straight from Info.plist (no launch, no codesign)

let infoURL = appPath.appendingPathComponent("Contents/Info.plist")
guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
    cleanup()
    die("cannot read \(infoURL.path)", code: 2)
}
let bundleID = info["CFBundleIdentifier"] as? String
let shortVersion = info["CFBundleShortVersionString"] as? String
let buildVersion = info["CFBundleVersion"] as? String
let ksChannel = info["KSChannelID"] as? String
// The display name AppScanner sees is the bundle's on-disk file name.
let displayName = appPath.deletingPathExtension().lastPathComponent
// Mozilla's authoritative per-channel marker, read the same way AppScanner does.
let remotingName = (bundleID?.hasPrefix("org.mozilla") == true)
    ? AppScanner.mozillaRemotingName(in: appPath) : nil

// MARK: - run the PRODUCTION channel detector

let detected = ReleaseChannel.detect(
    name: displayName,
    bundleID: bundleID,
    keystoneChannel: ksChannel,
    version: shortVersion,
    mozillaRemotingName: remotingName
)

print("""

  app             \(displayName)
  bundle id       \(bundleID ?? "<none>")
  short version   \(shortVersion ?? "<none>")
  build version   \(buildVersion ?? "<none>")
  KSChannelID     \(ksChannel ?? "<none>")
  RemotingName    \(remotingName ?? "<none>")
  ─────────────────────────────────────────────
  detected channel  → \(detected.rawValue)
""")

var exitCode: Int32 = 0
if let expected, expected != detected.rawValue {
    print("  ✗ MISMATCH: expected channel '\(expected)'")
    exitCode = 1
} else if expected != nil {
    print("  ✓ detection matches --expect \(expected!)")
}

// MARK: - run the PRODUCTION VendorProbe for this (bundleID, channel)

let app = InstalledApp(
    name: displayName,
    bundleID: bundleID,
    shortVersion: shortVersion,
    buildVersion: buildVersion,
    path: appPath,
    isMASApp: false,
    sparkleFeedURL: nil,
    releaseChannel: detected
)

let probe = VendorProbeSource()
let remote = try? await probe.latestVersion(for: app)

print("  ─────────────────────────────────────────────")
if let remote {
    let latest = remote.displayVersion ?? "<nil>"
    print("""
  VendorProbe       ✓ recipe answered for channel '\(detected.rawValue)'
    latest          \(latest)
    shortVersion    \(remote.shortVersion ?? "<nil>")
    version(build)  \(remote.version ?? "<nil>")
    download        \(remote.downloadURL?.absoluteString ?? "<nil>")
    changelog       \(remote.changelogURL?.absoluteString ?? "<nil>")
""")
    // Verdict via the REAL engine gate (`VersionComparator.isNewer`), comparing on
    // the same field the engine uses (build vs marketing). This matters for Mozilla:
    // a feed's `140.11.1esr` sorts BELOW the install's suffix-less `140.11.1`, so the
    // engine treats it as "up to date" even though the strings differ.
    let remoteVer = remote.shortVersion ?? remote.version
    let installed = remote.shortVersion != nil ? shortVersion : buildVersion
    if let installed, let remoteVer {
        if VersionComparator.isNewer(remoteVer, than: installed) {
            print("    verdict       UPDATE \(installed) → \(remoteVer)")
        } else {
            print("    verdict       up to date (installed \(installed); latest \(remoteVer) not newer)")
        }
    } else {
        print("    verdict       (insufficient version info)")
    }
} else {
    print("""
  VendorProbe       ✗ no version
    → either no recipe is keyed to bundle '\(bundleID ?? "?")' on channel
      '\(detected.rawValue)', or the probe missed (network / pattern). This is the
      failure the channel gate produces when a recipe's bundleID/channel is wrong.
""")
    if expected != nil { exitCode = 1 }
}

cleanup()
exit(exitCode)
