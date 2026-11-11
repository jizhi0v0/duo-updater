# Maestro

## 基本信息
- Bundle ID: `com.maestro.app`
- 仓库: `RunMaestro/Maestro`（由 `pedramamini/Maestro` 改名而来，旧地址 API 与下载都重定向到新仓库）
- Team ID: `4N4DQ24LED`（Developer ID Application: Pedram Amini）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.0.2（tag `v1.0.2`，资产 `maestro-1.0.2-arm64-mac.zip`）；上一版 1.0.1；观测日期: 2026-11-11
- 自更新机制: Electron（electron-updater，provider github）
- 分发: GitHub Releases；Homebrew cask `maestro`（`auto_updates true`，装 arm64 dmg，cask URL 仍写旧仓库名）。没有 MAS 版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | ✓ | —      |
| **beta (RC)** | —    | —        | —   | ✓ 一键 arm64 zip（`MaestroChannel` 读 `enableBetaUpdates`） | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`channel-verify`：`winning source  GitHub`）

`feed-discover` 结论 `review electronProviderNeedsConstruction`：`app-update.yml` 只写
`provider: github, owner: RunMaestro, repo: Maestro, updaterCacheDirName: maestro-updater`，
不给地址，`ElectronManifestSource` 不接，所以走 `GitHubReleaseRule`，与 PicGo、Responsively 同路。

## 覆盖清单
- 各版本的 bundle id / Team（读真包 Info.plist 与主可执行文件的签名；1.0.2、1.0.1 是整包，其余用 HTTP range 只取
  `Contents/Info.plist`、`Contents/MacOS/Maestro`、`app-update.yml`）:
  - 1.0.2、1.0.1、1.1.0-RC、0.16.16、0.15.4-RC、0.14.5、0.13.0、0.10.0、0.9.x、0.8.1–0.8.8、0.8.8-rc：
    全是 `com.maestro.app`，Team `4N4DQ24LED`，版本串等于 tag（去 `v`）
  - 0.1.0（在 tag `v0.1.3` 下，资产名还是 `Maestro-0.1.0-…`）、0.1.6、0.2.0、0.7.0、0.8.0：同 bundle id，
    **ad-hoc 签名**（`Signature=adhoc`，无 Team）；它们的 `app-update.yml` 写的是占位
    `owner: yourusername repo: maestro`，自更新器永远找不到新版
  - 没有改过 bundle id：改名只改了仓库，`app-update.yml` 的 owner 从 0.8.1 起是 `pedramamini`，0.15.x 起是 `RunMaestro`
- 其他轨: `-RC` 预发布（同 bundle id），见 Channel 详情。没有 nightly / 别的 edition
- 版本范围: v0.1.0–v1.0.2，103 个 release（67 个非 prerelease）。`v0.1.0`–`v0.1.2` 没有资产。
  - 0.1.0–0.8.0（ad-hoc）：检测 ✓（同 id，规则照样报新版）；一键被 Team 闸拒绝（装着的副本没有 Team，
    `.developerID` 要求下载与已装副本同 Team；`.publishedDigestOnly` 只适用于两边都没有 Team 的情形，
    这里新包有 Team，所以不适用）。用户手动更新一次后进入下面一组
  - 0.8.1 起：同 Team，检测 + 一键
