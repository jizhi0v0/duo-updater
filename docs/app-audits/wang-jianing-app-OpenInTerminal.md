# OpenInTerminal

## 基本信息
- Bundle ID: `wang.jianing.app.OpenInTerminal`
- Team ID: `C8VX3ZLX5U`（2.3.9 起；2.3.8 的签名 Team 是 `Q33U8R4U57`，同一署名 “Jianing Wang”）
- 观测版本: `2.3.9`（`CFBundleVersion` 恒为 `1`，不参与比较）
- 自更新机制: 无（包内无 `SUFeedURL`，无 Sparkle / electron-builder 配置；`feed-discover` 结论
  “no Sparkle and no electron-builder update config”）
- 分发: GitHub Releases（`Ji4n1ng/OpenInTerminal`）/ Homebrew cask `openinterminal`（下载同一个
  `OpenInTerminal.zip`，非 `auto_updates`）。无 MAS。
- 开源: 是。仓库根的 `build-signed.sh` 构建、Developer ID 签名、公证并 staple 三个 app，
  输出 `export/<App>.zip` 供手动上传；仓库没有 release workflow，tag 与上传是手工的。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`channel-verify` 实测）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `wang.jianing.app.OpenInTerminal` | 单一渠道 | — | tag `^vX.Y.Z$` + 资产名 `OpenInTerminal.zip` | ✓ |

单渠道：最近 30 个 release 全部非 prerelease、非 draft（2026-09-29，`gh api .../releases?per_page=30`）。

### 同仓库的另外两个产品
同一仓库、同一 tag 命名空间还发布 OpenInTerminal-Lite 与 OpenInEditor-Lite：主 app 是 `v2.x`
（资产 `OpenInTerminal.zip`），Lite 是 `v1.x`（资产 `OpenInTerminal-Lite.zip`、
`OpenInEditor-Lite.zip`，有时带 `Icons.zip`）。两者通常同时发布（v2.3.9 与 v1.2.8 的
`created_at` 相同，`published_at` 相差 14 秒）。tag 形状区分不了两者，所以规则靠资产名：
- 规则设了 `installAssetPattern: ^OpenInTerminal\.zip$`。若 `/releases/latest` 返回的是 Lite
  release，它没有匹配资产，`settle()` 回落到 releases 列表并跳过所有 Lite release。
- 2026-09-29 `/releases/latest` 实际返回 `v2.3.9`；Lite 在前的情形用临时 Swift 测试验证过
  （stub 让 `/releases/latest` 回 `v1.2.8`，列表为 `v1.2.8, v2.3.9, v1.2.7, v2.3.8`，
  真实规则经 `resolveDiagnostic` 得到 `2.3.9` / `OpenInTerminal.zip`、failure=nil；测试未提交）。
- 余量：Lite release 的 tag 同样匹配 `versionPattern`，会计入 `maxReleasesWithoutMacOSAsset`（5）。
  历史上主 app 与 Lite 基本成对出现，连续 5 个仅 Lite 的 release 没有出现过；若出现，规则会
  报资产未匹配（不会给出错误版本）。

OpenInTerminal-Lite 的 bundle id 是 `wang.jianing.app.OpenInTerminal-Lite`（v1.2.8 真包：
short `1.2.8` == tag，universal，Team `C8VX3ZLX5U`，`spctl` Notarized Developer ID）。本次**未接入**，
见「建议下一步」。

## 更新检测
- 源: `Ji4n1ng/OpenInTerminal` GitHub Releases，`/releases/latest`（资产不匹配时回落列表）
- 版本方案: tag `v2.3.9` → `2.3.9` == 包的 `CFBundleShortVersionString`（2.3.8 同样相等）。
  资产名不带版本号；2022 年及以前叫 `OpenInTerminal.app.zip`，自 v2.3.7 起是 `OpenInTerminal.zip`。
- 注意事项: 早年 tag 有不带 `v` 的（`2.2.3`、`1.1.5` 等，2020 年），不匹配 pattern，均非最新，不影响。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 无自更新器（无 `SUFeedURL`） | release 只有整包 zip（2026-09-29） | — |

## 按 OS 分轨
- `LSMinimumSystemVersion` = `10.13`（2.3.8、2.3.9 相同）；无上限声明。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 经 `GitHubMarkdownParser` 结构化带回；
  `channel-verify` 显示 changelogURL 指向 `releases/tag/v2.3.9`）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（从 2.3.9 起的安装）
- 格式: zip — `OpenInTerminal.zip`，universal（`x86_64 arm64`）
- Pattern: `^OpenInTerminal\.zip$`, kind `.zip`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；Homebrew cask 下载的是同一个 URL）
- 包验（2026-09-29，v2.3.9 解压）: `wang.jianing.app.OpenInTerminal` / `2.3.9`，
  Team `C8VX3ZLX5U`，`Notarization Ticket=stapled`，`spctl accepted / Notarized Developer ID`
- 包内有 Finder Sync 扩展与登录项 helper（`Contents/Library/LoginItems`），整包替换会一起换掉。
- ⚠️ Team 变更: v2.3.8 包的 Team 是 `Q33U8R4U57`，v2.3.9 是 `C8VX3ZLX5U`。`SignatureVerifier`
  的 Team-ID 闸要求已装与下载一致，所以从 2.3.8（以及其他 `Q33U8R4U57` 签名的旧版）一键到 2.3.9
  会被拒绝（读代码得出，未实跑安装）；检测仍会报出更新，用户需手动下载一次。2.3.9 之后的版本
  若保持 `C8VX3ZLX5U`，一键正常。

## 已知问题
- 上述 Team 变更使旧版一键被 Team-ID 闸拒绝（fail-closed，不会替换）。

## 如何复验
```
# GET https://api.github.com/repos/Ji4n1ng/OpenInTerminal/releases/latest → v2.3.9
# ditto -x -k OpenInTerminal.zip（v2.3.9）→ wang.jianing.app.OpenInTerminal / 2.3.9 / Team C8VX3ZLX5U
swift run --package-path application-test channel-verify <v2.3.9>/OpenInTerminal.app --expect stable
#   → winning source GitHub, latest 2.3.9, status up to date
swift run --package-path application-test channel-verify <v2.3.8>/OpenInTerminal.app --expect stable
#   → winning source GitHub, latest 2.3.9, status UPDATE → 2.3.9
```

## 建议下一步
1. OpenInTerminal-Lite（`wang.jianing.app.OpenInTerminal-Lite`）可同法接入：同仓库，资产
   `^OpenInTerminal-Lite\.zip$` 会让规则跳过主 app 的 `v2.x` release。需先做同样的旧→新
   `channel-verify`。OpenInEditor-Lite 同理（bundle id 未读）。
