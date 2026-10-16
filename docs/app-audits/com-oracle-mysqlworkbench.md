# MySQL Workbench

Oracle 的 MySQL GUI。2026 年起有两个互不相同的 app：

- **MySQL Workbench 26.x**：基于 MySQL Shell 的 Electron 重写版，bundle id `com.oracle.mysqlworkbench`，
  app 名 `MySQL Workbench.app`，首个版本 26.7.0。
- **MySQL Workbench 8.0.x**：原生旧版，bundle id `com.oracle.workbench.MySQLWorkbench`，app 名
  `MySQLWorkbench.app`。官方手册摘要写的是 "versions 8.0 through 8.0.47"（2026-10-16 读
  `dev.mysql.com/doc/workbench/en/`）；当前下载页只剩 26.7.0，8.0.x 只在 archives。

两者 bundle id、app 名、技术栈都不同，是 Pattern A 意义上的两个 app，不是一个 app 的两条轨。

## 基本信息
- Bundle ID: `com.oracle.mysqlworkbench`（26.x）；`com.oracle.workbench.MySQLWorkbench`（8.0.x）
- Team ID: `VB5E2TV963`（Oracle America, Inc.），26.7.0、8.0.47、8.0.46 三个真包都是，`spctl` 均为 Notarized Developer ID
- 观测版本: 26.x short `26.7.0` / build `26.7.0`；8.0.x short `8.0.47.CE` / build `1`（8.0.46 为 `8.0.46.CE` / `1`）
- 自更新机制: 26.x 无（Electron 自带 `Squirrel.framework`，但 `Resources/app/src/main.cjs` 不调用 `autoUpdater`，
  `src/` 下没有 update 相关代码）；8.0.x 只有手动 "Check for Updates"（`Resources/plugins/wb_utils_grt.py`，
  GET `http://workbench.mysql.com/current-release`，只弹框指向下载页，不下载）
- 开源: GPL-2.0（26.x `package.json` 的 `license`）；没有用到仓库，版本和下载都从厂商页面读

## 覆盖清单（Coverage checklist）

| 组 | 结论 |
|---|---|
| bundle id | 两个：`com.oracle.mysqlworkbench`（26.x，已接）、`com.oracle.workbench.MySQLWorkbench`（8.0.x，**只接 changelog，检测缺口见下**） |
| 发布轨 | 下载页只有 GA；26.x 没见 rc/beta 文件；8.0.x 的 "Not released" 版本（8.0.37/8.0.39）没有包 |
| 版本区间 | 26.x 只有 26.7.0 一个版本。8.0.46 → 8.0.47 Team、bundle id 不变 |
| 架构 | 26.7.0 只发 arm64（`…-26.7.0-macos-x86_64.dmg` 404）；8.0.x 发 arm64 + x86_64。DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`），recipe 只读 arm64 |
| OS 下限 | 26.7.0 `LSMinimumSystemVersion` 12.0，8.0.47 为 13.0，都低于本项目的 15.0 部署目标，不加 `hostRequirement` |
| 嵌套 app | 26.x：只有 Electron 的四个 Helper（`Contents/Frameworks`）。8.0.x：`Contents/Resources/swb/MySQL Shell Workbench.app`（`com.oracle.MySQL-Shell-Workbench`，普通 GUI app，无 `LSUIElement` / `LSBackgroundOnly`，由 `libwbprivate.be.dylib` 按需启动，不是常驻 agent） |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **26.x stable** | — | — | — | — | ✓ 一键 |
| **8.0.x stable** | — | ○（cask `mysqlworkbench` 2026-10-16 仍是 8.0.47） | — | — | ○ 被 `.CE` 后缀挡住 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: 26.x **Vendor**；8.0.x 非 brew 安装的副本 **无**（unknown）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（26.x） | `com.oracle.mysqlworkbench` | 独立 | bundle id | 下载页 macOS 标签 | ✓ |
| stable（8.0.x） | `com.oracle.workbench.MySQLWorkbench` | 独立 | bundle id | archives macOS 标签 | ○ |

## 更新检测

### 26.x（已接）
- 源: `VendorProbeRecipe`，`Recipes/com-oracle-mysqlworkbench.swift`
- 端点: `https://dev.mysql.com/downloads/workbench/?os=33`（下载页的 macOS 标签）。表格每个包一行，文件名写在括号里：
  `(mysql-workbench-26.7.0-macos-arm64.dmg)`、`(mysql-workbench-26.7.0-macos-arm64.zip)`。
- 版本 pattern: `\(mysql-workbench-([0-9]+(?:\.[0-9]+)+)-macos-arm64\.dmg\)`。zip 行、带 `-rc` 之类后缀的文件名、
  8.0.x 的 `mysql-workbench-community-…` 都不匹配（单测覆盖）。读出的 `26.7.0` 等于 `CFBundleShortVersionString`。