- 主机下限: 1.0.x 的 `LSMinimumSystemVersion` 12.0，0.x 是 10.15，都低于 DuoUpdater 的 macOS 15 / arm64 下限，不需要 `architectureRequirement`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.maestro.app` | — | — | `^v([0-9]+(?:\.[0-9]+)+)$` | ✓ |
| RC      | `com.maestro.app` | 共享 | app 设置 `enableBetaUpdates`（版本串 `-RC` 不算信号） | `MaestroChannel` → `usePrereleases` 的 beta rule | ✓ |

- RC 包的版本串带后缀：`1.1.0-RC`、`0.15.4-RC`（真包 Info.plist）。`ReleaseChannel.detect` 不认 `-RC`，读成
  **stable**（`channel-verify` 对 1.1.0-RC 的 Info.plist：`detected channel → stable`，`status up to date`）。
  `VersionComparator` 把 `1.1.0-RC` 排在 1.0.2 之上、1.1.0 之下，所以 stable 规则不降级它，下一个 stable 发布时推终版。
- app 自己怎么分轨（settled from source: `src/main/auto-updater.ts`、`src/main/update-checker.ts`、
  `src/renderer/stores/settingsStore.ts` on `main`）：electron-updater 显式设 `allowPrerelease = false`，
  再按设置 `enableBetaUpdates`（Settings → General → Updates →「Include beta and release candidate updates」，
  **默认 false**）改写；自己的检查读 `api.github.com/repos/RunMaestro/Maestro/releases`，关着时滤掉
  `prerelease` 与 tag 带 `-(rc|beta|alpha|dev|canary)` 的。也就是说 RC 副本在开关关着时同样只拿 stable——和我们现在的行为一致。
- RC 轨已接（2026-11-11）：`MaestroChannel` 读 `~/Library/Application Support/maestro/maestro-settings.json`
  （真机目录是小写 `maestro`；`maestro-bootstrap.json` 的 `customSyncPath` 指向别处时读那里）的顶层 `enableBetaUpdates`，
  JSON `true` → `.beta`，其他一律 `.stable`。真机 1.0.2 拨两态实测：开 → `true`，关 → `false`，键保留（文件 81 个键）。
  beta rule 读整个列表，tag 收 `v<ver>` 与 `v<ver>-RC` / `-rc`，取最新发布的那一个（RC 或正式版），与 app 开着开关时
  `update-checker.ts` 把 `allReleases[0]` 当最新一致。RC 线常比正式版补丁先发（1.1.0-RC 在 1.0.0 与 1.0.1 之间发布），
  这时最新发布的那个版本号低于 RC 副本，RC 副本读 up to date、不降级。
- RC 的 release 也发 `latest-mac.yml`（不是 `beta-mac.yml`），里面 `version: 1.1.0-RC`。
- 四个没标 prerelease 的 RC tag（`v0.15.4-RC`、`v0.15.0-RC`、`v0.11.2-rc`、`v0.8.8-rc`）被整串锚定的
  `versionPattern` 排除。`/releases/latest` 若落在这种 tag 上，它的资产名带 `-RC`，`installAssetPattern` 也不收，
  引擎回退到列表并只看非 prerelease，再按 pattern 往回找到真正的 stable。
- `v0.16.16-RC`（prerelease）里混着一份 `maestro-0.16.16-arm64-mac.zip`（包内 0.16.16），stable 规则不读
  prerelease，不受影响；0.16.16 副本按 stable 被推新版。

## 更新检测
- 源: `RunMaestro/Maestro` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.0.2` → `CFBundleShortVersionString` `1.0.2`、`CFBundleVersion` `1.0.2`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读 67 个非 prerelease tag 中的 63 个，不读的是上面四个 RC
- install pattern `^maestro-[0-9]+(?:\.[0-9]+)+-arm64-mac\.zip$`；1.0.2 里它不收的: `maestro-1.0.2-arm64-mac.dmg`、
  `maestro-1.0.2-x64-mac.dmg`、`maestro-1.0.2-x64-mac.zip`。0.14.5 及更早资产名首字母大写（`Maestro-0.14.5-arm64-mac.zip`），
  只在最新 release 缺 mac 资产、引擎往回找时才相关
- 注意事项: 旧判断「这个仓库只发 `cli-<ver>`」是把 `mobile-dev-inc/maestro`（移动端测试 CLI，tag `cli-2.12.1`）
  当成了这个 app 的仓库；`RunMaestro/Maestro` 没有任何 `cli-*` tag，`GitHubReleaseRegistry` 里那段排除说明已删除

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（`-arm64-mac` / `-x64-mac`，各有 dmg 和 zip），没有 universal；规则取 arm64 zip
- `LSMinimumSystemVersion`: 12.0（1.0.x），10.15（0.x）
- `latest-mac.yml` 只列 arm64 的 zip/dmg

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | — |
| 证据 | electron-updater 的 mac 端支持按 `.zip.blockmap` 差量下载 | v1.0.2 / v1.0.1 / v1.1.0-RC 的资产里没有 `*.blockmap`（GitHub API 资产列表，2026-11-11） | 没有差量可用；一键下整包 |

