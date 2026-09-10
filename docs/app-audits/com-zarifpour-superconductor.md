# super.engineering（Superconductor）

## 基本信息
- Bundle ID: `com.zarifpour.superconductor`
- Team ID: `MR38E36N26`（Developer ID Application: David Daniel，已公证，`spctl -a` accepted）
- 观测版本: `8545a7d8`（2026-09-10 的构建；`CFBundleShortVersionString` 与 `CFBundleVersion` 都是它）
- 自更新机制: 自研 —— 每小时查 `releases.superconductor.so/latest.json`，下载 dmg、校验 sha256、暂存，重启时原子交换 bundle（设置页原文 "Downloads stay staged until you restart"）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **nightly（当前唯一轨道）** | — | — | — | — | ✓ 一键 |
| **stable（厂商 2026-04 关闭）** | — | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**

- `feed-discover`（对 2026-09-10 的 dmg）: `no Sparkle and no electron-builder update config`
- Homebrew 无 cask（`brew info --cask superconductor` → 不存在）；不上 MAS；无公开 GitHub Releases

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| nightly | `com.zarifpour.superconductor` | 共享 | `~/.superconductor/settings.json` → `update_channel` = `nightly`；没有记录时按 app 默认 nightly | channel-gated VendorProbe（`SuperconductorChannel` 选配方）| ✓ |
| stable | 同上 | 共享 | `update_channel` 为 nightly 以外的任何值 | 无配方 → 不提示，绝不推 nightly | — 厂商已关闭 |

厂商在 2026-04-05 关掉了 stable 轨道（它自己 changelog 里的 #711 "Disable stable channel and
enforce nightly-only updates"），app 设置页写着 "Nightly is currently the only release track
available"。但设置页的选择器还在，选择写在 `~/.superconductor/settings.json` 顶层的
`update_channel`（2026-09-11 在真实安装上读到 `"nightly"`）。这个文件把整份设置连同默认值一起
序列化（92 个顶层键里有 4 个 `null`、15 个 `false`），所以启动过的安装基本都带这个键 —— 这是推断，
没有重置设置去验证。

bundle 本身不带渠道信号（`detect()` 读作 `.stable`），所以由 `SuperconductorChannel` 读这个键：
`nightly` 或没有记录 → `.nightly`（app 自己的默认，也是唯一轨道）；其他任何值 → 一个没有配方的渠道，
不提示，**绝不把 nightly 推给选了别的轨道的人**。binding 是 authoritative 的，会顶掉 `detect()`。
`ChannelProofRegistry` 登记了 `.artifact(/nightly/Superconductor-nightly-<sha8>-arm64.dmg)`。

**若厂商重开 stable**：`latest.json` 大概率会多出一个同级的 `"stable"` 条目 —— 更新器按渠道名取条目
（报错字符串 "nightly entry missing from release manifest"）；这是推断，归档里找不到 #711 之前的清单。
所有 pattern 已锚在 `"nightly"` 对象里，不会误读另一轨；届时加一条锚 `"stable"` 的 `.stable` recipe，
并核对 lineage（`changelog.json`）是否分轨。`identity.json` 的 `build_channel`（实测 `prod`）是构建
风味，不是更新渠道，别读错。

**不监听 `~/.superconductor`**：FSEvents 是递归的，而 app 的日志就写在这个目录下，会持续触发重查；
现在只有一条轨道、切换不可能发生。渠道在每次扫描、以及 app 启动 / 退出时重读。

## 更新检测
- 源: VendorProbe，`https://releases.superconductor.so/latest.json` —— app 自己的更新器读的就是它
  （URL、UA `superconductor-updater`、报错字符串 "nightly entry missing valid sha" 都在二进制里）。
  浏览器 UA 同样 200。
- 形状（2026-09-10）: `{"nightly": {"sha": "<40 位 hex>", "url": ".../nightly/Superconductor-nightly-<sha8>-arm64.dmg", "sha256": "<hex>", "date": "2026-09-10"}}`
- **版本是 commit hash**。bundle 两个版本字段都是 sha 的前 8 位，所以 `versionPattern` 只取这 8 位；
  取全 40 位会永远不等于 bundle，恒判「有更新」。
- **hash 没有顺序**。用真实的 `VersionComparator.swift` 重放 `changelog.json` 里全部 626 对相邻发布
  （2026-09-10 取的 627 条）：新的读作更新 313 次、读作更旧 313 次。直接比较等于抛硬币 —— 一半的
  更新永远不提示，还会把旧构建当成更新推出去。
- **所以排序读厂商自己的发布史**：recipe 声明 `buildLineage` → `changelog.json`（按日期倒序，一个已发布
  构建一条；lineage pattern 同样只取前 8 位，627 条的 8 位前缀互不相同）。引擎在
  `UpdateChecker.evaluate`、降级提示（`UpdatePolicy.laggingRemoteVersion`）、`duo verify` 的
  `RecipeSanity.remoteBehindInstalled` 和 baseline 的「version went BACKWARDS」里都按 lineage 位置判断；
  预装前复查（`PreInstallGate`）判断「复查是否倒退」时同样按 lineage。lineage 放不下的组合记为一次
  **失败的检查**（带 Retry），不猜 —— 不用 `.unknown`，因为它在 UI 上显示成「没有来源覆盖这个 app」。
  拿不到 / 解析不出 lineage 时 probe 直接失败（`buildLineageUnavailable` / `buildLineagePatternNoMatch`，
  附带的样本是 `changelog.json` 本身），绝不退回比较器。
- 两份文档分开发布：2026-09-10 `latest.json` 与 `changelog.json` 的 Last-Modified 相差 3 秒。
  落在这个窗口里的检查会报 `buildLineageMissesVersion`（归为 infra，持续才上报）。两份当天都是
  `CF-Cache-Status: DYNAMIC`（CDN 不缓存），所以窗口就是厂商的发布间隔，不是边缘缓存的寿命。
