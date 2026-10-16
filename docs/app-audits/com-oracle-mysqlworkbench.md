# MySQL Workbench

Oracle 的 MySQL GUI。2026 年起有两个互不相同的 app：

- **MySQL Workbench 26.x**：基于 MySQL Shell 的 Electron 重写版，bundle id `com.oracle.mysqlworkbench`，
  app 名 `MySQL Workbench.app`，首个版本 26.7.0。
- **MySQL Workbench 8.0.x**：原生旧版，bundle id `com.oracle.workbench.MySQLWorkbench`，app 名
  `MySQLWorkbench.app`。官方手册摘要写的是 "versions 8.0 through 8.0.47"（2026-10-16 读
  `dev.mysql.com/doc/workbench/en/`）；当前下载页只剩 26.7.0，8.0.x 只在 archives。

bundle id、app 名、技术栈都不同。厂商自己把 8.0 用户指向 26：8.0 app 的 "Check for Updates" 读
`workbench.mysql.com/current-release`，该端点答 26.7.0。所以 8.0 副本按 `BundleIDMigration`（标为**重写版**）
归到 26.x 的 recipe 下：检测到 26.7.0，可一键更新，但必须先在确认面板里点「Update anyway」。

## 基本信息
- Bundle ID: `com.oracle.mysqlworkbench`（26.x）；`com.oracle.workbench.MySQLWorkbench`（8.0.x，迁移到前者）
- Team ID: `VB5E2TV963`（Oracle America, Inc.），26.7.0、8.0.47、8.0.46 三个真包都是，`spctl` 均为 Notarized Developer ID
- 观测版本: 26.x short `26.7.0` / build `26.7.0`；8.0.x short `8.0.47.CE` / build `1`（8.0.46 为 `8.0.46.CE` / `1`）
- 自更新机制: 26.x 无（Electron 自带 `Squirrel.framework`，但 `Resources/app/src/main.cjs` 不调用 `autoUpdater`，
  `src/` 下没有 update 相关代码）；8.0.x 只有手动 "Check for Updates"（`Resources/plugins/wb_utils_grt.py`，
  GET `http://workbench.mysql.com/current-release`，只弹框指向下载页，不下载）
- 开源: GPL-2.0（26.x `package.json` 的 `license`）；没有用到仓库，版本和下载都从厂商页面读

## 覆盖清单（Coverage checklist）

| 组 | 结论 |
|---|---|
| bundle id | 两个：`com.oracle.mysqlworkbench`（26.x，recipe 键）、`com.oracle.workbench.MySQLWorkbench`（8.0.x，`BundleIDMigration` 重写版条目，归到 26.x） |
| 发布轨 | 下载页只有 GA；26.x 没见 rc/beta 文件；8.0.x 的 "Not released" 版本（8.0.37/8.0.39）没有包 |
| 版本区间 | 26.x 只有 26.7.0 一个版本。8.0.46、8.0.47 同 Team；迁移的界是 `lastFromVersion` 8.0.47 / `firstToVersion` 26.7.0，`8.0.x.CE` 都在界内 |
| 架构 | 26.7.0 只发 arm64（`…-26.7.0-macos-x86_64.dmg` 404）；8.0.x 发 arm64 + x86_64。DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`），recipe 只读 arm64 |
| OS 下限 | 26.7.0 `LSMinimumSystemVersion` 12.0，8.0.47 为 13.0，都低于本项目的 15.0 部署目标，不加 `hostRequirement` |
| 嵌套 app | 26.x：只有 Electron 的四个 Helper（`Contents/Frameworks`）。8.0.x：`Contents/Resources/swb/MySQL Shell Workbench.app`（`com.oracle.MySQL-Shell-Workbench`，普通 GUI app，无 `LSUIElement` / `LSBackgroundOnly`，由 `libwbprivate.be.dylib` 按需启动，不是常驻 agent；启动行为未实测） |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **26.x stable** | — | — | — | — | ✓ 一键 |
| **8.0.x stable** | — | 见下 | — | — | ✓ 经迁移，提示后一键到 26.x |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: 两个 id 都是 **Vendor**（brew 装且由 brew 保持更新的副本另由 Homebrew 应答，
cask `mysqlworkbench` 2026-10-16 仍是 8.0.47）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（26.x） | `com.oracle.mysqlworkbench` | 独立 | bundle id | 下载页 macOS 标签 | ✓ |
| 8.0.x → 26.x | `com.oracle.workbench.MySQLWorkbench` | 独立 | bundle id + 版本界 | `BundleIDMigration`（`isRewrite`） | ✓ |

## 更新检测

### 26.x
- 源: `VendorProbeRecipe`，`Recipes/com-oracle-mysqlworkbench.swift`
- 端点: `https://dev.mysql.com/downloads/workbench/?os=33`（下载页的 macOS 标签）。表格每个包一行，文件名写在括号里：
  `(mysql-workbench-26.7.0-macos-arm64.dmg)`、`(mysql-workbench-26.7.0-macos-arm64.zip)`。
