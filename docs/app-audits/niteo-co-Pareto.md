# Pareto Security

2026-11-28 核实官网直接发行版。厂商的 GitHub 正式版和预发行版都使用三段数字版本，均提供同名 DMG。正式版和 Beta 使用同一 bundle ID，切换渠道由用户设置决定。[厂商发布](https://github.com/ParetoSecurity/pareto-mac/releases) · [厂商选版逻辑](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Pareto/Updater.swift)

## 覆盖矩阵

| 副本 | 检测 | 一键安装 | 更新日志 |
|---|---|---|---|
| 直接发行版，默认设置 | GitHub 正式发布 | 已签名、公证的 universal DMG | 当前正式发布的 GitHub 正文 |
| 直接发行版，启用 Beta | 接受正式和预发行，按最高版本选择 | 同一 DMG 规则 | 所选发布的 GitHub 正文 |
| Setapp | 独立 ID `niteo.co.Pareto-setapp`，由 Setapp 管理 | 由 Setapp 更新 | 官网规则仅匹配直接发行版 |

## 历史与实测

直接发行的 ID 是 `niteo.co.Pareto`，1.49.0、1.49.1 和 1.50.0 的实测 DMG 均无 Sparkle feed。历史标签包括正式版 `v1.22.0` 和预发行 `v1.7.74`，两份对应 DMG 的营销版本也都保留 `v`。两轨按标签原文核对签名包。0.0.19 之前没有预发行开关。0.0.19 至 1.9.0 的更新器读标准偏好 `betaChannel`。这些版本的 `showBeta`（如存在）控制实验界面。1.9.1 起更新器改读 `showBeta`，忽略遗留的 `betaChannel`。两代开关均默认关闭。[引入预发行开关](https://github.com/ParetoSecurity/pareto-mac/commit/179e7b9) · [切换偏好](https://github.com/ParetoSecurity/pareto-mac/commit/43af066)

启用后，即使当前为预发行 1.49.1，也应提示后来的正式版 1.50.0。厂商按 GitHub 的 prerelease 标记过滤，不能只按数字推测历史渠道。Homebrew cask 引用同一个直接发行的 DMG。[厂商偏好设置](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Pareto/Defaults.swift) · [Setapp 版 ID](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Config/App-SetApp.xcconfig)

| 官方包 | short / build | 实测或已核实的渠道信息 |
|---|---|---|
| 最早正式 0.0.13 ZIP | 0.0.13 / 639 | 同 ID，Team PM784W7B8X，universal |
| 预发行 v1.7.74 DMG | v1.7.74 / 5403 | 使用历史 betaChannel 偏好 |
| 正式 1.9.3 DMG | 1.9.3 / 5850 | 使用 showBeta 偏好 |
| 正式 v1.22.0 DMG | v1.22.0 / 6955 | 使用 showBeta 偏好 |
| 正式 1.49.0 DMG | 1.49.0 / 15803 | Team PM784W7B8X，universal，已公证 |
| 预发行 1.49.1 DMG | 1.49.1 / 15808 | 同上 |
| 正式 1.50.0 DMG | 1.50.0 / 15908 | 同上 |

## 一键安装

选择 `ParetoSecurity.dmg`。安装时核对签名包的营销版本与所选标签，拒绝误挂到新发布下的旧 DMG。主程序、登录项及可选的 `ParetoSecurityHelper` 均在 app 内。后者以 SMAppService daemon 注册，LaunchDaemon 的 BundleProgram 指向 `Contents/MacOS/ParetoSecurityHelper`。Firewall 等特权检查会查询 helper 版本，必要时由应用重新注册。最新版的 GitHub 正文含 “What's Changed” 标题和五项变更。[厂商 helper 管理](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Pareto/Extensions/HelperTool.swift) · [正式发布说明](https://github.com/ParetoSecurity/pareto-mac/releases/tag/1.50.0)

macOS 27.2 Apple Silicon VM 使用签名 Release CLI，将运行中的官方 1.49.0 原地升级至 1.50.0，随后由 Duo 重启主进程。严格签名、公证及升级后复查通过。实测开启 Beta 的 1.49.1 也提示 1.50.0；两轨各显示五项结构化变更，面板省略通用标题。

### 已授权的特权 helper

在同一 VM 启用 System Checks Access 并运行检查，确认旧 daemon 正在运行（构建 15803，PID 47584）。随后用签名 Release CLI 升级并重启主进程。新版第一次特权检查识别到 helper 1.0.4，预期为 1.0.5。注销旧服务成功，但首次重新注册返回错误 1，sudo 检查暂时不可用。

恢复方法已实测：在 Pareto Security → Preferences → Permissions 的 **System Checks Access** 一栏点击 **Authorize**，再运行检查。本次无需再次输入密码。新服务绑定构建 15908，以新 PID 48605 运行；应用确认 helper 1.0.5 已是最新。启动登录项仅负责在登录时打开主应用，随后退出。[登录启动器实现](https://github.com/sindresorhus/LaunchAtLogin/blob/v5.0.0/Sources/LaunchAtLoginHelper/main.swift)

## 夜扫覆盖

两条 GitHub 检测和安装规则随注册表自动枚举：

- `github:ParetoSecurity/pareto-mac:stable` 和 `github:ParetoSecurity/pareto-mac:beta`
- `install:github:ParetoSecurity/pareto-mac:stable` 和 `install:github:ParetoSecurity/pareto-mac:beta`

Beta 目标可合法地解析到较新的正式包。Setapp 版使用其独立分发机制。
