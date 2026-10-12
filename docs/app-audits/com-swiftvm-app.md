# SwiftVM

## 基本信息
- Bundle ID: `com.swiftvm.app`
- Team ID: `NYSXATY4AA`（三个包一致：1.0.0、1.0.0-beta.16、1.0.0-beta.12），`spctl` 均为 Notarized Developer ID
- 观测版本: stable 1.0.0（`CFBundleVersion` 16）；beta 1.0.0-beta.16（16）、1.0.0-beta.12（12）。取自 GitHub release 资产 dmg，只读挂载读取（2026-10-12）
- 自更新机制: Sparkle 2.10.0（Info.plist 带 `SUFeedURL` + `SUPublicEDKey`，`SUEnableAutomaticChecks` 与 `SUAutomaticallyUpdate` 均为 true）
- 架构 / OS: arm64 only；`LSMinimumSystemVersion` 27.0；`LSUIElement` true（菜单栏 app）
- 开源: `swiftvm-app/swiftvm`（Apache-2.0），下面的 channel / 版本 / 发布结论都 settled from source（`main`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —        | —   | —      | —           |
| **beta**     | ✓（`SwiftVMChannel`） | — | — | — | —         |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。两种构建各自在 Info.plist 里声明
自己的 feed，通用 `SparkleAppcastSource` 直接读；另加一条 `ChannelBinding`（`SwiftVMChannel`），原因见下。

- Homebrew —：homebrew/cask 里没有（`brew info --cask swiftvm` → `No Cask with this name exists`）。
  厂商自己的 tap `swiftvm-app/homebrew-tap` 有 `Casks/swiftvm.rb`（1.0.0，`auto_updates true`，
  `depends_on arch: :arm64`，sha256 与官方 dmg 一致），`auto_updates` 让 `HomebrewCaskSource` 让位，
  Sparkle 在优先链更前，不需要它。
- GitHub —：appcast 的 enclosure 本来就指向 GitHub release 资产，不需要第二条源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.swiftvm.app` | 共享 | bundle 的 `SUFeedURL` = stable feed（binding 答 nil，走通用推断） | 独立 feed，item 无 tag | ✓ |
| beta    | `com.swiftvm.app` | 共享 | bundle 的 `SUFeedURL` = beta feed | 独立 feed + `<sparkle:channel>beta</sparkle:channel>` | ✓ |

**渠道在构建时定死，app 里没有开关，也没有任何偏好键。** settled from source（`swiftvm-app/swiftvm` main）：

1. `App/Updates/UpdateService.swift` 第 7–13 行 `UpdateChannel.channels(forVersion:)`：版本串含
   `-beta.` 时返回 `["beta"]`，否则空集；第 88–92 行 `allowedChannels(for:)` 只调用它，参数是
   第 40 行读的 `CFBundleShortVersionString`。没有 `feedURLString(for:)`，没有 UserDefaults 键，
   没有设置界面。
2. `.github/workflows/release-beta.yml` 第 45–51 行：版本 = `BETA_VERSION` 文件 + `-beta.` + 提交数，
   第 63 行 `feed_url` = `https://github.com/swiftvm-app/swiftvm/releases/download/beta-channel/appcast-beta.xml`；
   第 104 行 `CHANNEL: beta` → `scripts/generate-appcast.sh` 第 31–33 行给每条 item 写
   `<sparkle:channel>beta</sparkle:channel>`。
3. `.github/workflows/release.yml`：输入是一个 beta tag，第 59 行 build 号取那个 beta tag 的提交数，
   第 68 行从 beta tag 重新构建，第 71 行 `feed_url` = `…/releases/latest/download/appcast.xml`，
   第 117 行 `CHANNEL: stable`（不写 channel 元素）。
4. `scripts/build-release.sh` 把版本与 feed 地址写进 Info.plist；开发构建两者都不写，不自更新
   （`UpdateService.updates(from:)` 第 46–50 行）。

所以 beta 构建与 stable 构建的区别是：版本串带 `-beta.N`，且 Info.plist 的 `SUFeedURL` 指向 beta feed。
**偏好键：无。** 不需要真机拨开关——没有开关可拨，也没有要确认的写入。

**为什么还是加了 binding。** 没有 binding 时两轨今天都解析正确（见「如何复验」的加 binding 前结果），
但 beta 副本被认成 beta 只靠一件事：`SparkleAppcastSource.allowedChannels` 在 beta feed 里找到了
副本自己的 build。beta feed 的 item **全部**打了 `beta` tag、没有无 tag 的；副本的 build 一旦不在
feed 里，推断回退到默认 channel，匹配零条。厂商 workflow 在下载不到旧的 `appcast-beta.xml` 时会
从零生成只含当前一条的新 feed（`release-beta.yml` 第 91–99 行 + `generate-appcast.sh` 第 74–87 行），
并另备一个「Republish Beta Appcast」workflow 把 beta 放回去——这正是会发生的形状。
`feed-discover` 对 beta 包在加 binding 前报 `NEEDS BINDING`。