- 版本 pattern: `\(mysql-workbench-([0-9]+(?:\.[0-9]+)+)-macos-arm64\.dmg\)`。zip 行、带 `-rc` 之类后缀的文件名、
  8.0.x 的 `mysql-workbench-community-…` 都不匹配（单测覆盖）。读出的 `26.7.0` 等于 `CFBundleShortVersionString`。
- 为什么不用 `workbench.mysql.com/current-release`：只有版本号，不说明 macOS 包是否已上架；下载页同一份 body
  里同时有版本和 mac 文件名。
- WAF：用 curl 测时 `dev.mysql.com` / `downloads.mysql.com` 对浏览器 UA 和 `DuoUpdater/0.1` 都回 403
  "Technical Difficulties"，对 `curl/…` / `Python-urllib/…` 回 200。用 URLSession（生产路径用的栈）测，四种 UA
  （Safari 式、`DuoUpdater/0.1`、curl、Python-urllib）对下载页、archives、release notes、`current-release` 全部 200。
  拦截看的不只是 UA；recipe 不设 `requestHeaders`。
- 读的是**轨道最新**，同时也是下载页上人人可手动下载的 GA 构建（请求不带设备信息）。
- 按 OS 分轨：页面不给系统版本字段；包内下限见上表。

### 8.0.x：按重写版迁移到 26.x
- `BundleIDMigration(from: "com.oracle.workbench.MySQLWorkbench", to: "com.oracle.mysqlworkbench", teamID: "VB5E2TV963",
  lastFromVersion: "8.0.47", firstToVersion: "26.7.0", isRewrite: true)`。
- 效果（迁移表的四处读者照旧）：8.0 副本的 recipe 查 26.x 的 id；签名闸允许 26.x 包替换 8.0 副本（同 Team、已装版本低于
  26.7.0）；重启按两个 id 找进程；回滚按两个 id 找备份。
- `isRewrite` 是新增的标记（默认 false，其它迁移条目不变）：`UpdateResult.isVendorRewrite` 为真时 `isMajorUpgrade`
  恒为真，哪怕来源是 Vendor 这种 license-neutral 源。于是这一行走现有的确认路线：琥珀色「!」→ 面板 →「Update anyway」；
  菜单栏的 Update All 也照旧跳过它（`installAllTargets` 排除 `isMajorUpgrade`）。只提示，不阻止。
- 面板文字换成重写版专用（不讲 license）：
  - 标题 "Rewritten app"
  - "MySQLWorkbench 8.0.47.CE → 26.7.0 replaces this app with the vendor’s rewrite. Features and settings may differ from the version you have now."
  - "The new version replaces this copy. If “Keep a backup so updates can be rolled back” is on in Settings, you can roll back to the version you have now."
  - 依据代码：`VendorInstaller` 把新包装到已装副本的路径上（`installApp(newApp, over: result.app.path)`，路径名仍是
    `MySQLWorkbench.app`），备份只在设置开着时由 `InstallCoordinator.backUp` 保存；代码里没有移到废纸篓的步骤。
