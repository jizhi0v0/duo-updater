# Osaurus

## 基本信息
- Bundle ID: `com.dinoki.osaurus`
- Team ID: `4W8QF9VR2F`（Developer ID Application: Terence Pae），notarized
- 观测版本: 0.25.14（`CFBundleVersion` 0.25.14），取自官方 0.25.14 release 资产 `Osaurus-0.25.14.dmg`，只读挂载读取；另取 0.25.13 dmg 作落后一版的对照
- 自更新机制: Sparkle（Info.plist 带 `SUFeedURL`）
- 架构 / OS: arm64 only；`LSMinimumSystemVersion` 15.0
- 开源: `osaurus-ai/osaurus`，下面的 channel 结论都 settled from source

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS  | GitHub | VendorProbe |
|--------------|---------|----------|------|--------|-------------|
| **stable**   | ✓       | —        | 未查 | —      | —           |
| **beta**     | ○（厂商尚未发过） | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。bundle 自带 `SUFeedURL`，
通用 `SparkleAppcastSource` 直接读；另加一条常量 `ChannelBinding`（`OsaurusChannel`），原因见下。

- Homebrew —：cask `osaurus` 存在（2026-09-29 停在 0.25.12，落后 feed 两版），Sparkle 在优先链更前。
- GitHub —：appcast 的 enclosure 本来就指向 GitHub release 资产，不需要第二条源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.dinoki.osaurus` | 共享 | 无（常量 binding） | feed 每条 item 都打 `<sparkle:channel>release</sparkle:channel>`，binding 放行 `release` | ✓ |
| beta | `com.dinoki.osaurus` | 共享 | 偏好 `betaUpdatesEnabled` | `<sparkle:channel>beta</sparkle:channel>` | ○ 未接：厂商从未发过 |

**`release` 是 stable 轨的标签，不是预发布轨。** settled from source（`osaurus-ai/osaurus` main）：

1. `scripts/setup_env.sh`：tag 含 `-beta` 时写 `SPARKLE_CHANNEL=beta`，否则 `SPARKLE_CHANNEL=release`；
   `gen_appcast.sh` 默认也是 `release`，以 `generate_appcast --channel "$SPARKLE_CHANNEL"` 生成。
2. `Packages/OsaurusCore/Services/UpdaterService.swift` 的 `allowedChannels(for:)`：
   `betaUpdatesEnabled` 为 true 时返回 `["release", "beta"]`，否则 `["release"]`。

**为什么需要 binding。** 2026-09-29 的 feed 共 160 条 item，**全部**打 `release`，没有无 tag 的。
feed 保留历史，但不完整：GitHub 上 0.15.12 及更早的 317 个 release 没有对应 item（0.15.13 起全在）。
没有 binding 时，`allowedChannels` 靠「装机 build 在 feed 里对应哪条 item」推断 channel；装机版本
不在 feed 里时推断回退到默认 channel，而这份 feed 没有任何无 tag 的 item：匹配零条 → `.unknown`。
binding 解析为 `.stable` + `sparkleChannelNames: ["release"]`（`.stable` 自己不推导出任何 tag，必须显式写），
不进 `boundBundleIDs`（没有影响答案的用户偏好，同 CodeEdit）。

**beta 为什么没接。** 2026-09-29 查：478 个 GitHub release 里没有 `-beta` tag（唯一一个
`prerelease=true` 的是 `wa-helper-v0.2.3`，另一条产品线），feed 里没有 `beta` item。非 stable 的
binding 手写 channel 名需要一条 `bindingProofs` `.recipeAnchor`（`ChannelProofRegistry` 的第 3 条
谓词），而现在没有任何真实 beta 构建可以锚。所以所有副本一律解析为 `.stable`，不管
`betaUpdatesEnabled` 是什么——这与 app 自己今天拿到的东西一致（beta 轨为空）。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://osaurus-ai.github.io/osaurus/appcast.xml`（Info.plist 声明；`UpdaterService.feedURLString(for:)` 返回同一地址）
- 版本方案: `sparkle:version` = `sparkle:shortVersionString` = `CFBundleVersion` = `CFBundleShortVersionString`（0.25.14），不需要 `versionIsBuild`。
- OS / 架构: 每条 item 带 `minimumSystemVersion` 15.0 与 `hardwareRequirements` arm64，**没有** `maximumSystemVersion`。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 无可消费 |
| 证据 | — | 2026-09-29 feed 160 条均无 `<sparkle:deltas>`；channel-verify `deltas 0` | 服务端不发 |

