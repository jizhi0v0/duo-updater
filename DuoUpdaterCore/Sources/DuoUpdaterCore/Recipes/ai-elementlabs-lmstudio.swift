import Foundation

enum ai_elementlabs_lmstudio {
    static let set = AppRecipeSet(
        family: "ai-elementlabs-lmstudio",
        probes: [
        // History: docs/app-audits/ai-elementlabs-lmstudio.md#历史与实测
        // LM Studio — official version endpoint (same one Homebrew livecheck
        // uses). Compares on marketing version; build suffix is ignored.
        VendorProbeRecipe(
            bundleID: "ai.elementlabs.lmstudio",
            url: URL(string: "https://versions-prod.lmstudio.ai/update/darwin/arm64/0.0.0")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://lmstudio.ai/changelog/lmstudio"),
            // Feed has no link — build the dmg path from version + build, both of
            // which are REQUIRED in the path (e.g. …/0.4.15-2/LM-Studio-0.4.15-2-arm64.dmg;
            // dropping the build 404s). Team D65G88RHWN.
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://installers.lmstudio.ai/darwin/arm64/{0}-{1}/LM-Studio-{0}-{1}-arm64.dmg",
                    fields: [#""version"\s*:\s*"([^"]+)""#, #""build"\s*:\s*"([^"]+)""#]),
                kind: .dmg)),
        ],
        changelogs: [
        // LM Studio — Next.js changelog index. The index page already carries the
        // *full* release notes for the latest versions inline (the visible
        // truncation is a CSS mask only; the markup is complete), so we parse it
        // directly rather than the per-version pages. Each entry is, e.g.:
        //   <a href="/changelog/lmstudio/lmstudio-v0.4.20">
        //     <span class="sr-only">LM Studio 0.4.20</span></a>
        //   …<div class="markdown-body …"><p><strong>Build 1</strong></p>
        //     <ul class="list-disc"><li>…</li>…</ul>…</div></div></div>
        // No per-entry date is printed on the index, so `date` is omitted. Notes
        // use nested <ul> for sub-bullets; the <li> pattern folds a sub-list into
        // its parent line — cosmetically fine, and a miss just falls back to the
        // embedded page.
        //
        // The bare `/changelog` root is NOT this app's changelog: Element Labs
        // repurposed it for **Bionic**, a different product (entries `bionic-v…`),
        // and LM Studio's notes live at `/changelog/lmstudio`, with the per-version
        // slug nested one level deeper (History has when that changed). Chasing the
        // rebrand by matching `bionic-v` would have shown Bionic
        // 1.0.x notes to an LM Studio 0.4.x install, so the fix is the new URL plus
        // an href that tolerates both the nested and the old flat slug. The literal
        // `LM Studio ` in the sr-only span is the guard that keeps Bionic entries
        // out: a Bionic block simply doesn't match, and zero entries falls back.
        ChangelogRecipe(
            bundleID: "ai.elementlabs.lmstudio",
            source: URL(string: "https://lmstudio.ai/changelog/lmstudio")!,
            entryPattern:
                #"href="/changelog/(?:lmstudio/)?lmstudio-v[^"]*">\s*"#
                + #"<span class="sr-only">LM Studio (?<version>[^<]+)</span></a>"#
                + #".*?"#
                + #"<div class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>\s*</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
