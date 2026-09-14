# Wispr Flow

## 基本信息
- Bundle ID: `com.electron.wispr-flow`
- Team ID: `C9VQZ78H85`
- 已验证版本: `1.6.531`
- 自更新机制: 自研 `RELEASES.json` / ShipIt

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.electron.wispr-flow` | `currentRelease` | ✓ |

## 更新检测
- 端点: `https://dl.wisprflow.com/wispr-flow/darwin/arm64/RELEASES.json`。
- 生产验证: mounted DMG `1.6.531 → 1.6.531`, stable/up-to-date。

## Changelog
- feed 的 `notes` 当前为空；无稳定公开 changelog 页面。

## 一键安装
- 状态: **已启用**（2026-08-29），`.versionTemplate` →
  `https://dl.wisprflow.com/wispr-flow/darwin/arm64/Wispr%20Flow-darwin-arm64-{version}.zip`。
- 为什么不是 `.bodyPatternHighestVersioned`: feed 的每条 entry 里 `version` 印在 `url`
  **之前**，而该 case 要求捕获组 1 是 url、组 2 是 version——单条从左到右的正则给不出这个顺序。
  其余 body 选项都是在赌 feed 的排列顺序。`.versionTemplate` 用已解析的版本拼 URL，
  比较的是哪个版本、下载的就是哪个版本。
- 无 checksum: feed 对任何 entry 都不发布摘要，完整性由签名 + Team 闸承担。
- **不跟 feed 自己的 `url`**: stable feed 全部 26 条 entry 都指向 `wispr-flow-beta/…`。
  跟着走是能下到正确的包（1.6.721 实测: `com.electron.wispr-flow`,
  `Developer ID Application: Wispr AI INC (C9VQZ78H85)`, spctl accepted / Notarized, 已 staple），
  但会让每晚的 `duo verify` 常驻一条 "stable recipe resolved what looks like a PRE-RELEASE
  artifact"——`duo reconcile` 还会把它开成 issue。同一个对象在 recipe 已经在探的 stable
  路径 `wispr-flow/darwin/arm64/` 下也有: 2026-08-29 两条各下一份，长度同为 331,807,594 B、
  SHA-256 同为 `0217292d…d6a31`，即 `-beta` 是别名不是另一个 build。所以模板用 stable 路径，
  是把告警**消掉**而不是压掉。
  2026-09-14 复测（只读 GET + 不跟随重定向的 HEAD）：feed 仍是 26 条，最老的 22 条（到 1.6.721）仍指向
  `wispr-flow-beta/…`，1.6.765 起的 4 条已改指 `wispr-flow/…`；`currentRelease` 1.6.827 在两条路径下都回 200、
  `Content-Length` 同为 317,421,090，但 ETag 与 Last-Modified 不同，没有下载比对字节。
- 端到端实测 2026-08-29: 装 1.6.675 → `duo check` 报 1.6.721 → `duo install` →
  磁盘 1.6.721，Team 不变，`duo check` 转 up-to-date。

## 已知问题
- 两架构当前同版本；若未来分叉需拆分来源。
- 早先此处记的阻塞（"Intel/arm64 分离，安装规格不能按 host 选包"）是错的：probe 端点
  本身就是 `/darwin/arm64/`，架构在**检测**这一步已经定死，安装侧没有第二次选择；
  且 DuoUpdater 为 arm64-only（`App/project.yml`），不存在会来要 Intel 包的宿主。

## 建议下一步
1. 若 vendor 改动资产路径，`.versionTemplate` 会以 404 大声失败——届时改模板即可。


## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-electron-wispr-flow.swift — stable VendorProbe（`.versionTemplate` 一键）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`495d1e81`（2026-08-29）。

The feed's 26 entries each carry their own `url`, but the
version is printed BEFORE the url inside every entry, and
`.bodyPatternHighestVersioned` requires capture group 1 to be the url and
group 2 the version — an order a single left-to-right regex cannot
produce here.

An earlier note here said the feed was architecture-specific and that a
one-click risked a cross-architecture swap.

Every entry
in this stable feed — all 26 — points at a `wispr-flow-beta/…` path.
Following it works (the artifact there is a normal notarized stable
build; 1.6.721 downloaded and extracted 2026-08-29:
`com.electron.wispr-flow`, CFBundleShortVersionString 1.6.721,
`Developer ID Application: Wispr AI INC (C9VQZ78H85)`, spctl "accepted /
Notarized Developer ID", stapled), but it makes every nightly `duo
verify` raise "stable recipe resolved what looks like a PRE-RELEASE
artifact" — a standing false positive on the one sweep whose job is to
be believed, and one `duo reconcile` would file as an issue.

The same object is served from the stable path this recipe already
probes, `wispr-flow/darwin/arm64/`: verified 2026-08-29 by fetching both
and comparing — identical size (331,807,594 B) and identical SHA-256
(0217292d…d6a31), so the `-beta` bucket is an alias, not another build.

复测 2026-09-14（03:12 UTC，只读 GET 与不跟随重定向的 HEAD，没有下载）：`RELEASES.json` 仍有 26 条；最老的 22 条（1.5.848 … 1.6.721，发布于 2026-08-28 及以前）指向 `wispr-flow-beta/…`，最新的 4 条（1.6.765 … 1.6.827，2026-09-02 起）指向 `wispr-flow/…`。`currentRelease` 是 1.6.827，它在两条路径下都回 200、`Content-Length` 同为 317,421,090，ETag 不同（stable 路径那份是分段上传的 `…-38`）、Last-Modified 相差 11 分钟；字节是否相同没有比对。代码里 "all 26" 那句已改写。
