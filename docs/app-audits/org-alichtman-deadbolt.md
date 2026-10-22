# Deadbolt

## 基本信息
- App: Deadbolt — 跨平台的文件加密工具（Electron），MIT
- Bundle ID: `org.alichtman.deadbolt`（0.1.0、1.0.0、2.1.0、2.1.1 真包相同）
- 仓库: `alichtman/deadbolt`（默认分支 `main`）
- Team ID: `BF3UMC9FSZ`（2.1.1 起；`codesign --verify --deep --strict` 通过，spctl `Notarized Developer ID`）。各版本见「覆盖清单」
- 观测版本: 2.1.1（tag `v2.1.1`，2026-02-25 发布）；上一版 2.1.0；观测日期: 2026-10-22
- 自更新机制: **无**。bundle 里有 electron-builder 生成的 `Contents/Resources/app-update.yml`（`provider: github`），但 settled from source: `src/main/main.ts` 在 `v2.0.2`、`v2.1.0`、`v2.1.1` 三个 tag 上 `import { autoUpdater } from 'electron-updater'` 和 `new AppUpdater()` 都是注释掉的（`// TODO: Implement auto-updater`）。2.1.1 的 `app.asar` 里 `autoUpdater` / `checkForUpdates` 各只有 1 处命中，都在 source map 里那段注释；`app.asar.unpacked/node_modules` 只有 `@node-rs`，没有 electron-updater。`electron-builder.yml` 设了 `dmg.writeUpdateInfo: false`，所有 release 都没有 `latest-mac.yml`
- 分发: GitHub Releases；Homebrew cask `deadbolt`（2.1.1，`auto_updates` 未设，url 指向 GitHub 的 arm64 dmg）。没有 MAS。另有 npm 包 `deadbolt-cli`（`main` 上 v2.1.1 之后加的命令行工具，不是 `.app`，不在本规则范围）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源） | — | ✓  | —           |

当前生效源: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 2.1.1 arm64 dmg: `review electronProviderNeedsConstruction`——`app-update.yml` 是 github provider，没有可直接取的 `*-mac.yml`；release 里也确实没有，`ElectronManifestSource` 无从接手。

## 覆盖清单
- 各版本的 bundle id / Team（都读真包）:
  - 2.1.1（arm64 dmg、x86_64 dmg）: `org.alichtman.deadbolt`，Team `BF3UMC9FSZ`，Developer ID、notarized
  - 2.1.0（arm64 dmg）: `org.alichtman.deadbolt`，**ad-hoc、linker-signed**（`codesign -dvv`: `Identifier=Electron`、`flags=0x20002(adhoc,linker-signed)`、`TeamIdentifier=not set`；`--verify --deep --strict` 退出 1，"code has no resources but signature indicates they must be present"）
  - 1.0.0（`Deadbolt-1.0.0-mac.zip`，x86_64）: `org.alichtman.deadbolt`，**完全未签名**（"code object is not signed at all"）。release 说明写这一版是在 Linux 上打的 zip
  - 0.1.0（`Deadbolt-0.1.0.dmg`，x86_64）: `org.alichtman.deadbolt`，Apple Development 证书签名，`TeamIdentifier=BF3UMC9FSZ`，codesign 校验通过，spctl `rejected`（不是 Developer ID、没公证）
  - 2.0.0、2.0.2、`v2.0.0-alpha`: 没下真包，签名未读（我的猜测：与 2.1.0 一样是 ad-hoc，因为 2.1.1 的唯一改动是「Add macOS signing in CI」）
