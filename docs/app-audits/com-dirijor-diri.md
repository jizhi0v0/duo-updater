# diri

## 基本信息
- Bundle ID: `com.dirijor.diri`
- Team ID: `A56RVNJ69X`（Developer ID，公证并 staple；0.9.0 与 0.9.1 相同）
- 观测版本: `0.9.1`（`CFBundleShortVersionString` = tag 去掉 `v`；`CFBundleVersion` 是构建时间戳
  `20261002.150608`，不参与比较）
- 自更新机制: 自研（`diri/crates/diri-updater`，Rust），**不是 Sparkle**：无 `SUFeedURL`，读每个
  release 上的 `appcast.json` 资产（`releases/latest/download/appcast.json`）
- 分发: GitHub Releases（`cristicretu/diri`）+ 作者自己的 tap `cristicretu/diri/diri`（不在官方
  homebrew-cask，`auto_updates true`）。无 MAS
- 开源: 是。以下更新器、换 bundle 方式、Engine 接管读自 `main` 分支源码

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | — | —（tap cask `auto_updates true`，落到下一个源） | — | ✓（一键 zip） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.dirijor.diri` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。2026-10-04 全部 release（v0.4.1–v0.9.1）都不是 prerelease；仓库另有三个 `diri-v0.4.x`
tag，没有对应 release，锚定 pattern 也不收。CI 有 Nightly 构建，但只是 workflow artifact，不发
release，app 内也没有渠道开关（settled from source: `diri/UPDATING.md` on `main`，feed 只有
`releases/latest` 一个地址）。

## 更新检测
- 源: `cristicretu/diri` GitHub Releases，`/releases/latest`
- 端点（上游自己的）: `https://github.com/cristicretu/diri/releases/latest/download/appcast.json`，
  JSON（`feed_version: 1`），保留最新 5 个版本，每条有 `version` / `url`（zip）/ `sha256` /
  `minimum_system_version` / `published`。我们不读它：GitHub 源给出的版本、资产地址与它一致
- 版本方案: tag `v0.9.1` ↔ short `0.9.1`
- 注意事项: 无设备标识、无灰度

## 按 OS 分轨
- 0.9.1 真包 `LSMinimumSystemVersion` = `15.0`；`appcast.json` 每条 `minimum_system_version` = `15.0`
  （v0.8.9–v0.9.1），无上限；tap cask `depends_on macos: :sequoia`
- 不按 OS 分桶：每个版本只有一个 macOS 包（universal）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | 不带 Sparkle；`diri-updater` 只下载整包 zip（`UPDATING.md`） | `appcast.json`（2026-10-04）每条只有一个 zip `url`，没有 delta 字段 | — |

## Changelog
- 来源: `ChangelogRecipe`，`api.github.com/repos/cristicretu/diri/releases?per_page=40`，
  `.gitHubReleases`，`maxEntries: 20`
- 为什么要 recipe: GitHub 源只带最新一条正文，而上游几乎每天发版，落后几个版本的副本只看得到
  一版说明
- 正文形状: 0.8.3 起 `##` 分节（带 emoji）；0.6.x–0.7.x 是 `## diri <ver> — …` 标题下 `###` 分节；
  0.7.4–0.8.2 是无标题的列表。末尾的下载说明是段落，不进条目，不需要 `skipSections`
- 结构化（2026-10-04，`channel-verify` 的 `changelog pane` 行）:
  `recipe changelog:com.dirijor.diri:-: 20 entries; newest 0.9.1: 21 items, headings ["✨ Highlights",
  "🛡 Sessions come through", "👋 First run", "📝 Notes", "🖥 Feel", "🔧 Fixes"]`。逐条看过 20 个
  条目：`##` / `###` 分节都作为标题保留，无标题版本是纯列表，最后一项都是正文列表项而不是下载说明
