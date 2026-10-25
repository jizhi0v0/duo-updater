import Foundation
import CryptoKit
import Security

/// The gates a downloaded update must pass before we will install it. Any
/// failure aborts the install.
///
/// Gates 1–4 are about trust (EdDSA signature, code signature, Team ID, bundle
/// ID); gates 5 and 6 are about liveness — whether the bundle can launch on this
/// Mac at all, by architecture and by the OS version it declares it needs.
/// Callers pick the gates that apply to their route via `verifyInstallArtifact`
/// below, the single shared entry point both installers call: the Sparkle
/// installer runs it after its own EdDSA gate (1), the vendor installer runs it
/// as its whole gate sequence (no feed signature to check).
///
/// Gate 5b (`verifyNoArchitectureDowngrade`) is a NARROWER liveness check than 5
/// and 6: not "can this Mac run the download" but "does the download run worse
/// than what's already installed" (arm64 → x86_64-only, still launchable under
/// Rosetta, but never natively again). `verifyInstallArtifact` calls it
/// immediately AFTER gate 5, never before — a package that is both unrunnable
/// and a downgrade must fail with gate 5's "cannot launch" message (the more
/// severe, still-true problem), not gate 5b's "this would run translated" (which
/// implies it launches). Like gate 5, it never sees the pkg route: `newApp`
/// there is handed straight to Installer.app, so there is no bundle to read the
/// Mach-O slices out of. See issue #196. Gate 6 is different — it needs only a
/// plist, which `PackageInstaller` reads out of the payload, so that route does
/// run it (#639). `PackageInstaller`'s own header carries the one table of which
/// gates that route runs; do not restate the list here.
///
/// Gate 7 (`verifyNoBundleVersionDowngrade`) is Sparkle's own downgrade check,
/// run by `SparkleInstaller` alone, after `verifyInstallArtifact`.
public enum SignatureVerifier {

    public enum VerifyError: LocalizedError {
        case edSignatureMissing
        case edSignatureInvalid
        /// A MyGo signature (`verifyMyGoSignature`) is absent or does not verify.
        /// Apart from the two above because the key is not the app's: it is the
        /// vendor's MyGo update key, stated in DuoUpdater's recipe for the app.
        case myGoSignatureMissing
        case myGoSignatureInvalid
        case codeSignatureInvalid(OSStatus)
        case noTeamIdentifier(which: String)
        case teamIdentifierMismatch(installed: String, downloaded: String)
        case noBundleIdentifier(which: String)
        case bundleIdentifierMismatch(installed: String, downloaded: String)
        case unrunnableArchitecture(built: String, host: String)
        case architectureDowngrade(installed: String, downloaded: String)
        case unsupportedSystemVersion(required: String, host: String)
        /// Digest-only route: GitHub published no usable `digest` for the asset.
        case publishedDigestMissing
        /// Digest-only route: the downloaded bytes are not the published asset.
        case publishedDigestMismatch
        /// Digest-only route: the installed copy has no Team ID but the download
        /// has one. A Team ID cannot be pinned to an install that never had one,
        /// so this refuses exactly as gate 3 would — said in words a row can carry.
        case teamIdentifierAppeared(downloaded: String)
        /// Digest-only route: the download is signed, has no Team ID, and is not
        /// ad-hoc — a shape no rule was checked against.
        case notAdHocSigned
        /// Digest-only route: `CFBundleIdentifier` (or the signed identifier) is
        /// not the app this rule is for.
        case infoPlistIdentifierMismatch(expected: String, installed: String, downloaded: String)
        /// Digest-only route: the download's `CFBundleShortVersionString` is not
        /// the release the digest was published for.
        case infoPlistVersionMismatch(expected: String, downloaded: String)
        /// Sparkle route, gate 7: the download's `CFBundleVersion` is older than
        /// the installed copy's.
        case bundleVersionDowngrade(installed: String, downloaded: String)
        /// Sparkle route, gate 7: the download has no `CFBundleVersion` to compare.
        case bundleVersionMissing
        /// Sparkle route, installed copy without a Team ID: it carries no
        /// `SUPublicEDKey` either, so nothing ties a download to it.
        case noTeamIdentifierOrUpdateKey
        /// Sparkle route, installed copy without a Team ID: the download is signed
        /// a different way than the installed copy — ad-hoc against a certificate,
        /// or the other way round. Signing never changes kind on this route.
        case signingKindChanged
        /// Sparkle route, self-signed installed copy: the download does not
        /// satisfy the installed copy's designated requirement — it was not signed
        /// with the same certificate.
        case designatedRequirementNotSatisfied(OSStatus)
        /// Sparkle route, installed copy without a Team ID: the download carries
        /// no `SUPublicEDKey`. Installed, it would have no Team ID and no key, so
        /// this route could not update it again, and neither could an ad-hoc
        /// copy's own Sparkle (a copy signed with its own certificate could still
        /// update through Sparkle's code-signing check).
        case updateKeyRemoved

        public var errorDescription: String? {
            switch self {
            case .edSignatureMissing:
                return "The update feed provided no EdDSA signature."
            case .edSignatureInvalid:
                return "The download's EdDSA signature did not match the app's public key."
            // Localized, unlike the Sparkle pair above: these two are new copy,
            // and the reason a user reads them is that one-click stopped. The
            // first clause carries the meaning, because the popover shows one
            // line of it (`MenuContentView`), the rest on hover.
            case .myGoSignatureMissing:
                return String(localized: "The update feed gave no signature for this download, but the vendor signs this app’s updates. Refusing to install it unverified.")
            case .myGoSignatureInvalid:
                return String(localized: "The download’s signature doesn’t match the app’s update key. The file may be damaged or replaced, or the vendor may have changed its key. Refusing to install.")
            case .codeSignatureInvalid(let status):
                return "The downloaded app's code signature is invalid (OSStatus \(status))."
            case .noTeamIdentifier(let which):
                return "Could not read a Team Identifier from the \(which) app."
            case .teamIdentifierMismatch(let installed, let downloaded):
                return "Team Identifier mismatch: installed “\(installed)” vs downloaded “\(downloaded)”. Refusing to install."
            case .noBundleIdentifier(let which):
                return "Could not read a signed bundle identifier from the \(which) app."
            case .bundleIdentifierMismatch(let installed, let downloaded):
                return "Bundle identifier mismatch: installed “\(installed)” vs downloaded “\(downloaded)”. Refusing to install."
            case .unrunnableArchitecture(let built, let host):
                return "The download is built for \(built) and this Mac runs \(host). Refusing to install a build it cannot launch."
            case .architectureDowngrade(let installed, let downloaded):
                return "The installed app runs natively (\(installed)) but this download only has \(downloaded). The download would still launch — under translation, from here on — so this is a downgrade, not an unrunnable build. Refusing to install it."
            case .unsupportedSystemVersion(let required, let host):
                return "The download requires macOS \(required) and this Mac runs macOS \(host). Refusing to install a build it cannot launch."
            case .publishedDigestMissing:
                return String(localized: "GitHub publishes no file hash for this release, so an app without a developer signature can’t be updated in one click.")
            case .publishedDigestMismatch:
                return String(localized: "The download doesn’t match the file hash GitHub publishes for it — it may be corrupt or replaced. Nothing was changed.")
            case .teamIdentifierAppeared(let downloaded):
                return String(localized: "The installed copy has no developer signature, but this version is signed by a developer (Team \(downloaded)). DuoUpdater can’t confirm they’re the same app, so it won’t replace it — install this version by hand once.")
            case .notAdHocSigned:
                return "The downloaded app has neither a Team Identifier nor an ad-hoc signature. Refusing to install it."
            case .infoPlistIdentifierMismatch(let expected, let installed, let downloaded):
                return "Bundle identifier mismatch: expected “\(expected)”, installed “\(installed)”, downloaded “\(downloaded)”. Refusing to install."
            case .infoPlistVersionMismatch(let expected, let downloaded):
                return "The download says it is version “\(downloaded)”, not the “\(expected)” it was published as. Refusing to install."
            case .bundleVersionDowngrade(let installed, let downloaded):
                return String(localized: "The download is an older build (\(downloaded)) than the installed one (\(installed)), though the update feed offered it as newer. Refusing to install it.")
            case .bundleVersionMissing:
                return String(localized: "The download has no build number, so DuoUpdater can’t confirm it isn’t older than the installed copy. Refusing to install it.")
            case .noTeamIdentifierOrUpdateKey:
                return String(localized: "The installed copy has neither a developer signature nor an update signing key, so DuoUpdater can’t confirm the download comes from the same developer. Refusing to install it.")
            case .signingKindChanged:
                return String(localized: "The download is signed differently from the installed copy, so DuoUpdater can’t confirm they’re the same app. Install this version by hand once.")
            case .designatedRequirementNotSatisfied:
                return String(localized: "The download isn’t signed with the same certificate as the installed copy. Refusing to install it.")
            case .updateKeyRemoved:
                return String(localized: "This version no longer carries an update signing key, so once installed DuoUpdater couldn’t check its future updates. Refusing to install it.")
            }
        }
    }

