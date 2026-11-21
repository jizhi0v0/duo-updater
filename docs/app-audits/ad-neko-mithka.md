# Mithka

## 分发与更新检测

- Telegram 客户端，GitHub 桌面版的 Bundle ID 为 `ad.neko.mithka`。已核对 1.10.3、1.11.8、1.12.8 和 1.13.4 Nightly 的真实包。GitHub 版最低 macOS 12，1.10.3 使用 universal ZIP，1.11.8 起发布分架构的 ZIP。规则接受 arm64 和旧 universal 文件名。
- 规则读取 `iebb/mithka` 的 `/releases/latest`，以 `vX.Y.Z` tag 对比 `CFBundleShortVersionString`。例如 1.12.8 的 `CFBundleVersion` 是 26111503。早期稳定 tag、测试发包和 Nightly 的发布形态见 [GitHub Releases](https://github.com/iebb/mithka/releases)。
- GitHub Nightly 的 tag 带 `-nightly.DATE.COMMIT`，真实 macOS 包和 Stable 共用名称、Bundle ID、ad-hoc 签名及纯数值营销版本，构建号使用同一日期格式。Duo 对直下副本使用 Stable 源。新版 Nightly 不会被降级，营销版本落后于 Stable 的 Nightly 会收到 Stable 更新提示。独立 Nightly 跟踪需要能区分这两类副本的信号。
- App Store 和 TestFlight 的同 ID 副本由原有商店分发路径处理。GitHub 发布使用独立的桌面包。1.12.8 的 [厂商更新客户端](https://github.com/iebb/mithka/blob/v1.12.8/lib/update/release_feed.dart) 的原地更新包选择只覆盖 Linux 和 Windows。

## 一键安装

GitHub 直下包是 ad-hoc 签名，签名标识为 `ad.neko.mithka`，通过严格签名校验。Duo 复用 `publishedDigestOnly` 路径。默认仅检测。启用「无开发者签名的 app 按文件哈希一键更新」后，还须取得所选 ZIP 的 GitHub SHA-256 摘要并通过安装身份校验。Gatekeeper 对这个 ad-hoc 包的评估仍为 rejected。

## 更新说明

沿用 GitHub 发布正文与发布页入口。`channel-verify` 在 1.10.3 真包上解析出 1.12.8 的一条结构化版本记录，含中英两段维护说明，详见 [发布记录](https://github.com/iebb/mithka/releases/tag/v1.12.8)。

## 夜扫覆盖

`duo verify --github --only ad.neko.mithka` 枚举 `github:iebb/mithka:stable`，`duo verify-install --only ad.neko.mithka --full` 检查完整 arm64 ZIP。Nightly 与商店分发不在这个 GitHub Stable 夜扫项内。
