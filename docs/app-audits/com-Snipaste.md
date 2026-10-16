# Snipaste

截图 + 贴图工具，Qt 写的闭源跨平台 app（Windows / Mac / Linux 共用一份 changelog）。
菜单栏常驻（主 app 自己就是 `LSUIElement=1`，包里没有嵌套 helper app）。

## 基本信息
- Bundle ID: `com.Snipaste`
- Team ID: `NGTL73P583`（Developer ID Application: Le Liu）
- 观测版本: short `2.11.3`, build `2.11.3`（2026-10-16，下载的官方 dmg）
- 自更新机制: 自研（Qt，`UpdaterDialog`；设置里有「Include beta builds」和自动安装更新的选项）
- 开源: 否（`github.com/Snipaste/feedback` 只是 issue 跟踪与 wiki）
- 架构 / 系统下限: universal（x86_64 arm64），`LSMinimumSystemVersion` = `10.13`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗ `auto_updates` | — | — | ✓ 一键 |
| **beta**     | —       | —        | —   | —      | ○ 见 Channel 详情 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**

- Sparkle：包里没有 `SUFeedURL`，`feed-discover` 结论 `—`（无 Sparkle / electron-builder / MyGo）。
- Homebrew：cask `snipaste` 是 `auto_updates true`，`HomebrewCaskSource` 不应答。
- MAS：Mac 版不在 App Store（官网只链了 Windows 的 Microsoft Store 版）。
- GitHub：`Snipaste/feedback` 没有 release 资产。

## Coverage checklist

| 组 | 结论 | 依据 |
|---|---|---|
| 所有 bundle id | 只有 `com.Snipaste` | 实测：2.11.3、2.11.2、`2.9.2-Beta` dmg 与 v1 的 `Snipaste-Mac-1.16.2-Beta.tar.gz` 的 `Info.plist` 都是 `com.Snipaste` |
| v1（1.16.2 Beta for Mac） | 不单独处理 | 实测：`Info.plist` 没有 `CFBundleShortVersionString` / `CFBundleVersion`，`codesign` 报 `not signed at all`，x86_64 only。没有版本号可比，签名闸也过不了；扫描对它显示什么**未验证** |
| 下载页里的 `-Beta` dmg（2.3.5 … 2.9.2） | 视为 stable | 实测：`Snipaste-2.9.2-Beta.dmg` 里报 `2.9.2`，同 Team、已公证；changelog 里 `v2.9.2` 是普通条目。这些是 Mac 版整体还叫 Beta 时期的命名，不是另一条轨。这样的副本会被提示更新到 2.11.3，属于正确行为 |
| beta 轨（app 内「Include beta builds」） | ○ 未接 | 见 Channel 详情 |
| 版本范围 / Team | 一致 | 实测：2.9.2、2.11.2、2.11.3 都是 `NGTL73P583`，`spctl` 都是 `Notarized Developer ID` |
| 版本号形状 | 已覆盖 | changelog 里 111 个正式版本，有两段（`2.11`、`2.10`）也有三段；`Snipaste-2.11.dmg` 存在（200，36,635,400 bytes），模板对两段版本也成立 |

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.Snipaste` | — | — | `versions` JSON 的 `mac_version` | ✓ |
| beta    | `com.Snipaste` | 共享 | app 内偏好（2.11.3 Free 界面里没有这个开关，见下） | app 自己的 feed（地址未找到） | ○ |

- beta 是 Pattern B（同 id、偏好切换）。二进制里有 `cb_betaUpdate` / `Include beta builds`，但偏好键不是字面量
  （`Update/` 段下能看到 `force_feed`、`last_feed`、`last_upack`、`changelog` 等，没有 beta 相关的键），feed 地址
  也是运行时拼的（`https://%1`）。
- 真机（2026-10-16，2.11.3 Free，全新 `~/.snipaste`）：Preferences ▸ Update 页只有 “Check for updates on startup / Every 24 h”、代理设置和
  “Check for updates” / “Restore Defaults”，**没有** “Include beta builds”。二进制里有这个复选框（`cb_betaUpdate`、提示
  “Beta versions may contain more bugs.”），但这个构建不显示它；显示条件（Pro？beta 构建？）没查到。`config.ini` 只有
  `first_run`、`language` 两行。所以这个版本的用户无法打开 beta 轨，没有偏好可读。
