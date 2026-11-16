# RapidAPI for Mac / Paw

## 基本信息

- Bundle ID：`com.luckymarmot.Paw`；Paw 和改名后的 RapidAPI for Mac 沿用此 ID。
- 分发：[官网](https://paw.cloud/)、Homebrew cask `rapidapi`；官网 ZIP 为通用二进制。
- 当前包 4.5.5 / 4005005001，最低 macOS 13；签名 Team `84599RL58A`（Paw Inc.）。
- 自更新：Sparkle，包内没有 `SUFeedURL`，有 delegate `feedURLStringForUpdater:`。本次用 `SparkleFeedCatalog` 补全官方 [appcast](https://paw.cloud/api/v2/updates/appcast)，保留已安装副本的密钥与既有校验规则。
- [官网兼容性公告](https://paw.cloud/)说明 macOS 27 及之后版本不再由 Nokia 测试、认证或正式支持。这是厂商兼容性限制，未给产品终止日期；不据此添加 `ProductSunset`。本次 VM 的包替换结果不代表完整业务功能获厂商支持。

## 覆盖矩阵

| 副本组 | 检测 | 一键安装 | 结构化更新日志 |
|---|---|---|---|
| 官网 RapidAPI，带 Ed25519 key | Sparkle feed 补全 | 同 Team、代码签名及 EdDSA 闸 | 官网 archive recipe，保留分节 |
| 官网 Paw / RapidAPI，DSA-only | 同一 stable feed | 同 Team 与代码签名闸；Duo 不验 DSA | 同一 archive recipe |
| 历史 Mac App Store Paw 2 | 保留现有 MAS 识别路径 | 不在本次官网替换范围 | 不宣称已验证 |

[官方 MAS 迁移文档](https://paw.cloud/docs/getting-started/migrate-from-appstore)要求先运行旧 MAS 版以保存许可，再手工安装官网版。不能把官网包覆盖当作许可迁移验证。没有添加 MAS 到官网的强制迁移。

## Channel 与副本组

- 官方 feed 的条目均为不带 `sparkle:channel` 的 stable；未发现单独 beta/RC feed 或同 ID 的独立 edition，故不加 ChannelBinding。
- 4.5.5、4.5.4 的 `SUPublicEDKey` 为 `EbtjNsFuPe0o0UZDSFr/514GIusvouXngkfdmiKApHY=`。
- 4.5.2 与 Paw 3.4.0 没有 Ed key，仅有 `SUPublicDSAKeyFile=dsa_pub.pem`。本次夜扫将两组分开，避免用新副本的 key 冒充旧副本的信任锚。
- 实测四个版本 ID、Team 相同，都是 universal、严格签名及 Notarized Developer ID 通过。Paw→RapidAPI 的名称变化不需要 BundleIDMigration。
- 更早历史包没有穷举签名团队；1.0.1、3.2.1 的公开包请求返回 403。未知旧 signer 仍受安装前 Team 闸保护，没有为绕过旧 signer 添加例外。

## 更新检测与日志

复用 `SparkleAppcastSource` 的 build/short-version 比较、最低系统判断、签名元数据和 ZIP 安装路径。当前版最低 macOS 13，在 Duo 支持的 macOS 15+ 主机上没有最低系统缺口。官网明确不支持 macOS 27+，见上文。

[完整更新历史](https://paw.cloud/updates)中，每个 `<article class="article-version">` 有版本链接、日期和变更正文。recipe 从链接读取版本，避免把 macOS badge 当版本；同时读取 `li` 和 `p`，并保留 `h4.update-type` 的 Fixes / New / Improvements 标题。feed 仅给每版 webview 链接，不内联说明，故使用完整 archive，而非依赖原文网页。

## 增量与自更新并发

公开 appcast 没有 delta 项，Duo 下载完整 ZIP。包内 Sparkle 存在，因此沿用现有自更新检测、暂存避让及安装事务；未增加第二套下载、后台任务或运行时查询。运行中端到端结果与能力边界在下文记录。

## 一键安装

本次待整批 VM 验证完成后记录旧版→新版替换、运行中退出/重开、数据保留及签名结果。

## 历史与实测

2026-11-16：读取官方 appcast 102 项；没有 channel 标签或 delta。官网 archive 有 103 个版本 article，首版 1.0 仅有标题没有变更条目；有效变更可由现有 extractor 读取，界面最多保留最近 40 条。4.5.5 为 2026-04-20；4.5.0 的变更用段落，3.1.8 用列表且有 Improvements / Fixes 两节，回归 fixture 覆盖这三种结构和外围导航污染。

4.5.5、4.5.4、4.5.2、3.4.0 的真实包均读取了 Info.plist、架构、签名团队，并执行 `codesign --verify --deep --strict` 和 `spctl -a -vv -t exec`，全部通过。它们均无 `SUFeedURL`；前两者有 Ed key，后两者无 Ed key。

## 夜扫覆盖

通用 feed inventory 新增以下两个精确 ID：

- `sparkle:com.luckymarmot.Paw:stable:ed25519`
- `sparkle:com.luckymarmot.Paw:stable:legacy-dsa`

安装字节监控对应 `install:` 前缀。另有 `feed:com.luckymarmot.paw` 监控 feed catalog；`changelog:com.luckymarmot.Paw:stable` 监控 archive recipe（最终 ID 以枚举器输出复核）。旧组在 `unavailablePublicKeys` 明确记录无 Ed key；它仍参与包身份读取，不冒充 EdDSA 验签成功。

整批 CLI 的精确集合、实际下载和实时解析结果将在本次实现的验收记录中补充。没有替换既有 identities/baseline，也没有添加签名失败豁免。