- 流量：`changelog.json` 约 850 KB，但两个端点都对 `If-None-Match` 回 304（2026-09-10 实测），更新会话的
  内存 URLCache（64 MB）容得下这个体积，缓存里还在时一次检查只是一次 304。**未测**：两次检查之间它会不会
  被挤出缓存。
- OS 边界: `latest.json` 只有 sha/url/sha256/date 四个字段，**不带** min/max 系统版本。静态下限取自
  bundle 的 `LSMinimumSystemVersion` = 14.0，连同 arm64（dmg 文件名与 `lipo -archs` 一致）写进
  `hostRequirement`。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不适用 |
| 证据 | 只看了更新器相关字符串：整包 dmg 下载、sha256 校验、`hdiutil attach`、原子交换；没专门搜 delta/patch | `latest.json`（2026-09-10）全部字段就是 sha/url/sha256/date，没有 patch URL | — |

- 格式: 无
- 阻塞项: 无

## Changelog
- 来源: `ChangelogRecipe`（structured `.superconductorChangelog`），与 lineage 同一份 `changelog.json` ——
  app 内 "What's New in Nightly" 读的也是它（二进制里这个 URL 挨着该字符串）。
- 条目标题是 sha 前 8 位（与行上显示的版本同一个字符串），厂商的分组标题（Features / Bug Fixes / …）
  作为独立一行排在各自的 commit 前面；空分组（`commits: []`）和空 message 丢弃。
- 厂商数据里同一天的多个构建常重复列出同一批 commit（累计式），原样展示。
- 跟随 channel: 只有一条轨道。
- Recipe 状态: 已有。站点没有人读的 changelog 页（`/changelog`、`/releases` 均 404），所以不设 `changelogURL`。

## 一键安装
- 状态: 支持
- 格式: dmg。镜像里 `Superconductor.app` 是指向 `super.engineering.app` 的符号链接；扫描器先解析符号链接、
  按真实路径去重，只出一行。
- 校验: `sha256` 是 hex SHA-256，`checksumPattern` 只吃 base64 SHA-512，未武装；Team `MR38E36N26` 闸兜底。
- **读的是**: 轨道最新 —— 也是唯一的轨道。它就是官网 Download 按钮（`super.engineering/api/download`
  在 2026-09-10 302 到同一个 dmg）和 app 自己的更新器发给任何用户的那个构建，不存在「厂商还没分配给
  这台机器」的情况。
- 阻塞: 无。**未验证**：app 自带更新器已经暂存了新版、我们又一键装了同一构建时，它下次重启的行为。

## 如何复验
- `swift run --package-path application-test feed-discover <dmg>` → `no Sparkle and no electron-builder update config`
- `swift run --package-path application-test channel-verify <dmg>`（2026-09-11，对 2026-09-10 的 dmg，读的是
  线上两份文档；运行的机器上没有 `settings.json`，走的是「没有记录 → nightly」）: bundle 自身推断
  `stable`，被 ChannelBinding 覆盖为 `nightly`；VendorProbe 对 `nightly` 应答 `8545a7d8`，下载 URL 就是
  `latest.json` 里的 nightly dmg；`UpdateChecker.check()` 全链 winning source = Vendor，status = up to date
- 挂载 `latest.json` 指向的 dmg（sha256 与 `latest.json` 的 `sha256` 一致）:
  `Info.plist` → `CFBundleIdentifier` `com.zarifpour.superconductor`、两个版本字段 `8545a7d8`、
  `LSMinimumSystemVersion` 14.0；`lipo -archs` → `arm64`；`codesign -dvvv` → TeamIdentifier `MR38E36N26`
- 真实安装的布局: `/Applications/super.engineering.app` 目录 + `/Applications/Superconductor.app` 符号链接；
  `~/.superconductor/settings.json` 的 `last_installed_version` / `last_seen_version` 是 40 位 sha；
  没有任何本地文件记录发布日期或序号 —— 这就是排序只能来自 `changelog.json` 的原因。
- 单元测试: `SuperconductorTests`（真实响应体逐字截取；每条排序用例先断言比较器在该组合上是错的）
- 实时: `duo verify --only com.zarifpour.superconductor`

## 已知问题
- 厂商若把 plist 里的版本改成别的长度（About 窗口显示的是 7 位 `8545a7d`），`versionPattern` 和 lineage
  pattern 要一起改；测试钉的是 8 位。
- App 层「运行中的版本落后于磁盘」的 Restart 徽标（`AppListModel`）仍用 `VersionComparator` 比较 hash，
  装完新版时约一半情况不会提示重启。未在这次改动里处理。
- `RelaunchProgress.hasLanded` 仍用比较器，但当前走不到：它只在 `SelfUpdaterStaging` 识别出暂存更新时
  调用，而它不识别这个 app 的更新器。
- `duo verify` 的两道历史检查（baseline 的「version went BACKWARDS」、changelog 落后于检测版本）对这个
  recipe 是**关掉**而不是换成 lineage 版：hash 之间比不出先后。`latest.json` 只有一条，`versionPattern`
  滑到旧条目的风险低；但同样的字段用在多条目 feed 上时会继承这个缺口。
- `RecipeSanity` 的「version contains no digits」对 lineage recipe 不适用（`deadbeef` 是合法的 hash），已跳过。

## 建议下一步
1. 厂商重开 stable 时：加锚 `"stable"` 的 recipe，核对 lineage 是否分轨（见 Channel 详情）。
2. 让 App 层的 Restart 徽标也认 lineage（单独的 PR）。
