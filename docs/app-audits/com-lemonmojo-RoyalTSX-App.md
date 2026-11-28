# Royal TSX

## 官网分发与更新轨道

| 副本 | 真实版本 / build | 包内更新源 | 一键校验 |
|---|---|---|---|
| v6 正式版 | 6.4.4 / 6.4.4.1000、6.4.5 / 6.4.5.1000 | [v6 stable Sparkle](https://royaltsx-v6.royalapps.com/updates_stable) | DMG，厂商使用旧 DSA；DuoUpdater 检查 Developer ID、Team ID 和 bundle ID |
| v26 测试版 | 26.0.20 / 26.0.20.0 | [v26 Sparkle](https://royaltsx-v26.royalapps.com/app/updates) | DMG，包内有 Ed25519 公钥，feed 提供 `sparkle:edSignature` |

两条轨道使用同一个 bundle ID `com.lemonmojo.RoyalTSX.App`，分别读取各自声明的 feed。v6 两个实测包的 Team ID 都是 `VXP8K9EDP6`。v6 feed 的 14 个条目走默认轨道，v26 feed 的 20 个条目均标为 `beta`。旧 v26 build 被移出 feed 后无法从 build 推断标签，Sparkle 源仅对该 bundle ID 与这个精确地址允许 beta-only feed 的条目。若将来该 feed 新增正式版条目，则走通用推断。v6 的 Include Beta releases 开关对应包内的 `UpdateURLBeta`。2026-11-28 实查两个 v6 feed 的最新可下载包是同一个 6.4.5.1000。v6 测试 feed 中唯一的 v26 条目没有安装包 URL，只链接到厂商的手动下载页。DuoUpdater 用 v6 包内的默认源检测可安装更新，已有 v26 副本走各自的 beta feed。 [v6 测试 feed](https://royaltsx-v6.royalapps.com/updates_beta) · [正式版发布记录](https://community.royalapps.com/t/royal-tsx-v6-release-notes/243) · [测试版说明](https://community.royalapps.com/t/royal-tsx-beta-release-notes/2214)

## 更新检测、一键升级和更新日志

- **检测**：2026-11-16 在 Apple Silicon VM 用生产 CLI 检测，正式版 6.4.4 由 Sparkle 提供 6.4.5，更新后复查为最新。
- **一键升级**：同一轮的正式版 6.4.4 → 6.4.5 真实一键原地替换成功，下载 41,928,074 字节。新包的严格签名和公证通过，Team ID 与旧包一致。测试时应用已退出。
- **更新日志**：v6 和 v26 的 feed 都以内联 HTML 提供发布说明。条目前的 stylesheet `<link>` 曾被识别为列表开头，导致标题和首条说明一起消失。通用 HTML 解析现在按 `<li>` 的标签边界匹配。6.4.5 的实测 feed 片段纳入回归测试，固定 `Bugfixes` 标题文字和三条原始说明的顺序。

2026-11-28，Apple Silicon、macOS 27.3 上用 Developer ID 签名 Release CLI 验证停用的 6.4.4 → 6.4.5。Sparkle 原地换包成功，下载 41,928,074 字节，原厂 Team、严格签名和公证复验通过，升级后为最新。最终生产日志路径读出 14 条，6.4.5 保留原生 `Bugfixes` 标题与三条正文。

## 夜扫覆盖

- `duo verify-install` 在解析两个独立的 stable/beta 目标时读取各自的 feed。`duo verify --feed` 没有 Royal TSX 的单独条目。
- 安装字节验证分别使用 `install:sparkle:com.lemonmojo.RoyalTSX.App:stable` 和 `install:sparkle:com.lemonmojo.RoyalTSX.App:beta`。v26 使用实包 `SUPublicEDKey` 检查 Ed25519；v6 只提供 DSA，因此夜扫只检查安装包身份和签名。
- 2026-11-28，在本批 `duo verify-install --full` 中，stable 6.4.5 和 beta 26.0.20 均为 `ok`。beta 整包 Ed25519 校验通过。