`SwiftVMChannel` 读 bundle 自己的 `SUFeedURL`（`ChannelBinding.bundleFeeds`）：等于 beta feed →
`.beta`（tag 由 `ReleaseChannel.beta` 推导，不手写，所以不需要 `bindingProofs`）；其余 → nil。
用 feed 地址而不是版本串，是因为 resolver 拿到的是 bundle 的 feed，拿不到版本；在厂商的构建里
两者出自同一个 workflow 输入。不进 `boundBundleIDs`：没有可监听的用户偏好。

**beta 副本永远留在 beta 轨。** beta 构建只读 beta feed，beta feed 里只有 beta——app 自己的 Sparkle
就是这样，duo 也一样。厂商的 stable 都是某个 beta 原样重建：v1.0.0 与 v1.0.0-beta.16 的
`target_commitish` 同为 `0d23d67d`，build 号同为 16。所以 beta.16 副本看到的是「已是最新」，
它永远不会被推 stable 1.0.0；即便读到了，Sparkle 比 `sparkle:version`（16 对 16）也不算新版。
stable 副本只读 stable feed，那里没有 beta item，不存在跨轨。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点:
  - stable `https://github.com/swiftvm-app/swiftvm/releases/latest/download/appcast.xml`（1 条 item，无 tag）
  - beta `https://github.com/swiftvm-app/swiftvm/releases/download/beta-channel/appcast-beta.xml`（2 条 item，均 `beta`）
- 版本方案: `sparkle:version` = `CFBundleVersion` = 提交数（`git rev-list --count`）；
  `sparkle:shortVersionString` = `CFBundleShortVersionString`（`X.Y.Z` / `X.Y.Z-beta.N`，N 即 build 号）。
  stable 继承被提升那个 beta 的 build 号。不需要 `versionIsBuild`。
- OS / 架构: `generate-appcast.sh` 第 43 行给每条 item 写死 `sparkle:minimumSystemVersion` 27.0，
  没有 `maximumSystemVersion`，没有 `hardwareRequirements`；包本身 arm64 only、`LSMinimumSystemVersion` 27.0。
  `SparkleAppcastSource` 解析并执行 min/max 两个界。27.0 是这一代的固定下限（写在生成脚本里，不随
  release 变），feed 自己就带着，不需要另外冻结。
- 注意事项: `beta-channel` 这个 GitHub release 不是一个版本，只是 beta feed 的载体（正文
  "Rolling Sparkle appcast for the beta channel. Do not delete."，prerelease）。

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 无可消费 |
| 证据 | Sparkle 2.10.0 的 `Autoupdate` 含 `BinaryDelta` 字符串（`strings` 12 处命中，1.0.0 包） | 2026-10-12 两份 feed 均无 `<sparkle:deltas>`；`generate-appcast.sh` 不生成 delta；channel-verify `deltas 0` | 服务端不发 |

- 格式: —
- 阻塞项: 厂商不发

## Changelog
- 来源: **无**。feed 没有 `<description>`、没有 `<sparkle:releaseNotesLink>`，只有
  `<sparkle:fullReleaseNotesLink>` 指向 GitHub release 页；而那三个 release 的正文都是空的。
- 结构化（2026-10-12，`channel-verify` 的 `changelog pane` 行，三个包相同）:
  `changelog pane  none — the pane says there are no release notes`
- 为什么是空的（settled from source）: 两个 release workflow 都用 GitHub 的
  `releases/generate-notes` 生成正文，再经 `scripts/clean-changelog.sh` 去掉 `**Full Changelog**`
  行、New Contributors 段和「by @x in …」尾巴。该 API 按合并的 PR 列条目；仓库至今 0 个 PR
  （2026-10-12），于是只剩被删掉的那一行。GitHub API 对 v1.0.0、v1.0.0-beta.16、v1.0.0-beta.12
  返回 `"body": null`。仓库里也没有 CHANGELOG 文件，官网（`website/`）没有更新日志页。
- `fullReleaseNotesLink` 不被 `SparkleAppcastSource` 读取（只读 `releaseNotesLink`）；就算读了，指向的也是空页。
- 跟随 channel: 不适用（目前没有说明）
- Recipe 状态: **暂不需要**——厂商没发说明，recipe 只会解析出零条。重开条件与做法见「建议下一步」。

## 一键安装
- 状态: 走 Sparkle 通用一键路径（enclosure = GitHub release 的 `SwiftVM-<v>.dmg`，带 `sparkle:edSignature`；
  bundle 带 `SUPublicEDKey`）。三个包 Team 一致（`NYSXATY4AA`），Developer ID + 公证，dmg，没有嵌套 app。
  `Contents/Helpers/` 有两个可执行文件：`swiftvm`（命令行，厂商 tap 的 cask 把它链到 `binary`）和
  `swiftvm-agent`（`Packages/SwiftVMKit/Sources/GuestAgentMac`，装进 macOS 客体里的代理）。两者都不是
  宿主上常驻的 login item / LaunchAgent。
