# Dataflare

| 副本 | 检测 | 一键升级 | 更新日志 |
|---|---|---|---|
| 官方正式版 `app.dataflare.desktop` | 官方 Tauri ARM64 更新 JSON，营销版本与包内短版本一致 | 官方版本化 ARM64 DMG，沿用已有安装链的原厂签名、Team、bundle ID 和架构校验 | 厂商 Markdown 版本历史，保留日期和 Changes 小标题 |
| Homebrew 管理的正式版 | `dataflare` cask 的 `auto_updates` 副本可使用同一厂商更新源 | cask 与官网提供同样的版本化 DMG | 同一正式版历史 |

官网公开 Apple Silicon 和 Intel 两种 macOS 安装包，并公开推荐 Homebrew 安装。厂商另提供 Windows 便携版，macOS 下载页和已发布的桌面打包配置只列一个 macOS 产品。未发现厂商发布独立 macOS beta、nightly 或 Mac App Store 版本。已确认的 macOS 正式版共用 `app.dataflare.desktop`，在 DuoUpdater 支持的 Apple Silicon 主机上使用原厂 ARM64 包。 [官方下载](https://dataflare.app/download) · [官方打包配置](https://github.com/DataflareApp/dataflare/blob/v3.2.6/tauri.conf.json) · [Homebrew cask](https://formulae.brew.sh/cask/dataflare)

## 夜扫覆盖

- `vendor:app.dataflare.desktop:stable` 检查官方 ARM64 Tauri 端点。固定传入 `0.0.0`，避免当前版本收到 HTTP 204。只接受含官方 ARM64 更新归档地址的顶层正式版本字段。
- `install:vendor:app.dataflare.desktop:stable` 展开与检测版本对应的官方 ARM64 DMG 并检查安装包及签名身份。安装地址由解析到的版本生成，不使用 Tauri 响应中会随最新版滚动的归档地址。
- `changelog:app.dataflare.desktop:-` 解析厂商公开维护的 Markdown 日志。 [厂商日志](https://github.com/DataflareApp/dataflare/blob/main/CHANGELOG.md)

签名 Release CLI 的 `duo verify --vendor --changelog` 与 `duo verify-install --full` 均通过。完整下载的 3.2.6 DMG 解包后为同 ID、同 Team。

## 历史与实测

2026-11-28，macOS 27.2 Apple Silicon VM 上检查官方 3.2.5 与 3.2.6 ARM64 DMG。两个包均为 `app.dataflare.desktop`、Team `8Z4759S53G`，通过严格签名和 Gatekeeper 公证检查。`CFBundleShortVersionString` 与 `CFBundleVersion` 均等于各自的正式版本。两版包内没有 `SUFeedURL`，可执行文件声明厂商 Tauri 更新端点。

厂商更新端点对 `3.2.5` 和 `0.0.0` 均返回 `3.2.6` 及 ARM64 `Dataflare.app.tar.gz`，对 `3.2.6` 返回 HTTP 204。厂商的静态 ARM64 更新清单也提供同样的版本和归档。 [ARM64 更新端点](https://api.dataflare.app/release/darwin/aarch64/0.0.0)

同日只读挂载 Intel 3.2.5 DMG。真包含 x86_64 slice，bundle ID、Team、两项版本字段与 ARM64 3.2.5 一致，严格签名和公证通过。两种架构共享一个正式更新轨道。Homebrew 2.0.0 的历史 cask 已使用版本化 ARM64 和 Intel DMG，并记录同一应用数据目录。厂商 3.0.0 的打包配置保留同一 bundle ID 和更新端点。1.9.5、2.0.0 和 3.0.0 的版本化 ARM64 DMG 本轮均返回 HTTP 404。更早副本若使用同一标识仍可匹配检测，签名 Team 不同的副本会由既有安装校验拒绝。 [2.0.0 历史 cask](https://github.com/Homebrew/homebrew-cask/blob/c430e16ad65a3871524e68b3866e8f205399ec04/Casks/d/dataflare.rb) · [3.0.0 配置](https://github.com/DataflareApp/dataflare/blob/v3.0.0/tauri.conf.json)

VM 用签名 Release CLI 检出 3.2.5 → 3.2.6，在应用关闭时从厂商下载 DMG 并原地升级。升级后显示已是最新版，严格签名和公证通过，包内容与厂商原包一致。生产日志面板读取到 3.2.6 的 Changes 分节。
