import Foundation
import Testing
@testable import DuoUpdaterCore

/// `OneClickGate`: a recipe family names which installed copies may take the
/// one-click; everything else keeps detection only. Exercised through the
/// gates registered today (MuseScore and Memoh by installed version, GitKraken
/// by an asar entry, Hoppscotch by both a version and an executable marker) and
/// through both places that enforce them.
struct OneClickGateTests {
    /// A bundle at a fresh path whose `app.asar` packs `files` (path → contents),
    /// in Electron's layout: `[4][header pickle size]`, then
    /// `[payload][json length][json]` padded to 4 bytes, then the file bytes.
    private func bundle(_ files: [String: String]?) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("one-click-gate-\(UUID().uuidString)/App.app")
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
            == ["org.musescore.MuseScore", "com.axosoft.gitkraken", "ai.memoh.desktop", "io.hoppscotch.desktop"])
    }

    /// A bundle at a fresh path whose Info.plist is `plist` and whose
    /// `Contents/MacOS/<name>` holds `executable` (none when nil).
    private func tauriBundle(
        plist: [String: Any]?, executable: Data?, named name: String = "hoppscotch-desktop"
    ) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("one-click-gate-\(UUID().uuidString)/Hoppscotch.app")
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
            cloud, offering: remote(package: "Hoppscotch_mac_x64.dmg")) == nil)
        #expect(OneClickGateRegistry.withholding(
            cloud, offering: remote(source: "Homebrew", package: "hoppscotch")) == nil)
        #expect(OneClickGateRegistry.withholding(selfHost, offering: selfHostOffer) == nil)
        // Across editions: withheld by the offered edition's gate.
        #expect(marker(cloud, selfHostOffer) == Self.selfHostFeed)
        #expect(marker(selfHost, cloudOffer) == Self.cloudFeed)
        #expect(marker(selfHost, remote(source: "Homebrew", package: "hoppscotch")) == Self.cloudFeed)
        // Neither literal: withheld whichever edition is offered.
        #expect(marker(neither, cloudOffer) == Self.cloudFeed)
        #expect(marker(neither, selfHostOffer) == Self.selfHostFeed)
        // An offer no gate names, for either copy: the Self-Host cask, another
        // asset, another source, no package, no offer.
        let unnamed: [RemoteVersion?] = [
            remote(source: "Homebrew", package: "hoppscotch-selfhost"),
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
            for (feed, offer) in [(Self.cloudFeed, cloudOffer), (Self.selfHostFeed, selfHostOffer)] {
                #expect(OneClickGateRegistry.withholding(
                    try hoppscotch(version, feed: feed), offering: offer) != nil, "\(version)")
            }
        }
        #expect(OneClickGateRegistry.withholding(
            try hoppscotch(nil, feed: Self.cloudFeed), offering: cloudOffer) != nil)
    }

    /// The markers the downloaded package must carry: the offered edition's;
    /// none for an offer no edition gate names, or for an app without them.
    @Test func thePackageMustCarryTheOfferedEditionsMarker() {
        let id = "io.hoppscotch.desktop"
        #expect(OneClickGateRegistry.packageMarkers(for: id, offering: remote(package: Self.cloudDMG))
            == [Self.cloudFeed])
        #expect(OneClickGateRegistry.packageMarkers(for: id, offering: remote(package: Self.selfHostDMG))
            == [Self.selfHostFeed])
        #expect(OneClickGateRegistry.packageMarkers(
            for: id, offering: remote(source: "Homebrew", package: "hoppscotch")) == [Self.cloudFeed])
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
