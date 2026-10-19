# AirBuild

## 基本信息
- Bundle ID: `plus.yellow.AirBuild`
- Team ID: `QDJ93ZUQ9B`（Developer ID Application: YellowPlus, Inc.），1.1.93 / 1.1.120 / 1.1.121 真包一致，`spctl` 为 Notarized Developer ID
- 观测版本: 1.1（`CFBundleVersion` 1.1.121），取自 `https://release.air.build/macos/AirBuild-latest.zip`（2026-10-18，123637793 字节）；另取 1.1.93（stable）与 1.1.120（beta）
- 自更新机制: Sparkle（`SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks`、`SUScheduledCheckInterval` 3600）
- 架构 / OS: arm64；`LSMinimumSystemVersion` 26.0
- 产品: AI 生成并提交 iOS app 的工具（`https://air.build/`），与 JetBrains Air（`com.jetbrains.air`）无关。app 本身不开源（`yellowplushq` 只公开了插件等周边仓库）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —        | —   | —      | —           |
| **beta**     | ✓（`AirBuildChannel`） | — | — | — | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`feed-discover`：`declared  https://release.air.build/macos/appcast.xml`）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `plus.yellow.AirBuild` | 共享 | CFPrefs `ReceiveBetaVersions` 为 false / 缺省 | feed 里无 tag 的 item | ✓ |
| beta    | `plus.yellow.AirBuild` | 共享 | CFPrefs `ReceiveBetaVersions` 为 true | `<sparkle:channel>beta</sparkle:channel>` | ✓ `AirBuildChannel`，真机拨开关已确认 |

- 开关：Settings ▸ General ▸「Receive Beta Updates」（说明文字「Beta versions arrive more often and may be less stable.」）。二进制里 `AppUpdater.swift` 旁有 `ReceiveBetaVersions` 与 `allowedChannelsForUpdater:`。
- 真机确认（2026-10-19，1.1.93 运行中，从设置界面拨开关）：打开 → `defaults read plus.yellow.AirBuild` 出现 `ReceiveBetaVersions = 1`；关闭 → 布尔 `0`，键保留；启动后、拨开关前没有这个键。app 未沙盒，域在 `~/Library/Preferences`。
- 为什么要 binding：beta 包没有渠道标记。1.1.120（beta）与 1.1.121（stable）的 `CFBundleShortVersionString` 都是 `1.1`，`AirBuildReleaseLabel` 都是 `v1.1-beta.143`（121 就是 beta.143 升成正式的那个构建），`ReleaseChannel.detect` 一律判 stable。feed 保留全部构建，所以已装 beta 靠反查 build 能认出来（channel-verify 1.1.120：`release history 292 entries`）；认不出的是勾了开关、装着 stable 的副本。
- 不勾或没有键 → `.stable`（权威），与 app 自己的默认一致；勾了 → `.beta`（标签由 `ReleaseChannel.beta` 推出，与 feed 写法一致，不需要 binding proof）。
- 生产路径（app 已退出，`defaults write` 后跑 `channel-verify /Applications/AirBuild.app`，事后还原为 app 写过的 `0`）：`true` → `ChannelBinding beta — read from this app's own preference`、`detected channel → beta`；`false` → `stable`。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://release.air.build/macos/appcast.xml`
- feed 形状（2026-10-19）: 292 条，151 条 `beta`、141 条无 tag；每条 `minimumSystemVersion` 26.0；没有 `maximumSystemVersion`、`phasedRolloutInterval`、`<sparkle:deltas>`、`<description>`、`releaseNotesLink`
- 版本: `sparkle:version` = `CFBundleVersion`（`1.1.121`），`shortVersionString` 只到 `1.1`，同一个 1.1 下的构建只靠 build 区分；`duo check` 显示为 `1.1 (1.1.93) → 1.1 (1.1.121)`

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle） | 无 | 无可消费 |
| 证据 | 包内 `Sparkle.framework` | 2026-10-19 feed 292 条均无 `<sparkle:deltas>`；channel-verify `deltas 0` | 发了也是 Sparkle delta，`DeltaApplier` 现成 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不适用 |
| 证据 | — | 第二轮启动后它自己的 Sparkle 弹出「Software Update」窗口（没点），Caches / Application Support / Containers 下没有新的大文件 | — |

## Changelog
- 来源: 无。feed 不带说明；`air.build/changelog`、`/changelog/`、`/releases` 都是 404，sitemap 里没有更新说明页。
- 结构化: ✗（厂商不发布）；channel-verify `changelog pane none — the pane says there are no release notes`
- 跟随 channel: 不适用
- Recipe 状态: 不需要（没有来源）

## 一键安装
- 状态: 支持（Sparkle 通用路径，zip，EdDSA + Team ID 闸）
- 端到端（2026-10-19）:
  - 第一轮（未运行）：1.1.93（官方 zip）放进 `/Applications`。`duo check AirBuild` → `1.1 (1.1.93) → 1.1 (1.1.121) [Sparkle, in-place]`；`duo install AirBuild --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 123637793`，21.1 s。之后为 1.1.121，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，与厂商 1.1.121 `diff -r --no-dereference` 一致。
  - 第二轮（运行中）：重新放入 1.1.93 并启动（启动前后比对 `~/.claude` 的 skills / agents / commands、`~/.codex`、`~/.cursor`：没有新文件）。`duo install` → `installed` → `duo restart AirBuild` → `restarted`，进程换新，之后 10 s 磁盘一直是 1.1.121。
- 格式: zip
- 校验: 只有 EdDSA，没有 SHA 摘要
- **读的是**: 人人可手动下载的 GA。enclosure 是 `release.air.build/macos/` 下公开的 zip（产品页下载按钮指向同目录的 `AirBuild-latest.zip`）；beta 是同一 feed 的 `beta` 标签，与 app 自己勾开关后看到的一致
- 嵌套: `LiveKitWebRTC.framework`、`Sparkle.framework`，没有 helper / LoginItem
- 阻塞: 无

## 已知问题
- 无。

## 如何复验

```sh
curl -sSL -o AirBuild-latest.zip https://release.air.build/macos/AirBuild-latest.zip && ditto -x -k AirBuild-latest.zip x
swift run --package-path application-test feed-discover x/AirBuild.app
swift run --package-path application-test channel-verify x/AirBuild.app
curl -sSL https://release.air.build/macos/appcast.xml | grep -c '<sparkle:channel>beta'
```

2026-10-19：channel-verify（1.1.93 zip）`winning source Sparkle`、`latest 1.1`、download `…/AirBuild-macOS-1.1-121.zip`、`release history 141 entries`、`deltas 0`、`status UPDATE → 1.1`；1.1.120（beta）zip 同样推 1.1.121，`release history 292 entries`。

## 建议下一步
1. 无代码待办。厂商若开始发更新说明，再加 changelog recipe。
