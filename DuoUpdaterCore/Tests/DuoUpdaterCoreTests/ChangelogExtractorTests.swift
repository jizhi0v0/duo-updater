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

// Trimmed real payloads from central.github.com/deployments/desktop/desktop/
// changelog.json — the stable feed (bare semver) and the `?env=beta` feed
// (`-betaN` versions). The beta note includes a JSON `\"` escape to prove the
// json-mode string unescaper turns it into a real quote.
private let ghDesktopStableFixture = """
[{"name":"","notes":["[Fixed] Items in lists such as branches and changed files are properly announced by screen readers on Windows - #22219"],"pub_date":"2026-06-01T17:43:05Z","version":"3.5.12"},{"name":"","notes":["[Fixed] Fix launching custom shells"],"pub_date":"2026-05-26T00:00:00Z","version":"3.5.11"}]
"""

private let ghDesktopBetaFixture = """
[{"name":"","notes":["[Improved] Show \\"No newline at end of file\\" as visible text in the diff view instead of requiring a tooltip hover - #22204","[Fixed] Screen reader now correctly announces added and removed line counts in the pull request preview dialog - #22202"],"pub_date":"2026-05-29T09:38:07Z","version":"3.5.12-beta2"}]
"""

// Trimmed real markup from the latest VS Code updates page (v1_123): one release
// header and its highlight bullets. Includes the trailing <blockquote> aside
// that 1.123 introduced between the highlights <ul> and "Happy Coding!" — the
// addition that regressed the old close anchor into a webview fallback.
private let vscodeFixture = """
<h1>Visual Studio Code 1.123</h1>
<p>Follow us on <a href="https://www.linkedin.com/showcase/vs-code">LinkedIn</a></p>
<hr>
<p><em>Release date: June 3, 2026</em></p>
<p>Downloads: Windows: <a href="https://update.code.visualstudio.com/1.123.0/win32-x64-user/stable">x64</a></p>
<hr>
<p>Welcome to the 1.123 release of Visual Studio Code.</p>
<ul>
<li><a href="#_session-sync-and-chronicle">Session sync</a>: Automatically sync your chat sessions across machines and search your coding history.</li>
<li><a href="#_agents-window-preview">Agents window</a>: Open multiple agent sessions side-by-side to compare or review work in parallel.</li>
<li><a href="#_research-agent-preview">Research agent</a>: Run deep research on a topic and get a thorough, well-cited Markdown report.</li>
</ul>
<blockquote><p>Make sure to join <a href="https://aka.ms/VSCode/Livestage" class="external-link" target="_blank">VS Code Live at Build 2026</a> on June 3!</p>
</blockquote><p>Happy Coding!</p>
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

@Test func extractsGitHubDesktopPerChannelFromJSON() throws {
    // Stable channel → bare semver versions, plain-text notes.
    let stable = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.github.GitHubClient", channel: .stable))
    let scl = try #require(ChangelogExtractor.extract(from: ghDesktopStableFixture, using: stable))
    #expect(scl.entries.count == 2)
    #expect(scl.entries[0].version == "3.5.12")
    #expect(scl.entries[0].date == "2026-06-01")
    #expect(scl.entries[0].items.count == 1)
    #expect(scl.entries[0].items[0] == "[Fixed] Items in lists such as branches and changed files are properly announced by screen readers on Windows - #22219")
    #expect(scl.entries[1].version == "3.5.11")

    // Beta channel — SAME bundle id, selected by `channel: .beta`: -betaN version,
    // and the JSON `\"` escape in the first note must decode to a real quote.
    let beta = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.github.GitHubClient", channel: .beta))
    let bcl = try #require(ChangelogExtractor.extract(from: ghDesktopBetaFixture, using: beta))
    #expect(bcl.entries[0].version == "3.5.12-beta2")
    #expect(bcl.entries[0].items.count == 2)
    #expect(bcl.entries[0].items[0] == "[Improved] Show \"No newline at end of file\" as visible text in the diff view instead of requiring a tooltip hover - #22204")
}

@Test func extractsLatestVSCodeReleaseHighlights() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.microsoft.VSCode"))
    let changelog = try #require(ChangelogExtractor.extract(from: vscodeFixture, using: recipe))

    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "1.123")
    #expect(changelog.entries[0].date == "June 3, 2026")
    #expect(changelog.entries[0].items.count == 3)
    #expect(changelog.entries[0].items[0] == "Session sync: Automatically sync your chat sessions across machines and search your coding history.")
    #expect(changelog.entries[0].items[2] == "Research agent: Run deep research on a topic and get a thorough, well-cited Markdown report.")
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

// Trimmed real markup from the HBuilderX *Alpha* changelog page (followed from
// alpha.json's `release` field). Same shape as the stable page, but every version
// <h2> carries an "-alpha" suffix — which the alpha recipe's version group requires.
private let hbuilderxAlphaFixture = """
<h1 id="hbuilder-x---release-notes">HBuilder X - Release Notes</h1>
<h2 id="5112026052520-alpha">5.11.2026052520-alpha</h2>
<h3 id="hbuilder">HBuilder</h3>
<ul>
<li>调整 内置node版本由v18.20.0升级到v22.22.2</li>
</ul>
<h3 id="uni-app-x">uni-app x</h3>
<ul>
<li>Android平台 修复 某些情况下编译报错的问题 <a href="https://issues.dcloud.net.cn/x">详情</a></li>
</ul>
<h2 id="5082026050815-alpha">5.08.2026050815-alpha</h2>
<h3 id="hbuilder-1">HBuilder</h3>
<ul>
<li>修复 alpha 渠道某个崩溃问题</li>
</ul>
"""

@Test func extractsHBuilderXAlphaEntriesWithSuffix() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "io.dcloud.HBuilderXAlpha"))
    let changelog = try #require(ChangelogExtractor.extract(from: hbuilderxAlphaFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "5.11.2026052520-alpha")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0].contains("内置node版本"))
    #expect(changelog.entries[1].version == "5.08.2026050815-alpha")
    #expect(changelog.entries[1].items.count == 1)
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

// Trimmed real shape of releases.warp.dev/channel_versions.json: a per-channel
// `changelogs` map whose entries are NOT in newest-first order (the June build is
// listed AFTER May), one entry with empty `markdown_sections` that must be skipped,
// markdown PR links to flatten, and a separate `preview` channel that must not leak
// into a `stable` decode. This is what the docs-site HTML scrape was replaced with.
private let warpFeedFixture = """
{
  "stable": { "version": "v0.2026.06.10.09.27.stable_01" },
  "changelogs": {
    "stable": {
      "v0.2026.05.20.09.21.stable_03": {
        "date": "2026-05-20T09:21:00+00:00",
        "markdown_sections": [
          { "title": "Improvements",
            "markdown": "* Added support for double-clicking pane dividers to evenly redistribute panes." }
        ]
      },
      "v0.2026.06.10.09.27.stable_01": {
        "date": "2026-06-10T09:27:00+0000",
        "markdown_sections": [
          { "title": "New features",
            "markdown": "* Git operations are now supported on remote sessions ([#12230](https://github.com/warpdotdev/warp/pull/12230))" },
          { "title": "Bug fixes",
            "markdown": "* Fixed a crash that could occur after clearing a terminal. ([#12085](https://github.com/warpdotdev/warp/pull/12085))\\n* Applied the latest security patches." }
        ]
      },
      "v0.2026.04.29.00.00.stable_00": {
        "date": "2026-04-29T00:00:00+0000",
        "markdown_sections": []
      }
    },
    "preview": {
      "v0.2026.06.11.10.00.preview_00": {
        "date": "2026-06-11T10:00:00+0000",
        "markdown_sections": [
          { "title": "New features", "markdown": "* A preview-only feature." }
        ]
      }
    }
  }
}
"""

@Test func warpRecipeIsStructuredJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.warp.Warp-Stable"))
    #expect(recipe.structuredFormat == .warpChannelVersions)
    #expect(recipe.channel == .stable)
    #expect(recipe.source.absoluteString == "https://releases.warp.dev/channel_versions.json")
}

@Test func decodesWarpStableSortedNewestFirstSkippingEmpty() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        warpFeedFixture, format: .warpChannelVersions, channel: .stable, maxEntries: 20))

    // The empty-`markdown_sections` April entry is dropped; the remaining two are
    // ordered newest-first despite the June build being listed second in the JSON.
    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "0.2026.06.10.09.27")
    #expect(changelog.entries[0].date == "2026-06-10")
    // Sections flatten into one ordered list: 1 (New features) + 2 (Bug fixes).
    #expect(changelog.entries[0].items.count == 3)
    // Markdown PR link `([#12230](url))` flattens to `(#12230)`.
    #expect(changelog.entries[0].items[0] == "Git operations are now supported on remote sessions (#12230)")
    #expect(changelog.entries[0].items[1] == "Fixed a crash that could occur after clearing a terminal. (#12085)")
    #expect(changelog.entries[0].items[2] == "Applied the latest security patches.")
    #expect(changelog.entries[1].version == "0.2026.05.20.09.21")
    #expect(changelog.entries[1].date == "2026-05-20")
    #expect(changelog.entries[1].items == ["Added support for double-clicking pane dividers to evenly redistribute panes."])
}

@Test func warpChannelsDoNotLeak() throws {
    // A `stable` decode must not surface the `preview`-only build, and vice versa.
    let stable = try #require(StructuredChangelogDecoder.decode(
        warpFeedFixture, format: .warpChannelVersions, channel: .stable, maxEntries: 20))
    #expect(!stable.entries.contains { $0.version.contains("06.11") })

    let preview = try #require(StructuredChangelogDecoder.decode(
        warpFeedFixture, format: .warpChannelVersions, channel: .preview, maxEntries: 20))
    #expect(preview.entries.count == 1)
    #expect(preview.entries[0].version == "0.2026.06.11.10.00")
}

@Test func warpDecodeRespectsMaxEntries() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        warpFeedFixture, format: .warpChannelVersions, channel: .stable, maxEntries: 1))
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "0.2026.06.10.09.27")
}

// Two builds in the SAME minute-timestamp whose `_NN` counter has crossed into two
// digits: `_10` is newer than `_9`, but a plain descending lexical sort ranks `_9`
// first (because '9' > '1'). The decoder must compare the counter numerically.
@Test func warpSortHandlesWideBuildCounterNumerically() throws {
    let feed = """
    {
      "changelogs": {
        "stable": {
          "v0.2026.06.10.09.27.stable_9": {
            "date": "2026-06-10T09:27:00+0000",
            "markdown_sections": [ { "title": "x", "markdown": "* build nine" } ]
          },
          "v0.2026.06.10.09.27.stable_10": {
            "date": "2026-06-10T09:27:00+0000",
            "markdown_sections": [ { "title": "x", "markdown": "* build ten" } ]
          }
        }
      }
    }
    """
    let changelog = try #require(StructuredChangelogDecoder.decode(
        feed, format: .warpChannelVersions, channel: .stable, maxEntries: 20))
    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].items == ["build ten"])
    #expect(changelog.entries[1].items == ["build nine"])
}

// A change line that links to a URL containing parentheses must flatten to the link
// text with no dangling `)`, and an inline image must be stripped (not decay to a
// stray `!alt`).
@Test func warpBulletFlattensParenURLsAndStripsImages() throws {
    let feed = """
    {
      "changelogs": {
        "stable": {
          "v0.2026.06.10.09.27.stable_01": {
            "date": "2026-06-10T09:27:00+0000",
            "markdown_sections": [
              { "title": "Notes",
                "markdown": "* See [docs](https://en.wikipedia.org/wiki/Foo_(bar)) for details\\n* ![shot](https://x/y.png) Added a thing" }
            ]
          }
        }
      }
    }
    """
    let changelog = try #require(StructuredChangelogDecoder.decode(
        feed, format: .warpChannelVersions, channel: .stable, maxEntries: 20))
    #expect(changelog.entries[0].items[0] == "See docs for details")
    #expect(changelog.entries[0].items[1] == "Added a thing")
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

// Trimmed slice of air.dev's real Vite/React JS bundle (the data array `h9=[…]`).
// Four entries cover all three content shapes plus the description fallback:
//   - 261.681.18: feature release, each feature an <h4> heading (h4 pattern)
//   - 261.311.41: small fix, plain <p> prose + the "Share your feedback" footer
//     that must be skipped (prose pattern, footer filtered)
//   - 261.232.26: <p> whose children open with an AIR issue link, real note in
//     the text after it (after-link pattern)
//   - 261.232.22: content is only the footer; the note lives in `description`
// The array closes with `}],m9=` to exercise the entry terminator's array-end arm.
private let airFixture = """
;h9=[{version:"261.681.18",date:"June 2, 2026",title:"Air on Linux, Claude subagents via /, and per-agent permission modes",description:"",content:i.jsxs(i.Fragment,{children:[i.jsx("h4",{className:"mb-[10px] uppercase",style:{color:"var(--header-white, #FFF)"},children:"Air on Linux in Toolbox App"}),i.jsxs("p",{className:"text-foreground/80 text-[15px]",children:["Air now runs on Linux."]}),i.jsx("h4",{className:"mb-[10px] mt-[24px] uppercase",style:{color:"#FFF"},children:"Built-in and custom Claude subagents"})]})},{version:"261.311.41",date:"March 14, 2026",title:"Fixes for Junie and Terminal",description:"",content:i.jsxs(i.Fragment,{children:[i.jsxs("p",{className:"text-foreground/80 text-[15px]",children:["This update fixes the 403 error when working with Junie (",i.jsx("a",{href:"https://youtrack.jetbrains.com/issue/AIR-4175",children:"AIR-4175"}),")."]}),i.jsxs("p",{className:"text-foreground/80 text-[15px]",children:["Share your feedback with us via the"," ",i.jsx("a",{href:"x",children:"issue tracker"}),"."]})]})},{version:"261.232.26",date:"February 13, 2026",title:"Fix for Claude Agent",description:"",content:i.jsx(i.Fragment,{children:i.jsxs("p",{className:"text-foreground/80 text-[15px]",children:[i.jsx("a",{href:"https://youtrack.jetbrains.com/issue/AIR-3781",children:"AIR-3781"})," ","Fixed an issue with handling events from the Claude Agent"]})})},{version:"261.232.22",date:"February 12, 2026",title:"Claude Agent with Opus 4.6",description:"This update of the Claude Agent to version 2.1.38 and adds support for Opus 4.6.",content:i.jsx(i.Fragment,{children:i.jsxs("p",{className:"text-foreground/80 text-[15px]",children:["Share your feedback with us via the"," ",i.jsx("a",{href:"x",children:"issue tracker"}),"."]})})}],m9=()=>i.jsx
"""

@Test func extractsAirEntriesAcrossContentShapes() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.jetbrains.air"))
    let changelog = try #require(ChangelogExtractor.extract(from: airFixture, using: recipe))

    #expect(changelog.entries.count == 4)

    // Feature release → <h4> headings.
    #expect(changelog.entries[0].version == "261.681.18")
    #expect(changelog.entries[0].date == "June 2, 2026")
    #expect(changelog.entries[0].title == "Air on Linux, Claude subagents via /, and per-agent permission modes")
    #expect(changelog.entries[0].items == [
        "Air on Linux in Toolbox App",
        "Built-in and custom Claude subagents",
    ])

    // Small fix → lead <p> prose, "Share your feedback" footer skipped.
    #expect(changelog.entries[1].version == "261.311.41")
    #expect(changelog.entries[1].items.count == 1)
    #expect(changelog.entries[1].items[0] == "This update fixes the 403 error when working with Junie (")

    // <p> opening with an issue link → the note text after the link.
    #expect(changelog.entries[2].version == "261.232.26")
    #expect(changelog.entries[2].items == ["Fixed an issue with handling events from the Claude Agent"])

    // Footer-only content → the note from the `description` field.
    #expect(changelog.entries[3].version == "261.232.22")
    #expect(changelog.entries[3].items == [
        "This update of the Claude Agent to version 2.1.38 and adds support for Opus 4.6.",
    ])
}

@Test func followsAirHashedBundleLink() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.jetbrains.air"))
    let pattern = try #require(recipe.indexLinkPattern)
    let shell = """
    <link rel="stylesheet" crossorigin href="/assets/index-ChMVGmWt.css">
    <script type="module" crossorigin src="/assets/index-CtPepV0y.js"></script>
    """
    let url = ChangelogService.firstLink(in: shell, pattern: pattern, base: recipe.source)
    #expect(url?.absoluteString == "https://air.dev/assets/index-CtPepV0y.js")
}

// Slack — two trimmed release <article>s from slack.com/release-notes/mac; the
// second carries `&lt;`/`&gt;` and `&#8217;` to prove entity decoding.
private let slackFixture = """
<article><a name="11727"></a><h2 class="u-flex u-align--center">Slack 4.50.128</h2>\
<p>May 26, 2026</p><h3>Bug Fixes</h3><ul><li>Thanks for updating the app! Here&#8217;s to incremental gains!</li></ul></article>\
<article><a name="1959"></a><h2 class="u-flex u-align--center">Slack 4.27.154</h2><p>June 14, 2022</p>\
<h3>What&#8217;s New</h3><ul><li>Going forward, you&#8217;ll see numbers in a &lt;MAJOR.MINOR.BUILD&gt; sequence.</li></ul></article>
"""

@Test func extractsSlackEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.tinyspeck.slackmacgap"))
    let cl = try #require(ChangelogExtractor.extract(from: slackFixture, using: recipe))
    #expect(cl.entries.count == 2)
    #expect(cl.entries.first?.version == "4.50.128")
    #expect(cl.entries.first?.date == "May 26, 2026")
    #expect(cl.entries.first?.items.count == 1)
    #expect(cl.entries.first?.items.first == "Thanks for updating the app! Here\u{2019}s to incremental gains!")
    #expect(cl.entries.last?.items.first == "Going forward, you\u{2019}ll see numbers in a <MAJOR.MINOR.BUILD> sequence.")
}

// Notion — two product-changelog posts from notion.com/releases. The first has a
// `videoPlayer_errorLine` decoy <p> (must be excluded), a `&amp;` entity, and an
// inner <code> tag to prove stripping; the title stands in for the version.
private let notionFixture = #"""
<article class="release_release__p2Jug"><div class="release_releaseMeta__bvuES"><div class="release_dateRow__ew79j"><time class="release_date__P0TR_">May 26, 2026</time></div></div><div class="release_content__gxmgt"><a class="release_titleLink__zEwHf" href="/releases/2026-05-26"><h2 class="semanticTypography_semanticTypography__mWJkv release_title__o1nuh">Merge cells in simple tables</h2></a><article class="contentfulRichText_richText__rW7Oq"><p class="videoPlayer_errorLine__pR8bX">Uh-oh! Your ad blocker is preventing the video from playing.</p><p class="contentfulRichText_paragraph___hjRE">Finally! Merge cells in simple tables &amp; databases.</p><p class="contentfulRichText_paragraph___hjRE">Select multiple cells → open the cell menu → select <code class="contentfulRichText_code__RWBxk">Merge</code>.</p></article></div></article><article class="release_release__p2Jug"><div class="release_releaseMeta__bvuES"><div class="release_dateRow__ew79j"><time class="release_date__P0TR_">May 7, 2026</time></div></div><div class="release_content__gxmgt"><a class="release_titleLink__zEwHf" href="/releases/2026-05-07"><h2 class="semanticTypography_semanticTypography__mWJkv release_title__o1nuh">Plan Mode</h2></a><article class="contentfulRichText_richText__rW7Oq"><p class="contentfulRichText_paragraph___hjRE">Your agent now drafts a plan before making significant changes.</p></article></div></article></main>
"""#

@Test func extractsNotionEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "notion.id"))
    let cl = try #require(ChangelogExtractor.extract(from: notionFixture, using: recipe))
    #expect(cl.entries.count == 2)
    #expect(cl.entries.first?.version == "Merge cells in simple tables")
    #expect(cl.entries.first?.date == "May 26, 2026")
    #expect(cl.entries.first?.items.count == 2)   // videoPlayer decoy <p> excluded
    #expect(cl.entries.first?.items.first == "Finally! Merge cells in simple tables & databases.")
    #expect(cl.entries.last?.version == "Plan Mode")
    #expect(cl.entries.last?.items.count == 1)
}

// Obsidian — a trimmed desktop block (1.12.3) from obsidian.md/changelog with a
// `&quot;` entity and an inline <code> tag.
private let obsidianFixture = #"""
<div class="flex py-16 flex-col md:flex-row">
	<div class="grow">
		<div class="md:sticky md:top-[var(--header-height)]">
			<a href="/changelog/2026-02-23-desktop-v1.12.3/" class="font-semibold text-3xl sm:text-xl">
				February 23, 2026
			</a>
			<div class="font-mono mt-2 text-muted">
				<a href="/changelog/2026-02-23-desktop-v1.12.3/" class="flex items-center gap-4">
					<span class="text-sm">1.12.3
						<span span class=""> Desktop</span>
					</span>
				</a>
			</div>
		</div>
	</div>
	<div class="md:basis-3/4">
		<div class="typeset break-words" dir="ltr">
			<h2>No longer broken</h2>
