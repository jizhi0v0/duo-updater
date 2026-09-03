# UTM

审计日期：2026-09-03。

## 基本信息

- Bundle ID：`com.utmapp.UTM`
- Team ID：`WDNLXAD4W8`
- 已验证真实包：stable `4.7.5` / build `118`；beta `5.0.4` / build `123`、`5.0.5` / build `124`
- 当前上游版本：stable `4.7.5`；GitHub prerelease beta `5.0.5`
- 自更新机制：GitHub 直装版无 Sparkle；Mac App Store / TestFlight 版本分别交由对应商店管理
- 官方发布页：https://github.com/utmapp/UTM/releases

## 覆盖矩阵

> ✓ = 已接入　○ = 可接入（未实现）　✗ = 已调查不可行　— = 不适用

| | Sparkle | Homebrew | MAS | TestFlight | GitHub | VendorProbe |
|---|---|---|---|---|---|---|
| **stable** | — | ✓ | ✓（通用源） | — | ✓（一键） | — |
| **beta** | — | ✓（回落 GitHub 分轨） | — | ✓（通用托管） | ✓（一键） | — |

当前生效源取决于安装来源：

- Mac App Store 安装：`MacAppStoreSource`
- TestFlight beta：TestFlight 本地 inventory 的托管路径
- Homebrew `utm`（4.7.5）/ `utm@beta`（5.0.5）：`HomebrewCaskSource`，仅当该 cask 真的
  装过（provenance 闸要求它在 Caskroom 里）
