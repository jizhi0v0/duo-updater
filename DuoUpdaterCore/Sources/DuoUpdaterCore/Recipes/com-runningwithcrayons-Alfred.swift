import Foundation

enum com_runningwithcrayons_Alfred {
    static let set = AppRecipeSet(
        family: "com-runningwithcrayons-Alfred",
        probes: [
        // Alfred, PRE-RELEASE channel — the missing half of the pair below.
        //
        // A user who ticks "Pre-releases" in Alfred's own Update preferences is
        // resolved to `.beta` by `AlfredChannel`, and the channel guard then refuses
        // the stable recipe — correctly, but with nothing left to answer, so the row
        // read "Failed" indefinitely. (The Sparkle path couldn't cover for it: that
        // binding pointed at `alfredapp.com/appcast.xml` and `/prerelease.xml`, both
        // of which now 404 — the unreadable `SparkleError error 0` in the logs.)
        //
        // Same plist shape as stable, different endpoint. The two frequently serve
        // the SAME build — both were 5.7.3 (2320) here — so being on beta doesn't by
        // itself mean a newer version is on offer.
        VendorProbeRecipe(
            bundleID: AlfredChannel.bundleID,
            url: URL(string: "https://www.alfredapp.com/app/update5/prerelease.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9]+(?:\.[0-9]+)+)</string>"#,
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>location</key>\s*<string>(https://[^<]+\.tar\.gz)</string>"#),
                kind: .tarGz),
            channel: .beta),

        // Alfred 5 — Sparkle PLIST appcast (not RSS). Alfred has no Info.plist
        // SUFeedURL (the feed is configured in Alfred's own Preferences), so it
        // reaches us here rather than via SparkleAppcastSource — same situation as
        // the Codex/OrbStack neighbors. The manifest is a single-release plist: the
        // top-level <key>version</key><string> is the latest build (5.7.3),
        // unambiguous vs the descending "## Alfred X.Y.Z" history inside
        // changelogdata. One release listed → first match is correct.
        //
        // One-click added 2026-08-08 after verifying what `location` points at: the
        // tarball holds `Alfred 5.app` at its root, whose bundle id
        // (`com.runningwithcrayons.Alfred`) and Team (`XZZXE9SED4`) match the
        // installed copy, and `spctl` reports "Notarized Developer ID". That URL
        // carries the version, so it's read from the same body rather than fixed.
        // Alfred still self-updates on its own; this only means the row can too.
        VendorProbeRecipe(
            bundleID: AlfredChannel.bundleID,
            url: URL(string: "https://www.alfredapp.com/app/update5/general.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>version</key>\s*<string>([0-9][0-9.]*)</string>"#,
            changelogURL: URL(string: "https://www.alfredapp.com/changelog/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>location</key>\s*<string>(https://[^<]+\.tar\.gz)</string>"#),
                kind: .tarGz)),
        ],
        channelProofs: [
        // Alfred serves stable and pre-release from two endpoints that frequently
        // carry the SAME build (both were 5.7.3 (2320) on 2026-08-09), and the
        // tarball name never mentions a channel — only the endpoint can prove it.
        // Endpoint-scoped for the same reason as IntelliJ EAP: this recipe's
        // install `bodyPattern` is byte-identical to the stable Alfred recipe's
        // (same plist shape, different endpoint) and its `versionPattern` differs
        // only in strictness — neither names a channel. So the endpoint is not
        // merely the best evidence, it is the only evidence there is, and the
        // proof says so.
        ChannelProofKey("com.runningwithcrayons.Alfred", .beta):
            .recipeAnchor(#"prerelease\.xml"#, in: ["url"]),
        ])
}