<ul>
<li>Fixed copy-paste converting links and callouts into standard Markdown.</li>
<li>File explorer: Fixed &quot;Duplicate&quot; menu item generating an incomplete folder name.</li>
</ul>
<h2>Developers</h2>
<ul>
<li>Added <code>appendBinary</code> method to the vault and adapter API.</li>
</ul>
		</div>
	</div>
</div>
"""#

@Test func extractsObsidianEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "md.obsidian"))
    let cl = try #require(ChangelogExtractor.extract(from: obsidianFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries.first?.version == "1.12.3")
    #expect(cl.entries.first?.date == "February 23, 2026")
    #expect(cl.entries.first?.items.count == 3)
    #expect(cl.entries.first?.items[1] == "File explorer: Fixed \"Duplicate\" menu item generating an incomplete folder name.")
    #expect(cl.entries.first?.items[2] == "Added appendBinary method to the vault and adapter API.")
}

// Figma — two product release-notes <article>s from figma.com/release-notes; the
// first has a <strong> to strip and a `&#x27;` entity to decode. Title = version.
private let figmaFixture = """
<article aria-label="Plan smarter" class="fig-1ud82tx">\
<div class="fig-1u7wo0i">\
<time dateTime="Jun 3, 2026" class="fig-4tc1ef">Jun 3, 2026</time>\
<h2 class="fig-1u8vp4l">Plan smarter with more context in Make</h2>\
</div>\
<div class="fig-k1i24q">\
<p class="fig-jco665"><strong>Plan mode</strong></p>\
<p class="fig-jco665">It&#x27;s most useful for complex work.</p>\
</div></article>\
<article aria-label="Sharper controls" class="fig-1ud82tx">\
<div class="fig-1u7wo0i">\
<time dateTime="Jun 1, 2026" class="fig-4tc1ef">Jun 1, 2026</time>\
<h2 class="fig-1u8vp4l">Sharper controls for every slot</h2>\
</div>\
<div class="fig-k1i24q">\
<p class="fig-jco665">New slot settings let you set guardrails.</p>\
</div></article>
"""

@Test func extractsFigmaEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.figma.Desktop"))
    let cl = try #require(ChangelogExtractor.extract(from: figmaFixture, using: recipe))
    #expect(cl.entries.count == 2)
    #expect(cl.entries.first?.version == "Plan smarter with more context in Make")
    #expect(cl.entries.first?.date == "Jun 3, 2026")
    #expect(cl.entries.first?.items.count == 2)
    #expect(cl.entries.first?.items.first == "Plan mode")              // <strong> stripped
    #expect(cl.entries.first?.items.last == "It's most useful for complex work.")  // &#x27; decoded
    #expect(cl.entries.last?.version == "Sharper controls for every slot")
    #expect(cl.entries.last?.items.count == 1)
}

// 1Password — two stable release <article>s from releases.1password.com/mac/stable/;
// items keep their GitLab issue refs inline, and the first carries `&rsquo;`.
private let onePasswordFixture = """
<article class="c-updates__release u-mb-6"><header class="c-updates__header">\
<a href=#1password-for-mac-8.12.22 class="c-updates__anchor">\
<time datetime="2026-06-02 00:00:00 +0000 UTC" class="c-heading c-updates__date u-mb-2 u-is-displayblock">June 2 2026</time>\
<h6 class="c-heading c-updates__title">1Password for Mac 8.12.22</h6></a></header>\
<div class="c-updates__content u-py-8"><ul>\
<li>We&rsquo;ve improved the scrolling experience. <span class='c-icon c-icon--gitlab'>!37801</span></li></ul></div></article>\
<article class="c-updates__release u-mb-6"><header class="c-updates__header">\
<a href=#1password-for-mac-8.12.21 class="c-updates__anchor">\
<time datetime="2026-05-20 00:00:00 +0000 UTC" class="c-heading c-updates__date u-mb-2 u-is-displayblock">May 20 2026</time>\
<h6 class="c-heading c-updates__title">1Password for Mac 8.12.21</h6></a></header>\
<div class="c-updates__content u-py-8"><ul>\
<li>You can now use Codex to interact directly with 1Password Environments. <span class='c-icon c-icon--gitlab'>!37261</span></li>\
<li>Fixed an issue with autofill. <span class='c-icon c-icon--gitlab'>#DESK-541</span></li></ul></div></article>
"""

@Test func extractsOnePasswordEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.1password.1password"))
    let cl = try #require(ChangelogExtractor.extract(from: onePasswordFixture, using: recipe))
    #expect(cl.entries.count == 2)
    #expect(cl.entries.first?.version == "8.12.22")
    #expect(cl.entries.first?.date == "June 2 2026")
    #expect(cl.entries.first?.items.count == 1)
    #expect(cl.entries.first?.items.first == "We\u{2019}ve improved the scrolling experience. !37801")
    #expect(cl.entries.last?.version == "8.12.21")
    #expect(cl.entries.last?.items.count == 2)
}

// Sublime Text — two /download build blocks; the 4200 block keeps an `&amp;`
// entity and an inline <tt> tag. Versions are 4-digit build numbers.
private let sublimeFixture = """
<h2>Changelog</h2>
<article class="current">
<h3>Build 4200</h3>
<div class="release-date">21 May 2025</div>
<p>We're planning on making some changes to the supported plugin Python versions.</p>
<h3>New Features and Improvements</h3>
<ul class="topic">
    <li>Sidebar can now be moved to the right side using the <tt>"sidebar_on_right"</tt> setting</li>
    <li>Mac: Added security entitlements allowing plugins &amp; build systems to request the camera and microphone</li>
