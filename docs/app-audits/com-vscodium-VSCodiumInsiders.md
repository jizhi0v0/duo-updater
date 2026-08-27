# VSCodium Insiders

审计 2026-08-27,配合 issue #92。

## 基本信息

- Bundle ID: `com.vscodium.VSCodiumInsiders`
- App 名: `VSCodium - Insiders.app`
- CFBundleName / CFBundleDisplayName: `VSCodium - Insiders`
- 官网 / 下载页: https://github.com/VSCodium/vscodium-insiders/releases
- 观测版本: `CFBundleShortVersionString` = `CFBundleVersion` = `1.126.04518-insider`
- Team ID: `VC39D2VNQ7`(Baptiste Augrain)—与 stable `com.vscodium` 同一个 Team,
  `spctl -a --type execute` 判定 `accepted, source=Notarized Developer ID`
- 与 **VS Code Insiders**(`com.microsoft.VSCodeInsiders`,已接入)是完全不同的产品:
  不同 bundle id、不同仓库、不同 Homebrew cask(`vscodium@insiders` vs
  `visual-studio-code@insiders`)。2026-08-27 的渠道扫描一开始把两者混了,这份审计
  和对应的 recipe 只管 VSCodium 这一支。

以上四项(bundle id / 版本 / Team / notarized)不是抄 issue #92 的原始截图,是本次
审计重新下载 `VSCodium-darwin-arm64-1.126.04518-insider.zip`(GitHub Releases 原始
资产,211013018 字节,校验完整后 `ditto` 解包)、直接读 `Info.plist` 和跑
`codesign -dv` / `spctl -a` 得到的独立结果 —— 与 issue 描述完全吻合,两个独立见证。

## 覆盖矩阵

> ✓ = 已接入 ○ = 可接入(未实现) ✗ = 已调查不可行 — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **preview** | — | ○(未实现) | — | ✓ 一键 | — |

当前生效源:**GitHubReleasesSource**。

- **GitHub** — `VSCodium/vscodium-insiders` 是官方独立仓库,`/releases/latest`
  直接给出 macOS 资产,不需要猜测端点。本次接入的就是这一条。
- **Homebrew** — cask `vscodium@insiders` 存在(`CHANNEL_COVERAGE_TODO.md` §2c
  已列出实测版本 `1.126.04524`,注意 cask 版本号读的是 stable 的构建号规则,当天与
  GitHub 侧存在滞后窗口),未接入;GitHub 源已经覆盖,没有必要再加一条会退化到同一
  仓库的重复源。
- **Sparkle** — VSCodium 系列不走 Sparkle,`Info.plist` 无 `SUFeedURL`。
- **MAS** — 不在 App Store 分发。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.vscodium` | 独立 | — | — | ✓(已有) |
| preview(Insiders) | `com.vscodium.VSCodiumInsiders` | 独立 | 见下 | `channel: .preview` | ✓ |

**detect() 命中的路径,和 issue 里暗示的不一样。** issue #92 说"distinct bundle id"
就意味着检测免费,但 bundle id 是单个 camelCase 段 `VSCodiumInsiders`,"Insiders"
前面没有 `.`/`-` 分隔符,所以 `ReleaseChannel.detect` 里靠**分隔符**识别的
"`.insiders`/`-insiders` 后缀"那一步根本不触发。真正命中的是**显示名**那一步:
装机 `CFBundleName`/`CFBundleDisplayName` 是 `"VSCodium - Insiders"`,里面
"Insiders" 是一个独立词,`channelWord()` 按词边界匹配到它 → `.preview`。这条链路
用 `ChannelGuardTests.vscodiumInsidersDisplayNameSignalsPreview()` 直接钉住
(同时钉住"裸 bundle id 不触发"的反例),而不是改 `ReleaseChannel.swift`——按分工
那个文件本次改动不touch。

## 更新检测

`GitHubReleaseRule`(`DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubReleasesSource.swift`):

```swift
GitHubReleaseRule(
    bundleID: "com.vscodium.VSCodiumInsiders",
    owner: "VSCodium", repo: "vscodium-insiders",
    versionPattern: #"^([0-9]+(?:\.[0-9]+)+-insider)$"#,
    installAssetPattern: #"^VSCodium-darwin-(?:arm64|x64)-[0-9.]+-insider\.zip$"#,
    installerKind: .zip,
    channel: .preview)
```

实测(`GET /repos/VSCodium/vscodium-insiders/releases/latest`,2026-08-27):

```
tag_name: 1.126.04518-insider
prerelease: false
165 个 assets,其中 darwin 相关两个:
  VSCodium-darwin-arm64-1.126.04518-insider.zip
  VSCodium-darwin-x64-1.126.04518-insider.zip
