# Private Internet Access

## 分发与渠道

- 厂商桌面版 `com.privateinternetaccess.vpn` 使用带特权 helper 的签名 ZIP。稳定版发布记录按版本提供 Mac 下载和 SHA-256。[厂商发布记录](https://www.privateinternetaccess.com/pages/changelog)
- 厂商桌面版设置中的 Receive Beta Updates 允许同时查看稳定版和 Beta。Duo 读取系统范围内 PIA 自己的更新设置，尊重已知的稳定和 Beta 选项。自定义渠道留在厂商应用内处理。[厂商设置说明](https://helpdesk.privateinternetaccess.com/hc/en-us/articles/46777259429531-macOS-Installing-and-Using-the-PIA-App) · [3.8.0 更新选择源码](https://github.com/pia-foss/desktop/blob/3.8.0/daemon/src/updatedownloader.cpp)
- Beta 接口提供版本和下载链接。缺少厂商发布的摘要时保留版本检测，由 PIA 自身处理 Beta 安装。启用 Beta 的用户仍可从官网发布记录获得更新的稳定版。
- App Store 副本由商店更新。Homebrew 管理的副本沿用原有 Homebrew 路径。直接安装的厂商副本按上述设置选择来源。厂商安装器的目标固定，使用其他安装位置的副本保留官方网页入口。

## Changelog

- 官网 /pages/changelog 的 Stable 发布记录按独立 release article 分段，版本标题、发布日期和变更列表属于同一个版本。新增 ChangelogRecipe 负责原生版本历史；现有 VendorProbeRecipe 仍独立负责版本、Mac ZIP 和 SHA-256。
- 原生说明保留 Windows、Linux/macOS、macOS、All 等原文标记，不把跨平台内容误当成 macOS 专属。下载链接和 SHA-256 校验段落不作为更新条目。
- Beta 共用官网 Stable 历史作为回退，不编造不存在的 Beta 发布条目。解析失败时沿用官网 WebView 兜底。

## 安装器交接

灰色 Update 下载官网发布记录中的 Mac ZIP，校验摘要、Developer ID、Team ID、Bundle ID 和版本。Duo 在用户会话打开官方安装器，安装器向 macOS 请求管理员授权，并负责迁移应用和替换 VPN daemon。拒绝授权后用户可重试。Duo 的后台更新和 Update All 不触发这项交接。

## 历史与实测

- 2026-11-23，直接下载官网发布页原始 HTML，核对 7 段版本记录。生产 CLI 的 changelog 和 coverage 检查均为 `ok`。最新为 3.8.0（2026-10-15，5 条），上一版为 3.7.2（2026-03-19，1 条）。测试夹具保留官网的下载区、版本标题、日期、变更列表和校验段结构。

- 2026-11-22，厂商官网稳定版为 3.8.0，Mac ZIP 名为 `pia-macos-3.8-08539.zip`。同页列出 3.7.2（08420）的 Mac ZIP 和摘要。公开应用更新 API 的 GA 记录为 3.5.7，Beta 记录为 3.6.1-beta.2，因此稳定版采用当前官网下载记录。
- Apple Silicon macOS 27.2 VM，从厂商 3.7.2 升级到 3.8.0。签名 ZIP 与官网摘要一致。安装器直接打开 macOS 的 Install Helper 授权。拒绝授权时旧应用与 daemon 仍可用。授权后安装器将暂存应用迁移至 `/Applications/Private Internet Access.app`，应用及 daemon 均更新到 3.8.0。测试未连接 VPN。此处记录直接运行厂商安装器的验证。
