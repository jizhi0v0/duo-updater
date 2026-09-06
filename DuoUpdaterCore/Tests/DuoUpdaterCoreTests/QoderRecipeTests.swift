import Foundation
import Testing

@testable import DuoUpdaterCore

/// `center.qoder.sh/algo/api/update/darwin-arm64/stable/latest`, captured
/// verbatim 2026-09-06 (the whole response is 344 bytes).
private let qoderIDEUpdateFixture = #"""
{"url":"https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-arm64.zip","name":"1.28.0","version":"68cf4c38cec43130a7dccbadcf9e5e0902ef5549","productVersion":"1.28.0","hash":"d712c37efc09025fbbadfdd00e37f8093033667c","timestamp":1788277155505,"sha256hash":"52c46d6d5fed3a36b56ede60b9354ced9077c77809149a293c18b76e621b6f0e"}
"""#

/// The x64 answer from the same server, same second — kept because it is the one
/// thing an architecture-blind pattern would happily install on an arm64 Mac.
private let qoderIDEIntelUpdateFixture = #"""
{"url":"https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-x64.zip","name":"1.28.0","version":"68cf4c38cec43130a7dccbadcf9e5e0902ef5549","productVersion":"1.28.0","hash":"04f93753eadb31fb535d95aa9ff8c4a1c4d9101d","timestamp":1788277129713,"sha256hash":"74edb29015d01c80d795c1a840cbbb05b63107e3516b1aacd5334d7cd6519579"}
"""#

/// `download.qoder.com/qoder-app/releases/latest/manifest.json`, captured
/// verbatim 2026-09-06 and trimmed to the macOS artifacts plus the Windows one
/// that follows them — the Windows entry is the neighbour a loose install
/// pattern would reach.
private let qoderAppManifestFixture = #"""
{
  "schemaVersion": 1,
  "version": "0.1.8",
  "artifacts": [
    {
      "id": "mac-arm64",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip",
      "sha256": "8f71bf3899b74d028253497fe47fe2dff7a54c9ed06369595b9b46d93a33a7e7"
    },
    {
      "id": "mac-x64",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-x64.zip",
      "sha256": "25e349dedb5940fec1d8c802255f351af6e93f8911ae2d8c5583f7aeae062361"
    },
    {
      "id": "win-x64-user",
      "url": "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-win-x64-user.exe",
      "sha256": "10ce1b6861aa819f04d29d63e195dfd4cae4e85e7cf40d468120a781626853d7"
    }
  ]
}
"""#

/// The newest two entries of `docs.qoder.com/release-notes/desktop`, 2026-09-06,
/// **with the page header above them** — that preamble is not decoration, it is
/// what makes this fixture able to fail. Verbatim but for the SVG path data,
/// which is several hundred bytes of icon geometry and says nothing about the
/// shape being parsed.
private let qoderIDENotesFixture = #"""
<div class="eyebrow text-caption-c1 text-primary-550">Release Notes</div><header class="mt-2.5 space-y-2.5"><div class="flex flex-col sm:flex-row items-start sm:items-center relative gap-12 min-w-0 justify-between"><h1 id="page-title" class="page-title font-bold text-neutral-950 tracking-tight [overflow-wrap:anywhere]">IDE Release Notes</h1><div class="hidden lg:flex"><div id="page-context-menu" class="relative flex items-center shrink-0 min-w-[143px] justify-end "><div class="flex min-h-15 items-stretch overflow-hidden rounded-[var(--adoc-radius-sm,8px)] border border-line-200 bg-background-light"><button type="button" id="page-context-menu-button" aria-label="Copy page" data-tracker-params="adoc_docs_copy_page" class="flex items-center rounded-none rounded-l-[var(--adoc-radius-sm,8px)] border-r border-line-200 pl-6 pr-4 py-3 font-normal text-neutral-950 transition-colors duration-150 cursor-pointer hover:bg-neutral-150"><div class="flex h-10 items-center gap-2"><svg aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="…"></path></svg><span class="text-[14px] leading-[20px] text-neutral-750">Copy page</span></div></button><button aria-label="More actions" aria-haspopup="menu" aria-expanded="false" type="button" data-tracker-params="adoc_docs_copy_page_more" class="group flex items-center justify-center rounded-none rounded-r-[var(--adoc-radius-sm,8px)] pl-4 pr-6 py-3 transition-colors duration-150 text-neutral-950 cursor-pointer hover:bg-neutral-150 "><span class="inline-flex h-10 items-center justify-center"><svg aria-hidden="true"><path d="…"></path></svg></span></button></div></div></div></div></header><article class="w-full overflow-x-visible mx-auto" style="max-width:var(--adoc-content-max-width-wide)"><div class="prose content mt-4 text-[14px] leading-[22px]"><p class="m-0" node="[object Object]">Release history for IDE.</p></div><div class="flex lg:hidden mt-4"><div id="page-context-menu" class="relative flex items-center shrink-0 min-w-[143px] justify-end "><div class="flex min-h-15 items-stretch overflow-hidden rounded-[var(--adoc-radius-sm,8px)] border border-line-200 bg-background-light"><button type="button" id="page-context-menu-button" aria-label="Copy page" data-tracker-params="adoc_docs_copy_page" class="flex items-center rounded-none rounded-l-[var(--adoc-radius-sm,8px)] border-r border-line-200 pl-6 pr-4 py-3 font-normal text-neutral-950 transition-colors duration-150 cursor-pointer hover:bg-neutral-150"><div class="flex h-10 items-center gap-2"><svg aria-hidden="true"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"></rect><path d="…"></path></svg><span class="text-[14px] leading-[20px] text-neutral-750">Copy page</span></div></button><button aria-label="More actions" aria-haspopup="menu" aria-expanded="false" type="button" data-tracker-params="adoc_docs_copy_page_more" class="group flex items-center justify-center rounded-none rounded-r-[var(--adoc-radius-sm,8px)] pl-4 pr-6 py-3 transition-colors duration-150 text-neutral-950 cursor-pointer hover:bg-neutral-150 "><span class="inline-flex h-10 items-center justify-center"><svg aria-hidden="true"><path d="…"></path></svg></span></button></div></div></div><div class="adoc-mdx-content"><div class="prose content dark:prose-invert max-w-none mt-6"><span data-as="p">This page lists the release history for IDE, with the newest version first.</span>
<div id="1280-2026-09-02"></div>
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="september-2-2026"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#september-2-2026">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">September 2, 2026</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">1.28.0</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Improvements</h3><ul>
<li>Increased the tool execution limit for single tasks in Qoder IDE to 500 rounds, making complex long-chain tasks less likely to be interrupted prematurely.</li>
<li>Tasks interrupted due to depleted credits can now be manually resumed by clicking continue after credits are restored.</li>
</ul></div></div></div>
<div id="1270-2026-08-29"></div>
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="august-29-2026"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#august-29-2026">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">August 29, 2026</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">1.27.0</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Improvements</h3><ul>
<li>Added an enterprise control to disable external network access from the built-in browser, helping organizations meet security and operational management requirements.</li>
<li>Personal edition BYOK now supports OpenAI, Google, and OpenRouter providers, enabling model services to be connected as needed.</li>
</ul></div></div></div>
"""#

/// The newest entry of `docs.qoder.com/release-notes/qoder`, same day and same
/// trim. Note the version reads "Qoder 0.1.8" here where the IDE page's reads a
/// bare "1.28.0".
private let qoderAppNotesFixture = #"""
<div class="update update-container relative flex w-full flex-col items-start gap-2 py-8 lg:flex-row lg:gap-6" id="september-5-2026"><div class="group top-(--scroll-mt) flex w-full shrink-0 flex-col items-start justify-start lg:sticky lg:w-[160px]"><div class="absolute"><a aria-label="Navigate to changelog" class="group/link -ml-10 flex items-center border-0 opacity-0 focus:opacity-100 focus:outline-0 group-hover:opacity-100" href="#september-5-2026">​<div class="flex size-6 items-center justify-center rounded-md bg-white text-stone-400 shadow-sm ring-1 ring-stone-400/30 hover:ring-stone-400/60 group-focus/link:border-2 group-focus/link:border-adoc-primary dark:bg-adoc-bg dark:text-white/50 dark:ring-1 dark:ring-stone-700/25 dark:brightness-[1.35] dark:group-focus/link:border-adoc-primary-light dark:hover:ring-white/20 dark:hover:brightness-150"><svg aria-hidden="true"><path d="…"></path></svg></div></a></div><div class="flex grow-0 cursor-pointer items-center justify-center rounded-lg bg-adoc-primary/10 px-2 py-1 font-medium text-adoc-primary text-sm" contentEditable="false" data-component-part="update-label">September 5, 2026</div><div class="wrap-break-word mt-3 max-w-[160px] px-1 text-adoc-text-secondary text-sm dark:text-adoc-text-tertiary" contentEditable="false" data-component-part="update-description">Qoder 0.1.8</div></div><div class="max-w-full flex-1 overflow-hidden px-0.5"><div class="prose-sm" data-component-part="update-content"><h3>Custom Base URLs for BYOK</h3><h4>Features</h4><ul>
<li><strong>Custom BYOK endpoints</strong>: Personal plan BYOK now supports custom Base URLs for any OpenAI- or Anthropic-compatible model service.</li>
</ul><h4>Improvements</h4><ul>
<li><strong>Workspace Search</strong>: You can now search for content directly within the Markdown preview.</li>
<li><strong>Installer</strong>: Better process detection and install recovery on Windows</li>
<li><strong>Extension Market</strong>: Smoother category switching and detail layout</li>
</ul><h4>Fixes</h4><ul>
<li>Fixed messages lost after repeated context compression</li>
<li>Fixed MCP OAuth negotiation failure diagnostics</li>
<li>Fixed Worktree init failure with no retry option</li>
<li>Fixed voice input floating window position not preserved</li>
</ul></div></div></div>
"""#

/// The same two releases as they appear in the Next.js RSC payload the SAME page
/// also carries, verbatim (2026-09-06). Kept so the claim about it stays honest:
/// see `theRSCPayloadCopyAddsNoEntries` for what it does and does not threaten.
private let qoderRSCPayloadFixture = #"""
\"content\":[[\"$\",\"span\",null,{\"data-as\":\"p\",\"children\":\"This page lists the release history for IDE, with the newest version first.\"}],\"\\n\",[\"$\",\"div\",null,{\"id\":\"1280-2026-09-02\"}],\"\\n\",[\"$\",\"$L19\",null,{\"id\":\"september-2-2026\",\"label\":\"September 2, 2026\",\"description\":\"1.28.0\",\"tags\":\"$undefined\",\"isVisible\":true,\"children\":[[\"$\",\"h3\",null,{\"children\":\"Improvements\"}],[\"$\",\"ul\",null,{\"children\":[\"\\n\",[\"$\",\"li\",null,{\"children\":\"Increased the tool execution limit for single tasks in Qoder IDE to 500 rounds, making complex long-chain tasks less likely to be interrupted prematurely.\"}],\"\\n\",[\"$\",\"li\",null,{\"children\":\"Tasks interrupted due to depleted credits can now be manually resumed by clicking continue after credits are restored.\"}],\"\\n\"]}]]}],\"\\n\",[\"$\",\"div\",null,{\"id\":\"1270-2026-08-29\"}],\"\\n\",[\"$\",\"$L19\",null,{\"id\":\"august-29-2026\",\"label\":\"August 29, 2026\",\"description\":\"1.27.0\",\"tags\":\"$undefined\",\"isVisible\":true,\"children\":[[\"$\",\"h3\",null,{\"children\":\"Improvements\"}],[\"$\",\"ul\",null,{\"children\":[\"\\n\",[\"$\",\"li\",null,{\"children\":\"Added an enterprise control to disable external network access from the built-in browser, helping organizations meet security and operational management requirements.\"}],\"\\n\",[\"$\",\"li\",null,{\"children\":\"Personal edition BYOK now supports OpenAI, Google, and OpenRouter providers, enabling model services to
"""#

@Suite struct QoderRecipeTests {

    private func probe(_ bundleID: String) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
    }

    private func installPattern(_ recipe: VendorProbeRecipe) throws -> String {
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern for \(recipe.bundleID)")
            return ""
        }
        #expect(spec.kind == .zip)
        return pattern
    }

    // MARK: - Qoder IDE

    /// `productVersion`, not `name` and emphatically not `version` — the last is
    /// the commit. A pattern that drifted onto it would compare a 40-hex string
    /// against `1.27.0` forever, which is the one failure this app can produce
    /// that still looks like a working recipe.
    @Test func ideReadsProductVersionRatherThanTheCommit() throws {
        let recipe = try probe("com.qoder.ide")
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderIDEUpdateFixture, pattern: recipe.versionPattern) == "1.28.0")
        #expect(!recipe.versionPattern.contains(#""version""#) || recipe.versionPattern.contains("productVersion"))
    }

    /// The endpoint is conditional — it answers 204 with an EMPTY BODY when the
    /// commit you name is already newest — so the request has to be the
    /// unconditional `latest` sentinel and never this machine's commit. An empty
    /// body must read as a failure, not as "up to date".
    @Test func ideAsksTheUnconditionalLatestSentinel() throws {
        let recipe = try probe("com.qoder.ide")
        #expect(recipe.url.absoluteString
            == "https://center.qoder.sh/algo/api/update/darwin-arm64/stable/latest")
        #expect(VendorProbeRecipe.extractVersion(from: "", pattern: recipe.versionPattern) == nil)
    }

    /// The install spec takes the zip the API itself names, and only the arm64
    /// one: the same server answers `/darwin/stable/latest` with a byte-identical
    /// document whose only difference is `darwin-x64` in the URL.
    @Test func ideInstallsTheArm64ZipTheAPINames() throws {
        let recipe = try probe("com.qoder.ide")
        let pattern = try installPattern(recipe)
        #expect(VendorProbeRecipe.extractVersion(from: qoderIDEUpdateFixture, pattern: pattern)
            == "https://qoder-ide.oss-accelerate.aliyuncs.com/release/1.28.0/Qoder-darwin-arm64.zip")
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderIDEIntelUpdateFixture, pattern: pattern) == nil)
    }

    /// `timestamp` is epoch MILLISECONDS; `ReleaseDate` reads that window as ms,
    /// so the row gets an exact publish time rather than a date in 58 700 AD.
    @Test func ideReadsTheEpochMillisecondTimestamp() throws {
        let recipe = try probe("com.qoder.ide")
        let pattern = try #require(recipe.publishedAtPattern)
        let stamp = try #require(
            VendorProbeRecipe.extractVersion(from: qoderIDEUpdateFixture, pattern: pattern))
        #expect(stamp == "1788277155505")
        let parsed = try #require(ReleaseDate.parse(stamp))
        #expect(abs(parsed.timeIntervalSince1970 - 1_788_277_155.505) < 1)
    }

    // MARK: - Qoder (the app)

    /// `"version"` must not be satisfied by `"schemaVersion"`, whose value is the
    /// unquoted integer 1 — a pattern that matched it would report "1" as the
    /// app's version and never move again.
    @Test func appReadsTheManifestVersionAndNotTheSchemaVersion() throws {
        let recipe = try probe("com.qoder.app")
        #expect(qoderAppManifestFixture.contains(#""schemaVersion": 1"#))
        #expect(VendorProbeRecipe.extractVersion(
            from: qoderAppManifestFixture, pattern: recipe.versionPattern) == "0.1.8")
    }

    /// arm64 only, and the `.exe` two entries below is the neighbour that proves
    /// the anchor is doing something.
    @Test func appInstallsTheArm64ZipTheManifestNames() throws {
        let recipe = try probe("com.qoder.app")
        let pattern = try installPattern(recipe)
        #expect(VendorProbeRecipe.extractVersion(from: qoderAppManifestFixture, pattern: pattern)
            == "https://download.qoder.com.cn/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip")
    }

    /// The manifest is served from `download.qoder.com` and names artifacts on
    /// `download.qoder.com.cn`. Both hosts serve the same object, and the vendor's
    /// own installer fetches the `.cn` one, so the pattern accepts either rather
    /// than pinning whichever host we happened to fetch the manifest from.
    @Test func appAcceptsEitherOfTheVendorsTwoDownloadHosts() throws {
        let recipe = try probe("com.qoder.app")
        let pattern = try installPattern(recipe)
        let comHost = qoderAppManifestFixture.replacingOccurrences(
            of: "download.qoder.com.cn", with: "download.qoder.com")
        #expect(VendorProbeRecipe.extractVersion(from: comHost, pattern: pattern)
            == "https://download.qoder.com/qoder-app/releases/0.1.8/Qoder-mac-arm64.zip")
    }

    /// Two products, two bundle ids, two Team IDs — and so two recipes that must
    /// never be collapsed into one. The Teams are the vendor's own statement, from
    /// the installer stub's `installer-manifest.json`.
    @Test func theTwoProductsAreSeparateRecipesOnSeparateEndpoints() throws {
        let ide = try probe("com.qoder.ide")
        let app = try probe("com.qoder.app")
        #expect(ide.url.host != app.url.host)
        #expect(ide.changelogURL != app.changelogURL)
    }

    // MARK: - Release notes

    private func notes(_ bundleID: String, _ fixture: String) throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID))
        #expect(recipe.source.host == "docs.qoder.com")
        return try #require(ChangelogExtractor.extract(from: fixture, using: recipe))
    }

    @Test func ideNotesParseVersionDateAndBullets() throws {
        let log = try notes("com.qoder.ide", qoderIDENotesFixture)
        #expect(log.entries.map(\.version) == ["1.28.0", "1.27.0"])
        #expect(log.entries.first?.date == "September 2, 2026")
        #expect(log.entries.first?.items.count == 2)
        #expect(log.entries.first?.items.first?.hasPrefix(
            "Increased the tool execution limit") == true)
    }

    /// The app's page prefixes its version with the product name; the shared
    /// pattern makes that optional, so "Qoder 0.1.8" still yields "0.1.8" — not
    /// "0.1.8" prefixed, and not nothing.
    @Test func appNotesStripTheProductNameFromTheVersion() throws {
        let log = try notes("com.qoder.app", qoderAppNotesFixture)
        #expect(log.entries.map(\.version) == ["0.1.8"])
        #expect(log.entries.first?.date == "September 5, 2026")
        // Three `<ul>`s under three `<h4>`s: 1 feature + 3 improvements + 4 fixes.
        #expect(log.entries.first?.items.count == 8)
        #expect(log.entries.first?.items.contains {
            $0.contains("Fixed messages lost after repeated context compression")
        } == true)
    }

    /// The docs page also embeds a Next.js RSC payload repeating every release in
    /// JSON-escaped form, so it is worth saying exactly what protects against it —
    /// and it is NOT the `data-component-part` anchors. Measured 2026-09-06: that
    /// payload spells its fields as `\"description\":\"1.28.0\"` and contains no
    /// `</div>` at all, so the entry pattern's element structure alone excludes it.
    /// Appending it to a real page's entries changes neither the count nor the
    /// versions.
    @Test func theRSCPayloadCopyAddsNoEntries() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        #expect(qoderRSCPayloadFixture.contains("1.28.0"))
        #expect(!qoderRSCPayloadFixture.contains("</div>"))
        #expect(ChangelogExtractor.extract(from: qoderRSCPayloadFixture, using: recipe) == nil)
        let combined = qoderIDENotesFixture + "\n" + qoderRSCPayloadFixture
        let log = try #require(ChangelogExtractor.extract(from: combined, using: recipe))
        #expect(log.entries.map(\.version) == ["1.28.0", "1.27.0"])
    }

    /// What the `data-component-part` anchors ARE worth, measured rather than
    /// assumed: without them the newest entry's date is read off the page's own
    /// `<div class="eyebrow">Release Notes</div>` header instead of the release's
    /// label. Entry count and versions are unaffected — the loss is one wrong date
    /// on the entry the pane shows first, every time. This is why the fixture
    /// above carries the header.
    @Test func theAnchorsAreWhatKeepThePageHeaderOutOfTheNewestDate() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.qoder.ide"))
        #expect(qoderIDENotesFixture.contains(#">Release Notes</div>"#))
        let log = try #require(ChangelogExtractor.extract(from: qoderIDENotesFixture, using: recipe))
        #expect(log.entries.first?.date == "September 2, 2026")
        #expect(log.entries.first?.date != "Release Notes")
    }
}
