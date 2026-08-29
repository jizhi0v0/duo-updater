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
- 端到端实测 2026-08-29: 装 1.6.675 → `duo check` 报 1.6.721 → `duo install` →
  磁盘 1.6.721，Team 不变，`duo check` 转 up-to-date。

## 已知问题
- 两架构当前同版本；若未来分叉需拆分来源。
- 早先此处记的阻塞（"Intel/arm64 分离，安装规格不能按 host 选包"）是错的：probe 端点
  本身就是 `/darwin/arm64/`，架构在**检测**这一步已经定死，安装侧没有第二次选择；
  且 DuoUpdater 为 arm64-only（`App/project.yml`），不存在会来要 Intel 包的宿主。

## 建议下一步
1. 若 vendor 改动资产路径，`.versionTemplate` 会以 404 大声失败——届时改模板即可。

