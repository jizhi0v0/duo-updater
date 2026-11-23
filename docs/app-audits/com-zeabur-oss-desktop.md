# Zeabur Desktop

## 覆盖清单

| 安装来源 | 观测身份 | 更新路径 |
| --- | --- | --- |
| GitHub Stable，首个桌面稳定版 0.3.0 | `com.zeabur.oss.desktop`，Team `6T873K59LQ`，arm64 | GitHub Stable 检测、官方 DMG 一键更新、结构化发布说明 |
| GitHub Beta，0.3.0-beta.1 至 beta.5 | 同一 Bundle ID，已核对 beta.1 和 beta.5 的 Team，版本含 `-beta.N` | GitHub Beta 检测，可更新到版本更高的 Beta 或 Stable，官方 DMG 一键更新、结构化发布说明 |
| 发布流程声明的 RC 产物 | `-rc.N`，当前发布列表中无公开 RC DMG | 沿用 Beta 更新路径，使用测试数据验证渠道与资产筛选 |
| 官方 tap 的 Stable 与 Beta cask | 两个 cask 使用各自版本的同一官方 DMG，均声明 `auto_updates true` | Duo 默认沿用已安装 cask 的 Homebrew 路径 |

0.2.0 及更早的 GitHub 发布没有桌面 DMG，Mac 产物是独立的 `zeaburctl`。本规则追踪 Desktop，独立 CLI 的 Homebrew 公式由 Duo Updater 的通用 Brew 入口管理。 [首个桌面 Beta](https://github.com/zeabur-oss/zeabur/releases/tag/v0.3.0-beta.1) · [0.2.0](https://github.com/zeabur-oss/zeabur/releases/tag/v0.2.0) · [zeaburctl 安装文档](https://oss.zeabur.com/docs/zeabur/reference/zeaburctl/)

`v0.3.0-beta.0` 源码 tag 已含 Desktop，GitHub Release API 对该 tag 返回 404。若有保留的同 Bundle ID 构建，其 `-beta.0` 版本仍走 Beta 检测，能否原位升级由现有签名校验决定。 [Beta 0 源码](https://github.com/zeabur-oss/zeabur/tree/v0.3.0-beta.0/desktop)

## 检测、一键更新与发布说明

- `ReleaseChannel.detect` 识别 Zeabur 预发布的 `-beta.N` 与 `-rc.N` 后缀。Stable 读取 GitHub 最新正式版。预发布读取 30 项发布列表，加入独立请求得到的最新正式版，再按版本选择可用的 Desktop 资产。这个顺序对应厂商 updater 的晋升规则。历史时间线只收录有对应 arm64 桌面 DMG 的条目。
- 厂商 Tauri updater 读取 `latest.json` 并验证其归档的 minisign 签名。Duo 选 GitHub 上文件名与标签对应的 `zeabur-desktop-v<VERSION>-darwin-arm64.dmg`，沿用资产摘要、Developer ID 和同一 Team 校验，并在替换前确认签名 App 的版本。
- 共用 GitHub release 正文，内容也涉及同仓库的服务端和 CLI。`GitHubMarkdownParser` 从 0.3.0 的正文提取了 3 项结构化摘要，厂商页面提供完整的段落说明。

[厂商更新选择](https://github.com/zeabur-oss/zeabur/blob/v0.3.0/desktop/src/update.rs) · [发布资产生成](https://github.com/zeabur-oss/zeabur/blob/v0.3.0/scripts/desktop-release.ts) · [RC 发布流程](https://github.com/zeabur-oss/zeabur/blob/v0.3.0/.github/workflows/release-pr.yml#L9-L10)

官方 cask 的 token 分别为 `zeabur-desktop` 和 `zeabur-desktop@beta`，安装后各自的 Brew receipt 保留管理权。 [Stable cask](https://github.com/zeabur-oss/homebrew-tap/blob/HEAD/Casks/zeabur-desktop.rb) · [Beta cask](https://github.com/zeabur-oss/homebrew-tap/blob/HEAD/Casks/zeabur-desktop%40beta.rb)

## 历史与实测

2026-11-23 挂载官方 0.3.0、0.3.0-beta.1 和 0.3.0-beta.5 DMG。三个包均为 `Zeabur.app`，严格签名通过，Team 均为 `6T873K59LQ`，两个版本字段与各自标签去掉 `v` 后一致。 [Stable](https://github.com/zeabur-oss/zeabur/releases/tag/v0.3.0) · [Beta 5](https://github.com/zeabur-oss/zeabur/releases/tag/v0.3.0-beta.5)

GitHub 当天共有 13 个公开 release，最前六个连续发布了桌面 DMG，观测到的匹配深度下限为一项。

Apple Silicon macOS 27.2 (26B123) VM 上，Developer ID 签名 Release CLI 检测并原位升级官方 0.3.0-beta.1 → 0.3.0。升级后签名、公证和 Stable 最新版检查均通过。0.3.0 是首个桌面 Stable，实测覆盖 Beta 晋升与 Stable 的当前版本检测。

## 夜扫覆盖

GitHub 注册表枚举 `github:zeabur-oss/zeabur:stable` 与 `github:zeabur-oss/zeabur:beta`。VM 中用 `--only com.burakgon.openscreens,com.zeabur.oss.desktop` 运行 `duo verify --github --no-installed` 和 `duo verify-install --full`，合计检查三条规则，均通过。Zeabur 的两条规则当前都选中并检查同一个 0.3.0 正式版 DMG。Beta 5 的 DMG 签名另行核对。
