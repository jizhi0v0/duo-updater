import Foundation
import Testing
@testable import DuoUpdaterCore

/// `OneClickGate`: a recipe family names which installed copies may take the
/// one-click; everything else keeps detection only. Exercised through the
/// gates registered today (MuseScore, Memoh, Hyper, Readest, massCode, Museeks and Ferdium by installed version,
/// Rambox by installed and offered major, GitKraken by an asar entry, Hoppscotch by both a version and an
/// executable marker, FlowVision by an executable marker) and
/// through both places that enforce them.
struct OneClickGateTests {
    /// A bundle at a fresh path whose `app.asar` packs `files` (path → contents),
    /// in Electron's layout: `[4][header pickle size]`, then
    /// `[payload][json length][json]` padded to 4 bytes, then the file bytes.
    private func bundle(_ files: [String: String]?) throws -> URL {
        let app = TestScratch.directory("one-click-gate")
            .appendingPathComponent("App.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        guard let files else { return app }
        var tree: [String: Any] = [:]
        var body = Data()
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let bytes = Data(text.utf8)
            func insert(_ node: inout [String: Any], _ rest: ArraySlice<String>) {
                var children = node["files"] as? [String: Any] ?? [:]
                if rest.count == 1 {
                    children[rest.first!] = ["size": bytes.count, "offset": String(body.count)]
                } else {
                    var child = children[rest.first!] as? [String: Any] ?? [:]
                    insert(&child, rest.dropFirst())
                    children[rest.first!] = child
                }
                node["files"] = children
            }
            insert(&tree, path.split(separator: "/").map(String.init)[...])
            body.append(bytes)
        }
        let json = try JSONSerialization.data(withJSONObject: tree)
        let padded = (json.count + 3) / 4 * 4
        func le(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        var data = le(4) + le(8 + padded) + le(4 + padded) + le(json.count) + json
        data.append(Data(count: padded - json.count))
        data.append(body)
        try data.write(to: resources.appendingPathComponent("app.asar"))
        return app
    }

    private func app(_ bundleID: String, _ version: String?, at path: URL? = nil) -> InstalledApp {
        InstalledApp(
            name: "Fixture", bundleID: bundleID, shortVersion: version, buildVersion: nil,
            path: path ?? URL(fileURLWithPath: "/Applications/ZZFixture-\(UUID().uuidString).app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    private func gitKraken(_ edition: String) throws -> InstalledApp {
        app("com.axosoft.gitkraken", "12.5.0", at: try bundle([
            "src/main/static/clientType.js": "// auto-generated\nmodule.exports = '\(edition)';\n",
            "package.json": #"{"name":"gitkraken","version":"12.5.0"}"#,
        ]))
    }

    private func offer(
        _ app: InstalledApp, source: String = "Vendor", package: String = "App.zip"
    ) -> UpdateResult {
        UpdateResult(app: app, remote: remote(source: source, package: package),
                     status: .updateAvailable(latest: "99.0"))
    }

    /// An offer of `package` from `source`: the download URL's last component,
    /// and for Homebrew the cask token.
    private func remote(source: String = "GitHub", package: String) -> RemoteVersion {
        RemoteVersion(
            shortVersion: "99.0", version: nil,
            downloadURL: URL(string: "https://example.invalid/download/\(package)"),
            sourceName: source,
            sourceIdentifier: source == "Homebrew" ? package : nil,
            vendorInstallerKind: .zip)
    }

    private static let cloudDMG = "Hoppscotch_mac_aarch64.dmg"
    private static let selfHostDMG = "Hoppscotch_SelfHost_mac_aarch64.dmg"
    private static let cloudFeed = "hoppscotch-cloud-desktop.json"
    private static let selfHostFeed = "hoppscotch-selfhost-desktop.json"

    @Test func theRegisteredGatesAreTheMeasuredCases() {
        #expect(Set(OneClickGateRegistry.gates.map(\.bundleID))
            == ["org.musescore.MuseScore", "com.axosoft.gitkraken", "ai.memoh.desktop", "io.hoppscotch.desktop",
                "co.zeit.hyper", "com.bilingify.readest", "io.masscode.app", "netdcy.FlowVision", "org.ferdium.ferdium-app", "io.museeks.app", "com.rambox"])
    }

    /// Versions of the real bundles: stable 7.2.3, 7.2.2, 6.0.0, the nightlies
    /// 7.2.4-nightly.3 and 7.2.3-nightly.3, and the beta 6.4.1-beta.2, all
    /// `org.ferdium.ferdium-app`, Team 55E9FPJ93P.
    @Test func ferdiumOneClickIsForStableCopiesOnly() {
        for version in ["7.2.3", "7.2.2", "6.0.0", "8.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("org.ferdium.ferdium-app", version), offering: nil) == nil, "\(version)")
        }
        for version in ["7.2.4-nightly.3", "7.2.3-nightly.3", "6.4.1-beta.2"] {
            #expect(OneClickGateRegistry.withholding(app("org.ferdium.ferdium-app", version), offering: nil) != nil, "\(version)")
        }
    }

    /// Versions of the real bundles: stable 3.4.1, 3.4.0, 3.0.2 and the canary
    /// 4.0.0-canary.5, all `co.zeit.hyper`, Team JW6Y669B67. Older canary
    /// tags (`3.4.0-canary.1`, `3.0.1-canary.4`) stamp the same shape.
    @Test func hyperOneClickIsForStableCopiesOnly() {
        for version in ["3.4.1", "3.4.0", "3.0.2", "4.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("co.zeit.hyper", version), offering: nil) == nil, "\(version)")
        }
        for version in ["4.0.0-canary.5", "3.4.0-canary.1", "3.0.1-canary.4"] {
            #expect(OneClickGateRegistry.withholding(app("co.zeit.hyper", version), offering: nil) != nil, "\(version)")
        }
    }

    /// The versions of the real bundles: GitHub's stable dmgs (0.12.16, 0.12.12,
    /// 0.10.1, 0.7.9) and the nightly `.app.tar.gz` from
    /// download.readest.com/nightly/ (0.12.16-2026102206), all
    /// `com.bilingify.readest`, Team J5W48D69VR.
    @Test func readestOneClickIsForStableBuildsOnly() {
        for version in ["0.12.16", "0.12.12", "0.10.1", "0.7.9", "1.0"] {
            #expect(OneClickGateRegistry.withholding(app("com.bilingify.readest", version), offering: nil) == nil, "\(version)")
        }
        for version in ["0.12.16-2026102206", "0.11.4-2026061406"] {
            #expect(OneClickGateRegistry.withholding(app("com.bilingify.readest", version), offering: nil) != nil, "\(version)")
        }
    }

    /// Rambox 2 and 3 share `com.rambox` and Team 7F292FPD69 (real dmgs 2.7.2
    /// and 3.1.2, `Rambox-<version>-mac.dmg`); signing in to 3 moves the
    /// account one way. A 3.x-or-later dmg goes only to a 3.x-or-later copy, a
    /// 2.x dmg only to a 2.x copy, and any other package to neither.
    @Test func ramboxOneClickNeverCrossesFromTwoToThree() {
        let later = ["Rambox-3.1.2-mac.dmg", "Rambox-3.0.0-mac.dmg", "Rambox-4.0.0-mac.dmg", "Rambox-10.0.0-mac.dmg"]
        for version in ["2.7.2", "2.7.1", "2.0.1"] {
            for package in later {
                #expect(OneClickGateRegistry.withholding(
                    app("com.rambox", version), offering: remote(package: package)) != nil, "\(version) ← \(package)")
            }
            #expect(OneClickGateRegistry.withholding(
                app("com.rambox", version), offering: remote(package: "Rambox-2.7.2-mac.dmg")) == nil, "\(version)")
        }
        for version in ["3.1.2", "3.0.0", "4.0.0"] {
            for package in later.dropLast(2) {
                #expect(OneClickGateRegistry.withholding(
                    app("com.rambox", version), offering: remote(package: package)) == nil, "\(version) ← \(package)")
            }
            #expect(OneClickGateRegistry.withholding(
                app("com.rambox", version), offering: remote(package: "Rambox-2.7.2-mac.dmg")) != nil, "\(version)")
        }
        #expect(OneClickGateRegistry.withholding(
            app("com.rambox", "10.0.0"), offering: remote(package: "Rambox-10.0.0-mac.dmg")) == nil)
        for package in ["Rambox-3.1.2-mac.dmg", "Rambox-2.7.2-mac.dmg"] {
            #expect(OneClickGateRegistry.withholding(app("com.rambox", nil), offering: remote(package: package)) != nil)
        }
        #expect(OneClickGateRegistry.withholding(
            app("com.rambox", "2.7.1"), offering: remote(package: "RamboxPro-1.5.1.dmg")) != nil)
    }

    /// A bundle at a fresh path whose Info.plist is `plist` and whose
    /// `Contents/MacOS/<name>` holds `executable` (none when nil).
    private func tauriBundle(
        plist: [String: Any]?, executable: Data?, named name: String = "hoppscotch-desktop"
    ) throws -> URL {
        let app = TestScratch.directory("one-click-gate")
            .appendingPathComponent("Hoppscotch.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        if let plist {
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
        }
        if let executable { try executable.write(to: macOS.appendingPathComponent(name)) }
        return app
    }

    /// Filler, the updater URL the edition was built with, filler — the layout
    /// of the real executables, which differ only in that literal.
    private func hoppscotchExecutable(feed: String) -> Data {
        Data(repeating: 0xAB, count: 4096) + Data("https://releases.example.invalid/\(feed)".utf8)
            + Data(repeating: 0xCD, count: 4096)
    }

    private func hoppscotch(_ version: String?, feed: String) throws -> InstalledApp {
        app("io.hoppscotch.desktop", version, at: try tauriBundle(
            plist: ["CFBundleExecutable": "hoppscotch-desktop"],
            executable: hoppscotchExecutable(feed: feed)))
    }

    /// Each edition's package goes to that edition's copies only; a copy with
    /// neither literal, a first-generation copy and any offer no gate names
    /// are withheld.
    @Test func hoppscotchOneClickIsPerEditionForSecondGenerationCopies() throws {
        let cloud = try hoppscotch("26.9.0", feed: Self.cloudFeed)
        // Self-Host: same id, version and plist; only the executable differs.
        let selfHost = try hoppscotch("26.9.0", feed: Self.selfHostFeed)
        // The x64 builds: fragments only, neither literal whole.
        let neither = try hoppscotch("26.9.0", feed: "ch-cloud ch-selfh")
        let cloudOffer = remote(package: Self.cloudDMG)
        let selfHostOffer = remote(package: Self.selfHostDMG)
        func marker(_ app: InstalledApp, _ offer: RemoteVersion?) -> String? {
            guard case .executableContains(let marker)? =
                    OneClickGateRegistry.withholding(app, offering: offer)?.requirement else { return nil }
            return marker
        }
        #expect(OneClickGateRegistry.withholding(cloud, offering: cloudOffer) == nil)
        #expect(OneClickGateRegistry.withholding(
            cloud, offering: remote(source: "Homebrew", package: "hoppscotch")) == nil)
        #expect(OneClickGateRegistry.withholding(selfHost, offering: selfHostOffer) == nil)
        #expect(OneClickGateRegistry.withholding(
            selfHost, offering: remote(source: "Homebrew", package: "hoppscotch-selfhost")) == nil)
        // Across editions: withheld by the offered edition's gate.
        #expect(marker(cloud, selfHostOffer) == Self.selfHostFeed)
        #expect(marker(selfHost, cloudOffer) == Self.cloudFeed)
        #expect(marker(selfHost, remote(source: "Homebrew", package: "hoppscotch")) == Self.cloudFeed)
        #expect(marker(cloud, remote(source: "Homebrew", package: "hoppscotch-selfhost")) == Self.selfHostFeed)
        // Neither literal: withheld whichever edition is offered.
        #expect(marker(neither, cloudOffer) == Self.cloudFeed)
        #expect(marker(neither, selfHostOffer) == Self.selfHostFeed)
        // An offer no gate names, for either copy: the x64 dmgs (no copy
        // that passes is x64), another asset, another cask, another source,
        // no package, no offer.
        let unnamed: [RemoteVersion?] = [
            remote(package: "Hoppscotch_mac_x64.dmg"),
            remote(package: "Hoppscotch_SelfHost_mac_x64.dmg"),
            remote(source: "Homebrew", package: "hoppscotch-selfhost@beta"),
            remote(package: "Hoppscotch_mac_aarch64.tar.gz"),
            remote(source: "Vendor", package: Self.cloudDMG),
            RemoteVersion(shortVersion: "99.0", version: nil, downloadURL: nil,
                          sourceName: "GitHub", vendorInstallerKind: .dmg),
            nil,
        ]
        for copy in [cloud, selfHost] {
            for (index, offer) in unnamed.enumerated() {
                #expect(OneClickGateRegistry.withholding(copy, offering: offer)?.reason
                        == OneClickGate.unnamedOfferReason, "offer \(index)")
            }
        }
        // First generation: the bundle version keeps the tag's `-N`, even with
        // the marker present.
        for version in ["25.1.1-2", "25.1.1-0", "23.8.3-1"] {
            for (feed, offer) in [
                (Self.cloudFeed, cloudOffer), (Self.selfHostFeed, selfHostOffer),
                (Self.cloudFeed, remote(source: "Homebrew", package: "hoppscotch")),
                (Self.selfHostFeed, remote(source: "Homebrew", package: "hoppscotch-selfhost")),
            ] {
                #expect(OneClickGateRegistry.withholding(
                    try hoppscotch(version, feed: feed), offering: offer) != nil, "\(version)")
            }
        }
        #expect(OneClickGateRegistry.withholding(
            try hoppscotch(nil, feed: Self.cloudFeed), offering: cloudOffer) != nil)
    }

    /// A copy whose executable holds both editions' literals is neither
    /// edition: no offer is admitted, whichever edition's package and source.
    ///
    /// Mutation (run): either `executableLacks` gate removed from the recipe
    /// → that edition's offers admit this copy, red.
    @Test func aCopyWithBothEditionsMarkersIsWithheld() throws {
        let both = try hoppscotch("26.9.0", feed: "\(Self.cloudFeed) \(Self.selfHostFeed)")
        for offer in [
            remote(package: Self.cloudDMG), remote(package: Self.selfHostDMG),
            remote(source: "Homebrew", package: "hoppscotch"),
            remote(source: "Homebrew", package: "hoppscotch-selfhost"),
        ] {
            let gate = OneClickGateRegistry.withholding(both, offering: offer)
            #expect(gate != nil, "\(String(describing: OneClickGateRegistry.offerIdentity(offer)))")
            guard case .executableLacks? = gate?.requirement else {
                Issue.record("withheld by \(String(describing: gate?.requirement)), not the sibling marker")
                continue
            }
        }
    }

    /// `executableLacks` admits only a whole read without the marker: what
    /// keeps the executable from being read is a refusal, not an absence.
    @Test func anAbsentMarkerThatCannotBeReadIsNotAdmitted() throws {
        let marker = Self.selfHostFeed
        func admits(_ bundle: URL, _ gateMarker: String = marker) -> Bool {
            OneClickGate(bundleID: "zz.fixture", requirement: .executableLacks(marker: gateMarker), reason: "r")
                .admits(app("zz.fixture", "1.0", at: bundle))
        }
        let plist: [String: Any] = ["CFBundleExecutable": "hoppscotch-desktop"]
        #expect(admits(try tauriBundle(plist: plist, executable: hoppscotchExecutable(feed: Self.cloudFeed))))
        #expect(!admits(try tauriBundle(plist: plist, executable: hoppscotchExecutable(feed: marker))))
        #expect(!admits(try tauriBundle(plist: nil, executable: hoppscotchExecutable(feed: Self.cloudFeed))))
        #expect(!admits(try tauriBundle(plist: plist, executable: nil)))
        #expect(!admits(try tauriBundle(plist: plist, executable: hoppscotchExecutable(feed: Self.cloudFeed)), ""))
        let locked = try tauriBundle(plist: plist, executable: hoppscotchExecutable(feed: Self.cloudFeed))
        let lockedFile = locked.appendingPathComponent("Contents/MacOS/hoppscotch-desktop")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: lockedFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedFile.path) }
        #expect(!admits(locked))
        // Over the size limit: never read whole, so never proven absent.
        let big = try tauriBundle(plist: plist, executable: hoppscotchExecutable(feed: Self.cloudFeed))
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: executablePath(of: big)))
        try handle.truncate(atOffset: UInt64(ExecutableMarker.byteLimit) + 1)
        try handle.close()
        #expect(!admits(big))
    }

    /// An x64 package offered to an arm64 copy (a release that ships only
    /// x64 dmgs, say) is no offer of the gates': refused by the offer and by
    /// the coordinator before anything is downloaded, not after a full
    /// download by the installer's package check.
    ///
    /// Mutation (run): the offering widened back to `(?:aarch64|x64)` → the
    /// Cloud copy is admitted for the x64 dmg, red.
    @Test func anX64OfferIsWithheldBeforeInstall() async throws {
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)
        let environment = InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        for (feed, package) in [
            (Self.cloudFeed, "Hoppscotch_mac_x64.dmg"), (Self.selfHostFeed, "Hoppscotch_SelfHost_mac_x64.dmg"),
        ] {
            let result = offer(try hoppscotch("26.8.2", feed: feed), source: "GitHub", package: package)
            #expect(OneClickGateRegistry.withholding(result.app, offering: result.remote)?.reason
                    == OneClickGate.unnamedOfferReason, "\(package)")
            #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
            await #expect(throws: OneClickGateRegistry.Withheld.self) {
                _ = try await coordinator.perform(
                    result, route: .vendor, installedPopulation: [result.app],
                    digestOnlyAllowed: false, progress: { _ in })
            }
        }
    }

    /// The `hoppscotch-selfhost` cask goes to a proven Self-Host copy only.
    ///
    /// Mutation (run): `|Homebrew:hoppscotch-selfhost` removed from the
    /// Self-Host offering → the Self-Host copy is withheld as an unnamed
    /// offer, red.
    @Test func theSelfHostCaskIsForSelfHostCopiesOnly() throws {
        let cask = remote(source: "Homebrew", package: "hoppscotch-selfhost")
        #expect(OneClickGateRegistry.withholding(
            try hoppscotch("26.9.0", feed: Self.selfHostFeed), offering: cask) == nil)
        for copy in [
            try hoppscotch("26.9.0", feed: Self.cloudFeed),
            try hoppscotch("26.9.0", feed: "\(Self.cloudFeed) \(Self.selfHostFeed)"),
            try hoppscotch("25.1.1-2", feed: Self.selfHostFeed),
            try hoppscotch("26.9.0", feed: "ch-cloud ch-selfh"),
        ] {
            #expect(OneClickGateRegistry.withholding(copy, offering: cask) != nil)
        }
        #expect(OneClickGateRegistry.withholding(
            try hoppscotch("26.9.0", feed: Self.selfHostFeed),
            offering: remote(source: "Homebrew", package: "hoppscotch")) != nil)
    }

    /// A FlowVision copy whose executable holds `symbols` between filler, as
    /// the real builds do: the Xcode 26 builds import `_swift_coroFrameAlloc`,
    /// the Xcode 16 ones don't.
    private func flowVision(_ symbols: String) throws -> InstalledApp {
        app("netdcy.FlowVision", "1.7.5", at: try tauriBundle(
            plist: ["CFBundleExecutable": "FlowVision"],
            executable: Data(repeating: 0xAB, count: 4096) + Data(symbols.utf8)
                + Data(repeating: 0xCD, count: 4096),
            named: "FlowVision"))
    }

    /// FlowVision's Xcode 16 and Xcode 26 builds share id, Team, version and
    /// every plist key a gate reads: each build's zip goes to that build's
    /// copies only, the cask (the Xcode 16 zip) to the Xcode 16 copies only,
    /// and the copy's build picks the rule.
    ///
    /// Mutation (run): the Xcode 16 gate removed from the recipe → the plain
    /// zip and the cask admit the Xcode 26 copy, red.
    @Test func flowVisionOneClickIsPerBuild() async throws {
        let xcode16 = try flowVision("_$sSS5IndexVMn _swift_FORCE_LOAD_$_swiftDataDetection")
        let xcode26 = try flowVision("_NSToolbarSpaceItemIdentifier _swift_coroFrameAlloc")
        let plain = remote(package: "FlowVision.1.7.6.zip")
        let glass = remote(package: "FlowVision.1.7.6.Xcode26.zip")
        let cask = remote(source: "Homebrew", package: "flowvision")
        #expect(OneClickGateRegistry.withholding(xcode16, offering: plain) == nil)
        #expect(OneClickGateRegistry.withholding(xcode16, offering: cask) == nil)
        #expect(OneClickGateRegistry.withholding(xcode26, offering: glass) == nil)
        #expect(OneClickGateRegistry.withholding(xcode16, offering: glass) != nil)
        #expect(OneClickGateRegistry.withholding(xcode26, offering: plain) != nil)
        #expect(OneClickGateRegistry.withholding(xcode26, offering: cask) != nil)
        for offer in [remote(package: "FlowVision.1.7.6.dmg"),
                      remote(source: "Homebrew", package: "flowvision@beta"), nil] {
            for copy in [xcode16, xcode26] {
                #expect(OneClickGateRegistry.withholding(copy, offering: offer)?.reason
                        == OneClickGate.unnamedOfferReason)
            }
        }
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == "netdcy.FlowVision" }
        #expect(await GitHubReleasesSource.rule(forEditionOf: xcode16, among: rules)?.variant == nil)
        #expect(await GitHubReleasesSource.rule(forEditionOf: xcode26, among: rules)?.variant == "xcode26")
    }

    /// Offers a scoped gate may name although their route never consults
    /// `packageMarkers`: brew fetches and swaps the package itself, so only
    /// the gate on the copy stands before the swap.
    static let offeringsWithoutAPackageCheck: Set<String> = [
        "Homebrew:hoppscotch", "Homebrew:hoppscotch-selfhost", "Homebrew:flowvision",
    ]

    /// The package check (`VendorInstaller` step 3c) runs on the `.vendor`
    /// route only. Every offer a scoped gate names must take that route, or be
    /// one of the listed exceptions, and every exception must still be named.
    ///
    /// A probe, not a proof over the pattern's language: the offers tried are
    /// every source name the router tells apart, with every package name the
    /// pattern spells out (its runs of name characters, unescaped) plus a
    /// made-up one, at every installer kind the source can carry (a GitHub
    /// asset: the kind of the id's rule whose asset pattern takes it; other
    /// vendor sources: every kind). Routed by `InstallCoordinator.route`, a
    /// `.pkg` as `requiresInstaller`.
    @Test func everyOfferAScopedGateNamesHasAPackageCheck() {
        let vendorSources = ["GitHub", "Vendor", ElectronManifestSource.sourceName, MyGoUpdateSource.sourceName]
        let sources = vendorSources + ["Homebrew", "App Store", XcodeReleasesSource.sourceName, "Sparkle", "Unknown"]
        var named: Set<String> = []
        for gate in OneClickGateRegistry.gates {
            guard let offering = gate.offering else { continue }
            let unescaped = offering.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
            var packages = Set(unescaped.matches(of: /[A-Za-z0-9_.@-]+/).map { String($0.output) })
            packages.insert("Package.dmg")
            let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID.lowercased() == gate.bundleID.lowercased() }
            for source in sources {
                for package in packages {
                    var kinds: [VendorInstallerKind?]
                    if source == "GitHub" {
                        kinds = rules.filter {
                            $0.installAssetPattern.map { package.range(of: $0, options: .regularExpression) != nil } ?? false
                        }.map(\.installerKind)
                    } else if vendorSources.contains(source) {
                        kinds = VendorInstallerKind.allCases
                    } else {
                        kinds = [nil]
                    }
                    if kinds.isEmpty { kinds = [nil] }
                    for kind in kinds {
                        let remote = RemoteVersion(
                            shortVersion: "99.0", version: nil,
                            downloadURL: URL(string: "https://example.invalid/download/\(package)"),
                            sourceName: source,
                            sourceIdentifier: source == "Homebrew" ? package : nil,
                            vendorInstallerKind: kind)
                        guard let identity = OneClickGateRegistry.offerIdentity(remote),
                              gate.applies(toOffer: identity) else { continue }
                        let result = UpdateResult(
                            app: app(gate.bundleID, "99.0"), remote: remote,
                            status: .updateAvailable(latest: "99.0"))
                        let route = InstallCoordinator.route(for: result, requiresInstaller: kind == .pkg)
                        guard route != .vendor else { continue }
                        named.insert(identity)
                        #expect(Self.offeringsWithoutAPackageCheck.contains(identity),
                                "\(gate.bundleID) names \(identity), routed \(route) with no package check")
                    }
                }
            }
        }
        #expect(named == Self.offeringsWithoutAPackageCheck, "an exception no gate names any more")
    }

    /// The markers the downloaded package must carry, and must have been read
    /// whole without: the offered edition's, and the other's; none for an
    /// offer no edition gate names, or for an app without them.
    @Test func thePackageMustCarryTheOfferedEditionsMarker() {
        let id = "io.hoppscotch.desktop"
        let cloud = [
            OneClickGateRegistry.PackageMarker(marker: Self.cloudFeed, present: true),
            OneClickGateRegistry.PackageMarker(marker: Self.selfHostFeed, present: false),
        ]
        let selfHost = [
            OneClickGateRegistry.PackageMarker(marker: Self.selfHostFeed, present: true),
            OneClickGateRegistry.PackageMarker(marker: Self.cloudFeed, present: false),
        ]
        #expect(OneClickGateRegistry.packageMarkers(for: id, offering: remote(package: Self.cloudDMG)) == cloud)
        #expect(OneClickGateRegistry.packageMarkers(for: id, offering: remote(package: Self.selfHostDMG)) == selfHost)
        #expect(OneClickGateRegistry.packageMarkers(
            for: id, offering: remote(source: "Homebrew", package: "hoppscotch")) == cloud)
        #expect(OneClickGateRegistry.packageMarkers(for: id, offering: nil).isEmpty)
        #expect(OneClickGateRegistry.packageMarkers(
            for: "com.axosoft.gitkraken", offering: remote(package: "App.zip")).isEmpty)
    }

    /// Fails closed: whatever keeps the executable from being read is a refusal.
    @Test func anExecutableMarkerThatCannotBeReadIsNotAdmitted() throws {
        let marker = "hoppscotch-cloud-desktop.json"
        let cloud = hoppscotchExecutable(feed: marker)
        func admits(_ bundle: URL) -> Bool {
            OneClickGate(bundleID: "zz.fixture", requirement: .executableContains(marker: marker), reason: "r")
                .admits(app("zz.fixture", "1.0", at: bundle))
        }
        #expect(admits(try tauriBundle(plist: ["CFBundleExecutable": "hoppscotch-desktop"], executable: cloud)))
        // No Info.plist; no CFBundleExecutable; an empty or path-like one.
        #expect(!admits(try tauriBundle(plist: nil, executable: cloud)))
        #expect(!admits(try tauriBundle(plist: ["CFBundleName": "Hoppscotch"], executable: cloud)))
        #expect(!admits(try tauriBundle(plist: ["CFBundleExecutable": ""], executable: cloud)))
        #expect(!admits(try tauriBundle(
            plist: ["CFBundleExecutable": "../MacOS/hoppscotch-desktop"], executable: cloud)))
        // The plist names an executable that is not there.
        #expect(!admits(try tauriBundle(plist: ["CFBundleExecutable": "hoppscotch-desktop"], executable: nil)))
        // Not readable.
        let locked = try tauriBundle(plist: ["CFBundleExecutable": "hoppscotch-desktop"], executable: cloud)
        let lockedFile = locked.appendingPathComponent("Contents/MacOS/hoppscotch-desktop")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: lockedFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedFile.path) }
        #expect(!admits(locked))
        // A directory where the executable should be.
        let directory = try tauriBundle(plist: ["CFBundleExecutable": "hoppscotch-desktop"], executable: nil)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Contents/MacOS/hoppscotch-desktop"), withIntermediateDirectories: true)
        #expect(!admits(directory))
        // An empty marker matches nothing.
        let empty = OneClickGate(bundleID: "zz.fixture", requirement: .executableContains(marker: ""), reason: "r")
        #expect(!empty.admits(app("zz.fixture", "1.0", at: try tauriBundle(
            plist: ["CFBundleExecutable": "hoppscotch-desktop"], executable: cloud))))
    }

    /// The executable is read 4 MiB at a time; a marker split across two reads
    /// is still found, and one past the end of the file is not invented.
    @Test func anExecutableMarkerAcrossAChunkBoundaryIsFound() throws {
        let marker = "hoppscotch-cloud-desktop.json"
        // The size `ExecutableMarker` reads in, so this spans a boundary whatever it is.
        let chunk = ExecutableBytes.defaultChunkSize
        let straddling = Data(repeating: 0, count: chunk - 10) + Data(marker.utf8) + Data(repeating: 0, count: 100)
        let truncated = Data(repeating: 0, count: chunk - 10) + Data(marker.utf8.prefix(10))
        let plist: [String: Any] = ["CFBundleExecutable": "hoppscotch-desktop"]
        #expect(ExecutableMarker.found(marker, inMainExecutableOf: try tauriBundle(plist: plist, executable: straddling)))
        #expect(!ExecutableMarker.found(marker, inMainExecutableOf: try tauriBundle(plist: plist, executable: truncated)))
    }

    // MARK: - `.executableContains` cache and file checks

    private static let marker = "hoppscotch-cloud-desktop.json"
    /// The marker's length in other bytes: the same file size without a match.
    private static let noMarker = String(repeating: "x", count: marker.utf8.count)

    private func executablePath(of bundle: URL) -> String {
        bundle.appendingPathComponent("Contents/MacOS/hoppscotch-desktop").path
    }

    private func modified(_ path: String) -> timespec {
        var status = stat()
        precondition(stat(path, &status) == 0)
        return status.st_mtimespec
    }

    private func setModified(_ path: String, _ time: timespec) {
        var times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), time]
        precondition(utimensat(AT_FDCWD, path, &times, 0) == 0)
    }

    /// Overwrites the file's bytes in place: same inode.
    private func overwrite(_ path: String, with data: Data) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private func primedCloudBundle() throws -> URL {
        let bundle = try tauriBundle(
            plist: ["CFBundleExecutable": "hoppscotch-desktop"],
            executable: hoppscotchExecutable(feed: Self.marker))
        #expect(ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle))
        return bundle
    }

    /// A repeated ask answers from the cache: the marker is gone from the file,
    /// but its device, inode, size and mtime are not, so the verdict stays —
    /// until a fresh ask reads it again, and that read replaces what is kept.
    @Test func anExecutableMarkerVerdictIsCachedAndFreshReReads() throws {
        let bundle = try primedCloudBundle()
        let path = executablePath(of: bundle)
        let before = ExecutableMarker.FileIdentity(atPath: path)
        let time = modified(path)
        try overwrite(path, with: hoppscotchExecutable(feed: Self.noMarker))
        setModified(path, time)
        #expect(ExecutableMarker.FileIdentity(atPath: path) == before)
        #expect(ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle))
        #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle, fresh: true))
        #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle))
    }

    /// A Cloud copy whose verdict is cached as admitted, then turned into
    /// Self-Host in place with the executable's device, inode, size and mtime
    /// kept: the cache still says Cloud, the copy on disk is not.
    private func cloudCachedButNowSelfHost() throws -> InstalledApp {
        // Padded to the Self-Host feed's length, so the swap keeps the size.
        let cloud = "hoppscotch-cloud-desktop.json\0\0\0"
        let selfHost = "hoppscotch-selfhost-desktop.json"
        precondition(cloud.utf8.count == selfHost.utf8.count)
        let bundle = try tauriBundle(
            plist: ["CFBundleExecutable": "hoppscotch-desktop"], executable: hoppscotchExecutable(feed: cloud))
        let copy = app("io.hoppscotch.desktop", "26.8.2", at: bundle)
        #expect(OneClickGateRegistry.withholding(copy, offering: remote(package: Self.cloudDMG)) == nil)
        let path = executablePath(of: bundle)
        let before = ExecutableMarker.FileIdentity(atPath: path)
        let time = modified(path)
        try overwrite(path, with: hoppscotchExecutable(feed: selfHost))
        setModified(path, time)
        #expect(ExecutableMarker.FileIdentity(atPath: path) == before)
        #expect(OneClickGateRegistry.withholding(copy, offering: remote(package: Self.cloudDMG)) == nil,
                "the offer answers from the cache")
        return copy
    }

    /// The install-time ask (`fresh`) reads the swapped copy, not the cache.
    @Test func theFreshAskSeesACopyTheCacheDoesNot() throws {
        let copy = try cloudCachedButNowSelfHost()
        #expect(OneClickGateRegistry.withholding(
            copy, offering: remote(package: Self.cloudDMG), fresh: true) != nil)
    }

    /// The coordinator's gate is that fresh ask. The offer's download host
    /// does not resolve, so a gate that let the copy through fails on
    /// something else, offline.
    @Test func theCoordinatorReadsTheCopyAsItIsNow() async throws {
        let copy = try cloudCachedButNowSelfHost()
        let result = UpdateResult(
            app: copy, remote: remote(package: Self.cloudDMG),
            status: .updateAvailable(latest: "99.0"))
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        await #expect(throws: OneClickGateRegistry.Withheld.self) {
            _ = try await coordinator.perform(
                result, route: .vendor, installedPopulation: [copy],
                digestOnlyAllowed: false, progress: { _ in })
        }
    }

    @Test func aChangedExecutableOrPlistIsReadAgain() throws {
        // mtime only.
        do {
            let bundle = try primedCloudBundle()
            let path = executablePath(of: bundle)
            let time = modified(path)
            try overwrite(path, with: hoppscotchExecutable(feed: Self.noMarker))
            setModified(path, timespec(tv_sec: time.tv_sec + 10, tv_nsec: time.tv_nsec))
            #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle), "mtime")
        }
        // size only.
        do {
            let bundle = try primedCloudBundle()
            let path = executablePath(of: bundle)
            let time = modified(path)
            try overwrite(path, with: hoppscotchExecutable(feed: Self.noMarker + "x"))
            setModified(path, time)
            #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle), "size")
        }
        // inode only: another file renamed over it, same size and mtime.
        do {
            let bundle = try primedCloudBundle()
            let path = executablePath(of: bundle)
            let time = modified(path)
            let replacement = path + ".new"
            try hoppscotchExecutable(feed: Self.noMarker).write(to: URL(fileURLWithPath: replacement))
            precondition(rename(replacement, path) == 0)
            setModified(path, time)
            #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle), "inode")
        }
        // Info.plist rewritten; the executable's identity unchanged.
        do {
            let bundle = try primedCloudBundle()
            let path = executablePath(of: bundle)
            let time = modified(path)
            try overwrite(path, with: hoppscotchExecutable(feed: Self.noMarker))
            setModified(path, time)
            #expect(ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle))
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleExecutable": "hoppscotch-desktop", "CFBundleName": "Hoppscotch"],
                format: .xml, options: 0)
                .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: bundle), "plist")
        }
    }

    /// Only a regular file of bounded size is read; anything else is refused
    /// without being read. Each case is the witness of one guard, and neither
    /// has a timeout: a guard that goes missing shows as a wrong answer here
    /// (a FIFO that is read matches, an oversized file that is read matches).
    @Test func aNonRegularOrOversizedExecutableIsNotAdmitted() throws {
        let plist: [String: Any] = ["CFBundleExecutable": "hoppscotch-desktop"]
        // A FIFO holding the marker with its writer gone, so a read sees the
        // bytes and then end of file: reading it would match, and only the
        // regular-file check refuses it. A reader of ours keeps the buffer.
        let fifo = try tauriBundle(plist: plist, executable: nil)
        #expect(mkfifo(executablePath(of: fifo), 0o644) == 0)
        let keeper = open(executablePath(of: fifo), O_RDONLY | O_NONBLOCK)
        #expect(keeper >= 0)
        defer { close(keeper) }
        let writer = open(executablePath(of: fifo), O_WRONLY | O_NONBLOCK)
        #expect(writer >= 0)
        let bytes = Data(Self.marker.utf8) + Data(repeating: 0, count: 8)
        let written = bytes.withUnsafeBytes { write(writer, $0.baseAddress, $0.count) }
        #expect(written == bytes.count)
        close(writer)
        #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: fifo), "FIFO")
        // Over the size limit (sparse, so nothing is written). The marker is
        // near the start of the file: read, it would match, so only the size
        // check refuses it.
        let big = try tauriBundle(plist: plist, executable: hoppscotchExecutable(feed: Self.marker))
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: executablePath(of: big)))
        try handle.truncate(atOffset: UInt64(ExecutableMarker.byteLimit) + 1)
        try handle.close()
        #expect(!ExecutableMarker.found(Self.marker, inMainExecutableOf: big), "over the limit")
    }

    @Test func museScoreOneClickIsFor4xCopiesOnly() {
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", "3.6.2.548020600"), offering: nil) != nil)
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", nil), offering: nil) != nil)
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", "4.7.4"), offering: nil) == nil)
        #expect(OneClickGateRegistry.withholding(app("org.musescore.MuseScore", "4.0"), offering: nil) == nil)
    }

    /// The versions of the real bundles: the vendor's CDN builds, and the OSS
    /// repo's GitHub builds (Memoh 0.16.0, Memoh Local 0.13.0, Memoh-Desktop
    /// 0.9.0, the 0.7.0 one) — all `ai.memoh.desktop`, Team P9R669C27U.
    @Test func memohOneClickIsForTheVendorsDatedBuildsOnly() {
        for version in ["2026.10.19-1", "2026.9.16-1", "2027.1.2-3"] {
            #expect(OneClickGateRegistry.withholding(app("ai.memoh.desktop", version), offering: nil) == nil, "\(version)")
        }
        for version in ["0.16.0", "0.13.0", "0.9.0", "0.7.0", "1.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("ai.memoh.desktop", version), offering: nil) != nil, "\(version)")
        }
        #expect(OneClickGateRegistry.withholding(app("ai.memoh.desktop", nil), offering: nil) != nil)
    }

    /// The versions of real bundles (5.12.0, 6.0.0, 6.2.1, 6.3.1, 2.0.0-beta.6,
    /// all `io.masscode.app`). v6 reads only a Markdown Vault, which v5
    /// introduced; a 4.x or older library is unreadable by it.
    @Test func massCodeOneClickIsFor5xAnd6xCopiesOnly() {
        for version in ["6.3.1", "6.2.1", "6.0.0", "5.12.0", "5.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("io.masscode.app", version), offering: nil) == nil, "\(version)")
        }
        for version in ["4.7.1", "3.12.1", "2.0.0-beta.6", "7.0.0", "60.0"] {
            #expect(OneClickGateRegistry.withholding(app("io.masscode.app", version), offering: nil) != nil, "\(version)")
        }
        #expect(OneClickGateRegistry.withholding(app("io.masscode.app", nil), offering: nil) != nil)
    }

    /// Versions of the real bundles: the Tauri dmgs 0.23.4, 0.23.3, 0.22.0
    /// and the Electron dmg 0.13.1, all `io.museeks.app`, Team YK6MWU3892.
    /// The Tauri app (0.20.0 on) does not read the Electron app's library or
    /// playlists (the vendor's 0.20.0 notes).
    @Test func museeksOneClickIsForTauriCopiesOnly() {
        for version in ["0.23.4", "0.23.3", "0.22.0", "0.21.1", "0.20.0", "0.100.0", "1.0", "1.0.0"] {
            #expect(OneClickGateRegistry.withholding(app("io.museeks.app", version), offering: nil) == nil, "\(version)")
        }
        for version in ["0.13.1", "0.11.5", "0.10.1", "0.9.4", "0.1.0", "0.2", "0.23.4-beta.1"] {
            #expect(OneClickGateRegistry.withholding(app("io.museeks.app", version), offering: nil) != nil, "\(version)")
        }
        #expect(OneClickGateRegistry.withholding(app("io.museeks.app", nil), offering: nil) != nil)
    }

    @Test func gitKrakenOneClickIsForAProvenNormalEditionOnly() throws {
        #expect(OneClickGateRegistry.withholding(try gitKraken("NORMAL"), offering: nil) == nil)
        #expect(OneClickGateRegistry.withholding(try gitKraken("STANDALONE"), offering: nil) != nil)
        // No asar, no entry, or an entry naming no edition: withheld.
        let id = "com.axosoft.gitkraken"
        #expect(OneClickGateRegistry.withholding(app(id, "12.5.0", at: try bundle(nil)), offering: nil) != nil)
        #expect(OneClickGateRegistry.withholding(
            app(id, "12.5.0", at: try bundle(["package.json": "{}"])), offering: nil) != nil)
        #expect(OneClickGateRegistry.withholding(app(id, "12.5.0", at: try bundle(
            ["src/main/static/clientType.js": "module.exports = 1;"])), offering: nil) != nil)
    }

    @Test func anAppWithNoGateIsUntouched() throws {
        let other = app("com.example.other", "1.0", at: try bundle(
            ["src/main/static/clientType.js": "module.exports = 'STANDALONE';"]))
        #expect(OneClickGateRegistry.withholding(other, offering: nil) == nil)
    }

    /// The offer: detection stays, the one-click goes, whatever the source.
    @Test func aWithheldCopyIsDetectionOnly() throws {
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning)
        let environment = InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        func can(_ result: UpdateResult) -> Bool {
            UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment)
        }
        #expect(can(offer(try gitKraken("NORMAL"))))
        #expect(!can(offer(try gitKraken("STANDALONE"))))
        #expect(can(offer(app("org.musescore.MuseScore", "4.7.4"), source: "GitHub")))
        #expect(!can(offer(app("org.musescore.MuseScore", "3.6.2.548020600"), source: "GitHub")))
        let cloud = try hoppscotch("26.8.2", feed: Self.cloudFeed)
        let selfHost = try hoppscotch("26.8.2", feed: Self.selfHostFeed)
        #expect(can(offer(cloud, source: "GitHub", package: Self.cloudDMG)))
        #expect(can(offer(selfHost, source: "GitHub", package: Self.selfHostDMG)))
        #expect(!can(offer(cloud, source: "GitHub", package: Self.selfHostDMG)))
        #expect(!can(offer(selfHost, source: "GitHub", package: Self.cloudDMG)))
    }

    /// The gate: refused before anything is touched, on every route.
    @Test func theCoordinatorRefusesAWithheldCopy() async throws {
        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        for (result, route) in [
            (offer(app("org.musescore.MuseScore", "3.6.2.548020600"), source: "GitHub"), InstallCoordinator.Route.vendor),
            (offer(try gitKraken("STANDALONE")), .vendor),
            (offer(try gitKraken("STANDALONE")), .homebrew),
            (offer(try hoppscotch("26.8.2", feed: Self.selfHostFeed), source: "GitHub", package: Self.cloudDMG), .vendor),
            (offer(try hoppscotch("26.8.2", feed: Self.cloudFeed), source: "GitHub", package: Self.selfHostDMG), .vendor),
        ] {
            await #expect(throws: OneClickGateRegistry.Withheld.self) {
                _ = try await coordinator.perform(
                    result, route: route, installedPopulation: [result.app],
                    digestOnlyAllowed: false, progress: { _ in })
            }
        }
    }
}
