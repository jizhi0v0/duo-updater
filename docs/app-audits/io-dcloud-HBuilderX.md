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
| **stable**   | —       | ✗(auto)  | —   | —      | ✓ +一键      |
| **alpha**    | —       | —        | —   | —      | ✓ +一键      |

当前生效源: **VendorProbe**

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `io.dcloud.HBuilderX`      | 独立 | bundle id 无 channel 词 → stable       | ✓ |
| alpha   | `io.dcloud.HBuilderXAlpha` | 独立 | bundle id 含 `Alpha` + 名称 → `.alpha` | ✓ |

## 更新检测
- stable: `https://download1.dcloud.net.cn/hbuilderx/release.json`（**2026-07-03 改**：原为第三方镜像 `update.liuyingyong.cn/…/alpha/…`，只有 manifest 会滞后；官方 `release.json` 同时带版本+安装包，更权威更新鲜，与 changelog recipe 同源）
  - versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"` 末尾 `"` 关键——防止匹配 `displayVersion`(2 段)或 `-alpha`/`-beta` 后缀
- alpha: `https://download1.dcloud.net.cn/hbuilderx/alpha.json`
  - versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-alpha)"` 捕获含后缀的完整版本
  - `channel: .alpha`——VendorProbeSource channel gate 必须与安装的 `.alpha` 一致

## Changelog
- stable: ChangelogRecipe ✓（`hx.dcloud.net.cn/Tutorial/HistoryVersion`）
- alpha: ChangelogRecipe ✓（相同 changelogURL，单独 bundleID `io.dcloud.HBuilderXAlpha`）

## 一键安装
- stable: **一键 ✓**（2026-07-03 加，随版本源改到 `release.json` 一并接入）。`files[]` 里带
  `mac_simple_arm64` 的 `…arm64.dmg`；`.bodyPattern` 锁 `\.arm64\.dmg`（x64 `mac_simple` `.dmg`
  排前面，同 alpha 一样必须锚 arm64）；dmg 同 Team `YQM5H857L5`、已公证（`spctl` accepted），
  过 `VendorInstaller` 签名门。仅 arm64。
- alpha: **一键 ✓**（2026-06-05 加）。同一个 `alpha.json` 的 `files[]` 里就带安装包；
  `.bodyPattern` 锁 `…-alpha.arm64.dmg`（x64 的 `mac_simple` `.dmg` 排在前面，必须用
  `\.arm64\.dmg` 锚定，否则首个匹配会抓到 Intel 包）；dmg 与已装 alpha 同 Team
  `YQM5H857L5`、已公证（`spctl` accepted），过 `VendorInstaller` 签名门。仅 arm64。

## 已知问题
- stable 端点路径含 `/alpha/`（DCloud 命名混乱）；非 alpha 版本确认为官方 stable 构建（5.07.2026041006 = 最新正式版），非预发布
- Alpha 真正的版本字符串带 `-alpha` 后缀（`5.11.2026052520-alpha`），`VersionComparator` 将 `-alpha` 作为尾文本，纯数字版本高于它——比较正确

## channel-verify 状态
- ✓ **两 channel 已验证 2026-06-04**（`--scan`，本机同时装了 stable 与 alpha）。stable `io.dcloud.HBuilderX` 5.07… 与 alpha `io.dcloud.HBuilderXAlpha` 5.11…-alpha 是独立 bundle id；两条 VendorProbe 均应答=installed。证据：`application-test/records/io-dcloud-HBuilderX.md`
- ✓ **stable 复验 2026-07-03**（版本源改 `release.json` + 加一键后）：`channel-verify /Applications/HBuilderX.app --expect stable` → detected stable，VendorProbe 应答 `UPDATE 5.07.2026041006 → 5.14.2026070214`，download 抠出 `HBuilderX.5.14.2026070214.arm64.dmg`
