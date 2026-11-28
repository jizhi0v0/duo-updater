# Sigil

| 交付项 | 官网直装副本 |
|---|---|
| 检测 | 从[官网最新下载](https://sigil-ebook.com/sigil/download/)的 macOS ARM 链接读取版本。GitHub 标签和文件名须重复同一版本 |
| 一键安装 | 从同一版本的官方 GitHub TXZ 解出原生 arm64 应用，继续使用现有的同 Team、同 bundle ID 与代码签名检查 |
| 更新日志 | 解析官网链接的 [ChangeLog.txt](https://github.com/Sigil-Ebook/Sigil/blob/master/ChangeLog.txt)，按版本保留 Bug Fixes 和 New Features，合并折行条目 |

官网和 GitHub 发布资产使用同一 bundle ID `com.sigil-ebook.Sigil.app`。2.8.1 和 2.8.6 的 ARM 真包在 macOS 27.2 Apple Silicon VM 上通过严格签名和 Gatekeeper 公证检查。短版本和 build 均与下载标签相同。2.8.6 的 Intel 真包在 Apple Silicon 本机只读核对，保留同一 ID、版本和 Developer ID Team `2SMCVQU3CJ`，也通过严格签名和公证检查。当前官方包最低要求 macOS 13。

## 副本覆盖

- [官方 2.0.0](https://github.com/Sigil-Ebook/Sigil/releases/tag/2.0.0) 起分发 ARM 和 Intel 包。1.9.30 和 1.5.0 Beta 官方包仅有 Intel slice，需 Rosetta 才能在可运行 DuoUpdater 的 Apple Silicon 主机上运行。两包均实查为上述 bundle ID 和 Team，严格签名检查通过。配方向同 ID 的直装副本提供厂商当前原生 ARM 包。
- 1.5.0 Beta 实包版本为裸数字，二进制与 1.9.30、2.8.1、2.8.6 一样读取公开 [version.xml](https://raw.githubusercontent.com/Sigil-Ebook/Sigil/master/version.xml)。厂商使用同一个正式版更新提示将这一公开测试过渡到稳定版。2.0 的 [发布说明](https://github.com/Sigil-Ebook/Sigil/releases/tag/2.0.0) 另有面向插件作者的 Qt/PySide6 迁移信息。
- [旧版源码](https://github.com/Sigil-Ebook/Sigil/blob/0.8.900/src/Resource_Files/mac/MacOSXBundleInfo.plist) 已使用同一 bundle ID。历史 [0.8.900](https://github.com/Sigil-Ebook/Sigil/blob/0.8.900/src/Misc/UpdateChecker.cpp) 和 [0.9.991](https://github.com/Sigil-Ebook/Sigil/blob/0.9.991/src/Misc/UpdateChecker.cpp) 预发布版也读取仓库的同一 XML。不同 Team 或无可用签名的自行构建副本会被安装身份检查拒绝。独立的 PageEdit 有自己的 [发布仓库](https://github.com/Sigil-Ebook/PageEdit/releases)。
- Homebrew 管理版继续使用现有 cask 管理路径。官网安装包没有 `SUFeedURL`，厂商的 `version.xml` 提示新版后交由用户下载。

## 夜扫覆盖

- `duo verify --only com.sigil-ebook.Sigil.app` 选择 `vendor:com.sigil-ebook.Sigil.app:stable` 和 `changelog:com.sigil-ebook.Sigil.app:-`。
- `duo verify-install --full --only com.sigil-ebook.Sigil.app` 以 `vendor:com.sigil-ebook.Sigil.app:stable` 检查当前官方 ARM TXZ 的实际下载和包身份。

这两项签名 Release CLI 检查均通过。完整下载的 2.8.6 TXZ 解包后为同 ID、同 Team。

## 历史与实测

2026-11-28，官网 ARM 下载链接、[2.8.6 发布资产](https://github.com/Sigil-Ebook/Sigil/releases/tag/2.8.6) 与官方 XML 都指向 2.8.6。2.8.5 的 GitHub 发布页没有 macOS 资产，官网最新下载按钮直接给出实际发布的 2.8.6 ARM 资产。两份 ARM TXZ 用 macOS 自带的 tar 解包后，`codesign --verify --deep --strict` 通过，Gatekeeper 显示 `Notarized Developer ID`。厂商日志在 2.8.6 下列出 EPUB 3 封面更改可能损坏 OPF 清单的修复。

VM 用签名 Release CLI 检出 2.8.1 → 2.8.6，在应用关闭时下载官网 ARM TXZ 并原地升级。升级后显示已是最新版，严格签名和公证通过，包内容与厂商原包一致。生产日志面板保留 2.8.6 的 Bug Fixes 标题及六条更新。
