# BlockBlock

## 分发与更新入口

- Objective-See 官网的下载区提供正式版版本、GitHub Release ZIP 和 SHA-256。测试版本的 ZIP 包含厂商交互安装器。[BlockBlock 官网](https://objective-see.org/products/blockblock.html) · [GitHub 发布](https://github.com/objective-see/BlockBlock/releases)
- 默认扫描目录中的 `/Applications/BlockBlock Helper.app` 是菜单栏界面的签名副本，bundle ID 为 `com.objective-see.blockblock.helper`。安装器同时管理 `/Library/Objective-See/BlockBlock/BlockBlock.app`。以 Helper 作为 Duo 的单一更新入口，避免为同一安装公开两条更新入口。
- Duo 的灰色 Update 校验下载摘要、安装器签名、Team ID、bundle ID 和版本，在用户会话打开厂商安装器。用户在厂商界面确认后由 macOS 处理管理员授权。厂商另行引导用户前往系统设置授予 Full Disk Access。Duo 的后台更新和 Update All 跳过交接。
- 可识别的 Homebrew 副本保留已有 Brew 更新路径。其 cask 通过独立的提权脚本管理安装和卸载。[Homebrew cask](https://formulae.brew.sh/cask/blockblock)

## 历史与实测

- 2026-11-22，官网和 GitHub 均发布 2.5.2 的同一个 ZIP 和相同 SHA-256。安装器 bundle ID 为 `com.objective-see.blockblock.installer`，Team 为 `VBG97UB4TA`。
- Apple Silicon macOS 27.2 VM，从厂商安装器安装 2.5.1，再通过厂商界面确认和授权升级至 2.5.2。两处签名 bundle 均升级到 2.5.2。未授予 Full Disk Access，测试范围为安装和版本更新。