- 为什么不用 `workbench.mysql.com/current-release`：那是 8.0 app 自己的检查端点，现在答 `{"fullversion": "26.7.0", …}`，
  只有版本号，不说明 macOS 包是否已上架；下载页同一份 body 里同时有版本和 mac 文件名。
- WAF：用 curl 测时 `dev.mysql.com` / `downloads.mysql.com` 对浏览器 UA 和 `DuoUpdater/0.1` 都回 403
  "Technical Difficulties"，对 `curl/…` / `Python-urllib/…` 回 200。用 URLSession（生产路径用的栈）测，四种 UA
  （Safari 式、`DuoUpdater/0.1`、curl、Python-urllib）对下载页、archives、release notes、`current-release` 全部 200。
  拦截看的不只是 UA；recipe 不设 `requestHeaders`。
- 读的是**轨道最新**，同时也是下载页上人人可手动下载的 GA 构建（请求不带设备信息）。
- 按 OS 分轨：页面不给系统版本字段；包内下限见上表。

### 8.0.x（缺口）
- 可用端点（实测可读）：`https://downloads.mysql.com/archives/workbench/?os=33`，默认选中最新的 8.0.47，行内文件名
  `(mysql-workbench-community-8.0.47-macos-arm64.dmg)`，下载链接 `/archives/get/p/8/file/…` 302 到
  `https://cdn.mysql.com/archives/mysql-workbench/mysql-workbench-community-<v>-macos-arm64.dmg`。
- **为什么没接**：bundle 的 `CFBundleShortVersionString` 是 `8.0.47.CE`，厂商所有页面写 `8.0.47`。
  `VersionComparator` 里数字段胜过文本段，`8.0.47` 读成比 `8.0.47.CE` 新，于是每个已是最新的副本都会被推送它自己。
  试接后在真包上实测（2026-10-16）：8.0.47 → `verdict UPDATE 8.0.47.CE → 8.0.47`（假更新），8.0.46 →
  `verdict UPDATE 8.0.46.CE → 8.0.47`（正确）。页面上没有大写 `CE` 可供第二个捕获组拼回去，`.versionTemplate` 也会把
  拼上的后缀带进下载 URL。recipe 层没有干净的写法，所以撤掉了这条 probe。
- 详见「建议下一步」。

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
- 26.x: **无**。厂商 release notes（`dev.mysql.com/doc/relnotes/workbench/en/`，26.x app 内也链到这里）只到 8.0.47；
  `news-26-7-0.html` / `news-26-7.html` 均 404（2026-10-16）。`channel-verify` 的 pane 行：
  `changelog pane  none — the pane says there are no release notes`。厂商发了 26.x notes 后再加 recipe。
- 8.0.x: recipe，读 `news-8-0.html`（索引，newest first）→ 第一个 `news-8-0-<n>.html` → 解析该页。
  `channel-verify` 的 pane 行（8.0.46 真包）：
  `recipe changelog:com.oracle.workbench.MySQLWorkbench:-: 1 entries; newest 8.0.47: 4 items, headings ["Functionality Added or Changed"]; first items ["The bundled LIBPNG library has been upda", "The bundled OpenSSL library has been upd", "MySQL HeatWave Migration Assistant now s"]`。
  只取最新一版（`maxEntries: 1`，与 pgAdmin 同型）。没有 `<li>` 的版本（8.0.46 "This release contains no functional
  changes."）以段落为条目。这条 recipe 目前只在有别的源应答时（brew 装的副本）才有用。
- 跟随 channel: 否（两个 app 各自独立）

## 一键安装
- 状态: 26.x **支持**；8.0.x 无（没有检测）
- 端到端: 真机端到端：待主会话执行。26.x 目前只有 26.7.0 一个版本，没有真实的上一版可装，old→new 只能等 26.x 下一版
- 格式: dmg（UDBZ，无 SLA）
- 校验: 页面只公布 MD5（26.7.0 dmg `bb0f5e5bcba12d4add0a35957ce47355`，与下载的 315,593,422 字节一致），
  `checksumFormat` 不支持 MD5，不接；只靠 Team-ID 闸
- **读的是**: 轨道最新 = 下载页人人可手动下载的 GA 构建
- 下载 URL: `.versionTemplate("https://cdn.mysql.com/Downloads/MySQLGUITools/mysql-workbench-{version}-macos-arm64.dmg")`，
  即下载页按钮最终落到的 CDN 路径；curl HEAD 用 `DuoUpdater/0.1` 与 Safari 式 UA 都是 200、`content-length` 315593422
- 阻塞: 无（26.x）