- 顺带解决了 `.CE` 假更新：8.0 副本现在和 26.7.0 比，`8.0.47.CE` < `26.7.0`。一个 8.0 版本对 8.0 版本的 probe
  不再需要，也没有加（若加，`8.0.47` 会读成比 `8.0.47.CE` 新，2026-10-16 在真包上实测过 `UPDATE 8.0.47.CE → 8.0.47`）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 26.x 不调用 `autoUpdater`；8.0.x 的检查只读 `fullversion`、打开下载页 | 下载页 / archives 每版只有整包 dmg / zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（未启动 app） | — |
| 证据 | 两个版本都没有会下载的更新器（见上） | — | — |

## Changelog
- 来源: 无。厂商 release notes（`dev.mysql.com/doc/relnotes/workbench/en/`，26.x app 内也链到这里）只到 8.0.47；
  `news-26-7-0.html` / `news-26-7.html` 均 404（2026-10-16）。
- 结构化: `channel-verify` 的 pane 行（26.7.0、8.0.47、8.0.46 三个真包相同）：
  `changelog pane  none — the pane says there are no release notes`
- 跟随 channel: —
- Recipe 状态: 需要，等厂商发布 26.x notes。8.0 的 notes 有页面，但 8.0 副本的 recipe 都按 26.x 的 id 查，
  而它们要更新到的是 26.x，8.0 notes 对这次更新没有意义，所以不加。

## 一键安装
- 状态: 支持（26.x → 26.x，以及 8.0.x → 26.x 经确认后）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：用户本机真实的 8.0.47.CE（`com.oracle.workbench.MySQLWorkbench`）→ 26.7.0（`com.oracle.mysqlworkbench`），跨 id 经迁移；装好的 DuoUpdater 里该行显示「Major update」/「⚠」，点开是「Rewritten app」面板。26.x → 26.x 只有 26.7.0 一个版本，未做，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg（UDBZ，无 SLA）
- 校验: 页面只公布 MD5（26.7.0 dmg `bb0f5e5bcba12d4add0a35957ce47355`，与下载的 315,593,422 字节一致），
  `checksumFormat` 不支持 MD5，不接；只靠 Team-ID 闸
- **读的是**: 轨道最新 = 下载页人人可手动下载的 GA 构建
- 下载 URL: `.versionTemplate("https://cdn.mysql.com/Downloads/MySQLGUITools/mysql-workbench-{version}-macos-arm64.dmg")`，
  即下载页按钮最终落到的 CDN 路径；curl HEAD 用 `DuoUpdater/0.1` 与 Safari 式 UA 都是 200、`content-length` 315593422
- 阻塞: 无

## 已知问题
- 8.0 → 26 是重写：26 的用户数据目录与 8.0 的 `~/Library/Application Support/MySQL/Workbench`（cask 的 zap 列表）
  是否相通未核实；面板只说 "may differ"。
- 新包装在原路径上，所以 26.x 会住在 `MySQLWorkbench.app`（不是厂商 dmg 里的 `MySQL Workbench.app`）。
- duo CLI 没有这道确认：`duo install` 列出 `8.0.47.CE → 26.7.0` 后只问通用的 `Install N update(s)? [y/N]`（或 `--yes`），
  不显示重写版说明（CLI 里没有读 `isMajorUpgrade` 的地方）。
- 当前下载页只列一个版本。厂商下一版发布后 26.7.0 会移到 archives；recipe 只用最新版本拼 URL，不受影响。

## 建议下一步
1. 厂商发布 26.x release notes 后补 `ChangelogRecipe`；26.x 出第二个版本后用 26.7.0 真包跑一次 `channel-verify`。
2. 若需要，在 duo CLI 的安装计划里对 `isVendorRewrite` 的行加一句说明（逻辑已在 Core）。

