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
- 状态: 仅检测。
- 阻塞: 网关按架构返回短时效签名 URL，当前 Vendor 安装规格不能安全按 host 选包。

## 已知问题
- HEAD 被供应商重定向到 `example.com`；recipe 必须保持 GET/no-follow。

## 建议下一步
1. 上游 update2 若公开稳定协议，可替换重定向探测。

