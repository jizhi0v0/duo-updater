import Foundation

enum com_qoder_ide {
    static let set = AppRecipeSet(
        family: "com-qoder-ide",
        probes: [
        // MARK: - Qoder (2026-09-06)
        //
        // TWO SEPARATE PRODUCTS, both called "Qoder", both offered off one
        // `qoder.com/download` page. They are not one product mid-rename: the
        // vendor answered it on its own forum
        // (forum.qoder.com/t/qdoer-qoder-qoder-ide/12088, read 2026-09-06) —
        // "Qoder IDE 用来代码，Qoder 是国际版 QoderWork 的迭代": the IDE is the coding
        // tool, the plain "Qoder" app is the successor to QoderWork. Separate
        // bundle ids, separate version lines (e.g. 1.28.0 vs 0.1.8), separate
        // release-note pages, separate download hosts — and, the part the install
        // gate cares about, SEPARATE TEAM IDs (T27K5A5ZWD vs B6U242QL73). The
        // vendor states that split itself: the installer stub's
        // `installer-manifest.json` carries `expectedIdeTeamIdentifier` AND
        // `expectedQoderTeamIdentifier` side by side.

        // History: docs/app-audits/com-qoder-ide.md#历史与实测
        // Qoder IDE — a VS Code fork, so it speaks VS Code's update protocol
        // verbatim. `Contents/Resources/app/product.json` names
        // `updateUrl = https://center.qoder.sh/algo` (read off the real 1.27.0
        // dmg, 2026-09-06) and the path under it is Microsoft's:
        // `/api/update/<platform>/<quality>/<commit>`.
        //
        // ⚠️ CONDITIONAL ENDPOINT — the reason the last path segment is `latest`
        // and not a commit. An older build's commit is answered with the newest
        // build's JSON, and the CURRENT build's commit with **204, empty body**
        // (measured 2026-09-06; History has the commits). Sending this machine's
        // own commit would make one response shape mean two things —
        // "you are current" on a Mac that has it, "the endpoint is broken" in a
        // sweep that has no install — which is exactly how a check goes quietly
        // dead (the trap the Mozilla AUS recipes (`Recipes/org-mozilla-firefox.swift`) document at length).
        // `latest` is the token this repo's own VS Code recipes already use in
        // that slot, and Qoder answers it with the newest build: every user and
        // every sweep then sends the identical request, an answer is always
        // expected, and empty is unambiguously a failure.
        //
        // Be careful about WHY it works, because the measurement does not settle
        // it. An all-zeros commit is answered with the newest build too, which is
        // equally consistent with "this server 204s only when the token equals
        // the current commit, and answers everything else" — in which case
        // `latest` is not a sentinel being honoured, just a string that can never
        // be the current commit. Either way the request is safe and the failure
        // mode is the same; the claim about the upstream protocol is the part
        // that is unverified.
        //
        // `productVersion`, not `name`, though both carried the same version when
        // checked (2026-09-14, "1.29.0"): `name` is the field the protocol lets a
        // vendor put a human string in, and `productVersion` is the one defined to
        // be the version. `version` is the COMMIT — matching it would compare a
        // 40-hex string against `1.27.0` forever.
        //
        // The install spec takes the zip the API itself names, not the
        // `Qoder-IDE-darwin-arm64.dmg` the download page hands a human. Same
        // release, and the zip needs no mount. Unpacked on 2026-09-06 (History has
        // the check), its app's CFBundleShortVersionString == CFBundleVersion ==
        // the API's `productVersion`, signed by the same Team as the installed
        // copy, so the swap passes the VendorInstaller gate.
        //
        // Single channel: `stable` is the only quality this server answers —
        // `/api/update/darwin-arm64/insider/latest` 404s (measured 2026-09-06).
        //
        // ⚠️ The install pattern's `[0-9.]+` path segment is NOT tied to the
        // `productVersion` this recipe reports — both are read out of the same
        // response, but nothing requires them to agree. A vendor that bumped one
        // ahead of the other would make us report one version and install
        // another: a wrong answer, not an "unknown". `versionTemplate` would
        // couple them and is deliberately not used, because reading the vendor's
        // own declared URL survives a CDN or path change that a template would
        // 404 on. The exposure is one response's worth of inconsistency, which
        // this endpoint has never shown.
        VendorProbeRecipe(
            bundleID: "com.qoder.ide",
            url: URL(string: "https://center.qoder.sh/algo"
                + "/api/update/darwin-arm64/stable/latest")!,
            mode: .responseBody,
            versionPattern: #""productVersion"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://qoder.com/download"),
            changelogURL: URL(string: "https://docs.qoder.com/release-notes/desktop"),
            publishedAtPattern: #""timestamp"\s*:\s*([0-9]{9,})"#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://qoder-ide\.oss-accelerate\.aliyuncs\.com"#
                    + #"/release/[0-9.]+/Qoder-darwin-arm64\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // Qoder IDE and Qoder — one markup, two pages, two products. See the
        // `VendorProbeRecipe` pair for why "Qoder" is two apps and not one.
        //
        // The notes people are pointed at live on `qoder.com/changelog?type=…`,
        // which is a Next.js page whose entries only exist inside an RSC payload —
        // every product's entries in one document, in two languages, with the
        // `type` discriminator sitting AFTER the version in each object. Parsing
        // that means betting on which copy of "1.28.0" comes first. The docs site
        // renders the same releases as ordinary server-side HTML, one page per
        // product, so it is the page these read instead.
        //
        // Structure (verified against the live bytes, 2026-09-06): each release is
        // a `data-component-part="update-label"` div holding the date, a
        // `…="update-description"` div holding the version, and a
        // `…="update-content"` div holding `<h3>`/`<h4>` section headings and the
        // `<ul>`s under them. Headings are dropped — only `<li>`s become change
        // lines, as everywhere else here.
        //
        // Anchored on the `data-component-part` attributes rather than the class
        // soup, and it is worth being exact about what that buys, because the two
        // obvious answers are both wrong.
        //
        // It is NOT what excludes the Next.js RSC payload the same page carries at
        // the bottom: that copy has no `</div>` in it at all, so the entry
        // pattern's element structure already excludes it (measured 2026-09-06 —
        // appending the payload to the real entries changes neither the count nor
        // the versions).
        //
        // Nor is it what keeps the page's own
        // `<div class="eyebrow">Release Notes</div>` header out of the newest
        // entry's date: the sentinel the gaps below temper on is the label
        // attribute, so the tempering does that job, and the header is only
        // captured when the tempering goes too (History has the measurement, and
        // the first version of this recipe, where the attributes did do it).
        //
        // What they still earn: they are the shape this recipe DECLARES it reads,
        // which is what makes the tempering sentinel legitimate rather than a
        // second bet on the vendor's markup, and without them the damage cases
        // below stop being detectable (`aDamagedEntryCannotBorrow…` both fail
        // under a prefix-stripped pattern). Belt and braces, honestly labelled.
        //
        // How many blocks the pattern matches is its reach over the page, not
        // history a reader gets: `ChangelogExtractor` drops an entry whose notes
        // are prose with no `<li>`, and the pane shows the `maxEntries` default
        // of 40, which neither recipe overrides (History has the 2026-09-06
        // counts).
        //
        // `<li[^>]*>` rather than a bare `<li>`: no entry on either page carries an
        // attribute there today, so this changes nothing that can be measured — it
        // is the one place a docs generator adding a class would silently empty
        // every entry, and the cost of tolerating it is zero.
        ChangelogRecipe(
            bundleID: "com.qoder.ide",
            source: URL(string: "https://docs.qoder.com/release-notes/desktop")!,
            entryPattern: ChangelogRecipeRegistry.qoderEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
