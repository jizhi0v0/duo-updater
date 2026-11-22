# Backblaze Computer Backup

## 分发与更新入口

- 官方桌面版 `com.backblaze.Backblaze` 安装在 `/Applications/Backblaze.app`。Backblaze 的版本化 DMG 同时提供安装器和卸载器。灰色 Update 只识别签名安装器 `com.backblaze.bzdoinstall`。[厂商升级说明](https://www.backblaze.com/computer-backup/docs/update-the-backblaze-client)
- Homebrew 的公开 cask 记录提供稳定版版本、厂商版本化 DMG URL 和 SHA-256。Duo 校验该摘要、Backblaze 的 Developer ID 和 Team ID、安装器标识与版本，再在用户会话打开安装器。已识别的 Brew 副本继续由原路径处理。[Homebrew cask](https://formulae.brew.sh/cask/backblaze)
- 交接到厂商窗口为止。用户自行确认安装和授权，Duo 不调用静默升级或卸载。自动更新和 Update All 跳过交接。非标准路径保留厂商网页入口。
- 此规则提供稳定版，新版本判断阻止向较新的 Beta 副本提供降级。实测公开 Beta 与稳定版当前共用一个安装包。未来出现不同的 Beta 构建时，其频道识别仍需验证。旧版独立偏好面板继续由厂商自身更新。[厂商 Beta 页面](https://www.backblaze.com/status/backup-beta)

## 历史与实测

- 2026-11-22，正式版 10.0.4.1082 的版本化厂商 DMG 与 Homebrew SHA-256 匹配；官方 Beta 页同日提供相同字节。安装器和卸载器均为 Team `G4K4BQ7S8J`，两者 bundle ID 不同。
- Apple Silicon macOS 27.2 VM 已打开正式版交互安装器。旧版 10.0.3.1076 的签名客户端提取自厂商现代安装包，作为交接夹具。VM 未配置 Backblaze 帐户或既有备份，既有备份身份与历史延续未经验证。