- changelog 里最近一个不带平台限定的 beta 标题是 `v2.8.3 Beta2`（2022-12-25），之后只有
  `v2.8.8 Beta (Linux)`、`v2.8.9 Beta (Linux)`。也就是说当前没有比 stable 新的 Mac beta 在发（推断自 changelog，
  没有抓到 app 的 beta feed 来确认）。
- 打开 beta 开关的副本仍走 stable recipe：beta 号比 stable 高时判为已是最新，不会被往回推。

## 更新检测
- 源: `VendorProbeRecipe`（stable）
- 端点: `https://www.snipaste.com/versions`，官网下载页 `js/index.js` 用它填版本标签：

  ```json
  {"win_store_version":"2.11.3", "win_store_date":"2026.01.18","win_desktop_version":"2.11.3", "win_desktop_date":"2026.01.18","mac_version":"2.11.3", "mac_date":"2026.01.18","linux_version":"2.11.3", "linux_date":"2026.01.18"}
  ```
- 版本: `"mac_version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"`。`mac_version` 就是 `CFBundleShortVersionString`（与 `CFBundleVersion` 相同），
  不需要 `versionIsBuild`。数字后紧跟引号，`2.12-Beta` 这类带后缀的值读不出来。
- 发布日期: `mac_date` 是 `2026.01.18` 这种点分日期，`ReleaseDate` 不认，所以没设 `publishedAtPattern`。
- 读的是**人人可手动下载的 GA**：请求不带设备信息，答的就是下载页标的版本；`dl.snipaste.com/mac` 302 到同一个
  `archives/Snipaste-2.11.3.dmg`（cask 的 livecheck 也读这条 302）。
- 按 OS 分轨：应答里没有系统版本字段；包内 `LSMinimumSystemVersion` = `10.13`，低于我们的宿主下限。
- 按架构：dmg 是 universal，不分轨。
- app 自己的更新 feed 没有用：地址不在二进制里（见上），不知道它和 `versions` 是否同步。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 可能有（`upack`） | 没查 | 没查 |
| 证据 | 二进制字符串 `updatePackDownloadFinished()`、`upackDownloadFinished()`、`Update/last_upack`；没有 Sparkle、bsdiff 等字样 | app 的 feed 地址未知，没有拿到真实应答 | `DeltaApplier` 只吃 Sparkle / MyGo 格式，`upack` 是什么格式未知 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（用户点下载后） | 完整的 2.11.3 dmg（实测） | 不需要（见下） |
| 证据 | 2026-10-16 真机：默认配置下 2.11.2 运行 90 s、重启后 60 s 都没查更新；菜单栏菜单 “Check for updates...” → “New version available: 2.11.3” → “Download updates”（经系统代理约 5 分钟）→ 存到 `~/Downloads/Snipaste-Mac-2.11.3.dmg`（36,795,585 B，SHA-256 与厂商 2.11.3 dmg 相同），弹模态框 Cancel / Show in Finder / Install now | “Install now” 只是退出 app 并挂载这个 dmg（`/Volumes/Snipaste` 拖拽窗口），不替换 bundle | 一键自己下载厂商 dmg，不读它 |

## Changelog
- 来源: recipe，读 `https://docs.snipaste.com/wiki/Changelog.md`（docsify 站点，`/changelog` 是它的 alias，原文是 Markdown）
- 结构: 每版 `## v<版本>`，下一行 `> yyyy.MM.dd`，然后是 `*` 列表（有缩进的子项，一并收为条目）。beta 标题
  （`## v2.8.9 Beta (Linux)` 等）版本号后面还有字，不算条目，条目正文也不会越过下一个 `## `。
- 结构化: `recipe changelog:com.Snipaste:-: 20 entries; newest 2.11.3: 3 items, headings []; first items ["[PRO] Support customizing some in-app sh", "[PRO] Text extraction: support Tencent a", "Other improvements and bug fixes #3572 #"]`
- 全文实测: 134 个 `## ` 标题里 111 个匹配为条目，没匹配的 23 个全是 beta 标题；每个匹配条目都有日期行。
- 跟随 channel: 否（一份 changelog 覆盖所有平台；平台专属条目在正文里带 `[Mac]` / `[Linux]` 标记）
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（`.versionTemplate`，dmg）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：2.11.2 → 2.11.3，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg，`https://download.snipaste.com/archives/Snipaste-{version}.dmg`（universal，下载页标为 "Universal" 的那个文件，也是 cask 的 URL）
- 校验: `versions` 不带摘要。厂商另有 `dl.snipaste.com/sha-1.txt`，是 SHA-1，不支持，所以没接；只靠 Team ID 闸。
  2.11.3 dmg 实测 SHA-256 `a2287838889e7b1734a65d952bae5ef7f479bdc163d0c31be91859bca120fd3e`（36,795,585 bytes），与 cask 的 `sha256` 一致。
