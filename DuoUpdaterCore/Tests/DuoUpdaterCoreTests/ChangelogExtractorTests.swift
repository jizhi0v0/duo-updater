import Testing
import Foundation
@testable import DuoUpdaterCore

// A trimmed fixture mirroring CleanShot's real markup (Nuxt `data-v-*` attrs,
// `&quot;` entity, multiple entries, one with several items and one with a single
// item). Kept inline so the parser is tested offline, no network.
private let cleanshotFixture = """
<div class="col-1224" data-v-62d3e76f><h1 class="heading">Changelog</h1>
<section class="versions" data-v-62d3e76f>
<div class="version" data-v-62d3e76f><div class="number" data-v-62d3e76f>4.8.8</div>\
<div class="date" data-v-62d3e76f>23 March, 2026</div>\
<ul class="changes" data-v-62d3e76f>\
<li class="change" data-v-62d3e76f>Fixed issue with recording microphone</li>\
<li class="change" data-v-62d3e76f>Fixed bug with the &quot;Ask for Name&quot; dialog not receiving focus</li>\
<li class="change" data-v-62d3e76f>Minor fixes &amp; UX improvements</li>\
</ul></div>\
<div class="version" data-v-62d3e76f><div class="number" data-v-62d3e76f>4.8.7</div>\
<div class="date" data-v-62d3e76f>22 December, 2025</div>\
<ul class="changes" data-v-62d3e76f>\
<li class="change" data-v-62d3e76f>Fixed an issue that caused CleanShot to crash</li>\
</ul></div>\
</section></div>
"""

// Trimmed real markup from tableplus.com/osx/changelog: two version blocks,
// each with the standard h3/h4/h5 header then a <ul> of change items.
private let tablePlusFixture = """
<h3 id="version-710-710---liquid-glass">Version 7.1.0 (710) - Liquid Glass</h3>
<h4 id="release-date-26-may-2026">Release date: 26 May 2026.</h4>
<h5 id="download"><a href="https://files.tableplus.com/macos/710/TablePlus.dmg">Download</a></h5>
<h5 id="sha-abc">SHA: <code class="language-plaintext highlighter-rouge">abc123</code></h5>

<ul>
  <li>[DeepSeek] Fixed a bug with tool invocation.</li>
  <li>Fixed a bug where the Set Contains button was not displayed on the right sidebar.</li>
  <li>Added an auto pretty JSON feature.</li>
</ul>

<h3 id="version-706-706---liquid-glass">Version 7.0.6 (706) - Liquid Glass</h3>
<h4 id="release-date-21-may-2026">Release date: 21 May 2026.</h4>
<h5 id="download-1"><a href="https://files.tableplus.com/macos/706/TablePlus.dmg">Download</a></h5>
<h5 id="sha-def">SHA: <code class="language-plaintext highlighter-rouge">def456</code></h5>

<ul>
  <li>Optimize Liquid Glass</li>
  <li>Bug fixes and improvements.</li>
</ul>
"""

// A trimmed fixture mirroring LM Studio's real Next.js /changelog index markup:
// the version lives in a `sr-only` span on the entry's anchor, the notes are in a
// `markdown-body` div closed by three nested </div>, there is no per-entry date,
// and items use nested <ul> for sub-bullets (the second item below) plus a `&gt;`
// entity to prove decoding. Two entries, the second with a single item.
private let lmStudioFixture = """
<a class="absolute inset-0 z-0" href="/changelog/lmstudio-v0.4.15"><span class="sr-only">LM Studio 0.4.15</span></a>\
<div class="pointer-events-none relative z-10"><div class="flex flex-col gap-2">\
<h2 class="text-base font-semibold"><span class="rounded-sm underline">LM Studio 0.4.15</span></h2>\
<div class="relative h-40 overflow-hidden md:h-44">\
<div class="markdown-body blog-markdown-body text-sm leading-6">\
<p><strong class="text-foreground/95">Build 2</strong></p>
<ul class="list-disc">
<li>[CUDA] Added tensor parallelism support for multi-GPU model loading</li>
<li>LM Studio Engine Protocol beta 2
<ul class="list-disc">
<li>Turn it on in Settings &gt; Developer</li>
</ul>
</li>
</ul>
</div></div></div>\
<a class="absolute inset-0 z-0" href="/changelog/lmstudio-v0.4.14"><span class="sr-only">LM Studio 0.4.14</span></a>\
<div class="pointer-events-none relative z-10"><div class="flex flex-col gap-2">\
<h2 class="text-base font-semibold"><span class="rounded-sm underline">LM Studio 0.4.14</span></h2>\
<div class="relative h-40 overflow-hidden md:h-44">\
<div class="markdown-body blog-markdown-body text-sm leading-6">\
<p><strong class="text-foreground/95">Build 4</strong></p>
<ul class="list-disc">
<li>Stable release of MTP Speculative Decoding!</li>
</ul>
</div></div></div>
"""

// Trimmed real markup from conductor.build/changelog: two articles, one with 3
// list items (0.61.2) and one with 1 item (0.61.1). Both share the font-mono /
// text-muted-foreground / min-w-0 structure present in every Conductor entry.
private let conductorFixture = """
<article id="0-61-2" class="relative mb-14">\
<div class="mb-5"><div class="flex flex-col items-start gap-3"><a href="/changelog/0.61.2-bug-fixes">\
<div class="inline-flex font-mono tracking-wider uppercase">0.61.2</div></a>\
<span class="text-sm text-muted-foreground">June 1, 2026</span>\
</div></div>\
<div class="min-w-0">\
<a href="/changelog/0.61.2-bug-fixes">Bug fixes</a>\
<h3>Fixes</h3>\n<ul>\n\
<li class="text-base text-foreground">Fixed an issue with linking workspaces.</li>\n\
<li class="text-base text-foreground">Fixed an issue where the agent could hang.</li>\n\
<li class="text-base text-foreground">Fixed an issue where the plan approval message might appear out of order.</li>\n\
</ul></div></article>\
<article id="0-61-1" class="relative mb-14">\
<div class="mb-5"><div class="flex flex-col items-start gap-3"><a href="/changelog/0.61.1-claude-code-2-1-156">\
<div class="inline-flex font-mono tracking-wider uppercase">0.61.1</div></a>\
<span class="text-sm text-muted-foreground">May 31, 2026</span>\
</div></div>\
<div class="min-w-0">\
<a href="/changelog/0.61.1-claude-code-2-1-156">Claude Code 2.1.156</a>\
<h3>Fixes</h3>\n<ul>\n\
<li class="text-base text-foreground">Bumped the Claude Code binary to fix Opus 4.8 thinking&#x2011;block errors.</li>\n\
</ul></div></article>
"""

