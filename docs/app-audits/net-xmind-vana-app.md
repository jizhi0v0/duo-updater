# Xmind

## 分发和更新渠道

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版 `net.xmind.vana.app` | 官网正式下载入口的 HTTPS 重定向 | 安装同一次探测返回的版本化 universal DMG，要求已安装副本的公开发行标识 | 官网 Desktop 更新记录，保留版本、发布日期和章节 |
| 官网 Beta，同一 bundle ID | 包内短版本以 `-beta` 结尾，读取独立 Beta 下载入口 | 安装同一重定向中的 Beta DMG，校验 Beta 文件名与公开发行标识 | 独立 Beta JSON 中与该版本对应的编号条目 |
| Homebrew `xmind` / `xmind@beta` | 两个 cask 分别引用官网正式与 Beta 安装包，已有 Homebrew 源按实际托管状态处理 | 由现有安装来源决定 | 按包内发行轨选择同一份厂商日志 |
| Mac App Store `net.xmind.brownieapp` | 现有 App Store 路径 | 现有 App Store 路径 | App Store 版本历史 |
| XMind 8 Classic `org.xmind.cathy.application` | 厂商已停止维护，仍提供原授权对应的旧安装包 | 保留独立产品和原授权，官网新版的配方只针对新的 bundle ID | 原厂不再发布 Classic 更新 |
| 中小企业永久授权版、大客户定制包 | 厂商销售交付，未登记单独版本源 | 共享 ID 时，公开 DMG 的一键安装只接受 `app.asar/package.json` 中 `releaseType` 为 `vana_macosx` 的标准发行 | 未登记私有发行记录 |

正式和 Beta 入口使用相同的版本化文件名结构，Beta 文件名多一个 `-beta`。比较值等于包内短版本。DMG 文件名中的日期后缀用于定位原包，CFBundleVersion 另有一位尾数。官网旧域名和 Homebrew 下载使用 `xmind.net`，探针使用官网页面链接的 `xmind.app`，直接获得 HTTPS 的版本化归档地址。 [官网入口](https://xmind.com/download) · [正式版 cask](https://formulae.brew.sh/cask/xmind) · [Beta cask](https://formulae.brew.sh/cask/xmind@beta)

个人和商业订阅在公共客户端登录后解锁。中小企业永久授权和定制版由厂商销售交付，公开包内存在独立的企业版构建开关。公开发行的签名包实测使用 `releaseType: vana_macosx`，据此复用 `OneClickGate`。这也会保护版本相同但缺少已知发行标识的历史副本。 [订阅激活](https://xmind.cn/help/activate-subscription-macos) · [企业授权](https://xmind.cn/contact-sales) · [定制安装包条款](https://xmind.cn/legal/terms) · [App Store 身份](https://itunes.apple.com/lookup?id=1286983622&country=us) · [XMind 8 维护状态](https://xmind.com/help/can-i-still-use-xmind-8-pro)

## 夜扫覆盖

- `vendor:net.xmind.vana.app:stable` 和 `vendor:net.xmind.vana.app:beta` 分别验证官网正式和 Beta 入口。
- `install:vendor:net.xmind.vana.app:stable` 和 `install:vendor:net.xmind.vana.app:beta` 检查各自的 DMG 和包内身份，使用现有 Developer ID 验证。
- `changelog:net.xmind.vana.app:stable` 检查官网 Desktop 发布记录，`changelog:net.xmind.vana.app:beta` 检查厂商 Beta JSON。独立日志可避免 Beta 检查命中已有更新但显示正式版发行记录。
- App Store 副本由商店更新。停止维护的 Classic 无待跟踪版本源。企业自定义包的分发凭据和归档未进入公开夜扫。

## 历史与实测

2026-11-28，核对了正式版 27.01.05088（2026111107060）与 27.01.05089（2026111606400），以及 Beta 25.07.01031-beta（2025050623260）与 25.10.03031-beta（2025062907040）。四个官网 DMG 的 bundle ID 和 Team ID 均为 `net.xmind.vana.app` / `4WV38P2X5K`，严格代码签名和 Gatekeeper 公证检查通过。官网国际版和国内版的 27.01.05089 DMG 使用不同 CDN 域名，实测文件字节相同。 [国际版最新下载](https://xmind.app/zen/download/mac/) · [国内版最新下载](https://xmind.cn/zen/download/mac/) · [Beta 最新下载](https://xmind.app/desktop-beta/download/mac/)

正式版 Desktop 页面服务端返回三个版本，页面的响应式副本由现有提取器按版本去重。27.01.05089 和 27.01.05088 各有 6 条，27.01.05087 有 19 条并分成 3 节。Beta 的当前版本和 3 条编号说明来自真实 Beta 包内更新程序所使用的公开 JSON。 [官网正式日志](https://xmind.com/changelog) · [Beta JSON](https://www.xmind.app/xmind/update/beta-latest-mac.json)

官网签名包里的 Electron 更新代码按服务区请求厂商 JSON，并把 ZIP 交给 Squirrel。公开 DMG 的文件名同时包含营销版本和构建时间。两份 26.04.01341 官网 DMG 的包内 build 分别为 2026071207060、2026071300580，末尾的 0 之前是文件名中的时间。历史官网 Intel 版 10.3.1 直接使用 12 位 build `202101070049`。检测用这 12 位比较同版本重打包。

Quick Entry 是包内 `Contents/PlugIns/Xmind QuickEntry.app`（`net.xmind.vana.app.QuickEntry`），可独立随登录启动。若 Quick Entry 仍在运行，DuoUpdater 会先挡住换包。退出该副本的 Quick Entry 后再重试。 [Quick Entry 官方说明](https://xmind.com/user-guide/quick-entry-for-mac-new)

官网历史版 XMind 8 Update 9（`8_Update_9` / `3.7.9.201912052356`）的 DMG 使用 `org.xmind.cathy.application`，与现行产品的 bundle ID 分开。 [Classic 安装包](https://www.xmind.app/xmind/downloads/xmind-8-update9-macosx.dmg)
