# Claude Desktop

macOS 官网安装包与 Homebrew `claude` cask 都使用通用版 `Claude.app`，bundle ID 为
`com.anthropic.claudefordesktop`，Anthropic Team ID 为 `Q6L2SF6YDW`。
Stable 和 Latest 共用 bundle ID 和纯数字版本。用户在 Claude 的 Settings → Desktop app
选择渠道，Stable 为默认值。官方说明从 4.29.0 开始提供选择，切回 Stable 后等更新的 Stable 版本再升级。
[Anthropic 渠道说明](https://support.claude.com/en/articles/10065433-install-claude-desktop)

## 渠道与更新路径

- **Stable** 取公开 GA 跳转和本机 Squirrel 灰度两条版本源中较新的结果。同版时优先带发布时间的灰度结果。
  缺少设备 ID 时使用公开 GA。官网 URL 中的 `/latest/redirect` 指当前公开版本。
- **Latest** 读取 `~/Library/Application Support/Claude/claude_desktop_config.json` 中
  `preferences.releaseChannel`，兼容旧键 `ancientJournal`。早于 4.29.0 的副本、默认配置以及
  检测到本地受管理偏好时使用 Stable。用户修改偏好后，下次扫描或 Claude 启停时重新读取。
- **Latest 版本源** 使用 Squirrel API 的 Latest 渠道 UUID、Claude 写入的 `ant-did` 和本机 macOS 版本。
  只接受 `releases-latest` 下与 `currentRelease` 一致的 ZIP。设备 ID 缺失时该 recipe 跳过。
- **Homebrew** 的 `claude` cask 跟随公开版本。选择 Latest 后，自更新 cask 副本优先走 Latest
  版本源，同时保留 cask 来源。用户选择 `Homebrew Only` 时仍按 cask 检查。
- **一键更新与变更日志** 两条渠道都有 VendorInstaller ZIP 路径和签名校验，Squirrel 响应提供的
  SHA-256 用于下载校验。两条渠道都按发布版本查找官方桌面版变更日志，覆盖范围以官方实际发布的条目为准。
  [Claude Desktop 变更日志](https://claude.com/docs/cowork/changelog)

自定义 `CLAUDE_USER_DATA_DIR` 和服务端下发的企业或灰度策略尚未覆盖。

## 夜扫覆盖

- `duo verify` 和 `duo verify-install` 自动从 VendorProbe 注册表枚举
  `vendor:com.anthropic.claudefordesktop:stable:ga`、
  `vendor:com.anthropic.claudefordesktop:stable:rollout` 和
  `vendor:com.anthropic.claudefordesktop:latest`。三个 recipe 都有安装 ZIP。
- `duo verify --only com.anthropic.claudefordesktop` 实测三条版本源与共享的变更日志均通过。
  两条 Squirrel 路径需要扫描用户的 Claude `ant-did`，缺少设备 ID 的运行器只能覆盖 Stable GA。
- `duo verify-install --only vendor:com.anthropic.claudefordesktop:latest` 通过，验证了
  `6.6695.0` 的 399,150,694 字节 ZIP、bundle ID、Team ID 和通用架构。实际替换安装仍待验证。

## 历史与实测

### Stable 与 Latest 渠道（2026-11-18）

- 检查了已安装的 `5.11492.5`。其 `app.asar` 从 `claude_desktop_config.json` 解析渠道，
  Latest 请求附带 `channelUuid=77a14fc4-808e-4345-ac3e-090be671bf94`。
- 用本机设备 ID 和 macOS 27.3 查询时，公开跳转与 Stable Squirrel 均返回 `5.11492.5`。
  Latest Squirrel 返回 `6.6695.0` 及独立 CDN 路径、发布时间和 SHA-256。只发设备 ID 时
  Stable 回答 `1.46388.4`，Latest 回答 404。加上 macOS 版本后，省略客户端版本或传入
  本机版本得到相同结果。公开跳转加渠道 UUID 仍返回 Stable。
- 下载并解包了 Latest `6.6695.0`。版本和 bundle ID 与响应一致，Team ID 与已安装副本一致，
  ZIP 的 SHA-256、`codesign --verify --deep --strict` 和 Gatekeeper 公证检查均通过。
- `channel-verify` 用隔离偏好和真实 bundle 跑过完整检测链路。Stable `5.11492.5` 显示已最新，
  切换到 Latest 后同一副本收到 `6.6695.0`。用该版本的解包副本切回 Stable，结果为已最新。

以下记录于 2026-09-14 从 recipe 注释迁出，正文保留原样。

### Recipes/com-anthropic-claudefordesktop.swift — GA redirect + Squirrel rollout VendorProbe

转引自 recipe 注释，未复测。

GA alone goes blind for the whole ramp: on
2026-08-15, 1.30096.5 had been on the CDN for a day and the app's own
updater had already staged it for relaunch, while GA still said
1.30096.1 — we'd have reported "up to date" the entire time.

`device_id` is REQUIRED (no id → HTTP 400) and selects
the rollout bucket: four synthetic ids sampled on 2026-08-15 answered
.1/.5/.1/.1, which is exactly why the id must be this machine's real one
(`~/Library/Application Support/Claude/ant-did`, a base64-wrapped UUID)
and never a fabricated one.

### Recipes/com-anthropic-claudefordesktop.swift — rollout VendorProbe（`pub_date`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`b41af17a`（2026-08-15）。

`pub_date` is UTC (39s after the artifact's Last-Modified),
and it's what finally gets Claude into the Release Log timeline.

### Recipes/com-anthropic-claudefordesktop.swift — rollout 一键接上 sha256（2026-10-07）

rollout 端点的 `updateTo` 现在带 hex `sha256`（和 `size`）；2026-08-15 抓的 body 里还没有。rollout recipe 接上它（`checksumFormat: .sha256Hex`，#1016），
在 Team `Q6L2SF6YDW` 闸之上先核下载字节。pattern 取「body 里第一个 Claude zip URL 所在的那个对象」里的 `sha256`，即 install pattern 读的那一项，与键序无关；
该对象没有 `sha256` 时什么都不读，不会借后面另一个 release 的摘要。GA 端点是一个 307，`Location` 里没有摘要，所以不设 `checksumPattern`；
`VendorProbeSource.best` 交出的是整个 outcome，GA 胜出时它的 `RemoteVersion` 不带 SHA-256，rollout 的摘要不会套到 GA 的 zip 上。

实测（2026-10-07，只读 GET + 下载；没有碰本机装着的 Claude.app 和它的进程，只读了 `ant-did` 拿 device id）：
- rollout（本机 device id）：`currentRelease` 1.46388.4，`url` `…/1.46388.4/Claude-50e62f90….zip`，`sha256` `494c3c6e…8617`，`size` 355,648,442。
  下载这个 zip：355,648,442 B，SHA-256 `494c3c6e…8617`，一致。
- GA：307 → `…/2.19675.1/Claude-8613680e….zip`，无摘要。
- 生产路径（`VendorProbeSource.probeDiagnostic` 两个 recipe 各跑一次，再 `best(of:)`）：rollout 的 `expectedSHA256` 是 `494c3c6e…`，GA 为 nil；
  `best` 选 GA（2.19675.1 更高），结果 `expectedSHA256` 为 nil。`VendorInstaller.verifySHA256` 对下载的 rollout zip 通过，翻转一个字节的副本抛 `checksumMismatch`（临时测试，跑完已删）。没有跑 `duo install`。
- 观测（**未查原因**）：这台机器的 rollout 端点答 1.46388.4，比 GA 的 2.19675.1 低一个大版本，所以眼下 rollout 不会胜出，这次接上的摘要在本机暂时用不到。

### Recipes/com-anthropic-claudefordesktop.swift — changelog `.md` 改成 `**v…**` 行（2026-10-21）

症状：工作台 Detection recipes 报 `fetched claude.com but extracted no entries`。
实测（2026-10-21，Python urllib、浏览器 UA）：`https://claude.com/docs/cowork/changelog.md` 200 `text/markdown`，219,541 B；`<Update` 0 处，
`**v<version>**` 独占一行 68 处（最新 `**v3.1623.0**`），68 个里有 17 个在版本行下多了一行 `Bundled Claude Code version: …`（decoder 不读它），`.md` 里没有日期。
日期只在 HTML 页（`data-component-part="update-description"`，70 处，v3.1623.0 → `2026-10-20`）。
没换源的理由：Mintlify 的 `/docs/cowork/changelog/rss.xml` 只有 15 个 item，`pubDate` 与 HTML 的日期在其中 4 个上差一天（v2.31226.0、v2.9939.4、v2.7032.0、v2.2553.13）；
HTML 页 1.19 MB、class 是 Tailwind 串。所以留在 `.md`，decoder 两种形状都读，新形状的条目不带日期。
announcement（`**Resolved: Cowork on Windows**`、`**Known issue: …**`）现在是上一个 release 块里的一行粗体，按不显示的 surface 处理。