// Trimmed real markup from freemacsoft.net/appcleaner/releasenotes.html: two
// version blocks to cover the typical single-item and multi-item cases.
private let appCleanerFixture = """
<div class="releasenotes">
  <h2>AppCleaner 3.6.8 <span class="releasedate">- 4 July, 2023</span></h2>
  <ul>
    <li>New app icon (finally!), thanks to Octavio Viotti.</li>
    <li>Allow searching for related files of system apps, although system apps cannot be removed.</li>
  </ul>

  <h2>AppCleaner 3.6.7 <span class="releasedate">- 9 Dec, 2022</span></h2>
  <ul>
    <li>Fixed a bug causing SmartDelete to crash.</li>
  </ul>
</div>
"""

// Trimmed fixture from releases.chatwise.app/releases. The real endpoint is JSON,
// with markdown changelog lines stored as escaped strings.
private let chatWiseFixture = """
[
  {
    "version":"26.5.3",
    "changelog":"- Add Claude Opus 4.8 and adjust Claude reasoning support\\n",
    "assets":[],
    "date":"2026-05-29T07:02:44.116Z"
  },
  {
    "version":"26.5.2",
    "changelog":"- Add `curl.md` web fetch provider support\\n- Custom provider: add Responses API support for openai-compatible providers\\n- Set user-agent for LLM requests to `ChatWise/$version`\\n",
    "assets":[],
    "date":"2026-05-27T06:20:07.532Z"
  }
]
"""

// Trimmed real markup from the latest VS Code updates page: one release header
// and its highlight bullets.
private let vscodeFixture = """
<h1>Visual Studio Code 1.122</h1>
<p>Follow us on <a href="https://www.linkedin.com/showcase/vs-code">LinkedIn</a></p>
<hr>
<p><em>Release date: May 28, 2026</em></p>
<p><strong>Update 1.122.1</strong>: The update addresses these <a href="https://github.com/microsoft/vscode/issues?q=is%3Aissue+is%3Aclosed+milestone%3A1.122.1">issues</a>.</p>
<p>Downloads: Windows: <a href="https://update.code.visualstudio.com/1.122.1/win32-x64-user/stable">x64</a></p>
<hr>
<p>Welcome to the 1.122 release of Visual Studio Code.</p>
<ul>
<li>
<p><a href="#_1m-context-window-for-anthropic-and-openai-models">Larger context windows</a>: Support for 1M context windows for Anthropic and OpenAI models.</p>
</li>
<li>
<p><a href="#_use-byok-without-a-github-sign-in">Air-gapped BYOK</a>: Use your own language models, even when you're not connected.</p>
</li>
<li>
<p><a href="#_emulate-devices">Browser device emulation</a>: Test your website's responsiveness across different devices directly in the integrated browser.</p>
</li>
</ul>
<p>Happy Coding!</p>
"""

// Trimmed real markup from developers.openai.com/codex/changelog. Includes one
// prose-only general entry and one bullet-heavy app entry, while intentionally
// excluding the `github-release-*` CLI items.
private let codexFixture = """
<section class="flex flex-col gap-6" id="month-2026-06-section" aria-labelledby="month-2026-06" data-changelog-month-section>
<div class="flex items-center gap-3 text-gray-900 dark:text-white">
  <h2 id="month-2026-06" data-changelog-month class="text-xl font-semibold tracking-tight"> June 2026 </h2>
</div>
<ul class="[&>li+li]:mt-12">
<li id="codex-2026-06-01" class="scroll-mt-28" data-product="codex" data-products="codex" data-codex-topics="general" aria-hidden="false">
  <div class="flex flex-wrap flex-col items-baseline gap-2">
    <div class="flex flex-wrap items-center gap-2"><time class="text-sm text-secondary">2026-06-01</time></div>
    <h3 class="group flex items-center gap-2 heading-xl mb-4"><span> Use Codex with Amazon Bedrock </span></h3>
  </div>
  <article class="prose-content prose dark:prose-invert max-w-none pt-2 pb-6 prose-img:w-full break-words">
    <p>Codex can now use supported OpenAI models available through Amazon Bedrock.</p>
    <p>Configure <a href="/codex/amazon-bedrock">Amazon Bedrock as your model provider</a> to run Codex locally with AWS-managed authentication, account controls, and billing.</p>
  </article>
</li>
<li id="codex-2026-05-28-app" class="scroll-mt-28" data-product="codex" data-products="codex" data-codex-topics="codex-app" aria-hidden="false">
  <div class="flex flex-wrap flex-col items-baseline gap-2">
    <div class="flex flex-wrap items-center gap-2"><time class="text-sm text-secondary">2026-05-29</time></div>
    <h3 class="group flex items-center gap-2 heading-xl mb-4"><span> Computer use and mobile access on Windows <span class="text-tertiary"> 26.527</span> </span></h3>
  </div>
  <article class="prose-content prose dark:prose-invert max-w-none pt-2 pb-6 prose-img:w-full break-words">
    <h3 id="new-features">New features</h3>
    <ul>
      <li><p><a href="/codex/app/computer-use">Computer Use</a> now works on Windows. Codex can control Windows apps the same way it already can on macOS.</p></li>
      <li><p><a href="/codex/remote-connections">Remote control</a> now supports Windows devices.</p></li>
    </ul>
  </article>
</li>
<li id="github-release-332669350" class="scroll-mt-28" data-product="codex" data-products="codex" data-codex-topics="codex-cli" aria-hidden="false">
  <div class="flex flex-wrap items-center gap-2"><time class="text-sm text-secondary">2026-06-01</time></div>
  <h3 class="group flex items-center gap-2 heading-xl mb-4"><span>Codex CLI<span class="text-tertiary"> 0.136.0</span></span></h3>
</li>
</ul>
</section>
"""

