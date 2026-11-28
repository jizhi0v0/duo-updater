# Pareto Security

2026-11-28 核实官网直接发行版。厂商的 GitHub 正式版和预发行版都使用三段数字版本，均提供同名 DMG。正式版和 Beta 使用同一 bundle ID，切换渠道由用户设置决定。[厂商发布](https://github.com/ParetoSecurity/pareto-mac/releases) · [厂商选版逻辑](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Pareto/Updater.swift)

## 覆盖矩阵

| 副本 | 检测 | 一键安装 | 更新日志 |
|---|---|---|---|
| 直接发行版，默认设置 | GitHub 正式发布 | 已签名、公证的 universal DMG | 当前正式发布的 GitHub 正文 |
| 直接发行版，启用 Beta | 接受正式和预发行，按最高版本选择 | 同一 DMG 规则 | 所选发布的 GitHub 正文 |
| Setapp | 独立 ID `niteo.co.Pareto-setapp`，由 Setapp 管理 | 由 Setapp 更新 | 官网规则仅匹配直接发行版 |

## 历史与实测

直接发行的 ID 是 `niteo.co.Pareto`，三个实测 DMG 均无 Sparkle feed。历史标签包括正式版 `v1.22.0` 和预发行 `v1.7.74`，两轨规则均接受可选的前导 `v`。读取该 ID 的标准偏好 `showBeta`，默认关闭。启用后，即使当前为预发行 1.49.1，也应提示后来的正式版 1.50.0。厂商按 GitHub 的 prerelease 标记过滤，不能只按数字推测历史渠道。Homebrew cask 引用同一个直接发行的 DMG。[厂商偏好设置](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Pareto/Defaults.swift) · [Setapp 版 ID](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Config/App-SetApp.xcconfig)

| 官方包 | short / build | 签名与架构 |
|---|---|---|
| 最早正式 0.0.13 ZIP | 0.0.13 / 639 | 同 ID，Team PM784W7B8X，universal |
| 正式 1.49.0 DMG | 1.49.0 / 15803 | Team PM784W7B8X，universal，已公证 |
| 预发行 1.49.1 DMG | 1.49.1 / 15808 | 同上 |
| 正式 1.50.0 DMG | 1.50.0 / 15908 | 同上 |

## 一键安装

选择 `ParetoSecurity.dmg`。安装时核对签名包的营销版本与所选标签，拒绝误挂到新发布下的旧 DMG。主程序、登录项及可选的 `ParetoSecurityHelper` 均在 app 内。后者以 SMAppService daemon 注册，LaunchDaemon 的 BundleProgram 指向 `Contents/MacOS/ParetoSecurityHelper`。Firewall 等特权检查会查询 helper 版本，必要时由应用重新注册。最新版的 GitHub 正文含 “What's Changed” 标题和五项变更。[厂商 helper 管理](https://github.com/ParetoSecurity/pareto-mac/blob/1.50.0/Pareto/Extensions/HelperTool.swift) · [正式发布说明](https://github.com/ParetoSecurity/pareto-mac/releases/tag/1.50.0)

macOS 27.2 Apple Silicon VM 使用签名 Release CLI，将运行中的官方 1.49.0 原地升级至 1.50.0，随后由 Duo 重启主进程。严格签名、公证及升级后复查通过。实测开启 Beta 的 1.49.1 也提示 1.50.0；两轨各显示五项结构化变更，面板省略通用标题。此次 VM 未注册可选的特权 daemon，其运行中交接尚未实测。

## 夜扫覆盖

两条 GitHub 检测和安装规则随注册表自动枚举：

- `github:ParetoSecurity/pareto-mac:stable` 和 `github:ParetoSecurity/pareto-mac:beta`
- `install:github:ParetoSecurity/pareto-mac:stable` 和 `install:github:ParetoSecurity/pareto-mac:beta`

Beta 目标可合法地解析到较新的正式包。Setapp 版使用其独立分发机制。
