# RuntimeViewer

## 基本信息
- Bundle ID: `com.JH.RuntimeViewer`（1.1.0 起每个 release 都是这个 id，没有改名史）
- Team ID: `D5Q73692VW`（Developer ID Application: JieHui Lai），1.1.0 / 1.3.0 / 2.0.0 各 beta 与 RC / 2.0.0 / 2.1.1 / 2.1.2 / 3.0.0-beta.7 真包一致，`spctl` 为 Notarized Developer ID
- 观测版本: 2.1.2（`CFBundleVersion` 20260815.06.34）为最新稳定版，3.0.0-beta.7（`CFBundleShortVersionString` **3.0.0**，build 20261016.12.58）为最新预发布版；均取自官方 GitHub release 资产 `RuntimeViewer-macOS.zip`（2026-10-18）
- 自更新机制: Sparkle 2.9.2（v2.0.0-RC.6 起 Info.plist 带 `SUFeedURL`、`SUPublicEDKey`，三个真包的公钥相同）；更早的版本完全没有 Sparkle
- 架构 / OS: universal（x86_64 + arm64）；`LSMinimumSystemVersion` 15.0（2.0.0-beta.4 起；1.x 为 12.0，2.0.0-beta.1 为 14.0）；未沙盒
- 开源: `MxIris-Reverse-Engineering/RuntimeViewer`（MIT）。下面的 feed、channel、版本方案与 changelog 结论 settled from source：`Documentations/SparkleRelease.md`、`RuntimeViewerPackages/Sources/RuntimeViewerSettings/{Settings,Settings+Update,SettingsStorage}.swift`、`RuntimeViewerUsingAppKit/RuntimeViewerUsingAppKit/App/UpdaterService.swift`（`main`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —        | —   | —      | —           |
| **beta**     | ✓（`RuntimeViewerChannel`） | — | — | —  | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。从 RC.6 起的副本自己声明 `SUFeedURL`，通用 `SparkleAppcastSource` 直接读取；更早、不带 feed 的副本由 `RuntimeViewerChannel` 的 `feedOverride` 给同一个地址（见「已知问题」）。

