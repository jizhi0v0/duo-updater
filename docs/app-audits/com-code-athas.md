# Athas

Tauri 与 GPUI 的正式发行包都叫 `Athas.app`，Bundle ID 为 `com.code.athas`，签名 Team ID 为 `N43BXFX4H4`。Apple Silicon 包的版本字段保留 `-beta.N` 后缀。0.19 起采用 GPUI，两代沿用同一条应用内更新路径。 [官方迁移说明](https://github.com/athasdev/athas/blob/v0.19.0-beta.4/docs/release-migration.md)

## 渠道与来源

| 副本 | 渠道依据 | 更新源 |
| --- | --- | --- |
| Tauri 至 0.16.1 | Stable | 官网副本走 Vendor，Cask 副本走 Homebrew |
| Tauri 0.16.2 至 0.18 | `com.code.athas/settings.json` 顶层 `updateChannel` | 同下 |
| GPUI 0.19 起 | `dev.athas.app/settings.json` 顶层 `updateChannel`，首启读取旧配置 | 官网副本走 Vendor。Cask 副本走 Homebrew，明确开启 Beta 后改查 Vendor。Duo Updater 内的 Homebrew Only 选择优先 |
| 旧 Athas Preview | 独立 Bundle ID `com.code.athas.preview` | 官方 `/api/update/preview` 返回 HTTP 204，历史预览包留在原渠道 |

两个配置文件都在 `~/Library/Application Support`。默认 Stable。版本号用于选择配置文件，实际发布渠道取应用设置。主线可从任一代向前更新，无需 Bundle ID 迁移。旧 Preview 的独立设置目录和 Bundle ID 对应独立安装，官方没有提供迁移更新。 [旧 Preview 打包配置](https://github.com/athasdev/athas/blob/v0.14.1-preview.5/src-tauri/tauri.preview.conf.json)

## 检测、一键安装与说明

- 版本取官方 `https://athas.dev/api/update/stable` JSON 的 `version`。Stable 请求只接受稳定版本，Beta 请求可以收到更新的预览版或转正版本。两条规则都要求 `platforms.darwin-aarch64.url` 指向同一版本的官方 GitHub 更新包。
- Vendor 一键安装使用官方 `Athas_aarch64.app.tar.gz`。Duo Updater 沿用签名、Team ID、Bundle ID 和架构校验。Athas 自更新器另用 minisign 验签。
- 两个渠道的结构化更新说明复用 GitHub Releases Markdown 解析。Beta 也显示已转正版本，并过滤历史的 `-preview.N` 发行包。 [GitHub Releases](https://github.com/athasdev/athas/releases)

Tauri 读取 UTF-8 JSON。GPUI 接受 UTF-8 JSONC 的注释和尾逗号，也用同样的格式读取首启时的 Tauri 配置。
配置语法错误或缺少有效的 Beta 选项时使用 Stable。GPUI 当前配置存在且可读时优先采用它。

## 夜扫覆盖

- 版本探测由 Vendor registry 枚举 `vendor:com.code.athas:stable` 和 `vendor:com.code.athas:beta`。
- 安装包检查由 `verify-install` 枚举对应两条 Vendor 规则。历史 Preview 源返回 204，没有可供检查的后续更新包。
- 2026-11-23，`duo verify --only com.code.athas` 的 2 条版本探测和 2 条结构化更新说明全部通过。`duo verify-install --only com.code.athas` 实际下载并检查 Stable 0.17.0 和 Beta 0.19.0-beta.4，两个 ID 均为 `ok`，这是首次身份观测。

## 历史与实测

- 2026-11-23，macOS 27.2 ARM VM。Athas 0.17.0 在设置里开启 Beta，写入 `"updateChannel":"beta"`，手动检查显示 `0.19.0-beta.4 available`。Athas 自更新器安装后从原路径重启 GPUI；两个版本字段均为 `0.19.0-beta.4`，签名校验通过，Bundle ID 和 Team ID 保持一致。
- 同日对官方端点分别发送 Stable 和 Beta 请求，得到 `0.17.0` 和 `0.19.0-beta.4` 的 Apple Silicon archive。Homebrew 的 `athas` Cask 装的是官方 0.17.0 DMG。 [Homebrew 配方](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/a/athas.rb)
- 实际解包两份更新 archive，两个版本字段都与 manifest 一致，`LSMinimumSystemVersion` 分别为 10.15 和 10.15.7。两包均通过 Gatekeeper 的 Notarized Developer ID 检查。
- 用签名 Release `duo` 在同一 VM 检查三份真实副本。官网 Stable 0.16.3 由 Vendor 提供 0.17.0，一键安装成功。Homebrew 0.17.0 在 Stable 设置下由 Homebrew 应答并显示最新。GPUI 0.19.0-beta.4 按 Stable 检查时保持原版本。
- 同一份 Homebrew 0.17.0 改用 Beta 设置后由 Vendor 提供 0.19.0-beta.4，一键安装成功。磁盘版本为 0.19.0-beta.4，Bundle ID 和签名 Team 未变，签名校验通过。Homebrew 的 Caskroom 记录仍为 0.17.0，再次检查由 Vendor 返回 0.19.0-beta.4 并显示最新。
- 2026-11-23，Apple Silicon macOS 27.3。使用官方签名的 GPUI 0.19.0-beta.4 真包与隔离配置，
  通过 `channel-verify` 运行实际频道解析、Vendor 探测和更新判定。只有 JSON5 才接受的未加引号键回到 Stable，
  即使旧配置保留 Beta。包含注释及尾逗号的合法 JSONC 选中 Beta。实时端点分别应答 0.17.0 与 0.19.0-beta.4。
  Tauri 0.17.0 真包拒绝有尾逗号的配置并保持 Stable，换成合法 JSON 后选中 Beta 并获报 0.19.0-beta.4。
- 同日，Apple Silicon macOS 27.2 VM 的签名 Release 设置页显示了新的 Homebrew 提示。
  展开说明后，官方 Athas Beta 副本使用 Update Source，Homebrew Only 可覆盖 Beta 的默认选择。
