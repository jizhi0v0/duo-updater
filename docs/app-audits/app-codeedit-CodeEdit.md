# CodeEdit

## 基本信息
- Bundle ID: `app.codeedit.CodeEdit`
- Team ID: `9VS2VKC5LQ`（Developer ID Application: Austin Condiff；`spctl` 判 Notarized Developer ID）
- 观测版本: 0.3.6（`CFBundleVersion` 47），取自官方 v0.3.6 release 资产 `CodeEdit.dmg`，只读挂载读取
- 自更新机制: Sparkle 2.3.0（Info.plist 带 `SUFeedURL` + `SUPublicEDKey`）
- 架构 / OS: universal（x86_64 + arm64）；`LSMinimumSystemVersion` 13.0

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS  | GitHub | VendorProbe |
|--------------|---------|----------|------|--------|-------------|
| **stable**   | ✓       | ✗        | 未查 | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。bundle 自带 `SUFeedURL`，
通用 `SparkleAppcastSource` 直接读；另加一条常量 `ChannelBinding`（`CodeEditChannel`），原因见下。

- Homebrew ✗：cask `codeedit` 是 `auto_updates`，`HomebrewCaskSource` 让位，不作检测源。
- GitHub —：Sparkle 在优先链更前，且 appcast 的 enclosure 本来就指向 GitHub release 资产，不需要第二条源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（唯一轨） | `app.codeedit.CodeEdit` | — | 无（常量 binding） | feed 每条 item 都打 `<sparkle:channel>dev</sparkle:channel>`，binding 放行 `dev` | ✓ |

**`dev` 是唯一那条轨的标签，不是预发布轨。** 三条独立证据：

1. 厂商发版 workflow `.github/workflows/pre-release.yml` 写死 `SPARKLE_CHANNEL: dev`，
   `generate_appcast --channel "$SPARKLE_CHANNEL"`，每个版本都这样生成。
2. app 自己的 `SoftwareUpdater.allowedChannels(for:)` 无条件返回 `["dev"]`——它身上那个
   `includePrereleaseVersions` 设置此刻不影响任何事。
3. GitHub releases 列表（v0.3.6 往前 15 个）`prerelease` 全为 false。

**为什么需要 binding。** 每个 release 的 `appcast.xml` 资产**只含那一个版本**（v0.2.0、v0.3.4、
v0.3.5、v0.3.6 四份实测均为 1 条 item、tag `dev`）。没有 binding 时，`allowedChannels` 靠「装机
build 在 feed 里对应哪条 item」推断 channel——这只在副本已是最新时成立。落后一版，build 不在
feed 里，推断回退到默认 channel，而这份 feed 没有任何无 tag 的 item：匹配零条 → `.unknown`，
行上是问号而不是「有更新」。`CodeEditChannelTests.anInstallBehindTheFeedIsOfferedTheNewRelease`
在加 binding 前实测为红（0.3.5/46 得到 nil），加后为绿（得到 0.3.6）。

binding 解析为 `.stable` + `sparkleChannelNames: ["dev"]`，不进 `boundBundleIDs`（没有用户可设的
偏好需要监听，同 Ghostty）。`.stable` 同时意味着 `channelBindingsNeedingProof` 不要求 proof——
这里没有别的轨可串。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://github.com/CodeEditApp/CodeEdit/releases/latest/download/appcast.xml`
  （Info.plist 声明的地址；GitHub 的 `releases/latest/download/` 路径取最新 release 的同名资产）。
  app 运行时另走一步：`SoftwareUpdater` 先调 GitHub API 取 latest tag，再
  `setFeedURL(releases/download/<tag>/appcast.xml)`——指向的是同一份资产。
- 版本方案: `sparkle:version` 47 = `CFBundleVersion`，`sparkle:shortVersionString` 0.3.6 =
  `CFBundleShortVersionString`，两个命名空间都对得上，不需要 `versionIsBuild`。
- OS 上下限: feed `minimumSystemVersion` 13.0，**没有** `maximumSystemVersion`（四份 appcast 同）。
- 注意事项: feed 只有一条 item，所以 release history 永远只有 1 条。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（未 strings 核对） | 无 | 无可消费 |
| 证据 | bundle 内 `Sparkle.framework` 2.3.0，带 `Autoupdate` | 四份 appcast 均无 `<sparkle:deltas>`；workflow 显式 `--maximum-deltas 0`；channel-verify `deltas 0`（2026-09-12） | 服务端不发，`VendorAppcastDeltas` 无从取 |

