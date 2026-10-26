# Rambox

## 基本信息
- Bundle ID: `com.rambox`（2.x 与 3.x 同一个 id）
- 仓库: `ramboxapp/download`（只放发布包）
- Team ID: `7F292FPD69`（Rambox LLC）；2.7.2、3.1.2 都 `spctl` accepted，`source=Notarized Developer ID`
- 观测版本: 2.7.2（tag `v2.7.2`，资产 `Rambox-2.7.2-mac.dmg`）与 3.1.2（tag `v3.1.2`，资产 `Rambox-3.1.2-mac.dmg`）；观测日期: 2026-10-26
- 自更新机制: Electron，electron-updater（`Contents/Resources/app-update.yml`: `provider: github`、`owner: ramboxapp`、`repo: download`、`updaterCacheDirName: rambox-updater`）+ `Squirrel.framework`
- 分发: GitHub Releases（`ramboxapp/download`）、官网下载页、Homebrew cask `rambox`（2026-10-26 为 3.1.2，`auto_updates true`，装的是 `-mac.zip`）。MAS: iTunes Search API（`term=rambox&entity=macSoftware&country=us`，2026-10-26）44 条结果里没有 Rambox

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，`HomebrewCaskSource` 不应答） | — | ✓ | — |
| **beta**   | —       | —        | —   | ✗（只接一条 stable rule，见覆盖清单） | — |

当前生效源: **GitHub**（channel-verify 实测，2.7.2 与 3.1.2 两个真包都是 `winning source GitHub`）

## 覆盖清单
- 各版本的 bundle id / Team（读真包）:
  - v3.1.2: `com.rambox`，Team 7F292FPD69，universal（`x86_64 arm64`），`LSMinimumSystemVersion` 12.0
  - v2.7.2: `com.rambox`，Team 7F292FPD69，universal，12.0
  - v2.7.1、v2.0.1（scaffold 脚本下载比对）: 同 bundle id、同 Team，版本与 tag 一致
- **两个大版本共用一个 id。** 2.x 与 3.x 都是 `com.rambox`、同 Team，装在同一个 `/Applications/Rambox.app`。3.0.0 release notes 原文: 「Signing in to Rambox 3 moves your account to the new Rambox 3 format. Once moved, Rambox 2 can no longer sign in with that account」（单向迁移）。所以 2.x 副本一键换成 3.x 会让用户在没有选择的情况下走上单向迁移 → 用 `OneClickGate` 挡住，见一键安装
- **厂商把 3.x 压着不推（证据，2026-10-26）:**
  - `/releases/latest` = `v2.7.2`（发布于 2026-10-09T23:48Z，晚于 v3.0.0 和 v3.1.0；`curl -sI …/releases/latest` 的 `location` 指向 `tag/v2.7.2`）
  - v3.1.2 的 `latest-mac.yml` 末尾 `stagingPercentage: 0`；v2.7.2 的 `latest-mac.yml` 没有这个字段
  - 2.7.2 的 `app.asar` 里更新逻辑: `isV3` 按新版本的 semver major `>= 3` 判断，`willDownload: !isV3 && (autoUpdate || forced)`，界面上对 3.x 只显示「v3 可用」与下载按钮，不自动下载
  - Homebrew cask 已跟到 3.1.2（与厂商的 GitHub latest 不同）；cask 是 `auto_updates`，我们的 Homebrew 源不应答
- 本 rule 跟随厂商: 读 `/releases/latest`，所以今天 2.x 副本得到 2.7.x，**3.x 副本读到 2.7.2、显示 up to date**（channel-verify 实测）。等厂商把 `/releases/latest` 挪到 3.x，3.x 副本才看到更新，2.x 副本会看到 3.x 但一键被门挡住
- 旧 bundle id（各自是另一个产品，不做 `BundleIDMigration`）:
  - `com.grupovrs.ramboxpro`: Rambox Pro 1.x，同一个仓库的 `v1.x` tag（资产名 `RamboxPro-<v>-mac.dmg`，最新 v1.5.3）。上一轮核对读到同 Team、x86_64；本轮未重读真包。2.7.2 的更新器明确跳过 URL 含 `ramboxpro` 的更新（`indexOf("ramboxpro")` → `update-not-available`），厂商也把它当另一个产品。我们的 rule 只对 `com.rambox` 生效，安装模式 `^Rambox-…-mac\.dmg$` 也不匹配 `RamboxPro-…`
  - `com.grupovrs.ramboxce`: Rambox Community Edition，仓库 `ramboxapp/community-edition`（已 archived）
  - `com.saenzramiro.rambox`: 0.x 时代的 id（Homebrew cask 的 `zap` 列有它和 `com.grupovrs.ramboxce` 的偏好/缓存路径）；没读真包
  - 不做迁移的理由: 这些是厂商已停止的前代产品，新 Rambox 是另装、并排存在的另一个 app，不是改名；把它们映射到 `com.rambox` 会让一键用 Rambox 2.x/3.x 去换掉另一个产品
