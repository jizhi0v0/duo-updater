import Foundation
import Testing
@testable import DuoUpdaterCore

/// go's installs as managed rows (`GoAdapter`, design §4.9). The build info
/// is what `go version -m` printed for real binaries on 2026-10-27
/// (`~/go/bin/govulncheck`; gofumpt v0.9.1 built with go1.27.3 into an
/// isolated `GOBIN`); the `go list -m -json` answers are go 1.27.3's own
/// output for `golang.org/x/vuln@latest` and `mvdan.cc/gofumpt@latest`.
///
/// The host is scripted (`FakeHost`): nothing here lists the real home, runs
/// go or reaches the network. Each case names the mutation it fails under.
struct GoAdapterTests {

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let root = "/ZZFixture-home/go/bin"
    static let go = "/ZZbrew/bin/go"

    static func info(_ path: String, _ module: String, _ version: String, go: String = "go1.27.3") -> GoBuildInfo {
        GoBuildInfo.parse(goVersion: go, modinfo: "path\t\(path)\nmod\t\(module)\t\(version)\th1:x=\n")
    }

    static let gofumptLatest = Data("""
        {
        \t"Path": "mvdan.cc/gofumpt",
        \t"Version": "v0.12.0",
        \t"Query": "latest",
        \t"Time": "2026-09-07T22:34:18Z",
        \t"GoVersion": "1.26.0"
        }
        """.utf8)

