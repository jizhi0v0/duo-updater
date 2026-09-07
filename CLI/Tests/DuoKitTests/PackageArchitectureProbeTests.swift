import Foundation
import Testing
@testable import DuoKit
@testable import DuoUpdaterCore

/// The `warn` path has no live example — measured 2026-09-07, every declaration
/// in the registry is universal (#415) — so the classifier is tested directly
/// rather than against a real package. A check whose only interesting branch is
/// unreachable in production is exactly the kind this repo asks to be pinned by
/// construction instead of by fixture.
struct PackageArchitectureProbeTests {

    /// Mutation: compare against a literal `"arm64,x86_64"` instead of counting
    /// names, and the `x86_64,arm64` cases go red. Both spellings are live —
    /// 9 recipes use one order, 6 the other — so order carries no meaning and a
    /// string comparison would call half the registry single-architecture.
    @Test(arguments: [
        ("arm64,x86_64", false), ("x86_64,arm64", false),
        ("arm64, x86_64", false), ("x86_64", true), ("arm64", true),
        ("arm64,arm64", true),
    ])
    func universalIsDecidedByCountingNamesNotBySpelling(value: String, isSingle: Bool) {
        let declaration = PackageArchitectureProbe.classify(value)
        if case .single = declaration {
            #expect(isSingle, "\(value) was read as single-architecture")
        } else {
            #expect(!isSingle, "\(value) was read as universal")
        }
        #expect(declaration.value == value)   // the vendor's spelling is preserved verbatim
    }

