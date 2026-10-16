# Loop

## 基本信息
- App: Loop — 开源窗口管理器（径向菜单 + 快捷键调整窗口），菜单栏常驻
- Bundle ID: `com.MrKai77.Loop`（1.0.0-beta.7 起；1.0.0-beta.1–6 是 `com.KaiAzim.Loop`，见「覆盖清单」）
- 仓库: `MrKai77/Loop`（默认分支 `develop`）
- Team ID: `5F967GYF84`（Developer ID Application: Kai Azim，公证；1.0.0–1.4.2 八个正式版都相同）
- 观测版本: 1.4.2（`CFBundleVersion` 1693）；Development 轨 `🧪 1.4.3`（1783）；观测日期: 2026-10-16
- 自更新机制: 自研（`Loop/Updater/`，读 GitHub API）。1.0.0 及更早的包声明 Sparkle `SUFeedURL`
  `https://mrkai77.github.io/Loop/appcast.xml`，该地址 2026-10-16 返回 404；1.1.0 起不再声明
- 分发: GitHub Releases；Homebrew cask `loop`（`auto_updates true`，`HomebrewCaskSource` 让路）；无 MAS
  （iTunes lookup 按两个 bundle id 都是 0 条）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                 | Sparkle            | Homebrew          | MAS | GitHub | VendorProbe |
|-----------------|--------------------|-------------------|-----|--------|-------------|
| **stable**      | ✗（旧 feed 404）    | —（auto_updates） | —   | ✓      | —           |
| **dev**         | —                  | —                 | —   | ○（需要引擎改动，见下） | — |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 结论 `—`（1.4.2 包不声明任何 feed）。

## 覆盖清单（Coverage checklist）

| 副本组 | 处理 | 依据 |
|---|---|---|
| `com.MrKai77.Loop` 1.0.0–1.4.2 正式版 | GitHub rule，一键 | 实测，见下 |
| `com.MrKai77.Loop` Development 构建（版本 `🧪 x.y.z`） | 识别为 `.dev`，**不提供更新**（gap） | 实测 + 源码 |
| `com.MrKai77.Loop` 1.0.0-beta.7–15（版本 `1.0.0-beta.N`） | gap：识别为 beta，旧 Sparkle feed 404 | 实测 |
| `com.KaiAzim.Loop` 1.0.0-beta.1–6（版本 `0.3.0` 等） | gap：旧 id，旧 Sparkle feed 404 | 实测 |
| 架构 | 每个 release 一个通用 `Loop.zip`（`lipo` = x86_64 arm64） | 实测 |
| OS 下限 | `LSMinimumSystemVersion` 13.0（1.0.0–1.4.2 及 dev 构建），低于 DuoUpdater 自己的下限 | 实测 |

- **beta.7–15**：签名是 Apple Development（Team `8P53VAPX2H`），`spctl` rejected，未公证。版本串
  `1.0.0-beta.15` 被 `ReleaseChannel.detect` 第 4 步判成 `.beta`，stable rule 不服务；包里的 `SUFeedURL`
  已 404，`channel-verify` 实跑: `detected channel → beta`、`status error: The app's update feed returned HTTP 404`。
  这些 tag 在 GitHub 上没有标 prerelease，厂商当年把它们当正式版发；即便接上，一键也会被 Team 闸拒绝
  （`8P53VAPX2H` ≠ `5F967GYF84`）。没接：最后一个是 2024-03，2024-06 的 1.0.0 已取代。
- **`com.KaiAzim.Loop`**：beta.5 / beta.6 实测 id 为 `com.KaiAzim.Loop`、签名 Apple Development（Team `CK2YS5GSMD`），
  `spctl` rejected；`channel-verify` 实跑 `status error: … HTTP 404`。从这个 id 换到 `com.MrKai77.Loop` 是 bundle id
  变更，一键做不到；只做检测会把一个改了 id 的 app 当成同一个 app 的更新。没接。

## Channel 详情

