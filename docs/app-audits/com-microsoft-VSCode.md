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
