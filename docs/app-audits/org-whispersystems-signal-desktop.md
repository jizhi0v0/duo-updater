# Signal Desktop

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel 已检测**

## 基本信息
- Bundle ID: `org.whispersystems.signal-desktop`（Beta 独立：`org.whispersystems.signal-desktop-beta`）
- 自更新机制: electron-updater（自研，Squirrel-like）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **beta**     | —       | ✗(auto)  | —   | —      | ✓           |

当前生效源: **VendorProbe**（各自 electron-builder yml 端点）

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `org.whispersystems.signal-desktop`      | 独立 | bundle id 无后缀 → stable      | ✓ |
| beta    | `org.whispersystems.signal-desktop-beta` | 独立 | bundle id `-beta` 后缀 → .beta | ✓ |

## 更新检测
- stable: `https://updates.signal.org/desktop/latest-mac.yml` → `version: X.Y.Z`
- beta:   `https://updates.signal.org/desktop/beta-mac.yml` → 同 pattern

## Changelog
- changelogURL: `https://github.com/signalapp/Signal-Desktop/releases`（两 channel 共用）
- 无 ChangelogRecipe

## 一键安装
- 两 channel 均为 best-effort 一键（同一份 yml 里的 **universal dmg**，非 per-arch zip），
  叠在 electron-updater 之上。Team `U68MSDN6DR`，两 channel 同 Team、均已公证+stapled，
  签名 bundle id 各自独立 → VendorInstaller 的 Team + bundle-id 闸把每个 channel 钉在自己轨上。
- **两 channel 的 dmg 文件名不同构**：stable 是 `signal-desktop-mac-universal-<ver>.dmg`，
  beta 多一段 → `signal-desktop-beta-mac-universal-<ver>.dmg`。beta 早期复用了 stable 的
  pattern，匹配为空 → 版本照常解析、一键静默退化成仅检测（无任何报错）。两边 pattern 现在
  各钉各的 channel 拼写，互不匹配。2026-08-09 修。
- **两 channel 都不校验 feed 里的 sha512**：yml 的 `sha512`/`size` 是 electron-builder 出包时
  算的，Signal CI 之后才签名+stapler，CDN 发的是 stapled 版（`Content-Length` 比 feed 的
  `size` 大 2563 字节，两 channel 一致），feed hash 永远对不上下载到的字节 → 挂 checksum 只会
  让每次安装在 VendorInstaller 第 1 道闸 throw。对照：Typeless 同构 feed delta=0，所以这是
  Signal 自己的流水线问题，别照抄 Typeless 加回来。

## channel-verify 状态
- ✓ **两 channel 已验证 2026-06-04**（官方 zip 解压后对真实 `.app` 跑 channel-verify、未安装）。stable `org.whispersystems.signal-desktop` 8.13.0 / beta `…-beta` 8.14.0-beta.1 各自 VendorProbe（latest-mac.yml / beta-mac.yml）应答=installed，无幽灵更新。证据见下文「如何复验」。
- ✓ **2026-08-09 复验**（官方 universal dmg 挂载取 `.app`、未安装）：stable 8.22.0 / beta 8.23.0-beta.1
  检测=期望 channel、probe 应答=installed、各自解析到本 channel 的 dmg，签名/公证/Team 已核。
  同一份证据文件。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify "/tmp/Signal.app"      --expect stable
swift run --package-path application-test channel-verify "/tmp/Signal Beta.app" --expect beta
```
