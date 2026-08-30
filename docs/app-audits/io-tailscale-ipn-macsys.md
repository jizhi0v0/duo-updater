# Tailscale

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable 完整（检测+一键+Changelog）；unstable/rc 轨道未覆盖**

## 基本信息
- Bundle ID: `io.tailscale.ipn.macsys`
- 自更新机制: macOS Extension / System Extension，通过系统 pkg 更新
- Team ID: `W5364U7YZB`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **unstable** | —       | —        | —   | —      | ○           |

当前生效源: **VendorProbe**（stable 端点 `pkgs.tailscale.com/stable/`）

## Channel 详情

| Channel  | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|----------|-----------|----------|---------|------|
| stable   | `io.tailscale.ipn.macsys` | — | — | ✓ |
| unstable | `io.tailscale.ipn.macsys` | 共享(推测) | — | ○ 可加（端点 `pkgs.tailscale.com/unstable/`）|

## 更新检测
- stable: `https://pkgs.tailscale.com/stable/?mode=json` → `"MacZipsVersion":"X.Y.Z"`
  - 顶层 `Version` 是 Linux/Windows 版本（不同方案，不用！）
  - install URL 从 `"universal-package":"Tailscale-<ver>-<hash>.pkg"` 拼出，base `pkgs.tailscale.com/stable/`

## Changelog
- ChangelogRecipe ✓（`tailscale.com/changelog`）

## 一键安装
- ✓ pkg，Team W5364U7YZB

## 建议下一步
1. 如需 unstable 支持：端点 `https://pkgs.tailscale.com/unstable/?mode=json` → 同 pattern；bundle id 需确认是否独立（如独立则 Pattern A，如共享则需 channel 检测信号）
2. 若 unstable 共享同一 bundle id，需有偏好/版本信号可区分（暂无确认信息）

## channel-verify 状态
- ✓ **stable 已验证 2026-06-04**（`--scan`，对真实 `io.tailscale.ipn.macsys` bundle 1.98.5/101.98.5）。VendorProbe 应答 1.98.5=installed，无幽灵更新。`unstable` 轨无 recipe、不在范围。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan io.tailscale.ipn.macsys --expect stable
```
