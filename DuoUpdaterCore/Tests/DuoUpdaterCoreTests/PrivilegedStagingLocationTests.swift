import Foundation
import Testing
@testable import DuoUpdaterCore

/// Security review 2026-10-25, round 3.
///
/// R1. Root's staging directory was a `mktemp -d` beside the target — in
///     `/Applications`, which is `root:admin` 775 and not sticky. The admin user
///     can rename root's 0700 directory there and make its own at that name
///     (measured on macOS 27.2), and root's `ditto`, `codesign` and `mv` all
///     went by that name. Root now stages under `/private/var/tmp` (sticky), and
///     parks the bundle it displaces there too.
/// R4. For a certificate-signed install, root re-checked its copy against the
///     installed copy's designated requirement only — which every build that
///     signer ever shipped meets. It now also pins the cdhash gate 2 passed.
///
/// No password panel is raised: the elevated route runs through
/// `InPlaceSwap.elevatedShellOverride`, as this user. What that cannot show is
/// the half of R1 that rests on root owning the directory — run as this user,
/// the directory is this user's — so the R1 tests show where the shell stages
/// and that a user acting on the target's folder no longer reaches it.
@Suite struct PrivilegedStagingLocationTests {

    static let team = "ZZTEAM0007"
    static let identifier = "zz.duoupdater.staging"
    static let appName = "ZZStaging.app"

    // MARK: - R1: where root stages

