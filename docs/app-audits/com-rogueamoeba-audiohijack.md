# Audio Hijack

官网正式版 `com.rogueamoeba.audiohijack` 通过 `Protein.framework` 加载内嵌 Sparkle，并在运行时设置 feed。DuoUpdater 通过 `SparkleFeedCatalog` 补全这个地址。请求中的 `system` 取本机三段 macOS 版本并去掉点号，官网据此选择兼容的下载。集成覆盖正式版，厂商的测试版选项未接入。Audio Hijack 3 使用 `com.rogueamoeba.audiohijack3`，厂商最后支持到 macOS 13。 [旧版下载](https://rogueamoeba.com/legacy/) · [正式版发布说明](https://rogueamoeba.com/support/releasenotes/?product=Audio+Hijack)

官网提供可直接替换的 `.app` ZIP。正式版 feed 只写 `sparkle:version`，核对过的原厂包在 `CFBundleShortVersionString` 和 `CFBundleVersion` 使用相同版本号。已核对的 4.6.0 和 4.6.1 均无 `SUPublicEDKey`。安装沿用现有 Sparkle 路径，校验 Developer ID 签名、Team ID、bundle ID 和可运行架构，拒绝降级，并在换包前要求 `CFBundleVersion` 与本次 feed 的 `sparkle:version` 一致。 [官网安装说明](https://rogueamoeba.com/support/manuals/audiohijack/?print=true)

## 夜扫覆盖

- `feed:com.rogueamoeba.audiohijack` 检查正式版 feed 和 enclosure。
- `install:sparkle:com.rogueamoeba.audiohijack:stable` 下载并检查正式版 ZIP。EdDSA 公钥缺口已记录，安装包走代码签名和 Team ID 校验。
- 2026-11-26，从本次代码构建的 `duo verify --feed --only audiohijack` 和 `duo verify-install --only audiohijack --full` 各通过一项。后者下载并检查了 4.6.1 ZIP，记录为本地首次观测。

## 历史与实测

### Recipes/com-rogueamoeba-audiohijack.swift — 官网正式版

2026-11-26，本机 macOS 27.3（26C5047e）。原厂签名的 4.6.0 在接入前由 `duo check` 判为 `unknown`。同一官网 feed 未带 `system` 时返回 4.0.4。使用 `system=1500`、`2600` 和 `2730` 都返回 4.6.1，声明最低 macOS 14.4。4.6.0 和 4.6.1 的 bundle ID 与 Team ID `7266XEXAPM` 一致，均通过严格签名校验。 [问题 #2226](https://github.com/jizhi0v0/duo-updater/issues/2226) · [官网 Sparkle feed](https://rogueamoeba.net/ping/versionCheck.cgi?format=sparkle&bundleid=com.rogueamoeba.audiohijack&platform=osx&arch=arm64&system=2730)

安装和夜扫直接请求正式版 feed 返回的 enclosure。当前 `download.php` 对普通 GET 返回 HTML，带 `DuoUpdater/0.1 Sparkle` User-Agent 时重定向到官网 ZIP。最终归档地址由厂商决定。

旧版下载的 4.3.5 变体与 4.6.x 使用同一个 bundle ID 和 Team ID，主应用同样未声明 `SUFeedURL`，两项 bundle 版本字段均为 4.3.5。兼容版本由同一个官网稳定 feed 按运行的系统选择。菜单栏一键验证使用 4.6.0。

同日在本机用包含上述改动的 Developer ID 签名 Release 验证。菜单栏自动检测到 4.6.0 → 4.6.1，点击该行「Update」后下载 29,472,935 字节，约 8 秒完成换包。磁盘上的营销版本和构建版本都是 4.6.1，原厂签名与公证复验通过，更新后复查为 `upToDate`。测试时 Audio Hijack 未运行。
