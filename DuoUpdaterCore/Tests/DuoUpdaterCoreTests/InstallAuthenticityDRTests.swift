import CryptoKit
import Foundation
import Security
import Testing
@testable import DuoUpdaterCore

/// Security review 2026-10-25, items 1 and 6.
///
/// 1. A Team ID is only what the leaf certificate's OU says, and gate 2 checks a
///    seal against no requirement — so a self-signed certificate naming the
///    vendor's Team passed gates 2–4 on the `.developerID` route. The download
///    must now satisfy the installed copy's designated requirement.
/// 2. The privileged swap staged into a fixed sibling (`<App>.app.duoupdater-new`)
///    and root re-read the source from a user-writable directory after the Swift
///    gates had passed. It now stages into a root `mktemp -d` directory and
///    checks the staged copy again in the same shell.
///
/// Forged signatures are made without a keychain: `openssl` mints a self-signed
/// certificate, `SecPKCS12Import` with `kSecImportToMemoryOnly` holds the
/// identity in memory, and `SecCodeSigner` (the SPI `codesign` itself uses)
/// signs with it. Nothing is added to any keychain or search list, and nothing
/// here raises a dialog.
@Suite struct InstallAuthenticityDRTests {

    // MARK: - Item 1: the `.developerID` route

    /// The attack itself: the real Developer-ID-style app installed, and a
    /// download that claims its Team and its identifier under a self-signed
    /// certificate. Gates 2–4 all pass on it; the designated requirement does not.
    @Test func aSelfSignedForgeryOfTheTeamIsRefusedOnTheDeveloperIDRoute() async throws {
        let dir = try DigestOnlyInstallTests.scratch("dr-forgery")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installed = try #require(await DigestOnlyInstallTests.teamSignedApp())
        let (team, identifier) = try await offCooperativePool {
            (try SignatureVerifier.teamIdentifier(at: installed),
             try SignatureVerifier.signingIdentifier(at: installed))
        }
        let forgedTeam = try #require(team)
        let forgedID = try #require(identifier)
        let forger = try await SelfSignedCodeSigner.mint(team: forgedTeam, label: "forger", in: dir)
        let forged = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("forged/App.app"), identifier: forgedID,
            team: forgedTeam, with: forger)

