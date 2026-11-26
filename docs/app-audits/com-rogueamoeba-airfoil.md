# Rogue Amoeba

覆盖官网直发的正式版。各产品由原厂签名的实际包确认 bundle ID，主程序把更新地址藏在 `Protein.framework` 的运行时设置里。官网 feed 按主版本与本机 macOS 返回安装包，DuoUpdater 跟随其 enclosure 和重定向。替换前要求 ZIP 内的 app 与已装 bundle ID、Developer ID Team 一致，且构建号与 feed 完全一致。Audio Hijack 的独立记录见 [Audio Hijack](com-rogueamoeba-audiohijack.md)。

| 产品 | Bundle ID | 接入的正式版 | 一键换包实测 | 当前发布说明条目 |
| --- | --- | --- | --- | --- |
| Airfoil | `com.rogueamoeba.Airfoil` | 5.x | 5.11.9 → 5.13.0 | 2 |
| Airfoil Satellite for Mac | `com.rogueamoeba.AirfoilSpeakers` | 5.x | 5.12.6 → 5.13.0 | 1 |
| Farrago | `com.rogueamoeba.farrago` | 2.x | 2.1.5 → 2.2.0 | 19 |
| Fission | `com.rogueamoeba.Fission` | 2.x | 2.9.4 → 2.9.5 | 7 |
| Loopback | `com.rogueamoeba.Loopback` | 2.x | 2.3.5 → 2.5.1 | 2 |
| Piezo | `com.rogueamoeba.Piezo` | 1.x | 1.8.4 → 1.9.10 | 2 |
| SoundSource | `com.rogueamoeba.soundsource` | 6.x，以及 macOS 15、26 上的 5.x | 6.1.6 → 6.2.0，5.8.11 → 5.9.0（mini） | 21（6.x） |

Airfoil ZIP 同时带 Airfoil 和 Satellite，安装只选与正在更新的 bundle ID 一致的包。Satellite 自己的 feed 返回独立 ZIP。七个直发包均无 `SUPublicEDKey`，继续用 Sparkle 路径的代码签名校验。正式版 release notes 优先读 feed 中的 HTML 列表，官网产品发布说明用于回退。

旧版 Farrago 1 与 2、SoundSource 5 与 6 共用同一 bundle ID，属不同付费主版本。Farrago 1 最后支持到 macOS 13，DuoUpdater 当前支持的主机上不给它挂载 2.x feed。SoundSource 5 最后版本为 5.9.0，原厂包的 `RAMaximumButNotSupportedSystemVersion` 是 27.0，已装 5.x 走同代 feed 并受这个系统上限约束。同 bundle ID 的更早 Airfoil、Fission、Loopback、SoundSource 代际不满足当前支持的系统范围。厂商测试版需要在各自 app 中选择，公开正式版 feed 没有测试条目，本次只接正式版。 [原厂兼容性说明](https://rogueamoeba.com/status/) · [旧版与授权升级](https://rogueamoeba.com/legacy/)

Fission 和 Piezo 的旧 App Store 副本保留商店路由。当前 Homebrew cask 声明 `auto_updates: true`，Airfoil cask 同时登记两个 app。DuoUpdater 对已识别的套装成员仍优先由 Homebrew 管理。 [厂商 App Store 说明](https://rogueamoeba.com/support/knowledgebase/?showArticle=MiscMacAppStore) · [Airfoil cask](https://formulae.brew.sh/cask/airfoil)

## 夜扫覆盖

表中每个当前代际使用 `feed:<小写 bundle ID>` 和 `install:sparkle:<表中 bundle ID>:stable`。2026-11-26，`duo verify --feed --only rogueamoeba` 与 `duo verify-install --only rogueamoeba --full` 均通过 8 项，含已有的 Audio Hijack。安装包结果为本地首次观测。SoundSource 5 的包可从原厂归档读取，macOS 27 的正常更新评估会拒绝这一轨，暂未纳入当前 nightly 安装项。测试版和未使用 EdDSA 公钥的范围另记在公开 inventory。

## 历史与实测

### Recipes/com-rogueamoeba-airfoil.swift

2026-11-26。从官网正式版链接下载并读到 Airfoil 5.13.0、Satellite 5.13.0、Farrago 2.2.0、Fission 2.9.5、Loopback 2.5.1、Piezo 1.9.10、SoundSource 6.2.0。包内两个版本字段一致，Team ID 为 `7266XEXAPM`，通过严格签名验证。官网 feed 只写 `sparkle:version`，带 Sparkle 的 User-Agent 可从 `download.php` 获取 ZIP。

同日用 `system=1500`、`2670` 和 `2730` 检查同厂接口。不带 `version` 的 Farrago、Fission、Loopback、SoundSource 各返回旧主版。加入对应主版的 `version` 后，SoundSource 的 5.x 和 6.x 分别回 5.9.0、6.2.0，Farrago、Fission、Loopback 的 2.x 则返回当前 2.x。Farrago 1.6.8 和 SoundSource 5.9.0 也已从原厂归档取得，bundle ID 与当前代分别相同。 [原版软件包目录](https://rogueamoeba.com/legacy/downloads/)

同日在本机 macOS 27.3（26C5047e）把七个旧包作为临时副本放进用户扫描目录，按各自绝对路径用 `duo check` 检测，再用 `duo install --yes --route sparkle` 更新。七项均报告已实际换包，磁盘 inode 已变，两个版本字段、bundle ID、原厂签名和公证均通过，复查为 `up-to-date`。各产品测试时均未启动。SoundSource 6.1.6 来自原厂 CDN 的 Internet Archive 快照，已通过原厂签名校验。真实的 SoundSource 5.9.0 和 Farrago 1.6.8 在这台机器上均没有被提供跨代更新。

同日在 Apple Silicon Mac mini 的 macOS 26.7（25G229）上验证 SoundSource 5。用本分支构建并签名的 CLI 检查原厂 5.8.11 临时副本，Sparkle 仅提供 5.9.0。执行 `duo install --yes --route sparkle` 下载 41,954,766 字节，报告 `applied: true`。磁盘 inode 已变，两个版本字段均为 5.9.0，原厂签名与 Gatekeeper 公证校验通过，复查为 `up-to-date`。应用在测试时未启动。macOS 15 上的换包尚未实测。 [5.8.11 原厂 CDN 快照](https://web.archive.org/web/20251127121029id_/https://cdn.rogueamoeba.com/soundsource/download/SoundSource.zip)

各产品的 `channel-verify` 均返回 Sparkle 与结构化发布说明，条目数见表。厂商在描述里嵌入完整 HTML 文档，解析前截取其版本说明容器以去除文档外框。
