# Neovide

## 基本信息
- Bundle ID: `com.neovide.neovide`
- Team ID: `X8CNW77992`
- 观测版本: `0.16.2`（`CFBundleVersion` 固定为 `20230908.235224`，不参与比较）
- 自更新机制: 无（没有 `SUFeedURL`，`feed-discover` 结论为 no Sparkle and no electron-builder update config）
- 分发: GitHub Releases（`neovide/neovide`）/ Homebrew cask `neovide-app`（url 指向同一 GitHub 资产）
- 开源: 是。以下版本方案、渠道均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | ✓*       | —   | ✓      | —           |
| **nightly** | —       | —        | —   | ✗      | —           |

\* cask 装的副本走通用 Homebrew 源；本次未单独验证。

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.neovide.neovide` | 共享 | — | tag 锚 `^X.Y.Z$` | ✓ |
| nightly | `com.neovide.neovide` | 共享 | 无 | — | ✗ |

nightly: settled from source: `.github/workflows/nightly.yml` on `main`——每日 cron 删除并重建
tag `nightly` 的 release（`prerelease: true`）。2026-09-29 挂载 nightly 的
`Neovide-aarch64-apple-darwin.dmg`：bundle id、`CFBundleShortVersionString`（`0.16.2`）、
`CFBundleVersion`、Team 全部与 stable 0.16.2 相同，没有任何可区分信号 → D 类，不接入。
`versionPattern` 不收 `nightly` 这个 tag，且规则 `usePrereleases = false`。

## 更新检测
- 源: `neovide/neovide` GitHub Releases
- 版本方案: settled from source: `extra/osx/Neovide.app/Contents/Info.plist` on `main`——
  这是 `macos-builder/run` 原样复制进包的模板，`CFBundleShortVersionString` 由维护者在每次
  「prepare release」提交里手动改（该文件提交历史里 0.13.3 起每个版本都有对应的 bump 提交），
  `CFBundleVersion` 一直是 `20230908.235224`。tag 是裸版本号 `0.16.2`，等于包的
  `CFBundleShortVersionString`（0.16.2 与 0.16.1 两个真包均已挂载核对）。
- 资产名: settled from source: `.github/workflows/build.yml` on `main`——
  `Neovide-aarch64-apple-darwin.dmg` / `Neovide-x86_64-apple-darwin.dmg`，无版本号。
  0.13.2 起一直是这个名字；0.13.1 及更早是 `neovide.dmg.zip` / `Neovide.dmg.zip` / `Neovide.app.zip`，pattern 不收，都不是最新，不影响。
- 注意事项: 若某次发版漏改 Info.plist 模板，tag 会高于包里的版本，表现为装完仍提示更新
  （未发生过，只是方案本身的脆弱点）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | app 没有自更新器（无 `SUFeedURL`） | release 资产只有整包 dmg（2026-09-29） | — |

## 按 OS 分轨
- 包的 `LSMinimumSystemVersion` = `10.11`（与 `build.yml` 的 `MACOSX_DEPLOYMENT_TARGET` 一致）；
  release 无 min/max 系统版本字段。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 经 `GitHubMarkdownParser` 结构化带回）
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 0.16.1 检查）: ✓ 分节保留 — `Bug Fixes` / `Docs`，5 条；只带回最新一版的说明（1 个条目）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `Neovide-aarch64-apple-darwin.dmg`（`Neovide-x86_64-apple-darwin.dmg` 是 Intel 兄弟，无 universal）
- Pattern: `^Neovide-aarch64-apple-darwin\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；Homebrew cask 下的也是同一个包）
- 包验（2026-09-29，0.16.2 挂载）: `com.neovide.neovide` / `0.16.2`，Team `X8CNW77992`，
  hardened runtime，`spctl accepted / Notarized Developer ID`，arm64 单架构；
  dmg sha256 `5eb745ea…6b26` 与 GitHub 资产 digest 相同
- 端到端（2026-09-29）: 装 0.16.1 → `duo check` 报 `0.16.1 → 0.16.2 [GitHub, in-place]` → `duo install --yes`
  走完 backup / download / verifyingCodeSignature / install → 装好的包 `0.16.2`、Team `X8CNW77992`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized

## 已知问题
- nightly 轨与 stable 共享 bundle id 且包内无区分信号，未覆盖（见上）。

## 如何复验
```
# GET https://api.github.com/repos/neovide/neovide/releases/latest → 0.16.2
# 挂载 Neovide-aarch64-apple-darwin.dmg (0.16.2) → com.neovide.neovide / 0.16.2 / Team X8CNW77992
swift run --package-path application-test channel-verify <0.16.2 的 dmg> --expect stable
#   → winning source GitHub, latest 0.16.2, status up to date
swift run --package-path application-test channel-verify <0.16.1 的 dmg> --expect stable
#   → winning source GitHub, latest 0.16.2, status UPDATE → 0.16.2
```

## 建议下一步
无。stable 检测 + 一键 + changelog 均已覆盖；nightly 无检测信号，不做。