    final class FakeHost: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: Data] = ["/ZZbrew/Cellar/go/1.27.3/INSTALL_RECEIPT.json": Data("{}".utf8)]
        var links: [String: String] = [GoAdapterTests.go: "/ZZbrew/Cellar/go/1.27.3/libexec/bin/go"]
        var binaries: [String: GoBuildInfo] = [
            "gofumpt": GoAdapterTests.info("mvdan.cc/gofumpt", "mvdan.cc/gofumpt", "v0.9.1"),
            "govulncheck": GoAdapterTests.info("golang.org/x/vuln/cmd/govulncheck", "golang.org/x/vuln", "v1.3.0", go: "go1.26.4"),
            "stringer": GoAdapterTests.info("golang.org/x/tools/cmd/stringer", "golang.org/x/tools", "v0.0.0-20191109021931-daa7c04131f5"),
            "mytool": GoAdapterTests.info("github.com/me/mytool", "github.com/me/mytool", "(devel)"),
            "dirty": GoAdapterTests.info("github.com/me/dirty", "github.com/me/dirty", "v1.2.3+dirty"),
            "loose": GoAdapterTests.info("command-line-arguments", "command-line-arguments", "(devel)"),
            "fumpt-old": GoAdapterTests.info("mvdan.cc/gofumpt", "mvdan.cc/gofumpt", "v0.8.0"),
        ]
        var latest: [String: Data] = [
            "mvdan.cc/gofumpt": GoAdapterTests.gofumptLatest,
            "golang.org/x/vuln": Data(#"{"Path":"golang.org/x/vuln","Version":"v1.3.0","GoVersion":"1.22.0"}"#.utf8),
        ]
        var processes: [NpmActivity.Process] = []
        var quarantined: Set<String> = []
        private var _runs: [(arguments: [String], environment: [String: String])] = []
        var runs: [(arguments: [String], environment: [String: String])] { lock.withLock { _runs } }

        var host: GoAdapter.Host {
            GoAdapter.Host(
                contents: { path in self.lock.withLock { self.files[path] } },
                directories: { path in
                    self.lock.withLock { path == GoAdapterTests.root ? Array(self.binaries.keys) + [".DS_Store"] : nil }
                },
                resolve: { path in
                    self.lock.withLock {
                        if let link = self.links[path] { return link }
                        if path.hasPrefix(GoAdapterTests.root + "/") { return path }
                        return nil
                    }
                },
                isQuarantined: { path in self.lock.withLock { self.quarantined.contains(path) } },
                buildInfo: { path in self.lock.withLock { self.binaries[(path as NSString).lastPathComponent] } },
                run: { executable, arguments, environment in
                    #expect(executable == GoAdapterTests.go)
                    return self.lock.withLock {
                        self._runs.append((arguments, environment))
                        return self.latest[String(arguments[3].dropLast("@latest".count))]
                    }
                },
                proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
                processes: { self.lock.withLock { self.processes } })
        }
    }

    static func adapter(_ host: FakeHost) -> GoAdapter {
        GoAdapter(home: home, host: host.host, homebrewRoots: ["/ZZbrew"])
    }

    static func status(_ report: CLIToolReport, _ key: String) -> CLIToolStatus? {
        report.statuses.first { $0.managedItem?.key == key }
    }

    // MARK: build info

    /// The `path` line is the package `go install` names. Mutation: skip it,
    /// as `GoBuildInfo` did before.
    @Test func theBuildInfoKeepsThePackagePath() {
        let info = GoBuildInfo.parse(goVersion: "go1.26.4", modinfo: """
            path\tgolang.org/x/vuln/cmd/govulncheck
            mod\tgolang.org/x/vuln\tv1.3.0\th1:hZYz=
            dep\tgolang.org/x/mod\tv0.35.0\th1:Ww1D=

            """)
        #expect(info.packagePath == "golang.org/x/vuln/cmd/govulncheck")
        #expect(info.main?.path == "golang.org/x/vuln")
        #expect(info.main?.version == "v1.3.0")
        #expect(info.dependencies.map(\.path) == ["golang.org/x/mod"])
    }

    // MARK: where

    /// `GOBIN`, else `GOPATH`'s first entry, else `~/go/bin` — from `go env
    /// -w`'s file. Mutation: read only the default; take `GOPATH` whole.
    @Test func theRootFollowsGoEnvsFile() throws {
        let host = FakeHost()
        let file = Self.home.path + "/Library/Application Support/go/env"
        #expect(Self.adapter(host).binDirectory() == Self.root)
        host.files[file] = Data("GOPROXY=https://goproxy.cn,direct\nGOPATH=/ZZgo:/ZZother\n".utf8)
        #expect(Self.adapter(host).binDirectory() == "/ZZgo/bin")
        host.files[file] = Data("GOPATH=/ZZgo\nGOBIN=/ZZbin\n".utf8)
        #expect(Self.adapter(host).binDirectory() == "/ZZbin")
    }

    // MARK: scan

    /// One row per Go binary, keyed by its package; what `go install @latest`
    /// would not reproduce is reported with why. Mutation: offer a
    /// pseudo-version, `(devel)`, `+dirty` or loose-files build; key a
    /// renamed copy by the package alone (two identities collide).
    @Test func theScanClassifiesEachBinary() async throws {
        let host = FakeHost()
        let scan = await Self.adapter(host).scan()
        let byName = Dictionary(uniqueKeysWithValues: scan.items.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["gofumpt", "govulncheck", "stringer", "mytool", "dirty", "loose", "fumpt-old"])
        #expect(Set(scan.items.map(\.identity)).count == scan.items.count)
        let gofumpt = try #require(byName["gofumpt"])
        #expect(gofumpt.key == "mvdan.cc/gofumpt")
        #expect(gofumpt.installed == "0.9.1")
        #expect(gofumpt.backend == "mvdan.cc/gofumpt")
        #expect(gofumpt.installPath == Self.root + "/gofumpt")
        #expect(gofumpt.notes == .goModule("mvdan.cc/gofumpt"))
        #expect(GoAdapter.notIndexed(gofumpt) == nil)
        #expect(GoAdapter.notIndexed(try #require(byName["govulncheck"])) == nil)
        #expect(GoAdapter.notIndexed(try #require(byName["stringer"])) == "a pseudo-version: built from a commit, not a release")
        #expect(GoAdapter.notIndexed(try #require(byName["mytool"])) == "built from a checkout (devel)")
        #expect(GoAdapter.notIndexed(try #require(byName["dirty"])) == "built from a checkout with uncommitted changes")
        #expect(GoAdapter.notIndexed(try #require(byName["loose"])) == "built from loose .go files, not a package")
        let renamed = try #require(byName["fumpt-old"])
        #expect(renamed.key == "mvdan.cc/gofumpt#fumpt-old")
        #expect(GoAdapter.notIndexed(renamed) == "renamed since go install wrote it")
        #expect(scan.roots.first?.binary == ManagedRoot.Binary(path: Self.go, version: "1.27.3", trust: .homebrewKeg))
        #expect(host.runs.isEmpty)
    }

    /// The forms a pseudo-version takes. Mutation: match only `v0.0.0-…`.
    @Test func pseudoVersionsAreKnown() {
        #expect(GoAdapter.isPseudoVersion("0.0.0-20191109021931-daa7c04131f5"))
        #expect(GoAdapter.isPseudoVersion("1.2.4-0.20191109021931-daa7c04131f5"))
        #expect(GoAdapter.isPseudoVersion("1.2.3-pre.0.20191109021931-daa7c04131f5"))
        #expect(!GoAdapter.isPseudoVersion("1.2.3"))
        #expect(!GoAdapter.isPseudoVersion("1.2.3-rc.1"))
        #expect(GoAdapter.installedName(of: "github.com/x/y/cmd/foo/v2") == "foo")
        #expect(GoAdapter.installedName(of: "mvdan.cc/gofumpt") == "gofumpt")
    }

    // MARK: check and click

    /// gofumpt v0.9.1 → v0.12.0 offered as `go install mvdan.cc/gofumpt@latest`
    /// with `GOBIN` the root; govulncheck current; one `go list` per module,
    /// with `GOTOOLCHAIN=local`. Mutation: drop `GOBIN` (the build lands
    /// wherever go's env file says); ask `go list` for a reported row.
    @Test func gofumptIsOfferedAndTheCommandWritesTheRow() async throws {
        let host = FakeHost()
        let adapter = Self.adapter(host)
        let report = await ManagedProvider(
            adapter, home: Self.home, proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { _, _, _, _, _ in ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: []) }
        ).check()
        let gofumpt = try #require(Self.status(report, "mvdan.cc/gofumpt"))
        #expect(gofumpt.state == .updateAvailable)
        #expect(gofumpt.latestVersion == "0.12.0")
        #expect(gofumpt.oneClick == CLIToolCommand(executable: Self.go, arguments: ["install", "mvdan.cc/gofumpt@latest"], pathPrefix: nil))
        #expect(Self.status(report, "golang.org/x/vuln/cmd/govulncheck")?.state == .upToDate)
        #expect(Self.status(report, "github.com/me/mytool")?.withheld == .unsupportedInstaller)
        #expect(host.runs.map(\.arguments).sorted { $0[3] < $1[3] } == [
            ["list", "-m", "-json", "golang.org/x/vuln@latest"], ["list", "-m", "-json", "mvdan.cc/gofumpt@latest"],
        ])
        #expect(host.runs.first?.environment["GOTOOLCHAIN"] == "local")
        #expect(host.runs.first?.environment["HOME"] == Self.home.path)
        let root = try #require(await adapter.scan().roots.first)
        let item = try #require(gofumpt.managedItem)
        let upgrade = try #require(adapter.upgrade(item, root: root))
        #expect(upgrade.environment == ["GOTOOLCHAIN": "local", "GOFLAGS": "-mod=mod", "GOBIN": Self.root])
    }

    /// A newest whose `go.mod` asks for a newer Go is reported, never fetched
    /// (`GOTOOLCHAIN=local`). Mutation: ignore `GoVersion`.
    @Test func aNewestNeedingANewerGoIsReported() async throws {
        let host = FakeHost()
        host.latest["mvdan.cc/gofumpt"] = Data(#"{"Version":"v0.12.0","GoVersion":"1.28.0"}"#.utf8)
        let verdicts = await Self.adapter(host).check(await Self.adapter(host).scan())
        let gofumpt = try #require(verdicts.first { $0.item.key == "mvdan.cc/gofumpt" })
        #expect(gofumpt.blocker == .runtimeTooOld("go 1.28.0"))
    }

    /// A go that is found but may not run — the pkg installer's
    /// `/usr/local/go`, whose signature is not measured, or a quarantined keg
    /// — is never asked anything: the root has a binary, and the check's
    /// trust guard is what keeps it from running. With nothing asked, no
    /// newer version is known: the rows are not checked, say which go was
    /// not run and why, and hand no command out (one appears only when the
    /// guard is gone and the row turns offered). Mutation: drop
    /// `root.runnable` from `check`'s guard
    /// (review round 1: the old fixture left no go at all, so the guard was
    /// never reached).
    @Test(arguments: ["pkg", "quarantined keg"])
    func aGoThatMayNotRunIsNotRun(_ which: String) async throws {
        let host = FakeHost()
        let pkg = "/usr/local/go/bin/go"
        if which == "pkg" {
            host.files["/ZZbrew/Cellar/go/1.27.3/INSTALL_RECEIPT.json"] = nil
            host.links[pkg] = pkg
            host.files["/usr/local/go/VERSION"] = Data("go1.27.3\ntime 2026-10-01T00:00:00Z\n".utf8)
        } else {
            host.quarantined = ["/ZZbrew/Cellar/go/1.27.3/libexec/bin/go"]
        }
        let scan = await Self.adapter(host).scan()
        let binary = try #require(scan.roots.first?.binary)
        #expect(binary == ManagedRoot.Binary(
            path: which == "pkg" ? pkg : Self.go, version: "1.27.3",
            trust: which == "pkg" ? .untrusted(nil) : .quarantined))
        let verdicts = await Self.adapter(host).check(scan)
        #expect(host.runs.isEmpty)
        #expect(verdicts.first { $0.item.key == "mvdan.cc/gofumpt" }?.vendorWouldUpgrade == nil)
        let report = await ManagedProvider(
            Self.adapter(host), home: Self.home, proxyEnvironment: { [:] }, processes: { [] }, token: { nil },
            runner: { _, _, _, _, _ in ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: []) }
        ).check()
        let gofumpt = try #require(Self.status(report, "mvdan.cc/gofumpt"))
        #expect(gofumpt.state == .unknown)
        #expect(gofumpt.oneClick == nil)
        #expect(gofumpt.withheld == .unverified)
        #expect(gofumpt.commandToCopy == nil)
        #expect(gofumpt.note?.hasPrefix(binary.path + " is ") == true)
        #expect(gofumpt.note?.hasSuffix(", so nothing of it is run") == true)
        #expect(host.runs.isEmpty)
    }

    /// A `go install` of this package running. Mutation: match any `go install`.
    @Test func aRunningInstallIsBusy() {
        #expect(GoAdapter.busy(package: "mvdan.cc/gofumpt", processes: [
            NpmActivity.Process(pid: 3, arguments: ["go", "install", "mvdan.cc/gofumpt@latest"], executable: nil),
        ]) == "go install mvdan.cc/gofumpt is running (pid 3)")
        #expect(GoAdapter.busy(package: "mvdan.cc/gofumpt", processes: [
            NpmActivity.Process(pid: 4, arguments: ["go", "install", "golang.org/x/tools/gopls@latest"], executable: nil),
        ]) == nil)
    }

    // MARK: notes

    /// GitHub off the path, a subdirectory as the tag prefix, a major suffix
    /// dropped; anything else from proxy.golang.org's `Origin` (its real
    /// answers, 2026-10-27). Mutation: keep `/v2` in the prefix; ignore `Subdir`.
    @Test func theNotesRepositoryIsFound() {
        #expect(GoModule.gitHub(path: "github.com/BurntSushi/toml") == .init(owner: "BurntSushi", repo: "toml", tagPrefix: ""))
        #expect(GoModule.gitHub(path: "github.com/x/y/v2") == .init(owner: "x", repo: "y", tagPrefix: ""))
        #expect(GoModule.gitHub(path: "github.com/aws/aws-sdk-go-v2/service/s3") == .init(
            owner: "aws", repo: "aws-sdk-go-v2", tagPrefix: "service/s3/"))
        #expect(GoModule.gitHub(path: "mvdan.cc/gofumpt") == nil)
        #expect(GoModule.escaped("github.com/BurntSushi/toml") == "github.com/!burnt!sushi/toml")
        #expect(GoModule.origin(Data(#"{"Version":"v0.12.0","Origin":{"VCS":"git","URL":"https://github.com/mvdan/gofumpt","Ref":"refs/tags/v0.12.0"}}"#.utf8))
            == .init(owner: "mvdan", repo: "gofumpt", tagPrefix: ""))
        #expect(GoModule.origin(Data(#"{"Origin":{"URL":"https://github.com/aws/aws-sdk-go-v2","Subdir":"service/s3"}}"#.utf8))
            == .init(owner: "aws", repo: "aws-sdk-go-v2", tagPrefix: "service/s3/"))
        #expect(GoModule.origin(Data(#"{"Origin":{"URL":"https://go.googlesource.com/vuln"}}"#.utf8)) == nil)
    }
}
