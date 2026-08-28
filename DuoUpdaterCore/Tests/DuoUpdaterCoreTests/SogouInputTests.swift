import Foundation
import Testing
@testable import DuoUpdaterCore

/// 搜狗输入法 reads the vendor's own update endpoint, which is CONDITIONAL: it
/// answers "given this client's version, what should it upgrade to", not "what is
/// the latest". Both of its answers are real responses, captured verbatim
/// 2026-08-28, because the difference between them is the entire recipe.

/// What the endpoint says to a client that is already current. `1.0.0.1` is a
/// sentinel meaning "stay put" — below every build the vendor has ever shipped —
/// and reading it as a version is the mistake this recipe is shaped to prevent.
///
/// Byte-verbatim, 188 bytes, including the mixed line endings: the server writes
/// LF down to `md5=` and CRLF after it. Written with explicit escapes rather than
/// a pretty multiline literal, because the escapes ARE the fixture — a tidied
/// copy would stop exercising the `\n` anchors the pattern is built on.
private let sogouNoUpdateFixture =
    "[product0]\npid=0\nversion=1.0.0.1\nurl=http://pinyin.sogou.com/mac/\nmd5=\n"
    + "pkg_url=http://pro.cdn.ime.sogou.com/SogouInput_V1.0.0.1.ins\r\n"
    + "pkg_md5=eac14135ade15c84ceb6aef491cc0c3d\r\n\n[end]\nend=1\n"

/// What it says to an out-of-date client — which is what the probe always is,
/// because it pins `v=0.0.0.1`. Byte-verbatim, 252 bytes.
///
/// The payload host alternates between `pro.cdn` and `pro.cdn2` request to
/// request; this pins the one that came back on the capture. Nothing reads it —
/// the pattern only needs the key's presence — but it is why "the response is
/// stable" is a claim about the VERSION and not about the bytes.
private let sogouUpdateFixture =
    "[product0]\npid=0\nversion=6.24.1.11676\nurl=http://pinyin.sogou.com/mac/\nmd5=\n"
    + "update_pack_url=http://pro.cdn2.ime.sogou.com/autosetup6.24.1.11676_V10003_20260715_223833.zip\r\n"
    + "update_pack_md5=654bd06d7df44e2237e0c61fab08477b\r\nupdate_notice=0\r\n\n[end]\nend=1\n"

private func sogouRecipe() throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.sogou.inputmethod.sogou" })
}

@Suite struct SogouInputTests {