    /// Proof that `verifyPublishedDigest` passed. Only that function can make one,
    /// so the digest-only gates below cannot be reached without the hash check
    /// having run first.
    public struct VerifiedDigest: Sendable {
        fileprivate init() {}
    }

    /// Proof that `verifyMyGoSignature` passed. Only that function can make one,
    /// so the MyGo ad-hoc route (`InstallTrust.myGoSignatureOnly`) cannot reach
    /// its identity gates without the signature having been checked first.
    public struct VerifiedMyGoSignature: Sendable {
        fileprivate init() {}
    }

    /// Proof that `verifySparkleSignature` passed: the file's EdDSA signature
    /// verified against the `SUPublicEDKey` read from the INSTALLED copy on disk.
    /// Only that function can make one, so the no-Team-ID Sparkle route
    /// (`ArtifactTrust.sparkleSignature`) cannot reach its identity gate on any
    /// other key — in particular not on a key that came out of the download,
    /// which is what `isEdKeyRotation` verifies against.
    public struct VerifiedSparkleSignature: Sendable {
        fileprivate init() {}
    }

    /// Which identity gates a swap runs. `.developerID` is gates 3 and 4 as they
    /// have always been. `.publishedDigest` and `.myGoSignature` are the two
    /// ad-hoc routes, which differ only in their proof of origin and share the
    /// identity gates — see `verifyDigestOnlyIdentity`. `.sparkleSignature` is
    /// the Sparkle route for an installed copy without a Team ID — see
    /// `verifySparkleKeyOnlyIdentity`.
    enum ArtifactTrust: Sendable {
        case developerID
        case publishedDigest(VerifiedDigest, bundleID: String, version: String)
        case myGoSignature(VerifiedMyGoSignature, bundleID: String, version: String)
        case sparkleSignature(VerifiedSparkleSignature)
    }

    /// The digest-only route's whole proof of origin: the SHA-256 of `file` — the
    /// exact archive that is then unpacked — equals the `digest` GitHub's API
    /// published for that asset. Blocking file read; callers stay off the pool.
    static func verifyPublishedDigest(of file: URL, expected: String?) throws -> VerifiedDigest {
        guard let expected, !expected.isEmpty else { throw VerifyError.publishedDigestMissing }
        let actual = try BundleArchive.sha256(of: file)
        guard CLIToolTrust.matches(actual, published: expected) else {
            throw VerifyError.publishedDigestMismatch
        }
        return VerifiedDigest()
    }

    /// Shared app-bundle gates for Sparkle and vendor installs, after extraction
    /// or delta reconstruction and before the bundle swap. Archive signatures,
    /// checksums and vendor installer-stub validation stay with their callers;
    /// this entry point does not validate pkg installs.
    ///
    /// Keep the entire sequence in one hop: Security calls can block a narrow
    /// cooperative pool (#351). The first failure determines the reported error.
    ///
    /// `host`, `canRunIntel` and `osVersion` are defaulted to exactly what gates
    /// 5, 5b and 6 default to on their own (`HostArch.current`,
    /// `HostArch.canRunIntelBuilds`, `HostOS.numericVersion()`) — both
    /// installers call this with no extra arguments, so production behavior is
    /// unchanged. The parameters exist so a test can pin the gate-5/5b ordering
    /// without needing a real non-arm64 or Rosetta-less machine to do it on.
    ///
    /// Returns what a privileged swap must re-check its staged copy against
    /// (`InPlaceSwap.stagedCopyRequirement`), fixed here, at the gate: callers
    /// hand it to `InPlaceSwap.replace`. The bundle stays in a user-writable
    /// scratch directory until root copies it, so anything read off it later
    /// could describe a substitute.
    @discardableResult
    static func verifyInstallArtifact(
        downloadedApp: URL,
        installedApp: URL,
        host: HostArch = .current,
        canRunIntel: Bool = HostArch.canRunIntelBuilds,
        osVersion: String = HostOS.numericVersion(),
        trust: ArtifactTrust = .developerID
    ) async throws -> InPlaceSwap.StagedCopyRequirement? {
        // A cancel that landed while the bundle was being produced stops here,
        // before the gates. Every caller is before its install's commit point, so
        // the swap would refuse it anyway — but only after these checks, which
        // cannot be interrupted once started: ~2 s for Arc (`codesign --verify
        // --deep --strict` as a proxy, measured 2026-10-19). A patch or a DMG
        // mount that a cancel cannot cut runs to its end first, and then this
        // is the next place the cancel is seen.
        try Task.checkCancellation()
        return try await offCooperativePool {
            // Gates 2–4 pin a valid signature to this vendor AND this exact app.
            // Gate 2 is the same on both routes: an ad-hoc seal must still verify.
            let gatedCdhash = try verifyCodeSignatureCapturingCdhash(appAt: downloadedApp)
            switch trust {
            case .developerID:
                try verifyTeamIdentifierMatch(
                    installedApp: installedApp, downloadedApp: downloadedApp)
                try verifyBundleIdentifierMatch(
                    installedApp: installedApp, downloadedApp: downloadedApp)
                try verifySignedLikeInstalledCopy(
                    installedApp: installedApp, downloadedApp: downloadedApp)
            case .publishedDigest(_, let bundleID, let version),
                 .myGoSignature(_, let bundleID, let version):
                try verifyDigestOnlyIdentity(
                    installedApp: installedApp, downloadedApp: downloadedApp,
                    bundleID: bundleID, version: version)
            case .sparkleSignature:
                try verifySparkleKeyOnlyIdentity(
                    installedApp: installedApp, downloadedApp: downloadedApp)
            }

            // Gate 5 reads the actual Mach-O slices; artifact filenames cannot
            // prove that the downloaded build can launch on this Mac.
            try verifyRunnableArchitecture(
                appAt: downloadedApp, host: host, canRunIntel: canRunIntel)
            // Gate 5b must follow gate 5: an unrunnable Intel-only download over
            // an arm64 install must report "cannot launch", not "would run
            // translated". Delta output need not share its baseline's slices.
            try verifyNoArchitectureDowngrade(
                installedApp: installedApp, downloadedApp: downloadedApp, host: host)
            // Gate 6 reads the bundle's OS floor even when the source omits it.
            try verifyRunnableSystemVersion(appAt: downloadedApp, osVersion: osVersion)
            return InPlaceSwap.stagedCopyRequirement(
                installed: installedApp, downloaded: downloadedApp, gatedCdhash: gatedCdhash)
        }
    }