```

- **`-insider` 后缀必须留在比较用的版本里 —— 这是本次审计要结的第一个"未验证"。**
  已验证:装机 `CFBundleShortVersionString`/`CFBundleVersion` 都是
  `1.126.04518-insider`(见上,读自真实解包的 `Info.plist`)。默认 pattern
  `v?([0-9]+(?:\.[0-9]+)+)` 会在最后一段数字处停下,吃不到 `-insider`;
  `VersionComparator` 把「缺失的第 4 段」补成数字 `"0"`,而数字分量恒大于文本分量
  (`insider` 是文本),于是缺后缀的 `1.126.04518` 会被判定"比装机的
  `1.126.04518-insider` 新"——**同一个版本被永久读成待更新**,不会随时间自愈。
  `GitHubReleaseRuleTests.vscodiumInsidersMissingSuffixWouldBeAPermanentPhantomUpdate()`
  把这条陷阱在真实 `VersionComparator` 上复现了一遍,不是靠注释描述。上面这条 recipe
  的 pattern 把后缀纳入捕获组,所以 remote == installed 时比较结果是
  `.orderedSame`,不会有 phantom update。
- **x64 资产是否存在 —— 第二个"未验证",已用真实响应结清:存在。** 与 stable 那条
  `installAssetPattern`(只认 arm64,即使 stable 仓库也确实同时发布了
  `VSCodium-darwin-x64-….zip`——那是既有决定,本次不动)不同,这条 recipe 的 pattern
  用 `(?:arm64|x64)` 同时匹配两个真实文件名,交给已有的架构感知选择逻辑
  (`GitHubReleaseRule.installableAsset` + `HostArch`)按本机架构挑正确的一个。
  `GitHubAssetSelectionTests.selectionIsIndependentOfListOrder` 用真实的两个文件名
  验证了这一步在正反序下都选对。
- **issue 把"要不要 `hostRequirement`"作为 x64 问题的落点,这个说法本身有出入,已在
  代码注释里改写清楚。** `hostRequirement` 是 `VendorProbeRecipe` 独有的字段,
  `GitHubReleaseRule` 根本没有这个概念——它从来靠 `installAssetPattern` +
  `installableAsset` 的架构感知选择来处理多架构,不需要额外的宿主门控。所以 x64
  存在与否影响的只是 pattern 该匹配几个文件名,不涉及"加不加 hostRequirement"这个
  并不存在的选项。

生产验证(`swift run --package-path CLI duo verify --only vscodium`,针对本
worktree 构建的 CLI,2026-08-27):

```
duo verify
0 vendor probes  2 GitHub rules  0 changelogs
─────────────────────────────────────────────
GitHub rule   ✓ 2  ⚠ 0  ✗ 0  ~ 0  - 0
total          ✓ 2  ⚠ 0  ✗ 0  ~ 0  - 0      2s
```

`--samples` report(`report.json`)里两条 finding:

```json
{"bundleID": "com.vscodium.VSCodiumInsiders", "channel": "preview",
 "version": "1.126.04518-insider", "status": "ok", "warnings": []}
{"bundleID": "com.vscodium", "channel": "stable",
 "version": "1.126.04524", "status": "ok", "warnings": []}
```

全量 `duo verify --samples`(135 vendor probes + 69 GitHub rules + 68
changelogs,~95s)同一天也跑过一遍:GitHub rule 一栏 `✓ 69 ⚠ 0 ✗ 0`,新增这一条
包含在 69 里,没有引入新的 warning;仅有的两条 warning(WorkBuddy 的 changelog、
LibreOffice 的 vendor probe)与本次改动无关,是既有问题。

## Changelog

**未接。** VSCodium 系列(含 stable)目前都没有 `ChangelogRecipe`——上游发行页
`https://github.com/VSCodium/vscodium-insiders/releases` 本身就是可读的 GitHub
Releases 页,`downloadURL` 已经指向这里,UI 能直接展示;如果之后要接原生 changelog,
可以复用 stable 若接入时选的解析方式(目前 stable 同样没有接)。

## 一键安装

- 状态:**已启用**,`kind: .zip`。
- 产物:`VSCodium-darwin-arm64-1.126.04518-insider.zip` /
  `VSCodium-darwin-x64-1.126.04518-insider.zip`,按本机架构由
  `installableAsset` 选择。
- **Team + notarization 门禁验证**:按 CLAUDE.md 的要求,没有只信任 issue 里的截图,
  本次审计重新下载了 arm64 资产并现场验证——`codesign -dv` 显示
  `TeamIdentifier=VC39D2VNQ7`、`Notarization Ticket=stapled`;
  `spctl -a -vv --type execute` 返回 `accepted, source=Notarized Developer ID`。
  与已装 `com.vscodium` stable 同一个 Team ID,`VendorInstaller` 的强制同 Team 闸
  会放行。
- **`ChannelProofRegistry` 不适用,不是漏做。** 该注册表(以及
  `channelProofsCoverEveryChannelRecipe` 穷举测试)只扫描
  `VendorProbeRegistry.recipes`,`GitHubReleaseRule` 从不在它的覆盖范围内——两种
  recipe 类型的"跨渠道误装"防线是分开设计的。对 `GitHubReleaseRule` 来说,
  channel 隔离靠的是 stable/preview 从**两个不同的仓库**(`VSCodium/vscodium` vs
  `VSCodium/vscodium-insiders`)读,不存在共享端点、靠 URL token 区分渠道的那种风险
  ——`ChannelArtifactProof` 要防的正是"同一个端点被两个渠道共用"的场景,这里根本
  不成立。

## 已知问题

- stable 的 `installAssetPattern` 是纯 arm64(`^VSCodium-darwin-arm64-…\.zip$`),
  即使 stable 仓库同一天也在发布 `VSCodium-darwin-x64-….zip`。这是既有状态,本次
  审计顺带确认了它,但按"外科手术式改动"的要求没有去改——如果要修,应该是
  `com.vscodium` 那条单独的改动,不属于 #92。
- 未接 Homebrew 源(`vscodium@insiders` cask 存在但会与 GitHub 源重复,故意不加)。

## 建议下一步

1. 若 VSCodium stable 那条 arm64-only 的 `installAssetPattern` 后续要补 x64,
   参考本次 insiders 这条的 `(?:arm64|x64)` 写法和对应的
   `GitHubAssetSelectionTests.multiCandidateCases` 条目。
2. 若之后要给 VSCodium(stable 或 insiders)接原生 changelog,GitHub Releases 页
   本身就是候选源。
