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

// A trimmed fixture mirroring LM Studio's real Next.js /changelog/lmstudio index
// markup: the version lives in a `sr-only` span on the entry's anchor, the notes
// are in a `markdown-body` div closed by three nested </div>, there is no per-entry
// date, and items use nested <ul> for sub-bullets (the second item below) plus a
// `&gt;` entity to prove decoding. Two entries, the second with a single item.
// Note the per-version slug is nested (`/changelog/lmstudio/lmstudio-v…`) since the
// 2026-08 Bionic rebrand took over the bare `/changelog` root.
private let lmStudioFixture = """
<a class="absolute inset-0 z-0" href="/changelog/lmstudio/lmstudio-v0.4.15"><span class="sr-only">LM Studio 0.4.15</span></a>\
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
<a class="absolute inset-0 z-0" href="/changelog/lmstudio/lmstudio-v0.4.14"><span class="sr-only">LM Studio 0.4.14</span></a>\
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

// Two entries lifted VERBATIM (assets and hashes included) from a real
// releases.chatwise.app/releases response fetched 2026-08-21, in the order the
// endpoint emits them. Kept byte-for-byte, and in a raw literal so the `\n`
// escapes inside `changelog` stay two characters, because the shape that broke
// us was exactly that escaping: 26.6.0's notes do NOT end in a trailing `\n`,
// which is what made the old regex item pattern lose its last (here: only)
// bullet. 26.5.2 is the multi-bullet counterpart.
private let chatWiseFixture = #"""
[
{"version":"26.6.0","changelog":"- new provider: cloudflare workers ai","assets":[{"name":"ChatWise-26.6.0-x64.zip","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0-x64.zip","sha512":"hR0mkg45XrysNVY8TCDaXw3gqVeP+NAAvvYhlF5MYYZrhTTT7Y77FYDIoAHGAT7dEikSsmcuQ5nxXXbdBBGmOA=="},{"name":"ChatWise-26.6.0-arm64.zip","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0-arm64.zip","sha512":"PdsVbVwbQgYdW2HcmR1U5FaKr3zslAGy82eYVb2iRwT875VlYNi9/MHvdZceSDEvRV8979cU2N8Q8sC6IPaA2g=="},{"name":"ChatWise-26.6.0-x64.dmg","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0-x64.dmg","sha512":"iWgVJGPSlye6Ay7uJ08zhkBXY+h8FfD+sPY7C8rKQxO+jImxrWTF+qvbr9Lly9Rqu7Yyt32/04IucEXsmXAmXA=="},{"name":"ChatWise-26.6.0-arm64.dmg","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0-arm64.dmg","sha512":"Ue2BUmAkDB2MfUFo89oQcrWXvOr2q9wlwA0zs4KZYhpvx6kWyZKer1sMFUAHLcuxzsmveRYj4NzWH5dPcUoysw=="},{"name":"ChatWise-26.6.0-setup.exe","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0-setup.exe","sha512":"3PfSmUXs9mtAs/25n3oZUKh6BOwXPYHuDna+mw6uZdfC7R+SzzAgWlDo8mHpEpNWB7//213UvPQArgwezwUqEg=="},{"name":"ChatWise-26.6.0.AppImage","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0.AppImage","sha512":"oDnIZ36PKHbm8ShzIxuHtdl2hHCUmbLm/9TR7+aUqd8XeslcteMS6BNtGgHfDIC1Jhqbg0pdaP/+mia4Bl6MVw=="},{"name":"ChatWise-26.6.0.deb","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0.deb","sha512":"u6eRy6Yx40P+D1GcTXf8e7wA5m71mpf5v3fnBFAEBGfE4dpcivJqxU5E+jVO2vPoIf5E7uEDgza5b5efaq7sGQ=="},{"name":"ChatWise-26.6.0.rpm","url":"https://releases.chatwise.app/26.6.0/ChatWise-26.6.0.rpm","sha512":"US8qTdbIf75Kh5K18g267WXH9BqGD2OOEPyPgel8cUaM5GDmbawqT0GIkOcn2kL5dP8X9xYEQwu5iFR3faN/ow=="}],"date":"2026-06-26T16:04:26.161Z"},
{"version":"26.5.2","changelog":"- Add `curl.md` web fetch provider support\n- Custom provider: add Responses API support for openai-compatible providers\n- Set user-agent for LLM requests to `ChatWise/$version`\n- Add CJK-friendly remark plugins for better markdown rendering\n","assets":[{"name":"ChatWise-26.5.2-x64.zip","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2-x64.zip","sha512":"O98u9F82JZ6ZSPjt8MHYt+GoEH7gAeyetStz04GVFIlkfQdSaplh0GoM8IxtWo05o0IXmt4jtHeIePYx4AOBzw=="},{"name":"ChatWise-26.5.2-arm64.zip","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2-arm64.zip","sha512":"5thP89IXREnbenfzZRvT3p6amfPFW2zOB6/zFA410lHZBpjIx/PLirqVfhrGUTMLMTbb/YbJ+k8c2c4cDlskNw=="},{"name":"ChatWise-26.5.2-x64.dmg","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2-x64.dmg","sha512":"aCHj9cCyz7i3jLd55WIDTWnVnMxpLNeG6nMRI6HE5CdQkXMOzsEN21o/3AMnNfM+TUgY0y7x/OBeg3bXCQR8Pw=="},{"name":"ChatWise-26.5.2-arm64.dmg","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2-arm64.dmg","sha512":"0XFpaeX4d3skvOBtYkGo3hsMf0gpQxSkkIlFC3wxOVCB7uAGrPHRge6Gan0/B4QISJUuD2RU8LDR1H6dUK9YNw=="},{"name":"ChatWise-26.5.2-setup.exe","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2-setup.exe","sha512":"ybIFl3MghEN3Mx9odKS6hcjESib0IILBiMj6efcNXLxVc9//aMYRryTDjZSyjO4Bj9CHi4x9XqXaW4SzHso+Uw=="},{"name":"ChatWise-26.5.2.AppImage","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2.AppImage","sha512":"VhXtsqJ79aBxz2QiPCN6xuWGmINV//EnnUSqXlVniE21GeH/goL8oZf9HeJjrTEVWkAfQOZFYRoBAV+nM62QcA=="},{"name":"ChatWise-26.5.2.deb","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2.deb","sha512":"TNLNJ6EDdTV/ql3yAEiE1163hflarImlXVcg+6n/hNvucTk4oNo2oM53jFwZdKIjySWrWwNo5f7T7pWqCoKmCA=="},{"name":"ChatWise-26.5.2.rpm","url":"https://releases.chatwise.app/26.5.2/ChatWise-26.5.2.rpm","sha512":"nhaFrSermyq+eXqPddMElQIBKAk2nr2VFOe/Ukqs+bsi7VXeaDaBH930JODI83SAkvkC2tirFkTkDTj2gyVVog=="}],"date":"2026-05-27T06:20:07.532Z"}
]
"""#

// Byte-for-byte slices of two adjacent array elements each, taken from a real
// `curl` of central.github.com/deployments/desktop/desktop/changelog.json (stable)
// and the same URL with `?env=beta` appended — captured 2026-08-21. Both feeds
// are flat JSON arrays, newest-first, of `{name, notes, pub_date, version}` with
// `notes` already an array of one-line strings — no markdown, nothing to regex.
//
// The stable slice's 3.6.3 entry happens to carry a real `\"@null\"` JSON escape
// (a Git ref name quoted in the note text), so it doubles as the "does the decoder
// see a literal quote, not a backslash-quote" proof — no constructed case needed.
private let ghDesktopStableFixture = #"""
[{"name":"","notes":["[Improved] Update Git for Windows to v2.53.0.windows.4","[Improved] Update Git Credential Manager to 2.9.0"],"pub_date":"2026-08-11T22:07:40Z","version":"3.6.4"},{"name":"","notes":["[Fixed] Resolve error that prevented Copilot-based features from working correctly on Windows - #22509","[Fixed] Keep commit message @-mention autocomplete from surfacing users without a profile name when typing queries like \"@null\" - #22414. Thanks @sukanth!","[Fixed] Resolve a crash where the truncated repository path text could enter an infinite re-render loop - #22458","[Fixed] Fall back to the main worktree so a repository no longer appears as missing when its linked worktree folder was deleted outside Desktop - #22474","[Fixed] Keep files visible in the Changes list after Desktop returns from being backgrounded - #22497","[Fixed] Show an error dialog instead of silently doing nothing when Copilot fails to generate a commit message due to a Git error - #22496","[Fixed] Copilot sessions from generating commit messages or resolving conflicts do not show up in VS Code - #22443","[Fixed] Repository list scrolling no longer gets stuck or jitters when scrolling over tall groups (e.g. large organizations) - #22438. Thanks @peteski22!","[Improved] Clarify the line-ending conversion warning to explain that Git will automatically convert the file's line endings on next checkout, with a link to learn more - #21446. Thanks @Whitebrim!"],"pub_date":"2026-07-14T17:47:41Z","version":"3.6.3"}]
"""#

// Beta slice: two adjacent 3.6.3-beta entries, the first (beta3) also carrying a
// real `\"@null\"` escape — same proof as the stable slice, on the beta feed.
private let ghDesktopBetaFixture = #"""
[{"name":"","notes":["[Fixed] Resolve error that prevented Copilot-based features from working correctly on Windows - #22509","[Fixed] Keep commit message @-mention autocomplete from surfacing users without a profile name when typing queries like \"@null\" - #22414. Thanks @sukanth!"],"pub_date":"2026-07-08T12:55:09Z","version":"3.6.3-beta3"},{"name":"","notes":["[Fixed] Resolve a crash where the truncated repository path text could enter an infinite re-render loop - #22458","[Fixed] Fall back to the main worktree so a repository no longer appears as missing when its linked worktree folder was deleted outside Desktop - #22474","[Fixed] Keep files visible in the Changes list after Desktop returns from being backgrounded - #22497","[Fixed] Show an error dialog instead of silently doing nothing when Copilot fails to generate a commit message due to a git error - #22496","[Fixed] Copilot sessions from generating commit messages or resolving conflicts do not show up in VS Code - #22443"],"pub_date":"2026-07-07T17:21:05Z","version":"3.6.3-beta2"}]
"""#

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

// MARK: - SunLogin/AweSun (client-webapi.oray.com/softwares/… → structured decoder)

// Trimmed real response from client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM
// (re-verified live 2026-08-21: GET returns 200/~15KB, matching this shape):
// three entries chosen to cover single-item (V16.5.0.30757), multi-item numbered
// (v16.0.0.22931), and multi-item unnumbered (V16.3.0.29006). JSON uses \uXXXX
// for all non-ASCII text and \/ for forward slashes inside HTML strings — both
// resolved for free by JSONDecoder before the fragment parser ever sees them,
// which is why the structured decoder needs no entity/unicode-escape pass of
// its own (unlike the regex path it replaces).
private let aweSunFixture = #"""
{"logs":[{"logid":3299,"softwareid":187,"versionid":"3239","lang":"zh","logs":"<ol><li>V16.5.0.30757<\/li><li>1、修复已知bug<\/li><\/ol>","memoen":"V16.5.0.30757\r\n1、修复已知bug","memo":"V16.5.0.30757\r\n1、修复已知bug","updatedate":"2026-05-28 00:00:00","createtime":"2026-05-28 14:41:53"},{"logid":2881,"softwareid":187,"versionid":"2822","lang":"zh","logs":"<ol><li>v16.0.0.22931<\/li><li>1、【优化】功能交互，提升操作体验<\/li><li>2、【修复】已知问题，提升稳定性<\/li><\/ol>","memoen":"v16.0.0.22931 \r\n1、【优化】功能交互，提升操作体验\r\n2、【修复】已知问题，提升稳定性","memo":"v16.0.0.22931 \r\n1、【优化】功能交互，提升操作体验\r\n2、【修复】已知问题，提升稳定性","updatedate":"2025-07-17 00:00:00","createtime":"2025-07-17 14:57:37"},{"logid":3212,"softwareid":187,"versionid":"3153","lang":"zh","logs":"<ol><li>V16.3.0.29006<\/li><li>【新增】向日葵 MCP<\/li><li>【新增】端上支持分组<\/li><li>【新增】网络代理<\/li><li>【新增】跟随被控鼠标自动切换屏幕<\/li><li>【新增】支持设置低 \/ 中 \/ 高码率<\/li><li>【新增】Mac 跨平台文件拖拽<\/li><li>【新增】Mac 主控 HDR 支持<\/li><li>【新增】远程控控支持切换触摸 \/ 鼠标模式<\/li><li>【新增】智能远控硬件线缆状态<\/li><li>【优化】若干操作交互体验<\/li><li>【修复】若干已知问题<\/li><\/ol>","memoen":"V16.3.0.29006\r\n【新增】向日葵 MCP","memo":"V16.3.0.29006\r\n【新增】向日葵 MCP","updatedate":"2026-03-26 00:00:00","createtime":"2026-03-26 16:53:17"}]}
"""#

// The OLD regex-based recipe this format replaces. Kept only here (deliberately
// NOT in the registry any more) so the new structured decoder can be
// cross-checked against it on the exact same fixture below.
private let aweSunLegacyRegexRecipe = ChangelogRecipe(
    bundleID: "com.oray.sunlogin.macclient",
    source: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
    entryPattern:
        #""logid":\d+.*?"logs":"<ol><li>(?<version>[^<]+)<\\/li>(?<body>.*?)<\\/ol>".*?"updatedate":"(?<date>\d{4}-\d{2}-\d{2})"#,
    itemPatterns: [#"<li>(?<item>.*?)<\\/li>"#],
    mode: .json)

@Test func sunLoginRecipeIsStructuredJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.oray.sunlogin.macclient"))
    #expect(recipe.structuredFormat == .sunLoginSoftwareLogs)
    #expect(recipe.mode == .json)
}

@Test func decodesSunLoginEntriesFromLogsArray() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        aweSunFixture, format: .sunLoginSoftwareLogs, channel: nil, maxEntries: 40))

    #expect(changelog.entries.count == 3)

    // Entry 0: single item, \uXXXX Chinese text decoded (by JSONDecoder).
    #expect(changelog.entries[0].version == "V16.5.0.30757")
    #expect(changelog.entries[0].date == "2026-05-28")
    #expect(changelog.entries[0].items == ["1、修复已知bug"])

    // Entry 1: two numbered items.
    #expect(changelog.entries[1].version == "v16.0.0.22931")
    #expect(changelog.entries[1].date == "2025-07-17")
    #expect(changelog.entries[1].items == [
        "1、【优化】功能交互，提升操作体验",
        "2、【修复】已知问题，提升稳定性",
    ])

    // Entry 2: eleven unnumbered items; \/ inside text resolved to a literal /.
    // The LAST item is pinned explicitly — a regex-based cut is exactly the
    // kind of thing that silently drops the final bullet (see ChatWise).
    let entry2 = changelog.entries[2]
    #expect(entry2.version == "V16.3.0.29006")
    #expect(entry2.date == "2026-03-26")
    #expect(entry2.items.count == 11)
    #expect(entry2.items[0] == "【新增】向日葵 MCP")
    #expect(entry2.items[4] == "【新增】支持设置低 / 中 / 高码率")
    #expect(entry2.items.last == "【修复】若干已知问题")
}

@Test func sunLoginDecodeRespectsMaxEntries() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        aweSunFixture, format: .sunLoginSoftwareLogs, channel: nil, maxEntries: 1))
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "V16.5.0.30757")
}

@Test func sunLoginDecodeDegradesToNilOnGarbage() {
    #expect(StructuredChangelogDecoder.decode(
        "not json", format: .sunLoginSoftwareLogs, channel: nil, maxEntries: 40) == nil)
    #expect(StructuredChangelogDecoder.decode(
        #"{"logs":[]}"#, format: .sunLoginSoftwareLogs, channel: nil, maxEntries: 40) == nil)
}

// Old regex path vs new structured decoder, run against the SAME fixture:
// version/date/item-count/exact-text must match entry for entry.
@Test func sunLoginOldRegexAndNewDecoderAgree() throws {
    let legacy = try #require(ChangelogExtractor.extract(from: aweSunFixture, using: aweSunLegacyRegexRecipe))
    let structured = try #require(StructuredChangelogDecoder.decode(
        aweSunFixture, format: .sunLoginSoftwareLogs, channel: nil, maxEntries: 40))

    #expect(legacy.entries.count == structured.entries.count)
    for (old, new) in zip(legacy.entries, structured.entries) {
        #expect(old.version == new.version)
        #expect(old.date == new.date)
        #expect(old.items == new.items)
    }
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

@Test func chatWiseRecipeIsStructuredJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "app.chatwise"))
    #expect(recipe.structuredFormat == .chatwiseReleases)
    #expect(recipe.source.absoluteString == "https://releases.chatwise.app/releases")
}

@Test func decodesChatWiseKeepingTheLastBullet() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        chatWiseFixture, format: .chatwiseReleases, channel: nil, maxEntries: 20))

    #expect(changelog.entries.count == 2)

    // 26.6.0's changelog string has no trailing `\n` escape, so its only bullet
    // IS its last bullet — the case the previous regex pattern dropped outright.
    #expect(changelog.entries[0].version == "26.6.0")
    #expect(changelog.entries[0].date == "2026-06-26")
    #expect(changelog.entries[0].items == ["new provider: cloudflare workers ai"])

    // Multi-bullet entry: pin the count AND the final item specifically, so a
    // regression that silently truncates the tail fails here rather than merely
    // shrinking a count somewhere.
    let multi = changelog.entries[1]
    #expect(multi.version == "26.5.2")
    #expect(multi.date == "2026-05-27")
    #expect(multi.items.count == 4)
    #expect(multi.items.first == "Add `curl.md` web fetch provider support")
    #expect(multi.items.last == "Add CJK-friendly remark plugins for better markdown rendering")
}

@Test func extractsGitHubDesktopPerChannelFromStructuredJSON() throws {
    // Stable channel → recipe wiring: bundle id resolves to the .stable recipe,
    // and it's declared structured (no regex left to exercise).
    let stable = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.github.GitHubClient", channel: .stable))
    #expect(stable.structuredFormat == .gitHubDesktopChangelog)
    let scl = try #require(StructuredChangelogDecoder.decode(
        ghDesktopStableFixture, format: stable.structuredFormat!,
        channel: stable.channel, maxEntries: stable.maxEntries))
    #expect(scl.entries.count == 2)
    #expect(scl.entries[0].version == "3.6.4")
    #expect(scl.entries[0].date == "2026-08-11")
    #expect(scl.entries[0].items.count == 2)
    #expect(scl.entries[0].items[0] == "[Improved] Update Git for Windows to v2.53.0.windows.4")
    #expect(scl.entries[1].version == "3.6.3")
    #expect(scl.entries[1].date == "2026-07-14")
    #expect(scl.entries[1].items.count == 9)
    // A real JSON `\"@null\"` escape inside the entry must decode to a literal
    // quote, not survive as a backslash-quote.
    #expect(scl.entries[1].items[1] == "[Fixed] Keep commit message @-mention autocomplete from surfacing users without a profile name when typing queries like \"@null\" - #22414. Thanks @sukanth!")
    #expect(scl.entries[1].items.last == "[Improved] Clarify the line-ending conversion warning to explain that Git will automatically convert the file's line endings on next checkout, with a link to learn more - #21446. Thanks @Whitebrim!")

    // Beta channel — SAME bundle id, a DIFFERENT recipe/URL (`?env=beta`),
    // selected by `channel: .beta`. Same structured format.
    let beta = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.github.GitHubClient", channel: .beta))
    #expect(beta.structuredFormat == .gitHubDesktopChangelog)
    let bcl = try #require(StructuredChangelogDecoder.decode(
        ghDesktopBetaFixture, format: beta.structuredFormat!,
        channel: beta.channel, maxEntries: beta.maxEntries))
    #expect(bcl.entries.count == 2)
    #expect(bcl.entries[0].version == "3.6.3-beta3")
    #expect(bcl.entries[0].date == "2026-07-08")
    #expect(bcl.entries[0].items.count == 2)
    #expect(bcl.entries[0].items[0] == "[Fixed] Resolve error that prevented Copilot-based features from working correctly on Windows - #22509")
    #expect(bcl.entries[0].items.last == "[Fixed] Keep commit message @-mention autocomplete from surfacing users without a profile name when typing queries like \"@null\" - #22414. Thanks @sukanth!")
    #expect(bcl.entries[1].version == "3.6.3-beta2")
    #expect(bcl.entries[1].items.count == 5)
    #expect(bcl.entries[1].items.last == "[Fixed] Copilot sessions from generating commit messages or resolving conflicts do not show up in VS Code - #22443")
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

// Trimmed real markup from ghostty.org/docs/install/release-notes/1-3-1, fetched
// 2026-08-25 after the heading id changed. The version and date are in the
// <meta name="description"> near the top; items come from
// <li class="...weightRegular..."> elements in the Full Changelog section
// (now id="full-changelog"). Nav <li> elements (no class) are skipped.
private let ghosttyFixture = """
<meta name="description" content="Release notes for Ghostty 1.3.1, released on March 13, 2026."/>
<h1 class="Text-module__3468va__text">Ghostty 1.3.1</h1>
<div id="full-changelog"><div class="JumplinkHeader-module__SpWIGW__content JumplinkHeader-module__SpWIGW__h2"><h2>Full Changelog</h2></div></div>
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