- GitHub 直装 stable：`GitHubReleasesSource` 的 stable rule
- GitHub 直装及 Homebrew `utm@beta`：`GitHubReleasesSource` 先按观测版本反查 exact release，再选择 beta rule

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.utmapp.UTM` | 共享 | 本地无标记时先视为候选 stable | exact release 为 `prerelease: false`，更新读 GitHub `/releases/latest` | ✓ |
| beta（TestFlight） | `com.utmapp.UTM` | 共享 | TestFlight receipt / 本地 inventory | TestFlight 托管 | ✓ |
| beta（GitHub/Homebrew） | `com.utmapp.UTM` | 共享 | 包内无标记；exact tag 对应 release 的 `prerelease: true` | 候选取 `max(装机大版本线最新, 全局最新正式版)`，排除 draft —— **不是"只收 prerelease"**，见下 | ✓ |

UTM 的 stable 与 beta bundle ID、app 名、Team ID、资产名都相同，营销版本也是不带后缀的
纯数字。因此 `ReleaseChannel.detect()` 单靠本地 bundle 无法分轨。做法不是用"5.x 就是 beta"
这类版本猜测，而是以已安装 `CFBundleShortVersionString` 构造 exact tag `v<version>`，读取
GitHub 对该 release 的权威 `prerelease` 位：

- `true`：这份拷贝在预览轨；
- `false`：这份拷贝在正式轨；
- exact tag 不存在、是 draft、或应答不再带 `prerelease`/`draft` 字段：**不声称任何渠道，退回
  stable rule**（即这个机制出现之前的行为）。

  注意这里是"丢徽章"而不是"丢整行"。早期做法是判不出就不响应，但 UTM 没有 Sparkle、cask 只在
  brew 装过时才应答，所以不响应等于这一行掉到 `.unknown`、连本来能给的 4.7.5 都不再提示，而且
  静默。这不是假设：`v3.1.3` / `v3.0.4` 上游已重打成 `-2` 后缀、原 tag 不存在，`v2.0b7` /
  `v1.0-rc6` / `v0.2-fakesign` 连 tag 正则都不匹配。退回 stable 在这个方向上是安全的 ——
  它至多给出最新正式版，比它新的预览装机会走 `laggingRemoteVersion`，不会被当成可安装的降级。

判轨结果写进 `ResolvedChannelStore`（`~/Library/Application Support/com.duoupdater.app/resolved-channels.json`），
**按安装路径 + 两个版本串**建 key。两点原因：

1. **同机可以同时装两份**。开发机上就是这种情况：系统应用目录里一份 5.0.5 (124) beta，
   用户应用目录里一份 4.7.5 (118) stable；两者版本不同，`AppScanner.dedupeIdenticalInstalls`
   不会折叠，所以是两行。按 bundle ID 建 key 会让两行抢同一条记录。
2. **判轨证据在远端**。`UpdateChecker` 的 `.error` / `.unknown` 返回 `remote: nil`，
   渠道若只挂在 `RemoteVersion` 上，一次网络抖动就会让 Beta 徽章消失、changelog cache key
   从 `:beta` 翻回 `:stable`。存下来之后，失败的那一轮仍然读得到 `provenChannel`。

顺带把稳态成本降回每轮一个请求：exact-tag 只在装机版本变化时重探一次。

## ⚠️ `prerelease` 位不是"轨"，是"这一版还没转正"

这是本次接入最重要的一条事实，**照抄"prerelease = beta 渠道"会引入静默停更**。

拉全部 131 条 release 实测：**78 条 `prerelease: true` / 53 条 false**。UTM 的模式是每条
minor 线先发若干预览、再用**更高的补丁号转正**：

```
v5.0.5…v5.0.0  (Beta)      ← v5 线尚未转正
v4.7.5  v4.7.4             ← 转正
v4.7.3…v4.7.0  (Beta)
v4.6.5…v4.6.2              ← 转正
v4.6.1  v4.6.0  (Beta)
```

于是两种"显然"的算法各错一半：

- **只收 prerelease**：装机所在的线一转正就断供。按真实发布历史复算，这种窗口出现过
  **14 次**，最长 2024-11-27 → 2025-07-09（约 7.5 个月），期间上游发了 4 个正式版而用户
  一条都看不到，且**静默**（显示"已是最新"）。
- **取全局最新**：装着 `v4.7.3 (Beta)` 的人会被推去 `v5.0.5` —— 一条还没转正的线，
  而他要的是自己这条线的 `v4.7.5`。

所以候选算法是 `max(装机大版本线的最新 release, 全局最新正式版)`
（`GitHubCandidateScope.installedMajorLineOrNewestStable`）。两半都承重：前半把预览装机
带到自己那条线的转正版，后半防止老线上的装机被永久钉死。实测七个用例（含两个历史时点）
全部给出正确答案。

## 更新检测

stable 与 beta 各有一条 `GitHubReleaseRule`。两条都把 tag 限定为纯数字 `vX.Y…`，都只
接受精确资产名 `UTM.dmg`。stable 读 `/releases/latest`（GitHub 定义上不返回 prerelease，
所以正式轨永远看不到预览）；beta 读列表，另有两个字段：

```swift
usePrereleases: true                                  // 列表里才看得见预览
candidateScope: .installedMajorLineOrNewestStable      // 上面那条候选算法
installedTagPrefix: "v"                                // 开启 exact-release 判轨
```

`duo verify` 对任何设了 `installedTagPrefix` 的 rule **额外跑一条 discovery 诊断**：
拿列表最新的 tag 反查 exact release，要求应答仍带 `prerelease`/`draft` 且 tag 能被
`versionPattern` 提取，失败报 `channelDiscoveryBroken`。没有这条的话，exact-tag 端点挂掉
时 sweep 会全绿而真实用户的 UTM 行整个消失 —— 诊断在量一个没人跑的算法。
（变异验证：把 `installedTagPrefix` 改成 `"release-v"`，sweep 当场变红并打印原因。）

Homebrew 同时发布 `utm` 与 `utm@beta`，二者安装成同一个 `UTM.app` 并互相冲突。2026-09-03
复核时二者已分别更新到 `4.7.5` 和 `5.0.5`。`utm@beta` 若未被 Homebrew 文件名索引直接
接管，会回落到上述 GitHub exact-release 分轨；不会依据 cask 名之外的猜测跨渠道。

## Changelog

- 来源：`https://api.github.com/repos/utmapp/UTM/releases?per_page=40`
- stable / beta 各注册一条 channel-keyed `ChangelogRecipe`
- 两条共用同一份 JSON，`.gitHubReleases` decoder 按 `prerelease` 位分流并排除 draft
- **beta 那条带 `includesPromotedStable: true`**，这不是对称的疏漏：预览装机会被提供它那条线
  转正后的正式版（`4.7.3 → 4.7.5`），而那条 release 的 `prerelease` 是 false —— 只收预览的
  历史会把这次更新的说明渲染成一个空面板。stable 那条保持 false，正式轨永远看不到预览。
- `RemoteVersion.releaseChannel` / `UpdateResult.provenChannel` 把判出的渠道传给菜单栏、
  Workbench、缓存 key 与 recipe 选择
- fixture 测试同时放入 stable、beta 和 draft，确认两条历史互不串轨

