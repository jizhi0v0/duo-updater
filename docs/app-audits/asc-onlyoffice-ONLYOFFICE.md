# ONLYOFFICE Desktop Editors

## 已接入的副本

| 副本 | 检测 | 一键升级 | 更新日志 |
|---|---|---|---|
| Apple Silicon 官网正式版 `asc.onlyoffice.ONLYOFFICE` | 读取包内 ARM Sparkle feed | 通用 Sparkle 路径验证完整 ZIP 的 Ed25519 签名和换包身份，也可按现有路径处理适用的差分 | 官方帮助中心逐版日志，保留原厂分节和迁移说明 |
| Intel 官网正式版，在支持 Rosetta 的 Apple Silicon 上 | 读取包内 x86_64 Sparkle feed | 同一 Sparkle 路径，仅在宿主能运行 Intel 包时提供该架构的更新 | 同一份 Desktop Editors 日志 |
| 使用旧 feed 的 Intel 官网副本 | 原始 feed 最新为 6.4.1/519 | 6.4.1 厂商包改用 x86_64 feed，旧副本可经此桥接至当前 Intel 发布路径 | 同一份 Desktop Editors 日志 |
| Homebrew `onlyoffice` | cask 的 Apple Silicon 安装资产为厂商 ARM DMG，保留现有 Homebrew 管理路径 | 由 Homebrew 更新其管理的副本 | 同一份 Desktop Editors 日志 |
| Mac App Store 的 ONLYOFFICE Documents | `com.onlyoffice.Documents` 是可在 Apple Silicon Mac 使用的移动版，走 App Store | 由 App Store 更新 | 使用该商品自己的发布说明 |

官网包的 ID 和签名 Team 在已检查的 Intel 与 ARM 副本间相同，架构由各自的 `SUFeedURL` 区分。保留包内 feed 就能区分当前 ARM、当前 Intel、旧 Intel 三组。旧 Intel 包的第一步是官方桥接版 6.4.1，现有 Sparkle 规则接着读取桥接版声明的当前 Intel feed。Intel 更新依赖 Rosetta 及宿主系统支持。

10.0 重写了应用。厂商提示部分设置需要重填，包括云端登录和自定义用户名。结构化日志在普通改动之前展示这段提示。Sparkle 的 9→10 报价沿用现有的大版本确认，用户需单独确认升级。

## 夜扫覆盖

- `install:sparkle:asc.onlyoffice.ONLYOFFICE:stable:arm64` 检查当前 ARM feed 和完整 ZIP。
- `install:sparkle:asc.onlyoffice.ONLYOFFICE:stable:intel` 检查当前 Intel feed 和完整 ZIP。
- `install:sparkle:asc.onlyoffice.ONLYOFFICE:stable:legacy-intel` 检查原始 Intel feed 和桥接版完整 ZIP。
- 三组公钥均从各自安装副本读取，为 `N2LfKoNN6LkD5qNMjt+lEh6LYrQMEFNCEXQ3Kk6nTlM=`。Intel 目标的解析沿用生产 Sparkle 的 Rosetta 检查。
- `changelog:asc.onlyoffice.ONLYOFFICE:-` 检查官方文档中逐版本提取的更新日志。

## 历史与实测

2026-11-28 检查了 ARM 9.4.0/563 的官网 DMG、10.0.0/564 的官网 DMG 和 Sparkle ZIP。还检查了 Intel 的 6.1/443、6.4.1/519、10.0.0/564 官网 DMG。所有副本的 bundle ID 为 `asc.onlyoffice.ONLYOFFICE`，Team ID 为 `2WH24U26GJ`，通过严格代码签名和 Gatekeeper 公证检查。

同日 ARM 和当前 Intel appcast 均提供 10.0.0/564 与带 Ed25519 签名的架构专用 ZIP，另列从 563、562、561 构建开始的差分。原始 `/mac/onlyoffice.xml` 的完整 6.4.1 ZIP 地址仍响应。6.4.1 官网 DMG 内的 feed 已切换到 `/mac/x86_64/onlyoffice.xml`。已核对的公开 Mac feed 为正式版。

解析同日官方帮助中心的原始 HTML 得到 59 个版本。10.0.0 有 81 条内容和 10 个标题，第一条保留厂商的重写迁移说明。9.4.0 有 12 条内容和 7 个标题。迁移说明的 HTML 省略 `</p>`，回归样例保留了这段结构。

[官网下载](https://www.onlyoffice.com/download-desktop) · [Desktop Editors 厂商发布](https://github.com/ONLYOFFICE/DesktopEditors/releases) · [官方版本历史和迁移说明](https://helpcenter.onlyoffice.com/desktop/desktop-changelog) · [6.1 的 Rosetta 支持说明](https://www.onlyoffice.com/blog/2020/12/onlyoffice-desktop-editors-6-1-goes-to-arm-based-apple-silicon-macs) · [App Store 的 ONLYOFFICE Documents](https://apps.apple.com/us/app/onlyoffice-documents/id944896972?platform=mac)