// The recipe must read /changelog/lmstudio, NOT the bare /changelog root — that root
// now serves the changelog of **Bionic**, a different Element Labs product on a 1.0.x
// train, while `ai.elementlabs.lmstudio` is still 0.4.x. Pinning the URL in a test
// because the failure mode of getting this wrong is silent and wrong-looking-right:
// Bionic notes rendered under an LM Studio version.
@Test func lmStudioRecipeReadsTheLMStudioSubpageNotTheBionicRoot() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.elementlabs.lmstudio"))
    #expect(recipe.source.absoluteString == "https://lmstudio.ai/changelog/lmstudio")
}

// Real shape of a Bionic entry on the rebranded /changelog root: identical markup,
// only the product name in the `sr-only` span and the `bionic-v…` slug differ. The
// `LM Studio ` literal in the entry pattern is what keeps it out, so a Bionic-only
// body must extract nothing at all (→ nil → fall back to the embedded page).
private let bionicFixture = """
<a class="absolute inset-0 z-0" href="/changelog/bionic-v1.0.6"><span class="sr-only">Bionic 1.0.6</span></a>\
<div class="pointer-events-none relative z-10"><div class="flex flex-col gap-2">\
<h2 class="text-base font-semibold"><span class="rounded-sm underline">Bionic 1.0.6</span></h2>\
<div class="relative h-40 overflow-hidden md:h-44">\
<div class="markdown-body blog-markdown-body text-sm leading-6">\
<ul class="list-disc">
<li>Bionic-only change that must never appear under LM Studio</li>
</ul>
</div></div></div>
"""

@Test func lmStudioRecipeRejectsBionicEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "ai.elementlabs.lmstudio"))
    #expect(ChangelogExtractor.extract(from: bionicFixture, using: recipe) == nil)
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

// Byte-for-byte slice of the real feed (curled 2026-08-21 from
// mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json), four
// "notes[]" objects verbatim, covering every shape the decoder has to handle:
//   - 12.24.3: a `#### ` feature heading (kept, prefix stripped) followed by a
//     bold safety line, two prose paragraphs, and a trailing `[text](url)` link
//     line — 5 items, `\r\n` separators.
//   - 12.23.7: the same shape but with a `- ` bullet list in the middle — 8
//     items, exercises "not just single-paragraph" bodies.
//   - 12.17.3: the entry the OLD regex path truncated. Its one bug-fix line
//     contains an escaped quote (`\"8000\"`) — the old itemPattern's
//     `[^\\]{10,}` capture stopped at that backslash and silently dropped the
//     rest of the sentence. This fixture pins the FULL, correct sentence.
//   - 9.18.2: a legacy entry whose body uses a bare `\n` separator (only the
//     very last blank line is `\r\n\r\n`) — the format older entries actually
//     shipped in, which the old itemPattern (anchored on `\\r\\n`) could never
//     match at all.
private let postmanFeedFixture = #"""
{"notes":[
{"version":"12.24.3","content":"## Postman 12.24.3\r\nAugust 19, 2026\r\n\r\n### What’s New\r\n#### Mocks are now available in Cloud View\r\n**Available on Solo, Team, and Enterprise plans**\r\n\r\nMocks let you simulate APIs using custom JavaScript request handlers. In Cloud View, each mock receives a unique URL and is always available to handle requests.\r\n\r\nYou can also deploy a mock as a mock server, giving your team a cloud-hosted service they can send requests to at any time. By default, mock servers deployed from a mock are private and require workspace access or a valid Postman API key.\r\n\r\nTo learn more, see [Build API mocks with JavaScript](https://learning.postman.com/docs/design-apis/mock-apis/local-mock-servers).\r\n\r\n","createdAt":"2026-08-19T06:06:19.000Z"},
{"version":"12.23.7","content":"## Postman 12.23.7\r\nAugust 14, 2026\r\n\r\n### What’s New\r\n#### Buy Postman from AWS Marketplace\r\n\r\nYou can now purchase Postman Team and Enterprise plans directly through the AWS Marketplace, consolidating Postman within your existing AWS billing.\r\n\r\nThere are two ways to get started:\r\n\r\n- Subscribe from the AWS Marketplace listing and complete setup on a Postman-hosted page.\r\n- In the Postman app, click **Buy with AWS** to purchase without leaving Postman.\r\n\r\nBoth flows support purchasing for your own team or on behalf of another team in your organization. All subscription changes are managed through the AWS Marketplace console.\r\n\r\nAvailable for net-new Team and Enterprise plans.\r\n\r\nTo learn more, see [Purchase AWS from AWS Marketplace](https://learning.postman.com/docs/billing/buying-aws).\r\n\r\n","createdAt":"2026-08-14T02:32:42.000Z"},
{"version":"12.17.3","content":"## Postman 12.17.3\r\nJuly 2, 2026\r\n\r\n### Bug fixes\r\nFixed an issue in Postman Flows where configuration values typed as Number arrived as text at runtime (for example, 8000 became \"8000\" ), which could break blocks expecting a real number.\r\n","createdAt":"2026-07-02T02:32:20.000Z"},
{"version":"9.18.2","content":"## Postman v9.18.2\n\n### Bug Fixes\n- Fixed the issue of cookies not showing up in the interceptor debug session - [Github #10901](https://github.com/postmanlabs/postman-app-support/issues/10901)\r\n\r\n","createdAt":"2022-05-11T10:42:53.000Z"}
]}
"""#

@Test func postmanRecipeIsStructuredJSON() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.postmanlabs.mac"))
    #expect(recipe.structuredFormat == .postmanReleaseNotes)
    #expect(recipe.maxEntries == 30)
    #expect(recipe.entryPattern.isEmpty)
    #expect(recipe.itemPatterns.isEmpty)
}

@Test func decodesPostmanFeedSliceExactly() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        postmanFeedFixture, format: .postmanReleaseNotes, channel: nil, maxEntries: 10))

    #expect(changelog.entries.count == 4)

    let a = changelog.entries[0]
    #expect(a.version == "12.24.3")
    #expect(a.date == "2026-08-19")
    #expect(a.items.count == 5)
    #expect(a.items[0] == "Mocks are now available in Cloud View")
    #expect(a.items[1] == "**Available on Solo, Team, and Enterprise plans**")
    #expect(a.items.last == "To learn more, see [Build API mocks with JavaScript](https://learning.postman.com/docs/design-apis/mock-apis/local-mock-servers).")
    // The "## Postman 12.24.3" title line, the "August 19, 2026" date line, and
    // the "### What's New" section heading must all be filtered out — none of
    // them are a change line.
    #expect(!a.items.contains { $0.contains("## Postman") })
    #expect(!a.items.contains { $0.contains("August 19, 2026") })
    #expect(!a.items.contains { $0.contains("What’s New") })

    let b = changelog.entries[1]
    #expect(b.version == "12.23.7")
    #expect(b.date == "2026-08-14")
    #expect(b.items.count == 8)
    #expect(b.items[0] == "Buy Postman from AWS Marketplace")
    #expect(b.items[3] == "- Subscribe from the AWS Marketplace listing and complete setup on a Postman-hosted page.")
    #expect(b.items.last == "To learn more, see [Purchase AWS from AWS Marketplace](https://learning.postman.com/docs/billing/buying-aws).")

    // 12.17.3: the old regex path's item capture (`[^\\]{10,}`) stopped at the
    // backslash in `\"8000\"`, truncating this to "...8000 became ". The
    // structured decoder reads the real, unescaped string and must not lose the
    // rest of the sentence.
    let c = changelog.entries[2]
    #expect(c.version == "12.17.3")
    #expect(c.items.count == 1)
    #expect(c.items[0] == "Fixed an issue in Postman Flows where configuration values typed as Number arrived as text at runtime (for example, 8000 became \"8000\" ), which could break blocks expecting a real number.")

    // 9.18.2: legacy entry whose body is `\n`-separated (not `\r\n`) — a shape
    // the old itemPattern could never match, so this release's notes were
    // structurally invisible under the regex path. The decoder must still find it.
    let d = changelog.entries[3]
    #expect(d.version == "9.18.2")
    #expect(d.date == "2022-05-11")
    #expect(d.items == ["- Fixed the issue of cookies not showing up in the interceptor debug session - [Github #10901](https://github.com/postmanlabs/postman-app-support/issues/10901)"])
}

@Test func postmanDecodeRespectsMaxEntries() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        postmanFeedFixture, format: .postmanReleaseNotes, channel: nil, maxEntries: 2))
    #expect(changelog.entries.count == 2)
    #expect(changelog.entries.map(\.version) == ["12.24.3", "12.23.7"])
}

@Test func postmanMalformedBodyDecodesToNil() {
    #expect(StructuredChangelogDecoder.decode(
        "not json at all", format: .postmanReleaseNotes, channel: nil, maxEntries: 30) == nil)
    #expect(StructuredChangelogDecoder.decode(
        #"{"notes": []}"#, format: .postmanReleaseNotes, channel: nil, maxEntries: 30) == nil)
}

// Verbatim leading slice (lines 1-17, plus one trailing blank line so the last
// item's line-end still has a following "\n" for the item pattern's lookahead —
// see the note on that below) of the real response body from
// https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md,
// fetched 2026-08-21. Two version blocks: 5.24.2026081301 has a single
// link-free item; 5.23.2026080626 has 13 items, all but one carrying a
// trailing `[详情](url)` markdown link, and one (the uni-network-cronet line)
// carrying both a `[文档](url)` link AND a bare `<url>` autolink after it — the
// item pattern must strip all of that, in sequence, off the end of the line.
// No date field — the version itself encodes YYYYMMDD (5.23.2026080626 =
// 2026-08-06), same as the old HTML source; this is not a regression.
private let hbuilderxFixture = """
## 5.24.2026081301
* 修复 uniapp框架的一些Bug

