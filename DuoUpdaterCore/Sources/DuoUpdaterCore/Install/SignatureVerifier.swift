import Foundation
import CryptoKit
import Security

/// The gates a downloaded update must pass before we will install it. Any
/// failure aborts the install.
///
/// Gates 1–4 are about trust (EdDSA signature, code signature, Team ID, bundle
/// ID); gates 5 and 6 are about liveness — whether the bundle can launch on this
/// Mac at all, by architecture and by the OS version it declares it needs.
/// Callers pick the gates that apply to their route: the Sparkle installer runs
/// all of them, the vendor installer runs 2–6 (no feed signature to check).
public enum SignatureVerifier {

    public enum VerifyError: LocalizedError {
        case edSignatureMissing
        case edSignatureInvalid
        case codeSignatureInvalid(OSStatus)
        case noTeamIdentifier(which: String)
        case teamIdentifierMismatch(installed: String, downloaded: String)
        case noBundleIdentifier(which: String)
        case bundleIdentifierMismatch(installed: String, downloaded: String)
        case unrunnableArchitecture(built: String, host: String)
        case unsupportedSystemVersion(required: String, host: String)

        public var errorDescription: String? {
            switch self {
            case .edSignatureMissing:
                return "The update feed provided no EdDSA signature."
            case .edSignatureInvalid:
                return "The download's EdDSA signature did not match the app's public key."
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
            case .unsupportedSystemVersion(let required, let host):
                return "The download requires macOS \(required) and this Mac runs macOS \(host). Refusing to install a build it cannot launch."
            }
        }
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
        let code = try staticCode(at: url)
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures
            | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, nil)
        guard status == errSecSuccess else {
            throw VerifyError.codeSignatureInvalid(status)
        }
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
    /// permits any app from the same vendor (Google's Chrome vs Earth); this pins
    /// the swap to the exact product. We read the *signed* identifier
    /// (`kSecCodeInfoIdentifier`), not the raw Info.plist, so it's covered by the
    /// code seal already verified in Gate 2 and can't be spoofed.
    public static func verifyBundleIdentifierMatch(
        installedApp: URL,
        downloadedApp: URL
    ) throws {
        guard let installedID = try signingIdentifier(at: installedApp) else {
            throw VerifyError.noBundleIdentifier(which: "installed")
        }
        guard let downloadedID = try signingIdentifier(at: downloadedApp) else {
            throw VerifyError.noBundleIdentifier(which: "downloaded")
        }
        guard installedID == downloadedID else {
            throw VerifyError.bundleIdentifierMismatch(
                installed: installedID, downloaded: downloadedID
            )
        }
    }

    public static func signingIdentifier(at url: URL) throws -> String? {
        try signingInfo(at: url)[kSecCodeInfoIdentifier as String] as? String
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
    /// .app to read, so it stays gated on signature + Team ID only; Homebrew and
    /// the Mac App Store pick their own architecture and need no gate here.
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
    /// Read through `BundleLayout.interiorPrefix` rather than a hardcoded
    /// `Contents/`: a wrapped iPhone/iPad app keeps its plist under
    /// `Wrapper/<Inner>.app/`, and reading the wrong path here would not fail —
    /// it would read nothing, which this gate treats as "no floor declared" and
    /// waves through. Silent per-layout blindness, not an error.
    static func declaredMinimumSystemVersion(
        ofAppAt appURL: URL, fileManager: FileManager = .default
    ) -> String? {
        let prefix = BundleLayout.interiorPrefix(for: appURL, fileManager: fileManager)
        let plistURL = appURL.appendingPathComponent(prefix + "Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any],
            let declared = (plist["LSMinimumSystemVersion"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !declared.isEmpty
        else { return nil }
        return declared
    }

    /// Whether a bundle declaring `minimumSystemVersion` can launch on a Mac
    /// running `osVersion`.
    ///
    /// Fails OPEN on anything it cannot read as a version — a nil/empty value, or
    /// a string with no numeric component at all. Same rule gate 5 states for an
    /// unreadable Mach-O header, and for the same reason: this gate exists to
    /// catch a build we can PROVE is wrong for the machine, so an unparseable
    /// value must not start refusing updates that install fine today.
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
        guard !canRun(minimumSystemVersion: declared, on: osVersion) else { return }
        // `declared` is non-nil here: a nil floor is runnable by definition above.
        throw VerifyError.unsupportedSystemVersion(
            required: declared ?? "?", host: osVersion)
    }

}
