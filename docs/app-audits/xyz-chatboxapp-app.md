# Chatbox

## 基本信息
- Bundle ID: `xyz.chatboxapp.app`
- Team ID: `YJ5GSB3AMW`
- 观测版本: `1.22.6`（short == build）
- 自更新机制: electron-updater（electron-builder 管道；无 `SUFeedURL`）
- 分发: 官方 CDN `download.chatboxai.app/releases/` + Homebrew cask `chatbox`
  （`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | — | ✓ |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `xyz.chatboxapp.app` | 单一渠道 | — | — | ✓ |

单渠道，vendor 无 beta/canary 面。

## 更新检测
- 源: `https://download.chatboxai.app/releases/latest-mac.yml` —— electron-builder
  feed，首行 `version: 1.22.6`。**这正是 Homebrew 自家 `chatbox` cask 的
  `livecheck` 用的端点（`strategy :electron_builder`）**，第三方已依赖同一
  端点做同一件事。
- 版本方案: feed `version` == 包的 short == build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | electron-updater 支持 | 无 | 不能 |
| 证据 | — | yml 无 delta 条目（观测 2026-08-30） | — |

## Changelog
- 来源: **厂商自己的 changelog 页** `chatboxai.app/en/help-center/changelog`。
  版本源那份 `latest-mac.yml` 是 electron-builder 清单（文件名/大小/哈希），没有正文。
- 同号（2026-09-03）: 页面 `v1.23.1`，yml `version: 1.23.1`。
- 页面结构: 每个版本是 `<h2>v<ver> - <date></h2>`，**后面跟两个列表**——`<ol>` 是
  改动，`<ul>` 是各平台下载链接。entry pattern **必须绑住 `<ol>`**；捕获到下一个
  `<h2>` 为止会把 6 条下载链接（"MacOS(Apple Silicon)"、"Windows"…）塞进每个版本的
  notes 里。
- 实测（2026-09-03，对真实页面跑正则）: **30 条**，`1.23.1` → 4 items、`1.23.0` → 9
  items，**没有任何一条 body 含 `download.chatboxai.app`**。
- Recipe 状态: **已接**。`duo verify --only chatboxapp` 打真实端点 `changelog ✓ 1`。

## 一键安装
- 状态: **支持**
- 格式: dmg — `Chatbox-{ver}-arm64.dmg`（相对路径，解析到 releases 基址）
- **读的是**: 人人可手动下载的 GA（vendor 自有 CDN）
- **校验和**: feed 内该 dmg 条目的 base64 sha512，下载后先验再装。2026-08-30
  对真实下载的 dmg 逐字节复算，与 feed hash 完全一致（151,499,252 bytes）——
  不像 Signal 那条 yml（签名装订后字节对不上），这条 hash 就是 CDN 实际字节。
- 包验（2026-08-30，1.22.6 挂载）: `xyz.chatboxapp.app` / `1.22.6`，Team
  `YJ5GSB3AMW`，notarized；自包含 bundle → `kind: .dmg` 正确。
- x64 dmg 与两个 zip 是同场兄弟资产，刻意不选（DuoUpdater arm64-only）。

## 已知问题
- 无。

## 如何复验
```
# GET https://download.chatboxai.app/releases/latest-mac.yml → version: 1.22.6
# 挂载 Chatbox-1.22.6-arm64.dmg → xyz.chatboxapp.app / 1.22.6
# channel-verify --check xyz.chatboxapp.app → winning=Vendor, up to date
```

## 建议下一步
- changelog：可后续接 ChangelogRecipe（vendor 更新页结构未查）。
