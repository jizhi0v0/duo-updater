import Testing
import Foundation
@testable import DuoUpdaterCore

struct PackageInstallerTests {
    @Test func parsesDeveloperIDInstallerTeamIdentifier() {
        let output = """
        Package "Example.pkg":
           Status: signed by a certificate trusted by Mac OS X
           Certificate Chain:
            1. Developer ID Installer: Example Corp (ABCDE12345)
            2. Developer ID Certification Authority
            3. Apple Root CA
        """

        #expect(PackageInstaller.packageTeamIdentifier(fromPkgutilOutput: output) == "ABCDE12345")
    }

    @Test func ignoresNonInstallerCertificates() {
        let output = """
        Package "Example.pkg":
           Status: signed by a certificate trusted by Mac OS X
           Certificate Chain:
            1. Developer ID Application: Example Corp (ABCDE12345)
            2. Developer ID Certification Authority
            3. Apple Root CA
        """

        #expect(PackageInstaller.packageTeamIdentifier(fromPkgutilOutput: output) == nil)
    }

    @Test func acceptsFlatAndBundlePackagesButRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-entry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let flat = root.appendingPathComponent("Flat.pkg")
        try Data("flat".utf8).write(to: flat)

        let bundle = root.appendingPathComponent("Bundle.pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let symlink = root.appendingPathComponent("Link.pkg")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: flat)

        let text = root.appendingPathComponent("Readme.txt")
        try Data("not a package".utf8).write(to: text)

        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        #expect(PackageInstaller.isPackageEntry(flat, insideResolvedPath: base))
        #expect(PackageInstaller.isPackageEntry(bundle, insideResolvedPath: base))
        #expect(!PackageInstaller.isPackageEntry(symlink, insideResolvedPath: base))
        #expect(!PackageInstaller.isPackageEntry(text, insideResolvedPath: base))
    }

    @Test func packageScratchDirectoriesAreUniquePerInstall() {
        let app = URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true)
        let first = PackageInstaller.workDirectory(forInstalledApp: app)
        let second = PackageInstaller.workDirectory(forInstalledApp: app)

