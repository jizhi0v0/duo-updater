# Msty Studio

## 基本信息
- Bundle ID: `MstyStudio`
- Team ID: `S6CF5A8MX9`
- 已验证版本: `2.9.7`
- 自更新机制: electron-builder generic provider

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `MstyStudio` | latest-mac.yml `version` | ✓ |

## 更新检测
- 端点: `https://next-assets.msty.studio/app/latest/mac/latest-mac.yml`。
- 生产验证: mounted DMG `2.9.7 → 2.9.7`, stable/up-to-date。

## Changelog
- `https://msty.ai/resources/changelog/studio/`。

## 一键安装
- 状态: **已启用**（2026-08-29），`.fixed` →
  `https://next-assets.msty.studio/app/latest/mac/MstyStudio_arm64.zip`（文件名不带版本，
  URL 是常量，没有可模板化的东西），校验和取 manifest 里 **arm64 那一条**。
- **真正的阻碍不是"按 host 选包"，是校验和配对**: `checksumPattern` 是对整份 body 的首个匹配，
  而这份 manifest 列了四个资产、`MstyStudio_x64.zip` **排第一**，`path:` 指的也是 x64。
  所以朴素的 `^\s+sha512:` 会把 x64 的摘要配给 arm64 的下载，每次安装必失败。
  把正则锚在 `url: MstyStudio_arm64.zip` 后面，配对就从"靠位置"变成"靠结构"。
  2026-08-29 实测：朴素写法得 `2Ix1WRcS…`(x64)，锚定写法得 `aNSie9nH…`(arm64)，
  而下载到的 `MstyStudio_arm64.zip` 的 sha512 正是后者。
- **校验和在这里有第二重作用（但是 best-effort）**: URL 是 "latest" 而摘要属于探针比较过的
  那个版本，所以检查与点击之间厂商如果发了新版，会**校验和失败**而不是悄悄装上一个没人
  比较过的版本——失败是响的，重新检查即可恢复。
  **限制**: 安装时校验和是可选的（`VendorInstaller` 用 `if let expected` 包着），所以这条
  正则一旦失配（厂商调换条目内的键序、或改资产名），安装会**不带校验**继续，"latest" 又变回
  可能装上没人比较过的版本；只有当晚的 sweep 通过 `checksumPatternNoMatch` 事后发现。
  考虑过把它改成硬失败，否决了：厂商一次改版会把「装了个更新一点的版本」变成「一键彻底不可用」，
  后者更糟。
- 包实测 2026-08-29: 248,234,928 B，解出 `MstyStudio.app` 2.9.8,
  `Developer ID Application: Ashok Gelal (S6CF5A8MX9)`, spctl accepted / Notarized, arm64。
- 生产路径实测: 签名闸 harness 报 `sha512 expected: aNSie9nHz5ybfhfC… actual: aNSie9nHz5ybfhfC…`
  —— 即锚定摘要对真实字节成立 —— 随后 `✅ gate passed`。**未做**红→绿：
  厂商只有 latest 路径，`app/2.9.7/…` 与 `app/2.9.6/…` 均 404，拿不到旧构建。

## 已知问题
- Bundle ID 为无点形式 `MstyStudio`，不得按产品名推导成反向域名。
- manifest 的 `path:` 指向 x64，任何"跟着 path 走"的写法都会装错架构。

## 建议下一步
1. 架构感知安装规格落地后使用对应 DMG 与 sha512。

