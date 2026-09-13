import Foundation

enum com_microsoft_edgemac {
    static let set = AppRecipeSet(
        family: "com-microsoft-edgemac",
        probes: [
        // Microsoft Edge — Stable / Beta / Dev. One enterprise endpoint lists all
        // products; each per-channel pattern scopes to that Product's first
        // (newest) MacOS release. Distinct bundle ids (`…edgemac[.Beta/.Dev]`) so
        // the channel gate routes each install to its own version. Edge self-updates
        // via Microsoft AutoUpdate; like Office there's no rollout-jump risk (the
        // CDN serves the GA build), so Stable gets a one-click pkg from the official
        // "latest" fwlink (linkid=2093504 → MicrosoftEdge-<ver>.pkg, same 4-component
        // ProductVersion scheme as detection). Beta/Dev ALSO get a one-click pkg,
        // but from a different place than Stable: the same enterprise JSON lists
        // each channel's MacOS pkg under `Artifacts[].Location`, so we scope the
        // install pattern to that Product's first (newest) MacOS release — exactly
        // parallel to the versionPattern — and the `\.pkg` anchor skips the sibling
        // `.plist` artifact. The pkg is notarized under Microsoft's Developer ID
        // Installer (UBF8T346G9), same as Stable, so it clears the signature gate.
        // The channel gate still routes each pkg to its own bundle id. (Edge Canary
        // isn't carried by this enterprise API, so it stays "unknown" rather than
        // mis-served.)
        //
        // Release notes: Microsoft renamed the PER-CHANNEL enterprise docs pages
        // from `microsoft-edge-relnotes-<channel>` to
        // `microsoft-edge-relnote-<channel>` (singular) and the old spellings now
        // 404 — see issue #107. Not a blanket rename, and worth knowing before
        // guessing at any other page in that section: the security notes are still
        // `microsoft-edge-relnotes-security`, plural.
        //
        // Dev gets NO `changelogURL` at all, and that is the measured answer
        // rather than a guess. `learn.microsoft.com/en-us/deployedge/toc.json`
        // (2026-08-28) carries eight `relnote*` paths — Beta, Stable, Mobile Beta,
        // Mobile Stable, three `-archive-` companions, and the security page — and
        // not one of them is Dev. Four plausible Dev spellings all 404
        // (`…relnote-dev-channel`, `…relnotes-dev-channel`, `…relnote-dev`,
        // `…relnote-archive-dev-channel`), and Learn's own search API returns Beta,
        // Security and the release schedule for "Edge Dev channel release notes".
        // Microsoft stopped publishing Dev channel notes; pointing the button at
        // Beta's or Stable's page would show a Dev user another train's changes,
        // which is worse than showing none (same call as Thunderbird Daily below).
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Stable"(?:(?!"Product"\s*:)[\s\S])*?"Platform"\s*:\s*"MacOS"(?:(?!"Product"\s*:)[\s\S])*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoft.com/edge/download"),
            changelogURL: URL(
                string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnote-stable-channel"),
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=2093504")!),
                kind: .pkg)),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Beta",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Beta"(?:(?!"Product"\s*:)[\s\S])*?"Platform"\s*:\s*"MacOS"(?:(?!"Product"\s*:)[\s\S])*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            // How this vendor signals "no build on this track right now": the
            // product's block is present and contains no MacOS release at all.
            // Consulted only after the version pattern already missed, so a
            // publishing track can never be talked into looking closed.
            //
            // Measured 2026-09-10 on the live body, both directions: with Beta's
            // MacOS list empty this matches and Dev/Stable do not; two hours later,
            // with 154.0.4258.9 back under Beta, it stops matching.
            //
            // ⚠️ **Beta only, on purpose.** `VendorInstallTests` builds its dormancy
            // exemption from the *presence* of this declaration, not from whether it
            // matches, so every channel that declares one is permanently exempt from
            // "resolved no installer URL" — a recipe that genuinely breaks there
            // reports "dormant" and passes. Beta is the one track measured dormant,
            // so it is the only one that gets the exemption; Dev and Stable keep
            // failing loudly, and the price is that the first day either of them goes
            // quiet the sweep reds once. That is the safe direction.
            //
            // ⚠️ The trailing `(?:"Product"\s*:|$)` needs another product after this
            // one, or the very end of the body, to anchor on. Today the feed orders
            // them Dev, Beta, Stable, EdgeUpdate, Policy, so every channel has
            // something after it; a future feed that puts a channel last with other
            // trailing content would read its empty track as breakage instead. Loud,
            // not silent, so it stays a note rather than a guard.
            trackClosedPattern: #"(?s)"Product"\s*:\s*"Beta"(?:(?!"Platform"\s*:\s*"MacOS")(?!"Product"\s*:)[\s\S])*?(?:"Product"\s*:|$)"#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            changelogURL: URL(
                string: "https://learn.microsoft.com/deployedge/microsoft-edge-relnote-beta-channel"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(?s)"Product"\s*:\s*"Beta"(?:(?!"Product"\s*:)[\s\S])*?"Platform"\s*:\s*"MacOS"(?:(?!"Product"\s*:)[\s\S])*?"Location"\s*:\s*"(https://[^"]+\.pkg)""#),
                kind: .pkg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.microsoft.edgemac.Dev",
            url: URL(string: "https://edgeupdates.microsoft.com/api/products?view=enterprise")!,
            mode: .responseBody,
            versionPattern: #"(?s)"Product"\s*:\s*"Dev"(?:(?!"Product"\s*:)[\s\S])*?"Platform"\s*:\s*"MacOS"(?:(?!"Product"\s*:)[\s\S])*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})""#,
            downloadURL: URL(string: "https://www.microsoftedgeinsider.com/download"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(?s)"Product"\s*:\s*"Dev"(?:(?!"Product"\s*:)[\s\S])*?"Platform"\s*:\s*"MacOS"(?:(?!"Product"\s*:)[\s\S])*?"Location"\s*:\s*"(https://[^"]+\.pkg)""#),
                kind: .pkg),
            channel: .dev),
        ],
        channelProofs: [
        ChannelProofKey("com.microsoft.edgemac.Beta", .beta): .artifact(#"MicrosoftEdgeBeta-"#),
        ChannelProofKey("com.microsoft.edgemac.Dev", .dev): .artifact(#"MicrosoftEdgeDev-"#),
        ])
}
