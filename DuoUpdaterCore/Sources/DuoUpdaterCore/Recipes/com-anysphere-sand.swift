import Foundation

enum com_anysphere_sand {
    static let set = AppRecipeSet(
        family: "com-anysphere-sand",
        probes: [
        // History: docs/app-audits/com-anysphere-sand.md#历史与实测
        // Grok Bot — xAI's product, but built and signed by Anysphere and riding
        // Cursor's release infrastructure, which is why it sits next to Cursor
        // rather than under x.ai: `com.anysphere.sand`, Team DCNK4UB866,
        // notarized, arm64-only, updates from `api2.cursor.sh`.
        //
        // The app is `sand` on that API — not `grok-bot`, not `grokbot`. The
        // endpoint says so itself: any other name 404s with "Invalid app name -
        // can only download stable for cursor or sand".
        //
        // Single channel, and that is the vendor's position rather than an
        // assumption. The bundle's `appNameForTrack` maps three tracks
        // (stable → `sand`, nightly → `sand-nightly`, dogfood → `sand-dogfood`),
        // but the client coerces nightly back to stable and hides dogfood behind
        // an internal unlock, and the server 404s both of those app names for
        // every channel path. Only stable is reachable from a shipped build.
        //
        // Two other endpoints on the same API were rejected, both deliberately:
        //
        //   • The URL x.ai/bot's own download button uses,
        //     `/updates/download/stable/darwin-arm64/grok-bot-<token>`, 302s
        //     straight to the same dmg but publishes no version anywhere — it
        //     could only be probed by reading a filename.
        //   • `/updates/api/update/darwin-arm64/sand/<installed>/stable`, which
        //     the Homebrew cask's livecheck reads, is the app's own Squirrel feed
        //     and is CONDITIONAL: it answers `{"url":…,"name":"0.30.0"}` when a
        //     newer build exists and **204 with an empty body** when the caller is
        //     already current. An
        //     empty body is also what a broken endpoint looks like, so probing it
        //     would mean teaching the sweep to read silence as good news.
        //
        // `/updates/api/download/…` answers unconditionally with the version as a
        // JSON field, which is why it is the one here. The version pattern is
        // quote-bounded on both sides, so the segment count is not the boundary
        // (the Zotero rule).
        //
        // One-click: same-Team as the installed copy, and the install pattern is
        // pinned to this app's own path prefix because `downloads.cursor.com`
        // also serves Cursor's own builds (`/production/`) and the x64/universal
        // variants of this one. Two prefixes, because the vendor publishes the
        // same artifact under both: the API answers `/grokbot/…`, while the
        // Homebrew cask's url template builds `/sand/…`. If it ever moves to a
        // third the pattern stops matching and the one-click quietly goes away,
        // which is the direction this should fail.
        // `.dmg` and not `.pkg`: Electron with Squirrel.framework, and everything
        // it ships lives inside the bundle (`Contents/Frameworks`,
        // `Contents/Helpers`) — no daemon, no launch agent, nothing under
        // /Library.
        //
        // No `changelogURL`, and not an oversight: xAI publishes no release notes
        // for this desktop app. The only "changelog" x.ai links is
        // `x.ai/api/changelog`, which is the developer console's, on an unrelated
        // subject and version scheme.
        VendorProbeRecipe(
            bundleID: "com.anysphere.sand",
            url: URL(string: "https://api2.cursor.sh/updates/api/download/stable/darwin-arm64/sand")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://x.ai/bot"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""downloadUrl"\s*:\s*"(https://downloads\.cursor\.com/(?:grokbot|sand)/stable/darwin-arm64/[^"]+\.dmg)""#),
                kind: .dmg)),
        ])
}