- Homebrew —：cask `runtimeviewer`（2026-10-18 为 2.1.2，同一个 GitHub zip）`auto_updates: true`，`HomebrewCaskSource` 退让，cask 装的副本同样由 Sparkle 应答。
- MAS —：不上架。
- GitHub —：appcast 的 enclosure 就是 GitHub release 资产，不需要第二条源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.JH.RuntimeViewer` | 共享 | `settings.json` `update.includePrereleases` 为 false / 缺省 | feed 里无 tag 的 item | ✓ |
| beta    | `com.JH.RuntimeViewer` | 共享 | `settings.json` `update.includePrereleases` 为 true | `<sparkle:channel>beta</sparkle:channel>` | ✓ `RuntimeViewerChannel`，真机拨开关已确认 |

**开关在哪，settled from source：**

1. Settings ▸ Updates ▸ Channel ▸「Include pre-release versions (Beta)」= `Settings.Update.includePrereleases`，默认 `false`；`allowedChannels` 为 `includePrereleases ? ["beta"] : []`，由 `UpdaterService` 交给 Sparkle 的 `allowedChannels(for:)`。
2. `Settings` 是 MetaCodable `@Codable`，由 `SettingsFileSystemStorage` 以 JSON 写到 `~/Library/Application Support/RuntimeViewer/settings.json`（Debug 构建是 `RuntimeViewer-Debug`）。只有某项设置改动后才写文件：首次启动后目录里只有 `mcp-http-port`，没有 `settings.json`。
3. 发版：`ArchiveScript.sh` / `release.yml` 按 tag 推断 channel：`*-RC*|*-beta*|*-alpha*` 进 `beta`，其余进 stable（`Documentations/SparkleRelease.md`）。

**为什么必须有 binding：** 预发布包上没有任何 channel 标记。3.0.0-beta.7 的 `CFBundleShortVersionString` 是 `3.0.0`，和将来的 3.0.0 正式版一样；bundle id、名字、文件名也一样。`ReleaseChannel.detect` 只能判 stable。`SparkleAppcastSource` 能拿 build 号去 feed 里反推，但只对 build 还在 feed 上的副本有效，厂商会修剪 feed（2026-10-18 的 feed 只剩 beta.4/6/7）。没有 binding 的话，在 2.1.2 上勾了开关的用户拿不到 beta。

**没勾或读不到 → `.stable`（权威）**，和 Mac Mouse Fix 同一形状：这是 app 自己的默认值，app 内的 Sparkle 此时只放行无 tag 的 item。所以装着 beta、没勾开关的副本只会收到下一个正式版，和 app 自己的更新器一致。

**真机确认（2026-10-18，2.1.2 运行中，通过设置界面拨开关）：**
- 打开：`settings.json` 出现，`update` = `{"automaticallyChecks": true, "checkInterval": "daily", "automaticallyDownloads": false, "includePrereleases": true}`；`duo check RuntimeViewer` → `2.1.2 → 3.0.0 [Sparkle, in-place]`。
- 关闭：文件保留，`includePrereleases` 变成 `false`；`duo check` → `Everything is up to date.`
- 删掉文件：`channel-verify` → `ChannelBinding  stable`，`latest 2.1.2`，`up to date`。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml`（Info.plist 声明；GitHub Pages 托管 `main` 分支的 `docs/appcast.xml`）
- 版本方案: `sparkle:version` = `CFBundleVersion`，格式 `YYYYMMDD.HH.MM`（2.0.0-beta.9 起；之前是 1 / 12 / 13 这样的小整数，单调递增）；`sparkle:shortVersionString` = `CFBundleShortVersionString`，预发布不带后缀。同一个 3.0.0 下的几个 beta 和将来的正式版只能靠 build 区分，`UpdateChecker` 本来就先比 build。
- feed 形状（2026-10-18）: 6 条 item（3.0.0 ×3 带 `beta` tag：beta.7/6/4；2.1.2、2.1.1、2.0.1 无 tag）。每条都有 `minimumSystemVersion` 15.0；没有 `maximumSystemVersion`、`phasedRolloutInterval`、`hardwareRequirements`、`<sparkle:deltas>`；item 里没有 `<description>` 和 `releaseNotesLink`。厂商会撤掉坏版本（2.1.0 已从 feed 拿掉，见 v2.1.1 说明）。
- 注意事项: 无灰度、无 WAF。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 无可消费 |
| 证据 | 2.1.2 包内 `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta` / `sparkle:deltaFrom`（32 处） | 2026-10-18 feed 6 条均无 `<sparkle:deltas>`；`channel-verify` `deltas 0` | 服务端不发；发了也是 Sparkle binary delta，`DeltaApplier` 现成可用 |

- 格式: Sparkle binary delta（客户端能力）
- 阻塞项: 厂商不发

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 默认不会 | 无 | 没查 |
| 证据 | `Settings.Update.automaticallyDownloads` 默认 `false`，Sparkle 不会后台下载 | 第二轮启动 2.1.1、Sparkle 完成检查（`SULastCheckTime` 已写）后，`~/Library/{Caches,Application Support,Containers}` 下没有 RuntimeViewer 相关的 >8 MB 新文件 | 用户打开自动下载后才会出现 Sparkle 的标准暂存，本次没测 |

## Changelog
- 来源: GitHub release 正文（`release.yml` 从 `Changelogs/<tag>.md` 写入）。feed 不带 notes。
- recipe: `Recipes/com-JH-RuntimeViewer.swift`，两条，读 `https://api.github.com/repos/MxIris-Reverse-Engineering/RuntimeViewer/releases?per_page=40`，`structuredFormat: .gitHubReleases`：
  - stable：`tagPattern ^v([0-9]+(?:\.[0-9]+)+)$`，只收裸版本号。
  - beta：`includesPromotedStable: true`（beta 会毕业成同号正式版，例如 2.1.0-RC.3 → 2.1.0），`tagPattern` 收 `-alpha/-beta/-RC.N` 并保留后缀，让同为 3.0.0 的几个 beta 条目能区分开。
