# IntelliJ IDEA

**这不是审计**：family `com-jetbrains-intellij`（`Recipes/com-jetbrains-intellij.swift`）里 IntelliJ IDEA `com.jetbrains.intellij` 与 IntelliJ IDEA EAP `com.jetbrains.intellij-EAP` 的覆盖情况没有审过。这份文件记录配方历史和相关实测，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-jetbrains-intellij.swift — stable VendorProbe（`code=IIU&type=release`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`2fcbc0a2`（2026-08-08）。

It was pinned to exactly three (`YYYY.x.y`) and JetBrains then
shipped a fourth — `"version": "2026.2.0.1"` — so the anchored pattern
stopped matching and the row silently fell to "unknown" with the probe
reporting "resolved no version".


### 独立安装的 IntelliJ IDEA EAP

2026-11-21 对照 JetBrains 的 [下载 API](https://data.services.jetbrains.com/products/releases?code=IIU&type=eap) 和 [原生更新流](https://www.jetbrains.com/updates/updates.xml)。两者共有的 111 个 build 中，下载 API 的 `licenseRequired: false` 对应 `IU-EAP-licensing-EAP`，`true` 对应 `IU-EAP-licensing-RELEASE`。两个许可类别都出现在下载 API 的 `type=eap` 列表。人工核对的 EAP 7（`263.7031.23`）和 Beta（`263.7307.44`）的 macOS 签名标识和 bundle ID 均为 `com.jetbrains.intellij-EAP`，Team ID 为 `2ZEFAR8TH3`。小版本 Preview（`263.8311.30`）使用正式版的 `com.jetbrains.intellij`。

旧 `latest=true` 只回一条，最新指向小版本 Preview 时，已有 EAP 副本就会发现另一类安装包。读取列表并按 build 选出声明 `licenseRequired: false` 的最新版本；只有同一条记录的官方 Apple Silicon DMG 可以参与一键安装。旧响应重放保留 EAP 的 build 号比较，混合列表重放跳过小版本 Preview。对跨 bundle ID 的替换，现有签名校验仍会核对安装身份。

本次覆盖独立安装且使用 `com.jetbrains.intellij-EAP` 的 Apple Silicon 副本。共享正式版 bundle ID 的小版本 Preview 走该 bundle ID 的现有检测，加入原生 Preview 渠道选择需要判断该副本的更新设置。Toolbox 管理的副本由 Toolbox 来源处理。

## 夜扫覆盖

- 版本探测继续使用 `vendor:com.jetbrains.intellij-EAP:preview`，安装包继续使用 `install:vendor:com.jetbrains.intellij-EAP:preview`。两条由 VendorProbe 注册表枚举。
- `verify/identities.json` 的 EAP 安装身份锚点沿用原有 `com.jetbrains.intellij-EAP`、Team ID `2ZEFAR8TH3` 和 arm64 记录。