// Trimmed real response from client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM:
// three entries chosen to cover single-item (V16.5.0.30757), multi-item numbered
// (v16.0.0.22931), and multi-item unnumbered (V16.3.0.29006). JSON uses \uXXXX
// for all non-ASCII text and \/ for forward slashes inside HTML attributes — both
// decoded by ChangelogExtractor.decodeEntities.
// Fixture uses the raw server encoding: \uXXXX for non-ASCII, \/ for forward
// slashes inside HTML strings — both must survive the extractor unchanged unless
// decodeEntities resolves them.
private let aweSunFixture = #"""
{"logs":[{"logid":3299,"softwareid":187,"versionid":"3239","lang":"zh","logs":"<ol><li>V16.5.0.30757<\/li><li>1、修复已知bug<\/li><\/ol>","memoen":"V16.5.0.30757\r\n1、修复已知bug","memo":"V16.5.0.30757\r\n1、修复已知bug","updatedate":"2026-05-28 00:00:00","createtime":"2026-05-28 14:41:53"},{"logid":2881,"softwareid":187,"versionid":"2822","lang":"zh","logs":"<ol><li>v16.0.0.22931<\/li><li>1、【优化】功能交互，提升操作体验<\/li><li>2、【修复】已知问题，提升稳定性<\/li><\/ol>","memoen":"v16.0.0.22931 \r\n1、【优化】功能交互，提升操作体验\r\n2、【修复】已知问题，提升稳定性","memo":"v16.0.0.22931 \r\n1、【优化】功能交互，提升操作体验\r\n2、【修复】已知问题，提升稳定性","updatedate":"2025-07-17 00:00:00","createtime":"2025-07-17 14:57:37"},{"logid":3212,"softwareid":187,"versionid":"3153","lang":"zh","logs":"<ol><li>V16.3.0.29006<\/li><li>【新增】向日葵 MCP<\/li><li>【新增】端上支持分组<\/li><li>【新增】网络代理<\/li><li>【新增】跟随被控鼠标自动切换屏幕<\/li><li>【新增】支持设置低 \/ 中 \/ 高码率<\/li><li>【新增】Mac 跨平台文件拖拽<\/li><li>【新增】Mac 主控 HDR 支持<\/li><li>【新增】远程控控支持切换触摸 \/ 鼠标模式<\/li><li>【新增】智能远控硬件线缆状态<\/li><li>【优化】若干操作交互体验<\/li><li>【修复】若干已知问题<\/li><\/ol>","memoen":"V16.3.0.29006\r\n【新增】向日葵 MCP","memo":"V16.3.0.29006\r\n【新增】向日葵 MCP","updatedate":"2026-03-26 00:00:00","createtime":"2026-03-26 16:53:17"}]}
"""#

@Test func extractsAweSunEntriesAndDecodesJSONEscapes() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.oray.sunlogin.macclient"))
    let changelog = try #require(ChangelogExtractor.extract(from: aweSunFixture, using: recipe))

    #expect(changelog.entries.count == 3)

    // Entry 0: single item, \uXXXX Chinese text decoded.
    #expect(changelog.entries[0].version == "V16.5.0.30757")
    #expect(changelog.entries[0].date == "2026-05-28")
    #expect(changelog.entries[0].items.count == 1)
    #expect(changelog.entries[0].items[0] == "1、修复已知bug")

    // Entry 1: two numbered items.
    #expect(changelog.entries[1].version == "v16.0.0.22931")
    #expect(changelog.entries[1].date == "2025-07-17")
    #expect(changelog.entries[1].items.count == 2)
    #expect(changelog.entries[1].items[0] == "1、【优化】功能交互，提升操作体验")
    #expect(changelog.entries[1].items[1] == "2、【修复】已知问题，提升稳定性")

    // Entry 2: eleven unnumbered items; \/ inside text decoded to /.
    #expect(changelog.entries[2].version == "V16.3.0.29006")
    #expect(changelog.entries[2].date == "2026-03-26")
    #expect(changelog.entries[2].items.count == 11)
    #expect(changelog.entries[2].items[0] == "【新增】向日葵 MCP")
    #expect(changelog.entries[2].items[4] == "【新增】支持设置低 / 中 / 高码率")
    #expect(changelog.entries[2].items[10] == "【修复】若干已知问题")
}

@Test func extractsAppCleanerEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.freemacsoft.AppCleaner"))
    let changelog = try #require(ChangelogExtractor.extract(from: appCleanerFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "3.6.8")
    #expect(changelog.entries[0].date == "4 July, 2023")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "New app icon (finally!), thanks to Octavio Viotti.")
    #expect(changelog.entries[1].version == "3.6.7")
    #expect(changelog.entries[1].date == "9 Dec, 2022")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0] == "Fixed a bug causing SmartDelete to crash.")
}

@Test func extractsChatWiseEntriesFromJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "app.chatwise"))
    let changelog = try #require(ChangelogExtractor.extract(from: chatWiseFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "26.5.3")
    #expect(changelog.entries[0].date == "2026-05-29T07:02:44.116Z")
    #expect(changelog.entries[0].items.count == 1)
    #expect(changelog.entries[0].items[0] == "Add Claude Opus 4.8 and adjust Claude reasoning support")
    #expect(changelog.entries[1].version == "26.5.2")
    #expect(changelog.entries[1].items.count == 3)
    #expect(changelog.entries[1].items[1] == "Custom provider: add Responses API support for openai-compatible providers")
}

@Test func extractsLatestVSCodeReleaseHighlights() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.VSCode"))
    let changelog = try #require(ChangelogExtractor.extract(from: vscodeFixture, using: recipe))

    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "1.122")
    #expect(changelog.entries[0].date == "May 28, 2026")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[0].items[0] == "Larger context windows: Support for 1M context windows for Anthropic and OpenAI models.")
    #expect(changelog.entries[0].items[2] == "Browser device emulation: Test your website's responsiveness across different devices directly in the integrated browser.")
}

@Test func extractsCodexAppEntriesAndSkipsGeneralAndCLIReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.openai.codex"))
    let changelog = try #require(ChangelogExtractor.extract(from: codexFixture, using: recipe))

    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].title == "Computer use and mobile access on Windows")
    #expect(changelog.entries[0].version == "26.527")
    #expect(changelog.entries[0].date == "2026-05-29")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "Computer Use now works on Windows. Codex can control Windows apps the same way it already can on macOS.")
}

// Trimmed real markup from git-fork.com/releasenotes: two version blocks. Each
// opens with an h4 (version) and h5 (date), then any number of media items
// (badge + media-body/p.lead). The second block starts a new h4, which also
// acts as the end-sentinel for the first block's entryPattern lookahead.
private let forkFixture = """
<div class="col-sm-6">
    <h4 class="header4 release-notes">Fork 2.67</h4>
</div>
<div class="col-sm-6">
    <h5 class="date">15 May 2026</h5>
</div>
<hr />
<div class="row">
    <div class="col-sm-12">
        <div class="media">
            <div class="media-left">
                <p class="lead text-right"><span class="badge badge-success"> New </span></p>
            </div>
            <div class="media-body">
                <p class="lead">New keyboard shortcut for create tag: Shift+Cmd+G</p>
            </div>
        </div>
        <div class="media">
            <div class="media-left">
                <p class="lead text-right"><span class="badge badge-danger"> Fixed </span></p>
            </div>
            <div class="media-body">
                <p class="lead">Submodule add not updating nested submodules</p>
            </div>
        </div>
    </div>