- 端到端: **未跑**——真机端到端由维护者在本审计之后串行执行（需要先装旧版再 `duo install`）。
  可用的旧版：beta 轨 1.0.0-beta.12 → 1.0.0-beta.16；stable 轨只有 1.0.0 一个 release，暂无旧版可降。
- 格式: dmg（arm64 only）
- 校验: Sparkle EdDSA（`sparkle:edSignature`）+ Team ID 闸。feed 的 `length` 与下载字节数一致
  （1.0.0：4914007；beta.16：4914698；beta.12：4914440）。
- **读的是**: stable 是人人可手动下载的 GA（GitHub Releases 的 latest）；beta 是 beta 轨最新，
  同样是 GitHub 上公开的 prerelease 资产，没有灰度参数——app 自己的 Sparkle 读的就是同一份。
- 阻塞: 无已知阻塞。

## 已知问题
- **自更新器可能抢先**：`SUAutomaticallyUpdate` 与 `SUEnableAutomaticChecks` 都是 true，app 自己的
  Sparkle 会静默下载并安装。端到端第二轮（运行中、自更新器已暂存）要看 duo 换完后是否被它换回。
- **运行中的虚拟机**：厂商文档说自更新会「照常退出 app，并对正在运行的机器提问」。duo 在 app 运行、
  有虚拟机在跑时 install / restart 的表现没测过，端到端时一并看。
- channel-verify 把 SwiftVM 的 binding 描述为「read from this app's own preference」——那是 harness 对所有
  binding 的通用措辞；这里读的是 bundle 的 `SUFeedURL`，没有偏好。

## 如何复验

```sh
gh api repos/swiftvm-app/swiftvm/releases -q '.[] | "\(.tag_name) \(.prerelease) \(.body)"'
curl -sSL https://github.com/swiftvm-app/swiftvm/releases/latest/download/appcast.xml
curl -sSL https://github.com/swiftvm-app/swiftvm/releases/download/beta-channel/appcast-beta.xml
swift run --package-path application-test feed-discover <SwiftVM-1.0.0-beta.16.dmg>
swift run --package-path application-test channel-verify <SwiftVM-1.0.0.dmg> --expect stable
swift run --package-path application-test channel-verify <SwiftVM-1.0.0-beta.12.dmg> --expect beta
swift run --package-path application-test channel-verify <SwiftVM-1.0.0-beta.16.dmg> --expect beta
swift test --package-path DuoUpdaterCore --filter SwiftVMChannelTests
```

包地址：
- `https://github.com/swiftvm-app/swiftvm/releases/download/v1.0.0/SwiftVM-1.0.0.dmg`
- `https://github.com/swiftvm-app/swiftvm/releases/download/v1.0.0-beta.16/SwiftVM-1.0.0-beta.16.dmg`
- `https://github.com/swiftvm-app/swiftvm/releases/download/v1.0.0-beta.12/SwiftVM-1.0.0-beta.12.dmg`

2026-10-12 实测：
- `feed-discover`：1.0.0 → `declared …/releases/latest/download/appcast.xml`；beta.16 加 binding 前
  `NEEDS BINDING …/beta-channel/appcast-beta.xml`，加后 beta.16 与 beta.12 都是 `declared`。
- `channel-verify`（加 binding 后）：
  - 1.0.0 `--expect stable`：`inferred stable`、`ChannelBinding <none for this app>`、
    `detected channel → stable`、winning source Sparkle、latest 1.0.0、`status up to date`
  - 1.0.0-beta.12 `--expect beta`：`ChannelBinding beta`、`detected channel → beta`、latest
    1.0.0-beta.16、download `…/v1.0.0-beta.16/SwiftVM-1.0.0-beta.16.dmg`、`status UPDATE → 1.0.0-beta.16`
  - 1.0.0-beta.16 `--expect beta`：`ChannelBinding beta`、`detected channel → beta`、latest
    1.0.0-beta.16、`status up to date`
  - 加 binding 前三者结果相同（beta 包靠 build 12 / 16 在 beta feed 里被推断为 beta）——binding 管的是
    build 不在 feed 里的 beta 副本，由单测覆盖。
- 单测 `aBetaCopyMissingFromTheFeedIsStillOfferedTheNewerBeta`：beta feed 只剩 beta.16 时，beta.12 副本
  没有 binding 得到 nil（红），有 binding 得到 1.0.0-beta.16（绿）。变异：resolver 改答 `.stable`
  让它与 `theBetaFeedResolvesTheDerivedBetaTag` 变红。

## 建议下一步
1. 一键端到端（维护者串行）：beta 轨装 1.0.0-beta.12 → `duo install`，两轮（不运行 / 运行中且自更新器已暂存）。
2. changelog 重开条件：任一版本 release 正文非空。届时照 `Recipes/com-robinebers-openusage.swift`
   加两条 `.gitHubReleases` recipe（stable / beta），**都要** `tagPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$"#`，
   否则 beta recipe 会把 `beta-channel` 那个 prerelease 的一句话当成一个版本；beta recipe **不要**
   `includesPromotedStable`（beta 副本不会被推 stable）。先看真实正文的标题结构再定。