- 跟随 channel: 单渠道
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（`installAssetPattern` `^diri-[0-9.]+-universal\.zip$`，`.zip`）
- 端到端: ✓（2026-10-04）。`/Applications` 装 0.9.0 → `duo check` 报 `0.9.0 → 0.9.1 [GitHub, in-place]` →
  `duo install diri --yes` 依次 downloading / extracting / verifyingCodeSignature / installing → done；
  装上的副本 short `0.9.1`、`TeamIdentifier=A56RVNJ69X`、`codesign --verify --deep --strict` 退出 0、
  `spctl` 为 Notarized Developer ID、无 quarantine、旁边没有残留的暂存包，之后 `duo check` 为最新
- 格式: zip，内含 stapled 的 `diri.app`（即上游 updater 安装的同一个包；同 release 的 dmg 是同一个
  bundle 再封装）
- **读的是**: 人人可手动下载的 GA（`/releases/latest` 的公开资产，也是上游 updater 的 feed 地址）
- 常驻进程: bundle 的 `Contents/Resources/bin` 里有 Engine（`dirijord-rs`）、每个会话一个
  `diri-holder`，它们比 app 活得久；0.9.1 起还有 SMAppService 守护进程
  `Contents/Library/LaunchDaemons/com.dirijor.diri.wake.plist`（`BundleProgram` 指向
  `Contents/Resources/bin/diri-wake-helper`，socket 按需拉起）。为什么换 bundle 仍然安全：
  - 上游自己的 updater 也是在这些进程还活着时换 bundle。settled from source:
    `diri/crates/diri-app/src/daemon_launch.rs` on `main`：app 启动时对 bundle 里的 Engine 算 sha256，
    与运行中 Engine 的 `executableHash` 不同就让旧 Engine 持久化状态后退出，Holder 和 agent 继续跑，
    新 Engine 接管。所以除了用户自己重启 diri，不需要别的重启
  - 唯一硬要求是 app 路径上**始终有可读的 bundle**：diri 退出时 loginwindow 会让 Background Task
    Management 读这个路径，读不到就终止 Engine、所有 Holder 和 agent（`UPDATING.md`「How the swap
    works」；0.9.1 release notes #648 修的就是这个）。`InPlaceSwap` 在可写位置用 `replaceItemAt`
    原子交换，路径上不会出现缺失或拷了一半的 bundle。需要管理员的路径
    （`privilegedReplacementShell`）先把新包完整拷到旁边，再两次同目录 rename，中间只有两次
    rename 之间的空档——和上游 helper 的「旧包改名 → 新包改名就位」是同一个形状
  - 守护进程按相对路径注册，换包后路径不变，下次按需拉起的是新二进制
- 阻塞: 无

## 已知问题
- 上游 updater 默认开启自动更新；两边都会提示同一个版本，谁先装都无害

## 如何复验
```
# GET https://api.github.com/repos/cristicretu/diri/releases/latest → v0.9.1
# diri-0.9.1-universal.zip sha256 2d120ffe…6479、dmg 7a2ac45f…a2ae，与 release 资产的 digest、
#   SHA256SUMS 一致
# 解包 → com.dirijor.diri / 0.9.1 / 20261002.150608，x86_64 + arm64，LSMinimumSystemVersion 15.0，
#        无 SUFeedURL，TeamIdentifier=A56RVNJ69X，spctl: Notarized Developer ID，stapler validate ✓
# diri-0.9.0-universal.zip 解包 → com.dirijor.diri / 0.9.0，TeamIdentifier=A56RVNJ69X
swift run --package-path application-test feed-discover diri-0.9.1-universal.zip
#   → no Sparkle and no electron-builder update config
swift run --package-path application-test channel-verify diri-0.9.1-universal.dmg
#   → detected channel stable, winning source GitHub, latest 0.9.1,
#     download …/v0.9.1/diri-0.9.1-universal.zip, status up to date
swift run --package-path application-test channel-verify <0.9.0 解包>/diri.app
#   → winning source GitHub, latest 0.9.1, status UPDATE → 0.9.1
```

## 建议下一步
1. 无。上游若开始发 prerelease（beta 轨），按版本后缀另加一条规则前先确认 app 内有无渠道开关