</ul>
</article>

<article>
<h3>Build 4192</h3>
<div class="release-date">20 Jan 2025</div>
<ul class="topic">
    <li>Fixed tab not working when tab completion is disabled</li>
</ul>
</article>
"""

@Test func extractsSublimeTextEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.sublimetext.4"))
    let cl = try #require(ChangelogExtractor.extract(from: sublimeFixture, using: recipe))
    #expect(cl.entries.count == 2)
    #expect(cl.entries.first?.version == "4200")
    #expect(cl.entries.first?.date == "21 May 2025")
    #expect(cl.entries.first?.items.count == 2)
    #expect(cl.entries.first?.items[1] == "Mac: Added security entitlements allowing plugins & build systems to request the camera and microphone")
    #expect(cl.entries.last?.version == "4192")
}

// Calibre — calibre-ebook.com/whats-new: version+date in the <h2> title; items
// are <span class="title"> only (bare news-source <li> dropped); &gt; entity.
private let calibreFixture = """
<div class="panes">
<div class="pane" id="release-pane">
<div class="release">
    <h2 class="release-title">Release: 9.9 [28 May, 2026]</h2>
<h3 class="category">New features</h3><ul class="entries">
<li class="minor"><span class="title">A new option to keep the current search when switching Virtual libraries under Preferences-&gt;Searching</span>
<p class="tickets">Closes tickets: <a href="https://bugs.launchpad.net/calibre/+bug/2151262">2151262</a></p>
</li>
</ul>
<h3 class="category">Bug fixes</h3><ul class="entries">
<li class="minor"><span class="title">Linux: Fix SSL certificate loading not working on Fedora 44</span>
</li>
</ul>
<h3 class="category">New news sources</h3>
<ul class="entries">
<li>SuperInteressante by Pedro Henrique Souza</li>
</ul>
    </div>
    </div>
    </div>
