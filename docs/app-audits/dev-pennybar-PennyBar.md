# PennyBar

## 基本信息
- App: PennyBar — 在菜单栏显示云服务账单（Cloudflare、Vercel、Neon、PlanetScale、Railway 等）的 app（`LSUIElement`），Swift，开源
- Bundle ID: `dev.pennybar.PennyBar`
- 仓库: `anxndsgn/pennybar`（默认分支 `master`）
- Team ID: `9FX2RB5LD6`（Developer ID + 公证，dmg 已 staple）
- 观测版本: 0.1.0（`CFBundleVersion` 1）；观测日期: 2026-10-19
- 自更新机制: 无。没有 `SUFeedURL`、没有 Sparkle，主执行文件里没有 GitHub / 更新检查地址（`strings` 只见各云厂商的 API 地址）
- 分发: 只有 GitHub Releases。没有 Homebrew cask（`brew search --cask pennybar` 无结果），没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**

## Channel 详情

只有一条轨，settled from source: `.github/workflows/release.yml` 与 `scripts/release.sh` on `master`。
推 `v*` tag 触发 release，`gh release create` 不带 `--prerelease`；到 2026-10-19 只有 v0.1.0 一个 release、一个 tag。

## 更新检测
- 源: `anxndsgn/pennybar` GitHub Releases（`/releases/latest`）
- 版本: `^v([0-9]+(?:\.[0-9]+)+)$`。`scripts/release.sh` 用 tag 去掉 `v` 的值盖章 `CFBundleShortVersionString`，
  dmg 名也取自它，所以 tag 与已装版本由构建保证一致（真包 0.1.0 核对过）
- 实测（2026-10-19，channel-verify，真包 0.1.0）: `winning source GitHub`，`latest 0.1.0`，`status up to date`

## 按架构 / 按 OS 分轨
- 只有 arm64；`LSMinimumSystemVersion` = `26.0`。release 不声明上下限，资产名不带架构

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（bundle 里无 Frameworks，strings 无更新地址） | release 只有一个 dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | — |
| 证据 | 没有更新器 | — | — |

## Changelog
- 来源: GitHub Release body
- 结构化: ✗。channel-verify `changelog pane`: `raw inline notes, 71 chars, no structure`。release workflow 用
  `--generate-notes`，v0.1.0 的正文只有一行 `**Full Changelog**: …/commits/v0.1.0`，没有可解析的条目。仓库没有 CHANGELOG 文件。
  以后的 release 若合入 PR，`--generate-notes` 会生成 「What's Changed」 bullet，`GitHubMarkdownParser` 能读
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要（厂商没有可抓的说明）

## 一键安装
- 状态: 支持
- 端到端（2026-10-19）:
  - 第一轮（未运行）：厂商只有 0.1.0 一个 release，「上一版」用 0.1.0 包改 `Info.plist` 版本号为 0.0.9 代替，Team ID 不变。
    `duo check` → `0.0.9 → 0.1.0 [GitHub, in-place]`；`duo install --yes --json` → `outcome: installed`，`route: vendor`，
    `bytesDownloaded: 2133131`，6.0 s。之后为 0.1.0，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted /
    Notarized Developer ID，Team `9FX2RB5LD6`，`diff -r --no-dereference` 与厂商包一致
  - 第二轮（运行中）：改过版本号的副本封印已破、不能启动，所以没有「旧版运行中」可测；app 也没有自更新器，不存在碰撞。
    装好的 0.1.0 启动后 `duo restart PennyBar` → `restarted`，进程换了新 PID
- 格式: dmg（根目录 `PennyBar.app` + `/Applications` 链接）
- Pattern: `^PennyBar-[0-9]+(?:\.[0-9]+)+\.dmg$`，kind `.dmg`
- 校验: GitHub 资产 `digest`（`sha256:9af7e8d8…5f31`）与下载文件 `shasum -a 256` 相等；规则无需额外配置
- **读的是**: 人人可手动下载的 GA（GitHub latest release）
- 嵌套: 无
- 阻塞: 无

## 已知问题
- 只有一个 release，规则对下一个真实版本的读取尚未见过实例；版本盖章来自 tag，风险低

## 建议下一步
1. 无。下一个 release 出来后 `duo verify` 夜扫会覆盖

## 如何复验

```sh
gh release download v0.1.0 -R anxndsgn/pennybar
hdiutil attach -readonly -nobrowse PennyBar-0.1.0.dmg
plutil -p /Volumes/PennyBar/PennyBar.app/Contents/Info.plist | grep -E 'Identifier|Version|LSUIElement'
codesign -dv /Volumes/PennyBar/PennyBar.app 2>&1 | grep Team
swift run --package-path application-test channel-verify /Volumes/PennyBar/PennyBar.app
```
