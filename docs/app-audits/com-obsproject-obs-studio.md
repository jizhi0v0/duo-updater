# OBS

## 基本信息
- Bundle ID: `com.obsproject.obs-studio`
- Team ID: `2MMRE5MTB8`（Wizards of OBS LLC；32.2.1、32.2.2、33.0.0-beta5、33.0.0-beta6 四个真包一致）
- 观测版本: 32.2.2（`CFBundleVersion` 31845296735），2026-10-08
- 自更新机制: Sparkle 2.9.2（`SUFeedURL` 按架构：`https://obsproject.com/osx_update/updates_arm64_v2.xml` / `updates_x86_64_v2.xml`）
- 开源: `obsproject/obs-studio`，渠道机制从源码读出（见下）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓ 一键  | ✗ (`auto_updates`) | — | — | — |
| **beta**     | ✓（`OBSChannel` 绑定） | — | — | — | — |

当前生效源（`UpdateChecker` 按 `SourceStack.make` 顺序第一个应答的）: **Sparkle**。

## Channel 详情

settled from source: `frontend/utility/MacUpdateThread.cpp`、`frontend/utility/OBSUpdateDelegate.mm`、`frontend/widgets/OBSBasic.cpp`（default branch，2026-10-08）。

- OBS 的 `SPUUpdaterDelegate.allowedChannelsForUpdater` 只返回 **一个** 渠道名：`[NSSet setWithObject:branch]`。
- `branch` 取自 `global.ini` 的 `[General] UpdateBranch`；没有这个键时是 `"stable"`。分支名要先出现在 `https://obsproject.com/update_studio/branches.json` 里并且 `enabled`，否则静默回落到 stable（2026-10-08 只列了 `beta`，`"macos": true`）。
- **预发布版第一次运行时自己写 `UpdateBranch=beta`** 和 `AutoBetaOptIn=true`（`OBS_RELEASE_CANDIDATE > 0 || OBS_BETA > 0` 的编译分支）。之后再装回正式版，这个键还在。设置 → 常规里的「更新通道」下拉框写的也是这个键。
- 文件: `~/Library/Application Support/obs-studio/global.ini`（INI，`[General]` 节）。

真实 app 上的写入（2026-10-08）：