    /// The premise the move rests on, read off this Mac: the staging root is
    /// root's and sticky, and on the same volume as a scratch folder in this
    /// user's temporary directory (the Data volume).
    @Test func theStagingRootIsStickyAndRootOwned() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: InPlaceSwap.privilegedStagingRoot)
        let mode = try #require(attrs[.posixPermissions] as? NSNumber).intValue
        #expect(mode & 0o1000 != 0, "not sticky: \(String(mode, radix: 8))")
        #expect((attrs[.ownerAccountID] as? NSNumber)?.intValue == 0)
        #expect(attrs[.type] as? FileAttributeType == .typeDirectory)
    }

    /// Structure: both shells `mktemp -d` under `/private/var/tmp` with the
    /// target's prefix and nowhere beside the target, and the replaced bundle
    /// is parked inside `$S`. Then both run end to end and leave nothing behind
    /// in either place.
    @Test func thePrivilegedShellsStageUnderVarTmpNotBesideTheTarget() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-vartmp")
        defer { try? fm.removeItem(at: dir) }
        let target = try plainBundle(at: dir.appendingPathComponent(Self.appName), marker: "old")
        let incoming = try plainBundle(at: dir.appendingPathComponent("src/Incoming.app"), marker: "new")
        let gone = dir.appendingPathComponent("ZZGone.app")

        let replace = InPlaceSwap.privilegedReplacementShell(newApp: incoming, target: target)
        let place = InPlaceSwap.privilegedPlacementShell(newApp: incoming, target: gone)
        for (shell, app) in [(replace, target), (place, gone)] {
            let prefix = InPlaceSwap.privilegedStagingPrefix(for: app)
            #expect(shell.contains("/usr/bin/mktemp -d /private/var/tmp/\(prefix)XXXXXX"),
                    "root must stage under /private/var/tmp: \(shell)")
            #expect(!shell.contains("/usr/bin/mktemp -d '\(app.path)"), "staging beside the target: \(shell)")
            #expect(!shell.contains("/usr/bin/mktemp -d '\(dir.path)"), "staging beside the target: \(shell)")
        }
        let parked = "\"$S\"/'\(Self.appName).duoupdater-old'"
        #expect(replace.contains("/bin/mv '\(target.path)' \(parked) && "),
                "the displaced bundle must be parked inside $S: \(replace)")
        #expect(!replace.contains("/bin/mv '\(target.path)' '\(target.path).duoupdater-old'"),
                "the displaced bundle is parked beside the target: \(replace)")

        #expect(try await SelfSignedCodeSigner.shell(replace) == 0)
        #expect(marker(of: target) == "new")
        #expect(try await SelfSignedCodeSigner.shell(place) == 0)
        #expect(marker(of: gone) == "new")
        #expect(try leftoversBeside(in: dir).isEmpty)
        #expect(try leftoversInStagingRoot(for: target).isEmpty)
        #expect(try leftoversInStagingRoot(for: gone).isEmpty)
    }

    /// End to end through the elevated route, with a user who acts on the
    /// target's folder at the worst moment: after root's check passed and
    /// before its `mv`, every staging directory beside the target is renamed
    /// away and one of the user's own is made at its name, holding a build the
    /// gates never saw. That is what the admin user can do to a root 0700
    /// directory in `/Applications` (measured, see the suite comment). The
    /// hook is spliced into the shell in front of `mv <target> <old>`.
    ///
    /// On the beside-target layout the user's build 9 lands; now the user has
    /// nothing to act on.
    @Test func aStagingDirectorySwappedBesideTheTargetDoesNotLand() async throws {
        try await withFixture("swap-beside") { fixture in
            let vendor = fixture.vendor
            try await signed(fixture.target, build: "1", with: vendor)
            let source = fixture.dir.appendingPathComponent("src/\(Self.appName)")
            try await signed(source, build: "2", with: vendor)
            let substitute = fixture.dir.appendingPathComponent("substitute/\(Self.appName)")
            try await signed(substitute, build: "9", with: vendor)
            let check = try await SignatureVerifier.verifyInstallArtifact(
                downloadedApp: source, installedApp: fixture.target)

            let hook = """
            for d in \(shellQuote(fixture.apps.path))/*\(InPlaceSwap.privilegedStagingInfix)*; do \
            [ -d "$d" ] || continue; /bin/mv "$d" "$d.moved" && /bin/mkdir "$d" && \
            /usr/bin/ditto \(shellQuote(substitute.path)) "$d"/\(shellQuote(Self.appName)); done
            """
            let calls = Calls()
            let apps = fixture.apps
            let target = fixture.target
            chmod(apps.path, 0o555)
            try await InPlaceSwap.$elevatedShellOverride.withValue({ shell in
                calls.add(shell)
                chmod(apps.path, 0o755)
                let anchor = "/bin/mv '\(target.path)' "
                guard let at = shell.range(of: anchor) else {
                    throw SelfSignedCodeSigner.Failure(description: "no `mv <target>` in: \(shell)")
                }
                let spliced = shell.replacingCharacters(in: at.lowerBound..<at.lowerBound, with: "{ \(hook); } && ")
                return try await ChildProcess.run("/bin/sh", ["-c", spliced], onCancel: .runToCompletion)
            }) {
                try await InPlaceSwap.replace(newApp: source, over: target, stagedCheck: check)
            }
            #expect(calls.all.count == 1, "the swap must have taken the elevated route")
            #expect(build(of: fixture.target) == "2", "the user's directory must not supply what lands")
            #expect(try leftoversInStagingRoot(for: fixture.target).isEmpty)
        }
    }

    /// The displaced bundle now sits inside the directory the trap removes. When
    /// neither the new bundle nor the old one can be moved into place — the
    /// folder made read-only right after `mv <target> <old>` — the app is
    /// missing and that parked copy is the only one: the trap must keep it and
    /// say where it is, not delete it.
    ///
    /// Mutation: make the trap remove `$S` unconditionally → the copy is gone.
    @Test func theParkedCopyIsKeptWhenItCannotBePutBack() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-keep-old")
        let apps = dir.appendingPathComponent("apps", isDirectory: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        let target = try plainBundle(at: apps.appendingPathComponent(Self.appName), marker: "old")
        let incoming = try plainBundle(at: dir.appendingPathComponent("src/Incoming.app"), marker: "new")
        let prefix = InPlaceSwap.privilegedStagingPrefix(for: target)
        defer {
            chmod(apps.path, 0o755)
            try? fm.removeItem(at: dir)
            for name in (try? leftoversInStagingRoot(for: target)) ?? [] {
                try? fm.removeItem(atPath: InPlaceSwap.privilegedStagingRoot + "/" + name)
            }
        }

        let shell = InPlaceSwap.privilegedReplacementShell(newApp: incoming, target: target)
        let anchor = "/bin/mv '\(target.path)' \"$S\"/'\(Self.appName).duoupdater-old' && "
        let at = try #require(shell.range(of: anchor), "no parking `mv` in: \(shell)")
        let spliced = shell.replacingCharacters(
            in: at.upperBound..<at.upperBound, with: "/bin/chmod 555 \(shellQuote(apps.path)) && ")
        let outcome = try await ChildProcess.run("/bin/sh", ["-c", spliced], onCancel: .runToCompletion)
        let stderr = String(decoding: outcome.standardError, as: UTF8.self)

        #expect(outcome.terminationStatus != 0)
        #expect(!fm.fileExists(atPath: target.path), "premise: the app could not be put back")
        let kept = try leftoversInStagingRoot(for: target)
        #expect(kept.count == 1, "\(kept)")
        let parked = URL(fileURLWithPath: InPlaceSwap.privilegedStagingRoot)
            .appendingPathComponent(kept.first ?? prefix)
            .appendingPathComponent("\(Self.appName).duoupdater-old")
        #expect(marker(of: parked) == "old", "the only copy of the app must survive")
        #expect(stderr.contains("It is at \(parked.path)."), "\(stderr)")
    }

    /// The final `mv` must be a rename. A target whose folder is on another
    /// volume than the staging root is refused before anything is copied, and
    /// the reason is said. `/dev` is a different device and nothing is written
    /// to it: the shell stops at the check.
    @Test func aTargetOnAnotherVolumeIsRefusedBeforeAnythingIsCopied() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-device")
        defer { try? fm.removeItem(at: dir) }
        let incoming = try plainBundle(at: dir.appendingPathComponent("src/Incoming.app"), marker: "new")
        let elsewhere = URL(fileURLWithPath: "/dev/ZZStagingFixture.app")
        let shell = InPlaceSwap.privilegedPlacementShell(newApp: incoming, target: elsewhere)

        let outcome = try await ChildProcess.run("/bin/sh", ["-c", shell], onCancel: .runToCompletion)
        let stderr = String(decoding: outcome.standardError, as: UTF8.self)
        #expect(outcome.terminationStatus != 0)
        #expect(stderr.contains("is not on the same disk as /private/var/tmp"), "\(stderr)")
        #expect(!fm.fileExists(atPath: elsewhere.path))
        #expect(try leftoversInStagingRoot(for: elsewhere).isEmpty)
    }

    // MARK: - R4: another genuine build of the same signer

    /// Gate 2 passes build 3; while the panel is up, the scratch copy is
    /// replaced by build 2 — genuine, signed by the same certificate, so it
    /// meets the installed copy's designated requirement. Root must refuse it.
    ///
    /// Mutation: drop the cdhash clause from `stagedCopyCheck` → build 2 lands.
    @Test func anotherBuildOfTheSameSignerSwappedInAfterTheGatesIsRefusedByRoot() async throws {
        try await withFixture("same-signer") { fixture in
            let vendor = fixture.vendor
            try await signed(fixture.target, build: "1", with: vendor)
            let source = fixture.dir.appendingPathComponent("src/\(Self.appName)")
            try await signed(source, build: "3", with: vendor)
            let older = fixture.dir.appendingPathComponent("older/\(Self.appName)")
            try await signed(older, build: "2", with: vendor)
            let check = try #require(await SignatureVerifier.verifyInstallArtifact(
                downloadedApp: source, installedApp: fixture.target))
            #expect(check.allArchitectures, "a certificate-signed install takes the DR form")
            // The premise: the substitute meets the installed copy's requirement.
            try await SelfSignedCodeSigner.run([
                "/usr/bin/codesign", "--verify", "-R", "=" + check.text, older.path])

            let calls = Calls()
            chmod(fixture.apps.path, 0o555)
            try await InPlaceSwap.$elevatedShellOverride.withValue(
                runAsThisUser(fixture, calls: calls) {
                    try FileManager.default.removeItem(at: source)
                    try FileManager.default.copyItem(at: older, to: source)
                }
            ) {
                await #expect(throws: (any Error).self) {
                    try await InPlaceSwap.replace(newApp: source, over: fixture.target, stagedCheck: check)
                }
            }
            #expect(calls.all.count == 1, "the swap must have taken the elevated route")
            #expect(build(of: fixture.target) == "1", "another build of the signer must not land")
            #expect(try leftoversInStagingRoot(for: fixture.target).isEmpty)

            // Vacuity guard: the build that was gated lands.
            try FileManager.default.removeItem(at: source)
            try await signed(source, build: "3", with: vendor)
            let honest = try #require(await SignatureVerifier.verifyInstallArtifact(
                downloadedApp: source, installedApp: fixture.target))
            chmod(fixture.apps.path, 0o555)
            try await InPlaceSwap.$elevatedShellOverride.withValue(runAsThisUser(fixture, calls: calls)) {
                try await InPlaceSwap.replace(newApp: source, over: fixture.target, stagedCheck: honest)
            }
            #expect(build(of: fixture.target) == "3")
        }
    }

    /// A restore's requirement is unchanged: no cdhash pin (another PR).
    @Test func aRestoreRequirementCarriesNoCdhashPin() {
        let restore = InPlaceSwap.StagedCopyRequirement(
            text: "identifier \"zz\"", allArchitectures: true, validatesResources: false)
        let clause = InPlaceSwap.stagedCopyCheck("\"$S\"/'X.app'", restore)
        #expect(!clause.contains("cdhash"), "\(clause)")
    }

    // MARK: - Helpers

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var shells: [String] = []
        func add(_ shell: String) { lock.withLock { shells.append(shell) } }
        var all: [String] { lock.withLock { shells } }
    }

    struct Fixture {
        let dir: URL
        let apps: URL
        let target: URL
        let vendor: SelfSignedCodeSigner.Identity
    }

    /// `apps/` holds the target and is made read-only by each test, so `replace`
    /// takes the elevated route.
    private func withFixture(_ label: String, _ body: (Fixture) async throws -> Void) async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-\(label)")
        let apps = dir.appendingPathComponent("apps", isDirectory: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        defer {
            chmod(apps.path, 0o755)
            try? fm.removeItem(at: dir)
        }
        let vendor = try await SelfSignedCodeSigner.mint(team: Self.team, label: "vendor", in: dir)
        try await body(Fixture(
            dir: dir, apps: apps, target: apps.appendingPathComponent(Self.appName), vendor: vendor))
    }

    /// Runs the shell as this user, the parent made writable again first;
    /// `beforeRunning` is the window between the Swift gates and root's copy.
    private func runAsThisUser(
        _ fixture: Fixture, calls: Calls, beforeRunning: @escaping @Sendable () throws -> Void = {}
    ) -> @Sendable (String) async throws -> ChildProcess.Outcome {
        let apps = fixture.apps
        return { shell in
            calls.add(shell)
            chmod(apps.path, 0o755)
            try beforeRunning()
            return try await ChildProcess.run("/bin/sh", ["-c", shell], onCancel: .runToCompletion)
        }
    }

    @discardableResult
    private func signed(_ url: URL, build: String, with identity: SelfSignedCodeSigner.Identity) async throws -> URL {
        try await SelfSignedCodeSigner.makeSignedApp(
            at: url, identifier: Self.identifier, build: build, team: Self.team, with: identity)
    }

    private func plainBundle(at url: URL, marker: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent("Contents/marker"))
        return url
    }

    private func marker(of url: URL) -> String? {
        (try? Data(contentsOf: url.appendingPathComponent("Contents/marker")))
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private func build(of app: URL) -> String? {
        SignatureVerifier.infoPlist(of: app)["CFBundleVersion"] as? String
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func leftoversBeside(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(InPlaceSwap.privilegedStagingInfix) || $0.hasSuffix(".duoupdater-old") }
    }

    private func leftoversInStagingRoot(for target: URL) throws -> [String] {
        let prefix = InPlaceSwap.privilegedStagingPrefix(for: target)
        return try FileManager.default.contentsOfDirectory(atPath: InPlaceSwap.privilegedStagingRoot)
            .filter { $0.hasPrefix(prefix) }
    }
}
