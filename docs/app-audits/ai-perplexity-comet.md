# Comet

## 基本信息
- Bundle ID: `ai.perplexity.comet`
- Team ID: `7S8W4W365S`
- 已验证版本: short `151.0.7922.247`, build `7922.247`
- 自更新机制: Keystone (`KSUpdateURL` `/rest/browser/update2`)

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `ai.perplexity.comet` | stable download redirect | ✓ |

## 更新检测
- 端点: stable download GET 的 3xx `Location` 版本目录。
- 生产验证: `151.0.7922.247 → 151.0.7922.247`, stable/up-to-date。
- 未采用旧 `/rest/browser/update` JSON：它仍返回 `145.2.7632.4581`，低于真实公开包。

## Changelog
- 未发现稳定、逐版本公开页面。

## 一键安装
- 状态: **已启用**（2026-08-29），`.fixed` 指向**网关本身**
  `https://www.perplexity.ai/rest/browser/download?channel=stable&platform=mac_arm64`。
- **为什么不用探针刚解析出来的那个签名 URL**: install URL 是在**检查时**解析并挂在行上的，
  而这个签名带 `X-Amz-Expires=3600`；除 hourly 外的任何检查频率都比它长，隔夜再点就是 403。
  把网关交给下载器，重定向就发生在**下载时**，签名永远只有几分钟大。也正因如此，短时效 URL
  从来不需要"重新解析"——没有任何地方会长期持有它。
- **为什么不用 `.redirect`**: 它发 HEAD，而这家 HEAD 答
  `Location: https://www.example.com?status=ok`（2026-08-29 实测；同一 URL 的 GET 正常）。
- 无 checksum：网关不发布摘要——所以与 Msty 不同，这里**没有任何东西**能发现"下到的构建
  不是比较过的那个"。网关恒发最新版：某一行在 151.0.7922.247 时检查、等 152.x 发布后才点，
  装的是 152.x 而记录的是 151.0.7922.247，直到下次检查才纠正。这是记账漂移不是坏 app，
  而且每条 `.redirect` recipe 本来就有同样的性质；写下来是因为版本与资产在**探测时**同出一份
  文档、在**安装时**却出自两个时刻。
- 包实测 2026-08-29（跟随重定向下载，313,170,645 B）: dmg 卷名 "Comet Installer"，里面是真正的
  710 MB `Comet.app`（不是 1Password 那种安装器壳）: `ai.perplexity.comet` 151.0.7922.247,
  `Developer ID Application: Perplexity AI Inc. (7S8W4W365S)`, spctl accepted / Notarized,
  universal (x86_64 + arm64)。
- 生产路径实测: 跑仓库的签名闸 harness（真实 `Downloader` + 全部闸，停在换包前）——
  Team 7S8W4W365S 对上，`✅ gate passed`。**未做**装旧版再升级的红→绿：网关只发最新版，
  Homebrew 的 comet cask 用的也是同一个 latest 网关，拿不到旧构建。
- 旁证: Homebrew cask `comet` 的 `url` 就是这个网关，说明"GET 网关 + 跟随重定向"是厂商的正规下载路径。

## 已知问题
- HEAD 被供应商重定向到 `example.com`；recipe 必须保持 GET/no-follow，安装侧也不能用 `.redirect`。

## 建议下一步
1. 上游 update2 若公开稳定协议，可替换重定向探测。