        // The premise, so a pass below cannot come from an earlier gate refusing:
        // the forgery really does carry the installed copy's Team and identifier,
        // and its seal verifies.
        try await offCooperativePool {
            try SignatureVerifier.verifyCodeSignature(appAt: forged)
            try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: installed, downloadedApp: forged)
            try SignatureVerifier.verifyBundleIdentifierMatch(installedApp: installed, downloadedApp: forged)
        }

        await #expect {
            try await SignatureVerifier.verifyInstallArtifact(
                downloadedApp: forged, installedApp: installed)
        } throws: {
            if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
            return false
        }

        // Vacuity guard: an unmodified copy of the real app still passes every gate.
        let genuine = dir.appendingPathComponent("genuine/\(installed.lastPathComponent)")
        try FileManager.default.createDirectory(
            at: genuine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await SelfSignedCodeSigner.run(["/usr/bin/ditto", installed.path, genuine.path])
        try await SignatureVerifier.verifyInstallArtifact(downloadedApp: genuine, installedApp: installed)
    }

    /// The same forgery on the two ad-hoc routes. A digest-only or MyGo rule
    /// whose app is installed as a Team-signed copy takes `.teamGate`, which
    /// compared Team ID strings and identifiers only — so the self-signed copy
    /// claiming that Team passed there although `.developerID` refused it.
    /// Mutation: drop `verifySignedLikeInstalledCopy` from
    /// `verifyDigestOnlyIdentity`'s `.teamGate` → both routes accept, red.
    @Test func aSelfSignedForgeryOfTheTeamIsRefusedOnTheDigestAndMyGoRoutes() async throws {
        let dir = try DigestOnlyInstallTests.scratch("dr-forgery-digest")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (installed, forged) = try await Self.teamCopyAndForgery(in: dir)
        let bundleID = try #require(
            SignatureVerifier.infoPlist(of: installed)["CFBundleIdentifier"] as? String)
        let version = try #require(
            SignatureVerifier.infoPlist(of: installed)["CFBundleShortVersionString"] as? String)
        let routes: [(String, SignatureVerifier.ArtifactTrust)] = [
            ("publishedDigest", .publishedDigest(
                try DigestOnlyInstallTests.proof(in: dir), bundleID: bundleID, version: version)),
            ("myGoSignature", .myGoSignature(
                try Self.myGoProof(), bundleID: bundleID, version: version)),
        ]

        let genuine = dir.appendingPathComponent("genuine/\(installed.lastPathComponent)")
        try FileManager.default.createDirectory(
            at: genuine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await SelfSignedCodeSigner.run(["/usr/bin/ditto", installed.path, genuine.path])

        for (name, trust) in routes {
            await #expect("\(name): the forgery must be refused") {
                try await SignatureVerifier.verifyInstallArtifact(
                    downloadedApp: forged, installedApp: installed, trust: trust)
            } throws: {
                if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
                return false
            }
            // Vacuity guard: an unmodified copy of the real app passes the same route.
            try await SignatureVerifier.verifyInstallArtifact(
                downloadedApp: genuine, installedApp: installed, trust: trust)
        }
    }

    /// The Sparkle key-only route's `.teamGate`, kept the same as the others. An
    /// installed Team copy normally goes `.developerID` before this route is
    /// chosen, so this is the gate called directly. Mutation: drop
    /// `verifySignedLikeInstalledCopy` from `verifySparkleKeyOnlyIdentity`'s
    /// `.teamGate` → the forgery passes, red.
    @Test func aSelfSignedForgeryOfTheTeamIsRefusedOnTheSparkleKeyOnlyTeamGate() async throws {
        let dir = try DigestOnlyInstallTests.scratch("dr-forgery-sparkle")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (installed, forged) = try await Self.teamCopyAndForgery(in: dir)
        let genuine = dir.appendingPathComponent("genuine/\(installed.lastPathComponent)")
        try FileManager.default.createDirectory(
            at: genuine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await SelfSignedCodeSigner.run(["/usr/bin/ditto", installed.path, genuine.path])

        try await offCooperativePool {
            #expect {
                try SignatureVerifier.verifySparkleKeyOnlyIdentity(
                    installedApp: installed, downloadedApp: forged)
            } throws: {
                if case SignatureVerifier.VerifyError.designatedRequirementNotSatisfied = $0 { return true }
                return false
            }
            // Vacuity guard.
            try SignatureVerifier.verifySparkleKeyOnlyIdentity(
                installedApp: installed, downloadedApp: genuine)
        }
    }

    /// The Team-signed app from Xcode and a self-signed forgery claiming its Team
    /// and signed identifier, with the premise checked: the forgery's seal
    /// verifies and gates 3 and 4 pass on it, so a refusal can only come from
    /// the requirement.
    static func teamCopyAndForgery(in dir: URL) async throws -> (installed: URL, forged: URL) {
        let installed = try #require(await DigestOnlyInstallTests.teamSignedApp())
        let (team, identifier) = try await offCooperativePool {
            (try SignatureVerifier.teamIdentifier(at: installed),
             try SignatureVerifier.signingIdentifier(at: installed))
        }
        let forgedTeam = try #require(team)
        let forgedID = try #require(identifier)
        let forger = try await SelfSignedCodeSigner.mint(team: forgedTeam, label: "forger", in: dir)
        let forged = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("forged/App.app"), identifier: forgedID,
            team: forgedTeam, with: forger)
        try await offCooperativePool {
            try SignatureVerifier.verifyCodeSignature(appAt: forged)
            try SignatureVerifier.verifyTeamIdentifierMatch(installedApp: installed, downloadedApp: forged)
            try SignatureVerifier.verifyBundleIdentifierMatch(installedApp: installed, downloadedApp: forged)
        }
        return (installed, forged)
    }

    /// A real MyGo proof — the only way to get one is a signature that verifies.
    static func myGoProof() throws -> SignatureVerifier.VerifiedMyGoSignature {
        let key = Curve25519.Signing.PrivateKey()
        let file = Data("mygo".utf8)
        let signature = try key.signature(for: Data(SHA256.hash(data: file)))
        return try SignatureVerifier.verifyMyGoSignature(
            fileData: file, signatureBase64: signature.base64EncodedString(),
            publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString())
    }

    // MARK: - Item 6: the privileged shells

    /// Structure first, because an unprivileged test cannot reproduce the race:
    /// the leading `rm` would delete a planted symlink before `ditto` reached it.
    /// So: no fixed sibling anywhere, a `mktemp -d` directory, and `ditto` writes
    /// into it. Then both shells run end to end and leave no staging behind.
    @Test func thePrivilegedShellsStageInAFreshDirectoryNotAFixedSibling() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-shape")
        defer { try? fm.removeItem(at: dir) }
        let target = try plainBundle(at: dir.appendingPathComponent("ZZFixture.app"), marker: "old")
        let incoming = try plainBundle(at: dir.appendingPathComponent("src/Incoming.app"), marker: "new")
        let gone = dir.appendingPathComponent("ZZGone.app")

        let replace = await offCooperativePool {
            InPlaceSwap.privilegedReplacementShell(newApp: incoming, target: target)
        }
        let place = await offCooperativePool {
            InPlaceSwap.privilegedPlacementShell(newApp: incoming, target: gone)
        }
        for shell in [replace, place] {
            #expect(!shell.contains(".duoupdater-new"), "fixed sibling staging path in: \(shell)")
            #expect(shell.contains("/usr/bin/mktemp -d "), "no mktemp -d in: \(shell)")
            let ditto = try #require(shell.range(of: "/usr/bin/ditto '\(incoming.path)' "))
            #expect(shell[ditto.upperBound...].hasPrefix("\"$S\"/"),
                    "ditto must write into the mktemp directory: \(shell)")
        }

        #expect(try await SelfSignedCodeSigner.shell(replace) == 0)
        #expect(marker(of: target) == "new")
        #expect(try await SelfSignedCodeSigner.shell(place) == 0)
        #expect(marker(of: gone) == "new")
        // Refused (something is there now), and still nothing left behind.
        #expect(try await SelfSignedCodeSigner.shell(place) != 0)
        #expect(try stagingLeftovers(in: dir).isEmpty)
    }

    /// The shell re-checks the copy root made against the installed copy's
    /// designated requirement. Installed and gated download are signed with one
    /// certificate; after the gate, the source is swapped for a build signed with
    /// another certificate claiming the same Team. The swap must not land.
    @Test func aStagedCopySwappedAfterTheGateFailsTheInstalledRequirementInTheShell() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-dr")
        defer { try? fm.removeItem(at: dir) }
        let team = "ZZTEAM0001", identifier = "zz.duoupdater.fixture"
        let vendor = try await SelfSignedCodeSigner.mint(team: team, label: "vendor", in: dir)
        let other = try await SelfSignedCodeSigner.mint(team: team, label: "other", in: dir)
        let target = try await SelfSignedCodeSigner.makeSignedApp(
            at: dir.appendingPathComponent("ZZFixture.app"), identifier: identifier, build: "1",
            team: team, with: vendor)
        let source = dir.appendingPathComponent("src/Incoming.app")

        // Untampered: the check passes and the swap lands — proves the clause
        // itself is well-formed, not merely failing.
        try await SelfSignedCodeSigner.makeSignedApp(
            at: source, identifier: identifier, build: "2", team: team, with: vendor)
        let honestCheck = try #require(
            await SignatureVerifier.verifyInstallArtifact(downloadedApp: source, installedApp: target))
        #expect(honestCheck.allArchitectures, "a certificate-signed install takes the DR form")
        let honest = InPlaceSwap.privilegedReplacementShell(
            newApp: source, target: target, requirement: honestCheck)
        #expect(try await SelfSignedCodeSigner.shell(honest) == 0)
        #expect(build(of: target) == "2")

        // Gated build 3, then swapped for a build 4 signed by someone else.
        try fm.removeItem(at: source)
        try await SelfSignedCodeSigner.makeSignedApp(
            at: source, identifier: identifier, build: "3", team: team, with: vendor)
        let check = try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: source, installedApp: target)
        try fm.removeItem(at: source)
        try await SelfSignedCodeSigner.makeSignedApp(
            at: source, identifier: identifier, build: "4", team: team, with: other)
        let shell = InPlaceSwap.privilegedReplacementShell(
            newApp: source, target: target, requirement: check)

        #expect(try await SelfSignedCodeSigner.shell(shell) != 0)
        #expect(build(of: target) == "2")
        #expect(try stagingLeftovers(in: dir).isEmpty)
    }

    /// An ad-hoc install has no requirement another build can meet (its own
    /// cdhash), so the shell checks the cdhash gate 2 read: a different —
    /// validly signed — ad-hoc build put in its place after the gate is refused.
    @Test func aStagedAdHocCopySwappedAfterTheGateFailsItsCdhashInTheShell() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-cdhash")
        defer { try? fm.removeItem(at: dir) }
        let target = try await DigestOnlyInstallTests.makeApp(
            at: dir.appendingPathComponent("ZZFixture.app"), build: "1", signing: .sealed(identifier: nil))
        let source = dir.appendingPathComponent("src/Incoming.app")
        try await DigestOnlyInstallTests.makeApp(at: source, build: "2", signing: .sealed(identifier: nil))
        let check = try await Self.digestGate(source, over: target, in: dir)
        try fm.removeItem(at: source)
        try await DigestOnlyInstallTests.makeApp(at: source, build: "9", signing: .sealed(identifier: nil))
        let shell = InPlaceSwap.privilegedReplacementShell(newApp: source, target: target, requirement: check)

        #expect(try await SelfSignedCodeSigner.shell(shell) != 0)
        #expect(build(of: target) == "1")
        #expect(try stagingLeftovers(in: dir).isEmpty)

        // Gated as it now is, the build that IS there lands.
        let honestCheck = try await Self.digestGate(source, over: target, in: dir)
        let honest = InPlaceSwap.privilegedReplacementShell(
            newApp: source, target: target, requirement: honestCheck)
        #expect(try await SelfSignedCodeSigner.shell(honest) == 0)
        #expect(build(of: target) == "9")
    }

    /// The digest-only route's gate over an ad-hoc fixture, returning what the
    /// swap re-checks. `makeApp`'s defaults are the rule's bundle id and version.
    static func digestGate(
        _ source: URL, over target: URL, in dir: URL
    ) async throws -> InPlaceSwap.StagedCopyRequirement? {
        try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: source, installedApp: target,
            trust: .publishedDigest(try DigestOnlyInstallTests.proof(in: dir),
                                    bundleID: DigestOnlyInstallTests.bundleID, version: "2.0.0"))
    }

    /// The launch sweep knows the new staging name. Root's are 0700 and stay
    /// for the next privileged shell; one this user can remove is removed.
    @Test func theLaunchSweepClearsAStagingDirectoryItCanRemove() async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("stage-sweep")
        defer { try? fm.removeItem(at: dir) }
        let leftover = dir.appendingPathComponent("ZZFixture.app.duoupdater-stage.AbC123")
        try fm.createDirectory(
            at: leftover.appendingPathComponent("ZZFixture.app/Contents"), withIntermediateDirectories: true)
        let swept = await InPlaceSwap.recoverInterruptedSwaps(
            in: dir, lock: ProcessInstallLock(url: dir.appendingPathComponent("install.lock")))
        #expect(swept)
        #expect(!fm.fileExists(atPath: leftover.path))
    }

    // MARK: - Helpers

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

    private func stagingLeftovers(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".duoupdater-stage.") || $0.hasSuffix(".duoupdater-new") }
    }
}

