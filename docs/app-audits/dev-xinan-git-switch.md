# Git Switch

## 基本信息
- App: Git Switch — 在菜单栏切换全局 git `user.name` / `user.email` 的 app（`LSUIElement`），Swift，开源
- Bundle ID: `dev.xinan.git-switch`
- 仓库: `anxndsgn/git-switch`（默认分支 `main`）
- Team ID: `9FX2RB5LD6`（Developer ID + 公证）
- 观测版本: 1.0.1（`CFBundleVersion` 1）；观测日期: 2026-10-19
- 自更新机制: 无。没有 `SUFeedURL`、没有 Sparkle，主执行文件里没有 GitHub / 更新检查地址
- 分发: 只有 GitHub Releases。没有 Homebrew cask（`brew search --cask git-switch` 无结果），没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**

## Channel 详情

只有一条轨，settled from source: `.github/workflows/release.yml` on `main`。推 `v*` tag 触发 release，
`gh release create` 不带 `--prerelease`；到 2026-10-19 只有 v1.0.1 一个 release、一个 tag。

## 更新检测
- 源: `anxndsgn/git-switch` GitHub Releases（`/releases/latest`）
- 版本: `^v([0-9]+(?:\.[0-9]+)+)$`。⚠️ 版本号是 Xcode 工程里写死的 `MARKETING_VERSION`（`git-switch.xcodeproj`），
  release workflow 不用 tag 盖章；两者一致靠厂商手动同步。v1.0.1 = 1.0.1（真包核对过）
- 实测（2026-10-19，channel-verify，真包 1.0.1）: `winning source GitHub`，`latest 1.0.1`，`status up to date`

## 按架构 / 按 OS 分轨
- 只有 arm64；`LSMinimumSystemVersion` = `13.0`。release 不声明上下限，资产名不带架构

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（bundle 里无 Frameworks，strings 无更新地址） | release 只有 zip 与 dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | — |
| 证据 | 没有更新器 | — | — |

## Changelog
- 来源: GitHub Release body
- 结构化: ✗。channel-verify `changelog pane`: `raw inline notes, 73 chars, no structure`。release workflow 用
  `--generate-notes`，v1.0.1 的正文只有一行 `**Full Changelog**: …/commits/v1.0.1`。仓库没有 CHANGELOG 文件
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要（厂商没有可抓的说明）

## 一键安装
- 状态: 支持
- 端到端（2026-10-19）:
  - 第一轮（未运行）：厂商只有 1.0.1 一个 release，「上一版」用 1.0.1 包改 `Info.plist` 版本号为 1.0.0 代替，Team ID 不变。
    `duo check` → `1.0.0 → 1.0.1 [GitHub, in-place]`；`duo install --yes --json` → `outcome: installed`，`route: vendor`，
    `bytesDownloaded: 5076974`，4.7 s。之后为 1.0.1，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted /
    Notarized Developer ID，Team `9FX2RB5LD6`，`diff -r --no-dereference` 与厂商包一致
  - 第二轮（运行中）：改过版本号的副本封印已破、不能启动；app 没有自更新器，不存在碰撞。装好的 1.0.1 启动后
    `duo restart "Git Switch"` → `restarted`，进程换了新 PID
- 格式: zip（包根就是 `Git Switch.app`）。同一 release 还有一个 dmg（app + `/Applications` 链接 + `Install Guide.txt`），规则不用它
- Pattern: `^Git-Switch-v[0-9]+(?:\.[0-9]+)+\.zip$`，kind `.zip`
- 校验: GitHub 资产 `digest`（`sha256:48fc9723…994a2a`）与下载文件 `shasum -a 256` 相等；规则无需额外配置
- **读的是**: 人人可手动下载的 GA（GitHub latest release）
- 嵌套: 无
- 阻塞: 无

## 已知问题
- **tag 与 `MARKETING_VERSION` 分开维护。** 厂商打了新 tag 却没改工程里的版本号时，装好的新包仍报旧版本，这一行会一直显示有更新；
  反过来改了版本号、tag 打错则读不到。到 2026-10-19 两边一致

## 建议下一步
1. 无。下一个 release 出来后 `duo verify` 夜扫会覆盖

## 如何复验

```sh
gh release download v1.0.1 -R anxndsgn/git-switch -p '*.zip'
ditto -x -k Git-Switch-v1.0.1.zip x
plutil -p "x/Git Switch.app/Contents/Info.plist" | grep -E 'Identifier|Version|LSUIElement'
codesign -dv "x/Git Switch.app" 2>&1 | grep Team
swift run --package-path application-test channel-verify "x/Git Switch.app"
```
