# Rex

## 基本信息

Rex 的 macOS 客户端通过 [Superlogical](https://www.superlogical.com/rex/docs/installation)
分发。Preview 和 Bleeding Edge 都使用 `com.superlogical.rex`，Team ID
`AG92C3PT77`。观测的两个 DMG 都是 arm64，最低 macOS 15.0，内含 Sparkle，
并在 Info.plist 声明 `SURequireSignedFeed` 和相同的 `SUPublicEDKey`。

## Channel 详情

| Rex 设置 | Defaults 值 | Duo Updater | Sparkle feed |
|---|---|---|---|
| Preview | `preview` | Preview | [preview-arm64](https://blob.superlogical.com/public/rex-app/preview-arm64/appcast.xml) |
| Bleeding Edge（Snapshot） | `snapshot` | Nightly | [snapshot-arm64](https://blob.superlogical.com/public/rex-app/snapshot-arm64/appcast.xml) |

设置位于 [General → App Version](https://www.superlogical.com/rex/docs/reference/mac-settings)。
`defaults read com.superlogical.rex RexAppUpdateChannel` 可读取当前选择。
`RexChannel` 优先使用这个选择。缺少有效偏好时沿用包声明的 feed。
现有偏好监听覆盖这个 defaults 域。

## 更新检测与更新说明

两条 appcast 均为签名 XML，观察到的条目均无 `sparkle:channel` 和增量包。
通用 Sparkle 源按 `sparkle:version` 对比 `CFBundleVersion`。例如 Preview
2061 与 Snapshot 2104 的营销版本均为 0.1.0。若已在 2104，切回
Preview 后不会退回较旧的 2061。
打开更新说明时，`RexChangelog` 使用 build 在厂商的
[详细日志索引](https://blob.superlogical.com/public/changelog/index.json) 中查找
Mac 客户端正文，再根据正文中的 `includes` 或签名 Sparkle 摘要中的 Server 版本和
提交核对 Server & CLI 正文。详情用两个小标题呈现，索引未收录和加载失败各有提示。
Mac 正文不可用时仍显示同 build 的 Sparkle 摘要，包含构建标题、Rex 版本和提交链接。
详情直接读取匹配 build 的原始摘要。通用 Markdown 清理将全长提交哈希当作校验和，
会省略标识 Server 和客户端提交的两行。
版本列表只列当前频道的 Sparkle feed 中的构建。打开历史构建时，也按该构建
的原始摘要载入两部分正文。
正文就绪前显示加载状态。不同 Mac 构建可以共用同一个 Server 版本，副标题会
显示实际的 Server & CLI 版本。

Preview 2061 对应 [Mac 0.1.0-preview.33](https://blob.superlogical.com/public/changelog/mac/0.1.0-preview.33.json)，
其中 `includes` 关联 [Server & CLI preview.21](https://blob.superlogical.com/public/changelog/server/0.1.0-preview.21.json)。
Snapshot 2104 的 appcast 写明随包 Server 是 `0.1.0-preview.23`，提交 `c67cc2d0…`，与
[Server & CLI 正文](https://blob.superlogical.com/public/changelog/server/0.1.0-preview.23.json)
一致。索引中同名的 Mac `0.1.0-preview.23` 对应 build 1642。
本次核对时，Mac build 2104 没有单独的正文。

## 一键安装

使用通用 Sparkle DMG 安装路径，归档带 EdDSA 签名，两个包的 Bundle ID
和 Team ID 一致。两份归档均通过验证。2026-11-24，签名 Release 的
Duo Updater 按既有自动更新策略将运行中的 Rex 从 2061 更新到 2104。
安装日志确认替换完成，重新启动的 Rex 客户端以 Snapshot 2104 连回原服务端。

## 夜扫覆盖

- Feed：`feed:com.superlogical.rex:preview` 与
  `feed:com.superlogical.rex:nightly`，由 `ChannelBinding` 枚举。
- 安装包：`sparkle:com.superlogical.rex:preview` 与
  `sparkle:com.superlogical.rex:snapshot`，由 `AuditedUpdateFeeds` 枚举。
  2026-11-24 运行 `duo verify-install --only com.superlogical.rex`，
  两份归档首次验证均为 `ok`。

## 如何复验

2026-11-24 核对 Preview 0.1.0 (2061) 和 Snapshot 0.1.0 (2104) 真包，
两包的 `RexReleaseChannel` 与各自 Info.plist 的 `SUFeedURL` 一致。
通过 Rex 的 `client.update.set_channel` 实切两轨，分别写入 `preview` 和
`snapshot`，运行中的 Rex 同时切换到对应 feed。生产检查对 2061 在
Preview 报已最新，在 Snapshot 报可升至 2104。用 Snapshot 2104 DMG
复验时两轨均报已最新，切回 Preview 不降级。两个 feed 都解析出 15 条
结构化更新说明。

用同一份 build 2104 安装状态分别检查两条签名 feed，Preview 列表以 2061
开头，Nightly 列表以 2104 开头。选中 Preview 2042 和 1996 可加载两份正文，
选中 Nightly 2103 和 2102 可分别加载 Server preview.23 和 preview.22 正文。

可通过如下命令核对偏好、运行中的 Rex 所选 feed、Duo Updater 的检测和归档：

```sh
defaults read com.superlogical.rex RexAppUpdateChannel
rex -C <client> do client.update.status --json
swift run --package-path application-test channel-verify --check com.superlogical.rex --expect nightly
duo verify-install --only com.superlogical.rex
```