- 其他轨: 应用内 beta 开关（`betaChannel`，默认关）让 electron-updater `allowPrerelease`，读 `v*-beta.N` prerelease。本 rule 的 `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$` 不读这些 tag。beta 副本的版本号带 `-beta.N`（从 `latest-mac.yml` 的 `version: 3.0.0-beta.1` 推断，没读 beta 真包，**未验证**），`ReleaseChannel.detect` 会读成 beta，没有 beta rule → GitHub 源不应答，这些副本只靠 Rambox 自己的更新器。owner 决定只接一条 stable rule，这是已知缺口
- 版本范围: `versionPattern` 读得到列出的 42 个稳定 tag 全部（v2.0.1 … v3.1.2），也能读下个大版本（`v4.0.0`）
- 主机下限: 厂商 macOS 12、universal，都在我们的主机下限（arm64）之内

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable 2.x | `com.rambox` | 共享 | `CFBundleShortVersionString` major = 2 | `/releases/latest`（今天 2.7.2） | ✓ |
| stable 3.x | `com.rambox` | 共享 | major ≥ 3 | 同上；厂商挪 latest 之前读成 up to date | ✓（检测）|
| beta | `com.rambox` | 共享 | 版本带 `-beta.N` | 应用内 `betaChannel` | ✗（不接） |

## 更新检测
- 源: `ramboxapp/download` GitHub Releases，`/releases/latest`
- 版本方案: tag `v2.7.2` → `CFBundleShortVersionString` `2.7.2`、`CFBundleVersion` `2.7.2`；3.1.2 同形
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^Rambox-[0-9]+(?:\.[0-9]+)+-mac\.dmg$`（每个 release 一个 universal dmg；同 release 的 `-mac.zip` 是 electron-updater 用的，模式不取）
- channel-verify（2026-10-26）:
  - 2.7.2: `detected channel → stable`；`winning source GitHub`、`latest 2.7.2`、`status up to date`
  - 3.1.2: `detected channel → stable`；`winning source GitHub`、`latest 2.7.2`、`status up to date`
- Electron 源（`ElectronManifestSource`）对 `provider: github` 不构造地址，不会应答；Homebrew cask 是 `auto_updates`，`HomebrewCaskSource` 不应答。所以 `com.rambox` 的报价只来自这条 GitHub rule

## 按架构 / 按 OS 分轨
- 架构: universal（`lipo -archs`: `x86_64 arm64`），没有分架构资产；`LSMinimumSystemVersion`: 12.0（2.7.2、3.1.2 相同）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 | 不能 |
| 证据 | `app-update.yml` 指向 electron-updater；包内 `Squirrel.framework` | 每个 release 有 `Rambox-<v>-mac.zip.blockmap`、`-mac.dmg.blockmap`（v3.1.2 zip blockmap 228076 B） | `DeltaApplier` 只吃 Sparkle binary delta 和 MyGo；没有消费 blockmap 的机制 |

- 格式: electron-builder blockmap（按块差分下载，不是二进制补丁）
- 阻塞项: 没有 blockmap 机制；全量 dmg 约 214–216 MB

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（同大版本、`autoUpdate` 默认开） | 没查（没启动 app） | ○（`SelfUpdaterStash` 有 electron-updater 布局，没对 Rambox 端到端验） |
| 证据 | 2.7.2 asar: `autoDownload=!1` 后由自己的代码在 `willDownload` 时调 `downloadUpdate()`；设置 `autoUpdate` 默认 `!0`；electron-updater `autoInstallOnAppQuit=!0` | — | `SelfUpdaterStash` 按 `app-update.yml` 的 `updaterCacheDirName` 读 `~/Library/Caches/rambox-updater/pending/` |

- 记录文件与字段: electron-updater 的 `pending/update-info.json`（未对 Rambox 实测）
- 容器: electron-updater 在 Mac 上下 `-mac.zip`，包根是 `Rambox.app`
- 两份副本会不会共用这个目录: 会，目录名只按 `updaterCacheDirName`

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` → `GitHubMarkdownParser`）
- 结构化（2026-10-26，channel-verify `changelog pane`，2.7.2 与 3.1.2 两个真包相同，因为都读 `/releases/latest`）: `source structured: 1 entries; newest 2.7.2: 1 items, headings ["Fixes"]; first items ["Fixed few edge case were licence validat"]` —— 分节标题保留，没有被压平
- 3.x 的正文（如 v3.0.0 的 `## New` / `## Improvements` 列表）要等厂商把 latest 挪到 3.x 才会显示
- 跟随 channel: —（只有 stable）
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（同大版本内）；2.x → 3.x 由 `OneClickGate` 挡住
- 端到端: 待主会话（真机从上一版装到最新版）
- 格式: .dmg（`hdiutil imageinfo` 退出 0），根目录 `Rambox.app`
- 嵌套 / 常驻组件（2.7.2 包；3.1.2 包同样没有 `Contents/Library`）: 只有 `Contents/Frameworks` 下四个 Electron helper（`Rambox Helper.app`、`(GPU)`、`(Plugin)`、`(Renderer)`）和 `Squirrel.framework`、`Mantle.framework`、`ReactiveObjC.framework`；没有 `Contents/Library`（无 LoginItems / LaunchServices / SystemExtensions）
- 签名: 2.7.2、2.7.1、2.0.1、3.1.2 都是 Team `7F292FPD69`，上一版没有换 Team
- 校验: GitHub 资产 digest。2.7.2 `sha256:24ae43244c9ab7c3ecb5d8d8e18549a1ad9d0d01455396e2c1f4f66e63135ff6`，与下载的包一致
- **一键门**（两个按报价包名分的 `OneClickGate`）:
  - 包名大版本 ≥ 3（`^GitHub:Rambox-(?:[3-9]|[1-9][0-9]+)\.`）: 只给 `CFBundleShortVersionString` 大版本 ≥ 3 的副本（`^(?:[3-9]|[1-9][0-9]+)\.`）。2.x 副本（以及读不出版本的副本）保留检测、没有一键，理由是 3.0.0 的单向账号迁移
  - 包名大版本 = 2（`^GitHub:Rambox-2\.`）: 只给 2.x 副本（`^2\.`）。今天 3.x 副本读到 2.7.2 是 up to date，不会有这个报价；万一出现，3 → 2 是降级，账号已迁移的副本用不了 2.x
  - 其他包名（例如 `RamboxPro-…`）: 两个门都不点名 → `unnamedOffer` 挡住
  - 测试 `OneClickGateTests.ramboxOneClickNeverCrossesFromTwoToThree`；变异检查: 3.x 门的 requirement 放成 `.` → 12 条失败，2.x 门放成 `.` → 3 条失败，恢复后通过
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，即厂商自己的下载默认值 2.7.2）

