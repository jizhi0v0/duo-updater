import Foundation

enum com_openai_codex {
    static let set = AppRecipeSet(
        family: "com-openai-codex",
        probes: [
        // History: docs/app-audits/com-openai-codex.md#历史与实测
        // Codex — the endpoint ChatGPT's own updater asks, not the feed it ships
        // configured with. Those are different answers, which is the whole reason
        // this recipe looks like this.
        //
        // The app's `codexSparkleFeedUrl` is
        // `persistent.oaistatic.com/codex-app-prod/appcast.xml`, and reading it is
        // what we used to do. But `production-appcast-bootstrap.json` carries
        // `backendAppcastEnabled: true`, and Sparkle then asks the endpoint below,
        // which 307s to a per-target `appcast-<version>.xml`. The static file is a
        // PUBLISHING manifest; the redirect target is what the vendor is actually
        // shipping, and the two can disagree for hours (History has the
        // 2026-08-22 case). Installing the published-but-unshipped build starts a
        // fight the app wins: its own Sparkle stages the build the endpoint named,
        // waits for a quit, and our restart is the quit.
        //
        // That is also why this REPLACES the static feed rather than joining it as
        // a second endpoint. `VendorProbeSource.best(of:)` takes the highest, sound
        // only under its stated precondition — every endpoint must serve "a build
        // this machine may legitimately install". The publishing manifest doesn't.
        //
        // `app_version` is required (omit it, or send something unparseable, and
        // there is no redirect) but does not participate (History has the values
        // tried). A sentinel is deliberate — if OpenAI ever does step upgrades,
        // 0.0.0 is the value most likely to be rejected outright, which
        // `duo verify` reports, rather than to answer plausibly and wrongly. The
        // app also sends `os-version` and a `codex_cache_bust` counter; neither
        // changed the redirect target when measured (2026-08-24; History has the
        // values), so this URL stays as short as it can be.
        //
        // `installation_id` selects the rollout bucket and grants nothing; see
        // `ProbeIdentity` for why it never reaches a log, a report, or the
        // recipe's own recorded URL.
        //
        // `plan_type` is the second thing the endpoint keys on, and unlike
        // `app_version` it decides the answer. Measured 2026-08-24 (History has
        // the table), the consumer values (`free`, `go`, `plus`, `pro`, `team`)
        // resolved to a newer build than `business`, `enterprise` and `ent26`,
        // and `unknown`, omitted or nonsense landed with the enterprise ones.
        //
        // Two rollout tracks, not per-tier builds. This is the "enterprise-plan
        // recognition" of openai/codex 0.146.0 (PRs #35238, #35537): business
        // tiers roll out behind consumer ones so IT can qualify a build.
        //
        // The split is a WINDOW, not a standing structure: later the same day
        // every value resolved to the newer build. So nothing can assert on the
        // split, and `duo verify` cannot tell whether this parameter is doing
        // anything: outside the window both answers agree. It earns its place
        // only inside the window, which is exactly when getting it wrong starts
        // the fight described below.
        //
        // So omitting it is not neutral — it silently books this machine onto
        // the enterprise track. And hardcoding a consumer value is worse than
        // omitting: on an actual business account we would offer a build that
        // account's own updater refuses, which is precisely the fight described
        // above — its Sparkle stages the older build, waits for a quit, and our
        // restart is the quit.
        //
        // Hence reading the real value. It is an account attribute rather than a
        // machine id, so it lives with the account state in `~/.codex/auth.json`
        // — ChatGPT.app bundles the `codex` CLI at `Contents/Resources/codex`
        // and both resolve `CODEX_HOME ?? ~/.codex`, so it is one file for one
        // product. `ProbeIdentity.jwtClaim` reaches that one claim and nothing
        // else. Absent — never signed in, or the file moved — falls back to
        // "unknown", which is what OpenAI's own `codex doctor` hardcodes
        // (codex-rs/cli/src/doctor/updates.rs) and which lands on the cautious
        // track: the same answer we gave before this parameter existed.
        //
        // What is shared is the FILE and the LOGIN EVENTS. The VALUE is not.
        // When measured (2026-08-24; History has the steps), signing out of
        // ChatGPT.app deleted `~/.codex/auth.json` and signing in again through
        // `codex` recreated it, but with the file holding a different plan from
        // the app's session the app sent its session's plan and never touched
        // the file. It does not consult this file to answer.
        //
        // The app builds its value from the live session of the ACTIVE account
        // (`setSparkleQueryParams({beta, planType})`, fed from the account
        // object; default `unknown`), and that plan is not persisted anywhere we
        // can read — `~/Library/Application Support/com.openai.codex/` holds
        // only the bootstrap json above and a web session directory. So this
        // claim is the best local source that exists, not the app's own value.
        //
        // Ours is right whenever the login is the one the app is using — the
        // ordinary case, and strictly better than omitting the parameter (which
        // books every machine onto the enterprise track) or hardcoding one
        // (wrong in the dangerous direction on a business account). But four
        // things drift it, all silently:
        //
        //   * `codex login --with-api-key` — auth_mode becomes apikey and the
        //     token carries no `chatgpt_plan_type` at all, so we send "unknown"
        //     while the app sends the account's real plan;
        //   * a plan change between token refreshes leaves the claim stale;
        //   * switching the active workspace inside the app is not a re-login,
        //     so the minted claim need not follow it. UNVERIFIED: the account on
        //     hand belonged to no workspace, so no switcher appeared;
        //   * `CODEX_HOME` moves the file, and this path is hardcoded. Real
        //     setups do it — openai/codex#35817 is an XDG-style
        //     `CODEX_HOME=$HOME/.local/share/codex` on macOS whose `~/.codex`
        //     holds nothing but a stray Desktop sqlite dir. Those machines get
        //     the pre-fix behaviour. Reading the variable is NOT the fix: the
        //     GUI app is launched by launchd and does not inherit the user's
        //     shell environment, so `duo verify` (which does) would go green
        //     over a machine where the app still falls back.
        //
        // All four fail toward "unknown" or a stale consumer value, never toward
        // claiming enterprise on a consumer account, so the blast radius is the
        // cautious track — where omitting the parameter put everyone anyway.
        //
        // The first of the four is no longer silent, at least in a sweep: this
        // rides in `track` rather than `identities`, and `duo verify` reports a
        // machine that fell back WHILE the vendor's two tracks are actually
        // apart. See `RolloutTrack` for why that combination is the only one
        // worth a finding.
        VendorProbeRecipe(
            bundleID: "com.openai.codex",
            url: URL(string: "https://chatgpt.com/backend-api/wham/app/appcast?installation_id=__IDENTITY__&arch=arm64&beta=false&app_version=0.0.0&plan_type=__PLANTYPE__")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9][^<]*)</sparkle:shortVersionString>"#,
            // Required of any identity recipe: without it `.responseBody` falls back
            // to `recipe.url` as the download, which here is an unfetchable
            // placeholder (`ProbeIdentityRedactionTests`). The vendor's own page,
            // titled "Download ChatGPT" — behind a Cloudflare interstitial, so a
            // script gets 403 and only a browser confirms it.
            //
            // The tempting alternative is the direct artifact the site's button
            // serves, `codex-app-prod/Codex.dmg`. Do not use it, and not only
            // because `PageURLTests` requires a page: that dmg tracks the
            // PUBLISHING manifest (History has the Last-Modified that showed it).
            // Pointing anything at it walks straight back into the fight this
            // recipe exists to end.
            downloadURL: URL(string: "https://chatgpt.com/download/"),
            changelogURL: URL(string: "https://developers.openai.com/codex/changelog?type=codex-app")!,
            // Redirect followed (the default), so the body parsed here is the
            // pinned appcast. Its enclosure points at the full zip; the `.delta`
            // urls are ignored, unchanged from when this read the static feed.
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"url="([^"]+\.zip)""#),
                kind: .zip),
            identities: [
                ProbeIdentity(
                    applicationSupportPath: "com.openai.codex/production-appcast-bootstrap.json",
                    encoding: .jsonKey("installationId"),
                    validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#),
            ],
            // The plan is NOT an identity — it names which builds come back, not
            // which bucket this machine is in — so it rides here, where the
            // sweep can also check whether it is still deciding anything.
            //
            // `business` is the contrast because it is the value the two-track
            // split is actually about; when the endpoint answers it the same way
            // it answers ours, the rollout has merged and today's value cannot be
            // wrong. `validationPattern` is deliberately permissive: we are a
            // passthrough, not an authority on OpenAI's tier names. A slug we
            // have never seen is forwarded as-is and the vendor decides; only
            // something that isn't a slug at all falls back. `maxBytes` is raised
            // because this file holds JWTs — see `.jwtClaim` for what is and is
            // not read out of it, and `RegistrySecurity` for the allow-list that
            // keeps it that way.
            track: RolloutTrack(
                selector: ProbeIdentity(
                    location: .home(".codex/auth.json"),
                    encoding: .jwtClaim(
                        tokenPath: ["tokens", "access_token"],
                        claimPath: ["https://api.openai.com/auth", "chatgpt_plan_type"]),
                    validationPattern: #"[a-z0-9_]{1,32}"#,
                    placeholder: "__PLANTYPE__",
                    fallback: "unknown",
                    maxBytes: 32768),
                contrastValue: "business",
                contrastTrackName: "the enterprise track")),
        ],
        changelogs: [
        // Codex — parse the app-specific OpenAI Developers changelog view rather
        // than the mixed all-topics page. The HTML still contains non-app entries,
        // so we additionally require `data-codex-topics` to include `codex-app`.
        // Capture the human title separately from the optional trailing build
        // number (`<span class="text-tertiary">26.527</span>`), which some app
        // posts have and some do not.
        //
        // The page moved to learn.chatgpt.com in August 2026; the old
        // developers.openai.com/codex/changelog address still 308s here, but a
        // permanent redirect is the vendor's to withdraw, so we follow it once in
        // the registry rather than on every fetch.
        ChangelogRecipe(
            bundleID: "com.openai.codex",
            source: URL(string: "https://learn.chatgpt.com/docs/changelog?type=codex-app")!,
            entryPattern:
                #"<li id="codex-[^"]*"[^>]*data-codex-topics="[^"]*codex-app[^"]*"[^>]*>.*?"#
                + #"<time[^>]*>(?<date>[^<]+)</time>.*?"#
                + #"<h3[^>]*>\s*<span>\s*(?<title>.*?)\s*(?:<span[^>]*>\s*(?<version>[^<]+)\s*</span>)?\s*</span>.*?</h3>.*?"#
                + #"<article[^>]*>(?<body>.*?)</article>"#,
            itemPatterns: [
                #"<li[^>]*>\s*(?:<p>)?(?<item>.*?)(?:</p>)?\s*</li>"#,
                #"<p>(?<item>.*?)</p>"#
            ],
            maxEntries: 20),
        ])
}
