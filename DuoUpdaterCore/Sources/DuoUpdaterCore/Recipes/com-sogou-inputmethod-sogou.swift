import Foundation

enum com_sogou_inputmethod_sogou {
    static let set = AppRecipeSet(
        family: "com-sogou-inputmethod-sogou",
        probes: [
        // History: docs/app-audits/com-sogou-inputmethod-sogou.md#历史与实测
        // 搜狗输入法 (SogouInput) — Sogou's input method, installed from
        // `shurufa.sogou.com` / `pinyin.sogou.com` into `/Library/Input Methods`.
        //
        // Reads the vendor's OWN update endpoint — the one `SogouServices` calls,
        // captured off the wire (2026-08-28):
        //
        //   GET macime.sogou.com/macversion.txt?h=<md5>&v=<installed>&r=1111&sv=27.0&s=0
        //
        // It is a CONDITIONAL endpoint: "given this client's version, what should
        // it upgrade to". Ask it as an up-to-date client and it answers with a
        // sentinel — `version=1.0.0.1`, below every real build, which is how it
        // tells the client to stay put. Ask it as an old one and it names the
        // current release with a payload URL and an md5, e.g.:
        //
        //   version=6.24.1.11676
        //   update_pack_url=…/autosetup6.24.1.11676_V10003_20260715_223833.zip
        //   update_pack_md5=654bd06d7df44e2237e0c61fab08477b
        //
        // So the probe pins `v` at `0.0.0.1` — below anything the vendor can ever
        // ship, so the request can never drift into sentinel territory. It does
        // NOT stage: every older version tried was answered with the same newest
        // build rather than an intermediate hop (History has the values), which is
        // the property that makes a pinned-old-version probe mean "latest".
        //
        // THE VERSION IS THE BUNDLE'S OWN. e.g. `6.24.1.11676` is exactly
        // `CFBundleShortVersionString`, four segments included — unlike the
        // changelog page, which publishes three and would have needed the
        // installed side trimmed to compare at all. Same namespace, no derivation,
        // and respins that change only the fourth segment are visible.
        //
        // PARAMETERS. Only `sv` is actually required — omit it and the answer
        // collapses to the sentinel. `v` and `s` are sent anyway, because what
        // they do is worth pinning rather than leaving to a default: `v` absent or
        // unparseable is treated as ancient (the pin states the intent instead of
        // relying on that), and `s` is read as an integer where 0 means "check for
        // an update" — `s=1`, `s=2`, `s=3`, `s=-1` all select a branch that
        // sentinels unconditionally.
        //
        // `r` (the installed copy's distribution channel) is omitted: the server
        // ignores it — absent, `r=1111` and `r=9999` answer identically — and a
        // channel code lifted from one machine's install would be stating
        // something untrue about every other. `h`, the per-device hash the real
        // client sends, is omitted for a stronger reason: a probe of ours has no
        // business carrying a machine identifier to a vendor. The binary also
        // builds requests carrying `r0` and `cpu` (an architecture selector);
        // `cpu` is inert today — `arm64`, `x86_64` and `intel` answer identically
        // — but it is what would decide which architecture we are told about if
        // Sogou ever split them.
        //
        // WARNING: `sv` DOES gate by OS. Swept finely there were three answers
        // (History has the sweep): the sentinel below 10.10, the current build
        // for 10.14 – 27.6, and a build frozen since June 2023 for 10.10 – 10.13
        // and again from 27.61 up.
        //
        // So the pinned `27.0` IS choosing a build for an OS, and that upper edge
        // has a consequence for the vendor's own users: a Sogou client on macOS 28
        // asks with `sv=28.x`, is handed a 2023 build below its own install, and
        // quietly stops updating. Pinning a constant is what keeps OUR answer
        // right for every host regardless — sending the machine's real OS would
        // break detection on exactly those Macs.
        //
        // The residual risk is narrow, and it is this recipe's one quiet failure:
        // if Sogou splits the 10.14–27.6 bucket and ships a newer build only above
        // it, the pinned request keeps answering the build it answers now and
        // nothing fails. Most boundary moves are loud instead — a pin landing in
        // the legacy bucket reports the frozen 2023 build, below every real
        // install, which the sweep flags as `remote is BEHIND the installed copy`.
        // The check for the quiet case is the changelog page: at the next release
        // it advances and so must this.
        //
        // The pattern requires `update_pack_url` to FOLLOW the version, so the
        // sentinel response cannot be read as one. Without that guard a sentinel
        // would be reported as `1.0.0.1` — which reads as a colossal downgrade and
        // would at least be loud, but refusing it outright is better than being
        // loud about a number we know is not a version.
        //
        // And the span between them is `[^\[]*?`, not `[\s\S]*?`, so it cannot
        // cross a `[` — which is to say it cannot leave the block it started in.
        // The response is `[product0]` … `[end]`, with a `pid=0` inside: a shape
        // that plainly anticipates more than one product, even though no request
        // tried here produced one. An unbounded span over a sentinel block
        // followed by a real one pairs the FIRST block's `version=1.0.0.1` with
        // the SECOND block's payload URL and reports `1.0.0.1` as the release —
        // measured on exactly that concatenation. Not being able to make the
        // server emit two blocks is not evidence that it never will.
        //
        // `pid=0` is required ahead of the version for the same reason, one step
        // further: block-scoping stops us pairing two blocks' fields, but not
        // reading the FIRST block when that block is some other product. That
        // `pid` identifies the product is UNVERIFIED — it is `0` in both responses
        // ever seen, and no request produced a second block — but the guard fails
        // in the safe direction either way: a response this does not recognise
        // resolves no version at all, which is loud, rather than quietly reporting
        // a number belonging to something else.
        //
        // `changelogURL` stays on the update-log page: it is the only place the
        // release notes exist, and the two agreed when this was written (2026-08-28)
        // and on recheck 2026-09-14 (History has the versions and dates).
        //
        // ONE-CLICK, added 2026-09-20 — and the reason it took until then is that
        // the case against it was read off the WEBSITE INSTALLER, which does lay
        // down `/Library/LaunchAgents` plists, register a QuickLook generator,
        // migrate the user's directory and `killall -9` its way out. The
        // SELF-UPDATE package — the one this endpoint hands out, and the one an
        // ordinary release travels in — does none of that. Measured on
        // 6.25.1.11973 (History has all three scripts):
        //
        //   * `pre.sh` acts only when the bundle is NOT writable, and
        //     `InPlaceSwap.stageRotation` refuses that same case up front.
        //   * `post.sh` is wrapped entirely in a test for the 2019 build
        //     `3.2.0.68597`.
        //   * `switch.sh` holds the only teeth, and they are argument-gated:
        //     `switch.sh 1` deletes `~/Library/Application Support/Sogou/InputMethod`
        //     — the learned dictionary — before moving an older location over it.
        //     It also ends in `killall -KILL SystemUIServer`.
        //
        // None of the three is run. What is run is the half that IS the update:
        // `Contents` rotation, the same exchange the other two input methods get,
        // via `ContentsPayload` — because unlike theirs this package carries a
        // bare `Contents<version>` directory and no `.app` at either level.
        //
        // Assembled into a bundle it verifies: `codesign --verify --deep --strict`
        // valid, `spctl` `Notarized Developer ID`, Team `DFD88F82SU` matching the
        // installed copy, id `com.sogou.inputmethod.sogou`. Gates 2–6 are untouched.
        //
        // `SGQuDao`, the channel code the installed `Info.plist` carries, is NOT in
        // the payload and no script puts it back — so the vendor's own update drops
        // it too. Re-injecting it would break a signature that just passed.
        //
        // `update_pack_md5` is MD5 and `checksumPattern` is SHA-512/base64, so it
        // is deliberately NOT wired rather than mis-declared — the same call
        // WeType's `zip_download_md5` got.
        //
        // The install URL comes from THIS response, the one pinned at
        // `v=0.0.0.1`, and that is deliberate against the audit's first
        // suggestion of re-asking with the real installed version. Two measured
        // facts make the pin the safer of the two: the endpoint does not stage
        // (so the pinned request's payload is the newest one), and `sv` gates by
        // OS (so a request carrying a macOS 28 host's real version would be
        // answered with the frozen 2023 build — below every real install). The
        // version that was compared and the bytes that get installed come out of
        // one response either way.
        //
        // The user's dictionary and settings live in
        // `~/Library/Application Support/Sogou/` and `~/Library/Preferences/`, none
        // of it in the bundle. `InputMethodDataBackup.declaredDataNames` is what
        // reaches them — the general rules find one plist of the seven, because
        // nothing on disk is called `SogouInput`.
        VendorProbeRecipe(
            bundleID: "com.sogou.inputmethod.sogou",
            url: URL(string: "https://macime.sogou.com/macversion.txt?v=0.0.0.1&sv=27.0&s=0")!,
            mode: .responseBody,
            versionPattern: #"\npid=0\n(?:[^\[]*?\n)?version=([0-9]+(?:\.[0-9]+)+)[^\[]*?\nupdate_pack_url="#,
            downloadURL: URL(string: "https://shurufa.sogou.com/mac"),
            changelogURL: URL(string: "https://pinyin.sogou.com/mac/update_log.php"),
            install: VendorInstallSpec(
                // Block-scoped exactly like `versionPattern` above, and for the
                // same reason: an unscoped `update_pack_url=` takes the FIRST one
                // in the body, which in a multi-block response need not belong to
                // the block the version was read from. Nobody has seen this server
                // send two blocks with payloads — the guard is that the two
                // patterns cannot disagree about which release is being installed,
                // which is a property worth having by construction rather than by
                // the server's habit. `aVersionIsNeverPairedWithAnotherBlocksPayload`
                // builds the body where the unscoped spelling reads the wrong one.
                urlSource: .bodyPattern(
                    #"\npid=0\n(?:[^\[]*?\n)?version=[0-9]+(?:\.[0-9]+)+[^\[]*?\nupdate_pack_url=(https?://[^\s]+\.zip)"#),
                kind: .zip,
                contentsArchivePattern: #"^Contents[0-9.]+\.zip$"#)),
        ])
}
