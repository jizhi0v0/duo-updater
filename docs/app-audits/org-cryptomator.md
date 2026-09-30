# Cryptomator

## 基本信息
- Bundle ID: `org.cryptomator`
- Team ID: `YZQJQUHA3L`（Skymatic GmbH）
- 观测版本: `1.19.3`（`CFBundleVersion` `6495` 是 CI 的 revision 号，不参与比较）
- 自更新机制: 自研（JavaFX/jpackage，无 Sparkle）。dmg 构建的 `Contents/app/Cryptomator.cfg`
  写着 `-Dcryptomator.updateMechanism=org.cryptomator.macos.update.DmgUpdateMechanism`：
  读 `api.cryptomator.org/connect/apps/desktop/latest-version?format=1`，下载本架构 dmg、校验
  sha256、`codesign --verify --deep --strict` + `spctl`，退出后删掉旧 bundle 再 `mv` 新的进去。
  需用户在 app 内确认；回退路径（`FallbackUpdateMechanism`）只读同一端点的无参版本并打开官网下载页
- 分发: GitHub Releases（`cryptomator/cryptomator`）/ Homebrew cask `cryptomator`（`auto_updates` 未设，
  cask 的 url 就是 GitHub 的 arm64 dmg）/ 官网下载页
- 开源: 是。渠道、版本方案、端点均读自仓库源码

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（仅 brew 装的副本）| — | ✓      | —           |
| **beta**（alpha/beta/rc） | — | — | — | ✗ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（channel-verify 实测，见「如何复验」）。
经 Homebrew 安装的副本由排在前面的 `HomebrewCaskSource` 应答（通用源，按 Caskroom 出处闸），两边版本同源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.cryptomator` | 共享 | — | `/releases/latest` + tag 锚 `^X.Y.Z$` | ✓ |
| alpha/beta/rc | `org.cryptomator` | 共享 | Info.plist 里没有 | GitHub prerelease | ✗ 未接入 |

- settled from source: `.github/workflows/RELEASE.md` on `develop`——tag 解析为
  alpha / beta / rc / stable 四类；非 stable 的在 GitHub 上标 prerelease（最近 30 个 release 实测一致，
  如 `1.19.3-rc1`、`1.19.0-beta2`、`1.19.0-alpha2`）。
- settled from source: `.github/workflows/mac-dmg.yml`——`CFBundleShortVersionString` 只写
  `semVerNum`（Major.Minor.Patch），**后缀被剥掉**，所以装着的 `1.19.3-rc1` 在 Info.plist 里也是
  `1.19.3`。同一 workflow 把带后缀的完整版本写进 `Cryptomator.cfg` 的 `-Dcryptomator.appVersion=`；
  1.19.3 稳定版实测为 `1.19.3`。rc 包里是否为 `1.19.3-rc1` **未验证**（没下 rc 包）。这是日后接
  prerelease 轨唯一可能的渠道信号，需要真包确认 + 扫描端读取支持。

## 更新检测
- 源: `cryptomator/cryptomator` GitHub Releases，`/releases/latest`（GitHub 该端点排除 prerelease）
- 版本方案: tag 无 `v` 前缀（`1.19.3`），== `CFBundleShortVersionString`。`versionPattern`
  `^([0-9]+(?:\.[0-9]+)+)$` 两端锚定，`1.19.3-rc1`、`1.19.0-rc1.1` 这类 tag 不会被截成数字。
- 厂商端点对照（2026-09-29）: `GET https://api.cryptomator.org/connect/apps/desktop/latest-version`
  → `{"mac":"1.19.3","win":"1.19.3","linux":"1.19.3"}`；加 `?format=1` 另带 `assets[]`，其中
  `Cryptomator-1.19.3-arm64.dmg` 的 `downloadUrl` 就是 GitHub release 资产，digest
  `sha256:0bfe8c6a…4f23` 与下载到的 dmg 及 release body 里的校验和一致。请求不带任何设备标识，
  没有按设备灰度。按 `RELEASE.md`，这个文件（S3 上的 `latest-version.json`）是发版后**人工**更新的，
  所以它只可能晚于 GitHub，不会领先。
- 注意事项 —— **按平台发布**: 版本号全平台共用，但 hotfix 可能只发某些平台：`1.18.1`（标题
  "Windows only"，只有 exe/msi）、`1.15.3`（"Hotfix, Linux Only"，只有 AppImage/deb）都是非
  prerelease 的正式 release、没有 dmg。`installAssetPattern` 同时充当 macOS 闸：latest 没有 dmg 时
  `GitHubReleasesSource` 改走列表、跳过无 dmg 的 release，不会报一个装不上的幽灵更新。
