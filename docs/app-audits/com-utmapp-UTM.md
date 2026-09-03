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
- Homebrew `utm` stable：`HomebrewCaskSource`
- GitHub 直装 stable：`GitHubReleasesSource` 的 stable rule
- GitHub 直装及 Homebrew `utm@beta`：`GitHubReleasesSource` 先按观测版本反查 exact release，再选择 beta rule

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.utmapp.UTM` | 共享 | 本地无标记时先视为候选 stable | exact release 为 `prerelease: false`，更新读 GitHub `/releases/latest` | ✓ |
| beta（TestFlight） | `com.utmapp.UTM` | 共享 | TestFlight receipt / 本地 inventory | TestFlight 托管 | ✓ |
| beta（GitHub/Homebrew） | `com.utmapp.UTM` | 共享 | 包内无标记；exact tag 对应 release 的 `prerelease: true` | 更新列表再强制只收 `prerelease: true` 且非 draft | ✓ |

UTM 的 stable 与 beta bundle ID、app 名、Team ID、资产名都相同，营销版本也是不带后缀的
纯数字。因此 `ReleaseChannel.detect()` 单靠本地 bundle 无法分轨。现在的做法不是用“5.x
就是 beta”这类临时版本猜测，而是以已安装 `CFBundleShortVersionString` 构造 exact tag
`v<version>`，读取 GitHub 对该 release 的权威 `prerelease` 位：

- `true`：选择 beta rule；
- `false`：选择 stable rule；
- exact tag 不存在、是 draft、或 tag 解析后与装机版本不一致：fail closed，本源不响应。

因此未来 UTM 把 5.x 转为 stable 时也不会跨轨。

## 更新检测

stable 与 beta 各有一条 `GitHubReleaseRule`。两条都把 tag 限定为纯数字 `vX.Y…`，都只
接受精确资产名 `UTM.dmg`；beta 另有两个硬门：

```swift
usePrereleases: true
releaseKind: .prerelease
```

`installedTagPrefix: "v"` 开启 exact-release 渠道发现。beta 列表即使把一个未来 stable
release 排在最前面，也会先按 release record 的 `prerelease` 位过滤，再选择最新 beta。

Homebrew 同时发布 `utm` 与 `utm@beta`，二者安装成同一个 `UTM.app` 并互相冲突。2026-09-03
复核时二者已分别更新到 `4.7.5` 和 `5.0.5`。`utm@beta` 若未被 Homebrew 文件名索引直接
接管，会回落到上述 GitHub exact-release 分轨；不会依据 cask 名之外的猜测跨渠道。

## Changelog

- 来源：`https://api.github.com/repos/utmapp/UTM/releases?per_page=40`
- stable / beta 各注册一条 channel-keyed `ChangelogRecipe`
- 两条 recipe 共用 GitHub Releases JSON，但 `.gitHubReleases` decoder 按 `prerelease` 位分流并排除 draft
- `RemoteVersion.releaseChannel` 把源端证明出的渠道传给菜单栏、Workbench、缓存 key 与 recipe 选择
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

- 渠道发现需要网络访问 GitHub exact-release API。
- 自编译、改写版本号或上游已删除 exact tag 的构建无法证明渠道，会安全地不响应，不会猜轨。
- GitHub 的 `prerelease` 位是渠道依据；若上游重新标记一条既有 release，DuoUpdater 会按上游当前声明处理。

## 验证

- 源级 fixture：直装 `5.0.4` 判 beta，解析 `5.0.5`、Beta notes 与一键 DMG；直装 `4.7.4` 判 stable，解析 `4.7.5` 与 Stable notes。
- 负例：beta 列表前置未来 stable `v6.0.0`，仍只选 `v5.0.5`；未知 exact tag 返回 nil。
- changelog fixture：stable / beta / draft 混合输入，两个 channel 只得到各自已发布条目。
- 真实 v5.0.5 DMG 已完成摘要、bundle 身份、Team 与 Gatekeeper 验证。