| 操作 | `global.ini` `[General]` |
|---|---|
| 正式版 32.2.1 首次运行 | 没有 `UpdateBranch`、没有 `AutoBetaOptIn` |
| 33.0.0-beta6 首次运行 | `UpdateBranch=beta`、`AutoBetaOptIn=true` |

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.obsproject.obs-studio` | 共享 | 已装 build 命中 feed 里 `<sparkle:channel>stable` 的条目 | channel tag | ✓ |
| beta    | 同上 | 共享 | `global.ini` `UpdateBranch=beta`（`OBSChannel`）；没有这个键时靠已装 build 命中 `beta` 条目 | channel tag | ✓ |

`OBSChannel` 的映射（2026-10-08 起）：

| `UpdateBranch` | 解析结果 | 放行的 `<sparkle:channel>` |
|---|---|---|
| `beta` | `.beta`（权威） | 无标签 + `beta`；**不放行 `stable`**，和 OBS 自己的 `allowedChannelsForUpdater` 一致 |
| `stable` | `.stable`（权威） | 无标签 + `stable`；必须显式写出标签，否则只剩 2023 年的 29.0.2 |
| 没有这个键、文件不存在、其他值 | nil（不权威） | 交回已装 build 推断：正式版 → `stable`，beta 包 → `beta`。还没启动过的 beta 包没有 `global.ini`，如果答 stable 会把它钉死在 stable |

**beta 用户不推正式版，依据**：OBS 源码 `allowedChannelsForUpdater` 只返回一个渠道名；Sparkle 文档 [Publishing an update](https://sparkle-project.org/documentation/publishing/) 写明更新器只看默认渠道加被允许的渠道，「不能把自己排除在默认渠道之外」。OBS 的正式版都打了 `stable` 标签，不在默认渠道里。这一条**没有实测**：现在 beta 轨（33.0.0-beta6）比所有正式版都新，造不出「正式版比 beta 新」的场景。

不监听 `global.ini`：同目录有 OBS 运行时持续写的 `logs/` 和场景文件，FSEvents 是递归的。切换开关后，下一次扫描或 OBS 启动/退出时生效，做法和 super.engineering、Cindy 一样。设置页「更新通道」下拉框写 `UpdateBranch=<分支名>`，`stable` 是内置选项；这是从源码 `OBSBasicSettings.cpp` 读出来的。在真实 app 设置里拨开关这一步没做：启动 OBS 时会弹系统级的摄像头扩展授权框。

**版本号陷阱（同 Mozilla）**: beta 包把后缀去掉了。33.0.0-beta5、beta6 的 `CFBundleShortVersionString` 都是 `33.0.0`；feed 里 beta 条目的 `shortVersionString` 也是 `33.0.0`。两个包只能靠 `CFBundleVersion` / `sparkle:version` 区分（GitHub Actions 的 run id，单调递增：beta5 `36792081772`，beta6 `37074854565`）。版本字符串推不出渠道。

## 更新检测
- 源: `SparkleAppcastSource`（通用，无 per-app 代码）
- 端点: `https://obsproject.com/osx_update/updates_arm64_v2.xml`（2026-10-08: 71 个 item，`stable` 31 / `beta` 39 / 无标签 1）
- **feed 几乎全打了标签**: 唯一没标签的是 2023 年的 `OBS Studio 29.0.2`（还是 DSA 签名）。所以 `feed-discover` 判 `declared`，而不是 `NEEDS BINDING`；stable 能用并不是靠这条无标签条目，而是靠「已装 build 命中 `stable` 条目 → 放行 `stable` 标签」的推断。如果已装 build 被裁出了 feed，就会只剩 29.0.2 可比，结果是一直「已是最新」。2026-10-08 feed 里最老的 stable 是哪一版没核对。
- **正式版从不发到 beta 渠道**: 两个渠道的 `sparkle:version` 没有交集。OBS 自己的更新器对 beta 用户只放行 `beta` 标签，所以 32.2.0-rc2 的用户收不到 32.2.0 正式版和 32.2.1、32.2.2 的热修，要等到下一个 beta。duo 推断出来的范围（`{无标签, beta}`）和它一致。
- 分阶段推送: stable 条目带 `<sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>`（beta 没有）。`DuoUpdaterCore` 里没有任何地方读这个字段（2026-10-08 grep `phasedRollout` 零命中），所以 duo 在发布当天就推给所有人。
- OS 下限: feed 每条带 `sparkle:minimumSystemVersion`（32.2.x 为 13.0）；32.2.1 包内 `LSMinimumSystemVersion` 是 12.0，32.2.2 是 13.0（32.2.2 说明：Qt 升级后不再支持 macOS 12）。`SparkleAppcastSource` 按 feed 的下限过滤。
- 架构: 每条带 `<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>`（arm64 feed）。Intel 包和 x86_64 feed **没验**。OBS 自己在 Rosetta 下运行 Intel 包时会把 feed 换成 arm64（`OBSSparkle.mm` 的 `os_get_emulation_status()`），duo 只读包内的 `SUFeedURL`，那种情况下会继续给 Intel 包。这只是从源码读出来的，没测过。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（已在用） |
| 证据 | 包内 `Sparkle.framework` 2.9.2 | 2026-10-08 arm64 feed：每个 stable/beta 条目带 5 个 `<sparkle:deltas>`，例如 `OBS31845296735-30131037208.delta`（613602 字节） | `duo install` 32.2.1→32.2.2 输出 `bytesDownloaded: 613602`，就是这个 delta |

- 格式: Sparkle binary delta
- 阻塞项: 无

