import Testing
import Foundation
@testable import DuoUpdaterCore

/// Edge's enterprise feed gives every artifact a `Hash` with `HashAlgorithm:
/// SHA256` (UPPERCASE hex); the digest has to be the pkg's, under the channel's
/// own first MacOS release — not the sibling `.plist`/`.p7s`, not Linux's, not
/// another product's, not an older release's.
struct EdgeDigestTests {
    private static func body(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func pattern(_ bundleID: String) throws -> String {
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
        let spec = try #require(recipe.install)
        #expect(spec.checksumFormat == .sha256Hex)
        return try #require(spec.checksumPattern)
    }

    private static let stablePkgHash = "EA0CB511706321FBE7800D3E1D6B8E7C1237D9ABEA97D68A9AC56F7317479B38"

    @Test func eachChannelReadsItsOwnPkgHash() throws {
        let body = try Self.body("edge-enterprise-beta-publishing")
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.pattern("com.microsoft.edgemac.Dev"))
            == "4402E219E3E237DEF3D1CFD156ACD267C3365BB78BF300DCFE25C4459E4F3C15")
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.pattern("com.microsoft.edgemac.Beta"))
            == "EAE3F9A8E7F8AC884B6119F9F06465125DF0F1E7A1156156ED1BA8747ADB479E")
        // Stable lists a Linux release (rpm, deb) before its MacOS one.
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.pattern("com.microsoft.edgemac"))
            == Self.stablePkgHash)
    }

    /// The day Beta carried no MacOS release: no digest, rather than Stable's.
    @Test func anEmptyBetaTrackReadsNoDigest() throws {
        let body = try Self.body("edge-enterprise-beta-dormant")
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: try Self.pattern("com.microsoft.edgemac.Beta")) == nil)
    }

    @Test func keyOrderInsideTheArtifactDoesNotMatter() throws {
        let body = try Self.body("edge-enterprise-beta-publishing")
        let reordered = body.replacingOccurrences(
            of: #"{"ArtifactName":"pkg","Location":"https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/35c7ec3f-425a-430f-9998-6db18f725089/MicrosoftEdge-152.0.4191.66.pkg","Hash":"\#(Self.stablePkgHash)","#,
            with: #"{"Hash":"\#(Self.stablePkgHash)","ArtifactName":"pkg","Location":"https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/35c7ec3f-425a-430f-9998-6db18f725089/MicrosoftEdge-152.0.4191.66.pkg","#)
        #expect(reordered != body)
        #expect(VendorProbeRecipe.extractVersion(from: reordered, pattern: try Self.pattern("com.microsoft.edgemac"))
            == Self.stablePkgHash)
    }

    /// The pkg carries no `Hash`: nothing is read — not the `.plist` beside it, and
    /// not an older MacOS release's pkg further down, either of which would refuse
    /// the good download.
    @Test func aPkgWithoutAHashReadsNothingRatherThanASiblingsOrAnOlderReleases() throws {
        let body = try Self.body("edge-enterprise-beta-publishing")
        let older = #",{"ReleaseId":1,"Platform":"MacOS","Architecture":"universal","CVEs":[],"SeverityLevel":"None","ProductVersion":"151.0.4100.1","Artifacts":[{"ArtifactName":"pkg","Location":"https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/0/MicrosoftEdge-151.0.4100.1.pkg","Hash":"\#(String(repeating: "A", count: 64))","HashAlgorithm":"SHA256","SizeInBytes":1}]}"#
        let edited = body
            .replacingOccurrences(of: #""Hash":"\#(Self.stablePkgHash)","#, with: "")
            .replacingOccurrences(of: #""ExpectedExpiryDate":"2027-09-04T23:27:00"}]}]"#,
                                  with: #""ExpectedExpiryDate":"2027-09-04T23:27:00"}"# + older + "]}]")
        #expect(!edited.contains(Self.stablePkgHash))
        #expect(edited.contains("MicrosoftEdge-151.0.4100.1.pkg"))
        #expect(VendorProbeRecipe.extractVersion(from: edited, pattern: try Self.pattern("com.microsoft.edgemac")) == nil)
    }

    /// A hash in some other algorithm is not checked as SHA-256.
    @Test func aNonSHA256HashIsNotRead() throws {
        let body = try Self.body("edge-enterprise-beta-publishing")
        let edited = body.replacingOccurrences(
            of: #""Hash":"\#(Self.stablePkgHash)","HashAlgorithm":"SHA256""#,
            with: #""Hash":"\#(Self.stablePkgHash)","HashAlgorithm":"SHA3-256""#)
        #expect(edited != body)
        #expect(VendorProbeRecipe.extractVersion(from: edited, pattern: try Self.pattern("com.microsoft.edgemac")) == nil)
    }
}

/// Android Studio: the preview feed lists six platforms' files per item, each with
/// its own SHA-256 `checksum`; the website's table lists them by filename. The
/// digest has to be the arm64 dmg's — the file the install patterns read.
struct AndroidStudioDigestTests {
    // Real items from `jb.gg/android-studio-releases-list.json` (2026-10-07),
    // byte-for-byte: Canary 3, the stable Release, RC 2 — in feed order.
    static let canary3 = #"{"date":"October 1, 2026","platformBuild":"262.10968.63","download":[{"size":"1.2 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.2.3/android-studio-rabbit2-canary3-cros.deb","checksum":"5ceb23c2d654cb4be6a8484c028d1b27b26de4661b1cbbc542b3fbecd8aa83dd"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.2.3/android-studio-rabbit2-canary3-mac_arm.dmg","checksum":"67a98376e8b8eb19b72b54ebd66a207d4dbc54287a4f502f267f7155510a73c1"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.2.3/android-studio-rabbit2-canary3-mac.dmg","checksum":"87c4d7d2a3959353bc214ab4b719432e8223e5d9387a8859e9c554aa55b728b4"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.2.3/android-studio-rabbit2-canary3-windows.exe","checksum":"6cee39f763a1d36f15099af531d0e300f3b2e63732b7ea6eb4a32dd26e14deae"},{"size":"1.6 GB","link":"https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.2.2.3/android-studio-rabbit2-canary3-linux.tar.gz","checksum":"23505491b8241108e8c73851054799bf3fa01b810cc60af8159289cbb9b4eb61"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.2.2.3/android-studio-rabbit2-canary3-windows.zip","checksum":"15b3846603e4c7934883aece0d941b58f0e3bb0916897f67eff4fbc6d222706e"}],"build":"AI-262.10968.63.2622.16488178","platformVersion":"2026.2.3","name":"Android Studio Rabbit 2 | 2026.2.2 Canary 3","channel":"Canary","version":"2026.2.2.3"}"#
    static let release = #"{"date":"October 1, 2026","platformBuild":"262.9437.185","download":[{"size":"1.2 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.8/android-studio-rabbit1-cros.deb","checksum":"125383bc804e07ad7111dc68cbb67b8ddeb92880b98c663cdb9e71202171632d"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.8/android-studio-rabbit1-mac_arm.dmg","checksum":"16d4a0f8a52413b51869fc18d5bdcdf9cecd38615cd7bb7cf14d51b99d2fef54"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.8/android-studio-rabbit1-mac.dmg","checksum":"9284f783ac1096af1e0612173d8b5e17693fe32cc44ef8f6bec5d1367e00c40e"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.8/android-studio-rabbit1-windows.exe","checksum":"4c26f92e0e78adb1381c9a76597dbd5f6bce13d2ff2bf88cd2b57d425d685f3d"},{"size":"1.6 GB","link":"https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.2.1.8/android-studio-rabbit1-linux.tar.gz","checksum":"f8775c67cf899d9133712a2d7ee3ef7231e07fb16dbe0544c47e5f5babd5931b"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.2.1.8/android-studio-rabbit1-windows.zip","checksum":"6e83e7ce3e0a76c4e8e78d98eb5ef538cbc9fb386c745bda425fc0bacb9de6d4"}],"build":"AI-262.9437.185.2621.16467767","platformVersion":"2026.2.1","name":"Android Studio Rabbit 1 | 2026.2.1","channel":"Release","version":"2026.2.1.8"}"#
    static let rc2 = #"{"date":"September 28, 2026","platformBuild":"262.9437.185","download":[{"size":"1.2 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.7/android-studio-rabbit1-rc2-cros.deb","checksum":"d0f11a36bd3edc82110cd4057fc579b75b7e6691a41b01fe7955724515156691"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.7/android-studio-rabbit1-rc2-mac_arm.dmg","checksum":"8fb71c27a0feb96384aa951512eba5bf58e39c1a8e8f6392fd20218f255176ca"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.7/android-studio-rabbit1-rc2-mac.dmg","checksum":"05de967d4a1bc5d1fab88736ba0ea640581c79c7f8369704926506842edca844"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.7/android-studio-rabbit1-rc2-windows.exe","checksum":"d41ccc25ed49dbfc80255f6e0c82f22282a08e56a66d35d1b7f5496cf2a1f3bf"},{"size":"1.6 GB","link":"https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.2.1.7/android-studio-rabbit1-rc2-linux.tar.gz","checksum":"c08da174c858976ccf83c494dfe0f8d77ca016aac141f60c6f5ca33ac0d0d5a0"},{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/ide-zips/2026.2.1.7/android-studio-rabbit1-rc2-windows.zip","checksum":"27b4cd1eb8aded87a5fd74c72b7a95314ce4b2d4891ced7329e3e52643e3a33f"}],"build":"AI-262.9437.185.2621.16444166","platformVersion":"2026.2.1","name":"Android Studio Rabbit 1 | 2026.2.1 RC 2","channel":"RC","version":"2026.2.1.7"}"#

    static func feed(_ items: [String]) -> String {
        #"{"content":{"item":["# + items.joined(separator: ",") + "]}}"
    }

    static func recipe(_ channel: ReleaseChannel) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.google.android.studio" && $0.channel == channel
        })
    }

    @Test func everyChannelChecksSHA256Hex() throws {
        for channel in [ReleaseChannel.stable, .canary, .beta] {
            let spec = try #require(try Self.recipe(channel).install)
            #expect(spec.checksumPattern != nil, "\(channel)")
            #expect(spec.checksumFormat == .sha256Hex, "\(channel)")
        }
    }

    /// End to end through the probe: each preview channel's digest is the arm64
    /// dmg's of the item it resolved — Canary's Canary 3, Beta's RC 2 (never the
    /// Canary) — and not the Intel `-mac.dmg` listed right after it.
    @Test func eachPreviewChannelGetsItsResolvedItemsArm64Digest() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.feed([Self.canary3, Self.release, Self.rc2]))
        defer { server.stop() }

        let canary = await VendorProbeSource().probeDiagnostic(try Self.recipe(.canary).with(url: server.url))
        #expect(canary.remote?.downloadURL?.lastPathComponent == "android-studio-rabbit2-canary3-mac_arm.dmg")
        #expect(canary.remote?.expectedSHA256 == "67a98376e8b8eb19b72b54ebd66a207d4dbc54287a4f502f267f7155510a73c1")
        #expect(canary.remote?.expectedSHA512 == nil)
        #expect(!canary.warnings.contains(.checksumPatternNoMatch))

        let beta = await VendorProbeSource().probeDiagnostic(try Self.recipe(.beta).with(url: server.url))
        #expect(beta.remote?.downloadURL?.lastPathComponent == "android-studio-rabbit1-rc2-mac_arm.dmg")
        #expect(beta.remote?.expectedSHA256 == "8fb71c27a0feb96384aa951512eba5bf58e39c1a8e8f6392fd20218f255176ca")
    }

    @Test func keyOrderInsideTheDownloadObjectDoesNotMatter() throws {
        let pattern = try #require(try Self.recipe(.canary).install?.checksumPattern)
        let reordered = Self.canary3.replacingOccurrences(
            of: #"{"size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.2.3/android-studio-rabbit2-canary3-mac_arm.dmg","checksum":"67a98376e8b8eb19b72b54ebd66a207d4dbc54287a4f502f267f7155510a73c1"}"#,
            with: #"{"checksum":"67a98376e8b8eb19b72b54ebd66a207d4dbc54287a4f502f267f7155510a73c1","size":"1.5 GB","link":"https://edgedl.me.gvt1.com/android/studio/install/2026.2.2.3/android-studio-rabbit2-canary3-mac_arm.dmg"}"#)
        #expect(reordered != Self.canary3)
        #expect(VendorProbeRecipe.extractVersion(from: reordered, pattern: pattern)
            == "67a98376e8b8eb19b72b54ebd66a207d4dbc54287a4f502f267f7155510a73c1")
    }

    /// The arm64 dmg's object carries no `checksum`: nothing is read — not the
    /// Intel dmg's beside it, and (when slicing falls back to the whole feed) not a
    /// later item's arm64 dmg either.
    @Test func anArm64DmgWithoutAChecksumReadsNothing() throws {
        let pattern = try #require(try Self.recipe(.canary).install?.checksumPattern)
        let item = Self.canary3.replacingOccurrences(
            of: #"canary3-mac_arm.dmg","checksum":"67a98376e8b8eb19b72b54ebd66a207d4dbc54287a4f502f267f7155510a73c1""#,
            with: #"canary3-mac_arm.dmg""#)
        #expect(!item.contains("67a98376"))
        #expect(VendorProbeRecipe.extractVersion(from: item, pattern: pattern) == nil)
        #expect(VendorProbeRecipe.extractVersion(from: Self.feed([item, Self.rc2]), pattern: pattern) == nil)
    }

    // The developer.android.com/studio download table and its arm64 link, trimmed
    // from the 2026-10-07 page: the Intel row comes first, then arm64; the
    // SDK-tools table and the download dialogs follow.
    static let studioPage = #"""
      <table class="download">
        <tr>
          <th>Platform</th>
          <th>Android Studio package</th>
          <th>Size</th>
          <th>SHA-256 checksum</th>
        </tr>
        <tr>
          <td>Mac<br>(64-bit)</td>
          <td>
          <button class="devsite-dialog-button button-white button-regular"
                data-modal-dialog-id="studio_mac_bundle_download"
                >android-studio-rabbit1-mac.dmg</button>
          </td>
          <td>1.5 GB</td>
          <td>9284f783ac1096af1e0612173d8b5e17693fe32cc44ef8f6bec5d1367e00c40e</td>
        </tr>
        <tr>
          <td>Mac<br>(64-bit, ARM)</td>
          <td>
          <button class="devsite-dialog-button button-white button-regular"
                data-modal-dialog-id="studio_mac_arm_bundle_download"
                >android-studio-rabbit1-mac_arm.dmg</button>
          </td>
          <td>1.5 GB</td>
          <td>16d4a0f8a52413b51869fc18d5bdcdf9cecd38615cd7bb7cf14d51b99d2fef54</td>
        </tr>
      </table>
      <table class="download">
        <tr>
          <th>Platform</th>
          <th>SDK tools package</th>
          <th>Size</th>
          <th>SHA-256 checksum</th>
        </tr>
        <tr>
          <td><nobr>Mac</nobr></td>
          <td>
            <button class="devsite-dialog-button button-white button-regular"
                data-modal-dialog-id="sdk_mac_download"
                >commandlinetools-mac-15859902_latest.zip</button>
          </td>
          <td>155.7 MB</td>
          <td>\#(String(repeating: "b", count: 64))</td>
        </tr>
      </table>
              <a class="button button-primary
                   devsite-dialog-close gc-analytics-event"
                   data-category="studio_mac_arm_bundle_download" data-action="download"
                   href="https://edgedl.me.gvt1.com/android/studio/install/2026.2.1.8/android-studio-rabbit1-mac_arm.dmg"
                   id="agree-button__studio_mac_arm_bundle_download"
                >Download Android Studio Rabbit 1 | 2026.2.1
              </a>
                <p><em>android-studio-rabbit1-mac_arm.dmg</em></p>
    """#

    /// Stable reads the arm64 row — the file its link downloads — not the Intel row
    /// above it.
    @Test func stableReadsTheArm64RowOfTheChecksumTable() throws {
        let recipe = try Self.recipe(.stable)
        let pattern = try #require(recipe.install?.checksumPattern)
        #expect(VendorProbeRecipe.extractVersion(from: Self.studioPage, pattern: pattern)
            == "16d4a0f8a52413b51869fc18d5bdcdf9cecd38615cd7bb7cf14d51b99d2fef54")
        guard case .bodyPattern(let urlPattern) = try #require(recipe.install).urlSource else {
            Issue.record("stable install is no longer a bodyPattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(from: Self.studioPage, pattern: urlPattern)?
            .hasSuffix("/android-studio-rabbit1-mac_arm.dmg") == true)
    }

    /// No arm64 row in the Studio table: nothing is read, not an arm64-looking row
    /// that only appears in some later table.
    @Test func stableReadsNothingWhenTheStudioTableHasNoArm64Row() throws {
        let pattern = try #require(try Self.recipe(.stable).install?.checksumPattern)
        let page = Self.studioPage
            .replacingOccurrences(of: ">android-studio-rabbit1-mac_arm.dmg</button>", with: ">android-studio-rabbit1-linux.tar.gz</button>")
            .replacingOccurrences(of: ">commandlinetools-mac-15859902_latest.zip</button>", with: ">android-studio-rabbit1-mac_arm.dmg</button>")
        #expect(page.contains(">android-studio-rabbit1-mac_arm.dmg</button>"))
        #expect(VendorProbeRecipe.extractVersion(from: page, pattern: pattern) == nil)
    }
}