## 一键安装

- stable 与 beta 都固定选择 `UTM.dmg`
- v5.0.5 真实资产：302,621,893 bytes；SHA-256
  `713afe73c711f01344b8766654be531cd391ed2e30931206f43b5159f143764f`
- 挂载后为 `com.utmapp.UTM` 5.0.5 (124)，Team `WDNLXAD4W8`
- `codesign --verify --deep --strict` 通过；Gatekeeper 判定 `accepted`、`Notarized Developer ID`
- 安装时仍由 `VendorInstaller` 做现有 bundle ID / Team ID 闸，不因远端渠道判定放宽身份校验
- TestFlight beta 仍交由 TestFlight，不由 DuoUpdater 替换 app

## 已知限制

- 首次判轨需要网络访问 GitHub exact-release API；之后按路径 + 版本缓存，版本不变不再重探。
- 自编译、改写版本号或上游已删除 exact tag 的构建无法证明渠道，此时**不声称渠道、退回 stable
  rule**（见上文「Channel 详情」下的说明），不会猜轨，也不会让整行消失。
  分两种：版本串根本形不成合法 tag 的（`v2.0b7` / `v1.0-rc6` 这类）在构造 tag **之前**就被
  `versionPattern` 挡掉，一个请求都不花；版本串合法但上游 tag 已删的（`v3.1.3` / `v3.0.4`
  已重打成 `-2` 后缀）每轮仍会花一个必然 404 的请求 —— 这类拷贝极少，没有为它加负缓存。
- GitHub 的 `prerelease` 位是判轨依据；上游若重新标记一条既有 release，DuoUpdater 会按上游
  当前声明处理。注意判轨结果按"路径 + 版本"缓存且**不设过期**，所以重新标记要到该拷贝版本变化
  时才会被重新读取。
- **预览轨是单向的**：4.7.3 (Beta) 拿到转正的 4.7.5 之后，下一轮 exact-tag 查出
  `prerelease: false`，这份拷贝就回到正式轨，不会再收到 v5 预览。这是"prerelease 是阶段不是轨"
  的直接推论，但用户可能当成 bug —— 想继续跟预览需要自己去装一个预览版。
- Homebrew 两个 cask 都存在且版本正确（`utm` 4.7.5 / `utm@beta` 5.0.5，2026-09-03 实测），
  都装到 `/Applications/UTM.app` 且互相冲突。brew 装过的拷贝由 `HomebrewCaskSource` 先应答
  （它排在 GitHub 之前），此时判轨与 `ResolvedChannelStore` 都不会运行；只有直装的拷贝才走
  这套机制。

## 验证

- 源级 fixture（fixture 按真实仓库形状构造，含转正与 draft）：直装 5.0.4 判 beta → 5.0.5；
  直装 4.7.4 判 stable → 4.7.5；**直装 4.7.3（老预览）→ 4.7.5，不是 5.0.5**；
  直装 3.0.0（废弃线）→ 4.7.5；draft 任何情况下不可选。
- 负例：未知 exact tag、应答缺 `prerelease`/`draft` 字段，均返回 nil 且不写入 store。
- 判轨缓存：第二次检查不再打 exact-tag 请求；换版本后旧证据失效；两份安装各自独立；
  检查失败时仍由 `provenChannel` 保住渠道。
- changelog fixture：stable / beta / draft 混合输入，stable 只得到正式版条目，
  beta 同时得到 5.0.5 与转正的 4.7.5。
- sweep 变异验证：把 `installedTagPrefix` 改坏，`duo verify` 立刻报 `channelDiscoveryBroken`。
- 真机端到端（同机两份真实安装）：5.0.5 那份判 beta、4.7.5 那份判 stable，两条记录按
  各自安装路径分别落盘，互不覆盖。
- 真实 v5.0.5 DMG 已完成摘要、bundle 身份、Team 与 Gatekeeper 验证。
- 候选算法另有直接单元测试（`LineAnchoredCeilingTests`），把装机版本放在历史中的任意位置 ——
  sweep 只能锚在"本机装的那份或最新 tag"上，够不到这些位置。⚠️ 这也意味着 sweep 的
  `lastGoodVersion` 依赖跑 sweep 那台机器装了哪个版本；今天两种锚都给出 5.0.5，所以
  `verify/baseline.json` 不会因换机器而打架，但换机器后若出现 `version went BACKWARDS`
  的 finding，先查这一条再怀疑上游。