## Changelog
- 来源: Sparkle `releaseNotesLink`，按渠道分页：`https://obsproject.com/osx_update/notes_stable.html`、`notes_beta.html`；feed 里没有 inline `<description>`
- 接 recipe 之前: `changelog pane  web page https://obsproject.com/osx_update/notes_stable.html, no structure`（beta 拷贝显示 `notes_beta.html`，同样 no structure）
- 页面本身结构很干净：`<h1 id="obs-studio-32.2.2">`，每个热修和功能块是一个 `<h2>` + `<ul>`，2026-10-08 为 4426 字节。但它只覆盖当前这个小版本系列，不是每版一条的历史。GitHub release 正文是每版一条的 Markdown。
- 跟随 channel: 是（stable / beta 两张页）
- Recipe 状态: **已有**（`Recipes/com-obsproject-obs-studio.swift`，`feedPagePattern`：页面就是 feed 为这个拷贝解析出来的那张，自然跟渠道走）
- 结构化（2026-10-08，`channel-verify` 原文）:
  - stable: `recipe changelog:com.obsproject.obs-studio:-: 1 entries; newest 32.2.2: 49 items, headings ["32.2.2 Hotfix Changes", "32.2.1 Hotfix Changes", "32.2 New Features", "32.2 Changes", "32.2 Bug Fixes", "32.2 Deprecations"]`，前两条是 `<p>Important: …</p>` 提示
  - beta: `recipe changelog:com.obsproject.obs-studio:-: 1 entries; newest 33.0.0: 76 items, headings ["Beta 6 Changes", …, "33.0 Developer Information"]`
- 只有一条：页面是整个小版本系列合在一起的，没有每版一条的历史

## 一键安装
- 状态: 支持（stable，走 Sparkle 通用路径）
- 端到端（2026-10-08，arm64）:
  - **第一轮，未运行**: 32.2.1 → `duo install OBS --yes --json` → `outcome: installed`，`route: sparkle`，下载 613602 字节（delta），8 s。之后 `CFBundleShortVersionString` 32.2.2 / `CFBundleVersion` 31845296735，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `2MMRE5MTB8`。和厂商 32.2.2 dmg 里的 `OBS.app` 逐文件比对（SHA-256 + 符号链接目标 + 目录，2574 行）完全一致。`duo backups` 里有 32.2.1 的备份。
  - **第二轮，运行中**: 32.2.1 运行着 → `duo install` 同样 `installed`（delta，11 s）→ `duo restart OBS` 输出 `restarted`。新进程日志第一行是 `OBS 32.2.2 (mac)`，之后 12 s 内磁盘版本一直是 32.2.2，没有被回滚。OBS 的 Info.plist 没有 `SUAutomaticallyUpdate`，它自己的 Sparkle 默认不会在后台静默暂存，所以这一轮没有造出自更新器冲突的场景。
- 格式: dmg（Sparkle enclosure，EdDSA 签名，`SUPublicEDKey` 在包内）
- 校验: Sparkle 路径用 EdDSA。GitHub release 资产的 `digest`（`sha256:920d6f26…aaf7`）和下载到的 32.2.2 dmg 的 SHA-256 一致，但一键不走 GitHub，所以只是旁证。
- **读的是**: 轨道最新（忽略 `phasedRolloutInterval`）。可以接受的理由：同一个 dmg 在发布当时就作为 GitHub release 资产公开，obsproject.com 下载页也提供，用户手动就能下到；灰度只是 OBS 自己更新器的节奏，不是这个构建不给某些机器用。
- 阻塞: 无。beta 走同一条 Sparkle 路径（同 Team、同 EdDSA key），一键没有单独跑端到端。

