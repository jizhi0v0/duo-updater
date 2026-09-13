import Foundation

enum com_bytedance_inputmethod_doubaoime {
    static let set = AppRecipeSet(
        family: "com-bytedance-inputmethod-doubaoime",
        probes: [
        // 豆包输入法 (DoubaoIme) — ByteDance's input method, installed from
        // `shurufa.doubao.com` into `/Library/Input Methods`. No SUFeedURL, no MAS
        // receipt, no Homebrew cask (the `doubao` cask ships `doubao.app`, the
        // unrelated AI chat client), so nothing in the priority chain answered and
        // the row sat on "unknown" — it was scanned but never checked.
        //
        // The site's own download button reads this endpoint (`platform` ∈
        // android/ios/macos/windows), which is the vendor's statement of what the
        // current shipping build is:
        //
        //   {"code":0,"data":{"url":".../DoubaoImeInstaller_v90602_release.zip",
        //    "version_code":1002007,"version_name":"V0.9.6"},"msg":"success"}
        //
        // VERSION SCHEME — three numbers in this response, and which one to compare
        // is the whole recipe:
        //   * the `v90602` in the zip filename is the vendor's version code, and the
        //     installed bundle carries THE SAME NUMBER in its custom Info.plist key
        //     `Wave Build Version Number` (also spelled `0.9.6.2` in
        //     `Wave Build Version`). `AppScanner` reads that key in place of
        //     `CFBundleVersion`, which is a flat "1" on every build. This pair is
        //     what we compare — exact, respins included.
        //   * `version_name` "V0.9.6" is the marketing string, and is what the row
        //     SHOWS (`displayVersionPattern`); it equals the installed
        //     `CFBundleShortVersionString`.
        //   * `version_code` 1002007 is a THIRD namespace that matches nothing local.
        //     Never compare it.
        //
        // The first draft of this recipe compared only the marketing version, on the
        // mistaken reading that 90602 had no local counterpart. It does — it is just
        // not under a standard key. The cost of that draft was a blind spot for
        // same-marketing-version respins (90601 → 90602, both "0.9.6"); comparing the
        // vendor's own code closes it.
        //
        // If the vendor ever drops that Info.plist key, `AppScanner` reports NO build
        // rather than falling back to "1", and `evaluate()` returns to comparing
        // `version_name` against the installed marketing version — degraded, but
        // never a phantom. See `AppScanner.waveBuildVersionNumber`.
        //
        // No `changelogURL` — the marketing site has no release-notes page at all.
        // The notes come from the ChangelogRecipe over `ime.doubao.com`'s update
        // feed, which is structured; there is nothing worth embedding as a fallback.
        //
        // ONE-CLICK, and it takes one more step than any other recipe because the
        // artifact here is not the app. The endpoint hands over
        // `DoubaoImeInstaller_v<code>_release.zip`, a ~190 MB stub whose
        // `Contents/Resources` holds `DoubaoIme.zip` (170 MB) plus the `install.sh`
        // it runs — so `nestedArchivePath` unwraps one level, and the whole gate
        // stack (signature, Team, bundle id, architecture) then runs on the real
        // `DoubaoIme.app`. Without the unwrap the bundle-id gate would refuse
        // `com.bytedance.inputmethod.doubaoime.installer`, correctly, and the
        // one-click could never work.
        //
        // The unwrap is a gate MOVED, not skipped: `Contents/Resources` is sealed
        // by the stub's own code signature (Team 96L78H6LMH, the same Team as the
        // installed app), and `VendorInstaller` verifies the stub before reading
        // the payload out of it.
        //
        // The install itself rotates `Contents` inside the registered
        // `DoubaoIme.app`, which is what DoubaoIme's own updater does
        // (`Contents_update` / `Contents_backup`), while `install.sh` is the
        // first-install path that removes the whole bundle. See
        // `InPlaceSwap.usesContentsRotation`. That script also ends with
        // `chown -R root:staff` + `chmod -R 775` — recursively — which is why the
        // swap carries the group-write bit all the way down and not just two
        // levels: their updater has to be able to delete the Contents it displaced.
        VendorProbeRecipe(
            bundleID: "com.bytedance.inputmethod.doubaoime",
            url: URL(string: "https://ime.doubao.com/api/v1/app/download_url?platform=macos")!,
            mode: .responseBody,
            versionPattern: #"DoubaoImeInstaller_v([0-9]+)_release\.zip"#,
            downloadURL: URL(string: "https://shurufa.doubao.com/"),
            versionIsBuild: true,
            displayVersionPattern: #""version_name"\s*:\s*"[Vv]?([0-9]+(?:\.[0-9]+)+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://[^"]+/DoubaoImeInstaller_v[0-9]+_release\.zip)""#),
                kind: .zip,
                nestedArchivePath: "Contents/Resources/DoubaoIme.zip")),
        ],
        changelogs: [
        // 豆包输入法 (DoubaoIme) — the vendor publishes no release-notes page; the
        // notes only exist inside the endpoint the app's own updater polls:
        //
        //   ime.doubao.com/api/v1/version/list?channel=&version_code=&platform=
        //
        // It answers "what should a client on <version_code> be offered", so it needs
        // all three parameters (it 400s with 渠道/当前版本/平台不能为空 otherwise) and
        // returns [] once the caller is current. We pass `version_code=1` — an
        // impossibly old client — so the newest release's notes always come back,
        // whatever the reader has installed. `channel=release` is the user-facing
        // track; `inhouse` and `test` also answer but are ByteDance's internal builds
        // (the installed bundle's Info.plist carries `CHANNEL_NAME = release`).
        //
        //   {"list":[{"channel":"release","platform":"macOS","version_name":"0.9.6",
        //     "version_code":90601,"change_log":"- 新增账号登录…；\n- 新增离线语音…",
        //     …,"push_message":{"title":"豆包输入法已更新至 0.9.6 版本",…}}]}
        //
        // The entry pattern is anchored on `"platform":"macOS"` immediately before
        // `version_name` and walks the fields in emitted order, so it can only ever
        // bind a version to the `change_log` of its OWN object — and it cannot reach
        // the version number sitting in `push_message.title`.
        //
        // `change_log` is one string of `- `-prefixed lines joined by escaped `\n`,
        // so the item pattern splits on those. NOTE the tail alternative is `|$)`,
        // NOT the `|\\n?$)` used by the ChatWise recipe above: `\\n?` means "a literal
        // backslash, optionally followed by n", which requires the body to END in a
        // backslash and therefore drops the last bullet. Verified against the real
        // 2026-08-21 response: 6 bullets in, 6 out.
        ChangelogRecipe(
            bundleID: "com.bytedance.inputmethod.doubaoime",
            source: URL(string:
                "https://ime.doubao.com/api/v1/version/list"
                + "?channel=release&version_code=1&platform=macos")!,
            entryPattern:
                #""platform":"macOS","version_name":"(?<version>[0-9][^"]*)","#
                + #""version_code":\d+,"change_log":"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [
                #"(?:^|\\n)-\s*(?<item>.*?)\s*(?=\\n-\s|$)"#,
                #"\s*(?<item>.+?)\s*$"#,
            ],
            mode: .json,
            stripTags: false,
            maxEntries: 20),
        ])
}
