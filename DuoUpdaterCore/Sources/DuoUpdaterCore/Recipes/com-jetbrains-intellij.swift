import CoreFoundation
import Foundation

enum com_jetbrains_intellij {
    private static let eapBuild = #"[0-9]+(?:\.[0-9]+){1,3}"#

    // Match only the old EAP bundle's licensing class. Restrict the body seen
    // by the regular probe readers to the selected build and its own Apple
    // Silicon DMG. Unknown licensing and conflicting rows for a build cannot
    // authorize it. An ambiguous or absent DMG leaves detection available.
    static func eapReleaseBody(from body: String) -> String? {
        guard let response = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let entries = response["IIU"] as? [Any]
        else { return nil }
        let records = entries.compactMap { entry -> (String, [String: Any])? in
            guard let fields = entry as? [String: Any],
                  let build = fields["build"] as? String,
                  build.range(of: #"\A\#(eapBuild)\z"#, options: .regularExpression) != nil
            else { return nil }
            return (build, fields)
        }
        let builds = Dictionary(grouping: records, by: \.0)
        let eapBuilds = builds.filter { _, rows in
            rows.allSatisfy { _, fields in
                guard let license = fields["licenseRequired"] as? NSNumber,
                      CFGetTypeID(license) == CFBooleanGetTypeID()
                else { return false }
                return !license.boolValue
            }
        }
        guard let (build, rows) = eapBuilds.max(by: {
            VersionComparator.isNewer($1.key, than: $0.key)
        }) else { return nil }

        var selected = ["build": build]
        let artifact = "https://download.jetbrains.com/idea/idea-\(build)-aarch64.dmg"
        if rows.count == 1,
           let downloads = rows[0].1["downloads"] as? [String: Any],
           let mac = downloads["macM1"] as? [String: Any],
           mac["link"] as? String == artifact {
            selected["url"] = artifact
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: selected, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static let set = AppRecipeSet(
        family: "com-jetbrains-intellij",
        probes: [
        // History: docs/app-audits/com-jetbrains-intellij.md#历史与实测
        // IntelliJ IDEA — JetBrains data services. The `YYYY.` prefix is what keeps
        // this off the 2-component `majorVersion` field; the segment count must NOT
        // be pinned: JetBrains ships four-component versions too (e.g.
        // `"version": "2026.2.0.1"`). Accept one to three segments after the
        // year. Only consulted when Toolbox isn't managing it (a website install);
        // the same JSON carries the aarch64 DMG direct link, so we install in place.
        // No inline sha256 (the API gives only a checksum *link*), so we lean on the
        // mandatory Team ID signature gate — same posture as VLC's DMG. Apple
        // Silicon (macM1) only.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]{4}(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg)),

        // IntelliJ IDEA EAP — type=eap covers both EAP-licensed builds and
        // point-release Previews signed with the stable id. Read the list so
        // the current Preview cannot hide the latest EAP-licensed build.
        // Compare CFBundleVersion (without the IU- prefix) since multiple EAP
        // releases share the same marketing version. Only website-managed
        // copies are eligible for this recipe's in-place install.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij-EAP",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&type=eap")!,
            mode: .jetBrainsIdeaEAP,
            versionPattern: #""build"\s*:\s*"(\#(eapBuild))""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/"),
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""url"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg),
            channel: .preview),
        ],
        changelogs: [
        // IntelliJ IDEA — same JetBrains data-services API as Toolbox (`IIU`
        // product code, stable releases only via `type=release`). Structured decode
        // (`StructuredChangelogDecoder.decodeJetBrainsProductReleases`): the old
        // regex path read `whatsnew` as raw JSON-escaped text, where an embedded
        // `\n` is a two-character escape a hand-written item pattern can silently
        // mis-anchor on (the ChatWise-class bug this decoder family exists to avoid).
        // `Decodable` unescapes the JSON string for us, so the decoder walks real
        // HTML instead: `whatsnew` is a lead `<p>` summary then `<ul><li>` bullets,
        // and only the `<li>` bullets count as discrete changes — the lead `<p>`
        // is boilerplate ("IntelliJ IDEA X is out with…"). A hotfix release with no
        // `<li>` at all (its content is plain `<p>` prose, or just a pointer to the
        // release notes) yields zero items and is skipped, same as the regex did.
        ChangelogRecipe(
            bundleID: "com.jetbrains.intellij",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&type=release")!,
            maxEntries: 20,
            structuredFormat: .jetBrainsProductReleases),
        ],
        channelProofs: [
        // The URL selects the prerelease list. The mode further scopes it to
        // the EAP licensing class before either reader sees a build or DMG.
        ChannelProofKey("com.jetbrains.intellij-EAP", .preview):
            .recipeAnchor(#"(?:[?&]type=eap(?:&|$)|^jetBrainsIdeaEAP$)"#, in: ["url", "mode"]),
        ])
}
