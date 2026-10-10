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

### 2026-10-10 — manifest 换主机：`officecdn.microsoft.com` 那份停在 16.109

症状：`verify/baseline.json` 里 Outlook、OneNote 的 `lastGoodVersion` 都是 `16.109.26053122`，Excel 是 `16.113.26100421`；官方 release notes 已列 16.113.4 (Build 26100421, 2026-10-06)，含 Outlook 和 OneNote 两节。

实测（只读 GET，UA 为浏览器串）：

| URL 前缀（后接 `C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409<ID>.xml`） | OPIM2019 | ONMC2019 | XCEL2019 | MSau04 |
|---|---|---|---|---|
| `https://officecdn.microsoft.com/pr/` | 200，`16.109.26053122` | 200，`16.109.26053122` | 200，`16.109.26053122` | 200，`4.83.26040910` |
| `https://res.public.onecdn.static.microsoft/mro1cdnstorage/` | 200，`16.113.26100421` | 200，`16.113.26100421` | 200，`16.113.26100421` | 200，`4.85.26091737` |
| `https://res.cdn.office.net/mro1cdnstorage/` | 同上 | 同上 | 同上 | 同上 |
| `https://officecdnmac.microsoft.com/pr/` | 307 → `res.public.onecdn.static.microsoft` 同路径 | 同 | 同 | 同 |

旧主机上 Word（MSWD2019）、PowerPoint（PPT32019）也都停在 16.109，各 manifest 的 `<date>` 都是 2026-05-31；新主机这几份是 2026-10-04。所以冻住的是整台旧主机，跟 App ID 无关：新主机上的 manifest 仍然是 `OPIM2019` / `ONMC2019`（Outlook 39 个 dict 全是 `OPIM2019`），"2019" 不是原因。Excel/Word/PowerPoint 读的是 fwlink（如 525135），它 301 到 `res.public.onecdn.static.microsoft/…/Microsoft_Excel_16.113.26100421_Installer.pkg`，所以没受影响。

