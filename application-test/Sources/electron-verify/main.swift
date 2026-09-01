import Foundation
import DuoUpdaterCore

// electron-verify — on-machine verification for `ElectronManifestSource`, the one
// source with no registry to sweep.
//
// `duo verify` enumerates three registries (vendor / github / changelog). This
// source has none: the address it reads lives in each installed bundle's own
// `Contents/Resources/app-update.yml`, so the only place the set of covered apps
// exists is the machine. That is what this harness is for — it walks the real
// `AppScanner.scan()` output, asks `ElectronManifestSource` alone, and reports
// what production would conclude.
//
// It deliberately does NOT run the full source chain. In production this source
// sits last, so any app that also has a hand-written recipe is answered before it
// and its Electron path is never exercised. Scoping the stack to this one source
// is the only way to see what it would say — the install path below is still the
// production one (`UpdatePolicy` + `InstallCoordinator`), so a green `--install`
// run is evidence about the shipping code, not about a re-implementation.
//
// Usage:
//   swift run --package-path application-test electron-verify
//   swift run --package-path application-test electron-verify <bundleID>
//   swift run --package-path application-test electron-verify <bundleID> --install
//
// Exit codes: 0 = every app inspected reported a coherent state; 1 = at least one
// incoherent state (see `Finding`); 2 = bad input.

// MARK: - args

let argv = CommandLine.arguments
var wantBundle: String?
var doInstall = false
var assumeYes = false

for (i, arg) in argv.enumerated() where i > 0 {
    switch arg {
    case "--install": doInstall = true
    case "--yes", "-y": assumeYes = true
    case "-h", "--help":
        print("""
            usage: electron-verify [<bundleID>] [--install] [--yes]

              (no bundleID)   inspect every installed bundle carrying an app-update.yml
              <bundleID>      inspect one
              --install       run the production install path for it (asks first)
              --yes           skip the confirmation (for scripted runs)
            """)
        exit(0)
    default:
        if arg.hasPrefix("-") {
            FileHandle.standardError.write(Data("electron-verify: unknown flag \(arg)\n".utf8))
            exit(2)
        }
        wantBundle = arg
    }
}

if doInstall && wantBundle == nil {
    FileHandle.standardError.write(Data(
        "electron-verify: --install needs a bundle id — it replaces a real app\n".utf8))
    exit(2)
}

// MARK: - helpers

/// Architectures of a bundle's main executable, by the same reader the install
/// gate uses. Printed rather than inferred from the filename, because the whole
/// point of the Notion shape is that the filename does not say.
func architectures(ofAppAt url: URL) -> String {
    guard let bundle = Bundle(url: url), let archs = bundle.executableArchitectures else {
        return "unreadable"
    }
    let names = archs.map { n -> String in
        switch n.intValue {
        case NSBundleExecutableArchitectureARM64:  return "arm64"
        case NSBundleExecutableArchitectureX86_64: return "x86_64"
        default: return "arch \(n.intValue)"
        }
    }
    return names.isEmpty ? "none" : names.sorted().joined(separator: "+")
}

func shortVersion(ofAppAt url: URL) -> String? {
    let plist = url.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
          let info = try? PropertyListSerialization.propertyList(
              from: data, format: nil) as? [String: Any] else { return nil }
    return info["CFBundleShortVersionString"] as? String
}

var findings: [String] = []
@MainActor func note(_ line: String) { findings.append(line) }

// MARK: - inventory

let scanned = AppScanner().scan()
let electron = scanned
    .filter { $0.electronUpdate != nil }
    .filter { wantBundle == nil || $0.bundleID?.lowercased() == wantBundle?.lowercased() }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

guard !electron.isEmpty else {
    if let wantBundle {
        FileHandle.standardError.write(Data(
            "electron-verify: no installed app with bundle id \(wantBundle) carries an app-update.yml\n".utf8))
        exit(2)
    }
    print("no installed app carries an app-update.yml")
    exit(0)
}

print("""

  electron-verify
  \(electron.count) bundle\(electron.count == 1 ? "" : "s") with an app-update.yml
  ─────────────────────────────────────────────
""")

let source = ElectronManifestSource()

