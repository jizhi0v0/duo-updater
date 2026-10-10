# TigerVNC

**这不是审计**：family `com-tigervnc-tigervnc`（`Recipes/com-tigervnc-tigervnc.swift`）里 TigerVNC `com.tigervnc.tigervnc` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-tigervnc-tigervnc.swift — SourceForge VendorProbe（一键 dmg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里第一句原样留下，第二句（日期与 dmg 版本）搬到这里，改成「一键 dmg 挂载出来的 app 被 spctl 接受（checked 2026-08-16）」。

TigerVNC — Developer ID (Brian Hinz, S5LX88A9BW), notarized; `spctl`
accepts the mounted app. One-click verified 2026-08-16 against the
1.16.0 dmg the same way.

### Recipes/com-tigervnc-tigervnc.swift — 从 `best_release.json` 改读 stable RSS（2026-10-10）

起因：给 changelog recipe 取证时（PR #1160）发现 GitHub 已有 v1.16.2（2026-03-26），`verify/baseline.json` 里 vendor probe 却一直是 1.16.0。

实测（2026-10-10，`User-Agent: DuoUpdater/0.1`，即 probe 自己发的 UA）：

- `curl -A DuoUpdater/0.1 https://sourceforge.net/projects/tigervnc/best_release.json` → 200。`platform_releases.mac.filename` 是 `/stable/1.16.0/TigerVNC-1.16.0.dmg`（2026-01-27），同一份文档里 `linux` 和顶层 `release` 已是 `/stable/1.16.2/VncViewer-1.16.2.jar`（2026-03-26）。所以「best_release.json 还指着 1.16.0」是实测，不是推断。2026-08-16 抓的测试 fixture 里也已经是这样：mac 1.16.0、linux 1.16.2。当时的一键验证只核了 1.16.0 的 dmg，没发现落后。
- `curl -A DuoUpdater/0.1 'https://sourceforge.net/projects/tigervnc/rss?path=/stable'` → 200，119,607 B，100 个 `<item>`：77 个属于 1.16.2、23 个属于 1.16.1。整个 feed 里只有一个 dmg：`/stable/1.16.2/TigerVNC-1.16.2.dmg`（第 73 个，pubDate 2026-03-26 11:53:06，md5 `f304571d98c4b39bbd82f135f25d1830`，6,845,311 B）。同一 URL 用 Safari UA 也是 200。按 pubDate 大体从新到旧，但不严格：100 个 item 里有 2 处相邻倒序，各差 1 秒，都在同一批上传里（第 64/65、81/82 个）。recipe 用 `selectHighest`，不依赖顺序。加 `&limit=200` 或 `&limit=1000` → 400，窗口放不大。
- 下载 `files/stable/1.16.2/TigerVNC-1.16.2.dmg/download`（302 → 镜像）：6,845,311 B，md5 与 RSS 一致。挂载后 `TigerVNC.app`：`com.tigervnc.tigervnc`，`CFBundleShortVersionString` 1.16.2、`CFBundleVersion` 1.16.2f，universal（x86_64 arm64）。`codesign --verify --deep --strict` 通过，TeamIdentifier S5LX88A9BW，`spctl -a -t exec` → accepted，`source=Notarized Developer ID`，`origin=Developer ID Application: Brian Hinz (S5LX88A9BW)`。
- `gh api repos/TigerVNC/tigervnc/releases`：v1.16.2 / v1.16.1 / v1.16.0 都是 0 个 asset。GitHub release 证明不了有 macOS 构建，所以不改读 GitHub。

结论：1.16.2 有正式的 macOS 构建，offer 1.16.0 是错的。JSON 里带 `sf_platform_default: ["mac"]` 的仍是 1.16.0 的 dmg；这个标记由项目在 SourceForge 文件属性里设置、TigerVNC 没把它挪到 1.16.2——这是推断，没查 SourceForge 文档。probe 改读 stable RSS，只认 `/stable/<v>/TigerVNC-<v>.dmg`，`selectHighest`，一键 URL 用 `.versionTemplate` 按比较胜出的版本拼。改完后用同一份 RSS 解析出 1.16.2。