settled from source: `Loop/Updater/UpdaterModels.swift`、`Loop/Updater/UpdateChecker.swift`、
`.github/workflows/dev-build.yml`、`Loop/Extensions/Defaults+Extensions.swift`，均在 `develop` 分支。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.MrKai77.Loop` | — | — | `/releases/latest` | ✓ |
| dev（厂商称 Development） | `com.MrKai77.Loop` | 共享 | 版本串以 `🧪` 开头（`ReleaseChannel.detect` 0.995） | 一个滚动 prerelease | ○ |

- stable: 厂商更新器读 `https://api.github.com/repos/MrKai77/Loop/releases/latest`，tag 即版本。
- Development: 读 `/releases` 列表里第一个 `prerelease == true` 的 release。实际只有**一个** release，tag 固定为
  `prerelease`，每次 `dev-build.yml` 手动触发时覆盖它的附件、正文和名字。版本只在 release **名字**里:
  `🧪 1.4.3 (1783)`。`dev-build.yml` 把 `CFBundleShortVersionString` 写成 `🧪 1.4.3`（每轮发版手改），
  `CFBundleVersion` 写成 `git rev-list --count HEAD`。同一个 `🧪 1.4.3` 下 build 号一直涨，厂商更新器靠 build 号比较。
- 选轨偏好: CFPrefs `com.MrKai77.Loop` 的 `includeDevelopmentVersions`（Bool）。RELEASE 构建默认 false，
  其他构建默认 true（`#if RELEASE`），默认值不写盘——所以装着 dev 构建的副本这个键常常不存在，不能拿它判轨，
  版本串才是可靠信号。
- **为什么 dev 轨没接**: `GitHubReleaseRule` 只从 `tag_name` 读版本，而这里 tag 恒为 `prerelease`；版本在 release
  名字里，且同一个营销版本下要按 `CFBundleVersion` 比较。两样都需要改 `GitHubReleasesSource`，不是 recipe 能表达的。
- **没接之前的危险，已修**: 修之前 dev 构建被判成 stable，比较器把 `🧪 1.4.3` 排在 1.4.2 之下，`channel-verify`
  实跑 `detected channel → stable`、`status UPDATE → 1.4.2`——把旧的 stable 当更新推给更新的 dev 构建，Team 闸照样放行。
  现在 `ReleaseChannel.detect` 0.995 只对这个 bundle id 把 `🧪` 开头的版本判成 `.dev`，GitHub 源没有 dev rule，直接跳过：
  `detected channel → dev`、`status unknown (no source answered)`。测试见 `LoopChannelTests`（规则去掉后 2 个测试变红，已实测）。

## 更新检测
- 源: `MrKai77/Loop` GitHub Releases，`/releases/latest`（2026-10-16 为 `1.4.2`）
- 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`（锚定）。在全部 24 个 tag 上跑过: 8 个正式版（1.0.0–1.4.2）读出，
  15 个 `1.0.0-beta.N` 和 `prerelease` 不读；`2.0.0`、`1.5` 读出，`1.4.3-rc.1` 不读
- tag 等于 `CFBundleShortVersionString`（1.0.0–1.4.2 真包逐个核过）；`CFBundleVersion` 是提交计数，不参与比较
- 厂商更新器在正文里读 `Minimum macOS version` / `Maximum macOS version` / `Supported architectures` 三行；
  全部 release 正文里只出现过 `Minimum macOS version: 13.0`（1.4.0 起），没有上限、没有架构限制

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 源码: 只下 release 的 `.zip` 附件整包 | 每个 release 只有一个 `Loop.zip` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 基本不会 | 没查 | — |
| 证据 | 1.4.2 源码 `UpdateDownloader.swift`: 下载到 `~/Library/Application Support/Loop/Loop.zip`，只在用户点更新（或打开默认关闭的 `automaticallyUpdate`）后才下，下完立即安装 | 第二轮端到端由主会话做 | — |

- 记录文件: 无（没有完成记录）；容器 zip，包根是 `Loop.app`

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-16，channel-verify `changelog pane`，从 1.4.1 起）: `source structured: 1 entries; newest 1.4.2:
  15 items, headings ["📰 Development News", "✨ New Features", "🐞 Bug Fixes", "🌏 Localization"]; first items
  ["🚧 Fixed an issue in the previous version", "💸 Support Loop by [sponsoring the projec", "🌐 Let us know if you are interested in l"]`。
  分节保留；15 条 = 正文四节的 4+4+6+1 条，`---` 之后的 `Build number` / `Minimum macOS version` 两行不计入条目
- 第一节「Development News」是厂商写的公告（赞助、Discord 链接），照原样显示
- 跟随 channel: —（只接了 stable）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: zip（`^Loop\.zip$`，kind `.zip`），通用二进制
- 嵌套: 1.4.2 没有 LoginItems、Helpers、LaunchAgent、嵌套 app（triage 与本次解包一致）
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256` 前 16 位: 1.4.2 `514e97faab3843cd`、1.4.1
  `ed617a58b1c20425`，都与各自 `digest` 相同
