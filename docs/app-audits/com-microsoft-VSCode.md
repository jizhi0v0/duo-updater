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

### Recipes/com-microsoft-VSCode.swift — stable / Insiders 一键接上 sha256（2026-10-07）

两条 VendorProbe 的一键改为：`.bodyPattern` 读更新 API 响应里的 `url`（按 commit 钉死的 zip，各自钉 `/stable/` 或
`/insider/` 段），并对同一份响应的 `sha256hash`（hex，`checksumFormat: .sha256Hex`，#1016）核对。之前是 `.redirect`
跟 `update.code.visualstudio.com/latest/darwin-arm64/<quality>`：当天它 302 到的正是响应里的同一个 zip，但 app 的周期
检查不跟这个重定向（`resolvesInstallRedirects`，#671），要等按下 Update 才跟——新 build 一发（Insiders 每天都发），
重定向就落到另一个文件上，和检查时读到的摘要对不上，只会以 `checksumMismatch` 拒装。地址和摘要出自同一个 body 就没有这个窗口。
响应里的 `hash` 是 40 位 SHA-1，不读。

实测（2026-10-07，生产 `VendorProbeSource.probeDiagnostic`）：

- stable 1.140.0：`url` `…/dbazure/download/stable/07f806f9…/VSCode-darwin-arm64.zip`，`/latest/darwin-arm64/stable`
  同时 302 到同一地址；下载 317,901,801 B，`shasum -a 256` = `86a64f1c…593b0`，等于 `sha256hash`。
- Insiders 1.141.0-insider：`url` `…/dbazure/download/insider/2a59476c…/VSCode-darwin-arm64.zip`（重定向同址）；下载
  328,370,582 B，`shasum -a 256` = `b92a9e0c…8c5c6`，等于 `sha256hash`。
- 两者 `VendorInstaller.verifySHA256` 通过，翻转一个字节的副本抛 `checksumMismatch`。

### Recipes/com-microsoft-VSCode.swift — Insiders ChangelogRecipe（两段式 `/updates` → `v1_N`，2026-10-10）

接入前：`ChangelogCoverage.acknowledged` 里记为 "feasible, not written yet"，pane 嵌入 `code.visualstudio.com/updates`，也就是 stable 的那一页。

实测（2026-10-10，只读 GET）：`/updates` 重定向到 `/updates/v1_141`（200，18,722 B），侧栏第一项是 `<a href="/updates/v1_142" >Insiders</a>`，其后是 1.141、1.140……。`/updates/v1_142` 200，7,184 B：`<h1>Visual Studio Code 1.142 (Insiders)</h1>`、`Last updated: October 7, 2026`，一个 `<h2>October 7, 2026</h2>` 下 1 条。当天 Insiders 探针读到的是 `1.142.0-insider`（`verify/baseline.json`）。

空白窗口（来自 `microsoft/vscode-docs` 的提交时间，`gh api`）：`VS Code release 1.141` 2026-10-06 23:17 UTC；`Initialize Insiders release notes`（新建 `v1_142.md`）2026-10-07 07:51 UTC，这一版有标题与 "Last updated"，没有任何 `## <日期>` 小节；第一条内容 `Update Insiders release notes` 2026-10-07 20:46 UTC。在这期间 recipe 解析为空，pane 退回嵌入网页。1.141 发布到 v1_142 建页之间的几小时里，侧栏 Insiders 项指向哪里没有观测到。stable 现在约每周一版（1.139 9-23、1.140 9-29、1.141 10-06），所以 Insiders 页一般只有一到几天的小节，新到旧。

生产解析器（`ChangelogService.loadDiagnostic`，临时测试，跑完删除）读线上地址：detail 页 `/updates/v1_142`，1 条；`1.142` / October 7, 2026 / 1 条。条目版本是页面的 `1.142`，不是探针的 `1.142.0-insider`（与 stable recipe 一样只到 major.minor）；带设置名的条目会把页面下拉菜单的 "Open in VS Code Open in VS Code Insiders" 文字留在句中。

### Recipes/com-microsoft-VSCode.swift — stable ChangelogRecipe：1.144 版式改动（2026-11-03）

复测（2026-11-03，只读 GET，跟随 `/updates` 的重定向）：落到 `/updates/v1_144`。相比 1.139 那版，页面又动了两处：日期改成 `<p class="release-metadata"><span>Release date: October 28, 2026</span>`（1.139–1.143 是 `Released`），要点 `</ul>` 与 `</section>` 之间多了一段 `<p>Read all about this, and more, in our … VS Code Wrapped blog post</p>`。旧 pattern 的日期前缀只认 `Released`，close anchor 又要求 `</ul>` 后面紧跟 `</section>`，所以整页 0 条：`duo verify --changelog --only com.microsoft.VSCode` 报 `noEntriesExtracted`（#1318 那条 issue 的 recipe id）。

同一轮里还有两个观测：

- `/updates/v1_143`（1.144 之前那一版）**整页没有日期行**：`<h1>` 后面直接是 "Follow us on …" → `<hr>` → "Welcome to the 1.143 release of Visual Studio Code."，没有 `release-metadata` 也没有 `Release date:`。新旧 pattern 在它上面都是 0 条——1.143 那一周 recipe 本来就不出条目，1.144 恢复。日期锚没有改成可选：把整段日期前缀做成 `(?:…)?` 之后，老版式（`<p><em>Release date:` 在 `<hr>` 之后）会因为前面那个 `.*?` 先满足而永远跳过日期组，1.138 / 1.130 / 1.123 的日期全部变空——实测确认，所以保持必选。
- 同日 `/updates/v1_142`、`v1_139`、`v1_138`、`v1_130`、`v1_123` 都还能正常访问，用来对照新 pattern 没有放宽过头。

修复：日期锚写成 `Released|Release date:` 二选一；aside 串（一个或多个 `<blockquote>` 或不含 `<ul>` 的 `<p>`）挪到 close anchor 前面，两种版式共用，这样 `</ul>` 到 `</section>` 之间多一段 `<p>` 不会再断。

验证（Python `re.S|re.I` 移植，线上页面）：v1_144 抽出 `1.144` / October 28, 2026 / 11 条；v1_142 `1.142` / October 14, 2026 / 5 条；v1_139 3 条；v1_138 3 条；v1_130 4 条；v1_123 5 条——后四页与修复前的版本、日期、条数逐页相同。生产解析器（`duo verify --changelog --only com.microsoft.VSCode --samples`）修复后：`1.144` / 11 条，无 warning。