</div>

<div class="col-sm-6">
    <h4 class="header4 release-notes">Fork 2.64</h4>
</div>
<div class="col-sm-6">
    <h5 class="date">6 Mar 2026</h5>
</div>
<hr />
<div class="row">
    <div class="col-sm-12">
        <div class="media">
            <div class="media-body">
                <p class="lead">Add Codex support for AI commit messages and code review</p>
            </div>
        </div>
    </div>
</div>
"""

// Trimmed real markup from ghostty.org/docs/install/release-notes/1-3-1. The
// version and date are in the <meta name="description"> near the top; items
// come from <li class="...weightRegular..."> elements in the Full Changelog
// section (id="full-changelog-2"). Nav <li> elements (no class) are skipped.
private let ghosttyFixture = """
<meta name="description" content="Release notes for Ghostty 1.3.1, released on March 13, 2026."/>
<h1 class="Text-module__3468va__text">Ghostty 1.3.1</h1>
<div id="full-changelog-2"><div class="JumplinkHeader-module__SpWIGW__content JumplinkHeader-module__SpWIGW__h2"><h2>Full Changelog</h2></div></div>
<p class="Text-module__3468va__text">In each section, we try to sort improvements before bug fixes.</p>
<ul>
<li class="Text-module__3468va__text pretendardstdvariable_75f3002f-module__N7oTcq__className Text-module__3468va__weightRegular">New configuration: <code>progress-style</code> controls whether OSC 9;4 progress bars are shown. <a href="https://github.com/ghostty-org/ghostty/issues/11289">#11289</a></li>
<li class="Text-module__3468va__text pretendardstdvariable_75f3002f-module__N7oTcq__className Text-module__3468va__weightRegular">macOS: Fix stale mouse state leading to phantom drag/selection behavior after focus changes. <a href="https://github.com/ghostty-org/ghostty/issues/11276">#11276</a></li>
</ul>
</main>
"""

@Test func extractsForkEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.DanPristupov.Fork"))
    let changelog = try #require(ChangelogExtractor.extract(from: forkFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "2.67")
    #expect(changelog.entries[0].date == "15 May 2026")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "New keyboard shortcut for create tag: Shift+Cmd+G")
    #expect(changelog.entries[0].items[1] == "Submodule add not updating nested submodules")
    #expect(changelog.entries[1].version == "2.64")
    #expect(changelog.entries[1].date == "6 Mar 2026")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0] == "Add Codex support for AI commit messages and code review")
}

@Test func extractsGhosttyEntryFromVersionPage() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.mitchellh.ghostty"))
    let changelog = try #require(ChangelogExtractor.extract(from: ghosttyFixture, using: recipe))

    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "1.3.1")
    #expect(changelog.entries[0].date == "March 13, 2026")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "New configuration: progress-style controls whether OSC 9;4 progress bars are shown. #11289")
    #expect(changelog.entries[0].items[1] == "macOS: Fix stale mouse state leading to phantom drag/selection behavior after focus changes. #11276")
}

@Test func extractsTablePlusEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.tinyapp.TablePlus"))
    let changelog = try #require(ChangelogExtractor.extract(from: tablePlusFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "7.1.0")
    #expect(changelog.entries[0].date == "26 May 2026")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[0].items[0] == "[DeepSeek] Fixed a bug with tool invocation.")
    #expect(changelog.entries[0].items[2] == "Added an auto pretty JSON feature.")
    #expect(changelog.entries[1].version == "7.0.6")
    #expect(changelog.entries[1].date == "21 May 2026")
    #expect(changelog.entries[1].items.count == 2)
    #expect(changelog.entries[1].items[0] == "Optimize Liquid Glass")
}

@Test func extractsConductorEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.conductor.app"))
    let changelog = try #require(ChangelogExtractor.extract(from: conductorFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "0.61.2")
    #expect(changelog.entries[0].date == "June 1, 2026")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[0].items[0] == "Fixed an issue with linking workspaces.")
    #expect(changelog.entries[1].version == "0.61.1")
    #expect(changelog.entries[1].date == "May 31, 2026")
    #expect(changelog.entries[1].items.count == 1)
}

@Test func extractsLMStudioEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.elementlabs.lmstudio"))
    let changelog = try #require(ChangelogExtractor.extract(from: lmStudioFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "0.4.15")
    #expect(changelog.entries[0].date == nil)            // index prints no date
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "[CUDA] Added tensor parallelism support for multi-GPU model loading")
    #expect(changelog.entries[1].version == "0.4.14")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0] == "Stable release of MTP Speculative Decoding!")
}

@Test func decodesEntitiesAndFoldsNestedListForLMStudio() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.elementlabs.lmstudio"))
    let changelog = try #require(ChangelogExtractor.extract(from: lmStudioFixture, using: recipe))

    // &gt; → > and the nested sub-bullet is folded into its parent line.
    #expect(changelog.entries[0].items[1].contains("Turn it on in Settings > Developer"))
}

@Test func extractsCleanShotEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "pl.maketheweb.cleanshotx"))
    let changelog = try #require(ChangelogExtractor.extract(from: cleanshotFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "4.8.8")
    #expect(changelog.entries[0].date == "23 March, 2026")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[1].version == "4.8.7")
    #expect(changelog.entries[1].items.count == 1)
}

@Test func decodesHTMLEntitiesInItems() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "pl.maketheweb.cleanshotx"))
    let changelog = try #require(ChangelogExtractor.extract(from: cleanshotFixture, using: recipe))

    // &quot; → " and &amp; → &
    #expect(changelog.entries[0].items[1] == "Fixed bug with the \"Ask for Name\" dialog not receiving focus")
    #expect(changelog.entries[0].items[2] == "Minor fixes & UX improvements")
}

@Test func registryIsCaseInsensitiveAndMissesUnknown() {
    #expect(ChangelogRecipeRegistry.recipe(forBundleID: "PL.MakeTheWeb.CleanShotX") != nil)
    #expect(ChangelogRecipeRegistry.recipe(forBundleID: "com.example.nope") == nil)
    #expect(ChangelogRecipeRegistry.recipe(forBundleID: nil) == nil)
}

@Test func entryWithNoItemsIsDropped() {
    // A version block with an empty list contributes nothing; with all blocks
    // empty the extractor returns nil so the UI falls back to the web view.
    let html = """
    <div class="version"><div class="number">9.9.9</div>\
    <div class="date">today</div><ul class="changes"></ul></div>
    """
    let recipe = ChangelogRecipeRegistry.recipe(forBundleID: "pl.maketheweb.cleanshotx")!
    #expect(ChangelogExtractor.extract(from: html, using: recipe) == nil)
}

@Test func invalidPatternDegradesToNil() {
    let recipe = ChangelogRecipe(
        bundleID: "x",
        source: URL(string: "https://example.com")!,
        entryPattern: "(unclosed",          // malformed → compile fails
        itemPatterns: ["<li>(?<item>.*?)</li>"])
    #expect(ChangelogExtractor.extract(from: cleanshotFixture, using: recipe) == nil)
}

@Test func maxEntriesCapsOutput() {
    let recipe = ChangelogRecipe(
        bundleID: "pl.maketheweb.cleanshotx",
        source: URL(string: "https://cleanshot.com/changelog")!,
        entryPattern:
            #"<div class="version"[^>]*>\s*<div class="number"[^>]*>(?<version>[^<]+)</div>\s*"#
            + #"(?:<div class="date"[^>]*>(?<date>[^<]*)</div>\s*)?<ul[^>]*class="changes"[^>]*>(?<body>.*?)</ul>"#,
        itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
        maxEntries: 1)
    let changelog = ChangelogExtractor.extract(from: cleanshotFixture, using: recipe)
    #expect(changelog?.entries.count == 1)
    #expect(changelog?.entries.first?.version == "4.8.8")
}

// Trimmed real payload from mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json.
// Content field is Markdown with \\r\\n line separators (raw JSON escapes). Two entries:
// one with a #### feature heading + plain description + bug-fix line, and one with only
// a plain bug-fix line (no #### heading) to cover the simpler layout.
private let postmanFixture = """
{"notes":[{"version":"12.12.7","content":"## Postman 12.12.7\\r\\nMay 30, 2026\\r\\n\\r\\n### Improvements\\r\\n#### Aggregated test results in Postman Flows run logs\\r\\nRun logs in Postman Flows now aggregate and display test results from all **Request** blocks in a single summary view.\\r\\n\\r\\n### Bug fixes\\r\\nResolved an issue in Postman Flows where the environment selector would not respond.\\r\\n","createdAt":"2026-05-30T04:43:09.000Z"},{"version":"12.13.2","content":"## Postman 12.13.2\\r\\nJune 2, 2026\\r\\n\\r\\n### Bug Fixes\\r\\nSome critical bug fixes and enhancements were added in this release.\\r\\n","createdAt":"2026-06-02T02:32:09.000Z"}]}
"""

@Test func extractsPostmanEntriesFromJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.postmanlabs.mac"))
    let changelog = try #require(ChangelogExtractor.extract(from: postmanFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "12.12.7")
    #expect(changelog.entries[0].date == "2026-05-30")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[0].items[0] == "Aggregated test results in Postman Flows run logs")
    #expect(changelog.entries[0].items[1].contains("Run logs in Postman Flows"))
    #expect(changelog.entries[0].items[2].contains("Resolved an issue"))
    #expect(changelog.entries[1].version == "12.13.2")
    #expect(changelog.entries[1].date == "2026-06-02")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0].contains("critical bug fixes"))
}

// Trimmed real markup from update.dcloud.net.cn/hbuilderx/changelog/<version>.html.
// The page is cumulative — all versions in one file. Each version block starts with
// an <h2>, categories are <h3>, and changes are <li>. No explicit date field;
// the version string itself encodes YYYYMMDD (e.g. 5.07.2026041006 = 2026-04-10).
private let hbuilderxFixture = """
<h1 id="hbuilder-x---release-notes">HBuilder X - Release Notes</h1>
<p>======================================</p>
<h2 id="5072026041006">5.07.2026041006</h2>
<h3 id="hbuilder">HBuilder</h3>
<ul>
<li>修复 5.0版本引发的 uni-app iOS安心打包图标没有生效 <a href="https://issues.dcloud.net.cn/pages/issues/detail?id=27902">详情</a></li>
</ul>
<h3 id="uni-app-x">uni-app x</h3>
<ul>
<li>Android平台 修复 5.0版本引发的 API uni.showLoading 调用异常 <a href="https://issues.dcloud.net.cn/pages/issues/detail?id=27821">详情</a></li>
</ul>
<h2 id="5062026033105">5.06.2026033105</h2>
<h3 id="hbuilder-1">HBuilder</h3>
<ul>
<li>macOS平台 修复 5.0版本引发的 iOS 安心打包功能中资源拷贝路径不正确的问题 <a href="https://issues.dcloud.net.cn/pages/issues/detail?id=27379">详情</a></li>
</ul>
"""

@Test func extractsHBuilderXEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "io.dcloud.HBuilderX"))
    let changelog = try #require(ChangelogExtractor.extract(from: hbuilderxFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "5.07.2026041006")
    #expect(changelog.entries[0].date == nil)
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0].contains("uni-app iOS安心打包图标没有生效"))
    #expect(changelog.entries[1].version == "5.06.2026033105")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0].contains("iOS 安心打包功能中资源拷贝路径不正确"))
}

// Trimmed real markup from github.com/ollama/ollama/releases. Two sections:
// v0.24.0 (6 items including a bold model name) and v0.23.4 (2 items). The
// version group strips the leading "v" so stored versions are plain dotted numbers.
private let ollamaFixture = """
<section aria-labelledby="hd-abc123">
  <h2 class="sr-only" id="hd-abc123">v0.24.0</h2>
  <div class="d-flex flex-column flex-md-row">
    <div>
      <div class="mb-2 f4">
        <relative-time class="no-wrap" prefix="" datetime="2026-05-14T12:00:00Z">
          14 May 12:00
        </relative-time>
      </div>
    </div>
    <div>
      <div class="markdown-body tmp-my-3"><ul>
        <li><strong>kimi-k2.6</strong> (with vision support)</li>
        <li>New model: <code>qwen3</code></li>
        <li>Faster inference on Apple Silicon</li>
        <li>Fixed crash on model load failure</li>
        <li>Improved error messages</li>
        <li>Updated dependencies</li>
      </ul></div>
    </div>
  </div>