官方文档 [Network requests in Office for Mac](https://learn.microsoft.com/en-us/microsoft-365/enterprise/network-requests-in-office-2016-for-mac)（页面 updated_at 2026-08-20）把 `https://res.public.onecdn.static.microsoft/mro1cdnstorage/` 列为 "Microsoft AutoUpdate Manifests"，类型 ST（写死在客户端里）；整页没有 `officecdn.microsoft.com`。这次没有从 MAU 二进制里读它实际用的 URL，也没有抓包——host 的依据是文档加上 `officecdnmac` 的 307。

对用户的影响（从比较逻辑推出，未在装了 Outlook 的机器上复现）：装了 16.109 及以上的 Outlook/OneNote 永远看不到 16.110–16.113；低于 16.109 的会被提示升级到 16.109，一键装的也是 16.109 的 pkg。`duo verify --only com.microsoft.Outlook` 修复前给 ✓（`status ok, version 16.109.26053122`）——verify 只验能解析，看不出端点冻住。

修复：两条 recipe 的 `url` 换成 `res.public.onecdn.static.microsoft/mro1cdnstorage/…`，两条正则都没改。新 manifest 实测：第一个 dict 的 `Update Version` 是 `16.113.26100421`（Outlook 28 处、OneNote 13 处是这个版本，其余是 16.101 / 16.89 / … 等老 OS 封顶版本，排在后面）；`FullUpdaterLocation` 分别解析到 `Microsoft_Outlook_16.113.26100421_Updater.pkg` / `Microsoft_OneNote_16.113.26100421_Updater.pkg`（各自的 manifest 里只有这一种 FullUpdaterLocation）；`_Delta.pkg</string>` 分别出现 52 / 24 次。

两个 pkg（Range 读 xar 头和 TOC 里的 Distribution / PackageInfo，没下全包）：

- Outlook：200，Content-Length 1233749418；签名 `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`；pkg-ref 只有 `com.microsoft.Outlook`，`customLocation="/Applications"`；顶层 bundle `./Microsoft Outlook.app` `com.microsoft.Outlook` 16.113.4 / 16.113.26100421。
- OneNote：200，Content-Length 628294615；同一签名；pkg-ref 只有 `com.microsoft.onenote.mac`，`customLocation="/Applications"`；顶层 bundle `./Microsoft OneNote.app` `com.microsoft.onenote.mac` 16.113.4 / 16.113.26100421。

新增 `MicrosoftAutoUpdateManifestHostTests`：从注册表里挑出所有读 `/MacAutoupdate/*.xml` 的 recipe，要求 host 是 `res.public.onecdn.static.microsoft`。

真机一键（2026-10-10，用本分支 `make cli` 装的 `duo`）：先用 16.109 的 `Microsoft_{Outlook,OneNote}_16.109.26053122_Updater.pkg`（同 Team、已公证，仍在新主机上）经 `installer` 装回旧版；这两个 Updater 包只有最低系统版本检查，没装过也能装，且不带 MAU。`duo check` 两个都报 `16.109.26053122 → 16.113.26100421 [Vendor, installer]`。

- OneNote（不运行）：`duo install "/Applications/Microsoft OneNote.app" --yes --json` → `outcome: openedInstaller`、`bytesDownloaded: 628294615`、暂存 `Microsoft_OneNote_16.113.26100421_Updater.pkg`；在 Installer.app 里认证完成后 bundle 是 16.113.4 / 16.113.26100421，`codesign --verify --deep --strict` 通过，`spctl` 为 Notarized Developer ID（UBF8T346G9），receipt `com.microsoft.package.Microsoft_OneNote.app` 16.113.26100421，`duo check` 报 up to date。
- Outlook（16.109 运行中）：同样 `openedInstaller`、`bytesDownloaded: 1233749418`、暂存 `Microsoft_Outlook_16.113.26100421_Updater.pkg`；Installer 按 Distribution 的 `must-close` 先让 Outlook 退出（进程在版本切换前约 55 秒消失），装完不会自动重开。之后 bundle 16.113.4 / 16.113.26100421，签名、公证、receipt、`duo check` 结果同上。

一键在这里是「下载并校验后交给系统 Installer」，认证由用户在 Installer.app 里完成。

### Recipes/com-microsoft-Outlook.swift — changelog（Office for Mac release notes 的本 app 段，2026-10-10 接入）

接入时实测（2026-10-10，`learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac`，200，约 207 KB）：

- 页面 116 个带版本行的 `<h2>` 发布块，最新 `October 06, 2026` / `Version 16.113.4 (Build 26100421)`。版本行与 bundle 的对应：`16.113.4` = CFBundleShortVersionString，`16.113.26100421`（major.minor + Build）= CFBundleVersion，也就是探针报的版本；recipe 的条目用前者（单个捕获组拼不出后者）。
- 生产解析器（`ChangelogService.loadDiagnostic`，临时 Swift 测试，跑完已删）对线上页：30 条，最新 3 条 16.113.4（October 06, 2026，1 条）、16.113.3（September 29, 2026，2 条，首条「Fixed an issue preventing sharing documents and content from other Office applications to Outlook.」）、16.113.2（1 条）。条目数受 `maxEntries: 30` 截断。
- `\G` 链的正确性：用一份不依赖 `\G` 的 Python 参照实现（按 `<h3>` 分段、取本 app 与 Office Suite 段的 `<li>`/`<p>`）数前 30 个发布块，五个 app 的条目总数与生产解析器逐一相等（Excel 238、Word 189、PowerPoint 129、Outlook 154、OneNote 119）。
- 解析不到的历史形状（都在 30 条窗口之外）：`November 18, 2025` 的版本行按 app 列了两个 build（`… - Excel, OneNote; <br> … - PowerPoint`），整块不成条目；`November 14, 2025` 的列表没有 app 小标题，不归任何 app；`February 18, 2025` 的版本行前多了一段残留 `</li></ul>`，该块不成条目。
- Outlook 有一处段落不是列表（16.113 的 Resolved issues 是一个带 `<br>` 的 `<p>`），item 的 `<p>` 分支把它取成一条。30 条里 8 条有「Quality and performance improvements.」以外的内容。探针当时报 16.109.26053122（MAU manifest 停在 16.109，另一个会话在修），所以这页的最新条目领先探针；`duo verify` 的两个交叉检查对这一对都返回 nil（临时 DuoKit 测试实跑 `changelogLeadsProbeComplaint` / `changelogLagComplaint`，2026-10-10）：`Verify.buildDate` 把 `16.113`、`16.109` 读成 2016-01-13 / 2016-01-09，走按天的尺子，相差 4 天，低于 60 天阈值，所以不报警。
- 版本不匹配，有意接受（2026-10-10 用户决定）：条目带页面的 "Version"（`16.113.4` = CFBundleShortVersionString），探针比较 CFBundleVersion（`16.113.26100421`，取自安装包文件名，`versionIsBuild: true`）；页面把同一发布写成 "Version 16.113.4 (Build 26100421)"。后果：「正在运行的版本」圆点不会在这些条目上亮；`Changelog.carries(version: "16.113.26100421")` 对 `16.113.4` 的页面返回 false（临时测试实跑），笔记永远不算已确认、会被重读；verify 的落后/领先检查不触发（`Verify.buildDate` 把 `16.113` 读成日期）。要匹配需要一个多捕获组的 version 字段，会改动所有 changelog golden，所以不做。
- 接入前：这个 app 在 `ChangelogCoverage.acknowledged` 里标「feasible, not written yet」，详情页内嵌整页网页。