    /// The version the endpoint names is the bundle's own string, four segments and
    /// all — so there is nothing to derive, translate or trim on either side. That
    /// is why this source beats the changelog page, which publishes three segments
    /// and would have needed the installed version cut down to compare at all.
    @Test func theEndpointNamesTheBundlesOwnVersionString() throws {
        let recipe = try sogouRecipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: sogouUpdateFixture, pattern: recipe.versionPattern) == "6.24.1.11676")
        // Four segments, which is the property that makes this source better than
        // the changelog page: the page publishes three, so comparing against it
        // needed the installed version trimmed, and a respin moving only the
        // fourth segment was invisible. Asserted on what the pattern actually
        // extracted rather than on a literal compared with itself — the version
        // this test is about has to come out of the fixture, or the test proves
        // nothing about the recipe.
        let extracted = try #require(VendorProbeRecipe.extractVersion(
            from: sogouUpdateFixture, pattern: recipe.versionPattern))
        #expect(extracted.split(separator: ".").count == 4)
        #expect(extracted.allSatisfy { $0.isNumber || $0 == "." })
    }

    /// The sentinel must not be readable as a version. Requiring `update_pack_url`
    /// to follow it makes that structural rather than a magnitude argument — and a
    /// `1.0.0.1` reported as the latest release would read as a downgrade from
    /// every install in existence.
    ///
    /// This is the response the probe would get if its pinned `v` ever stopped
    /// being older than the newest build, which is why `v` is pinned at `0.0.0.1`
    /// rather than at some real past release.
    @Test func theNoUpdateSentinelIsNeverReadAsAVersion() throws {
        let recipe = try sogouRecipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: sogouNoUpdateFixture, pattern: recipe.versionPattern) == nil)
    }

    /// The response is `[product0]` … `[end]` with a `pid=0` in it — a shape that
    /// anticipates more than one product, even though no request tried against the
    /// live server produced one. So the span between `version=` and
    /// `update_pack_url=` must not be able to leave its block.
    ///
    /// Measured on this exact concatenation with an unbounded span: the FIRST
    /// block's sentinel version pairs with the SECOND block's payload URL and
    /// `1.0.0.1` is reported as the current release. Being unable to make the
    /// server emit two blocks is not evidence that it never will.
    @Test func aVersionIsNeverPairedWithAnotherBlocksPayload() throws {
        let recipe = try sogouRecipe()
        let twoBlocks = sogouNoUpdateFixture + sogouUpdateFixture
        #expect(VendorProbeRecipe.extractVersion(
            from: twoBlocks, pattern: recipe.versionPattern) == "6.24.1.11676")

        // And a block belonging to some other product, carrying its own payload
        // key, must not be the one we read. `pid` identifying the product is
        // unverified — no request produced a second block — so this pins the
        // guard's behaviour rather than a claim about the server.
        let otherProductFirst = """
        [product1]
        pid=1
        version=9.9.9.9
        url=http://pinyin.sogou.com/mac/
        update_pack_url=http://pro.cdn.ime.sogou.com/something-else.zip

        """.replacingOccurrences(of: "        ", with: "") + sogouUpdateFixture
        #expect(VendorProbeRecipe.extractVersion(
            from: otherProductFirst, pattern: recipe.versionPattern) == "6.24.1.11676")
    }

    /// The probe's request IS the recipe. Drop `sv`, or send `s=1`/`s=2`, and the
    /// endpoint answers with the sentinel instead — measured — so these are not
    /// decoration carried over from the packet capture, they are what makes it
    /// answer at all.
    ///
    /// `r` (the installed copy's distribution channel) is deliberately absent: the
    /// server ignores it (`r=9999` and no `r` answer identically), and a channel
    /// code lifted from one machine's install would be stating something untrue
    /// about every other. `h`, the per-device hash the real client sends, is absent
    /// for a stronger reason — a probe of ours has no business carrying a machine
    /// identifier to a vendor.
    @Test func theProbeAsksAsAnOutOfDateClientAndCarriesNoDeviceIdentity() throws {
        let recipe = try sogouRecipe()
        let query = try #require(URLComponents(url: recipe.url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value })

        // Pinned below anything the vendor can ship, so the request cannot drift
        // into the sentinel branch as releases go by.
        let pinned = try #require(query["v"])
        #expect(VersionComparator.isNewer("6.24.1.11676", than: pinned))
        #expect(VersionComparator.isNewer("1.0.0.1", than: pinned),
                "the pinned version must sit below even the sentinel")

        #expect(query["s"] == "0", "s=1 and s=2 both collapse the answer to the sentinel")
        #expect(query["sv"] != nil, "without sv the endpoint answers with the sentinel")
        #expect(query["h"] == nil, "no per-device identifier may be sent")
        #expect(query["r"] == nil, "the channel code belongs to an install, not to a probe")
        #expect(recipe.url.scheme == "https")
    }

    /// Release notes come from a different host than versions do, on purpose: the
    /// endpoint carries no notes and the marketing site carries no comparable
    /// version. (That the two AGREE — the page's newest entry is 6.24.1, dated the
    /// day this bundle was built — is recorded in the audit document, where a
    /// claim about live content belongs; a unit test cannot hold it.)
    @Test func notesAndVersionsComeFromDifferentSourcesOnPurpose() throws {
        let recipe = try sogouRecipe()
        let changelog = try #require(recipe.changelogURL)
        #expect(changelog.absoluteString == "https://pinyin.sogou.com/mac/update_log.php")
        // Different hosts on purpose: versions come from the vendor's update
        // service, notes from the marketing site.
        #expect(changelog.host != recipe.url.host)
    }

    /// Detection only. The full installer owns two LaunchAgents, a QuickLook
    /// generator and a user-data migration, none of which a `Contents` rotation
    /// touches. The narrower self-update payload is a nested `Contents` archive
    /// plus `pre`/`post`/`switch` scripts, and its `Info.plist` omits the installed
    /// copy's `SGQuDao` channel with reinjection behaviour still unverified. Either
    /// way it needs a dedicated installer, not the generic archive path.
    @Test func sogouStaysDetectionOnly() throws {
        let recipe = try sogouRecipe()
        #expect(recipe.install == nil)
        #expect(UpdatePolicy.isInputMethod(
            URL(fileURLWithPath: "/Library/Input Methods/SogouInput.app")))
    }
}