    // MARK: Gates 3 + 4, digest-only route

    /// Which identity gate a digest-only swap may take, from the two Team IDs
    /// alone. Trust is never lowered: an installed Team ID always means gates 3,
    /// 3b and 4 exactly as on `.developerID` (gate 3 refuses a download without
    /// one), and a download that unexpectedly has one is refused. Only "neither
    /// side has a Team ID" is the hash route.
    enum DigestOnlyIdentity: Equatable {
        case teamGate
        case teamAppeared(String)
        case adHoc
    }

    static func digestOnlyIdentity(installedTeam: String?, downloadedTeam: String?) -> DigestOnlyIdentity {
        if installedTeam != nil { return .teamGate }
        if let downloadedTeam { return .teamAppeared(downloadedTeam) }
        return .adHoc
    }

    /// Gates 3 and 4 for the digest-only and MyGo routes. An installed copy with a
    /// Team ID takes the `.developerID` gates unchanged — 3, 3b
    /// (`verifySignedLikeInstalledCopy`) and 4 — since a published digest or a
    /// MyGo signature says nothing about who signed the bundle, and without 3b a
    /// self-signed certificate naming the Team passes 3 and 4.
    ///
    /// Otherwise, for an app with no Team ID on either side: the signed
    /// identifier cannot carry gate 4 here — a linker-signed ad-hoc build reports
    /// `Electron` (MarkText 0.20.0, measured 2026-10-02) — so the bundle's own
    /// `CFBundleIdentifier` is compared on both sides and against the rule's, and
    /// the download's signed identifier must also equal it. Gate 2 has already
    /// verified the seal, which covers `Info.plist`. The version gate pins the
    /// bundle to the release whose digest was checked; the Team-ID route has no
    /// such gate because a Developer ID signature does not need one.
    static func verifyDigestOnlyIdentity(
        installedApp: URL, downloadedApp: URL, bundleID: String, version: String
    ) throws {
        switch digestOnlyIdentity(
            installedTeam: try teamIdentifier(at: installedApp),
            downloadedTeam: try teamIdentifier(at: downloadedApp)) {
        case .teamGate:
            try verifyTeamIdentifierMatch(installedApp: installedApp, downloadedApp: downloadedApp)
            try verifyBundleIdentifierMatch(installedApp: installedApp, downloadedApp: downloadedApp)
            try verifySignedLikeInstalledCopy(installedApp: installedApp, downloadedApp: downloadedApp)
            return
        case .teamAppeared(let team):
            throw VerifyError.teamIdentifierAppeared(downloaded: team)
        case .adHoc:
            break
        }
        let info = try signingInfo(at: downloadedApp)
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        guard flags & SecCodeSignatureFlags.adhoc.rawValue != 0 else {
            throw VerifyError.notAdHocSigned
        }
        let installedPlist = infoPlist(of: installedApp)
        let downloadedPlist = infoPlist(of: downloadedApp)
        let installedID = installedPlist["CFBundleIdentifier"] as? String ?? ""
        let downloadedID = downloadedPlist["CFBundleIdentifier"] as? String ?? ""
        let signedID = info[kSecCodeInfoIdentifier as String] as? String
        guard installedID == bundleID, downloadedID == bundleID, signedID == bundleID else {
            throw VerifyError.infoPlistIdentifierMismatch(
                expected: bundleID, installed: installedID,
                downloaded: signedID == downloadedID ? downloadedID : "\(downloadedID) (signed as \(signedID ?? "nothing"))")
        }
        let downloadedVersion = (downloadedPlist["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard downloadedVersion == version else {
            throw VerifyError.infoPlistVersionMismatch(expected: version, downloaded: downloadedVersion)
        }
    }

    // MARK: Gates 3 + 4, Sparkle route without a Team ID

    /// Gates 3 and 4 for a Sparkle update over a copy with no Team ID, after
    /// `verifySparkleSignature` has tied the download to the installed copy's own
    /// update key. That key is the trust anchor, exactly as for the app's own
    /// Sparkle; this gate keeps the swap from doing anything that copy's updater
    /// would not have been handed by the same key holder:
    ///
    /// - Signing never changes kind. Both Team IDs are read again here (throwing,
    ///   never a "no Team" guess); an installed Team ID takes gates 3, 3b and 4
    ///   exactly as on `.developerID`, and
    ///   a Team ID that appears only on the download is refused, as on the
    ///   digest-only route. An ad-hoc copy takes only an ad-hoc download. A copy
    ///   signed with its own certificate takes only a download that satisfies
    ///   its designated requirement — signed with that same certificate — which
    ///   also refuses a certificate-signed copy being replaced by an ad-hoc one.
    ///   (An ad-hoc copy's designated requirement is its own cdhash, which no
    ///   other build satisfies, so the ad-hoc case cannot use it.)
    /// - The bundle is the same app: `CFBundleIdentifier` equal on both sides and
    ///   to the download's signed identifier, for the reason
    ///   `verifyDigestOnlyIdentity` gives (linker-signed builds sign as
    ///   `Electron`). Sparkle itself has no such check.
    /// - The download still carries an `SUPublicEDKey`. Sparkle refuses an update
    ///   that drops the key ("Sparkle only supports rotation, but not removal of
    ///   (Ed)DSA keys", `SUUpdateValidator`); here the key is the copy's only
    ///   anchor, so installing one would leave nothing to check a later update
    ///   against. A DIFFERENT key is a rotation, which Sparkle allows when the
    ///   update is signed with the installed key — as gate 1 already required.
    ///
    /// No version pin: gate 7 (`verifyNoBundleVersionDowngrade`) refuses an older
    /// build, which is the downgrade a feed could replay.
    static func verifySparkleKeyOnlyIdentity(installedApp: URL, downloadedApp: URL) throws {
        switch digestOnlyIdentity(
            installedTeam: try teamIdentifier(at: installedApp),
            downloadedTeam: try teamIdentifier(at: downloadedApp)) {
        case .teamGate:
            try verifyTeamIdentifierMatch(installedApp: installedApp, downloadedApp: downloadedApp)
            try verifyBundleIdentifierMatch(installedApp: installedApp, downloadedApp: downloadedApp)
            try verifySignedLikeInstalledCopy(installedApp: installedApp, downloadedApp: downloadedApp)
            return
        case .teamAppeared(let team):
            throw VerifyError.teamIdentifierAppeared(downloaded: team)
        case .adHoc:
            break
        }
        let installedInfo = try signingInfo(at: installedApp)
        let downloadedInfo = try signingInfo(at: downloadedApp)
        func isAdHoc(_ info: [String: Any]) -> Bool {
            let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
            return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        }
        if isAdHoc(installedInfo) {
            guard isAdHoc(downloadedInfo) else { throw VerifyError.signingKindChanged }
        } else {
            guard !isAdHoc(downloadedInfo) else { throw VerifyError.signingKindChanged }
            try verifySatisfiesDesignatedRequirement(
                installedApp: installedApp, downloadedApp: downloadedApp)
        }
        guard embeddedEdPublicKey(at: downloadedApp) != nil else { throw VerifyError.updateKeyRemoved }
        let installedID = infoPlist(of: installedApp)["CFBundleIdentifier"] as? String ?? ""
        let downloadedID = infoPlist(of: downloadedApp)["CFBundleIdentifier"] as? String ?? ""
        let signedID = downloadedInfo[kSecCodeInfoIdentifier as String] as? String
        guard !installedID.isEmpty, downloadedID == installedID, signedID == installedID else {
            throw VerifyError.infoPlistIdentifierMismatch(
                expected: installedID, installed: installedID,
                downloaded: signedID == downloadedID ? downloadedID : "\(downloadedID) (signed as \(signedID ?? "nothing"))")
        }
    }

    /// The download satisfies the installed copy's designated requirement — what
    /// Sparkle's `SUCodeSigningVerifier` checks, with the same flags. Throws when
    /// the installed copy has no requirement to read (unsigned).
    static func verifySatisfiesDesignatedRequirement(installedApp: URL, downloadedApp: URL) throws {
        var requirement: SecRequirement?
        let read = SecCodeCopyDesignatedRequirement(try staticCode(at: installedApp), [], &requirement)
        guard read == errSecSuccess, let requirement else {
            throw VerifyError.designatedRequirementNotSatisfied(read)
        }
        let status = SecStaticCodeCheckValidity(
            try staticCode(at: downloadedApp),
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        guard status == errSecSuccess else {
            throw VerifyError.designatedRequirementNotSatisfied(status)
        }
    }

    // MARK: Gate 3b — signed by whoever signed the installed copy

    /// Gate 3 compares Team ID strings, and a Team ID is only what the leaf
    /// certificate's OU says; gate 2 checks the seal against no requirement, so
    /// a self-signed certificate whose OU names the vendor's Team passes both,
    /// and gate 4 with it (the identifier is the signer's to choose). This gate
    /// is the anchor: the download must satisfy the installed copy's own
    /// designated requirement — what `verifySatisfiesDesignatedRequirement` and
    /// Sparkle check, and what macOS uses to decide a new build is the same app.
    /// It follows whatever the installed copy is anchored to (Developer ID,
    /// Apple, Mac App Store), which a fixed `anchor apple generic` + Developer ID
    /// marker would not: that refuses Xcode and store copies.
    ///
    /// A `BundleIDMigration` rename is the one case the plain requirement gets
    /// wrong: it names the installed copy's identifier, which the renamed build
    /// no longer has. There the identifier clause is re-aimed at the download's
    /// signed identifier and everything else — the anchor, the certificate
    /// fields, the Team — still has to hold. Gate 4 has already decided whether
    /// the identifier may change; this gate only asks who signed.
    static func verifySignedLikeInstalledCopy(installedApp: URL, downloadedApp: URL) throws {
        let text = try installedSignerRequirement(installedApp: installedApp, downloadedApp: downloadedApp)
        var requirement: SecRequirement?
        let made = SecRequirementCreateWithString(text as CFString, [], &requirement)
        guard made == errSecSuccess, let requirement else {
            throw VerifyError.designatedRequirementNotSatisfied(made)
        }
        let status = SecStaticCodeCheckValidity(
            try staticCode(at: downloadedApp),
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        guard status == errSecSuccess else {
            throw VerifyError.designatedRequirementNotSatisfied(status)
        }
    }

    /// The installed copy's designated requirement as text, with its identifier
    /// clause re-aimed at `downloadedApp`'s signed identifier when the two
    /// differ (see `verifySignedLikeInstalledCopy`). Also what the privileged
    /// swap re-checks its staged copy against (`InPlaceSwap`). Throws when the
    /// installed copy has no requirement to read.
    static func installedSignerRequirement(installedApp: URL, downloadedApp: URL) throws -> String {
        var requirement: SecRequirement?
        let read = SecCodeCopyDesignatedRequirement(try staticCode(at: installedApp), [], &requirement)
        guard read == errSecSuccess, let requirement else {
            throw VerifyError.designatedRequirementNotSatisfied(read)
        }
        var cfText: CFString?
        let copied = SecRequirementCopyString(requirement, [], &cfText)
        guard copied == errSecSuccess, let text = cfText as String? else {
            throw VerifyError.designatedRequirementNotSatisfied(copied)
        }
        guard let installedID = try signingIdentifier(at: installedApp),
              let downloadedID = try signingIdentifier(at: downloadedApp),
              installedID != downloadedID
        else { return text }
        return Self.requirement(text, reaimedFrom: installedID, to: downloadedID)
    }

    /// `text` with every `identifier "<from>"` (quoted or bare, as
    /// `SecRequirementCopyString` writes a simple one) replaced by
    /// `identifier "<to>"`. A requirement that never names `from` comes back
    /// unchanged, so it still has to be met as written.
    static func requirement(_ text: String, reaimedFrom from: String, to: String) -> String {
        func quoted(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let pattern = "identifier\\s+(?:"
            + NSRegularExpression.escapedPattern(for: quoted(from)) + "|"
            + NSRegularExpression.escapedPattern(for: from) + "(?=[\\s)]|$))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: "identifier " + quoted(to)))
    }

    static func infoPlist(of app: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else { return [:] }
        return plist
    }

    // MARK: Gate 1 — EdDSA signature over the downloaded file

    /// Verify the Sparkle Ed25519 signature of `fileData` against the app's
    /// `SUPublicEDKey`. Both signature and key are base64.
    public static func verifyEdSignature(
        fileData: Data,
        signatureBase64: String?,
        publicKeyBase64: String
    ) throws {
        guard let signatureBase64, !signatureBase64.isEmpty else {
            throw VerifyError.edSignatureMissing
        }
        guard
            let signature = Data(base64Encoded: signatureBase64),
            let publicKeyRaw = Data(base64Encoded: publicKeyBase64),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw)
        else {
            throw VerifyError.edSignatureInvalid
        }
        guard publicKey.isValidSignature(signature, for: fileData) else {
            throw VerifyError.edSignatureInvalid
        }
    }

    /// Verify a MyGo signature (`update.Verify` in `github.com/egoist/mygo`):
    /// Ed25519 over the SHA-256 of `fileData`, with the vendor's MyGo update key
    /// (`VendorInstallSpec.myGoPublicKey`). Same primitive as
    /// `verifyEdSignature`; its own errors, because that one's text names the
    /// app's public key and this key comes from the recipe.
    @discardableResult
    public static func verifyMyGoSignature(
        fileData: Data,
        signatureBase64: String?,
        publicKeyBase64: String
    ) throws -> VerifiedMyGoSignature {
        do {
            try verifyEdSignature(
                fileData: Data(SHA256.hash(data: fileData)),
                signatureBase64: signatureBase64,
                publicKeyBase64: publicKeyBase64)
        } catch VerifyError.edSignatureMissing {
            throw VerifyError.myGoSignatureMissing
        } catch VerifyError.edSignatureInvalid {
            throw VerifyError.myGoSignatureInvalid
        }
        return VerifiedMyGoSignature()
    }

    /// Gate 1 for an installed copy without a Team ID: the EdDSA signature over
    /// `file` — the full archive, or the patch when one was downloaded — against
    /// the `SUPublicEDKey` read from `installedApp` on disk, never from the
    /// update or a cached scan. A missing key or signature refuses, and an
    /// invalid one throws at once: there is no rotation fallback on this route,
    /// because `isEdKeyRotation` leans on the Team-ID gate this copy cannot run.
    /// Blocking file read; callers stay off the pool.
    static func verifySparkleSignature(
        of file: URL, signatureBase64: String?, installedApp: URL
    ) throws -> VerifiedSparkleSignature {
        guard let key = embeddedEdPublicKey(at: installedApp) else {
            throw VerifyError.noTeamIdentifierOrUpdateKey
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        try verifyEdSignature(fileData: data, signatureBase64: signatureBase64, publicKeyBase64: key)
        return VerifiedSparkleSignature()
    }

    // MARK: Gate 1b — vendor rotated its Sparkle signing key

    /// True when an `edSignatureInvalid` failure is explained by the vendor
    /// having rotated its Sparkle key: the downloaded bundle ships a DIFFERENT
    /// `SUPublicEDKey` than the installed one, and the feed's signature verifies
    /// against that new key.
    ///
    /// This happens when a vendor generates a fresh Ed25519 keypair without
    /// shipping a transition release signed by the old key — the installed app's
    /// own Sparkle rejects the update just as we do, so the update chain is
    /// broken until the user installs by hand. (Observed 2026-08: Mirage Beacon
    /// 1.2.0 → 1.3.0.)
    ///
    /// Verifying against a key that came out of the same download is
    /// deliberately NOT a trust claim — it is circular, and proves only that the
    /// appcast entry and the bundle were minted by the same key holder (so a
    /// stale or mismatched feed entry still fails). ALL of the trust in this path
    /// comes from Gates 2/3/4 running afterwards — valid Developer ID code
    /// signature, same Team ID, same signed bundle id as installed — exactly the
    /// gate the Vendor/GitHub paths carry on their own, and it fails closed.
    /// Callers must therefore treat a `true` here as "keep going and let Gates
    /// 2/3/4 decide", never as "this download is verified".
    public static func isEdKeyRotation(
        fileData: Data,
        signatureBase64: String?,
        installedKeyBase64: String,
        downloadedApp: URL
    ) -> Bool {
        guard
            let newKey = embeddedEdPublicKey(at: downloadedApp),
            newKey != installedKeyBase64
        else { return false }
        do {
            try verifyEdSignature(
                fileData: fileData,
                signatureBase64: signatureBase64,
                publicKeyBase64: newKey
            )
            return true
        } catch {
            return false
        }
    }

    /// The `SUPublicEDKey` an app bundle ships in its `Info.plist`, or nil when
    /// it has none (an unsigned Sparkle feed).
    public static func embeddedEdPublicKey(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any],
            let key = (plist["SUPublicEDKey"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else { return nil }
        return key
    }

    // MARK: Gate 2 — code signature validity of the extracted app

    /// Run the equivalent of `codesign --verify --deep --strict` against the app
    /// bundle. `kSecCSCheckNestedCode` is essential: without it only the top-level
    /// seal is checked, so a tampered framework/helper/XPC service embedded in the
    /// bundle would pass. `kSecCSStrictValidate` rejects bundles with extra
    /// unsigned files or resource-rule tricks. This is the central code-trust gate
    /// for the Vendor/GitHub paths (no EdDSA there), so it must be deep.
    public static func verifyCodeSignature(appAt url: URL) throws {
        try verifyCodeSignature(of: try staticCode(at: url))
    }

    private static func verifyCodeSignature(of code: SecStaticCode) throws {
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures
            | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else {
            throw VerifyError.codeSignatureInvalid(status)
        }
    }

    /// Gate 2, and the cdhash (hex, this Mac's slice — what a `cdhash H"…"`
    /// requirement names) read off the SAME `SecStaticCode` the check just
    /// validated, not off a second open of the path: the bundle sits in a
    /// user-writable directory, and a path read later could describe a
    /// substitute. Nil only if the validated signature reports no cdhash.
    static func verifyCodeSignatureCapturingCdhash(appAt url: URL) throws -> String? {
        let code = try staticCode(at: url)
        try verifyCodeSignature(of: code)
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data,
              !unique.isEmpty
        else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Gate 3 — Team Identifier must match the installed app

    /// The single most important gate: the new build must be signed by the
    /// same developer team as what's already installed, so a hijacked feed
    /// can't swap in a different vendor's (or malicious) binary.
    public static func verifyTeamIdentifierMatch(
        installedApp: URL,
        downloadedApp: URL
    ) throws {
        guard let installedTeam = try teamIdentifier(at: installedApp) else {
            throw VerifyError.noTeamIdentifier(which: "installed")
        }
        guard let downloadedTeam = try teamIdentifier(at: downloadedApp) else {
            throw VerifyError.noTeamIdentifier(which: "downloaded")
        }
        guard installedTeam == downloadedTeam else {
            throw VerifyError.teamIdentifierMismatch(
                installed: installedTeam, downloaded: downloadedTeam
            )
        }
    }

    public static func teamIdentifier(at url: URL) throws -> String? {
        try signingInfo(at: url)[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: Gate 4 — signed bundle identifier must match the installed app

    /// Belt-and-suspenders on top of the Team ID gate: the downloaded build must
    /// carry the SAME signed identifier as the app it's replacing. Team ID alone
    /// permits any app from the same vendor (Google's Chrome vs Earth) — or a
    /// different CHANNEL of the same app sharing that Team, and sometimes the
    /// bundle id outright; this pins the swap to the exact product. We read the
    /// *signed* identifier (`kSecCodeInfoIdentifier`), not the raw Info.plist, so
    /// it's covered by the code seal already verified in Gate 2 and can't be
    /// spoofed.
    ///
    /// The one exception is a rename the vendor made and `BundleIDMigration`
    /// records: a download signed as the entry's `to` may replace a copy signed
    /// as its `from`, when both are signed by the entry's Team and the installed
    /// version is below the entry's bound. Nothing else differs from the strict
    /// comparison — not the reverse direction, not another Team, not a copy
    /// newer than the rename.
    public static func verifyBundleIdentifierMatch(
        installedApp: URL,
        downloadedApp: URL,
        migrations: [BundleIDMigration] = BundleIDMigration.all
    ) throws {
        guard let installedID = try signingIdentifier(at: installedApp) else {
            throw VerifyError.noBundleIdentifier(which: "installed")
        }
        guard let downloadedID = try signingIdentifier(at: downloadedApp) else {
            throw VerifyError.noBundleIdentifier(which: "downloaded")
        }
        guard installedID == downloadedID else {
            let installedVersion = (infoPlist(of: installedApp)["CFBundleShortVersionString"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if BundleIDMigration.migration(
                installed: installedID, downloaded: downloadedID,
                installedVersion: installedVersion,
                installedTeam: try teamIdentifier(at: installedApp),
                downloadedTeam: try teamIdentifier(at: downloadedApp),
                in: migrations) != nil {
                return
            }
            throw VerifyError.bundleIdentifierMismatch(
                installed: installedID, downloaded: downloadedID
            )
        }
    }

    public static func signingIdentifier(at url: URL) throws -> String? {
        try signingInfo(at: url)[kSecCodeInfoIdentifier as String] as? String
    }
    /// What a signature says about the code, for `duo diff` to compare across two
    /// releases. Read from `SecCodeCopySigningInformation` — the same fields
    /// `codesign -dvv` prints — without spawning it once per bundle.
    ///
    /// Not a validity check: a tampered bundle still reports what its signature
    /// claims. Blocking Security call, so callers stay off the cooperative pool.
    public struct SigningSummary: Sendable, Equatable, Codable {
        public let identifier: String?
        public let teamIdentifier: String?
        /// Certificate subject summaries, leaf first — codesign's `Authority=` lines.
        public let authorities: [String]
        /// CodeDirectory flags by codesign's names, e.g. `["runtime"]`.
        public let flags: [String]
        /// The hardened-runtime version, e.g. `27.0.0`.
        public let runtimeVersion: String?
        /// Flattened to `key -> value`, nested keys joined with `.` and arrays
        /// joined with `, `, so a single changed entry compares as one line.
        public let entitlements: [String: String]

        public init(
            identifier: String?, teamIdentifier: String?, authorities: [String], flags: [String],
            runtimeVersion: String?, entitlements: [String: String]
        ) {
            self.identifier = identifier
            self.teamIdentifier = teamIdentifier
            self.authorities = authorities
            self.flags = flags
            self.runtimeVersion = runtimeVersion
            self.entitlements = entitlements
        }
    }

    /// Nil when the bundle is unsigned or its signature cannot be read.
    public static func signingSummary(at url: URL) -> SigningSummary? {
        // Unsigned code is not an error here: the call succeeds with nothing but
        // `main-executable` in it. Signed code always carries an identifier.
        guard let info = try? signingInfo(at: url), info[kSecCodeInfoIdentifier as String] != nil
        else { return nil }
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let flagBits = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        // Named as `codesign` names them, so the output reads like its `flags=(…)`.
        let names: [(UInt32, String)] = [
            (0x0000_0001, "host"), (0x0000_0002, "adhoc"), (0x0000_0100, "hard"),
            (0x0000_0200, "kill"), (0x0000_0400, "expires"), (0x0000_0800, "restrict"),
            (0x0000_1000, "enforcement"), (0x0000_2000, "library-validation"),
            (0x0001_0000, "runtime"), (0x0002_0000, "linker-signed"),
        ]
        let runtime = (info[kSecCodeInfoRuntimeVersion as String] as? NSNumber)?.uint32Value
        return SigningSummary(
            identifier: info[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            authorities: certificates.map { SecCertificateCopySubjectSummary($0) as String? ?? "?" },
            flags: names.filter { flagBits & $0.0 != 0 }.map(\.1),
            runtimeVersion: runtime.map { "\($0 >> 16).\(($0 >> 8) & 0xff).\($0 & 0xff)" },
            entitlements: flattened(info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]))
    }

    static func flattened(_ value: Any, prefix: String = "") -> [String: String] {
        switch value {
        case let dict as [String: Any]:
            var out: [String: String] = [:]
            for (key, child) in dict {
                out.merge(flattened(child, prefix: prefix.isEmpty ? key : prefix + "." + key)) { first, _ in first }
            }
            return out
        case let array as [Any]:
            return [prefix: array.map { "\($0)" }.joined(separator: ", ")]
        default:
            return [prefix: "\(value)"]
        }
    }

    private static func signingInfo(at url: URL) throws -> [String: Any] {
        let code = try staticCode(at: url)
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let status = SecCodeCopySigningInformation(code, flags, &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else {
            throw VerifyError.codeSignatureInvalid(status)
        }
        return dict
    }

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw VerifyError.codeSignatureInvalid(status)
        }
        return staticCode
    }
    // MARK: Gate 5 — the download is a build this Mac can actually run

    /// Which architectures a bundle's main executable was built for, read from
    /// the real Mach-O rather than inferred from anything's name.
    ///
    /// This exists because the *selection* of a download is necessarily
    /// name-based — we choose an asset before we have it — and names lie. Real
    /// cases from the registry: `Goose.zip` and `MarkEdit-<ver>-apple-silicon.dmg`
    /// are arm64-only but carry no marker the asset picker reads, so they were
    /// classified as safe for either Mac. Whatever the filename said, the bundle
    /// either has a slice this machine can run or the swap is refused.
    ///
    /// Scope: this covers the two routes that swap in a bundle *we* picked by
    /// filename — VendorInstaller and SparkleInstaller. The pkg route
    /// (`PackageInstaller`) hands the file to Installer.app and never sees an
    /// .app to read the slices out of — see its header for which gates it does
    /// run; Homebrew and the Mac App Store pick their own architecture and need
    /// no gate here.
    static func executableArchitectures(ofAppAt url: URL) -> Set<Int> {
        guard let bundle = Bundle(url: url),
              let archs = bundle.executableArchitectures else { return [] }
        return Set(archs.map(\.intValue))
    }

    /// Whether a bundle built for `architectures` can launch on `host`.
    ///
    /// An empty set means "we could not read it" — a bundle whose executable is a
    /// script, say — and is treated as runnable. This gate exists to catch a build
    /// we can PROVE is wrong for the machine; it is not a proof of correctness, so
    /// an unreadable header must not start refusing updates that install fine
    /// today.
    ///
    /// The worrying version of "unreadable" — a bundle whose main executable is
    /// missing or truncated — cannot reach this gate: both make the *whole*
    /// bundle read as unsigned, so gate 2 refuses them first (measured
    /// 2026-08-16 on a copy of DuoUpdater.app with its executable emptied and
    /// with it deleted: `errSecCSUnsigned`, -67062, in both cases).
    static func canRun(architectures: Set<Int>, on host: HostArch, canRunIntel: Bool) -> Bool {
        guard !architectures.isEmpty else { return true }
        let arm = architectures.contains(NSBundleExecutableArchitectureARM64)
        let intel = architectures.contains(NSBundleExecutableArchitectureX86_64)
        switch host {
        case .arm64:
            // Native, or an Intel slice while translation still covers apps.
            return arm || (intel && canRunIntel)
        case .x86_64:
            // No reverse translation has ever existed: an arm64-only build is
            // simply not startable here.
            return intel
        }
    }

    /// Gate 5, run beside the signature gates on the downloaded bundle.
    public static func verifyRunnableArchitecture(
        appAt url: URL,
        host: HostArch = .current,
        canRunIntel: Bool = HostArch.canRunIntelBuilds
    ) throws {
        let archs = executableArchitectures(ofAppAt: url)
        guard !canRun(architectures: archs, on: host, canRunIntel: canRunIntel) else { return }
        let names = archs.map { arch -> String in
            switch arch {
            case NSBundleExecutableArchitectureARM64:  return "arm64"
            case NSBundleExecutableArchitectureX86_64: return "x86_64"
            default: return "arch \(arch)"
            }
        }.sorted().joined(separator: " + ")
        // `names` is never empty here: an empty set is runnable by definition
        // above, so this line is only reached with slices we could read.
        throw VerifyError.unrunnableArchitecture(
            built: names, host: host == .arm64 ? "arm64" : "x86_64")
    }

    // MARK: Gate 5b — the download must not drop a slice the installed bundle has

    /// Whether swapping `installed`'s architectures for `downloaded`'s would be a
    /// downgrade: the installed bundle can run natively (it has an arm64 slice)
    /// and the download cannot (it has none) — while still being a real
    /// replacement, i.e. it does carry SOME slice (x86_64) rather than reading as
    /// unparseable.
    ///
    /// Gate 5 above asks only "can THIS Mac run the download" — and on Apple
    /// silicon while Rosetta still covers apps, an Intel-only build answers that
    /// question ✅. The install then proceeds: it lands, it launches, and from
    /// that point on the app runs translated, including on the NEXT check, which
    /// picks the same Intel-only asset again. This predicate catches that one
    /// case instead: not "can it run", but "does it run WORSE than what's already
    /// there".
    ///
    /// Deliberately narrower than "any slice was dropped": going from universal
    /// to arm64-only, or from arm64-only to universal, both leave a native arm64
    /// slice in `downloaded` — normal thinning, not a downgrade, and both must
    /// return `false` here. Only `downloaded` having x86_64 but no arm64 is
    /// provably worse than an `installed` that has arm64.
    ///
    /// Fails open on an empty set on EITHER side, matching `canRun` above and for
    /// the same reason: an unreadable Mach-O header (installed OR downloaded)
    /// must not start refusing swaps that install fine today. This predicate
    /// proves a downgrade; it is not a proof that no downgrade occurred.
    static func isArchitectureDowngrade(installed: Set<Int>, downloaded: Set<Int>) -> Bool {
        guard !installed.isEmpty, !downloaded.isEmpty else { return false }
        guard installed.contains(NSBundleExecutableArchitectureARM64) else { return false }
        guard !downloaded.contains(NSBundleExecutableArchitectureARM64) else { return false }
        return downloaded.contains(NSBundleExecutableArchitectureX86_64)
    }

    /// Gate 5b, called by `verifyInstallArtifact` (both installers' shared entry
    /// point) immediately AFTER Gate 5 passes on the same
    /// `newApp`/`installedApp` pair — never before, and never on its own:
    /// a package that Gate 5 would refuse outright (arm64 host, no Rosetta,
    /// Intel-only download) must fail with Gate 5's "cannot launch" message,
    /// not this one's "would run translated", which implies it launches at
    /// all. Only meaningful on Apple silicon: an Intel Mac never had an arm64
    /// slice to lose, and this product ships arm64-only besides
    /// (`App/project.yml`, `ARCHS: arm64`), so there is no Intel host for
    /// `installedApp` to be read from in practice — this still checks `host`
    /// explicitly rather than assume it, so the gate stays correct if that
    /// ever changes.
    public static func verifyNoArchitectureDowngrade(
        installedApp: URL,
        downloadedApp: URL,
        host: HostArch = .current
    ) throws {
        guard host == .arm64 else { return }
        let installedArchs = executableArchitectures(ofAppAt: installedApp)
        let downloadedArchs = executableArchitectures(ofAppAt: downloadedApp)
        guard isArchitectureDowngrade(installed: installedArchs, downloaded: downloadedArchs)
        else { return }
        func names(_ archs: Set<Int>) -> String {
            archs.map { arch -> String in
                switch arch {
                case NSBundleExecutableArchitectureARM64:  return "arm64"
                case NSBundleExecutableArchitectureX86_64: return "x86_64"
                default: return "arch \(arch)"
                }
            }.sorted().joined(separator: " + ")
        }
        throw VerifyError.architectureDowngrade(
            installed: names(installedArchs), downloaded: names(downloadedArchs))
    }

    // MARK: Gate 6 — the download declares an OS floor this Mac is below

    /// The `LSMinimumSystemVersion` a downloaded bundle declares, or nil when it
    /// declares none (or the value is unreadable).
    ///
    /// This is the only OS-compatibility source that exists for most of what we
    /// install. Measured 2026-08-30 across the 143 apps on one real machine: the
    /// 16 answered by Sparkle publish a floor in the feed (12 of 14 reachable
    /// feeds declare `sparkle:minimumSystemVersion`, already honoured in
    /// `SparkleAppcastSource.usableItems`), but the 42 answered by
    /// `GitHubReleasesSource` publish NOTHING — a GitHub release carries no OS
    /// field at all — and only 5 of the ~140 `VendorProbeRegistry` recipes pin a
    /// floor by hand. For those routes the artifact's own plist is the whole
    /// truth, and it only arrives after the download: this gate cannot save the
    /// bandwidth, it can only keep us from swapping in a bundle that will not
    /// launch and reporting success.
    ///
    /// Read through `BundleLayout.infoPlistURL` rather than a hardcoded
    /// `Contents/`: a wrapped iPhone/iPad app keeps its plist under
    /// `Wrapper/<Inner>.app/`, and reading the wrong path would not fail — it
    /// would read nothing and wave the bundle through.
    ///
    /// **This gate does not apply to iOS apps running on Apple silicon, and says
    /// so explicitly rather than by accident.** Measured on the two wrapped
    /// bundles on one machine 2026-08-30 (`Amp 2.app`, `Aqara Home.app`): both
    /// declare `CFBundleSupportedPlatforms = [iPhoneOS]` and carry
    /// `MinimumOSVersion` (26.0 and 18.0) with **no `LSMinimumSystemVersion` at
    /// all**. So reaching the right plist buys this gate nothing for them — and
    /// reading `MinimumOSVersion` instead would be worse, not better: it is an
    /// **iOS** version, and comparing it against a macOS version is precisely the
    /// cross-namespace comparison this repo forbids. It looks harmless only while
    /// the two numbering schemes happen to be aligned (iOS 26 / macOS 26); on a
    /// macOS 15 host an iOS-18 floor would read as satisfied for the wrong
    /// reason. Declining by platform is the honest answer, and it keeps a future
    /// reader from "fixing" this by wiring the iOS key in.
    static func declaredMinimumSystemVersion(
        ofAppAt appURL: URL, fileManager: FileManager = .default
    ) -> String? {
        let plistURL = BundleLayout.infoPlistURL(for: appURL, fileManager: fileManager)
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return declaredMinimumSystemVersion(inInfoPlist: data)
    }

    /// The same rule, over `Info.plist` bytes that never became a bundle on disk.
    ///
    /// `PackageInstaller` reads its payload's plist straight out of the package's
    /// cpio archive, so it has the bytes and no bundle. Split out rather than
    /// re-derived there: the iPhoneOS decline above and the trim/empty handling
    /// below are the gate's rule, and a second copy of them is exactly the
    /// detection-time/install-time divergence `HostOS`'s doc comment warns about.
    /// Accepts XML and binary plists alike — `PropertyListSerialization` sniffs
    /// the format, and a payload's plist may be either — the one real vendor
    /// payload read for this (UU Remote 4.35.0) is XML, and a compiled bundle's
    /// is usually binary.
    /// Whether `data` is a property list at all.
    ///
    /// Only so a caller that got no floor can say WHICH kind of nothing it got:
    /// a plist that parses and declares no macOS floor is ordinary, one that does
    /// not parse means the caller read the wrong bytes. `PackageInstaller` needs
    /// the distinction; the bundle route never does, because it is holding the
    /// bundle.
    static func infoPlistParses(_ data: Data) -> Bool {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil
    }

    static func declaredMinimumSystemVersion(inInfoPlist data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        // An iOS bundle's floor is stated in iOS terms. Never compare it to macOS.
        if let platforms = plist["CFBundleSupportedPlatforms"] as? [String],
           platforms.contains("iPhoneOS") {
            return nil
        }
        guard
            let declared = (plist["LSMinimumSystemVersion"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !declared.isEmpty
        else { return nil }
        return declared
    }

    /// Whether a bundle declaring `minimumSystemVersion` can launch on a Mac
    /// running `osVersion`.
    ///
    /// Fails OPEN on anything it cannot read as a version. That covers more than
    /// a digit-free string: because `VersionComparator` ranks a text token below
    /// a numeric one, any value whose FIRST token is non-numeric ("macOS 13.0",
    /// "13.0 (Ventura)") also compares as satisfied regardless of the number that
    /// follows it. Stated because it is easy to read the guard below as narrower
    /// than it is. Same rule gate 5 states for an unreadable Mach-O header, and
    /// for the same reason: this gate exists to catch a build we can PROVE is
    /// wrong for the machine, so an unparseable value must not start refusing
    /// updates that install fine today.
    ///
    /// How much of a real population this covers, measured over the 143 app
    /// bundles on one machine 2026-08-30: 140 declare `LSMinimumSystemVersion`,
    /// 3 declare none, and every declared value parsed (two- and three-component
    /// numeric strings — "27.0", "10.15.7"). So the fail-open branch is the rare
    /// path here, not the common one — but it is still the right default, since
    /// the cost of a false refusal (an app that can never update) is worse than
    /// the cost of a miss (which lands back on the behaviour we ship today).
    ///
    /// Comparison is `VersionComparator`'s, matching what `usableItems` does with
    /// a feed's declared floor, so the two gates cannot disagree about the same
    /// pair of numbers.
    static func canRun(minimumSystemVersion declared: String?, on osVersion: String) -> Bool {
        guard let declared, !declared.isEmpty,
              declared.rangeOfCharacter(from: .decimalDigits) != nil
        else { return true }
        return VersionComparator.compare(osVersion, declared) != .orderedAscending
    }

    /// Gate 6, run beside gate 5 on the downloaded bundle.
    public static func verifyRunnableSystemVersion(
        appAt url: URL,
        osVersion: String = HostOS.numericVersion(),
        fileManager: FileManager = .default
    ) throws {
        let declared = declaredMinimumSystemVersion(ofAppAt: url, fileManager: fileManager)
        guard !canRun(minimumSystemVersion: declared, on: osVersion) else {
            // Log the fail-open too. A gate that silently declines to fire is
            // exactly the thing nobody notices, and `declared == nil` is the
            // shape every miss enumerated above collapses to.
            if declared == nil {
                Log.install.info(
                    "gate 6 no floor declared \(url.lastPathComponent, privacy: .public) — allowing")
            }
            return
        }
        // `declared` is non-nil here: a nil floor is runnable by definition above.
        throw VerifyError.unsupportedSystemVersion(
            required: declared ?? "?", host: osVersion)
    }

    // MARK: Gate 7 — a Sparkle download must not be an older build

    /// Sparkle's own downgrade check, which our Sparkle route otherwise lacks.
    ///
    /// What it stops: EdDSA proves the archive is one the vendor signed, not
    /// that it is the release the feed says it is. We read no signed feed
    /// (`SURequireSignedFeed`), so whoever controls the feed host can label an
    /// older, validly signed archive as the newest version, and every other gate
    /// passes it. Sparkle refuses that swap itself, in
    /// `SUPlainInstaller performInitialInstallation:` (read at 2.x,
    /// 2026-10-18): the update must have a `CFBundleVersion`, and the installed
    /// one must not compare above it. An equal build passes there and here.
    ///
    /// Sparkle route only, called by `SparkleInstaller` after
    /// `verifyInstallArtifact`. On that route this cannot refuse an update the
    /// app's own updater would install, because the app's Sparkle runs the
    /// same check. The vendor, GitHub and Xcode routes have no such guarantee:
    /// nothing promises their `CFBundleVersion` only rises, and refusing on an
    /// unproven rule is how an app stops updating.
    ///
    /// Compared up to the first `-`, because Sparkle's `SUStandardVersionComparator`
    /// stops reading there (`splitVersionString` breaks on `kDashType`) and
    /// `VersionComparator` would keep going: `1234-def` over `1234-abc` is equal to
    /// Sparkle and would read as a downgrade here.
    ///
    /// An installed copy with no `CFBundleVersion` is let through, with a log
    /// line: there is nothing to compare, the feed cannot change the installed
    /// bundle, and Sparkle cannot run in such an app anyway (`SUHost.version`
    /// raises without one).
    static func verifyNoBundleVersionDowngrade(installedApp: URL, downloadedApp: URL) throws {
        func bundleVersion(_ app: URL) -> String? {
            guard let raw = infoPlist(of: app)["CFBundleVersion"] as? String,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return raw
        }
        guard let downloaded = bundleVersion(downloadedApp) else {
            throw VerifyError.bundleVersionMissing
        }
        guard let installed = bundleVersion(installedApp) else {
            Log.install.info(
                "gate 7 installed \(installedApp.lastPathComponent, privacy: .public) has no CFBundleVersion — allowing")
            return
        }
        func beforeDash(_ version: String) -> String {
            String(version.prefix { $0 != "-" })
        }
        guard VersionComparator.compare(beforeDash(installed), beforeDash(downloaded))
                == .orderedDescending
        else { return }
        throw VerifyError.bundleVersionDowngrade(installed: installed, downloaded: downloaded)
    }

}