## Changelog
- 来源: Sparkle inline `<description sparkle:format="markdown">`（GitHub release 正文），channel-verify 读到 900 字符 inline
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 0.25.13 检查）: ⚠ 结构化但**小标题被压平** — 40 个版本条目，最新 0.25.14 有 14 条，`headings []`，`What's Changed` / `🐛 Bug Fixes` 作为普通条目出现在列表里。原因在 Sparkle markdown 路径（`AppcastMarkdownParser.items` 把标题保留为单独一行），所有用 `sparkle:format="markdown"` 的 app 都一样，不是本 app 的问题
- 跟随 channel: 不适用（只有一条轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: 走 Sparkle 通用一键路径（enclosure = GitHub release 的 `Osaurus-<v>.dmg`，带 `sparkle:edSignature`）。
- 端到端（2026-09-29）: 装 0.25.13 → `duo check` 报 `0.25.13 → 0.25.14 [Sparkle, in-place]` →
  `duo install --yes` 走完 backup / download / verifyingSignature（EdDSA）/ extracting /
  verifyingCodeSignature / install → 装好的包 `0.25.14`、Team `4W8QF9VR2F`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized → 再 `duo check` 为 up to date
- 格式: dmg
- **读的是**: 人人可手动下载的 GA——enclosure 就是 GitHub Releases 页上公开的 dmg，没有灰度参数。
- 阻塞: 无

## 已知问题
- **beta 缺口 / 重开条件**：厂商出现第一个 `-beta` tag，或 feed 出现第一条
  `<sparkle:channel>beta</sparkle:channel>` item 时——binding 改读 `betaUpdatesEnabled`，加 beta
  resolution，并以那个真实构建为锚在 `bindingProofs` 登记 `.recipeAnchor`。在此之前，打开了
  `betaUpdatesEnabled` 的副本也只会被推 stable。
- channel-verify 把这条 binding 描述为「read from this app's own preference」——那是 harness 对所有
  binding 的通用措辞，对常量 binding 不准确（同 CodeEdit）。

## 如何复验

```sh
swift run --package-path application-test feed-discover <Osaurus-0.25.14.dmg>
swift run --package-path application-test channel-verify <Osaurus-0.25.14.dmg> --expect stable
swift test --package-path DuoUpdaterCore --filter OsaurusChannelTests
curl -sS https://osaurus-ai.github.io/osaurus/appcast.xml | grep -o '<sparkle:channel>[^<]*' | sort | uniq -c
```

2026-09-29 实测：
- `feed-discover`（0.25.14 dmg）：加 binding 前 `NEEDS BINDING https://osaurus-ai.github.io/osaurus/appcast.xml`；
  加后 `declared  https://osaurus-ai.github.io/osaurus/appcast.xml`
- `channel-verify --expect stable`（加 binding 后）：0.25.14 → detected stable、winning source Sparkle、
  latest 0.25.14、`status up to date`；0.25.13 → `status UPDATE → 0.25.14`，download
  `https://github.com/osaurus-ai/osaurus/releases/download/0.25.14/Osaurus-0.25.14.dmg`。
  两者都在 feed 里，所以加 binding 前也是同样结果——binding 管的是不在 feed 里的副本，由单测覆盖。
- 变异验证：tag 改成 `Release`、置空 `sparkleChannelNames`，都让 `anInstallAbsentFromTheFeedIsOfferedTheNewest`
  与 `theCurrentInstallIsUpToDate` 变红；删掉 switch 里的 case 让 `anInstallAbsentFromTheFeedIsOfferedTheNewest`
  与 `BindingChannelProofTests.everyBindingIsEnumerated` 变红。

## 建议下一步
1. 盯厂商的第一个 beta（见「已知问题」），届时接 beta 轨并登记 binding proof。