- 格式: electron-builder blockmap（未发布）
- 阻塞项: 无

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 未测（运行中一轮未做） | 能（布局已接；运行中一轮未做） |
| 证据 | `app-update.yml` `updaterCacheDirName: maestro-updater`；electron-updater 的 `DownloadedUpdateHelper` | 未测（运行中一轮未做） | `SelfUpdaterStash` 读 `.electronUpdater(cacheDirectoryName:)`，名字取自包内 `app-update.yml` |

- 记录文件与字段: `~/Library/Caches/maestro-updater/pending/update-info.json`，下载完成后才写（`setDownloadedFile`），
  带 `fileName` 与 `sha512`（base64）
- 容器: zip（electron-updater 在 mac 上下 `latest-mac.yml` 的 `path`，即 `maestro-<v>-arm64-mac.zip`），包根是 `Maestro.app`
- 触发: `autoDownload = false`，只在用户在更新弹窗里点下载后才下载（`updates:download`，下载前把 provider 换成
  `generic` 指向该 tag 的 `releases/download/<tag>/`，缓存目录不变）；`autoInstallOnAppQuit = true`，下完后退出时由 Squirrel.Mac 安装
- 两份副本会不会共用这个目录: 会（目录按 `updaterCacheDirName`，不按副本），`SelfUpdaterStash.isSoleClaimant` 管这种情形

## Changelog
- 来源: GitHub release 列表（`api.github.com/repos/RunMaestro/Maestro/releases?per_page=40`），专用格式 `.maestroReleases`：
  每条正文先经 `MaestroReleaseNotes.normalized` 改写，再走与 `.gitHubReleases` 相同的 `GitHubMarkdownParser`
- 结构化: `changelog pane  recipe changelog:com.maestro.app:stable: 12 entries; newest 1.0.2: 10 items, headings ["Highlights", "Also in this release"]; first items ["▶️ **Shell blocks in an agent's reply hav", "📊 **Re-reading your usage history no lon", "🗺️ **The Cue Pipeline Graph groups pipeli"]`
- 为什么要专用格式: 正文把主要改动写成 `# 1.0.2 Highlights` 下的段落（emoji + 粗体句），其余放在 `## Also in 1.0.2` 的列表里。
  共享解析器只要正文里有列表就只取列表，带数字的标题又当成重复的版本号丢掉，所以只剩 Also in 的列表、没有小标题。
  改写把段落变成列表项（硬换行接起来；以 `:` 结尾的引导句、致谢、`**Full Changelog**`、图片和裸链接不动），
  标题去掉版本号（`in v0.15.2` / `in 0.17.x` / `to v0.12.3` → `… this release`，其余版本号删掉）。改写之前先按原标题
  切掉重复的旧版本段落（`### v0.13.0 Changes`），与共享解析器的规则一致。共享解析器本身没改，其他 GitHub 源不受影响
- 跟随 channel: stable；`tagPattern` 与 rule 相同，GitHub 没标 prerelease 的四个 RC tag 也排除
- 缓存: 加 recipe 之前没有 Maestro 的 recipe 缓存（磁盘缓存只存 recipe 结果），不需要 bump `Changelog.parserGeneration`

## 一键安装
- 状态: 支持（0.8.1 起的副本）
- 端到端: ✓ 第一轮（2026-11-11，本机，未运行）：/Applications 放 1.0.1，`duo install com.maestro.app --yes` → `verifyingSignature … verifyingCodeSignature … installed.`；结果 1.0.2、Team `4N4DQ24LED`、`codesign --verify --deep --strict` 0、spctl Notarized Developer ID。运行中一轮（含 electron-updater 停放与退出即装的竞争）未做。
- 格式: .zip（electron-updater 自己装的也是这个 zip）
- 嵌套 / 常驻组件: `Contents/Frameworks/Maestro Helper.app`、`Maestro Helper (GPU).app`、`Maestro Helper (Plugin).app`、
  `Maestro Helper (Renderer).app`，均 `LSUIElement=true`，是 Electron 标准的子进程 helper，随主进程退出；
  没有 `Contents/Library/LoginItems`，源码里没有 `setLoginItemSettings` / LaunchAgent。`Resources/maestro-cli.js` 是 CLI 脚本，不常驻