/// Keychain-free code signing with a self-signed certificate, for forging a
/// Team ID in tests. See `InstallAuthenticityDRTests`.
enum SelfSignedCodeSigner {

    struct Identity: @unchecked Sendable { let ref: SecIdentity }

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// A self-signed code-signing certificate whose subject OU — the field a
    /// Team ID is read from — is `team`, held only in memory.
    static func mint(team: String, label: String, in dir: URL) async throws -> Identity {
        let key = dir.appendingPathComponent("\(label).key.pem")
        let cert = dir.appendingPathComponent("\(label).cert.pem")
        let p12 = dir.appendingPathComponent("\(label).p12")
        try await run([
            "/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
            "-keyout", key.path, "-out", cert.path,
            "-subj", "/CN=Developer ID Application: Forged \(label) (\(team))/OU=\(team)/O=Forged/C=US",
            "-addext", "keyUsage=critical,digitalSignature",
            "-addext", "extendedKeyUsage=critical,codeSigning",
        ])
        try await run([
            "/usr/bin/openssl", "pkcs12", "-export", "-inkey", key.path, "-in", cert.path,
            "-out", p12.path, "-passout", "pass:duo",
        ])
        let data = try Data(contentsOf: p12)
        return try await offCooperativePool {
            var items: CFArray?
            let options: [String: Any] = [
                kSecImportExportPassphrase as String: "duo",
                kSecImportToMemoryOnly as String: true,
            ]
            let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
            guard status == errSecSuccess,
                  let first = (items as? [[String: Any]])?.first,
                  let identity = first[kSecImportItemIdentity as String]
            else { throw Failure(description: "SecPKCS12Import: \(status)") }
            return Identity(ref: identity as! SecIdentity)
        }
    }