## 如何复验

```bash
# 1. 端点（URLSession 与 curl 结果不同，见「更新检测」；用 curl 时带 -A curl/8.7.1）
curl -sS -A curl/8.7.1 "https://dev.mysql.com/downloads/workbench/?os=33" | grep -oE '\(mysql-workbench-[^)]*\)'
curl -sS -A curl/8.7.1 "https://workbench.mysql.com/current-release"

# 2. 生产检测（dmg 可直接给 channel-verify）
swift run --package-path application-test channel-verify <mysql-workbench-26.7.0-macos-arm64.dmg> --expect stable
swift run --package-path application-test channel-verify <mysql-workbench-community-8.0.47-macos-arm64.dmg> --expect stable
```

2026-10-16 实测（迁移条目加入后）:
- 26.7.0 真包: `VendorProbe ✓ recipe answered for channel 'stable'`、`latest 26.7.0`、`verdict up to date`；全链
  `winning source Vendor`、`status up to date`。
- 8.0.47 真包（`bundle id com.oracle.workbench.MySQLWorkbench`、`short version 8.0.47.CE`）: `VendorProbe ✓`、
  `latest 26.7.0`、`verdict UPDATE 8.0.47.CE → 26.7.0`、`winning source Vendor`、`status UPDATE → 26.7.0`。
- 8.0.46 真包: `verdict UPDATE 8.0.46.CE → 26.7.0`、`winning source Vendor`、`status UPDATE → 26.7.0`。
- 签名：三个真包 `TeamIdentifier=VB5E2TV963`，`spctl -a -vv -t exec` 均 `accepted / Notarized Developer ID`；26.7.0 主程序 `lipo -archs` = `arm64`。
- 面板：`RowStateGallery` 第 52 例（`verify/row-states/popover/52-vendor-rewrite-explanation.png`）。

## 历史与实测

### 2026-10-16 · 接入
- Homebrew cask `mysqlworkbench` 当天仍指向 8.0.47（`mysql-workbench-community-8.0.47-macos-arm64.dmg`，`auto_updates` 未设），
  而厂商下载页已换成 26.7.0：文件名去掉了 `community-`，app 名从 `MySQLWorkbench.app` 变成 `MySQL Workbench.app`，
  bundle id 从 `com.oracle.workbench.MySQLWorkbench` 变成 `com.oracle.mysqlworkbench`，技术栈换成 Electron。
- `workbench.mysql.com/current-release` 答 `{"fullversion": "26.7.0", "major": "26", "minor": "7", "release": "0"}`。
- 下载页 MD5：dmg `bb0f5e5bcba12d4add0a35957ce47355`、zip `5b6fc29f8673f27d73e16933eecefbca`；dmg 下载后 `md5` 相同，
  SHA-256 `063cd888335ba81343092f9fe6568c786f02aa9e82fb1752688738d534fb2004`。archives 页 8.0.46 arm64 dmg MD5
  `fe78c465033af4910d5afe0d963528cc`、8.0.47 arm64 dmg MD5 `dea79af28c98e73b556c0a0640b7e768`，下载核对一致
  （345,230,923 / 348,844,474 字节）。
- 第一版只接了 26.x 和一条 8.0 changelog recipe。试过一条读 archives 的 8.0 probe：8.0.47 真包上
  `verdict UPDATE 8.0.47.CE → 8.0.47`（`.CE` 后缀造成的假更新），撤回。
- 同日改为迁移：8.0 → 26 的 `BundleIDMigration`，标 `isRewrite`，确认后一键。迁移的界取自真包：最新的 8.0 是
  8.0.47（archives 默认选中，`CFBundleShortVersionString` `8.0.47.CE`），最早的 26.x 是 26.7.0（当前唯一版本）。
  8.0 changelog recipe 随之删除（8.0 id 不再被任何 recipe 作键，迁移表测试要求如此）。
