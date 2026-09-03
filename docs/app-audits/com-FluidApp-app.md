# FluidVoice

## 基本信息
- Bundle ID: `com.FluidApp.app`
- Team ID: `V4J43B279J` (Barathwaj Anandan)
- 观测版本: `1.6.9` (build `20`) — 官方 `v1.6.9` dmg
- 自更新机制: 自研（二进制里写着 GitHub Releases URL）；**无 `SUFeedURL`**、无 Sparkle 框架
- 分发: GitHub Releases / Homebrew cask `fluidvoice`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

`auto_updates: true` 的含义是 Homebrew 把更新责任交回应用自身；即使这份 app
由 brew 安装，`HomebrewCaskSource` 也会按设计返回 nil。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.FluidApp.app` | 单一渠道 | — | tag 必须完整匹配 `vX.Y.Z` | ✓ |

同一仓库还发 `vX.Y.Z-beta.N`（macOS prerelease）和 `windows-vX.Y.Z`（Windows）。
没有独立 bundle id，也没有本机可读的 channel 偏好；beta 靠 tag 锚拒绝，不单独建轨。

## 更新检测
- 源: `GitHubReleasesSource`，`altic-dev/FluidVoice`，`/releases/latest`
- Tag pattern: `^v([0-9]+(?:\.[0-9]+)+)$`
- 版本方案: tag `v1.6.9` → `1.6.9` == 包的 `CFBundleShortVersionString`。
  **不是** `CFBundleVersion`（小计数器 `20`）。short 是三段，folded-build
  fallback 会拼出 `1.6.9.20`，与三段的远程版本对不上，所以不会把 build
  误读进比较。
- 防跨渠道: `$` 锚拒绝 `v1.5.11-beta.3`（否则会截成 `1.5.11`）和
  `windows-v0.0.9`。`/releases/latest` 今天已经不返回这些，但 list fallback
  在「最新 stable 没带 dmg」时会走到同一份列表。
- Repo 改名: `altic-dev/Fluid-oss` 301 到 `altic-dev/FluidVoice`（API
  `full_name` 已是后者）。必须钉规范名，否则 URLSession 跟 301 时丢掉
  `Authorization`，请求掉进匿名额度。见 #135。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 包内无 Sparkle.framework；主二进制无 `SPUUpdater` / `Squirrel` / `electron-updater` | GitHub release 资产只有 `Fluid-oss-<ver>.dmg` 与同名 zip，无 `.delta` / `.patch`（观测 2026-08-30，v1.6.9） | 没有现成的非 Sparkle 补丁路径 |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable release
- Recipe 状态: 不需要单独 `ChangelogRecipe`

## 一键安装
- 状态: **支持**
- 格式: dmg — `Fluid-oss-<ver>.dmg`（文件名仍用改名前的产品 token）
- Pattern: `^Fluid-oss-[0-9.]+\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（GitHub latest stable）。同一条 dmg 挂在
  官方 Releases 页上，不是灰度分配。
- 包是 universal（x86_64 + arm64 一个文件），文件名没有 arch token；这与
  Goose.zip（文件名中性、内容却是 arm64-only）不同，Intel 宿主拿到的也是
  带 x86_64 slice 的同一份。

### 验证记录（2026-08-30，v1.6.9）
下载 `Fluid-oss-1.6.9.dmg` 只读挂载核对：

| 检查 | 结果 |
|------|------|
| dmg 结构 | 根目录 `FluidVoice.app` + `/Applications` 符号链接 |
| Bundle ID | `com.FluidApp.app` |
| 版本 | `CFBundleShortVersionString` = `1.6.9` == tag；`CFBundleVersion` = `20` |
| 架构 | universal `x86_64 arm64` |
| OS 下限 | `LSMinimumSystemVersion` = `15.0` |
| 签名 | `Developer ID Application: Barathwaj Anandan (V4J43B279J)`，hardened runtime |
| 公证 | `spctl -a -t install` → `accepted / source=Notarized Developer ID`；stapler validate 通过 |

## 已知问题
- 应用自己也读 GitHub Releases。没有 Sparkle feed，所以不受「让位给自更新器」
  那条路径影响；一键与它并行，谁先换上 bundle 算谁的。
- Windows 预构建发在同一个 repo 的 prerelease tag 下，靠 version pattern 的
  `^v` 锚挡掉，不靠资产名。

## 如何复验
```
# 规范名，不是旧 slug Fluid-oss
# GET https://api.github.com/repos/altic-dev/FluidVoice/releases/latest
# tag_name = v1.6.9
# assets 含 Fluid-oss-1.6.9.dmg，不含 Windows exe
#
# 挂载该 dmg，读 Info.plist：
#   CFBundleIdentifier = com.FluidApp.app
#   CFBundleShortVersionString = 1.6.9
# codesign TeamIdentifier = V4J43B279J
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
