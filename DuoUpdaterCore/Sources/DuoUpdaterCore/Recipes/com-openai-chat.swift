import Foundation

enum com_openai_chat {
    static let set = AppRecipeSet(
        family: "com-openai-chat",
        probes: [
        // MARK: - 2026-08-30 ChatGPT Classic

        // History: docs/app-audits/com-openai-chat.md#历史与实测
        // ChatGPT Classic (`com.openai.chat`) — OpenAI's PREVIOUS desktop app,
        // kept alive in maintenance mode (its release notes literally push the
        // new ChatGPT app: "Or, try the new ChatGPT app"; History has the release
        // it was still shipping). Its bundle carries NO `SUFeedURL` (verified
        // against the mounted dmg), so the generic Sparkle source can't see it
        // even though the vendor publishes a Sparkle feed. The
        // feed at `sidekick/public/sparkle_public_appcast.xml` is EXACTLY the
        // endpoint Homebrew's own `chatgpt-classic` cask names in its
        // `livecheck` block (`strategy :sparkle`) — a third-party witness that
        // this is the vendor's intended version surface.
        //
        // Feed shape: one `<item>` whose `sparkle:shortVersionString` is the
        // marketing version (matches CFBundleShortVersionString; the build
        // `sparkle:version` == CFBundleVersion (e.g. 1784145287), same namespace,
        // so no versionIsBuild). The enclosure is an UNVERSIONED moving pointer
        // (`ChatGPT_Classic.pkg`), but version and enclosure come from the SAME
        // feed entry — freshness is guaranteed by construction, better than a
        // separate version.txt + /latest/ dmg pairing.
        //
        // ⚠️ DETECTION-ONLY, and it has to be: `PackageInstaller` would refuse
        // this pkg every time. The gate in `verifyOpenable` is fail-closed on
        // declared destinations, and this package declares none: its
        // `PackageInfo` has no `<bundle path=…>` element, and the Bom's only
        // `.app`-bearing path is a `.app.zip`, so no path COMPONENT ends in
        // `.app` (History has the 2026-09-03 measurement on the real artifact).
        //
        // So an `install:` here resolves, downloads the whole package, and then
        // throws `packageDestinationsUnreadable` — a permanently broken Update
        // button.
        //
        // That is only the first reason. The pkg does not place the app at all:
        // its `postinstall` ditto-extracts the staged zip and then installs to
        // `/Applications/ChatGPT Classic.app` UNCONDITIONALLY, which means
        //   * a copy living at `/Applications/ChatGPT.app` is MOVED to the
        //     Classic path (the tracked bundle changes path under us),
        //   * a copy living anywhere else — `~/Applications`, say, which
        //     `AppScanner` also scans — is left untouched while a second copy
        //     appears in `/Applications`: an install that "succeeds" and updates
        //     nothing the user was looking at,
        //   * having BOTH paths occupied makes the script exit 1 outright
        //     ("Refusing to update because both ChatGPT paths are occupied"),
        //   * and on the move path it relaunches the app itself via
        //     `launchctl asuser … open -n`, which is not ours to coordinate.
        //
        // Detection is unaffected and is what this recipe is for. Anyone adding
        // one-click later has to solve the destination gate AND the relocation,
        // not just flip a flag.
        VendorProbeRecipe(
            bundleID: "com.openai.chat",
            url: URL(string: "https://persistent.oaistatic.com/sidekick/public/sparkle_public_appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9][^<]*)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://chatgpt.com/download/")),

        // Deliberately NOT covered by a ChangelogRecipe:
        //
        //   * **ChatGPT Classic** (`com.openai.chat`). Its Sparkle appcast has a
        //     `<description>`, so it LOOKS like a changelog source — but checked
        //     against the real bytes (2026-09-03; History quotes them), the
        //     content was vendor marketing pointing at the replacement product,
        //     not release notes. One `<item>`, no per-version history, and the
        //     same copy would render under every future build. Rendering that as
        //     "what is new" is worse than the web-view fallback, which at least
        //     shows it as the vendor's page.
        ])
}
