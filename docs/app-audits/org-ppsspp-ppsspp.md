# PPSSPP

## 已接入的副本

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网免费正式版 `org.ppsspp.ppsspp` | 从官方下载页的免费 macOS 按钮读取版本 | 同一按钮提供该版本的 universal DMG，换包前检查签名、Team ID 和 bundle ID | 从官网正式发布索引打开最新发布文章，按详细日志中的版本和分类分组 |
| Homebrew `ppsspp-emulator` | cask 指向同一官网 DMG，当前版本由现有 Homebrew 路径判断 | 用现有 Homebrew 路径管理已登记的副本 | 同 bundle ID，可复用官网发布说明 |
| GitHub 免费正式 ZIP | 同 bundle ID 和正式版本字段，可检测最新版本 | 1.20.4 的 GitHub ZIP 是 ad hoc 签名，没有 Team ID 可与官网包匹配，走厂商下载页 | 同 bundle ID，可复用官网发布说明 |
| 付费 Gold | macOS 版 bundle ID 为 `org.ppsspp.ppssppgold` | Gold 有独立的购买分发入口 | 本次覆盖免费直装版 |
| GitHub CI 开发包 | 实查的开发包使用免费版 bundle ID，两个版本字段均为空；正式版配方也要求安装副本已有纯数字点分版本 | 开发包没有可供此配方使用的正式版身份 | 官网开发页列出构建和提交，正式版文章不跟踪该轨 |

官方下载页将当前免费 DMG 与 Gold 下载、历史版本表分开。版本来自该 DMG 地址的目录名。两个或三个数字组件由探针按点连接，安装地址仍读取同一按钮的原始 URL。

官网日志使用发布文章自己的链接。一个文章可包含多个补丁版本，例如 1.20.3 在 1.20 系列文章。详细日志中的分类以段落和子列表编码，解析为独立小标题。当前呈现最新文章中列出的版本。

## 夜扫覆盖

- `vendor:org.ppsspp.ppsspp:stable` 检测当前免费 DMG，`install:vendor:org.ppsspp.ppsspp:stable` 检查下载和包内身份。官网下载页没有提供独立的 DMG 摘要或 Sparkle 公钥。
- `changelog:org.ppsspp.ppsspp:-` 检查官网发布索引和详细日志的提取。Gold 和开发包有独立的分发入口，未登记为免费正式版目标。

2026-11-28，本批用签名 Release CLI 对正式轨运行 `duo verify --vendor --changelog` 和 `duo verify-install --full`，该应用的版本源、日志和安装包均为 `ok`。

## 历史与实测

2026-11-28 核对官网免费版 DMG。1.20.3 和 1.20.4 均为 universal macOS app，bundle ID 为 `org.ppsspp.ppsspp`，Team ID 为 `97NS59EENG`，通过严格代码签名和 Gatekeeper 公证验证。GitHub 1.20.4 ZIP 的营销版本和构建版本也都是 1.20.4，但签名为 ad hoc。开发包的空版本字段使其在应用扫描阶段就被略过。

[官网下载](https://www.ppsspp.org/download/) · [1.20.4 正式发布](https://www.ppsspp.org/news/release-1.20.4/) · [1.20 系列发布文章](https://www.ppsspp.org/news/release-1.20/) · [GitHub 1.20.4](https://github.com/hrydgard/ppsspp/releases/tag/v1.20.4) · [上游 Gold 包身份](https://github.com/hrydgard/ppsspp/blob/v1.20.4/macOS/InfoGold.plist) · [官网开发构建](https://www.ppsspp.org/devbuilds/) · [实查的上游 CI run](https://github.com/hrydgard/ppsspp/actions/runs/46021421909)

2026-11-28，在 Apple Silicon、macOS 27.3 上用签名 Release CLI 验证 1.20.3 → 1.20.4。官网下载 37,090,805 字节，停用副本实际原地替换成功。升级后复查为最新，bundle ID、原厂 Team、严格签名和公证均通过。生产日志路径读出 1.20.4 的 30 条说明及 5 个原厂章节。