## 已知问题
- **首次启动的模态权限窗口挡住退出**: 没给任何权限时，OBS 每次启动都先弹「Review App Permissions」。这个窗口开着的时候，AppleScript `quit` 返回 `User canceled (-128)`，SIGTERM 也要等窗口关掉才生效，`duo restart` 只能报 `still running — likely a save prompt, left it alone`。这是 OBS 的行为，duo 没做错。
- **虚拟摄像头系统扩展**: 包内带 `Contents/Library/SystemExtensions/com.obsproject.obs-studio.mac-camera-extension.systemextension`。OBS 启动时自己比对版本并请求替换（日志：`mac-camera-extension: Replacement requested. Existing version: 32.2.1 …, new version: 32.2.2 …`），duo 换包不需要碰它。还没批准时，它一直停在 `activated waiting for user`。
- beta 用户显示的版本号是 `33.0.0 → 33.0.0`（后缀被去掉了），用户分不出是 beta5 还是 beta6。

## 如何复验

```bash
# 真包身份（arm64）
gh release download 32.2.2 -R obsproject/obs-studio -p 'OBS-Studio-32.2.2-macOS-Apple.dmg'
swift run --package-path application-test feed-discover OBS-Studio-32.2.1-macOS-Apple.dmg
swift run --package-path application-test channel-verify OBS-Studio-32.2.1-macOS-Apple.dmg
```

2026-10-08 结果：

| 包 | short / build | detected channel | winning source | status |
|---|---|---|---|---|
| 32.2.1 | 32.2.1 / 30131037208 | stable | Sparkle | `UPDATE → 32.2.2`，5 deltas，release history 32 条 |
| 33.0.0-beta5 | 33.0.0 / 36792081772 | stable（推断）；Sparkle 按 build 命中 `beta` | Sparkle | `UPDATE → 33.0.0`（beta6 的 dmg） |
| 33.0.0-beta6 | 33.0.0 / 37074854565 | stable（推断）；命中 `beta` | Sparkle | `up to date`，release history 40 条 |
| 32.2.2 + `UpdateBranch=beta`（接绑定前） | 32.2.2 / 31845296735 | stable | Sparkle | **`up to date`**。OBS 自己会推 33.0.0-beta6，这就是当时的 beta 缺口 |

接 `OBSChannel` 之后，同一个 32.2.2 拷贝（2026-10-08，`channel-verify /Applications/OBS.app`）：

| `global.ini` | ChannelBinding | detected channel | status |
|---|---|---|---|
| `UpdateBranch=beta` | `beta — read from this app's own preference` | beta | `UPDATE → 33.0.0`（beta6 的 dmg） |
| `UpdateBranch=stable` | `stable — read from this app's own preference` | stable | `up to date` |
| 无文件 | `<none for this app>` | stable | `up to date` |

`feed-discover` 对 32.2.1 的判定：`declared https://obsproject.com/osx_update/updates_arm64_v2.xml`。

## 建议下一步
1. Intel：拿 `OBS-Studio-<v>-macOS-Intel.dmg` 和 `updates_x86_64_v2.xml` 重跑一遍上面的表。
2. 如果哪天 OBS 让 beta 用户也看到正式版（`allowedChannelsForUpdater` 返回多个名字），`OBSChannel` 的 beta 分支跟着加上 `stable`；`OBSChannelTests.aBetaUserIsNotOfferedAStableRelease` 会提醒。

## 历史与实测

- 2026-10-08 两张说明页（stable 4426 字节、beta 6916 字节）：stable 1 个 `<h1>`、6 个 `<h2>`、47 个 `<li>`、2 个 `<p>`；beta 1 个 `<h1>`、9 个 `<h2>`、76 个 `<li>`、0 个 `<p>`；都没有 HTML 实体。生产解析器的条目数等于页面上 `<li>` + `<p>` 的数量（stable 49，beta 76）。
- 同一天 arm64 feed 里带 `releaseNotesLink` 的只有每条渠道最新的那个条目，加上 2023 年 29.0.2 的 `…/osx_update/stable/notes.html`；后者不在 `feedPagePattern` 里，会退回嵌入网页。