- **`codesign-verify-exit=1` 的原因（triage 记录的）**: zip 里带 `__MACOSX/._Loop.app`（AppleDouble，含 FinderInfo）。
  `ditto -x -k` 解包会把它还原成 `Loop.app` 上的 `com.apple.FinderInfo` xattr，`codesign --verify --deep --strict` 于是报
  `resource fork, Finder information, or similar detritus not allowed`；`unzip` 解包不还原 xattr，同一个 zip exit 0。
  `spctl` 两种解包都是 Notarized Developer ID。安装闸（`SignatureVerifier.verifyCodeSignature`，
  `kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate`）在 **ditto 解出、带 FinderInfo** 的
  1.4.2 上实测 `status=0`——这个 xattr 不挡一键。同类情况见 PhotoCraft 的审计
- Team: 上一版 1.4.1、以及 1.0.0–1.4.0 都是 `5F967GYF84`，与 1.4.2 相同，Team 闸不会拒绝老的正式版副本
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest` 的附件，也是厂商自己更新器读的那一个）
- 端到端: 真机端到端：待主会话执行
- 自更新器会不会和我们抢: 1.4.2 的更新器只在用户确认（或开了默认关闭的自动更新且 Loop 不在前台）时下载并安装，
  没有常驻进程。开发分支已加 `Contents/Library/LaunchServices/LoopUpdaterHelper`（dev 构建里有，1.4.2 没有）：
  `UpdaterAuthorizationCoordinator.swift` 用 `SMJobSubmit` 临时提交一个 `LaunchOnlyOnce` 的 system job，用完即
  `SMJobRemove`，不是常驻 helper。下一个正式版带上它时重看一次
- 阻塞: 无

## 已知问题
- Development 轨没有更新来源（见「Channel 详情」）；dev 副本的行显示 unknown，而不是被推一个更旧的 stable
- beta.7–15 与 `com.KaiAzim.Loop` 的老副本显示旧 feed 404（见「覆盖清单」）

## 建议下一步
1. 如要接 Development 轨: 给 `GitHubReleaseRule` 加「从 release 名字读版本 + 同营销版本按 build 比较」，或写一个
   读 `/releases/tags/prerelease` 名字的 VendorProbe（`versionIsBuild` + `displayVersionPattern`），并把
   `includeDevelopmentVersions` 写成 `ChannelBinding`（注意默认值不写盘）。
2. 第一个带 `LoopUpdaterHelper` 的正式版发布后，重跑 check-bundle 和一键端到端。

## 如何复验
```
.claude/skills/coverage-discovery/scripts/check-bundle.sh <Loop.zip>   # → com.MrKai77.Loop、Team 5F967GYF84、无 SUFeedURL
ditto -x -k <1.4.1 Loop.zip> <dir>
swift run --package-path application-test channel-verify "<dir>/Loop.app" --expect stable   # → stable，GitHub，UPDATE → 1.4.2
swift run --package-path application-test channel-verify "<1.4.2 dir>/Loop.app" --expect stable   # → up to date
swift run --package-path application-test channel-verify "<prerelease dir>/Loop.app" --expect dev # → dev，unknown (no source answered)
```
