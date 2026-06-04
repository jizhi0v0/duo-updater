# HBuilderX

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/alpha 两 channel 已检测（独立 bundle id）**

## 基本信息
- Bundle ID: `io.dcloud.HBuilderX`（Alpha 独立：`io.dcloud.HBuilderXAlpha`）
- Team ID: `YQM5H857L5`（stable 和 alpha 共用同一 Team）
- 自更新机制: 内置更新（DCloud 自研）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **alpha**    | —       | —        | —   | —      | ✓           |

当前生效源: **VendorProbe**

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `io.dcloud.HBuilderX`      | 独立 | bundle id 无 channel 词 → stable       | ✓ |
| alpha   | `io.dcloud.HBuilderXAlpha` | 独立 | bundle id 含 `Alpha` + 名称 → `.alpha` | ✓ |

## 更新检测
- stable: `https://update.liuyingyong.cn/hbuilderx/alpha/macosx-arm64/update/index.json`（路径含 `alpha` 但服务 stable 官方版！非 alpha 轨道端点）
  - versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"` 末尾 `"` 关键——防止匹配 `-alpha`/`-beta` 后缀
- alpha: `https://download1.dcloud.net.cn/hbuilderx/alpha.json`
  - versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-alpha)"` 捕获含后缀的完整版本
  - `channel: .alpha`——VendorProbeSource channel gate 必须与安装的 `.alpha` 一致

## Changelog
- stable: ChangelogRecipe ✓（`hx.dcloud.net.cn/Tutorial/HistoryVersion`）
- alpha: ChangelogRecipe ✓（相同 changelogURL，单独 bundleID `io.dcloud.HBuilderXAlpha`）

## 一键安装
- 仅检测（两 channel 均无 install 字段）

## 已知问题
- stable 端点路径含 `/alpha/`（DCloud 命名混乱）；非 alpha 版本确认为官方 stable 构建（5.07.2026041006 = 最新正式版），非预发布
- Alpha 真正的版本字符串带 `-alpha` 后缀（`5.11.2026052520-alpha`），`VersionComparator` 将 `-alpha` 作为尾文本，纯数字版本高于它——比较正确

## channel-verify 状态
- ✓ **两 channel 已验证 2026-06-04**（`--scan`，本机同时装了 stable 与 alpha）。stable `io.dcloud.HBuilderX` 5.07… 与 alpha `io.dcloud.HBuilderXAlpha` 5.11…-alpha 是独立 bundle id；两条 VendorProbe 均应答=installed。证据：`application-test/records/io-dcloud-HBuilderX.md`