- 结构化（`channel-verify` 的 `changelog pane` 行，2026-10-18）:
  - beta（2.1.2 + 开关打开）：`recipe changelog:com.JH.RuntimeViewer:beta: 20 entries; newest 3.0.0-beta.7: 18 items, headings ["New", "Improved", "Fixed"]; first items ["**Find navigator**: search the interface", …]`
  - stable（2.1.2，无设置文件）：`recipe changelog:com.JH.RuntimeViewer:stable: 8 entries; newest 2.1.2: 9 items, headings ["Bug fixes", "Dependency updates", "Upgrade notes"]; first items ["**Inspecting an injected arm64e app no l", …]`
  - 分节都保留了。v3.0.0-beta.6 的正文只有一行 Full Changelog 链接，条目为空，是厂商原样。
- 跟随 channel: 是
- Recipe 状态: ✓ 已接入

## 一键安装
- 状态: 支持（Sparkle 通用路径：GitHub release 的 `RuntimeViewer-macOS.zip`，带 `sparkle:edSignature`）
- 端到端（2026-10-18）:
  - 第一轮（未运行）2.1.1 → `duo install --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 56838153`，16 s。之后为 2.1.2 (20260815.06.34)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，Team `D5Q73692VW`；`diff -r --no-dereference` 对厂商 2.1.2 包无差异。
  - 无 Sparkle 的旧副本 1.3.0（build 1，无 `SUFeedURL`）：`duo check` → `1.3.0 → 2.1.2 [Sparkle, in-place]`，`duo install` → `installed`，结果为 2.1.2。
  - 第二轮（运行中）2.1.1 启动后 `duo install` → `installed`；`duo restart RuntimeViewer` → `restarted`，pid 换新，此后 10 s 内磁盘上一直是 2.1.2。自更新器默认不下载，没有可碰撞的暂存（见上）。
  - beta：开关打开时 2.1.2 → `duo install` → `installed`，`bytesDownloaded: 122471052`，结果为 3.0.0 (20261016.12.58)，严格签名校验、`spctl` 通过，对厂商 beta.7 包无差异；之后 `duo check` 报已是最新。
- 格式: zip
- 校验: feed 只有 EdDSA 签名，没有 SHA 摘要；GitHub asset 的 `digest` 不经过 Sparkle 路径。
- **读的是**: 人人可手动下载的 GA。enclosure 是 GitHub Releases 页上公开的 zip，feed 没有 `phasedRolloutInterval`。beta 是同一 feed 上的 `beta` tag，和 app 自己勾开关后看到的一致。
- 嵌套: `Contents/Applications/RuntimeViewerCatalystHelper.app`（`LSUIElement`、`LSBackgroundOnly`）；3.0 起还有 `Contents/Applications/runtime-viewer-cli`；`Contents/Library/LaunchDaemons/com.mxiris.runtimeviewer.service.plist`（SMAppService 特权 helper，`KeepAlive`，`BundleProgram` 指向包内）。换包后常驻的 helper 继续跑旧代码，但 app 每次启动都会比较 `RuntimeViewerServiceVersion`，不一致就重装 helper（`SparkleRelease.md`），和厂商自己的 Sparkle 更新路径一样，所以不挡一键。本次验证没有拨 helper 的安装，前后都没有注册任何 daemon。
- 阻塞: 无