    /// `DigestOnlyInstallTests.makeApp`'s unsigned bundle, signed by `identity`
    /// as `identifier` with `team` in the CodeDirectory.
    @discardableResult
    static func makeSignedApp(
        at url: URL, identifier: String, build: String = "2", team: String, with identity: Identity
    ) async throws -> URL {
        try await DigestOnlyInstallTests.makeApp(
            at: url, bundleID: identifier, build: build, signing: .unsigned)
        try await sign(url, identifier: identifier, team: team, with: identity)
        return url
    }

    static func sign(_ app: URL, identifier: String, team: String, with identity: Identity) async throws {
        try await offCooperativePool {
            typealias Create = @convention(c) (
                CFDictionary, UInt32, UnsafeMutablePointer<Unmanaged<AnyObject>?>) -> OSStatus
            typealias Add = @convention(c) (
                AnyObject, SecStaticCode, UInt32, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> OSStatus
            guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
                  let createSymbol = dlsym(security, "SecCodeSignerCreate"),
                  let addSymbol = dlsym(security, "SecCodeSignerAddSignatureWithErrors")
            else { throw Failure(description: "SecCodeSigner is not available") }
            func key(_ name: String) throws -> CFString {
                guard let symbol = dlsym(security, name) else { throw Failure(description: "\(name) missing") }
                return symbol.assumingMemoryBound(to: CFString.self).pointee
            }
            let parameters: [CFString: Any] = [
                try key("kSecCodeSignerIdentity"): identity.ref,
                try key("kSecCodeSignerIdentifier"): identifier,
                try key("kSecCodeSignerTeamIdentifier"): team,
            ]
            var signer: Unmanaged<AnyObject>?
            let made = unsafeBitCast(createSymbol, to: Create.self)(parameters as CFDictionary, 0, &signer)
            guard made == errSecSuccess, let signer = signer?.takeRetainedValue() else {
                throw Failure(description: "SecCodeSignerCreate: \(made)")
            }
            var code: SecStaticCode?
            let opened = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
            guard opened == errSecSuccess, let code else {
                throw Failure(description: "SecStaticCodeCreateWithPath: \(opened)")
            }
            var error: Unmanaged<CFError>?
            let added = unsafeBitCast(addSymbol, to: Add.self)(signer, code, 0, &error)
            guard added == errSecSuccess else {
                throw Failure(description: "SecCodeSignerAddSignature: \(added) \(String(describing: error?.takeRetainedValue()))")
            }
        }
    }

    static func run(_ argv: [String]) async throws {
        let outcome = try await ChildProcess.run(
            argv[0], Array(argv.dropFirst()), standardOutput: .discard, onCancel: .runToCompletion)
        guard outcome.terminationStatus == 0 else {
            throw Failure(description: "\(argv[0]): " + String(decoding: outcome.standardError, as: UTF8.self))
        }
    }

    /// A privileged shell, run as this user — the same `sh -c` `do shell script` uses.
    static func shell(_ script: String) async throws -> Int32 {
        try await ChildProcess.run("/bin/sh", ["-c", script], onCancel: .runToCompletion)
            .terminationStatus
    }
}
