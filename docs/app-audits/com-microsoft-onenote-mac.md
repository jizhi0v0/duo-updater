# Microsoft OneNote

**这不是审计**：family `com-microsoft-onenote-mac`（`Recipes/com-microsoft-onenote-mac.swift`）里 Microsoft OneNote `com.microsoft.onenote.mac` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-microsoft-onenote-mac.swift — stable VendorProbe（MAU manifest，一键 `FullUpdaterLocation` pkg）

转引自 recipe 注释，未复测。

It used to use the suite fwlink (linkid=525133), on the reasoning that
there is no dedicated OneNote fwlink and the suite reports the same
version. That is true for DETECTION and wrong for INSTALL: that link
serves `Microsoft_365_and_Office_<build>_Installer.pkg`, which declares
eight destinations — Word, Excel, PowerPoint, Outlook, OneNote, OneDrive,
AutoUpdate and a Defender shim. Someone who has only OneNote installed
and clicks Update would have had the entire Office suite put on their
machine. Verified 2026-08-19 by parsing the real 2.7 GB suite package.

`FullUpdaterLocation` in the MAU manifest is a standalone 592 MB
OneNote package that declares exactly one destination,
`/Applications/Microsoft OneNote.app` (verified the same way), signed
`Developer ID Installer: Microsoft Corporation (UBF8T346G9)`.

### Recipes/com-microsoft-onenote-mac.swift — changelog（Office for Mac release notes 的本 app 段，2026-10-10 接入）

接入时实测（2026-10-10，`learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac`，200，约 207 KB）：

- 页面 116 个带版本行的 `<h2>` 发布块，最新 `October 06, 2026` / `Version 16.113.4 (Build 26100421)`。版本行与 bundle 的对应：`16.113.4` = CFBundleShortVersionString，`16.113.26100421`（major.minor + Build）= CFBundleVersion，也就是探针报的版本；recipe 的条目用前者（单个捕获组拼不出后者）。
- 生产解析器（`ChangelogService.loadDiagnostic`，临时 Swift 测试，跑完已删）对线上页：30 条，最新 3 条 16.113.4 / 16.113.3 / 16.113.2，各 1 条「Quality and performance improvements.」。条目数受 `maxEntries: 30` 截断。
- `\G` 链的正确性：用一份不依赖 `\G` 的 Python 参照实现（按 `<h3>` 分段、取本 app 与 Office Suite 段的 `<li>`/`<p>`）数前 30 个发布块，五个 app 的条目总数与生产解析器逐一相等（Excel 238、Word 189、PowerPoint 129、Outlook 154、OneNote 119）。
- 解析不到的历史形状（都在 30 条窗口之外）：`November 18, 2025` 的版本行按 app 列了两个 build（`… - Excel, OneNote; <br> … - PowerPoint`），整块不成条目；`November 14, 2025` 的列表没有 app 小标题，不归任何 app；`February 18, 2025` 的版本行前多了一段残留 `</li></ul>`，该块不成条目。
- OneNote 段几乎全是样板：30 条里只有 6 条有样板以外的内容，其中 5 条的非样板内容只来自 Office Suite 段（共享框架的 CVE、套件级功能），只有 1 条来自 OneNote 自己的段。用户看到的就是这些。探针当时报 16.109.26053122（MAU manifest 停在 16.109，另一个会话在修），页面领先探针；`duo verify` 的两个交叉检查对这一对都返回 nil（临时 DuoKit 测试实跑 `changelogLeadsProbeComplaint` / `changelogLagComplaint`，2026-10-10）：`Verify.buildDate` 把 `16.113`、`16.109` 读成 2016-01-13 / 2016-01-09，走按天的尺子，相差 4 天，低于 60 天阈值，所以不报警。
- 版本不匹配，有意接受（2026-10-10 用户决定）：条目带页面的 "Version"（`16.113.4` = CFBundleShortVersionString），探针比较 CFBundleVersion（`16.113.26100421`，取自安装包文件名，`versionIsBuild: true`）；页面把同一发布写成 "Version 16.113.4 (Build 26100421)"。后果：「正在运行的版本」圆点不会在这些条目上亮；`Changelog.carries(version: "16.113.26100421")` 对 `16.113.4` 的页面返回 false（临时测试实跑），笔记永远不算已确认、会被重读；verify 的落后/领先检查不触发（`Verify.buildDate` 把 `16.113` 读成日期）。要匹配需要一个多捕获组的 version 字段，会改动所有 changelog golden，所以不做。
- 接入前：这个 app 在 `ChangelogCoverage.acknowledged` 里标「feasible, not written yet」，详情页内嵌整页网页。
