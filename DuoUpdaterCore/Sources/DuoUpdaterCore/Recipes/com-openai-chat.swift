import Foundation

enum com_openai_chat {
    static let set = AppRecipeSet(
        family: "com-openai-chat",
        probes: [
        // MARK: - 2026-08-30 ChatGPT Classic

        // ChatGPT Classic (`com.openai.chat`) — OpenAI's PREVIOUS desktop app,
        // kept alive in maintenance mode (its release notes literally push the
        // new ChatGPT app: "Or, try the new ChatGPT app"). Still updating as of
        // 2026-08-30 (1.2026.184 / build 1784145287, published 2026-07-15), and
        // the installed base is real — but its bundle carries NO `SUFeedURL`
        // (verified against the mounted dmg), so the generic Sparkle source
        // can't see it even though the vendor publishes a Sparkle feed. The
        // feed at `sidekick/public/sparkle_public_appcast.xml` is EXACTLY the
        // endpoint Homebrew's own `chatgpt-classic` cask names in its
        // `livecheck` block (`strategy :sparkle`) — a third-party witness that
        // this is the vendor's intended version surface.
        //
        // Feed shape: one `<item>` whose `sparkle:shortVersionString` is the
        // marketing version (matches CFBundleShortVersionString; the build
        // `sparkle:version` == CFBundleVersion 1784145287, same namespace, so
        // no versionIsBuild). The enclosure is an UNVERSIONED moving pointer
        // (`ChatGPT_Classic.pkg`), but version and enclosure come from the SAME
        // feed entry — freshness is guaranteed by construction, better than a
        // separate version.txt + /latest/ dmg pairing.
        //
        // ⚠️ DETECTION-ONLY, and it has to be: `PackageInstaller` would refuse
        // this pkg every time. The gate in `verifyOpenable` is fail-closed on
        // declared destinations, and this package declares none. Measured
        // 2026-09-03 against the real 78 MB artifact, and re-checked by running
        // `destinations(inPackageInfo:)` and `destinations(inBomListing:)` on its
        // actual bytes — both return the empty set:
        //
        //   * `PackageInfo` carries `install-location="/"` and an EMPTY
        //     `<bundle-version/>`; there is no `<bundle path=…>` element at all.
        //   * The Bom's only `.app`-bearing line is
        //     `./Library/Application Support/OpenAI/ChatGPT Classic Update/
        //     ChatGPT Classic.app.zip` — a zip, so no path COMPONENT ends in
        //     `.app` and `appBundlePrefixes` yields nothing.
        //
        // So an `install:` here resolves, downloads 78 MB, and then throws
        // `packageDestinationsUnreadable` — a permanently broken Update button.
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
        // not just flip a flag. Verified signing, for the record: "Developer ID
        // Installer: OpenAI OpCo, LLC (2DC432GLL2)", notarized, trusted
        // timestamp 2026-07-15, same Team as the installed bundle. Feed also
        // declares `hardwareRequirements=arm64` and minimumSystemVersion 14.0.
        VendorProbeRecipe(
            bundleID: "com.openai.chat",
            url: URL(string: "https://persistent.oaistatic.com/sidekick/public/sparkle_public_appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9][^<]*)</sparkle:shortVersionString>"#,
            downloadURL: URL(string: "https://chatgpt.com/download/")),
        ])
}
