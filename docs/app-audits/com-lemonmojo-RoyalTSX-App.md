# Royal TSX

## 官网分发与更新轨道

| 副本 | 真实版本 / build | 包内更新源 | 一键校验 |
|---|---|---|---|
| v6 正式版 | 6.4.4 / 6.4.4.1000、6.4.5 / 6.4.5.1000 | [v6 stable Sparkle](https://royaltsx-v6.royalapps.com/updates_stable) | DMG，厂商使用旧 DSA；DuoUpdater 检查 Developer ID、Team ID 和 bundle ID |
| v26 测试版 | 26.0.20 / 26.0.20.0 | [v26 Sparkle](https://royaltsx-v26.royalapps.com/app/updates) | DMG，包内有 Ed25519 公钥，feed 提供 `sparkle:edSignature` |

两条轨道使用同一个 bundle ID `com.lemonmojo.RoyalTSX.App`，分别读取各自声明的 feed。v6 两个实测包的 Team ID 都是 `VXP8K9EDP6`。v6 feed 的 14 个条目走默认轨道，v26 feed 的 20 个条目均标为 `beta`。现有 Sparkle 源通过 v26 已安装 build 在 feed 中的匹配识别可用标签。若旧 beta build 已从 feed 移除，通用推断可能拿不到标签。厂商还提供应用内的 Include Beta releases 开关，DuoUpdater 沿用包内声明的源，启用开关后的 v6 → v26 迁移尚未验证。 [正式版发布记录](https://community.royalapps.com/t/royal-tsx-v6-release-notes/243) · [测试版开启说明](https://community.royalapps.com/t/royal-tsx-beta-release-notes/2214)

## 更新检测、一键升级和更新日志

- **检测**：2026-11-16 在 Apple Silicon VM 用生产 CLI 检测，正式版 6.4.4 由 Sparkle 提供 6.4.5，更新后复查为最新。
- **一键升级**：同一轮的正式版 6.4.4 → 6.4.5 真实一键原地替换成功，下载 41,928,074 字节。新包的严格签名和公证通过，Team ID 与旧包一致。测试时应用已退出。
- **更新日志**：v6 和 v26 的 feed 都以内联 HTML 提供发布说明。条目前的 stylesheet `<link>` 曾被识别为列表开头，导致标题和首条说明一起消失。通用 HTML 解析现在按 `<li>` 的标签边界匹配。6.4.5 的实测 feed 片段纳入回归测试，固定 `Bugfixes` 标题文字和三条原始说明的顺序。

## 夜扫覆盖

- feed 验证用同一 bundle ID 下独立的 `stable` 和 `beta` 条目。
- 安装字节验证分别使用 `install:sparkle:com.lemonmojo.RoyalTSX.App:stable` 和 `install:sparkle:com.lemonmojo.RoyalTSX.App:beta`。v26 使用实包 `SUPublicEDKey` 检查 Ed25519；v6 只提供 DSA，因此夜扫只检查安装包身份和签名。