- 其他轨: 只有 `v2.0.0-alpha` 一个 prerelease（2025-01），之后再没有 beta / nightly。它的 `package.json` 版本是 `2.0.0-alpha`；`ReleaseChannel.detect` 的版本尾词表里没有 `alpha`（只有 nightly / snapshot / dev 等），按代码会归为 stable，被提示升到 2.1.1——这是想要的结果。未用真包验证
- 版本范围: 每组副本都能被检测（版本模式读得出全部稳定 tag，见下）。一键只对 Team `BF3UMC9FSZ` 的副本放行：2.1.1 及以后、以及 0.1.0；2.0.x、2.1.0、1.0.0 的副本会被 Team 闸拒（`noTeamIdentifier(which: "installed")`），要手动装一次 2.1.1。这是安全的拒绝，不需要 gate；`.publishedDigestOnly` 不适用：下载的 2.1.1 有 Team，装过去就是 `teamIdentifierAppeared`，而且 2.1.0 的签名标识是 `Electron` 不是 bundle id、seal 也不过
- 主机下限: DuoUpdater 只出 arm64（`App/project.yml` `ARCHS: arm64`）；2.1.1 `LSMinimumSystemVersion` 10.15，远低于我们的下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.alichtman.deadbolt` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `alichtman/deadbolt` GitHub Releases，`/releases/latest`
- 版本方案: tag `v2.1.1` → `CFBundleShortVersionString` `2.1.1`、`CFBundleVersion` `2.1.1`（electron-builder 用 `package.json` 的 version）
- `versionPattern` `^v?([0-9]+(?:\.[0-9]+)+)$`。2.0 以前的 tag 不带 `v`（`1.0.0`、`0.1.0`），真包证实是同一个产品、同一个 bundle id（两个 tag 上 `package.json` 的 `build.appId` 也都是 `org.alichtman.deadbolt`），所以收进来而不是排除。实测（Python `re`，同写法）: `v2.1.1 v2.1.0 v2.0.2 v2.0.1 v2.0.0 v0.2.0 1.0.0 0.1.0 v3.0.0 v3.0` 全读出；`v2.0.0-alpha`、`v2.2.0-rc.1`、`v2.2.0-beta` 不匹配
- install pattern `^Deadbolt-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`：匹配 `Deadbolt-2.1.1-arm64.dmg`，不匹配 `Deadbolt-2.1.1.dmg`（x86_64）、`Deadbolt-2.0.0-alpha-arm64.dmg`、1.0.0 的 zip、0.1.0 的 dmg
- channel-verify（2026-10-22，真包）:
  - 2.1.0 arm64 dmg: `winning source GitHub`、`latest 2.1.1`、`status UPDATE → 2.1.1`
  - 0.1.0 dmg: `winning source GitHub`、`status UPDATE → 2.1.1`
  - 2.1.1 arm64 dmg: `status up to date`

## 按架构 / 按 OS 分轨
- 每个 v2 release 两个 mac dmg：`Deadbolt-<v>-arm64.dmg`（`lipo -archs` = arm64）和 `Deadbolt-<v>.dmg`（x86_64），没有 universal（`electron-builder.yml` 的 mac target 是 `x64` + `arm64` 两个）。规则装 arm64 那个。1.0.0、0.1.0 只有 x86_64

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 自更新没启用（上面的源码与 asar） | release 资产只有整包，无 blockmap / yml | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（没有更新器；真机没跑运行中一轮，见一键安装） | 不需要 |
| 证据 | electron-updater 没打包、没调用 | — | — |

## Changelog
- 来源: GitHub release 正文（GitHub 生成的「What's Changed」），经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 2.1.0 起）: `source structured: 1 entries; newest 2.1.1: 1 items, headings []; first items ["Add macOS signing in CI"]`
- 2.1.1 正文就是一个 `## What's Changed` 加一条 PR。条目保留，`by @alichtman in <PR 链接>` 后缀被去掉；那个通用标题没进 headings，也没有被压平成条目（items 里没有标题文字）。`Full Changelog` 链接行不显示
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（对 Team `BF3UMC9FSZ` 的副本）
- 端到端（2026-10-22，本分支 `make cli` 的 duo，app 不运行）:
  - 真 2.1.0（ad-hoc）: `duo check` → `2.1.0 → 2.1.1 [GitHub]`；`duo install` → `Skipping: Deadbolt — the installed copy has no developer Team ID to check the download against`，磁盘仍是 2.1.0、inode 不变
  - 真 0.1.0（同 Team `BF3UMC9FSZ`，Apple Development 证书、未公证、x86_64，没启动）: `duo check` → `0.1.0 → 2.1.1 [GitHub, in-place]`；`duo install` `extracting verifyingCodeSignature installing done installed.` → 2.1.1、可执行文件 inode 变、`TeamIdentifier=BF3UMC9FSZ`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted（Notarized Developer ID）、`diff -r` 与厂商 2.1.1 arm64 包相同
  - **运行中一轮没跑**：没有能正常启动的同 Team 旧版（0.1.0 未公证且是 x86_64，会弹 Gatekeeper / Rosetta）。它没有自更新器，所以不走「先退出再换包」的 StagedRelaunch（那只用于 app 自己更新器已暂存的更新）；运行中一键走通用路径：在活着的进程底下换包，之后 CLI 打印 `Still running the old code: Deadbolt` 和 `duo restart …`，菜单栏 app 按「更新后自动重启」偏好重启（见下方已知问题）。没跑的运行中一轮要测的正是这种「Electron 主进程还活着、bundle 已被换掉」的情形（`Deadbolt Helper*.app` 按需从 `Contents/Frameworks/` 起）