### 启动副作用（读包，未启动）
- 开机自启: 设置 `openAuto` 默认 `"yes"`，用 node auto-launch 的 AppleScript 路线（`tell application "System Events" to …` 增删 login item）→ 首次启动会弹「控制 System Events」的自动化（Automation）授权框，并加一个登录项
- URL scheme: Info.plist 注册 `rambox://`
- 代理: 只有 Electron 的会话级 `session.setProxy`（每个服务一个 partition 的代理设置），asar 里没有 `networksetup`、`add-trusted-cert`、`/etc/hosts`、Network Extension，不改系统代理/证书/DNS
- MCP「Remote Control」是 3.0.0 notes 里写的可选设置（「an optional setting」），默认值没读

## 已知问题
- 3.x 副本今天读到 2.7.2、显示 up to date，看不到 3.1.x 的更新，直到厂商挪 `/releases/latest`。这是跟随厂商的决定（3.x 由它自己的更新器负责）
- beta 副本（`-beta.N`）没有 rule，见覆盖清单
- 运行中一键: 自更新器同大版本会自己下载、退出时由 Squirrel 安装；duo 换包后退出 app 时，若它已暂存了更旧的同大版本，可能装回去（未实测）

## 如何复验
```bash
gh release download v2.7.2 --repo ramboxapp/download --pattern 'Rambox-2.7.2-mac.dmg'
gh release download v3.1.2 --repo ramboxapp/download --pattern 'Rambox-3.1.2-mac.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Rambox-2.7.2-mac.dmg
swift run --package-path application-test channel-verify Rambox-2.7.2-mac.dmg --expect stable
swift run --package-path application-test channel-verify Rambox-3.1.2-mac.dmg --expect stable
curl -sI https://github.com/ramboxapp/download/releases/latest | grep -i '^location'
curl -sL https://github.com/ramboxapp/download/releases/download/v3.1.2/latest-mac.yml | grep stagingPercentage
swift test --package-path DuoUpdaterCore --filter OneClickGateTests
```

## 建议下一步
1. 真机一键: 2.7.1 → 2.7.2（不运行、运行中两轮）；另确认 2.7.2 副本面对 3.x 报价被门拒（需要让 GitHub 报 3.x，例如 `GitHub API` 模拟钩子）
2. 厂商把 `/releases/latest` 挪到 3.x 后，复核 3.x 副本的检测和 changelog
