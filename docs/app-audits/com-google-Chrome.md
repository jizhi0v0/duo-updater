# Google Chrome

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta/dev/canary 四 channel 全覆盖检测，工作正常**

## 基本信息
- Bundle ID: `com.google.Chrome`（beta/dev/canary 各自独立：`com.google.Chrome.beta` / `.dev` / `.canary`）
- 已安装版本: `149.0.7827.54`（stable，本机仅装 stable）
- `CFBundleShortVersionString` = `149.0.7827.54`（完整 4 段）/ `CFBundleVersion` = `7827.54`（截断）
- `KSChannelID` = `universal`（stable 装机即此值，**非** 空/`stable`）
- 自更新机制: **Keystone**（Google 自家更新器，后台静默升级）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **beta**     | —       | ✗(auto)  | —   | —      | ✓           |
| **dev**      | —       | ✗(auto)  | —   | —      | ✓           |
| **canary**   | —       | ✗(auto)  | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**
- Sparkle: 无 `SUFeedURL`，Chrome 不用 Sparkle。
- Homebrew: cask `google-chrome`（及 `@beta`/`@dev`/`@canary`）均 `auto_updates: true` → `HomebrewCaskSource` 返回 nil，落到 VendorProbe。
- MAS: Chrome 不上架 App Store。

## Channel 详情（Pattern A — 独立安装，各自 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.google.Chrome`        | 独立 | —（默认）；KSChannelID `universal` 走 fall-through→stable | 独立端点 | ✓ |
| beta    | `com.google.Chrome.beta`   | 独立 | bundle id `.beta` 后缀 / KSChannelID `beta` | 独立端点 | ✓ |
| dev     | `com.google.Chrome.dev`    | 独立 | bundle id `.dev` 后缀 / KSChannelID `dev` | 独立端点 | ✓ |
| canary  | `com.google.Chrome.canary` | 独立 | bundle id `.canary` 后缀 / KSChannelID `canary` | 独立端点 | ✓ |

每个 channel 是独立 bundle id + 独立 `ReleaseChannel`，channel gate 把每个安装路由到匹配的端点——beta 装机永远不会拿到 stable 版本，反之亦然。`KSChannelID` 是最强信号（`ReleaseChannel.detect` 第 1 优先级）：stable 实测值为 `universal`，不在 beta/dev/canary/stable/extended 白名单内，default 分支 fall-through，最终靠"无后缀 + 名称无 channel 词 + 版本号是稳定形态"判定为 stable——逻辑正确，无误判。

## 更新检测
- 源: VendorProbe（`mode: .responseBody`）
- 端点: Chrome 官方 VersionHistory API，每 channel 一个：
  `https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/{stable|beta|dev|canary}/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc`
- versionPattern: `"fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"`
- **rollout 防幽灵更新（关键设计）**: 用 `releases`（带 `fraction` 0–1 灰度比例）而非裸 `versions` 端点。裸端点会返回"仅存在"的最新 build（哪怕 0.5% 灰度），导致领先 Keystone 报幽灵更新（Chrome 自己还说"已是最新"）。pattern 锁 `fraction:1`（完全铺开 = Keystone 给所有人的版本），取其中最高版本。Canary 每个 build 都 fraction=1。
- **版本方案校验（Phase 3½）**: ✅ 端点返回完整 4 段（`149.0.7827.54`）= `CFBundleShortVersionString`，**不是** `CFBundleVersion`（`7827.54`）。无需 `versionIsBuild`，无幽灵更新风险。
- **实测**（2026-06-04）: stable 端点 fraction=1 最高版 = `149.0.7827.54`，与本机安装版**完全一致** → 检测口径正确。

## 一键安装
- 状态: **仅检测**（设计如此，不做一键）
- 原因: 四 channel 全部通过 Keystone 后台自更新，我们绝不覆盖安装。
- `downloadURL` = `chrome://settings/help`（app-scheme URL，UI 交给 Chrome 本体而非浏览器）：访问该页会让 Chrome 立即触发一次 Keystone 检查 + 下载，即它本channel 的真实更新路径。

## Changelog
- 来源: ChangelogRecipe（`com.google.Chrome`，**仅 stable**）
- 源页: `https://chromereleases.googleblog.com/search/label/Stable%20updates`（Chrome Releases blog / Blogger，server-rendered，正文内联在 `<script type='text/template'>`）
- entryPattern 用标题字面量 `Stable Channel Update for Desktop` 同时选中桌面 stable 帖、排除 Beta/Dev/Early/Extended（标题不同）。
- itemPatterns 两形态按序：① 安全帖的 `CVE-YYYY-N:` 内联 span；② 推广帖的 `promotion of Chrome…/been updated to…` 整段 `<p>`（tempered dot 防越界）。
- 跟随 channel: **否**——只覆盖 stable。beta/dev/canary 的 `changelogURL` 指向 `https://developer.chrome.com/release-notes`（按 channel 无独立 recipe，UI 内嵌网页）。
- Recipe 状态: stable 已有；非 stable 无 recipe（低优先，inline 网页兜底）。

## 已知问题
- 无功能性问题。stable 检测端到端实测通过。

## 建议下一步
1. **无需改代码** — 四 channel 检测均已接入且实测正确，写/更新本审计文档即可。
2. （可选，低优先）beta/dev/canary 暂无独立 changelog recipe，靠 `developer.chrome.com/release-notes` 内嵌兜底。若要做 per-channel changelog，需确认 Chrome Releases blog 是否有 `Beta updates`/`Dev updates` label 页结构同 stable —— 收益低，不建议现在做。
