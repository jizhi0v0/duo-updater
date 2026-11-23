# Athas

Tauri 与 GPUI 的正式发行包都叫 `Athas.app`，Bundle ID 为 `com.code.athas`，签名 Team ID 为 `N43BXFX4H4`。Apple Silicon 包的版本字段保留 `-beta.N` 后缀。0.19 起采用 GPUI，两代沿用同一条应用内更新路径。 [官方迁移说明](https://github.com/athasdev/athas/blob/v0.19.0-beta.4/docs/release-migration.md)

## 渠道与来源

| 副本 | 渠道依据 | 更新源 |
| --- | --- | --- |
| Tauri 至 0.16.1 | Stable | 官网副本走 Vendor，Cask 副本走 Homebrew |
| Tauri 0.16.2 至 0.18 | `com.code.athas/settings.json` 顶层 `updateChannel` | 同下 |
| GPUI 0.19 起 | `dev.athas.app/settings.json` 顶层 `updateChannel`，首启读取旧配置 | 官网副本走 Vendor；Cask 副本走 Homebrew，明确开启 Beta 后改查 Vendor。Duo Updater 内的 Homebrew Only 选择优先 |
| 旧 Athas Preview | 独立 Bundle ID `com.code.athas.preview` | 官方 `/api/update/preview` 返回 HTTP 204，历史预览包留在原渠道 |

两个配置文件都在 `~/Library/Application Support`。默认 Stable。版本号用于选择配置文件，实际发布渠道取应用设置。主线可从任一代向前更新，无需 Bundle ID 迁移。旧 Preview 的独立设置目录和 Bundle ID 对应独立安装，官方没有提供迁移更新。 [旧 Preview 打包配置](https://github.com/athasdev/athas/blob/v0.14.1-preview.5/src-tauri/tauri.preview.conf.json)

## 检测、一键安装与说明

- 版本取官方 `https://athas.dev/api/update/stable` JSON 的 `version`。Stable 请求只接受稳定版本，Beta 请求可以收到更新的预览版或转正版本。两条规则都要求 `platforms.darwin-aarch64.url` 指向同一版本的官方 GitHub 更新包。
- Vendor 一键安装使用官方 `Athas_aarch64.app.tar.gz`。Duo Updater 沿用签名、Team ID、Bundle ID 和架构校验。Athas 自更新器另用 minisign 验签。
- 两个渠道的结构化更新说明复用 GitHub Releases Markdown 解析。Beta 也显示已转正版本，并过滤历史的 `-preview.N` 发行包。 [GitHub Releases](https://github.com/athasdev/athas/releases)

## 夜扫覆盖

- 版本探测由 Vendor registry 枚举 `vendor:com.code.athas:stable` 和 `vendor:com.code.athas:beta`。
- 安装包检查由 `verify-install` 枚举对应两条 Vendor 规则。历史 Preview 源返回 204，没有可供检查的后续更新包。

## 历史与实测

- 2026-11-23，macOS 27.2 ARM VM。Athas 0.17.0 在设置里开启 Beta，写入 `"updateChannel":"beta"`，手动检查显示 `0.19.0-beta.4 available`。Athas 自更新器安装后从原路径重启 GPUI；两个版本字段均为 `0.19.0-beta.4`，签名校验通过，Bundle ID 和 Team ID 保持一致。
- 同日对官方端点分别发送 Stable 和 Beta 请求，得到 `0.17.0` 和 `0.19.0-beta.4` 的 Apple Silicon archive。Homebrew 的 `athas` Cask 装的是官方 0.17.0 DMG。 [Homebrew 配方](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/a/athas.rb)
- 实际解包两份更新 archive，两个版本字段都与 manifest 一致，`LSMinimumSystemVersion` 分别为 10.15 和 10.15.7。两包均通过 Gatekeeper 的 Notarized Developer ID 检查。
