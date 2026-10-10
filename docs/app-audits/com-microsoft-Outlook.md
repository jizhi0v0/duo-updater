# Microsoft Outlook

**这不是审计**：family `com-microsoft-Outlook`（`Recipes/com-microsoft-Outlook.swift`）里 Microsoft Outlook `com.microsoft.Outlook` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-microsoft-Outlook.swift — stable VendorProbe（MAU manifest，一键 `FullUpdaterLocation` pkg）

转引自 recipe 注释，未复测。

One-click repaired 2026-08-09. The old install spec read
`<key>Update Version Location</key>`, a key Microsoft has since removed
— the version still resolved, so the row quietly degraded to
detection-only with no error anywhere. Today's payload keys, and what
each actually points at (verified against the live manifest):

```
  Location / Payload      → `Outlook_<baseline>_to_<new>_Delta.pkg` on
                            the 24 delta entries — a PARTIAL payload
                            (504MB, 185 bundles, installKBytes 1117435)
  BinaryUpdaterLocation   → `…_BinaryDelta.pkg`, a 18–216MB binary patch
  FullUpdaterLocation     → `Microsoft_Outlook_<build>_Updater.pkg`, the
                            full standalone package (1.29GB, 210 bundles,
                            installKBytes 2664652, choice customLocation
                            /Applications)
```

Signed `Developer ID Installer: Microsoft
Corporation (UBF8T346G9)`, the same Team as the installed app (read from
the pkg's xar signature 2026-08-09, no full download needed).

复测 2026-09-14（03:15 UTC，只读 GET `0409OPIM2019.xml`）：manifest 里的 payload URL 都在 `res.public.onecdn.static.microsoft`（另有 `go.microsoft.com` 链接），payload 键是 `BinaryUpdaterLocation` / `FullUpdaterLocation` / `Location`；第一个 dict 的 `Update Version` 是 `16.109.26053122`，`FullUpdaterLocation` 是 `…/Microsoft_Outlook_16.109.26053122_Updater.pkg`；`_Delta.pkg` 这个串出现 48 次（没有按 entry 去数）。没有复查包大小与 bundle 数。

### Recipes/com-microsoft-Outlook.swift — changelog（Office for Mac release notes 的本 app 段，2026-10-10 接入）

接入时实测（2026-10-10，`learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac`，200，约 207 KB）：

- 页面 116 个带版本行的 `<h2>` 发布块，最新 `October 06, 2026` / `Version 16.113.4 (Build 26100421)`。版本行与 bundle 的对应：`16.113.4` = CFBundleShortVersionString，`16.113.26100421`（major.minor + Build）= CFBundleVersion，也就是探针报的版本；recipe 的条目用前者（单个捕获组拼不出后者）。
- 生产解析器（`ChangelogService.loadDiagnostic`，临时 Swift 测试，跑完已删）对线上页：30 条，最新 3 条 16.113.4（October 06, 2026，1 条）、16.113.3（September 29, 2026，2 条，首条「Fixed an issue preventing sharing documents and content from other Office applications to Outlook.」）、16.113.2（1 条）。条目数受 `maxEntries: 30` 截断。
- `\G` 链的正确性：用一份不依赖 `\G` 的 Python 参照实现（按 `<h3>` 分段、取本 app 与 Office Suite 段的 `<li>`/`<p>`）数前 30 个发布块，五个 app 的条目总数与生产解析器逐一相等（Excel 238、Word 189、PowerPoint 129、Outlook 154、OneNote 119）。
- 解析不到的历史形状（都在 30 条窗口之外）：`November 18, 2025` 的版本行按 app 列了两个 build（`… - Excel, OneNote; <br> … - PowerPoint`），整块不成条目；`November 14, 2025` 的列表没有 app 小标题，不归任何 app；`February 18, 2025` 的版本行前多了一段残留 `</li></ul>`，该块不成条目。
- Outlook 有一处段落不是列表（16.113 的 Resolved issues 是一个带 `<br>` 的 `<p>`），item 的 `<p>` 分支把它取成一条。30 条里 8 条有「Quality and performance improvements.」以外的内容。探针当时报 16.109.26053122（MAU manifest 停在 16.109，另一个会话在修），所以这页的最新条目领先探针，`duo verify` 的「changelog leads probe」警告在探针修好前是真信号。
- 接入前：这个 app 在 `ChangelogCoverage.acknowledged` 里标「feasible, not written yet」，详情页内嵌整页网页。