"""

@Test func extractsCalibreEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.kovidgoyal.calibre"))
    let cl = try #require(ChangelogExtractor.extract(from: calibreFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries.first?.version == "9.9")
    #expect(cl.entries.first?.date == "28 May, 2026")
    #expect(cl.entries.first?.items.count == 2)   // news-source <li> excluded
    #expect(cl.entries.first?.items.first == "A new option to keep the current search when switching Virtual libraries under Preferences->Searching")
}

// Audacity — GitHub releases page; the "Audacity " + x.y.z anchor skips the
// "Audacity-4.0.0.alpha-2" prerelease (hyphen, not space). &amp; + nested <a>.
private let audacityFixture = """
<section aria-labelledby="hd-3-7-7" data-hpc>
  <h2 class="sr-only" id="hd-3-7-7">Audacity 3.7.7</h2>
  <relative-time datetime="2025-12-11T19:48:17Z" class="no-wrap">Dec 11, 2025</relative-time>
  <div data-test-selector="body-content" class="markdown-body tmp-my-3">
    <p>This is a hotfix release.</p>
    <ul>
      <li><a class="issue-link" href="#9940">#9940</a> Added checksum to WavPack export &amp; metadata (thanks @ajsand)</li>
      <li>Fixed Export &amp; Import crash on macOS</li>
    </ul>
  </div>
</div>
<section aria-labelledby="hd-4-0-0-alpha" data-hpc>
  <h2 class="sr-only" id="hd-4-0-0-alpha">Audacity-4.0.0.alpha-2</h2>
  <relative-time datetime="2025-11-03T10:00:00Z" class="no-wrap">Nov 3, 2025</relative-time>
  <div data-test-selector="body-content" class="markdown-body tmp-my-3"><ul><li>Alpha preview</li></ul></div>
</div>
<section aria-labelledby="hd-3-7-6" data-hpc>
  <h2 class="sr-only" id="hd-3-7-6">Audacity 3.7.6</h2>
  <relative-time datetime="2025-12-04T12:00:00Z" class="no-wrap">Dec 4, 2025</relative-time>
  <div data-test-selector="body-content" class="markdown-body tmp-my-3"><ul><li>#9742 Added FFmpeg 8 support</li></ul></div>
