# Flycut

## 基本信息
- App: Flycut — 菜单栏剪贴板管理器（`LSUIElement=1`），开源
- Bundle ID: `com.generalarcade.flycut`
- 仓库: `TermiT/Flycut`（默认分支 `master`）
- Team ID: `S8JLSG5ES7`（1.8 起每个 release 都是这个 Team；1.8/1.8.x 证书名 Gennadiy Potapov，1.9.x 为 General Arcade (Pte. Ltd.)，Team 相同）
- 观测版本: 1.9.6（`CFBundleVersion` 9）；观测日期: 2026-10-16
- 自更新机制: 无。没有 `SUFeedURL`，主二进制里没有任何 http(s) 地址或更新相关字符串
- 分发: GitHub Releases（zip）；Homebrew cask `flycut`（`auto_updates` 未设，url 指向同一 GitHub zip，sha256 `bc1a73b9…` 与下载的 1.9.6 zip 相同）；
  Mac App Store（id 442160987，同 bundle id，商店版本 1.9.6）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（仅 brew 装的副本）| ✓（商店副本）| ✓ | — |

当前生效源（直接下载的副本）: **GitHub**（channel-verify 实测）。brew 装的副本由 `HomebrewCaskSource` 应答（只认本机 Caskroom 里有的 cask）；
商店副本由 MAS 源负责，`GitHubReleasesSource` 对 `isMASApp` 直接返回 nil。

## Coverage checklist

- **Bundle id**: 1.8、1.8.2、1.9.3、1.9.4、1.9.6 五个真包都是 `com.generalarcade.flycut`；没有改名、没有别的 edition。
  仓库里的 `Flycut-iOS` 是 iOS app，不是本 app。
- **轨道**: 只有正式版。6 个 tag（`1.8`、`1.8.1`、`1.8.2`、`1.9.3`、`1.9.4`、`1.9.6`，`git ls-remote --tags` 实测）全是非 prerelease；
  没有 beta/nightly。master 上的 `.github/workflows/release.yml` 写死 `prerelease: false`。
- **版本范围**: tag 都是裸版本号，有两段式（`1.8`），与 `CFBundleShortVersionString` 一致。release.yml 从 `v*` tag 出版本并去掉 `v`，
  所以 pattern 是 `^v?([0-9]+(?:\.[0-9]+)+)$`；实测读出全部 6 个 tag 与 `2.0`、`v2.0.1`，拒绝 `2.0-beta`、`2.0.0-rc.1`、`1.9.7b1`。
- **宿主下限**: 1.9.6 为 universal（x86_64 arm64），`LSMinimumSystemVersion` 10.10，低于我们的下限。
- **一键 best-effort**: 1.9.3 / 1.9.4 / 1.9.6 都是 Notarized Developer ID、Team 相同，Team 闸都放行；1.8 的 `spctl` 只给 `Developer ID`（未公证），
  但一键装的永远是最新版（1.9.6，已公证）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.generalarcade.flycut` | — | — | — | ✓ |

## 更新检测
- 源: `TermiT/Flycut` GitHub Releases，`/releases/latest`
- 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`
- 注意事项: 1.9.6（2020-12）之后没有新 release，但 master 在 2026-08 仍有提交：`CHANGELOG.md` 已写好 `## 1.9.7 (2026-08-04)`，
  `RELEASE_SETUP.md` 说明下一版用 `v1.9.7` tag 由 release.yml 发布，资产是单个 `Flycut.dmg`（不是 zip）。截至 2026-10-16 还没有 `v1.9.7` tag。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见上） | 每个 release 只有一个完整 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | — | — |
| 证据 | 没有更新器 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-16，channel-verify `changelog pane`，1.9.4 与 1.9.6 两次一致）: `source structured: 1 entries; newest 1.9.6: 2 items,
  headings []; first items ["Support for Apple Silicon (ARM64)", "Bezel closes when it loses focus"]`
- 厂商正文就是无小标题的 bullet 列表，`headings []` 不是被压平
- 跟随 channel: —（单轨）
- Recipe 状态: 暂不需要。release.yml 会在正文后追加 `## Installation`（下载/授权步骤，每版相同）；第一份这样的 release 出来后再看要不要加
  `ChangelogRecipe` 的 `skipSections: ["Installation"]`（这一条是读 workflow 得出的，未在真实 release 上看到）

## 一键安装
- 状态: **支持**（按 Team 闸）
- 格式: zip（universal；`unzip` 得到 `Flycut.app`）
- Pattern: `^Flycut(?:\.app)?(?:\.[0-9][0-9A-Za-z.-]*)?\.(?:zip|dmg)$`，kind `.zip`。
  匹配现有的 `Flycut.<v>.zip`、`Flycut.app.<v>.zip`（1.8.x），也匹配 release.yml 将来上传的 `Flycut.dmg`
- **已知限制（有意为之）**: 一条规则只有一个 installer kind。只认 zip 的话，`Flycut.dmg` 的 release 会因为没有匹配资产被跳过，
  检测停在 1.9.6 并报「已是最新」；所以 pattern 收 dmg，保证检测正确。代价是：第一个 dmg release 出来后，在把 kind 改成 `.dmg` 之前，
  一键会把 dmg 当 zip 解，在解包阶段失败（不会替换 app）。选 `.zip` 是因为今天唯一能跑的端到端（1.9.4 → 1.9.6）用的是 zip。
- 嵌套: `Contents/Library/LoginItems/FlycutHelper.app`（`com.generalarcade.flycuthelper`，`LSBackgroundOnly=true`）。
  源码 `FlycutHelper/AppDelegate.m`：算出外层 app 路径、`launchApplication:`、立刻 `terminate`。不常驻，换包后不会跑旧代码。
  1.8.x 没有这个 helper
- 校验: 资产上传于 2025-06 之前，GitHub 没有 `digest`；按 Team 闸安装。1.9.6 zip `shasum -a 256` = `bc1a73b9…74336862`，与 cask 的 sha256 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`）
- 上一版 Team: 1.9.4 = `S8JLSG5ES7`、Notarized（实测），与 1.9.6 相同
- 真机端到端：待主会话执行（1.9.4 → 1.9.6）
- 阻塞: 无

## 已知问题
- 见上「已知限制」：dmg 版发布后要把 kind 改成 `.dmg`。
- 1.9.7 的 Developer ID 包是否沿用 `S8JLSG5ES7`、是否公证，取决于仓库是否配置了签名与公证 secrets；没配时 release.yml 出 ad-hoc 包，Team 闸会拒绝。未验证。

## 建议下一步
1. 第一个 `v*` release 出来后：下载 `Flycut.dmg`，核 Team / 公证，把 kind 改成 `.dmg`（pattern 已经收），重跑 channel-verify 与一键端到端。
2. 同时看 `## Installation` 小节在 pane 里的样子，决定是否加 `ChangelogRecipe` 去掉它。

## 如何复验
```
swift run --package-path application-test channel-verify <1.9.4 的 Flycut.app> --expect stable   # → GitHub，UPDATE → 1.9.6
swift run --package-path application-test channel-verify <1.9.6 的 Flycut.app> --expect stable   # → GitHub，up to date
codesign -dvv <Flycut.app>        # → TeamIdentifier=S8JLSG5ES7
spctl -a -vv <Flycut.app>         # → accepted, source=Notarized Developer ID
```
