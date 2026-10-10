# TigerVNC

**这不是审计**：family `com-tigervnc-tigervnc`（`Recipes/com-tigervnc-tigervnc.swift`）里 TigerVNC `com.tigervnc.tigervnc` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-tigervnc-tigervnc.swift — SourceForge VendorProbe（一键 dmg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里第一句原样留下，第二句（日期与 dmg 版本）搬到这里，改成「一键 dmg 挂载出来的 app 被 spctl 接受（checked 2026-08-16）」。

TigerVNC — Developer ID (Brian Hinz, S5LX88A9BW), notarized; `spctl`
accepts the mounted app. One-click verified 2026-08-16 against the
1.16.0 dmg the same way.

### Recipes/com-tigervnc-tigervnc.swift — GitHub releases changelog（JSON 正则，2026-10-10）

实测（2026-10-10，`gh api repos/TigerVNC/tigervnc/releases?per_page=40`）：共 37 条，`.90` 结尾的 13 条是 beta（`prerelease: true`），其余 24 条 stable，tag 都是 `v<x.y[.z]>`。正文全是邮件式公告：开头一句、缩进的 `  - ` 列表或一两段散文、最后固定的 "Binaries are available from SourceForge:" / 链接 / "Regards" / "The TigerVNC Developers"（1.3.0 是 "You can download binary builds from our old Sourceforge page:"）。

为什么不用 `.gitHubReleases`：先用生产 `StructuredChangelogDecoder` 跑同一份 JSON，24 条里 6 条没有列表（1.16.2、1.16.1、1.10.1、1.7.1、1.4.2、1.3.1），`GitHubMarkdownParser` 的散文兜底把页脚三行都当成了变更——1.16.2 的 5 项里 3 项是 "Binaries are available from SourceForge:"、"Regards"、"The TigerVNC Developers"，而 1.16.2 是面板最上面那条。改成正则后同一份数据：1.16.2 剩 2 项（两段正文），有列表的条目和解码器结果一致（如 1.16.0 的 10 项）。

生产解析器（临时 Swift test 调 `ChangelogService.loadDiagnostic`，跑完已删）对线上端点：HTTP 200，20 条，最新 `1.16.2` / `2026-03-26` / 2 项。baseline 的 `lastGoodVersion` 是 `1.16.0`，在条目里（第 3 条，10 项）。

旁注（不属于 changelog）：probe 报 1.16.0，但 SourceForge 的 `rss?path=/stable`（同日）已列出 `/stable/1.16.2/TigerVNC-1.16.2.dmg`；probe 读的是 `best_release.json` 的 mac 条目，看样子还指着 1.16.0。`best_release.json` 当天 curl 拿到的是 Cloudflare 403 挑战页，没能直接核对，属推断。
