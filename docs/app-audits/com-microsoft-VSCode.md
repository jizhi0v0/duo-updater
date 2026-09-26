# VS Code

**这不是审计**：family `com-microsoft-VSCode`（`Recipes/com-microsoft-VSCode.swift`）里 VS Code `com.microsoft.VSCode` 与 VS Code Insiders `com.microsoft.VSCodeInsiders` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-microsoft-VSCode.swift — stable ChangelogRecipe（`code.visualstudio.com/updates`）

转引自 recipe 注释，未复测。前面的标记摘录是为了让句子从头开始而一并带上的。原句没写日期；日期取自引入这句话的提交：`19296da7`（2026-06-04）。

```
The top summary is:
  <h1>Visual Studio Code 1.123</h1>
  ...<hr><p><em>Release date: June 3, 2026</em></p>
  ...<ul><li><a …>…</a>: …</li>...</ul>
  [<blockquote><p>…event plug…</p></blockquote>]   ← optional, varies
  <p>Happy Coding!</p>
The highlights <ul> is the only list before "Happy Coding!", so the
body anchor is unambiguous; the trailing <blockquote> (an occasional
event/announcement aside, e.g. "VS Code Live at Build") is matched
optionally so its presence/absence doesn't break the close anchor — the
1.122→1.123 page added it, which is what regressed the old pattern to a
webview fallback.
```

复测 2026-09-14（03:16 UTC，只读 GET，跟随 `/updates` 的重定向）：落到 `/updates/v1_137`，`<h1>Visual Studio Code 1.137</h1>` 与 "Happy Coding!" 之间有 1 个 `<ul>`、1 个 `<blockquote>`。

复测 2026-09-17（只读 GET，跟随 `/updates` 的重定向，#697）：落到 `/updates/v1_138`。`</ul>` 与 "Happy Coding!" 之间出现了 `<p><em>These release notes were generated using GitHub Copilot and might contain inaccuracies.</em></p>`，没有 `<blockquote>`；旧 close anchor 只允许一个可选 `<blockquote>`，于是整页 0 条（sweep 报 `noEntriesExtracted`，连续两轮）。改成「`<blockquote>` 或不含 `<ul>` 的 `<p>` 的任意串」之后，同一组正则（Python `re.S|re.I` 移植）在 v1_138 上抽出 1.138 / September 16, 2026 / 3 条；在 v1_137、v1_136、v1_130、v1_123 上与旧 pattern 的版本、日期、条数、body 长度逐一相同（其中 v1_137 与 v1_123 带 `<blockquote>`，v1_136 与 v1_130 没有）。v1_110、v1_100 是更老的页面布局，新旧 pattern 都是 0 条——recipe 只读最新一页，不受影响。

复测 2026-09-26（只读 GET，跟随 `/updates` 的重定向）：落到 `/updates/v1_139`，页面换了布局——日期改成 `<p class="release-metadata"><span>Released September 23, 2026</span>`，下载链接收进 `<details class="release-downloads">` 里的 `<dl>`，要点列表包在 `<section class="release-highlights">` 里、后面紧跟 `</section>`，整页没有 "Release date:"，也没有 "Happy Coding!"。旧 pattern 0 条，设置页 Detection recipes 报 `fetched code.visualstudio.com but extracted no entries`。同日取的 v1_138、v1_130 仍是旧布局。改成「两种日期前缀二选一，close anchor 为 `</section>` 或旧的 aside 串 + "Happy Coding!"」之后，Python `re.S|re.I` 移植在 v1_139 上抽出 1.139 / September 23, 2026 / 3 条，v1_138 上 1.138 / September 16, 2026 / 3 条，v1_130 上 1.130 / July 22, 2026 / 4 条。
