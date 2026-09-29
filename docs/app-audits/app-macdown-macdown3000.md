# MacDown 3000

## 基本信息
- Bundle ID: `app.macdown.macdown3000`（原版 MacDown 是 `com.uranusjr.macdown`，两者不同，互不覆盖）
- Team ID: `EDUS6QCV5X`
- 观测版本: `3000.0.7`（`CFBundleVersion` `1429`，不参与比较）
- 自更新机制: 3000.0.7 及更早的正式版无（包里没有 `SUFeedURL`、没有 Sparkle.framework）；
  仓库 2026-08-04 合入 Sparkle 2（#556），`3000.0.8-rc.1` 包里已声明
  `SUFeedURL = https://macdown.app/sparkle/macdown3000/stable/appcast.xml` 并带 Sparkle.framework
- 分发: GitHub Releases（`schuyler/macdown3000`）/ Homebrew cask `macdown-3000`（非 `auto_updates`，
  url 指向同一个 GitHub dmg）；无 MAS
- 开源: 是。以下版本方案、渠道均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ○（feed 尚未上线） | ✓（通用源，未单独验证） | — | ✓ | — |
| **beta/rc**  | ○（Sparkle channel，见下） | — | — | ○ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: brew 装的副本是 **Homebrew**；
其余是 **GitHub**（3000.0.7 包无 `SUFeedURL`，`channel-verify` 实测 winning source GitHub）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.macdown.macdown3000` | 共享 | — | tag 锚 `^vX.Y.Z$` + GitHub `prerelease=false` | ✓ |
| beta/rc | `app.macdown.macdown3000` | 共享 | 短版本号带 `-beta.N` / `-rc.N`（`3000.0.8-rc.1` 包实测） | GitHub prerelease；Sparkle 侧由偏好 `updateIncludesPreReleases` 经 `allowedChannelsForUpdater:` 选 channel | ○ 未接入 |

settled from source: `.github/workflows/release.yml` on `main`——版本号取自 tag 去掉 `v`，
版本串含 `-(beta|alpha|rc)` 即发成 prerelease。仓库 14 个 release（2026-09-29）中 6 个是
prerelease（`-beta.N` / `-rc.N`），全部被正确标成 prerelease。本 rule 只跟 stable；
prerelease 轨是已知缺口。

## 更新检测
- 源: `schuyler/macdown3000` GitHub Releases，`/releases/latest`
- 版本方案: settled from source: `.github/workflows/release.yml` on `main`——tag `v<version>`，
  dmg 名 `MacDown-<version>.dmg`，`marketing-version` 取同一个 `VERSION`。tag `v3000.0.7` →
  `3000.0.7` == 包的 `CFBundleShortVersionString`。
- 资产: 每个 release 一个 dmg + 一个 `.sha256`；`MacDown-3000.0.7.dmg` 的 sha256
  `62296564…1c98` 与同 release 的 `.sha256` 文件一致（2026-09-29）。
- Sparkle 过渡: 仓库源码 `MacDown/MacDown-Info.plist` 已写 `SUFeedURL`，`3000.0.8-rc.1` 包里也有；
  2026-09-29 请求该地址得到 HTTP 404（GitHub Pages 404 页）。feed 上线后，带 `SUFeedURL` 的副本
  由 `SparkleAppcastSource` 先应答（`SourceStack` 里 Sparkle 在 GitHub 之前）；3000.0.7 及更早的
  副本仍只能由本 rule 覆盖。feed 上线后是否有 `<sparkle:channel>` 全标记问题未验证。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 3000.0.7 无；rc 起有 Sparkle 2 | 无 | 不能 |
| 证据 | 3000.0.7 包无 Sparkle.framework（2026-09-29 挂载） | release 资产只有整包 dmg；appcast 404（2026-09-29） | — |

## 按 OS 分轨
- 包的 `LSMinimumSystemVersion` = `11.0`；cask 无额外 `depends_on` 版本。release 无分 OS 资产。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 经 `GitHubMarkdownParser` 结构化带回；
  `channel-verify` 显示 release history 1 条、inline HTML 0 字符、changelogURL 指向 release 页）
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 3000.0.6 检查）: ✓ 分节保留 — `Added` / `Changed` / `Fixed` / `Security` / `Documentation` / `Infrastructure` / `Known Issues`，53 条；只带回最新一版的说明（1 个条目）
- 跟随 channel: 只跟 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `MacDown-{v}.dmg`，universal（`x86_64 arm64`）
- Pattern: `^MacDown-[0-9]+(?:\.[0-9]+)+\.dmg$`, kind `.dmg`（不收 `-beta.N` / `-rc.N` 的 dmg）
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；Homebrew cask 指向同一个 dmg）
- 包验（2026-09-29，v3000.0.7 挂载只读）: `app.macdown.macdown3000` / `3000.0.7`，
  `Developer ID Application: Schuyler Erle (EDUS6QCV5X)`，hardened runtime，
  `spctl accepted / source=Notarized Developer ID`
- 端到端（2026-09-29）: 装 3000.0.6 → `duo check` 报 `3000.0.6 → 3000.0.7 [GitHub, in-place]` → `duo install --yes`
  走完 backup / download / verifyingCodeSignature / install → 装好的包 `3000.0.7`、Team `EDUS6QCV5X`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized

## 已知问题
- prerelease 轨（`-beta.N` / `-rc.N`）未接入。
- Sparkle feed 上线后需复验：`feed-discover` 对带 `SUFeedURL` 的包应报 `declared`，且 stable
  副本能匹配到 feed 里的条目（未验证）。

## 如何复验
```
# GET https://api.github.com/repos/schuyler/macdown3000/releases/latest → v3000.0.7
# 挂载 MacDown-3000.0.7.dmg → app.macdown.macdown3000 / 3000.0.7 / Team EDUS6QCV5X / universal
swift run --package-path application-test feed-discover MacDown-3000.0.7.dmg
#   → no Sparkle and no electron-builder update config
swift run --package-path application-test channel-verify MacDown-3000.0.7.dmg --expect stable
#   → winning source GitHub, latest 3000.0.7, status up to date
swift run --package-path application-test channel-verify MacDown-3000.0.6.dmg --expect stable
#   → winning source GitHub, latest 3000.0.7, status UPDATE → 3000.0.7
```

## 建议下一步
1. `macdown.app/sparkle/macdown3000/stable/appcast.xml` 上线后跑 `feed-discover`，确认 Sparkle 源接手、
   两源版本一致。
2. prerelease 轨如需接入：rc/beta 与 stable 共享 bundle id，短版本号带 `-rc.N` / `-beta.N` 后缀，
   需先在真实 rc 包上确认 `ReleaseChannel.detect()` 的判定再加 rule。
