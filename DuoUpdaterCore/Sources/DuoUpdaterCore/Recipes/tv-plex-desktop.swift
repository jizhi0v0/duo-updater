import Foundation

enum tv_plex_desktop {
    static let set = AppRecipeSet(
        family: "tv-plex-desktop",
        probes: [
        // Plex (desktop, mac) — Plex's own downloads feed (plex.tv/api/downloads/
        // 6.json is the desktop product; 7.json is the separate PlexHTPC, and the
        // `plex` cask has no livecheck, so this is the clean source). Anchor to the
        // `MacOS` block and capture only the 3-component marketing version
        // (1.112.0), dropping the feed's full `1.112.0.359-0d79a49f`: the app's
        // CFBundleShortVersionString is the bare 1.112.0, and keeping the trailing
        // .359 would compare as +359 over a current install (VersionComparator
        // treats the missing 4th component as 0) — a permanent phantom update. The
        // MacOS block's top-level `version` precedes its `releases` array, so the
        // `[^}]*?` reaches it without crossing a `}` and never grabs the (earlier)
        // Windows block. One-click: the MacOS block's release `url` is the
        // `Plex-<full>-universal.zip` on downloads.plex.tv/plex-desktop/ — anchored
        // to that path so it can't grab the Windows installer. (Plex self-updates via
        // Squirrel; this is the fallback behind the same-Team gate.)
        VendorProbeRecipe(
            bundleID: "tv.plex.desktop",
            url: URL(string: "https://plex.tv/api/downloads/6.json")!,
            mode: .responseBody,
            // NOT widened to a variable segment count like several other probes' patterns. The feed's
            // value is `1.115.0.426-4e960a1d` and this pattern has no closing
            // delimiter, so the capture is bounded only by how many segments it
            // asks for: three yields the marketing version, four would silently
            // start reporting `1.115.0.426` — a build number the app does not
            // report, which is a phantom update. Verified against the live feed
            // 2026-08-19.
            versionPattern: #""MacOS"\s*:\s*\{[^}]*?"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"#,
            downloadURL: URL(string: "https://www.plex.tv/media-server-downloads/?cat=plex+desktop"),
            changelogURL: URL(string: "https://www.plex.tv/media-server-downloads/?cat=plex+desktop"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://downloads\.plex\.tv/plex-desktop/[^"]+/macos/[^"]+universal\.zip)"#),
                kind: .zip)),
        ])
}