    /// Mutation: drop the `\s*` around `=` and the formatted spelling goes red.
    /// This is an XML attribute, not a fixed vendor string — a reformatted
    /// Distribution is the same declaration.
    @Test func theAttributeIsReadWhateverTheXMLSpacing() {
        let bodies = [
            #"<options hostArchitectures="arm64,x86_64"/>"#,
            #"<options hostArchitectures = "arm64,x86_64" />"#,
            "<options\n    hostArchitectures=\"arm64,x86_64\"\n/>",
        ]
        for body in bodies {
            #expect(PackageArchitectureProbe.hostArchitecturesAttribute(
                in: Data(body.utf8)) == "arm64,x86_64", "failed on: \(body)")
        }
        // Absent must read as nil, not as an empty declaration — `.absent` and
        // `.single("")` are different findings.
        #expect(PackageArchitectureProbe.hostArchitecturesAttribute(
            in: Data(#"<options rootVolumeOnly="true"/>"#.utf8)) == nil)
    }

    /// Registry-derived: the SET of pkg specs, not a count.
    ///
    /// ⚠️ A count pin is the trap CLAUDE.md's `app_test_coverage.py` lesson names
    /// ("比名字集合,不要比两个总数"): remove one pkg spec, add another, and 22
    /// still holds. The first version of this test pinned the count AND
    /// re-implemented the filter inline, so deleting `sweepPackageArchitecture`
    /// entirely left it green.
    ///
    /// It also spans BOTH registries that can produce a pkg install, because a
    /// GitHub rule flipping `installerKind` to `.pkg` is the same silent move onto
    /// the gate-less route as a vendor recipe flipping `kind`.
    @Test func thePkgRouteIsExactlyWhatTheDocsSayItIs() {
        let vendorPkgs = Set(VendorProbeRegistry.recipes
            .filter { $0.install?.kind == .pkg }
            .map { Verify.pkgArchFinding($0, host: "-", outcome: nil, elapsedMs: 0).recipeID })
        #expect(vendorPkgs == [
            "pkgarch:cc.ffitch.shottr:stable",
            "pkgarch:com.microsoft.Excel:stable",
            "pkgarch:com.microsoft.OneDrive:stable",
            "pkgarch:com.microsoft.Outlook:stable",
            "pkgarch:com.microsoft.Powerpoint:stable",
            "pkgarch:com.microsoft.Word:stable",
            "pkgarch:com.microsoft.edgemac.Beta:beta",
            "pkgarch:com.microsoft.edgemac.Dev:dev",
            "pkgarch:com.microsoft.edgemac:stable",
            "pkgarch:com.microsoft.m365copilot:stable",
            "pkgarch:com.microsoft.onenote.mac:stable",
            "pkgarch:com.microsoft.teams2:stable",
            "pkgarch:com.netease.uuremote:stable",
            "pkgarch:com.oray.sunlogin.macclient:stable",
            "pkgarch:com.tclementdev.timemachineeditor.application:stable",
            "pkgarch:com.tencent.wechatdevtools:nightly",
            "pkgarch:com.tencent.wechatdevtools:rc",
            "pkgarch:com.tencent.wechatdevtools:stable",
            "pkgarch:com.youqu.todesk.mac:stable",
            "pkgarch:io.tailscale.ipn.macsys:rc",
            "pkgarch:io.tailscale.ipn.macsys:stable",
            "pkgarch:io.tailscale.ipn.macsys:unstable",
        ], """
            The pkg install route changed. Every one of these installs with NO \
            architecture gate, so this is worth reading rather than re-pinning: \
            re-run scripts/pkg_host_architectures.py and update #415 and \
            PackageInstaller's comment before changing this set.
            """)
        // ⚠️ The GitHub side is NOT swept — `sweepPackageArchitecture` takes
        // `[VendorProbeRecipe]` only. XQuartz was measured by hand for #415 and is
        // universal. This assertion exists so that gap stays a KNOWN one: a second
        // GitHub pkg rule makes it go red rather than joining the unswept set
        // silently.
        let githubPkgs = Set(GitHubReleaseRegistry.rules
            .filter { $0.installerKind == .pkg }
            .map(\.bundleID))
        #expect(githubPkgs == ["org.xquartz.X11"], """
            A GitHub rule now ships a pkg that the pkgarch sweep does not read. \
            Either extend the sweep to GitHubReleaseRegistry or record why not.
            """)
    }

    /// Mutation: use `recipe.recipeID` instead of `pkgArchID(recipe)` inside
    /// `pkgArchFinding` and this goes red.
    ///
    /// `Baseline` keys its entries on the id ALONE, so a pkgarch finding sharing
    /// the vendor recipe's id lands in the vendor recipe's baseline entry: one
    /// `consecutiveActionable` streak fed by two sweeps, and one issue number for
    /// both. Every other registry namespaces for this reason (`appstore:`,
    /// `feed:`, `github:`, `vendor:`).
    ///
    /// ⚠️ Asserted through `pkgArchFinding`, NOT by calling `pkgArchID` directly.
    /// The first version of this test did the latter and the mutation stayed
    /// GREEN — reverting the call site cannot be seen by a test that never goes
    /// through the call site.
    @Test func pkgArchFindingsGetTheirOwnBaselineKey() throws {
        let pkgs = VendorProbeRegistry.recipes.filter { $0.install?.kind == .pkg }
        let recipe = try #require(pkgs.first)
        let finding = Verify.pkgArchFinding(
            recipe, host: "example.invalid",
            outcome: .success(.universal("arm64,x86_64")), elapsedMs: 1)
        #expect(finding.recipeID.hasPrefix("pkgarch:"))
        #expect(finding.recipeID != recipe.recipeID)
        // Across the whole route, no pkgarch id may collide with any vendor id.
        let pkgArchIDs = Set(pkgs.map {
            Verify.pkgArchFinding($0, host: "-", outcome: nil, elapsedMs: 0).recipeID
        })
        let vendorIDs = Set(VendorProbeRegistry.recipes.map(\.recipeID))
        #expect(pkgArchIDs.isDisjoint(with: vendorIDs))
        #expect(pkgArchIDs.count == pkgs.count, "ids must stay unique per channel")
    }

    /// The sweep's status mapping, which no real package can exercise: measured
    /// 2026-09-07, every declaration in the registry is universal, so `.warn` —
    /// its only actionable branch — has no live example. Without this the branch
    /// would ship having never produced a finding.
    ///
    /// Mutation: flip `single ? .warn : .ok` either way and this goes red.
    /// Mutation: warn on `.absent` (the tempting "we should know about these")
    /// and this goes red too — 7 of 22 declare nothing, so that would file seven
    /// findings on day one.
    @Test func onlyASingleArchitectureDeclarationWarns() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.install?.kind == .pkg })
        func status(_ d: PackageArchitectureProbe.Declaration) -> FindingStatus {
            Verify.pkgArchFinding(recipe, host: "-", outcome: .success(d), elapsedMs: 0).status
        }
        #expect(status(.single("x86_64")) == .warn)
        #expect(status(.universal("arm64,x86_64")) == .ok)
        #expect(status(.absent) == .ok)
        #expect(status(.notAFlatPackage("bytes=28 magic=0x3c21444f")) == .ok)
        // A vendor hanging up is infra, never a recipe defect — filing those
        // trains the reader to ignore the sweep.
        #expect(Verify.pkgArchFinding(
            recipe, host: "-", outcome: .failure(URLError(.timedOut)), elapsedMs: 0)
            .status == .infra)
        // The declaration is recorded even when nothing is wrong, so drift shows
        // up as a report diff rather than needing someone to re-read a comment.
        let ok = Verify.pkgArchFinding(
            recipe, host: "-", outcome: .success(.universal("arm64,x86_64")), elapsedMs: 0)
        #expect(ok.warnings.contains("hostArchitectures=arm64,x86_64"))
    }

    /// Mutation: drop the `pkgarch:` ids from `liveRecipeIDs()` and this goes red.
    ///
    /// Nothing else would. `Baseline.prune` removes every entry whose id is not
    /// live, and the pruned baseline is what gets SAVED — so a pkgarch warn's
    /// streak is wiped before the next run reads it, `isReportable` never reaches
    /// `actionableThreshold`, and the sweep's only actionable branch can never
    /// file an issue. No test failed, no sweep failed; the id simply printed
    /// "dropped — no recipe produces this id any more" 22 times a run.
    @Test func pkgArchEntriesSurviveBaselinePruning() throws {
        let live = Verify.liveRecipeIDs()
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.install?.kind == .pkg })
        let id = Verify.pkgArchFinding(recipe, host: "-", outcome: nil, elapsedMs: 0).recipeID
        #expect(live.contains(id), "\(id) is not live, so prune deletes it every run")

        var baseline = Baseline()
        baseline.reconcile(Verify.pkgArchFinding(
            recipe, host: "-", outcome: .success(.single("x86_64")), elapsedMs: 0))
        let pruned = baseline.prune(keeping: live)
        #expect(!pruned.removed.contains(id))
        // And the streak it just recorded is still there to be built on.
        #expect(baseline.streak(id) == 1)
    }

    /// A synthetic flat package, so the parts that only ever ran against the
    /// network get exercised: the header parse, `XarTOC.member`, `Inflate`, and
    /// the Distribution-before-PackageInfo preference.
    ///
    /// ⚠️ These existed nowhere before. Swapping `bigEndian` for `littleEndian` in
    /// the header read passed the ENTIRE file — the classifier tests never touch a
    /// byte of a package.
    private static func xar(
        members: [(name: String, body: String)], compress: Bool = true,
        magic: String = "xar!", headerSize: UInt16 = 28
    ) -> Data {
        var heap = Data()
        var entries = ""
        for member in members {
            let raw = Data(member.body.utf8)
            let stored = compress
                ? (try! (raw as NSData).compressed(using: .zlib) as Data)
                : raw
            entries += """
                <file id="\(entries.count)"><name>\(member.name)</name>                <data><offset>\(heap.count)</offset><length>\(stored.count)</length>                <size>\(raw.count)</size>                <encoding style="\(compress ? "application/x-gzip" : "")"/></data></file>
                """
            heap.append(stored)
        }
        let toc = Data("<xar><toc>\(entries)</toc></xar>".utf8)
        let tocZ = try! (toc as NSData).compressed(using: .zlib) as Data
        var out = Data(magic.utf8)
        out.append(contentsOf: withUnsafeBytes(of: headerSize.bigEndian) { Array($0) })
        out.append(contentsOf: withUnsafeBytes(of: UInt16(1).bigEndian) { Array($0) })
        out.append(contentsOf: withUnsafeBytes(of: UInt64(tocZ.count).bigEndian) { Array($0) })
        out.append(contentsOf: withUnsafeBytes(of: UInt64(toc.count).bigEndian) { Array($0) })
        out.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })
        out.append(tocZ)
        out.append(heap)
        return out
    }

    /// Mutation: `bigEndian` → `littleEndian` on either header field, and this
    /// goes red. Nothing else in this file reads a package byte.
    @Test func aSyntheticPackageIsParsedEndToEnd() async throws {
        let pkg = Self.xar(members: [
            ("Distribution", #"<installer-gui-script><options hostArchitectures="arm64,x86_64"/></installer-gui-script>"#),
        ])
        let url = try StubURLProtocol.serve(pkg)
        defer { StubURLProtocol.reset() }
        let result = await PackageArchitectureProbe.declaration(at: url, session: StubURLProtocol.session)
        #expect(try result.get() == .universal("arm64,x86_64"))
    }

    /// Mutation: try `PackageInfo` before `Distribution` and this goes red. On a
    /// product archive the Distribution is the file that carries the declaration,
    /// and a component `PackageInfo` beside it may say something narrower.
    @Test func distributionWinsOverPackageInfo() async throws {
        let pkg = Self.xar(members: [
            ("PackageInfo", #"<pkg-info hostArchitectures="x86_64"/>"#),
            ("Distribution", #"<options hostArchitectures="arm64,x86_64"/>"#),
        ])
        let url = try StubURLProtocol.serve(pkg)
        defer { StubURLProtocol.reset() }
        let result = await PackageArchitectureProbe.declaration(at: url, session: StubURLProtocol.session)
        #expect(try result.get() == .universal("arm64,x86_64"))
    }

    /// A package with neither file, and one whose members carry no declaration:
    /// both are `.absent`, which is the registry's majority answer and must never
    /// become a warn.
    @Test func aPackageWithNoDeclarationIsAbsentNotSingle() async throws {
        for members in [[("Bom", "x")], [("Distribution", "<options rootVolumeOnly=\"true\"/>")]] {
            let url = try StubURLProtocol.serve(Self.xar(members: members))
            defer { StubURLProtocol.reset() }
            let result = await PackageArchitectureProbe.declaration(at: url, session: StubURLProtocol.session)
            #expect(try result.get() == .absent)
        }
    }

    /// Hostile input must REPORT, never trap. `Int(someUInt64)` traps above
    /// `Int.max` and a trap is not catchable, so a vendor-controlled length field
    /// with the high bit set would have killed `duo verify` outright.
    @Test func aHostileHeaderIsReportedRatherThanCrashing() async throws {
        var pkg = Data("xar!".utf8)
        pkg.append(contentsOf: withUnsafeBytes(of: UInt16(28).bigEndian) { Array($0) })
        pkg.append(contentsOf: withUnsafeBytes(of: UInt16(1).bigEndian) { Array($0) })
        pkg.append(contentsOf: withUnsafeBytes(of: UInt64(0x8000_0000_0000_0000).bigEndian) { Array($0) })
        pkg.append(contentsOf: withUnsafeBytes(of: UInt64(1).bigEndian) { Array($0) })
        pkg.append(contentsOf: withUnsafeBytes(of: UInt32(0).bigEndian) { Array($0) })
        let url = try StubURLProtocol.serve(pkg)
        defer { StubURLProtocol.reset() }
        let result = await PackageArchitectureProbe.declaration(at: url, session: StubURLProtocol.session)
        guard case .notAFlatPackage(let why) = try result.get() else {
            Issue.record("expected notAFlatPackage"); return
        }
        #expect(why.contains("toc="))
    }

    /// A server that ignores `Range` and answers 200 with the whole file must be
    /// refused, not read. Reading its first bytes would file `notAFlatPackage` as
    /// `ok` — a green verdict produced from the wrong bytes.
    @Test func aServerIgnoringRangeIsRefused() async throws {
        let url = try StubURLProtocol.serve(Self.xar(members: [
            ("Distribution", #"<options hostArchitectures="arm64,x86_64"/>"#),
        ]), status: 200)
        defer { StubURLProtocol.reset() }
        let result = await PackageArchitectureProbe.declaration(at: url, session: StubURLProtocol.session)
        #expect(throws: (any Error).self) { try result.get() }
    }
}

/// Serves a fixture per URL, so the reader can be driven without a vendor.
///
/// ⚠️ Keyed by URL and lock-guarded, NOT a single static body. swift-testing runs
/// these in parallel, and the first version held one `static var body` that
/// concurrent tests overwrote — three tests failed against a fixture another test
/// had just installed. A stub that works only when run alone is a flaky test
/// waiting to be blamed on the code under test.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Fixture { let body: Data; let status: Int }
    nonisolated(unsafe) private static var fixtures: [String: Fixture] = [:]
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counter = 0

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Returns a URL unique to this fixture, so parallel tests cannot collide.
    static func serve(_ data: Data, status: Int = 206) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        let path = "/fixture-\(counter).pkg"
        fixtures[path] = Fixture(body: data, status: status)
        return URL(string: "https://stub.invalid\(path)")!
    }

    static func reset() {}

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.invalid"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let path = request.url?.path else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        Self.lock.lock()
        let fixture = Self.fixtures[path]
        Self.lock.unlock()
        guard let fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return
        }
        // Honour Range the way a correct server does, so the reader's three
        // sequential reads land on the bytes they asked for.
        var slice = fixture.body
        var headers = ["Content-Type": "application/octet-stream"]
        if fixture.status == 206,
           let raw = request.value(forHTTPHeaderField: "Range")?
               .replacingOccurrences(of: "bytes=", with: ""),
           case let parts = raw.split(separator: "-"), parts.count == 2,
           let lo = Int(parts[0]), let hi = Int(parts[1]), lo <= hi, lo < fixture.body.count {
            let upper = min(hi, fixture.body.count - 1)
            slice = fixture.body.subdata(in: lo..<(upper + 1))
            headers["Content-Range"] = "bytes \(lo)-\(upper)/\(fixture.body.count)"
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: fixture.status, httpVersion: "HTTP/1.1",
            headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: slice)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
