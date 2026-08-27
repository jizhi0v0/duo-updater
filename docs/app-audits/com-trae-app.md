# TRAE

## 基本信息
- Bundle ID: `com.trae.app`
- Team ID: `79M8227NKH`
- 已验证版本: Info.plist short/build `3.5.81`
- 包内版本: `product.json` 为 `appVersion=3.5.81`, `tronBuildVersion=2.3.61406`
- 自更新机制: 自研 manifest / ShipIt

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✗           |

当前生效源: **unknown（已验证阻塞）**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.trae.app` | API 仅发布 packaging version | ✗ |

## 更新检测
- 官方 API: `https://api.trae.ai/icube/api/v1/native/version/trae/latest`。
- API/URL 返回 `2.3.61406`，同一真实 DMG 的 Info.plist 返回 `3.5.81`。
- 网络响应不发布 `appVersion`，因此没有可与扫描结果同构的远端版本。

## Changelog
- 官方 `https://www.trae.ai/changelog` 可作为人工页面，但没有安全检测源时不单独注册。

## 一键安装
- 状态: 不支持；检测版本未解决前禁止接入。

## 已知问题
- 直接比较会永久漏报或制造幽灵更新，违反 probe 安全约束。

## 建议下一步
1. 等待上游 API 发布 `appVersion`，或在应用更新流量中找到同构端点。
2. 不要把 `tronBuildVersion` 当作 `CFBundleVersion`。