- 注意事项 —— **按架构缺包**: `1.16.0` 只有 arm64 dmg（x64 包因 issue #3838 撤下）。pattern 钉
  arm64，Intel Mac 上这条 rule 给不出可装资产（见「一键安装」）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | `DmgUpdateMechanism` 只下载整包 dmg 再替换（读 `cryptomator/integrations-mac` 源码） | `?format=1` 与 release 资产都只有整包 dmg（2026-09-29） | — |

## 按 OS 分轨
- `LSMinimumSystemVersion` = `11`（1.19.3 与 1.19.2 真包均如此）。端点和 release 都不声明 min/max
  系统版本。无可读的逐版本 OS 窗口。

## FUSE 依赖
- `.app` 本身不带 FUSE 驱动（`Contents/app/mods` 里只有 `jfuse-mac` 绑定库）。arm64 dmg 附一个
  `FUSE-T.webloc` 链接；按 `RELEASE.md`，x64 dmg 走 macFUSE。一键更新只替换 `Cryptomator.app`，
  不会安装、升级或卸载 FUSE-T / macFUSE。
- 新版本是否会抬高所需的 FUSE-T/macFUSE 版本：**没查**。release notes 里历史上出现过 FUSE 版本
  相关修复（`1.15.3`，Linux），macOS 侧未见，但未系统核对。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 经 `GitHubMarkdownParser` 结构化带回）
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 1.19.2 检查）: ✓ 分节保留 — `What's New 🎉` / `Bugfixes 🐛` / `Other Changes 📎`，12 条；只带回最新一版的说明（1 个条目）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `Cryptomator-{v}-arm64.dmg`（`-x64.dmg` 是 Intel 兄弟；每个资产另有 `.asc` GPG 签名）
- Pattern: `^Cryptomator-[0-9.]+-arm64\.dmg$`, kind `.dmg`（排除 `.asc`、`-rcN`/`-betaN` 名字和 x64）
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；厂商自己的更新端点给的也是同一个文件）
- 包验（2026-09-29，1.19.3 挂载）: `org.cryptomator` / `1.19.3` (`6495`)，`lipo` = arm64 单架构，
  `Developer ID Application: Skymatic GmbH (YZQJQUHA3L)`，hardened runtime，
  `spctl -a -t exec`: accepted / Notarized Developer ID。1.19.2 真包同 Team `YZQJQUHA3L`。
- 阻塞: Intel Mac 没有一键（pattern 只收 arm64）。
- 端到端（2026-09-29）: 装 1.19.2 → `duo check` 报 `1.19.2 → 1.19.3 [GitHub, in-place]` → `duo install --yes`
  走完 backup / download / verifyingCodeSignature / install → 装好的包 `1.19.3`、Team `YZQJQUHA3L`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized

## 已知问题
- prerelease 轨（alpha/beta/rc）未接入：Info.plist 剥掉了后缀，装着 rc 的机器会被当成同号 stable。
  rc 装的 `1.20.0` 在 stable `1.19.3` 面前是「更新」的一方，不会被降级提示；stable `1.20.0` 发布后
  它显示为已是最新（实际是 rc）。
- Intel Mac 只检测不一键（arm64 pin）。

## 如何复验
```
# GET https://api.github.com/repos/cryptomator/cryptomator/releases/latest → 1.19.3
# 挂载 Cryptomator-1.19.3-arm64.dmg → org.cryptomator / 1.19.3 / Team YZQJQUHA3L / Notarized
swift run --package-path application-test feed-discover Cryptomator-1.19.3-arm64.dmg
#   → Cryptomator [org.cryptomator] 1.19.3 (6495) — no Sparkle and no electron-builder update config
swift run --package-path application-test channel-verify Cryptomator-1.19.3-arm64.dmg --expect stable
#   → detected stable, winning source GitHub, latest 1.19.3, status up to date
swift run --package-path application-test channel-verify Cryptomator-1.19.2-arm64.dmg --expect stable
#   → detected stable, winning source GitHub, latest 1.19.3, status UPDATE → 1.19.3
```

## 建议下一步
1. Intel 一键：把 pattern 放宽为 `(?:arm64|x64)`（arch 选择由 `installableAsset` 按本机决定），
   前提是先对 x64 dmg 做同样的签名/公证包验。
2. prerelease 轨：先下一个 rc 包确认 `Cryptomator.cfg` 的 `cryptomator.appVersion` 带后缀，再评估。