## 已知问题
- 8.0.x 非 brew 安装的副本显示 unknown（见「更新检测 · 8.0.x」）。
- 8.0.x 自带的 "Check for Updates" 现在会告诉用户 26.7.0 已发布；我们不跨 bundle id 推送 26.x（见「建议下一步」2）。
- 当前下载页只列一个版本。厂商下一版发布后 26.7.0 会移到 archives；recipe 只用最新版本拼 URL，不受影响。

## 建议下一步
1. **8.0.x 检测**需要一个决定（不在本次范围内擅自加）：
   - 方案 A：`VendorProbeRecipe` 新增一个字段，把厂商版本补成 bundle 的写法（如固定后缀 `.CE`），比较用补全后的串、
     下载 URL 仍用原始版本。改动会让所有 family 的 golden 多一行。
   - 方案 B：比较时忽略已装版本末尾的纯字母段——全局语义变化（`1.0` vs `1.0beta` 依赖现有规则），不建议。
   接上后用 8.0.46 → 8.0.47 跑一键（同 Team、同 bundle id、已公证，URL 见上）。
2. **8.0 → 26 迁移**：`BundleIDMigration` 能让 8.0 副本按 26.x 的 recipe 检查和安装，厂商自己的检查也指向 26.7.0。
   但 26 是功能未齐的重写版（自称并非所有 8.0 功能都已提供——这句出自 Oracle 博客的搜索摘要，博客直连 403，**未直接核实**），
   用户数据目录也不同，原地替换是产品决定，需用户拍板。
3. 厂商发布 26.x release notes 后补 26.x 的 `ChangelogRecipe`；26.x 出第二个版本后用 26.7.0 真包跑一次
   `channel-verify`，确认 `UPDATE 26.7.0 → …`。

## 如何复验

```bash
# 1. 端点（URLSession 与 curl 结果不同，见「更新检测」；用 curl 时带 -A curl/8.7.1）
curl -sS -A curl/8.7.1 "https://dev.mysql.com/downloads/workbench/?os=33" | grep -oE '\(mysql-workbench-[^)]*\)'
curl -sS -A curl/8.7.1 "https://downloads.mysql.com/archives/workbench/?os=33" | grep -oE '\(mysql-workbench-[^)]*\)'

# 2. 生产检测 + changelog（dmg 可直接给 channel-verify）
swift run --package-path application-test channel-verify <mysql-workbench-26.7.0-macos-arm64.dmg> --expect stable
swift run --package-path application-test channel-verify <mysql-workbench-community-8.0.46-macos-arm64.dmg> --expect stable
```

2026-10-16 实测:
- 26.7.0 真包（`https://cdn.mysql.com/Downloads/MySQLGUITools/mysql-workbench-26.7.0-macos-arm64.dmg`）:
  `detected channel → stable`、`VendorProbe ✓ recipe answered for channel 'stable'`、`latest 26.7.0`、`verdict up to date`；
  全链 `winning source Vendor`、`status up to date`。
- 只含 26.7.0 `Info.plist`、两个版本号改成 `26.6.0` 的骨架 bundle: `verdict UPDATE 26.6.0 → 26.7.0`、`winning source Vendor`。
- 8.0.46 真包（本次提交后）: `VendorProbe — no recipe registered`、`status unknown (no source answered)`，changelog pane 见上。
- 签名：三个真包 `TeamIdentifier=VB5E2TV963`，`spctl -a -vv -t exec` 均 `accepted / Notarized Developer ID`；26.7.0 主程序 `lipo -archs` = `arm64`。

## 历史与实测

### 2026-10-16 · 接入
- Homebrew cask `mysqlworkbench` 当天仍指向 8.0.47（`mysql-workbench-community-8.0.47-macos-arm64.dmg`，`auto_updates` 未设），
  而厂商下载页已换成 26.7.0：文件名去掉了 `community-`，app 名从 `MySQLWorkbench.app` 变成 `MySQL Workbench.app`，
  bundle id 从 `com.oracle.workbench.MySQLWorkbench` 变成 `com.oracle.mysqlworkbench`，技术栈换成 Electron。
- `workbench.mysql.com/current-release` 答 `{"fullversion": "26.7.0", "major": "26", "minor": "7", "release": "0"}`。
- 下载页 MD5：dmg `bb0f5e5bcba12d4add0a35957ce47355`、zip `5b6fc29f8673f27d73e16933eecefbca`；dmg 下载后 `md5` 相同，
  SHA-256 `063cd888335ba81343092f9fe6568c786f02aa9e82fb1752688738d534fb2004`。archives 页 8.0.46 arm64 dmg MD5
  `fe78c465033af4910d5afe0d963528cc`，下载核对一致（345,230,923 字节）；8.0.47 arm64 dmg 348,844,474 字节。
- 8.0.x probe 试接、在真包上看到假更新后撤回，过程见「更新检测 · 8.0.x」。
