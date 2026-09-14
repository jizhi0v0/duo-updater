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
        // release notes exist, and the two agreed when this was written
        // (2026-08-28) and on recheck 2026-09-14 (History has the versions and
        // dates).
        //
        // DETECTION ONLY, and here that is not conservatism. Its `install.sh` does
        // rotate `Contents` on the already-installed branch, like WeType's and
        // DoubaoIme's updaters — but that rotation is `rm -rf` then `mv`, not an
        // atomic exchange, and around it the script lays down two
        // `/Library/LaunchAgents` plists it then boots out, bootstraps and
        // kickstarts, re-registers a QuickLook generator (`qlmanage -r`), MIGRATES
        // `~/Library/Input Methods/Sogou` into
        // `~/Library/Application Support/Sogou/InputMethod`, and ends with
        // `killall -9 SogouInput` and `killall -KILL SystemUIServer` — force-kills
        // this app does not perform on anybody. A Contents rotation leaves every
        // one of those undone.
        //
        // Neither script installs a per-user LaunchAgent: both only `bootout` and
        // `rm -rf` `~/Library/LaunchAgents/com.sogou.SogouTaskManager.plist`
        // (History has the earlier note that said otherwise). The self-update
        // payload above is a narrower shape again (a double zip carrying
        // `Contents<version>.zip` plus `pre.sh`/`post.sh`/`switch.sh`, whose
        // switch script has its own migration branches), so a one-click here needs
        // a Sogou-specific path, not the generic archive install.
        VendorProbeRecipe(
            bundleID: "com.sogou.inputmethod.sogou",
            url: URL(string: "https://macime.sogou.com/macversion.txt?v=0.0.0.1&sv=27.0&s=0")!,
            mode: .responseBody,
            versionPattern: #"\npid=0\n(?:[^\[]*?\n)?version=([0-9]+(?:\.[0-9]+)+)[^\[]*?\nupdate_pack_url="#,
            downloadURL: URL(string: "https://shurufa.sogou.com/mac"),
            changelogURL: URL(string: "https://pinyin.sogou.com/mac/update_log.php")),
        ])
}