- **读的是**: 人人可手动下载的 GA
- Team ID: 上一版 2.11.2 与最新 2.11.3 都是 `NGTL73P583`，已公证；更早的 2.9.2 也一样。
- 嵌套 app / 常驻进程: 没有嵌套 `.app`；主 app 本身是菜单栏常驻（`LSUIElement=1`）。app 内的 `/Library/LaunchAgents/com.snipaste.plist`
  字符串是开机启动的路径，本次没确认它装的是什么（没有启动 app）。
- 阻塞: 无

## 已知问题
- app 自己的更新不会和一键互相覆盖：它的 “Install now” 只挂载 dmg 等用户拖拽（运行中一轮实测）。
- 它的 “已下载” 模态框开着时 app 拒绝退出（AppleScript `quit` 返回 -128 且进程不退），这时 `duo restart` 报 `still running — likely a save prompt, left it alone`，属于预期
- beta 轨没接，见 Channel 详情。

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：2.11.2 运行中、自带更新器已下载 2.11.3 dmg 且模态框开着，`duo install --yes` → `installed.` 并提示 `Still running the old code: Snipaste`；模态框开着时 `duo restart` 退不掉 app（见已知问题）；点 “Install now” 后 app 退出、只挂载 dmg，bundle inode 不变；启动 2.11.3 后 `duo restart` → `restarted`。Team `NGTL73P583`、`codesign --strict` 0、Notarized。新增只有 `~/.snipaste`，登录项前后无差异
2. beta：2.11.3 Free 界面里没有「Include beta builds」（2026-10-16 真机），暂无可接的偏好。等哪个版本把开关露出来（或确认 Pro 版有）再拨开关、读 `~/.snipaste/config.ini` 并抓更新请求。

## 如何复验

```bash
# 1. 端点
curl -sS https://www.snipaste.com/versions
curl -sS -I https://dl.snipaste.com/mac | grep -i '^location'

# 2. 生产检测 + changelog（上一版应 UPDATE，最新版应 up to date）
swift run --package-path application-test channel-verify Snipaste-2.11.2.dmg --expect stable
swift run --package-path application-test channel-verify Snipaste-2.11.3.dmg --expect stable

# 3. 签名
codesign -dvv Snipaste.app 2>&1 | grep -E 'TeamIdentifier|Authority=Developer'
spctl -a -vv -t exec Snipaste.app
```

2026-10-16 实测:
- `Snipaste-2.11.2.dmg`: `detected channel → stable`、`VendorProbe ✓ recipe answered for channel 'stable'`、`latest 2.11.3`、
  `download https://download.snipaste.com/archives/Snipaste-2.11.3.dmg`、`verdict UPDATE 2.11.2 → 2.11.3`；全链 `winning source Vendor`、`status UPDATE → 2.11.3`。
- `Snipaste-2.11.3.dmg`: 同上，`verdict up to date`、`status up to date`。
- 三个 dmg（2.9.2-Beta、2.11.2、2.11.3）: `com.Snipaste`、`TeamIdentifier=NGTL73P583`、`source=Notarized Developer ID`、`x86_64 arm64`。

## 历史与实测

### 2026-10-16 · 接入

- 二进制字符串里没有更新 feed 的字面地址，只有 `https://%1`、`Feed URL not set.`、`Update/force_feed` / `Update/last_feed`；
  改读官网下载页自己用的 `versions` JSON。
- 归档目录里不是每个版本都有 Mac dmg：`Snipaste-2.10.4.dmg`、`2.10.7`、`2.11.1` 回 520（16 bytes），`2.11`、`2.11.2`、`2.11.3` 回 200。
  这些版本在 changelog 里有，Mac 下载页没列；`mac_version` 只会写有 Mac 包的版本（推断，依据是下载页 Mac 列只链有包的版本）。
- `dl.snipaste.com/v1-mac` 302 到 `Snipaste-Mac-1.16.2-Beta.tar.gz`（11,345,715 bytes），解开后无版本键、未签名、x86_64 only。