- 格式: dmg（UDZO），根目录 `Deadbolt.app` + `Applications` 软链
- 嵌套: 只有 Electron 的四个 `Contents/Frameworks/Deadbolt Helper*.app`（`LSUIElement`，随主进程起落）；没有 LoginItems / Library / XPCServices；Info.plist 无 `CFBundleDocumentTypes` / `CFBundleURLTypes`；entitlements 只有 `com.apple.security.cs.allow-jit`
- 签名: 2.1.1 `TeamIdentifier=BF3UMC9FSZ`、notarized、hardened runtime。**上一版 2.1.0 没有 Team**，所以从 2.1.0（以及 2.0.x、1.0.0）升级会被 Team 闸拒；第一个能一键升级的场景是 2.1.1 → 下一版，或 0.1.0 → 2.1.1
- 校验: GitHub 资产 `digest`。`Deadbolt-2.1.1-arm64.dmg` `sha256:c8ce77caf427d24730fe0e9abd34cc49ebcb1650952cbbc79a2da180e7c8bee0`，下载后 `shasum -a 256` 相同，100107053 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 阻塞: 无。厂商还没有第二个 Developer ID 签名的 release，真机从「上一版」升级只能用 0.1.0（同 Team，但不是 Developer ID、没公证、x86_64）

## 已知问题
- 2.0.x / 2.1.0 / 1.0.0 的副本能看到更新但不能一键（Team 闸），真机已验证 2.1.0（见上）。要手动装一次 2.1.1
- macOS 上关掉最后一个窗口不退出（`window-all-closed` 在 darwin 上不 quit），运行中换包后要 `duo restart`

## 如何复验
```bash
gh release view v2.1.1 -R alichtman/deadbolt --json assets -q '.assets[]|.name+" "+.digest'
gh release download v2.1.1 -R alichtman/deadbolt -p 'Deadbolt-2.1.1-arm64.dmg'
gh release download v2.1.0 -R alichtman/deadbolt -p 'Deadbolt-2.1.0-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Deadbolt-2.1.0-arm64.dmg Deadbolt-2.1.1-arm64.dmg
swift run --package-path application-test feed-discover Deadbolt-2.1.1-arm64.dmg              # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Deadbolt-2.1.0-arm64.dmg --expect stable   # → GitHub，UPDATE → 2.1.1
swift run --package-path application-test channel-verify Deadbolt-2.1.1-arm64.dmg --expect stable   # → up to date
```

## 建议下一步
1. 厂商发下一个 Developer ID 版本后，补一轮 2.1.1 → 新版的运行中真机。
2. 下一个正式版出来后，复查 `/releases/latest`、资产名仍是 `Deadbolt-<v>-arm64.dmg`、Team 仍是 `BF3UMC9FSZ`，用 2.1.1 → 新版再跑一次一键。