for app in electron {
    let config = app.electronUpdate!
    print("\n▸ \(app.name)  [\(app.bundleID ?? "no-bundle-id")]")
    print("    installed   \(app.shortVersion ?? "?")  (\(architectures(ofAppAt: app.path)))")
    print("    provider    \(config.provider)"
        + (config.url.map { "  url=\($0)" } ?? "")
        + "  channel=\(config.channel)")

    guard let manifestURL = config.manifestURL else {
        // Not a fault: `github` states only owner/repo and `s3` only a bucket, and
        // constructing either is the thing `ElectronUpdateConfig.manifestURL`
        // refuses to do (Termius is the standing argument). These apps keep their
        // hand-written recipes.
        print("    manifest    — (provider states no address; recipe territory)")
        continue
    }
    print("    manifest    \(manifestURL.absoluteString)")

    let remote: RemoteVersion?
    do {
        remote = try await source.latestVersion(for: app)
    } catch {
        print("    resolved    ✗ threw — \(error.localizedDescription)")
        note("\(app.name): latestVersion threw")
        continue
    }

    guard let remote else {
        // The source degrades to nil for a manifest that 404s, will not parse, or
        // carries no version. That is its documented best-effort contract, so it is
        // reported rather than failed — but it IS the state that used to be
        // invisible, which is why it prints.
        print("    resolved    — nothing (manifest missing, unparseable, or versionless)")
        continue
    }

    let newer = VersionComparator.isNewer(remote.versionSide, than: app.versionSide)
    print("    resolved    \(remote.displayVersion ?? "?")"
        + "  \(newer ? "→ UPDATE" : "(not newer)")"
        + (remote.publishedAt.map { "  published=\($0)" } ?? "  published=—"))

    if let url = remote.downloadURL {
        print("    artifact    \(url.lastPathComponent)"
            + "  kind=\(remote.vendorInstallerKind.map(String.init(describing:)) ?? "—")"
            + "  sha512=\(remote.expectedSHA512 == nil ? "no" : "yes")"
            + (remote.downloadSize.map { "  \($0) B" } ?? ""))
        if remote.expectedSHA512 == nil {
            note("\(app.name): artifact resolved with no sha512 — the three install "
                + "fields are supposed to move together")
        }
        if remote.vendorInstallerKind == nil {
            note("\(app.name): downloadURL set but vendorInstallerKind nil — unroutable")
        }
    } else {
        print("    artifact    — none (detection only)")
    }

    // What production would DO with this. The point of printing it here is that a
    // source can resolve everything correctly and still be unreachable, which is
    // exactly the state this source shipped in.
    let result = UpdateResult(
        app: app,
        remote: remote,
        status: newer
            ? .updateAvailable(latest: remote.displayVersion ?? "?")
            : .upToDate)
    let environment = InstallEnvironment(
        isHelperEnabled: false,
        runningAppPaths: [],
        stagedSelfUpdates: [:])
    let settings = UpdateSettings(
        appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)
    let canAuto = UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment)
    let needsInstaller = UpdatePolicy.requiresInstaller(result, environment: environment)
    let route = InstallCoordinator.route(for: result, requiresInstaller: needsInstaller)
    print("    policy      canAutoInstall=\(canAuto)"
        + "  requiresInstaller=\(needsInstaller)"
        + "  route=\(route.rawValue)")

    if remote.vendorInstallerKind != nil, !canAuto, !needsInstaller {
        note("\(app.name): a resolved installer artifact that no policy branch "
            + "accepts — the install spec is computed and then dropped")
    }
    if canAuto && route != .vendor {
        note("\(app.name): canAutoInstall but route=\(route.rawValue) — "
            + "VendorInstaller is the only installer that accepts \"Electron\"")
    }

    guard doInstall else { continue }

    // MARK: install

    guard newer else {
        print("\n    --install: nothing to do, the installed build is already current.")
        print("    (put an older build on disk first — every electron-builder CDN")
        print("     keeps its versioned artifacts, so an old one is a plain fetch.)")
        continue
    }
    guard canAuto || needsInstaller else {
        print("\n    --install: refused by policy, see the line above.")
        note("\(app.name): --install asked for, policy refuses")
        continue
    }

    if !assumeYes {
        print("\n    Replace \(app.path.path)")
        print("      \(app.shortVersion ?? "?") → \(remote.displayVersion ?? "?")   [y/N] ", terminator: "")
        guard isatty(STDIN_FILENO) == 1,
              let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(),
              answer == "y" || answer == "yes" else {
            print("    skipped")
            continue
        }
    }

    let backup = await InstallCoordinator.backUp(app, route: route)
    print("    backup      \(backup)")

    let coordinator = InstallCoordinator()
    do {
        let outcome = try await coordinator.perform(result, route: route) { stage in
            if case .downloading(let fraction) = stage, fraction > 0 {
                // One line, overwritten — a 120 MB electron zip is the common size
                // and a per-chunk log buries everything above it.
                print("\r    downloading \(Int(fraction * 100))%   ", terminator: "")
                fflush(stdout)
            }
        }
        print("\r    installed   applied=\(outcome.applied)"
            + "  bytes=\(outcome.bytesDownloaded)"
            + (outcome.finalHost.map { "  host=\($0)" } ?? ""))
    } catch {
        print("\r    installed   ✗ \(error.localizedDescription)")
        note("\(app.name): install failed — \(error.localizedDescription)")
        continue
    }

    // Ask the DISK, not the outcome. `applied` is what the installer believes; the
    // bundle on disk is what the user gets, and the architecture is the half a
    // filename cannot be trusted about.
    let onDisk = shortVersion(ofAppAt: app.path) ?? "?"
    let onDiskArch = architectures(ofAppAt: app.path)
    print("    on disk     \(onDisk)  (\(onDiskArch))")
    if onDisk != (remote.shortVersion ?? remote.displayVersion) {
        note("\(app.name): installed \(remote.displayVersion ?? "?") but the bundle "
            + "on disk reports \(onDisk)")
    }
    if !onDiskArch.contains("arm64") {
        note("\(app.name): the bundle now on disk has no arm64 slice (\(onDiskArch)) "
            + "— an architecture downgrade landed")
    }
}

print("\n  ─────────────────────────────────────────────")
if findings.isEmpty {
    print("  no findings\n")
    exit(0)
}
print("  \(findings.count) finding\(findings.count == 1 ? "" : "s"):")
for f in findings { print("    ✗ \(f)") }
print("")
exit(1)
