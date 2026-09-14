import Foundation

enum org_gnome_Meld {
    static let set = AppRecipeSet(
        family: "org-gnome-Meld",
        probes: [
        // History: docs/app-audits/org-gnome-Meld.md#历史与实测
        // Meld — TRAP: upstream GNOME Meld (gitlab.gnome.org) is ahead of the
        // version any macOS build wraps (when checked, 2026-08-16 and 2026-09-14;
        // History has the versions), but there is no official macOS build; the
        // only one is a third-party repack by dehesselle
        // (`gitlab.com/dehesselle/meld_macos`) that stalled the wrapped app at an
        // older upstream release and instead versions ITS OWN repacks with a
        // trailing `+<build>` (e.g. `v3.22.3+105`). Reading gitlab.gnome.org would
        // report an update this macOS build can never actually install.
        // Probed `gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases`
        // (History has the response), whose default order
        // (`order_by=released_at&sort=desc`, confirmed by the response's own `Link`
        // header) puts the newest release first, so first-match is correct without
        // `selectHighest`.
        //
        // The mounted arm64 dmg's `CFBundleShortVersionString` is `3.22.3` and
        // `CFBundleVersion` is `105` — i.e. the tag's two halves map to the
        // bundle's two DIFFERENT version fields. Three separate releases share
        // marketing `3.22.3` with different builds (`+96`, `+100`, `+105`, all
        // 2025 repack-only bumps with no upstream version change) — comparing
        // only the marketing half would silently miss those updates (the
        // "folded-build" gap). So `versionPattern` captures ONLY the build
        // integer and `versionIsBuild` routes it against `CFBundleVersion`;
        // `displayVersionPattern` captures the full `3.22.3+105` string so the
        // row still shows the vendor's own scheme instead of a bare `105`.
        // The feed carries no base64 SHA-512 (GitLab's `x-checksum-sha256`
        // response header is hex, and isn't in the body anyway), so no
        // `checksumPattern`; the downloaded arm64 dmg's sha256 was independently
        // verified to match that header byte-for-byte, but that's outside what
        // `checksumPattern` can express (base64 SHA-512 only).
        // Bundle identity: `org.gnome.Meld`, notarized Developer ID, Team
        // SW3D6BB6A6 (Rene de Hesselle) — `spctl` accepted it as "Notarized
        // Developer ID" (checked 2026-08-16).
        VendorProbeRecipe(
            bundleID: "org.gnome.Meld",
            url: URL(string: "https://gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases")!,
            mode: .responseBody,
            versionPattern: #""tag_name"\s*:\s*"v[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)""#,
            downloadURL: URL(string: "https://gitlab.com/dehesselle/meld_macos/-/releases"),
            changelogURL: URL(string: "https://gitlab.com/dehesselle/meld_macos/-/releases"),
            versionIsBuild: true,
            displayVersionPattern: #""tag_name"\s*:\s*"v([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""name"\s*:\s*"Meld-[0-9.+]+_arm64\.dmg"[^}]*"direct_asset_url"\s*:\s*"([^"]+)""#),
                kind: .dmg)),
        ])
}