</section>
<section aria-labelledby="hd-def456">
  <h2 class="sr-only" id="hd-def456">v0.23.4</h2>
  <div class="d-flex flex-column flex-md-row">
    <div>
      <div class="mb-2 f4">
        <relative-time class="no-wrap" prefix="" datetime="2026-05-13T09:00:00Z">
          13 May 09:00
        </relative-time>
      </div>
    </div>
    <div>
      <div class="markdown-body tmp-my-3"><ul>
        <li><code>ollama launch opencode</code> now supports vision models with image inputs</li>
        <li>Bug fixes &amp; stability improvements</li>
      </ul></div>
    </div>
  </div>
</section>
"""

// Trimmed real markup from github.com/rustdesk/rustdesk/releases. Same GitHub
// release-section shape as Ollama, but the sr-only <h2> carries a bare version
// ("1.4.7", no leading "v"). Body opens with a screenshot link before the
// change bullets, and one item uses &amp; to prove entity decoding.
private let rustDeskFixture = """
<section aria-labelledby="hd-ff5db60a">
  <h2 class="sr-only" id="hd-ff5db60a">1.4.7</h2>
  <div class="d-flex flex-column flex-md-row">
    <div>
      <div class="mb-2 f4">
        <relative-time class="no-wrap" prefix="" datetime="2026-06-02T10:14:04Z">
          02 Jun 10:14
        </relative-time>
      </div>
    </div>
    <div>
      <div class="markdown-body tmp-my-3">
        <p><a href="https://example.com/shot.png"><img src="shot.png" alt="screenshot"></a></p>
        <ul>
          <li>Allow disabling the clipboard for security <a href="#1">#14440</a></li>
          <li>Better multi-monitor handling &amp; performance fixes</li>
        </ul>
      </div>
    </div>
  </div>