- 校验: GitHub digest `sha256:a73df9356cfa12ca4efef14b6843074bfbd282c3113c78a95f30c7dc4321ddba`，与下载的 1.0.2 包一致；
  1.0.1 `sha256:2c592d42d7100ae788fda922fd211b809e2fe738d606117cf26e074262b91cef`，一致
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 阻塞: 0.1.0–0.8.0 是 ad-hoc 签名，Team 闸拒绝，需手动更新一次

## 已知问题
- 自更新器竞争: 用户在 app 里点过下载、还没退出时，Squirrel.Mac 已经拿着那份包等退出安装（`autoInstallOnAppQuit`）。
  我们装上更新的版本后，若它在退出时再装旧的那份，就会回退。运行中一轮未做，未验证
- RC 轨一键端到端未做：今天最新发布的是 1.0.2（正式版），没有能被推到的 RC

## 如何复验
```bash
gh release download v1.0.2 --repo RunMaestro/Maestro --pattern 'maestro-1.0.2-arm64-mac.zip'
gh release download v1.0.1 --repo RunMaestro/Maestro --pattern 'maestro-1.0.1-arm64-mac.zip'
.claude/skills/coverage-discovery/scripts/check-bundle.sh maestro-1.0.2-arm64-mac.zip
ditto -x -k maestro-1.0.2-arm64-mac.zip new && swift run --package-path application-test channel-verify new/Maestro.app --expect stable
ditto -x -k maestro-1.0.1-arm64-mac.zip prev && swift run --package-path application-test channel-verify prev/Maestro.app --expect stable
```

2026-11-11 实测:
- 1.0.1: `detected channel → stable`，`winning source GitHub`，`latest 1.0.2`，
  `download https://github.com/RunMaestro/Maestro/releases/download/v1.0.2/maestro-1.0.2-arm64-mac.zip`，`status UPDATE → 1.0.2`
- 1.0.2: `detected channel → stable`，`status up to date`
- 1.1.0-RC（只取 Info.plist 的 bundle）: `detected channel → stable`，`latest 1.0.2`，`status up to date`
- 0.8.0（ad-hoc，只取 Info.plist 的 bundle）: `detected channel → stable`，`status UPDATE → 1.0.2`
- `check-bundle.sh` 1.0.2 zip: `TeamIdentifier=4N4DQ24LED`，`codesign-verify-exit=0`，`spctl source=Notarized Developer ID`，
  `updater electron-updater owner=RunMaestro repo=Maestro provider=github`

## 建议下一步
1. 主会话: 两轮一键端到端（未运行 / 运行中），第二轮在 app 里点下载让 `~/Library/Caches/maestro-updater/pending/` 出现
   `update-info.json`，看 `local stash hit`，再用更旧的停放包测 Squirrel.Mac 退出安装是否回退
2. 下一个 RC 成为最新发布时，用开了开关的副本做一次 RC 轨一键端到端

## 历史与实测
- 2026-11-11 加 changelog recipe。旧路径（`GitHubReleasesSource` 的结构化日志）1.0.2 只有 6 条、没有小标题（Highlights 的 4 段丢了）。
  全部 103 个 release 正文用新旧两种读法回放：stable 共 66 个版本，新读法 1123 条；1.0.2 6→10、1.0.1 49→54、1.0.0 23→31、
  0.17.2 1→18、0.13.x 不变（旧版本段落照样切掉），0.1.x–0.9.x 多数不变。唯一多出的非改动内容是 0.15.1 的一段 🙏 安全致谢。
  当时 40 条一页里有 13 个 stable release，RC 穿插其间
- 2026-11-11 接 RC 轨。真机 1.0.2 开关两态见 Channel 详情；开着时 `channel-verify` `ChannelBinding beta`、`latest 1.0.2`、up to date，
  关后 `ChannelBinding stable`。最新 100 个 release 的 tag 全部符合 beta rule，列表深度下限 1