## 已知问题
- **RC.6 之前的副本不带 Sparkle。** 1.1.0–1.3.0（稳定版）与 2.0.0-beta.1 至 RC.3 没有 `SUFeedURL`，id 和 Team 相同，build 递增（1 → 12/13 → `YYYYMMDD.HH.MM`）。不能用 `SparkleFeedCatalog` 补地址：这个 id 有 binding，`noEntryIsAlsoManagedByAChannelBinding` 不允许两者并存。所以 `RuntimeViewerChannel` 只在 bundle 不声明 `SUFeedURL` 时给出同一个 feed 作 `feedOverride`。两条轨读的是同一个地址，channel 由派生的 `beta` tag 决定，因此 `channelBindingsNeedingProof` 没有要证明的东西（`allResolutions` 用声明了 feed 的 bundle 列举）。1.x 的 `LSMinimumSystemVersion` 是 12.0，feed 里的 item 要求 15.0，低于 15 的系统上 feed 会正确地给不出东西。
- **装着 beta、没勾开关**：只会收到下一个正式版（例如 3.0.0），不会收到 beta.8。这是有意的，与 app 自身行为一致（见「Channel 详情」）。
- 开关变化不被监听（`preferenceWatchCandidates`）：目录里还有 app 的其他状态（`mcp-http-port`）；在下一次扫描或 app 启动/退出时生效。

## 如何复验

```sh
gh release download v2.1.2 -R MxIris-Reverse-Engineering/RuntimeViewer --pattern 'RuntimeViewer-macOS.zip'
ditto -x -k RuntimeViewer-macOS.zip x
swift run --package-path application-test feed-discover x/RuntimeViewer.app
swift run --package-path application-test channel-verify x/RuntimeViewer.app
curl -sS https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml | grep -cE '<sparkle:channel>beta'
gh api "repos/MxIris-Reverse-Engineering/RuntimeViewer/contents/RuntimeViewerPackages/Sources/RuntimeViewerSettings/Settings+Update.swift?ref=main" -q .content | base64 -d
```

2026-10-18 实测：

| 包 | 版本 (build) | `SUFeedURL` | min OS | feed-discover |
|---|---|---|---|---|
| 3.0.0-beta.7 | 3.0.0 (20261016.12.58) | 有 | 15.0 | `declared` |
| 2.1.2 | 2.1.2 (20260815.06.34) | 有 | 15.0 | `declared` |
| 2.1.1 | 2.1.1 (20260812.15.57) | 有 | 15.0 | — |
| 2.0.0 | 2.0.0 (20260424.06.08) | 有 | 15.0 | — |
| 2.0.0-RC.6 | 2.0.0 (20260424.04.26) | 有 | 15.0 | — |
| 2.0.0-RC.3 | 2.0.0 (20260303.12.04) | 无 | 15.0 | — |
| 2.0.0-RC.2 | 2.0.0 (20260301.23.48) | 无 | 15.0 | `no Sparkle, no electron-builder update config and no MyGo feed` |
| 2.0.0-beta.9 | 2.0.0 (20260106.23.26) | 无 | 15.0 | — |
| 2.0.0-beta.5 | 2.0.0 (13) | 无 | 15.0 | — |
| 2.0.0-beta.4 | 2.0.0 (12) | 无 | 15.0 | — |
| 2.0.0-beta.1 | 2.0.0 (1) | 无 | 14.0 | — |
| 1.3.0 | 1.3.0 (1) | 无 | 12.0 | — |
| 1.1.0 | 1.1.0 (1) | 无 | 12.0 | — |

全部为 `com.JH.RuntimeViewer`、Team `D5Q73692VW`。

`channel-verify /Applications/RuntimeViewer.app`（2.1.2，`includePrereleases: true`）：`inferred stable (overridden below)`，`ChannelBinding beta — read from this app's own preference`，`detected channel → beta`，`winning source Sparkle`，`latest 3.0.0`，download `…/v3.0.0-beta.7/RuntimeViewer-macOS.zip`，`release history 6 entries`，`deltas 0`，`status UPDATE → 3.0.0`。

## 建议下一步
1. 无代码待办。若厂商以后发 delta 或改用 `phasedRolloutInterval`，重跑上面的 feed 检查。
