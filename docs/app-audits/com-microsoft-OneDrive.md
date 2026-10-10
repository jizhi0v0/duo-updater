# Microsoft OneDrive

**这不是审计**：family `com-microsoft-OneDrive`（`Recipes/com-microsoft-OneDrive.swift`）里 Microsoft OneDrive `com.microsoft.OneDrive` 的覆盖情况没有审过。这份文件只接收 recipe 的实测历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### Recipes/com-microsoft-OneDrive.swift — 探针从下载 fwlink 换到 standalone updater 的 Production manifest（2026-10-10）

接入前：探针读 `go.microsoft.com/fwlink/?linkid=823060` 的 302 `Location`（`/Installers/<4 段版本>/universal/OneDrive.pkg`），取前三段；一键安装跟同一个 fwlink。

2026-10-10 实测：

- fwlink 仍 302 到 `…/Installers/26.153.0809.0004/universal/OneDrive.pkg`。Homebrew 的 `onedrive` cask（formulae.brew.sh API）同样是 `26.153.0809.0004`。
- `learn.microsoft.com/en-us/sharepoint/sync-release-notes` 的 macOS「Current Version」表写 Production 已发布 `26.173.0906.0008`，链接正是 linkid=823060；macOS Production Ring 最新条目 `26.173.0906.0008 (September 25, 2026)`。
- `https://g.live.com/0USSDMC_W5T/MacODSUProduction` 302 到 `https://oneclient.sfx.ms/Mac/Prod/ab157a739752435ccb69d349c175fb1cbf3651f1.xml`（658 字节 plist）：`ManifestArray` 只有一个 dict，`CFBundleShortVersionString` `26.173.0906`、`CFBundleVersion` `0906.0008`、`UniversalPkgBinaryURL` `…/Installers/26.173.0906.0008/universal/OneDrive.pkg`、`UniversalPkgSha256Hash` `zAJwEw3DLPktJ6UqFFY5psu/DogoehtWA75Ckq+dpmo=`、`UpdatePeriod` 1440、`Throttle` 100。
- fwlink 卡住的时间：`verify/baseline.json` 的 git 历史里 `vendor:com.microsoft.OneDrive:stable` 的 `lastGoodVersion` 依次是 26.119.0622（2026-08-09）、26.134.0713（08-11）、26.139.0720（08-15）、26.145.0728（08-25）、26.150.0804（09-03）、26.153.0809（09-12），此后再没变；同期页面与 manifest 走到了 26.158 / 26.163 / 26.168 / 26.173。即 fwlink 从约 2026-09-12 起停在 26.153。
- 真包核对（下载到临时目录，只读，没有安装也没有打开）：`UniversalPkgBinaryURL` 的包 412,501,448 字节，SHA-256（base64）等于 manifest 的 `UniversalPkgSha256Hash`；`pkgutil --check-signature`：`Developer ID Installer: Microsoft Corporation (UBF8T346G9)`，notarized，时间戳 2026-09-26；`Distribution` 里 `com.microsoft.OneDrive` 的 CFBundleShortVersionString `26.173.0906` / CFBundleVersion `26173.0906.0008`；`PackageInfo` 的 install-location `/Applications`，payload 全在 `OneDrive.app/` 下；`Scripts` 里的 `od_service` 往 `/Library/LaunchDaemons`、`/Library/LaunchAgents` 写 updater daemon、standalone updater agent、SyncReporter agent 的 plist——所以 `kind` 必须是 `.pkg`。
- `Throttle`：未找到微软文档（2026-10-10 搜索无结果），含义未验证；字面看像分阶段推送百分比，当时为 100。recipe 不读它。
- `verify` 交叉检查（临时 DuoKit 测试实跑）：页面 `26.173.0906` 对旧探针 `26.153.0809`，`changelogLeadsProbeComplaint` 报「reads AHEAD of every probe row」；换到 manifest 后两边都是 26.173.0906。

### Recipes/com-microsoft-OneDrive.swift — changelog（sync release notes 的 macOS Production Ring，2026-10-10 接入）

- 探针原 `changelogURL`（`support.microsoft.com/…/onedrive-release-notes-845dcf18-…`）301 到 `learn.microsoft.com/sharepoint/sync-release-notes`，再 302 到 `/en-us/sharepoint/sync-release-notes`，200（约 105 KB）；`changelogURL` 改为最终地址。
- 生产解析器对线上页：30 条（`maxEntries` 截断），最新 26.173.0906（September 25, 2026）、26.168.0830、26.163.0823，各 1 条「We resolved product issues to improve the reliability and performance of the OneDrive sync app.」；全部 39 条。
- 接入前：`ChangelogCoverage.acknowledged` 标「feasible, not written yet」，详情页内嵌整页网页。