## 5.23.2026080626
* Windows平台 修复 Windows 上使用在外部资源管理器打开文件时未选中目标文件 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=29907)
* 修复 5.0版本引发的 AI对比工具栏缺少跟随移动，多窗口下进行部分操作导致工具栏不消失 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31128)
* 修复 4.81版本引发的 部分git操作导致的文件变更无法在editor内同步 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=28392)
* 修复 条件编译置灰和 对比选中文件/uni-agent插件代码修改 的预览样式冲突 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=26579)
* 修复 在uniapp项目下uni.没有提示 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31477)
* 新增 HBuilderX CLI 支持通过 config get/set 命令行工具动态查询与管理全局配置项 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31115)
* 新增 HBuilderX CLI 独立编译 App 端 UTS 文件及 uni_modules 模块 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31116)
* 修复 HBuilderX cli launch 命令运行鸿蒙元服务时会卡住 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31740)
* 新增 manifest.json uni-app x Android平台 打包是否压缩so库的可视化选项 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31099)
* 新增 manifest.json uni-app x iOS平台可选模块配置 uni-oauth apple登录 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31102)
* 新增 manifest.json uni-app x 蒸汽模式 Android平台 可选模块配置 uni-network-cronet [文档](https://doc.dcloud.net.cn/uni-app-x/collocation/manifest-android.html#modulesnetwork) <https://issues.dcloud.net.cn/pages/issues/detail?id=31450>
* 新增 鸿蒙App配置增加可选模块配置uni-requestMerchantTransfer [文档](https://doc.dcloud.net.cn/uni-app-x/api/request-merchant-transfer.html) <https://issues.dcloud.net.cn/pages/issues/detail?id=31481>
* 新增 对应用打包所包含的动态库进行体积优化 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31285)

"""

@Test func extractsHBuilderXMarkdownEntriesWithLinksStripped() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "io.dcloud.HBuilderX"))
    let changelog = try #require(ChangelogExtractor.extract(from: hbuilderxFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "5.24.2026081301")
    #expect(changelog.entries[0].date == nil)
    #expect(changelog.entries[0].items.count == 1)
    #expect(changelog.entries[0].items[0] == "修复 uniapp框架的一些Bug")

    #expect(changelog.entries[1].version == "5.23.2026080626")
    #expect(changelog.entries[1].date == nil)
    #expect(changelog.entries[1].items.count == 13)
    // First item: trailing `[详情](url)` stripped clean off the end.
    #expect(
        changelog.entries[1].items.first
            == "Windows平台 修复 Windows 上使用在外部资源管理器打开文件时未选中目标文件")
    // Last item: same — the trailing link is gone, not left as a literal
    // "[详情](https://...)" tail.
    #expect(changelog.entries[1].items.last == "新增 对应用打包所包含的动态库进行体积优化")
    // The uni-network-cronet line carries a `[文档](url)` link immediately
    // followed by a bare `<url>` autolink — both must be stripped, not just one.
    let cronetItem = try #require(
        changelog.entries[1].items.first { $0.contains("uni-network-cronet") })
    #expect(
        cronetItem
            == "新增 manifest.json uni-app x 蒸汽模式 Android平台 可选模块配置 uni-network-cronet")
    #expect(!cronetItem.contains("["))
    #expect(!cronetItem.contains("<"))
}

// Verbatim leading slice (lines 1-13, plus trailing blank line for the same
// lookahead reason as above) of
// https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_alpha.md,
// fetched 2026-08-21. Every version heading carries the "-alpha" suffix, which
// the alpha recipe's version group requires (and the stable recipe's doesn't
// allow) — confirms the suffix survives capture intact rather than being eaten
// by the version pattern's dot-number matching.
private let hbuilderxAlphaFixture = """
## 5.23.2026080313-alpha
* 修复 cli launch 命令运行鸿蒙元服务时会卡住 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31740)