</div>
"""

@Test func extractsAudacityEntriesSkippingAlpha() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.audacityteam.audacity"))
    let cl = try #require(ChangelogExtractor.extract(from: audacityFixture, using: recipe))
    #expect(cl.entries.count == 2)   // alpha-2 block skipped
    #expect(cl.entries.first?.version == "3.7.7")
    #expect(cl.entries.first?.date == "2025-12-11")
    #expect(cl.entries.first?.items.count == 2)
    #expect(cl.entries.first?.items.first == "#9940 Added checksum to WavPack export & metadata (thanks @ajsand)")
    #expect(cl.entries[1].version == "3.7.6")
}

// Blender — dev-docs per-version page; "was released on" guard. &amp; entity.
private let blenderFixture = """
<h1 id="blender-51-release-notes">Blender 5.1 Release Notes<a class="headerlink" href="#blender-51-release-notes">&para;</a></h1>
<p>Blender 5.1 was released on March 17, 2026.</p>
<p>Check out the final <a href="https://www.blender.org/download/releases/5-1/">release notes on blender.org</a>.</p>
<ul>
<li><a href="animation_rigging/">Animation &amp; Rigging</a></li>
<li><a href="eevee/">EEVEE &amp; Viewport</a></li>
<li><a href="geometry_nodes/">Geometry Nodes</a></li>
</ul>
<h2 id="compatibility">Compatibility<a class="headerlink" href="#compatibility">&para;</a></h2>
<ul>
<li>Node Tools now have a global unique idname requirement.</li>
</ul>
<h2 id="bugfixes">Bugfixes<a class="headerlink" href="#bugfixes">&para;</a></h2>
<ul>
<li><a href="bugfixes/">Fixes for issues present in previous versions</a></li>
</ul>
<h2 id="corrective-releases"><a href="corrective_releases/">Corrective Releases</a></h2>
"""

@Test func extractsBlenderEntryWithReleasedGuard() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.blenderfoundation.blender"))
    let cl = try #require(ChangelogExtractor.extract(from: blenderFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries.first?.version == "5.1")
    #expect(cl.entries.first?.date == "March 17, 2026")
    #expect(cl.entries.first?.items.first == "Animation & Rigging")   // &amp; decoded
    // An in-development page ("is currently in Beta") must NOT match → no entries.
    let beta = "<h1 id=\"x\">Blender 5.2 Release Notes</h1>\n<p>Blender 5.2 is currently in Beta until June 2026.</p>\n<h2 id=\"corrective-releases\">x</h2>"
    #expect(ChangelogExtractor.extract(from: beta, using: recipe) == nil)
}

// Trimmed real markup from chromereleases.googleblog.com/search/label/Stable%20updates.
// The label page mixes platforms/channels, so the recipe selects desktop *stable*
// posts via the exact title literal. Three posts here: a promotion post (no CVEs →
// lead-sentence fallback), a non-stable decoy (Android — must be skipped by the
// title filter even though it carries a 4-part version), and a security post whose
// fixes are inline spans (not <li>). One CVE description carries `&amp;` to prove
// entity decoding; each post body wraps its content in a `<script type='text/template'>`.
private let chromeFixture = """
<div class='post' itemscope='' itemtype='http://schema.org/BlogPosting'>
<h2 class='title' itemprop='name'>
<a href='https://chromereleases.googleblog.com/2026/06/stable-channel-update-for-desktop.html' itemprop='url' title='Stable Channel Update for Desktop'>
Stable Channel Update for Desktop
</a>
</h2>
<div class='post-header'><div class='published'>
<span class='publishdate' itemprop='datePublished'>
Tuesday, June 2, 2026
</span>
</div></div>
<div class='post-body'><div class='post-content' itemprop='articleBody'>
<script type='text/template'>
<p><span style="color: #666666;">The Chrome team is delighted to announce the promotion of Chrome 149 to the stable channel for Windows, Mac and Linux. This will roll out over the coming days/weeks.</span></p><div style="color: #666666;"><span>Chrome 149.0.7827.53 (Linux)&nbsp;149.0.7827.53/.54&nbsp;Windows/Mac</span></div><p><span>Interested in switching release channels? Find out how here. If you find a new issue, please let us know by filing a bug.</span></p><p>Srinivas Sista</p><p>Google Chrome</p>
</script>
</div></div>
</div>
<div class='post' itemscope='' itemtype='http://schema.org/BlogPosting'>
<h2 class='title' itemprop='name'>
<a href='https://chromereleases.googleblog.com/2026/06/chrome-for-android-update.html' itemprop='url' title='Chrome for Android Update'>
Chrome for Android Update
</a>
</h2>
<div class='post-header'><div class='published'>
<span class='publishdate' itemprop='datePublished'>
Monday, June 1, 2026
</span>
</div></div>
<div class='post-body'><div class='post-content' itemprop='articleBody'>
<script type='text/template'>
<p>Hi everyone! We've just released Chrome 149 (149.0.7827.46) for Android.</p>
</script>
</div></div>
</div>
<div class='post' itemscope='' itemtype='http://schema.org/BlogPosting'>
<h2 class='title' itemprop='name'>
<a href='https://chromereleases.googleblog.com/2026/05/stable-channel-update-for-desktop_27.html' itemprop='url' title='Stable Channel Update for Desktop'>
Stable Channel Update for Desktop
</a>
</h2>
<div class='post-header'><div class='published'>
<span class='publishdate' itemprop='datePublished'>
Wednesday, May 27, 2026
</span>
</div></div>
<div class='post-body'><div class='post-content' itemprop='articleBody'>
<script type='text/template'>
<p><span>The Stable channel has been updated to 148.0.7778.216/217 for Windows and 148.0.7778.215/216 Mac and 148.0.7778.215 for Linux.</span></p><p>This update includes 2 security fixes.</p><span style="font-weight: 700;"> Critical </span><span> CVE-2026-9872: Out of bounds write in GPU. </span><span style="font-weight: 700;"> High </span><span> CVE-2026-9873: Heap buffer overflow in Media &amp; Audio. </span>
</script>
</div></div>
</div>
"""

@Test func extractsChromeStableDesktopPostsAndSkipsOtherChannels() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.google.Chrome"))
    let cl = try #require(ChangelogExtractor.extract(from: chromeFixture, using: recipe))

    // The Android decoy is dropped by the title filter → only the two desktop posts.
    #expect(cl.entries.count == 2)

    // Promotion post: no CVEs, so the lead-sentence fallback yields exactly one
    // item — the announcement, never the boilerplate or signature paragraphs.
    #expect(cl.entries[0].version == "149.0.7827.53")
    #expect(cl.entries[0].date == "Tuesday, June 2, 2026")
    #expect(cl.entries[0].items.count == 1)
    #expect(cl.entries[0].items[0].contains("promotion of Chrome 149 to the stable channel"))

    // Security post: version is the first listed build; fixes come from the inline
    // CVE spans, and `&amp;` decodes to `&`.
    #expect(cl.entries[1].version == "148.0.7778.216")
    #expect(cl.entries[1].date == "Wednesday, May 27, 2026")
    #expect(cl.entries[1].items.count == 2)
    #expect(cl.entries[1].items[0] == "CVE-2026-9872: Out of bounds write in GPU.")
    #expect(cl.entries[1].items[1] == "CVE-2026-9873: Heap buffer overflow in Media & Audio.")
}

// Trimmed real markup from docs.tablepro.app/changelog (Mintlify): two labeled
// release blocks with the date/version/content parts the recipe anchors on.
private let tableproFixture = """
<div data-component-part="update-label">June 2, 2026</div>
<div data-component-part="update-description">v0.48.0</div>
<div data-component-part="update-content"><h3 id="new-features"><span>New Features</span></h3>
<ul>
<li><strong>JSON Import</strong>: Import a JSON file into a table.</li>
<li><strong>Export Query Results</strong>: Export any SQL query result to CSV, JSON, SQL, XLSX, or MQL.</li>
</ul></div>
<div data-component-part="update-label">June 1, 2026</div>
<div data-component-part="update-description">v0.47.0</div>
<div data-component-part="update-content"><h3 id="new-features"><span>New Features</span></h3>
<ul>
<li><strong>Favorite Tables</strong>: Star a table in the sidebar to pin it to the top.</li>
</ul></div>
"""

@Test func extractsTableProMintlifyReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.TablePro"))
    let cl = try #require(ChangelogExtractor.extract(from: tableproFixture, using: recipe))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "0.48.0")
    #expect(cl.entries[0].date == "June 2, 2026")
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0] == "JSON Import: Import a JSON file into a table.")
    #expect(cl.entries[1].version == "0.47.0")
    #expect(cl.entries[1].items[0] == "Favorite Tables: Star a table in the sidebar to pin it to the top.")
}

// Trimmed real markup from corecode.io/macupdater/history3.html: two version
// blocks, each a <p><b>ver</b> (date):</p> header followed by bullet paragraphs.
private let macupdaterFixture = """
<p class="header"><a href="/macupdater/"><b>MacUpdater</b></a><b> History:</b></p>
<p><b>3.5.0</b> (Jan 2026):</p>
<p>• This is the last and final update to MacUpdater 3</p>
<p>• This version is free-to-use for everyone including "Pro" features</p>
<p><b>3.4.7</b> (Dec 2025):</p>
<p>• For its last 3 weeks in operation, MacUpdater is now free-to-use!</p>
"""

@Test func extractsMacUpdaterHistoryBullets() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.corecode.MacUpdater"))
    let cl = try #require(ChangelogExtractor.extract(from: macupdaterFixture, using: recipe))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "3.5.0")
    #expect(cl.entries[0].date == "Jan 2026")
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0] == "This is the last and final update to MacUpdater 3")
    #expect(cl.entries[1].version == "3.4.7")
    #expect(cl.entries[1].items.count == 1)
}

// Trimmed real bytes from the JetBrains TBA releases JSON. Raw string so the
// JSON escapes (\\n between tags, \\" in attrs) stay literal as on the wire. The
// whatsnew mixes a feature <p>, a <ul><li> bullet list, and the "See the full
// list…" footer the item pattern must skip.
private let jbToolboxFixture = #"""
{"TBA":[{"date":"2026-06-02","type":"release","downloads":{"mac":{"link":"https://x"}},"notesLink":"https://y","version":"3.5","majorVersion":"3.5","build":"3.5.0.84344","whatsnew":"<h3>What's New in Toolbox App 3.5</h3>\n<h4>Zoom controls</h4>\n<p>You can now zoom in and out with Cmd/Ctrl +. <a href=\"https://youtrack.jetbrains.com/issue/TBX-17170/\">TBX-17170</a></p>\n<h4>Bug fixes</h4>\n<ul>\n <li>IDEs no longer randomly disappear from the home view. <a href=\"https://x/TBX-10600/\">TBX-10600</a></li>\n</ul>\n<p>See the full list of release notes <a href=\"https://x\">here</a>.</p>"},{"date":"2026-04-15","type":"release","version":"3.4.3","majorVersion":"3.4","build":"3.4.3.81140","whatsnew":"<h3>Toolbox App 3.4.3</h3>\n<ul>\n <li>Fixed an internal error.</li>\n</ul>"}]}
"""#

@Test func extractsJetBrainsToolboxReleasesFromJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.jetbrains.toolbox"))
    let cl = try #require(ChangelogExtractor.extract(from: jbToolboxFixture, using: recipe))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "3.5")
    #expect(cl.entries[0].date == "2026-06-02")
    // One feature <p> + one <li>, footer <p> dropped by the negative lookahead.
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0].hasPrefix("You can now zoom in and out with Cmd/Ctrl +."))
    #expect(cl.entries[0].items[1].hasPrefix("IDEs no longer randomly disappear"))
    #expect(!cl.entries[0].items.contains { $0.contains("See the full list") })
    #expect(cl.entries[1].version == "3.4.3")
    #expect(cl.entries[1].items == ["Fixed an internal error."])
}

// Trimmed real markup from github.com/anomalyco/opencode/releases (GitHub
// releases, Ollama/RustDesk shape): two <section> blocks with an sr-only version
// h2, a <relative-time>, and a markdown-body list.
private let opencodeFixture = """
<section aria-labelledby="hd-1">
<h2 class="sr-only" id="hd-1">v1.15.13</h2>
<relative-time datetime="2026-05-30T12:00:00Z">May 30, 2026</relative-time>
<div class="markdown-body my-3">
<ul>
<li>Gateway Anthropic Opus 4.7+ adaptive reasoning now keeps summarized thinking.</li>
<li>Fixed a crash on startup.</li>
</ul>
</div>
</div>
</section>
<section aria-labelledby="hd-2">
<h2 class="sr-only" id="hd-2">v1.15.12</h2>
<relative-time datetime="2026-05-28T09:00:00Z">May 28, 2026</relative-time>
<div class="markdown-body my-3">
<ul>
<li>ACP integrations can now send prompts through acp-next.</li>
</ul>
</div>
</div>
</section>
"""

@Test func extractsOpenCodeGitHubReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.opencode.desktop"))
    let cl = try #require(ChangelogExtractor.extract(from: opencodeFixture, using: recipe))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "1.15.13")
    #expect(cl.entries[0].date == "2026-05-30")
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0] == "Gateway Anthropic Opus 4.7+ adaptive reasoning now keeps summarized thinking.")
    #expect(cl.entries[1].version == "1.15.12")
    #expect(cl.entries[1].items == ["ACP integrations can now send prompts through acp-next."])
}

// Trimmed real JSON from data.services.jetbrains.com/products/releases?code=IIU&type=release:
// two stable releases — 2026.1.2 (bug-fix with <li> list) and 2026.1 (major with section headings).
private let intellijFixture = #"""
{"IIU":[{"date":"2026-05-15","type":"release","notesLink":"https://youtrack.jetbrains.com/articles/IDEA-A-2100662679","version":"2026.1.2","majorVersion":"2026.1","build":"261.24374.151","whatsnew":"<p>IntelliJ IDEA 2026.1.2 is out with the following improvements:\n <br></p>\n<ul>\n <li>Projects can now be opened correctly via <code>.ipr</code> files. [<a href=\"https://youtrack.jetbrains.com/issue/IJPL-242321\">IJPL-242321</a>]</li>\n <li>The indentation for Java ternary expressions has been fixed. [<a href=\"https://youtrack.jetbrains.com/issue/IDEA-387867\">IDEA-387867</a>]</li>\n</ul>"},{"date":"2026-03-25","type":"release","version":"2026.1","majorVersion":"2026.1","build":"261.23610.47","whatsnew":"<p>IntelliJ IDEA 2026.1 is now out! The highlights include:</p>\n<ul>\n <li>ACP Registry: Browse and install AI agents in one click.</li>\n <li>Git worktrees: Work in parallel branches.</li>\n</ul>"}]}
"""#

@Test func extractsIntelliJIDEAReleasesFromJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.jetbrains.intellij"))
    let cl = try #require(ChangelogExtractor.extract(from: intellijFixture, using: recipe))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "2026.1.2")
    #expect(cl.entries[0].date == "2026-05-15")
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0].contains("Projects can now be opened correctly"))
    #expect(cl.entries[0].items[1].contains("ternary expressions"))
    #expect(cl.entries[1].version == "2026.1")
    #expect(cl.entries[1].date == "2026-03-25")
    #expect(cl.entries[1].items.count == 2)
    #expect(cl.entries[1].items[0].contains("ACP Registry"))
}

// MARK: - Thunderbird (Mozilla) — Stable / ESR / Beta share one page structure
// but live on different channels (Stable & ESR even share one bundle id). Each
// fixture is a trimmed slice of the real per-version notes page: an <h4> version
// heading, section <h3>s (ignored), and note-container → note-text → <p> items.
// `&amp;` proves entity decoding.

// Stable: the major .0 page the two-stage recipe resolves to (rich What's New +
// What's Fixed). Includes a non-note <div> after the items to prove the item
// pattern only sweeps note-text, not the footer.
private let thunderbirdStableFixture = """
<h4>Version 151.0 | Released May 19, 2026</h4>
<section><div class="container release-notes-container"><div class="section-text wide">
<h3 id="new" class="header-section">What’s New</h3>
<div id="note-0" class="note-container"><div class="note-flex">
<h4 class="note-category"><div class="category-container"><span class="category-icon"><svg></svg></span>new</div></h4>
<div class="note-text"><p>Enable Thundermail OAuth sign-in &amp; account auto-configuration</p></div>
</div></div>
<h3 id="fixes" class="header-section">What’s Fixed</h3>
<div id="note-1" class="note-container"><div class="note-flex">
<h4 class="note-category"><div class="category-container"><span class="category-icon"><svg></svg></span>fixed</div></h4>
<div class="note-text"><p>Forwarding/Redirecting Exchange message fails (see bug for work-around)</p></div>
</div></div>
<div class="see-all-releases"><a href="/en-US/thunderbird/releases">See All Releases</a></div>
</div></div></section>
"""

// ESR: the base major (140.0) notes page — same shape, different version literal.
private let thunderbirdESRFixture = """
<h4>Version 140.0 | Released July 2, 2025</h4>
<h3 id="new" class="header-section">What’s New</h3>
<div id="note-0" class="note-container"><div class="note-flex">
<h4 class="note-category"><div class="category-container">new</div></h4>
<div class="note-text"><p>Added ‘Mark as Spam’ and ‘Mark as Starred’ actions to mail notifications</p></div>
</div></div>
"""

// Beta: the cumulative cycle page — one "152.0beta" heading with several
// What's Fixed sections (b1/b2/b3); we sweep every note-text across them.
private let thunderbirdBetaFixture = """
<h4>Version 152.0beta | Released May 21, 2026</h4>
<h3 class="header-section">What’s New</h3>
<div id="note-0" class="note-container"><div class="note-text"><p>SecurityDevices enabled in enterprise policies</p></div></div>
<h3 class="header-section">What’s Fixed</h3>
<div id="note-1" class="note-container"><div class="note-text"><p>Calendar invitation parsing regression</p></div></div>
<h3 class="header-section">What’s Fixed</h3>
<div id="note-2" class="note-container"><div class="note-text"><p>Microsoft OAuth2 failed when HTTPS localhost redirect was not intercepted</p></div></div>
"""

@Test func extractsThunderbirdStableEntryAndDecodesEntities() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .stable))
    #expect(recipe.sourceTemplate != nil)   // stable is version-templated
    let cl = try #require(ChangelogExtractor.extract(from: thunderbirdStableFixture, using: recipe))
    #expect(cl.entries.count == 1)
    #expect(cl.entries[0].version == "151.0")
    #expect(cl.entries[0].date == "May 19, 2026")
    #expect(cl.entries[0].items.count == 2)   // one New + one Fixed, footer ignored
    #expect(cl.entries[0].items[0] == "Enable Thundermail OAuth sign-in & account auto-configuration")
}

@Test func extractsThunderbirdESREntryFromOwnChannelRecipe() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .esr))
    #expect(recipe.channel == .esr)
    let cl = try #require(ChangelogExtractor.extract(from: thunderbirdESRFixture, using: recipe))
    #expect(cl.entries.first?.version == "140.0")
    #expect(cl.entries.first?.items.count == 1)
}

// The per-version template + channel normalization is what makes the rendered
// version match the install: Stable uses the build as-is, ESR re-appends the
// `esr` suffix the install drops, Beta strips bN and appends "beta".
@Test func thunderbirdResolvedSourceMatchesExactVersionPerChannel() throws {
    let stable = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .stable))
    #expect(stable.resolvedSource(forVersion: "151.0.1").absoluteString
        == "https://www.thunderbird.net/en-US/thunderbird/151.0.1/releasenotes/")

    let esr = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .esr))
    // installed short version (esr suffix stripped) → suffix re-appended
    #expect(esr.resolvedSource(forVersion: "140.11.1").absoluteString
        == "https://www.thunderbird.net/en-US/thunderbird/140.11.1esr/releasenotes/")
    // probe version already carries the suffix → not doubled
    #expect(esr.resolvedSource(forVersion: "140.11.1esr").absoluteString
        == "https://www.thunderbird.net/en-US/thunderbird/140.11.1esr/releasenotes/")

    let beta = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbirdbeta", channel: .beta))
    #expect(beta.resolvedSource(forVersion: "152.0").absoluteString
        == "https://www.thunderbird.net/en-US/thunderbird/152.0beta/releasenotes/")
    #expect(beta.resolvedSource(forVersion: "152.0b3").absoluteString
        == "https://www.thunderbird.net/en-US/thunderbird/152.0beta/releasenotes/")

    // No version supplied → falls back to the recipe's fixed source untouched.
    #expect(stable.resolvedSource(forVersion: nil) == stable.source)
}

@Test func urlVersionTokenLeavesNonTemplatedChannelsUntouched() {
    #expect(ChangelogRecipe.urlVersionToken(for: "1.2.3", channel: nil) == "1.2.3")
    #expect(ChangelogRecipe.urlVersionToken(for: "1.2.3", channel: .stable) == "1.2.3")
}

@Test func extractsThunderbirdBetaCumulativeCycle() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbirdbeta", channel: .beta))
    let cl = try #require(ChangelogExtractor.extract(from: thunderbirdBetaFixture, using: recipe))
    #expect(cl.entries.first?.version == "152.0beta")
    #expect(cl.entries.first?.items.count == 3)   // swept across the three sections
}

@Test func thunderbirdStableAndESRSplitByChannelOnSharedBundleID() throws {
    let stable = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .stable))
    let esr = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .esr))
    #expect(stable.source != esr.source)
    #expect(stable.channel == .stable)
    #expect(esr.channel == .esr)
    // No channel given → falls back to the .stable recipe (not nil).
    let fallback = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.mozilla.thunderbird"))
    #expect(fallback.channel == .stable)
    // A channel with no recipe for this bundle id (.beta lives under a different
    // id) also degrades to the .stable recipe rather than returning nil.
    let betaOnStableID = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "org.mozilla.thunderbird", channel: .beta))
    #expect(betaOnStableID.channel == .stable)
}

@Test func channelAgnosticRecipeMatchesAnyChannel() throws {
    // Existing single-recipe apps carry no channel; passing one must not change
    // the result (backward compatibility for every non-Mozilla recipe).
    let onBeta = ChangelogRecipeRegistry.recipe(
        forBundleID: "pl.maketheweb.cleanshotx", channel: .beta)
    #expect(onBeta != nil)
    #expect(onBeta?.channel == nil)
}

// WeType (微信输入法) — trimmed slice of the real `__next_f` RSC blob: release
// objects for several platforms interleaved, OLDEST-FIRST (the macOS entries run
// 2.1.0 then 2.2.0 in document order), with a higher-versioned iOS entry between
// them to prove the `platform":3` anchor scopes to macOS. Notes carry a `&quot;`
// entity and a dash-bulleted `<h2>` line to prove decoding + the h2 item pattern.
private let weTypeFixture = """
[{"id":121,"title":"微信输入法 2.1.0 for Mac","release_date":1746000000,"version":"2.1.0","content":"","content_html":"<h2>- 新增「隔空传送」</h2>","platform":3,"download_url":""},\
{"id":130,"title":"微信输入法 3.4.0 for iOS","release_date":1747000000,"version":"3.4.0","content":"","content_html":"<h2>iOS only</h2>","platform":1,"download_url":""},\
{"id":152,"title":"微信输入法 2.2.0 for Mac","release_date":1748000000,"version":"2.2.0","content":"","content_html":"<h2>语音输入大模型升级</h2>\\n<h2>- 自动去掉&quot;嗯、啊&quot;等口水词</h2>","platform":3,"download_url":""}]
"""

@Test func extractsWeTypeMacOSEntriesNewestFirst() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.tencent.inputmethod.wetype"))
    #expect(recipe.newestLast)  // linchpin: the page lists releases oldest-first
    let changelog = try #require(ChangelogExtractor.extract(from: weTypeFixture, using: recipe))

    // Only the two macOS entries (iOS 3.4.0 is excluded by the platform:3 anchor),
    // flipped to newest-first by `newestLast`.
    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "2.2.0")
    #expect(changelog.entries[1].version == "2.1.0")
    // `&quot;` decoded, h2-line items captured.
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0] == "语音输入大模型升级")
    #expect(changelog.entries[0].items[1] == "- 自动去掉\"嗯、啊\"等口水词")
}

// WeChat's official updates site renders ONE Mac version per page (the recipe is
// templated on `{version}`): a Nuxt SSR page with a `faq_title`, a `发布日期`, and
// the change lines as `<h4>- …</h4>` inside `#page_center`. Trimmed but faithful.
private let weChatChangelogFixture = #"""
<style>.faq_title{font-size:32px}</style>
<div class="faq_content"><div class="faq__wrap"><div class="faq__detail">
<div class="faq_title"><!--[-->微信 4.1.10 for Mac 全新发布<!--]--></div><p>发布日期： 2026-05-27</p>
<div id="page_top" class="page_top"><p> 发布版本： 微信 4.1.10 for Mac <a href="https://dldir1v6.qq.com/weixin/Universal/Mac/WeChatMac_4.1.10.dmg">下载最新版本</a></p></div>
<div id="page_center"><p class="page_center_title">该版本主要更新如下：</p>
<!--[--><h4>- 在发消息时，支持边写边译为指定的语言；</h4><p><img src="https://res/mac1.png"></p><!--]-->
<!--[--><h4>- 修复一些已知问题。</h4><!--]-->
</div>
<div class="faq_footer"><h4>不相关的页脚标题</h4></div>
</div></div></div>
"""#

@Test func resolvesWeChatPerVersionUpdatesPage() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.tencent.xinWeChat"))
    // {version} is substituted with the offered/installed MARKETING version, so the
    // page fetched is exactly the release whose notes the user sees.
    #expect(recipe.resolvedSource(forVersion: "4.1.10").absoluteString
        == "https://weixin.qq.com/updates?platform=mac&version=4.1.10")
}

@Test func extractsWeChatNotesFromUpdatesPage() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.tencent.xinWeChat"))
    let changelog = try #require(ChangelogExtractor.extract(from: weChatChangelogFixture, using: recipe))

    // One entry — the page is per-version. Label + date match the official site.
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "4.1.10")
    #expect(changelog.entries[0].date == "2026-05-27")
    // The leading "- " bullet is stripped; the footer <h4> (outside #page_center) is
    // NOT picked up because `body` is bounded to the page_center container.
    #expect(changelog.entries[0].items == [
        "在发消息时，支持边写边译为指定的语言；",
        "修复一些已知问题。",
    ])
    // `content` preserves document order: the feature screenshot sits BETWEEN the two
    // change lines, exactly as on the vendor's page — not lumped at the end.
    #expect(changelog.entries[0].content == [
        .note("在发消息时，支持边写边译为指定的语言；"),
        .image(URL(string: "https://res/mac1.png")!),
        .note("修复一些已知问题。"),
    ])
}


// MARK: - Typeless (gzip'd __NEXT_DATA__ → structured decoder)

// Synthetic page: `__NEXT_DATA__.props.pageProps.compressedData` is base64(gzip(JSON))
// of a `<version> -> <locale> -> {date, features:[{title, content}]}` map. Two
// versions out of semver order ("1.9.0" listed before "1.10.0") to prove the
// decoder sorts numerically (1.10 > 1.9, not lexically). 1.10.0 also carries a
// non-en locale that must be ignored in favor of `en`.
private let typelessB64 = "H4sIAAAAAAAC/6WQQU+DMBTHv0rl5JIVWnCY7ep9J2/A4YFvo7GUhj62KeG7S9G4RaPJ9NTX37/5v/w6BDJchyLYsCFAMx8H7Jxq/fyRLVnwBIQexCJOuUh5nHhqNdCu7RqfNFC1zkOCvZtAVkzzDoH6Duf7EJAiPbdslUH/tGoNoSGPbrLitiaybhNF9GJRo3PcEZCqwqptIogOkq+5CI9Y2kVucuNLGGhbA7PQwb4DW4efQYl0yYOxGMelF5LiF9s5/KZ7z4X8j+7jtOoPtlJc6k4lZx92VFQzYJlW5vlcdQrxBI3VGNnFrDxtfa35w/Za0x9E8n6V3MkvLu8w79OyXOV9IkQ8f/b4Bok9TtBaAgAA"

private let typelessFixture = """
<!doctype html><html><body>
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"platform":"macos","compressedData":"\(typelessB64)"}},"page":"/help/release-notes/[platform]"}</script>
</body></html>
"""

@Test func typelessRecipeIsStructuredJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "now.typeless.desktop"))
    #expect(recipe.structuredFormat == .typelessReleaseNotes)
    #expect(recipe.source.absoluteString == "https://www.typeless.com/help/release-notes/macos")
}

@Test func gzipDecodeRoundTrips() throws {
    // GzipDecode handles the real base64+gzip member the page ships.
    let gz = try #require(Data(base64Encoded: typelessB64))
    let inflated = try #require(GzipDecode.decompress(gz))
    let json = try #require(String(data: inflated, encoding: .utf8))
    #expect(json.contains("\"1.10.0\""))
    #expect(json.contains("Ten paragraph"))
}

@Test func decodesTypelessSortedNewestFirstWithImages() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        typelessFixture, format: .typelessReleaseNotes, channel: nil, maxEntries: 12))

    #expect(changelog.entries.count == 2)
    // 1.10.0 outranks 1.9.0 numerically (a lexical sort would invert this).
    let ten = changelog.entries[0]
    #expect(ten.version == "1.10.0")
    #expect(ten.date == "2026-07-01")
    #expect(ten.title == "Ten")           // single feature → title rides the entry
    #expect(ten.items == ["Ten paragraph with a link."])  // [link](url) flattened
    // content preserves order: hero image first, then the prose note.
    #expect(ten.content == [
        .image(URL(string: "https://typeless-static.com/a/v1-10-0.webp")!),
        .note("Ten paragraph with a link."),
    ])

    let nine = changelog.entries[1]
    #expect(nine.version == "1.9.0")
    #expect(nine.title == "Nine")
    #expect(nine.items == ["Nine alpha paragraph.", "Nine beta paragraph."])
    #expect(nine.content == [
        .image(URL(string: "https://typeless-static.com/a/v1-9-0.webp")!),
        .note("Nine alpha paragraph."),
        .note("Nine beta paragraph."),
    ])
}

@Test func typelessDecodeRespectsMaxEntries() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        typelessFixture, format: .typelessReleaseNotes, channel: nil, maxEntries: 1))
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "1.10.0")
}

@Test func typelessDecodeDegradesToNilOnGarbage() {
    #expect(StructuredChangelogDecoder.decode(
        "<html>no next data here</html>", format: .typelessReleaseNotes,
        channel: nil, maxEntries: 12) == nil)
}

