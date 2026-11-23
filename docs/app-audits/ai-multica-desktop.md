# Multica

2026-11-23 接入调研。桌面应用与独立 CLI 共用 GitHub release 和版本号，安装与更新入口各自独立。

## 覆盖清单

| 安装来源 | 观测身份 | 覆盖路径 |
| --- | --- | --- |
| GitHub Desktop Stable | `ai.multica.desktop`，Team `Q85ULLN279` | GitHub Stable 检测、一键更新 DMG、结构化 changelog |
| 早期 Desktop | `com.multica.app`，0.1.0 源码及 0.1.7 真包，0.1.7 与新版同 Team | `BundleIDMigration` 识别早期版本，替换前单独确认。旧配置继承仍待验证 |
| 官方 Homebrew tap | `multica-ai/tap/multica` | Workbench Brew 复用 `BrewFormulaService`，当前公式从版本化 GitHub URL 推导 release notes |
| GitHub 独立 CLI | `multica`，Mach-O arm64，ad-hoc 签名 | 独立 provider，检测、验证发布包后原位更新、结构化 changelog |
| Desktop 内置 CLI | `Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica` | 跟随桌面包换版，CLI provider 排除位于 `.app` 内的副本 |

发布列表中的 176 个 release 均为稳定三段式标签。抽测的现行 DMG 是 arm64，最低 macOS 13.0.0。0.2.10 已用现行 Bundle ID，最低 macOS 12.0。早期 0.1.7 的 arm64 ZIP 通过公证校验，旧 Electron updater 指向同一仓库，但缓存名为 `multica-updater`。当前包的缓存名为 `@multicadesktop-updater`。历史包的配置迁移以及早期边界外的桌面产物仍需复核。[首发](https://github.com/multica-ai/multica/releases/tag/v0.1.0) · [0.1.7](https://github.com/multica-ai/multica/releases/tag/v0.1.7) · [0.2.10](https://github.com/multica-ai/multica/releases/tag/v0.2.10)

## 桌面检测、一键安装与 Changelog

- 复用 `app-responsively.swift` 的 GitHub provider 路径。版本用 `^v([0-9]+\.[0-9]+\.[0-9]+)$`，安装包用 `^multica-desktop-[0-9]+\.[0-9]+\.[0-9]+-mac-arm64\.dmg$`。`GitHubReleasesSource` 已会跳过当前平台缺安装包的 tag，例如 0.3.36 和 0.3.25，避免把只带 CLI 的 release 当成桌面更新。
- 复用默认的 Developer ID 安装信任与 GitHub asset SHA-256。Electron 配置是 `provider: github`，通用 `ElectronManifestSource` 需要包内声明的具体 URL。`latest-mac.yml` 首选 arm64 ZIP，另列 DMG。原生 updater 会自动下载，退出时应用，VM 已实测 Electron 下载完 ZIP 的场景，Duo 会提示用原生更新，`duo restart` 等待原生更新应用后再启动。
- `GitHubMarkdownParser` 可消费 release 正文的列表。0.11.1 的 55 条原始项目混合桌面、CLI 和服务端变更，两类产品可共享 release 正文。当前调研未验证 Workbench 的最终渲染。

[0.11.1 发布与变更日志](https://github.com/multica-ai/multica/releases/tag/v0.11.1) · [Desktop updater](https://github.com/multica-ai/multica/blob/v0.11.1/apps/desktop/src/main/updater.ts)

## 独立 CLI

官方脚本优先安装 Homebrew 公式，失败后取版本化 tarball，通常装到 `/usr/local/bin`，不可写时使用 `~/.local/bin`，也接受 `MULTICA_BIN_DIR`。官方 tap 的 `brew leaves` 和版本清单可沿用。公式的稳定 URL 直接指向 release asset，`BrewFormulaReleaseService` 能为公式当前版本推导 GitHub tag。较旧的已装版本没有专用的历史 tag 映射。 [官方安装脚本](https://github.com/multica-ai/multica/blob/v0.11.1/scripts/install.sh) · [公式](https://github.com/multica-ai/homebrew-tap/blob/main/Formula/multica.rb)

独立 provider 沿用现有无执行扫描惯例，按真实路径排除 Cellar、App bundle 和由其他管理器持有的文件。VM 的旧版与现行 Go 二进制均可读到 `-X main.version=`，可结合 Go package path / Mach-O 校验离线读版。`GoBuildInfo` 读取 linker flags，配合 Go package path 和 Mach-O 校验离线读版。安装时按架构选择版本化 tarball，兼容旧命名。使用官方 `checksums.txt`，GitHub 提供 asset digest 时还要核对两者一致。归档中只提取根目录的 `multica`。

官方 CLI 与 standalone daemon 有各自的更新入口。Daemon 在空闲时更新并重启，Desktop 管理的 daemon 跳过该自动更新。Duo 在下载前和替换前检查正在运行的同一路径进程。不可写的路径只显示更新，因为官方命令可能把 Homebrew 前缀下的独立副本按公式处理。替换前核对旧版二进制与官方归档一致，保留文件权限并原子替换。CLI 和 Desktop 的 release notes 取自同一份 GitHub 发布数据。[CLI 更新实现](https://github.com/multica-ai/multica/blob/v0.11.1/server/internal/cli/update.go) · [Daemon 更新实现](https://github.com/multica-ai/multica/blob/v0.11.1/server/internal/daemon/auto_update.go)

## VM 实测

- Apple Silicon、macOS 27.2。签名 Release 的 `duo check` 识别 0.11.0 → 0.11.1，`duo install --yes` 报告原位安装成功。严格签名、公证和升级后版本检查通过。
- 运行中的 Desktop 0.11.0 已暂存 0.11.1 的官方 ZIP 时，`duo install` 跳过，`duo restart` 完成厂商更新。磁盘版本为 0.11.1，新进程已启动，严格签名通过。
- 0.1.7 原版识别为可升 0.11.1。`--yes` 跳过，明确确认两个提示后，原位安装成功并读出新版 Bundle ID 和版本。严格签名通过。
- 独立 CLI 在隔离的 `MULTICA_BIN_DIR` 中经签名 Release 的 `duo list`、`duo check`、`duo install --yes` 完成 0.11.0 → 0.11.1。更新后的可执行文件与官方 tarball 二进制逐字节相同，第二次检查为最新。旧命名归档的 0.1.8 亦通过独立 CLI 原位升级。
- 官方 tap 安装 0.11.1 成功。`brew leaves` 的安装请求清单列出 `multica-ai/tap/multica`，可执行文件链接指向 Cellar。测试安装和 tap 已移除。
- 实际 `multica update` 请求遇到 GitHub 匿名配额耗尽的 HTTP 403。Duo 使用自己的 GitHub 请求和信任路径。带登录数据的旧 ID 迁移仍待实测。

## 夜扫覆盖

桌面 Stable 由 GitHub 注册表纳入夜扫，记录 ID 为 `github:multica-ai/multica:stable`。定向 `duo verify --github --only ai.multica.desktop` 与 `duo verify-install --only ai.multica.desktop --full` 均通过。当前夜扫安装器检查以 App bundle 身份为单位，独立 CLI tarball 由 provider 的测试及独立 VM 验证覆盖。
