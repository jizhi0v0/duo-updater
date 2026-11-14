# Kuvo Code

> 审计 2026-11-15。独立于 Docker 应用 Kuvo Box（`run.kuvo.app`）；两者不是 Bundle ID 迁移关系。

## 基本信息

- Bundle ID / 签名 ID：`run.kuvo.code`
- Team ID：`C8Y523R7T5`（Developer ID Application: Serhat Andiç）
- 官方仓库：[serhatandic/kuvo](https://github.com/serhatandic/kuvo)；已发布包仍声明 `serhatandic/kuvo-code` 的更新地址。
- 产品：原生 macOS AI 编程工具，使用 opencode 引擎。
- 正式版 `0.7.2` / 上一正式版 `0.7.1`；测试版 `0.8.0-beta.1`，构建号 `0.8.0b1`。
- 支持 Apple Silicon、macOS 26 或更新版本。最早正式版 `0.1.0` 为 arm64；检查的 `0.7.1`、`0.7.2`、`0.8.0-beta.1` 为 universal。
- 更新机制：Sparkle 2，包内 `SUFeedURL` 与 `SUPublicEDKey`；无需额外版本或安装 recipe。

## 覆盖矩阵

| 轨道 | Bundle ID | 更新源 | 选择依据 |
|---|---|---|---|
| stable | `run.kuvo.code` | generic Sparkle | `updates.betas=false`，或未设值的正式版 |
| beta | `run.kuvo.code` | 同一 Sparkle feed 的 `beta` items | `updates.betas=true`，或未设值且短版本包含 `-beta` |

直接下载的正式版与测试版共用 ID；没有将 Kuvo Box 的 ID 映射到这里。当前官方 README 提供 DMG 与源码构建，本轮没有新增其他发布渠道的规则。

## 覆盖清单

- **正式版早期拷贝**：最早发布的 Code `0.1.0` 已有正确产品 ID、macOS 26 floor、Sparkle feed 和更新密钥；不借用 Box 的版本序列。
- **正式版当前拷贝**：`0.7.1` → `0.7.2` 由同一 feed 的未标记 item 提供。
- **同 ID 测试版**：`0.8.0-beta.1` 的短版本保留 `-beta.1`，构建号为 `0.8.0b1`。首次选择前默认跟随 beta；明确关闭开关后，等待比已安装 beta 更新的正式版。
- **相同团队的另一产品**：Box 与 Code 的团队和 Sparkle key 相同，但产品 ID 不同。保留安装身份检查，不登记跨产品迁移。

## Channel 详情

`KuvoCodeChannel` 读取 `run.kuvo.code` 的 UserDefaults `updates.betas` Bool。正式版 `v0.7.2` 和测试版 `v0.8.0-beta.1` 的发布源码一致：

- `Updates.wantsBetas`：保存的 Bool 优先，未设值时使用 `AppInfo.isBeta`。
- `AppInfo.isBeta`：`CFBundleShortVersionString.contains("-beta")`。
- `allowedChannels`：开启时 `["beta"]`，关闭时 `[]`。

绑定只决定允许的标签，保留包自己的 feed。明确 false 返回 authoritative stable，避免 feed 根据已安装 beta 推断后重新打开 beta。偏好监测没有包版本上下文时，缺少 key 返回 nil；首次明确关闭与缺省状态因此有不同指纹，会触发重新扫描。

发布源码：[`Updates.swift`，v0.7.2](https://github.com/serhatandic/kuvo/blob/v0.7.2/KuvoCode/Stores/Updates.swift)、[`AppInfo.swift`，v0.7.2](https://github.com/serhatandic/kuvo/blob/v0.7.2/KuvoCode/App/AppInfo.swift)。`0.1.0` 的更新器尚无渠道 delegate；其缺省选择仍为稳定版。

## 更新检测

- 包内地址：`https://github.com/serhatandic/kuvo-code/releases/latest/download/appcast.xml`
- 当前可读地址：`https://github.com/serhatandic/kuvo/releases/latest/download/appcast.xml`
- feed 同时包含 stable `0.7.2` 与 `<sparkle:channel>beta</sparkle:channel>` 的 `0.8.0b1`，两个 item 都声明最低 macOS `26.0`。
- 不添加 GitHubReleaseRule：generic Sparkle 已提供版本、构建、OS floor、归属正确产品的安装地址和签名。

## Changelog

feed 使用 `<description sparkle:format="markdown">` 内联更新说明，生产 Sparkle 解析器可生成原生条目。正式版 `0.7.2` 与测试版 `0.8.0-beta.1` 的现有说明均为 bullet 列表，没有需要保留的分节标题；无需额外抓取网页或 recipe。

本轮增加真实 feed 形状的离线回归检查。实际 `channel-verify` 的原生面板条目与 VM 窗口呈现尚需在组合构建上验证，不能用离线解析替代该项结果。

## 一键安装

安装包为 `KuvoCode.dmg`，解出 `Kuvo Code.app`。检查的最早正式版、前一正式版、当前正式版与测试版同为 `C8Y523R7T5`，严格深度资源签名校验均通过，使用同一 Sparkle key。包内无 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent 或 LaunchDaemon 条目；应用未开启 App Sandbox。

这是安装前身份与包结构证据。本轮尚未在 VM 执行 `duo install` / `duo restart`；一键安装结论须由真实升级与重启结果补全，不能仅据验签宣称完成。

## 已停放整包（自更新器下完、还没装的那份）

发布包携带 Sparkle；本轮未启动应用以采样其下载暂存与后台引擎行为。VM 升级验证需同时检查运行中更新、重启后的版本和自更新器暂存，保留这一限制。

## 历史与实测

### 2026-11-15：独立产品与渠道信号

只读挂载以下官方 DMG，逐个读取 Info.plist、签名、主程序架构和组件目录；没有在宿主机安装或启动应用。

| 包版本 | 短版本 / 构建 | 签名 ID | Team | 最低系统 | 架构 | strict deep 验签 |
|---|---|---|---|---|---|---|
| `0.1.0` | `0.1.0` / `0.1.0` | `run.kuvo.code` | `C8Y523R7T5` | `26.0` | arm64 | exit 0 |
| `0.7.1` | `0.7.1` / `0.7.1` | `run.kuvo.code` | `C8Y523R7T5` | `26.0` | x86_64 + arm64 | exit 0 |
| `0.7.2` | `0.7.2` / `0.7.2` | `run.kuvo.code` | `C8Y523R7T5` | `26.0` | x86_64 + arm64 | exit 0 |
| `0.8.0-beta.1` | `0.8.0-beta.1` / `0.8.0b1` | `run.kuvo.code` | `C8Y523R7T5` | `26.0` | x86_64 + arm64 | exit 0 |

四包 `SUPublicEDKey` 均为 `uG/YbzL4kf+DAYCiTTfK8ztEOBo96hkEAuKk9rw9BE4=`。源码与包共同确认 Code 自最早发布起就与 Box 使用不同 ID，不能据仓库旧名字把两个产品串成升级链。

## 如何复验

```sh
swift test --package-path DuoUpdaterCore --filter KuvoCodeChannelTests
swift run --package-path application-test channel-verify <KuvoCode-0.7.1.dmg> --expect stable
swift run --package-path application-test channel-verify <KuvoCode-0.7.2.dmg> --expect stable
swift run --package-path application-test channel-verify <KuvoCode-0.8.0-beta.1.dmg> --expect beta
```

实际开关切换、`duo install` 与 `duo restart` 在独立 VM 执行；宿主机的偏好和安装不用于这些有副作用的验证。