</section>
<section aria-labelledby="hd-aa11bb22">
  <h2 class="sr-only" id="hd-aa11bb22">1.4.5</h2>
  <div class="d-flex flex-column flex-md-row">
    <div>
      <div class="mb-2 f4">
        <relative-time class="no-wrap" prefix="" datetime="2026-01-09T08:00:00Z">
          09 Jan 08:00
        </relative-time>
      </div>
    </div>
    <div>
      <div class="markdown-body tmp-my-3"><ul>
        <li>Allow configuring remote control permissions for different users</li>
      </ul></div>
    </div>
  </div>
</section>
"""

@Test func extractsRustDeskEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.carriez.rustdesk"))
    let changelog = try #require(ChangelogExtractor.extract(from: rustDeskFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "1.4.7")
    #expect(changelog.entries[0].date == "2026-06-02")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[1] == "Better multi-monitor handling & performance fixes")
    #expect(changelog.entries[1].version == "1.4.5")
    #expect(changelog.entries[1].date == "2026-01-09")
    #expect(changelog.entries[1].items.count == 1)
}

// Trimmed real markup from docs.orbstack.dev/release-notes. Two VitePress
// h2 entries: v2.1.3 (3 items, May 10) and v2.1.2 (2 items, May 9, one with
// a <strong> tag to prove stripping). OrbStack does not print a year so date
// is kept verbatim as the "(Month Day)" text inside parentheses.
private let orbStackFixture = """
<h2 id="v2-1-3-may-10" tabindex="-1">v2.1.3 (May 10) \
<a class="header-anchor" href="#v2-1-3-may-10" aria-label="Permalink">\u{200B}</a></h2>
<ul>
<li>Fixed proxy support breaking cross-container connections</li>
<li>Fully fixed MongoDB 8 and rseq compatibility issues</li>
<li>Updates: Linux 7.0.5</li>
</ul>
<h2 id="v2-1-2-may-9" tabindex="-1">v2.1.2 (May 9) \
<a class="header-anchor" href="#v2-1-2-may-9" aria-label="Permalink">\u{200B}</a></h2>
<ul>
<li><strong>Activity Monitor TUI: <code>orb top</code></strong></li>
<li>Fixed Dirty Frag (CVE-2026-43284) privilege escalation</li>
</ul>
"""

@Test func extractsOllamaEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.electron.ollama"))
    let changelog = try #require(ChangelogExtractor.extract(from: ollamaFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "0.24.0")
    #expect(changelog.entries[0].date == "2026-05-14")
    #expect(changelog.entries[0].items.count == 6)
    #expect(changelog.entries[0].items[0] == "kimi-k2.6 (with vision support)")
    #expect(changelog.entries[1].version == "0.23.4")
    #expect(changelog.entries[1].date == "2026-05-13")
    #expect(changelog.entries[1].items.count == 2)
    #expect(changelog.entries[1].items[1] == "Bug fixes & stability improvements")
}

@Test func extractsOrbStackEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.kdrag0n.MacVirt"))
    let changelog = try #require(ChangelogExtractor.extract(from: orbStackFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "2.1.3")
    #expect(changelog.entries[0].date == "May 10")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[0].items[0] == "Fixed proxy support breaking cross-container connections")
    #expect(changelog.entries[1].version == "2.1.2")
    #expect(changelog.entries[1].date == "May 9")
    #expect(changelog.entries[1].items.count == 2)
    #expect(changelog.entries[1].items[0] == "Activity Monitor TUI: orb top")
}

// Minimal but structurally faithful slice: one patch release (2 items) and one
// feature release with section headers (2 items from nested <ul>).
// Three entries: one with only a <p> note (no <li>), one plain patch, one with
// section headers. Verifies both the <li> primary pattern and the <p> fallback.
let zedPreviewFixture = """
<div class="foo" id="zed-1.5.3" style="content-visibility:auto"><header class="p-3 font-zed-mono text-sm flex justify-between border-b default-border-color"><p class="high-contrast-text tabular-nums">1.5.3</p><p class="tabular-nums whitespace-nowrap">May 28, 2026</p></header><div class="content"><article class="p-3"><p>No public-facing changes in this release. <a href="https://github.com/zed-industries/zed/compare/v1.5.2-pre...v1.5.3-pre#commits_bucket">View the commits</a>.</p></article></div></div><div class="foo" id="zed-1.5.1" style="content-visibility:auto"><header class="p-3 font-zed-mono text-sm flex justify-between border-b default-border-color"><p class="high-contrast-text tabular-nums">1.5.1</p><p class="tabular-nums whitespace-nowrap">May 28, 2026</p></header><div class="content"><article class="p-3"><ul class="list-disc">\n<li class="mb-2">Fixed GitHub Copilot Chat showing an empty model dropdown for users on newer Copilot SDK builds (<a href="https://github.com/zed-industries/zed/pull/57964">#57964</a>)</li>\n<li class="mb-2">git: Fixed an issue where worktree creation would not be possible if resolving default branch fails (<a href="https://github.com/zed-industries/zed/pull/57960">#57960</a>)</li>\n</ul></article></div></div><div class="foo" id="zed-1.5.0" style="content-visibility:auto"><header class="p-3 font-zed-mono text-sm flex justify-between border-b default-border-color"><p class="high-contrast-text tabular-nums">1.5.0</p><p class="tabular-nums whitespace-nowrap">May 27, 2026</p></header><div class="content"><article class="p-3"><h2 class="h3" id="features">Features</h2>\n<ul class="list-disc">\n<li class="mb-2">Agent: Added support for importing skills from GitHub Markdown URLs in the Skill Creator. (<a href="https://github.com/zed-industries/zed/pull/57458">#57458</a>)</li>\n<li class="mb-2">Agent: Added commands for opening global and project-specific <code>AGENTS.md</code> rules. (<a href="https://github.com/zed-industries/zed/pull/57847">#57847</a>)</li>\n</ul></article></div></div>
"""

@Test func extractsZedPreviewEntriesInOrder() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.zed.Zed-Preview"))
    let changelog = try #require(ChangelogExtractor.extract(from: zedPreviewFixture, using: recipe))

    #expect(changelog.entries.count == 3)
    // 1.5.3: no <li> items — falls back to <p> text
    #expect(changelog.entries[0].version == "1.5.3")
    #expect(changelog.entries[0].date == "May 28, 2026")
    #expect(changelog.entries[0].items.count == 1)
    #expect(changelog.entries[0].items[0] == "No public-facing changes in this release. View the commits.")
    // 1.5.1: plain patch with <li> items
    #expect(changelog.entries[1].version == "1.5.1")
    #expect(changelog.entries[1].date == "May 28, 2026")
    #expect(changelog.entries[1].items.count == 2)
    #expect(changelog.entries[1].items[0] == "Fixed GitHub Copilot Chat showing an empty model dropdown for users on newer Copilot SDK builds (#57964)")
    #expect(changelog.entries[1].items[1] == "git: Fixed an issue where worktree creation would not be possible if resolving default branch fails (#57960)")
    // 1.5.0: feature release with section headers — <li> wins over <p>
    #expect(changelog.entries[2].version == "1.5.0")
    #expect(changelog.entries[2].date == "May 27, 2026")
    #expect(changelog.entries[2].items.count == 2)
    #expect(changelog.entries[2].items[0] == "Agent: Added support for importing skills from GitHub Markdown URLs in the Skill Creator. (#57458)")
    #expect(changelog.entries[2].items[1] == "Agent: Added commands for opening global and project-specific AGENTS.md rules. (#57847)")
}

@Test func recipeDecodesFromTerseJSON() throws {
    // A remotely-authored recipe needs only the four required fields; tuning
    // fields fall back to defaults (the forgiving decode path).
    let json = """
    {
      "bundleID": "com.foo.bar",
      "source": "https://foo.example/changelog",
      "entryPattern": "<h2>(?<version>[^<]+)</h2>(?<body>.*?)<hr>",
      "itemPatterns": ["<li>(?<item>.*?)</li>"]
    }
    """
    let recipe = try JSONDecoder().decode(ChangelogRecipe.self, from: Data(json.utf8))
    #expect(recipe.bundleID == "com.foo.bar")
    #expect(recipe.mode == .html)        // defaulted
    #expect(recipe.stripTags == true)    // defaulted
    #expect(recipe.maxEntries == 40)     // defaulted
    #expect(recipe.minItemLength == 1)   // defaulted
}

// Trimmed real markup from tailscale.com/changelog. Two `-client` articles plus
// one service-only article (Kubernetes Operator, no "Tailscale v" h3) that must
// be silently skipped, yielding exactly two entries.
private let tailscaleFixture = """
<article id="2026-06-01" class="flex w-full">\
<aside class="md:flex-[0_1_200px]">\
<h2 class="date-heading text-subheading-black"><a href="#2026-06-01">Jun 1, 2026</a></h2>\
</aside>\
<div class="md:flex-[1_1_843px]"><div class="changelog-date-group dark space-y-6">\
<div id="2026-06-01-client" class="changelog-entry scroll-mt-28">\
<header><h3 class="changelog-title t-20">Tailscale v1.98.5</h3></header>\
<div><div class="t-b18 changelog-entry"><h5>All Apple Platforms</h5>\n\
<ul>\n<li data-change="changed">macOS and iOS clients are now built using the xCode 26.5 toolchain.</li>\n</ul>\n\
</div></div></div></div></div></article>\
<article id="2026-05-28" class="flex w-full">\
<aside class="md:flex-[0_1_200px]">\
<h2 class="date-heading text-subheading-black"><a href="#2026-05-28">May 28, 2026</a></h2>\
</aside>\
<div class="md:flex-[1_1_843px]"><div class="changelog-date-group dark space-y-6">\
<div id="2026-05-28-client" class="changelog-entry scroll-mt-28">\
<header><h3 class="changelog-title t-20">Tailscale v1.98.4</h3></header>\
<div><div class="t-b18 changelog-entry"><h5>All Platforms</h5>\n\
<ul>\n<li data-change="fixed">An issue causing a deadlock when processing peer changes.</li>\n</ul>\n\
</div></div></div></div></div></article>\
<article id="2026-05-29" class="flex w-full">\
<aside class="md:flex-[0_1_200px]">\
<h2 class="date-heading text-subheading-black"><a href="#2026-05-29">May 29, 2026</a></h2>\
</aside>\
<div class="md:flex-[1_1_843px]"><div class="changelog-date-group dark space-y-6">\
<div id="2026-05-29-service" class="changelog-entry scroll-mt-28">\
<header><h3 class="changelog-title t-20">Tailscale Kubernetes Operator v1.98.2</h3></header>\
<div><ul><li data-change="changed">A new release of the Tailscale Kubernetes Operator is available.</li></ul></div>\
</div></div></div></article>
"""

@Test func extractsTailscaleClientEntriesAndSkipsServiceOnly() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "io.tailscale.ipn.macsys"))
    let changelog = try #require(ChangelogExtractor.extract(from: tailscaleFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "1.98.5")
    #expect(changelog.entries[0].date == "2026-06-01")
    #expect(changelog.entries[0].items.count == 1)
    #expect(changelog.entries[0].items[0] == "macOS and iOS clients are now built using the xCode 26.5 toolchain.")
    #expect(changelog.entries[1].version == "1.98.4")
    #expect(changelog.entries[1].date == "2026-05-28")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0] == "An issue causing a deadlock when processing peer changes.")
}

// Trimmed real markup from docs.warp.dev/changelog/2026/. Two versioned entries
// with `(v…)` qualifiers plus a date-only heading `2026.04.29` which the pattern
// must skip, yielding exactly two entries.
private let warpFixture = """
<div class="sl-heading-wrapper level-h3">\
<h3 id="20260527-v0202605271544">2026.05.27 (v0.2026.05.27.15.44)</h3>\
<a class="sl-anchor-link" href="#20260527-v0202605271544"><span class="sr-only">anchor</span></a></div>
<p><strong>New features</strong></p>
<ul>
<li>Added git operations to the code review pane. (<a href="https://github.com/warpdotdev/warp/pull/11716">#11716</a>)</li>
</ul>
<p><strong>Improvements</strong></p>
<ul>
<li>A new, faster implementation of find is now available as an opt-in setting.</li>
</ul>
<div class="sl-heading-wrapper level-h3">\
<h3 id="20260520-v0202605200921">2026.05.20 (v0.2026.05.20.09.21)</h3>\
<a class="sl-anchor-link" href="#20260520-v0202605200921"><span class="sr-only">anchor</span></a></div>
<p><strong>Improvements</strong></p>
<ul>
<li>Added support for double-clicking pane dividers to evenly redistribute panes.</li>
</ul>
<div class="sl-heading-wrapper level-h3">\
<h3 id="20260429">2026.04.29</h3>\
<a class="sl-anchor-link" href="#20260429"><span class="sr-only">anchor</span></a></div>
<p><strong>Improvements</strong></p>
<ul>
<li>New AI setting to control whether Oz adds an attribution co-author line.</li>
</ul>
"""

@Test func extractsWarpVersionedEntriesAndSkipsDateOnly() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.warp.Warp-Stable"))
    let changelog = try #require(ChangelogExtractor.extract(from: warpFixture, using: recipe))

    // Date-only heading "2026.04.29" (no `(v…)`) must be skipped.
    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "0.2026.05.27.15.44")
    #expect(changelog.entries[0].date == "2026.05.27")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "Added git operations to the code review pane. (#11716)")
    #expect(changelog.entries[0].items[1] == "A new, faster implementation of find is now available as an opt-in setting.")
    #expect(changelog.entries[1].version == "0.2026.05.20.09.21")
    #expect(changelog.entries[1].date == "2026.05.20")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0] == "Added support for double-clicking pane dividers to evenly redistribute panes.")
}

// Trimmed real markup from videolan.org/vlc/releases/3.0.23.html: the slash-form
// heading, two <ul> columns of fixes (one item carries an inline <a> link to be
// tag-stripped), then the "3.0 Highlights" marketing <h1> that the body lookahead
// must stop before — its feature bullets must NOT leak into the Fixes entry.
private let vlcFixture = """
<section class="features">
<div class="container">
<h1 style='margin-bottom: 12px;'>3.0.22/3.0.23 Fixes</h1>
<div class="row">
<div class="col-sm-6"><ul>
<li style="padding-bottom: 8px;">VLC 3.0.23 is the twenty-fourth update of "Vetinari":</li>
<li>Codec updates, notably dav1d, ffmpeg, libvpx</li>
</ul></div>
<div class="col-sm-6"><ul>
<li>Allow renaming/moving/deleting of playing file on Windows</li>
<li>Fixed multiple security issues, which are detailed <a href="/security/sb-vlc3022.html">here</a></li>
</ul></div>
</div>
</div>
<div class="container">
<h1 style='margin-bottom: 12px;'>3.0 Highlights</h1>
<ul><li>VLC 3.0 "Vetinari" is a new major update of VLC</li></ul>
</div>
</section>
"""

@Test func extractsVLCFixesAndSkipsMarketingHighlights() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.videolan.vlc"))
    let changelog = try #require(ChangelogExtractor.extract(from: vlcFixture, using: recipe))

    // One entry; version is the final (current) build, not the superseded 3.0.22.
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "3.0.23")
    // Four fixes across both columns; the "3.0 Highlights" bullet must be excluded.
    #expect(changelog.entries[0].items.count == 4)
    #expect(changelog.entries[0].items[1] == "Codec updates, notably dav1d, ffmpeg, libvpx")
    // Inline <a> link is tag-stripped to plain text.
    #expect(changelog.entries[0].items[3] == "Fixed multiple security issues, which are detailed here")
}

// MARK: - Index link-following (two-stage resolution)

// Trimmed real markup from www.videolan.org/vlc/releases/: the newest-first list
// of per-version links. Nav/footer links to other *.html pages must NOT be picked
// — only /vlc/releases/<digit>… qualifies — and the merged "3.0.19/3.0.20" entry
// points at a page named after neither-version-alone (3.0.20.html), which is
// exactly why we follow the real href instead of templating a version number.
private let vlcIndexFixture = """
<a href="/vlc/features.html">Features</a>
<h1>VLC Releases</h1>
<h2>VLC 3.0.x branch</h2>
<a href="/vlc/releases/3.0.23.html">VLC 3.0.23</a>
<a href="/vlc/releases/3.0.21.html">VLC 3.0.21</a>
<a href="/vlc/releases/3.0.20.html">VLC 3.0.19/3.0.20</a>
<a href="/vlc/releases/3.0.18.html">VLC 3.0.18</a>
"""

private let ghosttyIndexFixture = """
<nav><a href="/docs/install">Install</a></nav>
<a href="/docs/install/release-notes/1-3-1">1.3.1</a>
<a href="/docs/install/release-notes/1-3-0">1.3.0</a>
<a href="/docs/install/release-notes/1-2-3">1.2.3</a>
"""

@Test func followsFirstVLCReleaseLinkSkippingNavLinks() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.videolan.vlc"))
    let pattern = try #require(recipe.indexLinkPattern)
    let url = ChangelogService.firstLink(in: vlcIndexFixture, pattern: pattern, base: recipe.source)
    // The /vlc/features.html nav link is skipped; the first release link wins and
    // resolves to an absolute URL against the index page.
    #expect(url?.absoluteString == "https://www.videolan.org/vlc/releases/3.0.23.html")
}

@Test func followsFirstGhosttyReleaseLink() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.mitchellh.ghostty"))
    let pattern = try #require(recipe.indexLinkPattern)
    let url = ChangelogService.firstLink(in: ghosttyIndexFixture, pattern: pattern, base: recipe.source)
    #expect(url?.absoluteString == "https://ghostty.org/docs/install/release-notes/1-3-1")
}

@Test func firstLinkReturnsNilWhenNoMatch() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.videolan.vlc"))
    let pattern = try #require(recipe.indexLinkPattern)
    let url = ChangelogService.firstLink(
        in: "<a href=\"/about.html\">About</a>", pattern: pattern, base: recipe.source)
    #expect(url == nil)
}