- 格式: 不适用
- 阻塞项: 厂商主动关掉了（`--maximum-deltas 0`）

## Changelog
- 来源: Sparkle inline `<description>`（GitHub release 正文渲染成的 HTML，`h1`/`h2`/`ul` 结构），
  channel-verify 读到 25263 字符 inline；另有 `sparkle:fullReleaseNotesLink` → `https://codeedit.app/whats-new/`
- 跟随 channel: 不适用（单轨）
- Recipe 状态: 不需要。代价是只有最新一版的说明（feed 只含一条）。

## 一键安装
- 状态: 走 Sparkle 通用一键路径。签名前提已在真包上核对：enclosure 的 `sparkle:edSignature` 用
  bundle 自己的 `SUPublicEDKey` 对 v0.3.6 dmg（35962501 字节，sha256 `fa5478f8…eac9`）验签通过，
  翻转一个字节后验签失败（负对照）。**端到端安装未跑。**
- 格式: dmg
- **读的是**: 人人可手动下载的 GA——enclosure 就是 GitHub Releases 页上公开的 `CodeEdit.dmg`，没有灰度参数。
- 阻塞: 无

## 已知问题
- **重开条件**：`SoftwareUpdater.allowedChannels` 里有一段被注释掉的
  `if includePrereleaseVersions { return ["dev"] } return []`，注释写着 "Uncomment when production
  build is released"。启用那天，stable 会变成无 tag、`dev` 变成 opt-in，而这条常量 binding 会把
  `dev` 构建推给 stable 用户——届时必须改成读 `includePrereleaseVersions`。**现在读它是错的**：
  它默认 false，所有副本都会回退到默认 channel、看不到任何更新。
- `feed-discover` 对本 app 只给出 `declared`，没有报「每条 item 都有 tag」：`FeedDiscovery.decide`
  在检查那一条（gate 3）之前就对 declared feed 返回了。已另开任务处理。
- channel-verify 把这条 binding 描述为「read from this app's own preference」——那是 harness 对所有
  binding 的通用措辞，对常量 binding 不准确。

## 如何复验

```sh
# 身份 + feed 判定（只读挂载，自动卸载）
swift run --package-path application-test feed-discover <CodeEdit.dmg>
swift run --package-path application-test channel-verify <CodeEdit.dmg>
# 单测（含加 binding 前为红的那一条）
swift test --package-path DuoUpdaterCore --filter CodeEditChannelTests
# 每个 release 的 appcast 形状
gh release download v0.3.5 -R CodeEditApp/CodeEdit -p appcast.xml -O - | grep -c '<item>'
```

2026-09-12 实测（v0.3.6 官方 dmg）：
- `feed-discover` → `declared  https://github.com/CodeEditApp/CodeEdit/releases/latest/download/appcast.xml`
- `channel-verify`（加 binding 后）→ bundle id `app.codeedit.CodeEdit`、short 0.3.6、build 47、
  detected channel stable、winning source Sparkle、latest 0.3.6、download
  `https://github.com/CodeEditApp/CodeEdit/releases/download/v0.3.6/CodeEdit.dmg`、status up to date
- appcast 形状：v0.2.0 / v0.3.4 / v0.3.5 / v0.3.6 各 1 条 item，channel 均为 `dev`，build 分别 39 / 45 / 46 / 47
- 变异验证：删掉 switch 里的 case、把 tag 置空、把 tag 改成 `Dev`，三者都让
  `anInstallBehindTheFeedIsOfferedTheNewRelease` 变红（第一个还让 `everyBindingIsEnumerated` 变红）

## 建议下一步
1. 盯厂商那段被注释的 `allowedChannels` 分支；启用后按「已知问题」第一条改 binding，并补一条
   stable 副本不被推 `dev` 的用例。
2. 可选：若要看到历史版本说明，可给 `ChangelogCatalog` 加 GitHub releases 兜底（feed 只含最新一条）。
