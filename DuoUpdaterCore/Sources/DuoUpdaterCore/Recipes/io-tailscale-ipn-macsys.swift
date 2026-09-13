import Foundation

enum io_tailscale_ipn_macsys {
    static let set = AppRecipeSet(
        family: "io-tailscale-ipn-macsys",
        probes: [
        // Tailscale — official package index. `MacZipsVersion` is the macsys
        // build (top-level `Version` is the Linux/Windows train — wrong here).
        // Three public tracks share `io.tailscale.ipn.macsys`; the channel gate
        // routes each install to its own endpoint per the app's opt-in toggle
        // (see `TailscaleChannel`). `pkgs.tailscale.com/rc` 404s, but that's just
        // the wrong guessed path — the real release-candidate track lives at
        // `pkgs.tailscale.com/release-candidate/` (verified 2026-08-21: HTTP 200,
        // same JSON shape as stable/unstable below).
        VendorProbeRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            url: URL(string: "https://pkgs.tailscale.com/stable/?mode=json")!,
            mode: .responseBody,
            versionPattern: #""MacZipsVersion"\s*:\s*"([0-9.]+)""#,
            changelogURL: URL(string: "https://tailscale.com/changelog"),
            // JSON gives only the pkg filename → resolve against the base dir.
            // pkg → opened in the system installer. Signed by Tailscale W5364U7YZB.
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""universal-package"\s*:\s*"(Tailscale-[^"]+\.pkg)""#,
                    base: URL(string: "https://pkgs.tailscale.com/stable/")!),
                kind: .pkg),
            channel: .stable),
        // Tailscale release candidate — same JSON shape on the
        // `/release-candidate/` track. Only reached when the install opted in via
        // `RCUpdatesEnabled`; the same Tailscale-signed pkg path.
        //
        // On version numbers: per Tailscale's own docs the RC track carries the
        // *next patch of the current stable line*, so it normally reads equal to
        // stable (right after a promotion — both were 1.102.3 on 2026-08-21) or
        // ahead of it (while a patch is being tested), not behind. Either way
        // nothing here depends on that: `VersionComparator.isNewer` requires
        // strictly-greater, so an equal or lower RC version offers no update
        // rather than proposing a downgrade.
        VendorProbeRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            url: URL(string: "https://pkgs.tailscale.com/release-candidate/?mode=json")!,
            mode: .responseBody,
            versionPattern: #""MacZipsVersion"\s*:\s*"([0-9.]+)""#,
            changelogURL: URL(string: "https://tailscale.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""universal-package"\s*:\s*"(Tailscale-[^"]+\.pkg)""#,
                    base: URL(string: "https://pkgs.tailscale.com/release-candidate/")!),
                kind: .pkg),
            channel: .rc),
        // Tailscale unstable — same JSON shape on the `/unstable` track (odd
        // minor, e.g. 1.99.x). Only reached when the install opted in via
        // `UnstableUpdatesEnabled`; the same Tailscale-signed pkg path.
        VendorProbeRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            url: URL(string: "https://pkgs.tailscale.com/unstable/?mode=json")!,
            mode: .responseBody,
            versionPattern: #""MacZipsVersion"\s*:\s*"([0-9.]+)""#,
            changelogURL: URL(string: "https://tailscale.com/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #""universal-package"\s*:\s*"(Tailscale-[^"]+\.pkg)""#,
                    base: URL(string: "https://pkgs.tailscale.com/unstable/")!),
                kind: .pkg),
            channel: .unstable),
        ],
        changelogs: [
        // Tailscale — official changelog page. Entries are `<article id="YYYY-MM-DD">`
        // elements; each date group may contain a macOS client entry AND service-only
        // entries (Kubernetes Operator, container image, etc.). The pattern matches only
        // articles whose body contains `<h3 class="changelog-title…">Tailscale v…</h3>`,
        // so service-only dates are silently skipped. The `date` group is the article id
        // (ISO date string). Items are `<li data-change="…">` inside the client div;
        // the body lookahead stops before the next `<div id=` (another entry in the same
        // date group) or the closing `</article>`.
        ChangelogRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            source: URL(string: "https://tailscale.com/changelog")!,
            entryPattern:
                #"<article id="(?<date>[^"]+)"[^>]*>.*?"#
                + #"<h3 class="changelog-title[^"]*">Tailscale v(?<version>[^<]+)</h3>"#
                + #"(?<body>.*?)(?=<div id="|</article>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ],
        channelProofs: [
        ChannelProofKey("io.tailscale.ipn.macsys", .unstable): .artifact(#"/unstable/"#),
        ChannelProofKey("io.tailscale.ipn.macsys", .rc): .artifact(#"/release-candidate/"#),
        ])
}