        #expect(first != second)
        #expect(first.lastPathComponent.hasPrefix("DuoUpdater-pkg-Example-App-"))
        #expect(second.lastPathComponent.hasPrefix("DuoUpdater-pkg-Example-App-"))
    }

    @Test func multiPackageImagesRequireAUniqueProductMatch() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("pkg-choice-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func package(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            return url
        }

        let product = try package("Foo.pkg")
        _ = try package("FooHelper.pkg")
        _ = try package("Bar.pkg")
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo")?.lastPathComponent
                    == product.lastPathComponent)

        try fm.removeItem(at: product)
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo") == nil,
                "a helper package must not win by substring")

        for sibling in ["Foo2Helper.pkg", "Foov2Agent.pkg", "Foo360.pkg"] {
            let misleading = try package(sibling)
            #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo") == nil,
                    "a sibling product beginning with digits must not look like a version")
            try fm.removeItem(at: misleading)
        }

        let versioned = try package("Foo-2.0.pkg")
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo")?.lastPathComponent
                    == versioned.lastPathComponent)

        _ = try package("Foo-v3.pkg")
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo") == nil,
                "two plausible product packages are ambiguous")

        try fm.removeItem(at: versioned)
        try fm.removeItem(at: root.appendingPathComponent("Foo-v3.pkg"))
        for qualified in [
            "Foo-2.0-beta.pkg", "Foo-2.0-rc1.pkg", "Foo-2.0-arm64.pkg",
            "Foo-2.0-universal.pkg",
        ] {
            let packageURL = try package(qualified)
            #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo")?.lastPathComponent
                        == packageURL.lastPathComponent)
            try fm.removeItem(at: packageURL)
        }
    }

    @Test func aSinglePackageNeedsNoFilenameConvention() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("pkg-single-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let only = root.appendingPathComponent("Installer.pkg")
        try Data("fixture".utf8).write(to: only)

        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Different App")?.lastPathComponent
                    == only.lastPathComponent)
    }

    /// The hand-over retires the *previous* Installer window for this app, so a
    /// package that fails the Developer-ID/Team-ID gate must not cost the user the
    /// window they already have open — nothing is closed and nothing is opened.
    @Test func aPackageThatFailsTheGateNeitherOpensNorRetiresAnything() async throws {
        let fm = FileManager.default
        let dir = PackageInstaller.workDirectory(forInstalledApp:
            URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        // Unsigned, so `pkgutil --check-signature` rejects it whatever else is true.
        let pkg = dir.appendingPathComponent("Example.pkg")
        try Data("not really a package".utf8).write(to: pkg)

        let opened = Recorder()
        let installer = PackageInstaller(opener: { await opened.record($0) })
        await #expect(throws: (any Error).self) {
            try await installer.reopen(
                package: pkg,
                installedApp: URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true))
        }
        #expect(await opened.urls.isEmpty)
    }

    @Test func replacementDuringBeforeOpenFailsTheFinalGate() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory
            .appendingPathComponent("trusted-\(UUID().uuidString).pkg")
        let uniqueApp = "Gate-\(UUID().uuidString)"
        let workPrefix = "DuoUpdater-pkg-\(uniqueApp)-"
        let tempDirectory = fm.temporaryDirectory
        let trusted = Data("trusted package".utf8)
        try trusted.write(to: source)
        defer { try? fm.removeItem(at: source) }

        let opened = Recorder()
        let installer = PackageInstaller(
            opener: { await opened.record($0) },
            // Simulates two different, valid packages signed by the same Team.
            // The Team gate accepts both; the pinned content proof must reject B.
            packageGate: { _, _ in })

        await #expect(throws: PackageInstaller.PackageError.self) {
            try await installer.downloadAndOpen(
                url: source,
                installedApp: URL(fileURLWithPath: "/Applications/\(uniqueApp).app"),
                onStage: { _ in },
                beforeOpen: {
                    // Replaces the exact approved pathname while the async hook is
                    // suspended, reproducing the original check/use window.
                    let manager = FileManager.default
                    let candidates = (try? manager.contentsOfDirectory(
                        at: tempDirectory, includingPropertiesForKeys: nil)) ?? []
                    guard let dir = candidates.first(where: {
                        $0.lastPathComponent.hasPrefix(workPrefix)
                    }), let pkg = try? manager.contentsOfDirectory(
                        at: dir, includingPropertiesForKeys: nil).first else { return }
                    try? Data("replacement package".utf8).write(to: pkg, options: .atomic)
                })
        }
        #expect(await opened.urls.isEmpty)
    }

    @Test func sourceFingerprintMismatchDoesNotRunBeforeOpen() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory
            .appendingPathComponent("source-proof-\(UUID().uuidString).pkg")
        try Data("source package A".utf8).write(to: source)
        defer { try? fm.removeItem(at: source) }

        let opened = Recorder()
        let retired = Flag()
        let installer = PackageInstaller(
            opener: { await opened.record($0) },
            packageGate: { _, _ in })

        await #expect(throws: PackageInstaller.PackageError.self) {
            try await installer.downloadAndOpen(
                url: source,
                installedApp: URL(fileURLWithPath: "/Applications/SourceProof.app"),
                onStage: { _ in },
                verifyDownload: { downloaded in
                    let fingerprint = try PackageInstaller.contentFingerprint(of: downloaded)
                    try Data("same-Team package B".utf8).write(to: downloaded, options: .atomic)
                    return fingerprint
                },
                beforeOpen: { await retired.set() })
        }
        #expect(!(await retired.value))
        #expect(await opened.urls.isEmpty)
    }

    @Test func bundleStylePackageCanBeFingerprintedAndHandedOff() async throws {
        let fm = FileManager.default
        let bundle = fm.temporaryDirectory
            .appendingPathComponent("Bundle-\(UUID().uuidString).pkg", isDirectory: true)
        try fm.createDirectory(
            at: bundle.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true)
        try Data("legacy package payload".utf8).write(
            to: bundle.appendingPathComponent("Contents/Archive.pax.gz"))
        defer { try? fm.removeItem(at: bundle) }

        let opened = Recorder()
        let installer = PackageInstaller(
            opener: { await opened.record($0) },
            packageGate: { _, _ in })
        try await installer.reopen(
            package: bundle,
            installedApp: URL(fileURLWithPath: "/Applications/Fixture.app"))

        #expect(await opened.urls == [bundle])
    }

    @Test func verifierFailureImmediatelyRemovesTheScratchDirectory() async throws {
        enum FixtureError: Error { case rejected }

        let fm = FileManager.default
        let uniqueApp = "Cleanup-\(UUID().uuidString)"
        let prefix = "DuoUpdater-pkg-\(uniqueApp)-"
        let source = fm.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).pkg")
        try Data(repeating: 0xA5, count: 64 * 1024).write(to: source)
        defer { try? fm.removeItem(at: source) }

        let installer = PackageInstaller(opener: { _ in })
        await #expect(throws: FixtureError.self) {
            try await installer.downloadAndOpen(
                url: source,
                installedApp: URL(fileURLWithPath: "/Applications/\(uniqueApp).app"),
                onStage: { _ in },
                verifyDownload: { _ in throw FixtureError.rejected })
        }

        let leftovers = try fm.contentsOfDirectory(
            at: fm.temporaryDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
        #expect(leftovers.isEmpty)
    }

    private actor Recorder {
        private(set) var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    private actor Flag {
        private(set) var value = false
        func set() { value = true }
    }

    @Test func discardsOnlyOurOwnScratchDirectories() throws {
        let fm = FileManager.default
        let app = URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true)

        let ours = PackageInstaller.workDirectory(forInstalledApp: app)
        try fm.createDirectory(at: ours, withIntermediateDirectories: true)
        let pkg = ours.appendingPathComponent("Example.pkg")
        try Data("pkg".utf8).write(to: pkg)
        #expect(PackageInstaller.discardWorkDirectory(containing: pkg))
        #expect(!fm.fileExists(atPath: ours.path))

        // Wrong name: someone else's temp directory is never removed.
        let foreign = fm.temporaryDirectory
            .appendingPathComponent("Other-pkg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: foreign, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: foreign) }
        let foreignPkg = foreign.appendingPathComponent("Example.pkg")
        try Data("pkg".utf8).write(to: foreignPkg)
        #expect(!PackageInstaller.discardWorkDirectory(containing: foreignPkg))
        #expect(fm.fileExists(atPath: foreignPkg.path))

        // Right name, wrong place: a persisted path pointing outside the temp
        // directory must not turn into a recursive delete there.
        let outside = fm.temporaryDirectory
            .appendingPathComponent("elsewhere-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("DuoUpdater-pkg-Example-App-x", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside.deletingLastPathComponent()) }
        let outsidePkg = outside.appendingPathComponent("Example.pkg")
        try Data("pkg".utf8).write(to: outsidePkg)
        #expect(!PackageInstaller.discardWorkDirectory(containing: outsidePkg))
        #expect(fm.fileExists(atPath: outsidePkg.path))
    }

    // MARK: Declared install destinations
    //
    // Bodies below are the real `PackageInfo` headers from vendor packages
    // downloaded on 2026-08-19, trimmed to the attributes the parser reads. They
    // cover all three shapes seen across the pkg recipes.

    /// Tailscale unpacks straight into the app bundle: `install-location` IS the
    /// destination, and every `<bundle path>` is a helper *inside* it. This is the
    /// case that makes a bundle-identifier gate unworkable — the package never
    /// declares `io.tailscale.ipn.macsys`, only its sub-bundles.
    @Test func destinationIsThePayloadRootWhenItIsTheAppItself() {
        let body = """
        <pkg-info identifier="com.tailscale.ipn.macsys" version="1.102.2" \
        install-location="/Applications/Tailscale.app" auth="root">
            <bundle path="./Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
        id="org.sparkle-project.Sparkle.Updater"/>
            <bundle path="./Contents/Library/LoginItems/TailscaleLoginItemHelper-macsys.app" \
        id="io.tailscale.ipn.macsys.login-item-helper"/>
        </pkg-info>
        """
        let dests = PackageInstaller.destinations(inPackageInfo: body)
        #expect(dests.contains("/Applications/Tailscale.app"))
        // Helpers nested inside the bundle come along as candidates too. That is
        // harmless: `AppScanner` only ever reports bundles sitting in the scanned
        // directories, never one buried inside another app, so a nested path can
        // never be the installed app the gate compares against.
        #expect(dests.contains("/Applications/Tailscale.app"))
    }

    /// WeChat DevTools is a flat component package rooted at `/`, so the
    /// destination comes from joining the relative bundle path onto it.
    @Test func destinationJoinsARelativeBundlePathOntoTheRoot() {
        let body = """
        <pkg-info identifier="com.tencent.wechatdevtools" version="2.02.2608182" \
        install-location="/" auth="root">
            <bundle path="./Applications/wechatwebdevtools.app" id="com.github.Electron"/>
        </pkg-info>
        """
        #expect(PackageInstaller.destinations(inPackageInfo: body)
            == ["/Applications/wechatwebdevtools.app"])
    }

    /// A single component legitimately writes more than one app. Constructed, not
    /// captured: the real Word archive spreads these across three components, and
    /// AutoUpdate actually lands under `/Library/Application Support/Microsoft/MAU2.0`.
    @Test func aPackageMayDeclareSeveralDestinations() {
        let body = """
        <pkg-info identifier="com.microsoft.word" version="16.112" \
        install-location="/Applications" auth="root">
            <bundle path="Microsoft Word.app" id="com.microsoft.Word"/>
            <bundle path="Microsoft Excel.app" id="com.microsoft.Excel"/>
        </pkg-info>
        """
        let dests = PackageInstaller.destinations(inPackageInfo: body)
        #expect(dests.contains("/Applications/Microsoft Word.app"))
        #expect(dests.contains("/Applications/Microsoft Excel.app"))
    }

    /// The property that motivates the gate: a same-vendor package for a
    /// *different* app resolves to a different destination, so it can be told
    /// apart from a genuine update even though the Team ID matches.
    @Test func aSiblingAppFromTheSameVendorIsADifferentDestination() {
        let body = """
        <pkg-info identifier="com.google.earth" install-location="/Applications" auth="root">
            <bundle path="Google Earth Pro.app" id="com.google.GoogleEarthPro"/>
        </pkg-info>
        """
        let dests = PackageInstaller.destinations(inPackageInfo: body)
        #expect(!dests.contains("/Applications/Google Chrome.app"))
        #expect(dests.contains("/Applications/Google Earth Pro.app"))
    }

    /// A body with nothing to go on yields no destinations, which the gate treats
    /// as "cannot verify" and falls back to the Team-only check rather than
    /// blocking a working install.
    @Test func anUnreadableLayoutYieldsNoDestinations() {
        #expect(PackageInstaller.destinations(inPackageInfo: "<pkg-info/>").isEmpty)
    }

    // MARK: Destination parsing traps
    //
    // Each of these was a real defect in the first version of this parser, which
    // scanned for the substring ".app" with unanchored attribute regexes. They
    // matter because the wrong answers were non-empty: a package that parses to a
    // fabricated destination is REFUSED, so these bugs broke legitimate updates
    // rather than merely weakening the gate.

    /// A reverse-DNS directory component contains ".app" without being a bundle.
    /// Truncating there both invents a destination and loses the real one.
    @Test func aDirectoryNamedLikeABundleDoesNotTruncateThePath() {
        let body = """
        <pkg-info install-location="/">
            <bundle path="./Library/Application Support/com.vendor.app/Real.app"/>
        </pkg-info>
        """
        // The real bundle must survive. The `com.vendor.app` ancestor also ends in
        // `.app` and is indistinguishable from a bundle by name, so it comes along
        // as a candidate — harmless, since it is a path the package really writes
        // and no installed app lives there.
        #expect(PackageInstaller.destinations(inPackageInfo: body)
            .contains("/Library/Application Support/com.vendor.app/Real.app"))
    }

    /// An `.appex` is not an `.app`, and one with no app ancestor installs no
    /// application — it must contribute nothing rather than a fabricated sibling.
    @Test func anAppExtensionDoesNotBecomeAnAppDestination() {
        let body = #"<pkg-info install-location="/Applications"><bundle path="./Widget.appex"/></pkg-info>"#
        #expect(PackageInstaller.destinations(inPackageInfo: body).isEmpty)
    }

    /// A plug-in inside a bundle resolves to the bundle, not to itself.
    @Test func aNestedBundleResolvesToItsTopLevelApp() {
        let body = """
        <pkg-info install-location="/Applications/Tailscale.app">
            <bundle path="./Contents/PlugIns/ShareExtension-macsys.appex"/>
        </pkg-info>
        """
        #expect(PackageInstaller.destinations(inPackageInfo: body)
            == ["/Applications/Tailscale.app"])
    }

    /// `search-path` also ends in "path". An unanchored attribute scan picked it
    /// up and added a destination the installer never writes.
    @Test func onlyTheBundlePathAttributeIsRead() {
        let body = #"<pkg-info install-location="/Applications"><bundle search-path="/Evil.app" path="./Good.app"/></pkg-info>"#
        #expect(PackageInstaller.destinations(inPackageInfo: body)
            == ["/Applications/Good.app"])
    }

    /// A commented-out element declares nothing.
    @Test func commentedOutBundlesAreNotDestinations() {
        let body = """
        <pkg-info install-location="/Applications">
            <!-- <bundle path="./Victim.app"/> -->
            <bundle path="./Real.app"/>
        </pkg-info>
        """
        #expect(PackageInstaller.destinations(inPackageInfo: body) == ["/Applications/Real.app"])
    }

    /// Entities have to be decoded, or an app with `&` in its name is refused.
    @Test func xmlEntitiesInAnAppNameAreDecoded() {
        let body = #"<pkg-info install-location="/Applications"><bundle path="./Foo &amp; Bar.app"/></pkg-info>"#
        #expect(PackageInstaller.destinations(inPackageInfo: body)
            == ["/Applications/Foo & Bar.app"])
    }

    /// Single quotes are legal XML; the regex scan silently returned nothing.
    @Test func singleQuotedAttributesParse() {
        let body = "<pkg-info install-location='/Applications'><bundle path='./Foo.app'/></pkg-info>"
        #expect(PackageInstaller.destinations(inPackageInfo: body) == ["/Applications/Foo.app"])
    }

    /// The filesystem is case-insensitive and vendors are inconsistent.
    @Test func bundleSuffixMatchingIsCaseInsensitive() {
        let body = #"<pkg-info install-location="/Applications"><bundle path="./Foo.APP"/></pkg-info>"#
        #expect(PackageInstaller.destinations(inPackageInfo: body) == ["/Applications/Foo.APP"])
    }

    /// Malformed input yields nothing, which the gate treats as "cannot verify".
    @Test func unparsableBodyYieldsNoDestinations() {
        #expect(PackageInstaller.destinations(inPackageInfo: "not xml at all <<<").isEmpty)
    }
}
