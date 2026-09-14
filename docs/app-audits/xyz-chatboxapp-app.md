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

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/xyz-chatboxapp-app.swift — VendorProbe（feed 的 sha512 就是 CDN 字节的核对）

转引自 recipe 注释，未复测。整段原文；代码里 "computed over the real downloaded dmg 2026-08-30, byte-for-byte equal (151,499,252 bytes)" 改成括号里的 "(computed over the real downloaded dmg 2026-08-30 and found byte-for-byte equal; History has the size)"；其余原样，重新折行。本审计也记着同一个字节数。

Feed shape: `version: 1.22.6` on the first line, then a `files:` list
pairing each artifact's relative `url:` with its base64 `sha512:`.
The arm64 dmg is resolved against `download.chatboxai.app/releases/`
and its sha512 verified from the feed — unlike Signal's yml, the hash
here IS the bytes the CDN serves: computed over the real downloaded
dmg 2026-08-30, byte-for-byte equal (151,499,252 bytes). The x64 dmg
and both zips are siblings we deliberately don't select; DuoUpdater
is arm64-only. Signed "Developer ID Application" (Team YJ5GSB3AMW,
notarized) — matches the mounted artifact, so the VendorInstaller
Team gate passes.

### Recipes/xyz-chatboxapp-app.swift — ChangelogRecipe（页面与 feed 同一套版本号）

转引自 recipe 注释，未复测。整段原文；代码里把括号里当时两边读到的版本号换成 "(checked 2026-09-03 and 2026-09-14; History has the versions)"。

Chatbox — the electron-builder feed we read for the version
(`latest-mac.yml`) is a manifest: filenames, sizes and hashes, no prose.
The vendor's own changelog page has the notes and uses the same
numbering as the feed (`v1.23.1` on the page, `version: 1.23.1` in the
yml, 2026-09-03).

复测 2026-09-14（13:59 UTC，只读 GET）：`download.chatboxai.app/releases/latest-mac.yml` 首行 `version: 1.23.2`；`chatboxai.app/en/help-center/changelog` 第一条 `<h2>` 是 `v1.23.2`。

### Recipes/xyz-chatboxapp-app.swift — ChangelogRecipe（entry pattern 为什么只绑 `<ol>`）

转引自 recipe 注释，未复测。整段原文；代码里 "Validated against the live page 2026-09-03: 30 entries, …" 改成只留结论（没有哪条的正文带 `download.chatboxai.app` 链接）并注明两次核对的日期，条数与各条的 item 数搬到这里。本审计也记着同一组数。

Each release renders as `<h2>v<ver> - <date></h2>` followed by TWO
lists: an `<ol>` of changes and a `<ul>` of per-platform download
links. The entry pattern binds the `<ol>` specifically — capturing up
to the next `<h2>` instead would put six download links ("MacOS(Apple
Silicon)", "Windows", …) into every release's notes. Validated against
the live page 2026-09-03: 30 entries, 1.23.1 → 4 items, 1.23.0 → 9,
and zero entries whose body contains a `download.chatboxai.app` link.

复测 2026-09-14（同一次页面读取，解压后 182,987 B，本地 Python 按 recipe 的 entryPattern 复算）：31 条，`1.23.2` → 9 个 item、`1.23.1` → 4 个；正文带 `download.chatboxai.app` 的条目 0 条。