## 5.22.2026072503-alpha
* 修复 条件编译置灰和 对比选中文件/uni-agent插件代码修改 的预览样式冲突 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=26579)
* 修复 5.0版本引发的 AI对比工具栏缺少跟随移动，多窗口下进行部分操作导致工具栏不消失 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31128)
* 新增 HBuilderX CLI 支持通过 config get/set 命令行工具动态查询与管理全局配置项 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31115)
* 新增 HBuilderX CLI 独立编译 App 端 UTS 文件及 uni_modules 模块 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31116)
* 新增 manifest.json uni-app x Android平台 打包是否压缩so库的可视化选项 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31099)
* 新增 manifest.json uni-app x iOS平台可选模块配置 uni-oauth apple登录 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31102)
* 新增 manifest.json uni-app x 蒸汽模式 Android平台 可选模块配置 uni-network-cronet [文档](https://doc.dcloud.net.cn/uni-app-x/collocation/manifest-ios.html#modulesoauth) <https://issues.dcloud.net.cn/pages/issues/detail?id=31450>
* 新增 鸿蒙App配置增加可选模块配置uni-requestMerchantTransfer [文档](https://doc.dcloud.net.cn/uni-app-x/api/request-merchant-transfer.html) <https://issues.dcloud.net.cn/pages/issues/detail?id=31481>
* 新增 对应用打包所包含的动态库进行体积优化 [详情](https://issues.dcloud.net.cn/pages/issues/detail?id=31285)

"""

@Test func extractsHBuilderXAlphaMarkdownEntriesWithSuffix() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "io.dcloud.HBuilderXAlpha"))
    let changelog = try #require(ChangelogExtractor.extract(from: hbuilderxAlphaFixture, using: recipe))

    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "5.23.2026080313-alpha")
    #expect(changelog.entries[0].items.count == 1)
    #expect(changelog.entries[0].items[0] == "修复 cli launch 命令运行鸿蒙元服务时会卡住")

    #expect(changelog.entries[1].version == "5.22.2026072503-alpha")
    #expect(changelog.entries[1].items.count == 9)
    #expect(
        changelog.entries[1].items.first
            == "修复 条件编译置灰和 对比选中文件/uni-agent插件代码修改 的预览样式冲突")
    #expect(changelog.entries[1].items.last == "新增 对应用打包所包含的动态库进行体积优化")
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

// Real (trimmed) slice of api.github.com/repos/zed-industries/zed/releases as of
// 2026-08-21: 4 of the 100 sampled releases, in the API's actual newest-first
// order — v1.17.0-pre, v1.16.1, v1.16.1-pre, v1.15.1 — so decode order is a real
// property of this fixture, not something the test asserts into existence.
// Bodies are truncated to their first 1-2 bullets (full bodies ran 700–14000
// chars) and CRLF-normalized to LF (the live API mixes both across releases;
// `GitHubMarkdownParser`/`CharacterSet.newlines` treat them identically, so this
// is a lossless simplification for the fixture, not a behavior change). Tags,
// dates, and every character of the kept bullets are verbatim from the real
// response — including the real PR-link/attribution markdown, which is why the
// items below still carry `([#62577](...); thanks [x](...))`.
let zedGitHubReleasesFixture = #"""
[
  {
    "tag_name": "v1.17.0-pre",
    "prerelease": true,
    "published_at": "2026-08-19T17:47:30Z",
    "body": "This week's release includes tabular data previews for CSV, TSV, PSV, and SSV files with sortable and resizable columns, value-based row filtering, and right-click copying; new Git blame and stashing actions; and lower memory use when opening large files.\n\n## Shipped by the Zed Guild 🛡️\n\n- Added support for low reasoning effort for DeepSeek V4 Flash and V4 Pro. ([#62577](https://github.com/zed-industries/zed/pull/62577); thanks [lingyaochu](https://github.com/lingyaochu))\n- Improved JetBrains keymap behavior with CamelHump-style subword navigation for `alt-left`, `alt-right`, `shift-alt-left`, and `shift-alt-right` in editors. ([#51540](https://github.com/zed-industries/zed/pull/51540); thanks [loadingalias](https://github.com/loadingalias))"
  },
  {
    "tag_name": "v1.16.1",
    "prerelease": false,
    "published_at": "2026-08-19T16:11:34Z",
    "body": "This week's release includes Gemini 3.6 Flash support, collapsible grouped changes and optional stash messages in the Git Panel, zooming and horizontal scrolling for Mermaid diagrams, and a new setting for controlling whether the Terminal Panel opens automatically in new workspaces.\n\n## Shipped by the Zed Guild 🛡️\n\n- Improved Git Panel organization by making grouped change sections collapsible. ([#62441](https://github.com/zed-industries/zed/pull/62441); thanks [chirivelli](https://github.com/chirivelli))\n- Linux: Improved memory usage. ([#62192](https://github.com/zed-industries/zed/pull/62192); thanks [tidely](https://github.com/tidely))"
  },
  {
    "tag_name": "v1.16.1-pre",
    "prerelease": true,
    "published_at": "2026-08-18T15:58:22Z",
    "body": "- Fixed an issue where the Cursor ACP agent would fail to start ([#62826](https://github.com/zed-industries/zed/pull/62826))\n- Added git_gutter_width setting to the Settings UI with default (font-size-scaled) and custom (fixed pixel width) options ([#62813](https://github.com/zed-industries/zed/pull/62813))"
  },
  {
    "tag_name": "v1.15.1",
    "prerelease": false,
    "published_at": "2026-08-18T16:05:04Z",
    "body": "- Fixed an issue where the Cursor ACP agent would fail to start ([#62825](https://github.com/zed-industries/zed/pull/62825))\n- Git: Fixed the GPG passphrase modal appearing on every commit for users whose configured pinentry (e.g. pinentry-mac with the macOS Keychain) can supply the passphrase without Zed's help. Zed now only prompts when gpg cannot obtain the passphrase on its own. ([#62783](https://github.com/zed-industries/zed/pull/62783))"
  }
]
"""#

@Test func zedRecipesAreStructuredJSONSharingOneURL() throws {
    let stable = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.zed.Zed"))
    let preview = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "dev.zed.Zed-Preview"))
    #expect(stable.structuredFormat == .zedGitHubReleases)
    #expect(preview.structuredFormat == .zedGitHubReleases)
    #expect(stable.channel == .stable)
    #expect(preview.channel == .preview)
    // Same endpoint for both — the whole reason `channel` exists on the format.
    #expect(stable.source == preview.source)
}

@Test func decodesZedStableFromGitHubReleases() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        zedGitHubReleasesFixture, format: .zedGitHubReleases, channel: .stable, maxEntries: 15))

    // Only the two non-prerelease entries, in the API's newest-first order.
    #expect(changelog.entries.count == 2)
    #expect(changelog.entries[0].version == "1.16.1")
    #expect(changelog.entries[0].date == "2026-08-19")
    #expect(changelog.entries[0].items.count == 2)
    #expect(changelog.entries[0].items[0]
        == "Improved Git Panel organization by making grouped change sections collapsible. ([#62441](https://github.com/zed-industries/zed/pull/62441); thanks [chirivelli](https://github.com/chirivelli))")
    #expect(changelog.entries[1].version == "1.15.1")
    #expect(changelog.entries[1].date == "2026-08-18")
    #expect(changelog.entries[1].items.count == 2)
    // Explicitly pin the last item: the version-normalization and the markdown
    // link both survive to the end of the list, not just the first entry.
    #expect(changelog.entries[1].items.last
        == "Git: Fixed the GPG passphrase modal appearing on every commit for users whose configured pinentry (e.g. pinentry-mac with the macOS Keychain) can supply the passphrase without Zed's help. Zed now only prompts when gpg cannot obtain the passphrase on its own. ([#62783](https://github.com/zed-industries/zed/pull/62783))")
}

@Test func decodesZedPreviewFromGitHubReleasesNormalizingPreSuffix() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        zedGitHubReleasesFixture, format: .zedGitHubReleases, channel: .preview, maxEntries: 15))

    #expect(changelog.entries.count == 2)
    // "v1.17.0-pre" -> "1.17.0": leading `v` and trailing `-pre` both stripped so
    // the rail version matches the installed CFBundleShortVersionString.
    #expect(changelog.entries[0].version == "1.17.0")
    #expect(changelog.entries[0].date == "2026-08-19")
    #expect(changelog.entries[1].version == "1.16.1")
    #expect(changelog.entries[1].date == "2026-08-18")
    #expect(changelog.entries[1].items.last
        == "Added git_gutter_width setting to the Settings UI with default (font-size-scaled) and custom (fixed pixel width) options ([#62813](https://github.com/zed-industries/zed/pull/62813))")
}

@Test func zedChannelsDoNotLeak() throws {
    // A stable decode must never surface a `-pre`-tagged version, and vice versa
    // — the whole point of routing both channels through one shared endpoint.
    let stable = try #require(StructuredChangelogDecoder.decode(
        zedGitHubReleasesFixture, format: .zedGitHubReleases, channel: .stable, maxEntries: 15))
    #expect(!stable.entries.contains { $0.version.contains("17.0") })
    #expect(stable.entries.allSatisfy { !$0.version.hasSuffix("-pre") })

    let preview = try #require(StructuredChangelogDecoder.decode(
        zedGitHubReleasesFixture, format: .zedGitHubReleases, channel: .preview, maxEntries: 15))
    #expect(!preview.entries.contains { $0.version == "1.16.1" && $0.date == "2026-08-19" })
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
    #expect(changelog.entries[0].version == "0.2026.06.10.09.27.01")
    #expect(changelog.entries[0].date == "2026-06-10")
    // Sections flatten into one ordered list: 1 (New features) + 2 (Bug fixes).
    #expect(changelog.entries[0].items.count == 3)
    // Markdown PR link `([#12230](url))` flattens to `(#12230)`.
    #expect(changelog.entries[0].items[0] == "Git operations are now supported on remote sessions (#12230)")
    #expect(changelog.entries[0].items[1] == "Fixed a crash that could occur after clearing a terminal. (#12085)")
    #expect(changelog.entries[0].items[2] == "Applied the latest security patches.")
    #expect(changelog.entries[1].version == "0.2026.05.20.09.21.03")
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
    #expect(preview.entries[0].version == "0.2026.06.11.10.00.00")
}

// Warp's `changelogs.dev` sub-feed is fixture data, not release notes: one entry
// whose key tracks the live dev build but whose body is the pre-2022 `sections`
// shape carrying literal "dev 1"/"dev 2" placeholders under a 2021 date (plus
// `[TEST]` oz_updates). Two guards, because the failure would be showing that junk
// under a real installed version:
//   1. the decoder ignores `sections` entirely, so a dev-shaped feed yields nil;
//   2. no Warp-Dev recipe is registered, so the workbench never even asks.
private let warpDevPlaceholderFixture = """
{
  "dev": { "version": "v0.2026.08.07.08.31.dev_00" },
  "changelogs": {
    "dev": {
      "v0.2026.08.07.08.31.dev_00": {
        "date": "2021-11-23T10:07:01-06:00",
        "sections": [ { "title": "dev", "items": ["dev 1", "dev 2"] } ],
        "oz_updates": ["[TEST] Testing Oz recent updates!"]
      }
    }
  }
}
"""

@Test func warpDevPlaceholderFeedDecodesToNothing() {
    #expect(StructuredChangelogDecoder.decode(
        warpDevPlaceholderFixture, format: .warpChannelVersions,
        channel: .dev, maxEntries: 20) == nil)
}

@Test func warpDevHasNoChangelogRecipe() {
    #expect(ChangelogRecipeRegistry.recipe(
        forBundleID: "dev.warp.Warp-Dev", channel: .dev) == nil)
    // Stable and Preview still resolve to their own channel's recipe.
    #expect(ChangelogRecipeRegistry.recipe(
        forBundleID: "dev.warp.Warp-Preview", channel: .preview)?.channel == .preview)
    #expect(ChangelogRecipeRegistry.recipe(
        forBundleID: "dev.warp.Warp-Stable", channel: .stable)?.channel == .stable)
}

@Test func warpDecodeRespectsMaxEntries() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        warpFeedFixture, format: .warpChannelVersions, channel: .stable, maxEntries: 1))
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "0.2026.06.10.09.27.01")
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

/// The regex recipe this fixture exercises is no longer the ACTIVE `notion.id`
/// recipe in `ChangelogRecipeRegistry` — 2026-08-22 it was replaced by
/// `.notionPageChunk` (see that recipe's comment), because this page has no
/// build number at all and its post titles were standing in for one, which
/// never matched the installed app's real version. The old pattern is kept
/// commented out in the registry (not deleted) for reference, so it can no
/// longer be fetched via `ChangelogRecipeRegistry.recipe(forBundleID:)` — this
/// reconstructs it inline to keep the regression coverage for the pattern
/// itself (the CSS-modules-rename fixture in `NotionChangelogRecipeTests`
/// depends on the same pattern surviving).
func notionProductAnnouncementsRecipe() -> ChangelogRecipe {
    ChangelogRecipe(
        bundleID: "notion.id",
        source: URL(string: "https://www.notion.com/releases")!,
        entryPattern:
            #"<article class="(?:release_release__[^"]*|release-module-scss-module__[^"]*__release)">.*?"#
            + #"<time class="(?:release_date__[^"]*|release-module-scss-module__[^"]*__date)">(?<date>[^<]+)</time>.*?"#
            + #"<h2 class="[^"]*(?:release_title__[^"]*|release-module-scss-module__[^"]*__title)">(?<version>.*?)</h2>"#
            + #"(?<body>.*?)(?=<article class="(?:release_release__|release-module-scss-module__[^"]*__release")|</main>|<footer)"#,
        itemPatterns: [
            #"<p class="(?:contentfulRichText_paragraph__[^"]*|contentfulRichText-module-scss-module__[^"]*__paragraph)">(?<item>.*?)</p>"#,
        ],
        maxEntries: 20,
        minItemLength: 4)
}

@Test func extractsNotionEntries() throws {
    let recipe = notionProductAnnouncementsRecipe()
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

// Figma — three verbatim <entry> blocks copied byte-for-byte from the live Atom
// feed (https://www.figma.com/release-notes/feed/atom.xml, fetched 2026-08-19).
// The third entry's content carries a raw apostrophe inside the CDATA ("We've
// added…"), which exercises that the entry/item patterns land strictly inside
// the `<![CDATA[…]]>` delimiters rather than swallowing them — a naive
// `<[^>]*>` strip run before the CDATA is pulled out eats the whole
// `<![CDATA[…]]>` construct (`[^>]*` reads through to the `>` that closes
// `]]>`), which would otherwise corrupt exactly this kind of entry.
// Not `private`: reused by ChangelogParserGenerationGuardTests as one of the
// anchor fixtures for the mechanical parser-generation guard (issue #112) — a
// registry-driven fixture whose parse depends on the LIVE `ChangelogRecipe`
// for this bundle id, so a future recipe-data edit (entryPattern, itemPatterns,
// source) moves the guard's pinned output exactly the way a parser-code change
// does.
let figmaFixture = #"""
    <entry>
        <title type="html"><![CDATA[Recommend resources you want users to discover and use]]></title>
        <id>dece0d00-5f03-4a5d-aa04-3b0fad21b5eb</id>
        <link href="https://www.figma.com/release-notes/?title=recommend-resources-you-want-users-to-discover-and-use"/>
        <updated>2026-08-17T00:00:00.000Z</updated>
        <content type="html"><![CDATA[Admins can now choose which resources (skills, templates, libraries, and Make kits) are recommended to your organization or workspace.]]></content>
    </entry>
    <entry>
        <title type="html"><![CDATA[Get responsive text across screens with text wrap]]></title>
        <id>fdeb868a-690e-4286-9075-bc4d7fb7f1f9</id>
        <link href="https://www.figma.com/release-notes/?title=get-responsive-text-across-screens-with-text-wrap"/>
        <updated>2026-08-14T00:00:00.000Z</updated>
        <content type="html"><![CDATA[Text wrap makes your text responsive with two new options: Balance and Pretty. Set either on a text layer, a text style, or an individual paragraph in text settings.]]></content>
    </entry>
    <entry>
        <title type="html"><![CDATA[Try skills from the Community and make your own with the Figma agent]]></title>
        <id>c6056d47-fcc7-497d-aa75-ee928836bfe4</id>
        <link href="https://www.figma.com/release-notes/?title=weve-added-more-ways-to-discover-create-and-share-skills-for-the-figma-agent"/>
        <updated>2026-08-13T00:00:00.000Z</updated>
        <content type="html"><![CDATA[We've added more ways to discover, create, and share skills for the Figma agent.]]></content>
    </entry>
    """#

@Test func extractsFigmaEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.figma.Desktop"))
    let cl = try #require(ChangelogExtractor.extract(from: figmaFixture, using: recipe))
    #expect(cl.entries.count == 3)

    let first = try #require(cl.entries.first)
    #expect(first.version == "Recommend resources you want users to discover and use")
    #expect(!first.version.contains("CDATA"))
    #expect(!first.version.isEmpty)
    #expect(first.date == "2026-08-17")
    #expect(first.items.count == 1)
    #expect(first.items.last == "Admins can now choose which resources (skills, templates, libraries, and Make kits) are recommended to your organization or workspace.")

    let last = try #require(cl.entries.last)
    #expect(last.version == "Try skills from the Community and make your own with the Figma agent")
    #expect(!last.version.contains("CDATA"))
    #expect(last.date == "2026-08-13")
    #expect(last.items.count == 1)
    // Raw apostrophe survives untouched — nothing to decode, and the CDATA
    // delimiters themselves must not leak into the captured text.
    #expect(last.items.last == "We've added more ways to discover, create, and share skills for the Figma agent.")
}

// Checked against the live 444-entry feed on 2026-08-19: no entry's <title> or
// <content> carries an embedded HTML tag (e.g. <a>, <br>) inside its CDATA —
// every post today is plain sentence-style text. So there is no real-world
// fixture to pin that shape against; if the vendor starts embedding markup,
// stripTags will clean it (same as every other HTML-sourced recipe here), but
// there is nothing to regression-test until that actually happens.

// 1Password's changelog moved from this page to the stable channel's RSS feed
// on 2026-08-16 (see `OnePasswordFeedTests`), so the page fixture that used to
// live here is gone with the recipe it pinned. The feed is the sturdier read:
// fixed element names instead of `c-updates__*` styling classes.

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

// TablePro deliberately has no recipe any more — the app's Sparkle appcast carries
// the notes inline, so the pane reads them from the feed we already fetch. Pin that
// absence: a future "add a changelog for TablePro" would silently preempt the feed.
@Test func tableProHasNoChangelogRecipe() {
    #expect(ChangelogRecipeRegistry.recipe(forBundleID: "com.TablePro") == nil)
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

// Trimmed real bytes from the live JetBrains TBA releases JSON
// (data.services.jetbrains.com/products/releases?code=TBA, fetched 2026-08-21).
// Raw string so the JSON escapes (\\n between tags, \\" in attrs) stay literal as
// on the wire — `StructuredChangelogDecoder` decodes this with `JSONDecoder`
// itself (not the regex `ChangelogExtractor`), so the escapes are unescaped by
// `Decodable`, never by a hand-written item pattern. The whatsnew mixes a
// feature <p>, a <ul><li> bullet list, and the "See the full list…" footer the
// decoder must skip. Verified against the real recipe (`ChangelogExtractor` on
// this same fixture with the pre-migration regex recipe): identical entry count,
// versions, dates, item counts, and last item per entry.
private let jbToolboxFixture = #"""
{"TBA":[{"date":"2026-06-02","type":"release","downloads":{"mac":{"link":"https://x"}},"notesLink":"https://y","version":"3.5","majorVersion":"3.5","build":"3.5.0.84344","whatsnew":"<h3>What's New in Toolbox App 3.5</h3>\n<h4>Zoom controls</h4>\n<p>You can now zoom in and out with Cmd/Ctrl +. <a href=\"https://youtrack.jetbrains.com/issue/TBX-17170/\">TBX-17170</a></p>\n<h4>Bug fixes</h4>\n<ul>\n <li>IDEs no longer randomly disappear from the home view. <a href=\"https://x/TBX-10600/\">TBX-10600</a></li>\n</ul>\n<p>See the full list of release notes <a href=\"https://x\">here</a>.</p>"},{"date":"2026-04-15","type":"release","version":"3.4.3","majorVersion":"3.4","build":"3.4.3.81140","whatsnew":"<h3>Toolbox App 3.4.3</h3>\n<ul>\n <li>Fixed an internal error.</li>\n</ul>"}]}
"""#

@Test func decodesJetBrainsToolboxReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.jetbrains.toolbox"))
    #expect(recipe.structuredFormat == .jetBrainsProductReleases)
    let cl = try #require(StructuredChangelogDecoder.decode(
        jbToolboxFixture, format: .jetBrainsProductReleases, channel: nil, maxEntries: nil))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "3.5")
    #expect(cl.entries[0].date == "2026-06-02")
    // One feature <p> + one <li>; footer <p> dropped.
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0].hasPrefix("You can now zoom in and out with Cmd/Ctrl +."))
    #expect(cl.entries[0].items[1].hasPrefix("IDEs no longer randomly disappear"))
    #expect(!cl.entries[0].items.contains { $0.contains("See the full list") })
    #expect(cl.entries[0].items.last == "IDEs no longer randomly disappear from the home view. TBX-10600")
    #expect(cl.entries[1].version == "3.4.3")
    #expect(cl.entries[1].items == ["Fixed an internal error."])
    #expect(cl.entries[1].items.last == "Fixed an internal error.")
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

// Trimmed real bytes from the live JetBrains IIU releases JSON
// (data.services.jetbrains.com/products/releases?code=IIU&type=release, fetched
// 2026-08-21): two stable releases — 2026.1.2 (bug-fix with a <li> list, and a
// boilerplate lead <p> the decoder must NOT count as an item) and 2026.1 (major,
// same shape). Raw string so the JSON escapes stay literal as on the wire; see
// `jbToolboxFixture` above for why that matters. Verified against the real
// recipe (`ChangelogExtractor` on this same fixture with the pre-migration regex
// recipe): identical entry count, versions, dates, item counts, and last item.
private let intellijFixture = #"""
{"IIU":[{"date":"2026-05-15","type":"release","notesLink":"https://youtrack.jetbrains.com/articles/IDEA-A-2100662679","version":"2026.1.2","majorVersion":"2026.1","build":"261.24374.151","whatsnew":"<p>IntelliJ IDEA 2026.1.2 is out with the following improvements:\n <br></p>\n<ul>\n <li>Projects can now be opened correctly via <code>.ipr</code> files. [<a href=\"https://youtrack.jetbrains.com/issue/IJPL-242321\">IJPL-242321</a>]</li>\n <li>The indentation for Java ternary expressions has been fixed. [<a href=\"https://youtrack.jetbrains.com/issue/IDEA-387867\">IDEA-387867</a>]</li>\n</ul>"},{"date":"2026-03-25","type":"release","version":"2026.1","majorVersion":"2026.1","build":"261.23610.47","whatsnew":"<p>IntelliJ IDEA 2026.1 is now out! The highlights include:</p>\n<ul>\n <li>ACP Registry: Browse and install AI agents in one click.</li>\n <li>Git worktrees: Work in parallel branches.</li>\n</ul>"}]}
"""#

@Test func decodesIntelliJIDEAReleases() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.jetbrains.intellij"))
    #expect(recipe.structuredFormat == .jetBrainsProductReleases)
    let cl = try #require(StructuredChangelogDecoder.decode(
        intellijFixture, format: .jetBrainsProductReleases, channel: nil, maxEntries: nil))

    #expect(cl.entries.count == 2)
    #expect(cl.entries[0].version == "2026.1.2")
    #expect(cl.entries[0].date == "2026-05-15")
    #expect(cl.entries[0].items.count == 2)
    #expect(cl.entries[0].items[0].contains("Projects can now be opened correctly"))
    #expect(cl.entries[0].items[1].contains("ternary expressions"))
    #expect(cl.entries[0].items.last == "The indentation for Java ternary expressions has been fixed. [IDEA-387867]")
    #expect(!cl.entries[0].items.contains { $0.contains("is out with the following improvements") })
    #expect(cl.entries[1].version == "2026.1")
    #expect(cl.entries[1].date == "2026-03-25")
    #expect(cl.entries[1].items.count == 2)
    #expect(cl.entries[1].items[0].contains("ACP Registry"))
    #expect(cl.entries[1].items.last == "Git worktrees: Work in parallel branches.")
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

// 豆包输入法 (DoubaoIme) — the real 2026-08-21 response of
// `ime.doubao.com/api/v1/version/list?channel=release&version_code=1&platform=macos`,
// verbatim. One release object; six `- ` bullets joined by escaped `\n`; a
// `push_message.title` carrying a SECOND "0.9.6" that the entry pattern must not
// reach.
private let doubaoImeVersionListFixture = #"""
{"code":0,"data":{"list":[{"id":7673437500949397514,"channel":"release","platform":"macOS","version_name":"0.9.6","version_code":90601,"change_log":"- 新增账号登录，词库定时云端同步，换设备也不丢数据；\n- 新增离线语音，可在无网环境下语音输入，飞机、高铁上也能用；\n- 新增 ①、② 等符号，输入特殊符号更方便；\n- 优化磁盘写入策略，减少不必要的读写，更护设备更省电；\n- 修复开启全局语音后，按 Ctrl 无法发起识别优化中的问题；\n- 修复全局语音偶现无法调起的问题。","pkg_url":"https://lf3-static.bytednsdoc.com/obj/eden-cn/x/macOS/DoubaoImeInstaller_v90601_release_20260814_120854_64003a2e.zip","build_branch":"","commit":"","invalid":false,"back_id":"7673437500949397514","push_message":{"title":"豆包输入法已更新至 0.9.6 版本","subtitle":"新增账号登录，可跨设备同步个人词库","jump_url":"","jump_title":"立即体验"}}]},"msg":"success"}
"""#

/// The LAST bullet is the point of this test. The obvious item pattern to copy here
/// is ChatWise's, whose tail alternative is `\\n?$` — a literal backslash, optionally
/// followed by `n`, then end-of-string. A body that ends in text rather than a
/// backslash never satisfies it, so the final bullet is silently dropped. Six in,
/// six out.
@Test func extractsAllDoubaoImeBulletsIncludingTheLast() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.bytedance.inputmethod.doubaoime"))
    let changelog = try #require(
        ChangelogExtractor.extract(from: doubaoImeVersionListFixture, using: recipe))

    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "0.9.6")
    #expect(changelog.entries[0].items.count == 6)
    #expect(changelog.entries[0].items[0] == "新增账号登录，词库定时云端同步，换设备也不丢数据；")
    #expect(changelog.entries[0].items[5] == "修复全局语音偶现无法调起的问题。")
}

/// The endpoint is a "what should a client on <version_code> be offered" query, not
/// a page: drop any of its three parameters and it 400s. `version_code=1` is the
/// load-bearing part — it says "I am an impossibly old client", so the newest
/// release's notes come back no matter what the reader has installed. `channel` must
/// stay on the user-facing `release` track (the installed bundle's Info.plist says
/// `CHANNEL_NAME = release`); `inhouse` and `test` answer too, with ByteDance's
/// internal builds.
@Test func doubaoImeChangelogQueryAsksAsAnAncientReleaseClient() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(
        forBundleID: "com.bytedance.inputmethod.doubaoime"))
    let query = try #require(recipe.source.query)
    #expect(query.contains("version_code=1"))
    #expect(query.contains("channel=release"))
    #expect(query.contains("platform=macos"))
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

// Synthetic page in the LEGACY payload shape: `compressedData` is base64(gzip(JSON))
// of a `<version> -> <locale> -> {date, features:[{title, content}]}` map. Two
// versions out of semver order ("1.9.0" listed before "1.10.0") to prove the
// decoder sorts numerically (1.10 > 1.9, not lexically). 1.10.0 also carries a
// non-en locale that must be ignored in favor of `en`. Kept alongside the v3 array
// fixture below because `typelessNotes` still accepts both shapes.
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

// The CURRENT payload shape (`pageProps.dataKey == "typeless-release-notes--v3--macos"`,
// seen 2026-08-09): the inflated JSON is a flat ARRAY of notes with no locale nesting
// — the page is locale-scoped via `pageProps.embeddedLangCode` instead. The old
// map-only decode returned nil against this, which is why the page went to zero
// entries while still fetching 200. Ordering is not guaranteed, so "2.0.0" is listed
// before "2.2.0" here to prove the semver sort still runs.
private let typelessV3B64 = "H4sIAAAAAAAC/51QPW/CMBT8K66nIuXD8tBWzCwdmJpOaYZH8ogtHDuyH0kR4r/XrpBQBBPydPfO9+5efeYT+qCd5WsuC1EInvEOCBMU8i0X77n4iNxogPbOD5EfoHUhUgR94Ou6yfgegY4eEzpz0mTS92p2UdQ6S2gp4pdaoXfNqyIaw7os6TSiwRDyQEC6LVo3lFBOMhe5KGbcjasfm170YSN46D2Mis2aFANWG20P917/Jr+rIi42CN5unU9R+KW5ZMum8lFT+VzTT0vedcdW255twB/Y1nX4XHe57P4dkFVXLYuimItgZ05MW2bcnBvdK2JoJ+2dHeKucF89uwX9whipY5WKSRf5rgNKg9uxH52x+QNXCkU6MgIAAA=="

private let typelessV3Fixture = """
<!doctype html><html><body>
<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"platform":"macos","dataKey":"typeless-release-notes--v3--macos","embeddedLangCode":"en","compressedData":"\(typelessV3B64)"}},"page":"/help/release-notes/[platform]"}</script>
</body></html>
"""

@Test func decodesTypelessV3ArrayPayload() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        typelessV3Fixture, format: .typelessReleaseNotes, channel: nil, maxEntries: 12))

    #expect(changelog.entries.count == 2)

    // 2.2.0 sorts ahead of 2.0.0 despite being listed second. Two features, so each
    // title folds in as a heading note and none rides on the entry.
    let latest = changelog.entries[0]
    #expect(latest.version == "2.2.0")
    #expect(latest.date == "2026-07-28")
    #expect(latest.title == nil)
    #expect(latest.items == [
        "Introducing Dark Mode",
        "Use Typeless comfortably in low-light environments.",
        "Second Thing",
        "Second thing paragraph.",
    ])
    #expect(latest.content == [
        .note("Introducing Dark Mode"),
        .image(URL(string: "https://typeless-static.com/a/v2-2-0.webp")!),
        .note("Use Typeless comfortably in low-light environments."),
        .note("Second Thing"),
        .note("Second thing paragraph."),
    ])

    // Single feature → its title rides the entry, and the markdown link flattens.
    let prior = changelog.entries[1]
    #expect(prior.version == "2.0.0")
    #expect(prior.title == "Two")
    #expect(prior.items == ["Two paragraph with a link."])
    #expect(prior.content == [
        .image(URL(string: "https://typeless-static.com/a/v2-0-0.webp")!),
        .note("Two paragraph with a link."),
    ])
}

// Markdown permits raw HTML and Typeless writes a `<br>` hard break after a lead-in
// phrase ("**Dictate the way you think** <br>"). We render plain strings, so it has
// to be dropped rather than shown literally. Exercised through the Warp path because
// both formats share `bulletItems`.
@Test func bulletItemsDropRawHTMLLineBreaks() throws {
    let feed = """
    {
      "changelogs": {
        "stable": {
          "v0.2026.06.10.09.27.stable_01": {
            "date": "2026-06-10T09:27:00+0000",
            "markdown_sections": [
              { "title": "Notes", "markdown": "* Dictate the way you think <br>\\n* Second line<br/>after the break" }
            ]
          }
        }
      }
    }
    """
    let changelog = try #require(StructuredChangelogDecoder.decode(
        feed, format: .warpChannelVersions, channel: .stable, maxEntries: 20))
    #expect(changelog.entries[0].items == [
        "Dictate the way you think",
        "Second line after the break",
    ])
}

@Test func typelessV3DecodeRespectsMaxEntries() throws {
    let changelog = try #require(StructuredChangelogDecoder.decode(
        typelessV3Fixture, format: .typelessReleaseNotes, channel: nil, maxEntries: 1))
    #expect(changelog.entries.count == 1)
    #expect(changelog.entries[0].version == "2.2.0")
}

// A trimmed fixture mirroring Claude Desktop's docs `.md` changelog: two
// `<Update>` blocks with **General**/**Code**/**Cowork**/**3P** sections, a
// literal `<channel-message>` in a Code note (must survive stripTags:false), and
// a **3P** section in each block that must be dropped (enterprise/MDM-only).
private let claudeFixture = """
<Update label="v1.22209.0" description="2026-07-16">
  **General**

  * Improved responsiveness while artifacts generate.
  * Fixed tool errors blaming an organization policy.

  **Code**

  * Added per-row actions to queued messages.
  * Fixed a typed `<channel-message>` turn rendering as a spoofable card.

  **Cowork**

  * Fixed documents Claude creates not opening in the editor.

  **3P**

  * Added `disableBrowserExternalNavigation` to managed-settings.json.
</Update>

<Update label="v1.21459.3" description="2026-07-16">
  **General**

  * Fixed installed extensions failing to load.

  **3P**

  * No user-facing changes.
</Update>
"""

@Test func extractsClaudeEntriesSkippingThirdParty() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.anthropic.claudefordesktop"))
    let cl = try #require(ChangelogExtractor.extract(from: claudeFixture, using: recipe))

    #expect(cl.entries.count == 2)

    let latest = cl.entries[0]
    #expect(latest.version == "1.22209.0")
    #expect(latest.date == "2026-07-16")
    // General(2) + Code(2) + Cowork(1) = 5; the **3P** bullet is dropped.
    #expect(latest.items.count == 5)
    // stripTags:false keeps the literal angle-bracket text intact.
    #expect(latest.items.contains { $0.contains("<channel-message>") })
    // the 3P managed-settings note never leaks in.
    #expect(!latest.items.contains { $0.contains("disableBrowserExternalNavigation") })

    // Second block: only the General bullet; its **3P** "No user-facing changes." is cut.
    let prev = cl.entries[1]
    #expect(prev.version == "1.21459.3")
    #expect(prev.items == ["Fixed installed extensions failing to load."])
}


// MARK: - Cursor

/// Trimmed real response from cursor.com/changelog: one post, **repeated**, then a
/// footer. Both of those are what the live page actually does — it ships its whole
/// `<main>` twice (two `</html>` tags, a Next.js streaming artifact) and ends with
/// chrome that contains `<li>` and `<p>` elements of its own. A recipe that handles
/// only the pretty middle produces every release twice and then swallows the footer
/// into the last entry.
@Suite struct CursorChangelogTests {

    static func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.todesktop.230313mzl4w4u92"))
    }

    /// Cursor publishes no version numbers at all — the changelog is dated posts —
    /// so the date takes the version column and the headline becomes the title.
    @Test func readsDatedPostsAsEntries() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: cursorFixture, using: try Self.recipe()))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "Aug 3, 2026")
        #expect(entry.title == "Google Workspace Plugins")
        #expect(entry.items.contains { $0.hasPrefix("Google Drive: search files") })
    }

    /// The page carries its own content twice; the reader must not see each release
    /// listed two rows apart.
    @Test func theDuplicatedDocumentYieldsOneEntry() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: cursorFixture, using: try Self.recipe()))
        #expect(log.entries.count == 1)
    }

    /// The last post has no next post to stop at. Without `<footer` closing the body
    /// the entry ran to the end of the document and adopted the page chrome.
    @Test func theFooterIsNotReadAsChanges() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: cursorFixture, using: try Self.recipe()))
        let items = log.entries.flatMap(\.items)
        #expect(!items.contains { $0.contains("registered trademark") })
        #expect(!items.contains { $0.contains("nav item") })
    }
}

private let cursorFixture = #"""
p)] left-[-1px] inline-flex items-center"><a class="hover:text-theme-text inline-flex items-center" href="/changelog/google-workspace-plugins"><time dateTime="2026-08-03T00:00:00.000Z" class="type-base">Aug 3, 2026</time></a><span class="xl:hidden"> · </span><a class="text-theme-text-sec hover:text-theme-text active:text-theme-text xl:hidden" href="/changelog">Changelog</a></p></div><div class="col-span-full xl:col-start-7 xl:col-end-19"><div class="mx-auto w-full max-w-[48rem]"><header class="mb-v1 relative"><h1 class="type-lg text-balance" id="google-workspace-plugins"><a class="active:text-theme-text hover:opacity-90" href="/changelog/google-workspace-plugins">Google Workspace Plugins</a></h1></header><div class="prose prose--block"><p>Cursor can now read, write, and act across your Google Workspace.</p>
<p>New plugins give coding agents direct access to Gmail, Google Drive, and Calendar, so you can pull context, draft and update files, and manage your inbox and calendar without leaving Cursor.</p>
<p>Install plugins to connect:</p>
<ul>
<li><strong><a href="https://cursor.com/marketplace/cursor/google-drive" rel="noopener noreferrer" target="_blank">Google Drive</a>:</strong> search files and folders, open and download content, create and organize files</li>
<li><strong><a href="https://cursor.com/marketplace/cursor/gmail" rel="noopener noreferrer" target="_blank">Gmail</a>:</strong> search and read mail, draft and send messages, apply labels and manage threads</li>
<li><strong><a href="https://cursor.com/marketplace/cursor/google-calendar" rel="noopener noreferrer" target="_blank">Google Calendar</a>:</strong> read schedules, create and update events, find free time</li>
</ul>
<p>Browse the new plugins in the <a href="https://cursor.com/marketplace" rel="noopener noreferrer" target="_blank">Cursor Marketplace</a> or install them from the Customize page in Cursor. Learn more in our <a href="https://cursor.com/docs/plugins" rel="noopener noreferrer" target="_blank">docs</a>.</p></div></div></div></div></article><article><div class="grid-cursor gap-y-0 pb-v5 mb-v5 border-theme-border-02 border-b"><div class="mb-v2/12 col-span-full max-xl:mx-auto max-xl:w-full max-xl:max-w-[48rem] xl:col-end-7"><p class="text-theme-text-sec sticky top-[var(--site-sticky-top)] left-[-1px] inline-flex items-center"><a class="hover:text-theme-text inline-flex items-center" href="/changelog/google-workspace-plugins"><time dateTime="2026-08-03T00:00:00.000Z" class="type-base">Aug 3, 2026</time></a><span class="xl:hidden"> · </span><a class="text-theme-text-sec hover:text-theme-text active:text-theme-text xl:hidden" href="/changelog">Changelog</a></p></div><div class="col-span-full xl:col-start-7 xl:col-end-19"><div class="mx-auto w-full max-w-[48rem]"><header class="mb-v1 relative"><h1 class="type-lg text-balance" id="google-workspace-plugins"><a class="active:text-theme-text hover:opacity-90" href="/changelog/google-workspace-plugins">Google Workspace Plugins</a></h1></header><div class="prose prose--block"><p>Cursor can now read, write, and act across your Google Workspace.</p>
<p>New plugins give coding agents direct access to Gmail, Google Drive, and Calendar, so you can pull context, draft and update files, and manage your inbox and calendar without leaving Cursor.</p>
<p>Install plugins to connect:</p>
<ul>
<li><strong><a href="https://cursor.com/marketplace/cursor/google-drive" rel="noopener noreferrer" target="_blank">Google Drive</a>:</strong> search files and folders, open and download content, create and organize files</li>
<li><strong><a href="https://cursor.com/marketplace/cursor/gmail" rel="noopener noreferrer" target="_blank">Gmail</a>:</strong> search and read mail, draft and send messages, apply labels and manage threads</li>
<li><strong><a href="https://cursor.com/marketplace/cursor/google-calendar" rel="noopener noreferrer" target="_blank">Google Calendar</a>:</strong> read schedules, create and update events, find free time</li>
</ul>
<p>Browse the new plugins in the <a href="https://cursor.com/marketplace" rel="noopener noreferrer" target="_blank">Cursor Marketplace</a> or install them from the Customize page in Cursor. Learn more in our <a href="https://cursor.com/docs/plugins" rel="noopener noreferrer" target="_blank">docs</a>.</p></div></div></div></div></article><article><div class="grid-cursor gap-y-0 pb-v5 mb-v5 border-theme-border-02 border-b"><div class="mb-v2/12 col-span-full max-xl:mx-auto max-xl:w-full max-xl:max-w-[48rem] xl:col-end-7"><p class="text-theme-text-sec sticky top-[var(--site-sticky-to<footer class="site-footer"><p>Cursor is a registered trademark.</p><li>nav item that is not a change</li></footer>
"""#
