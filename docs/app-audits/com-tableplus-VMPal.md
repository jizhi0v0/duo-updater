# VMPal

> 审计日期 2026-10-06 · 模式 INVESTIGATE → 已接入 · 结论：**单轨 Sparkle，feed 地址写在代码里（`SparkleFeedCatalog` 补上）+ changelog recipe**

## 基本信息
- Bundle ID: `com.tableplus.VMPal`
- Team ID: `3X57WP8E8V`（Developer ID Application: TablePlus Inc，已公证，ticket 订在 `.app` 上，dmg 容器本身没订）
- 观测版本: 0.36（`CFBundleVersion` 36），arm64 单架构，`LSMinimumSystemVersion` 26.0
- 自更新机制: Sparkle 2.10.0（2064）。`Info.plist` 有 `SUPublicEDKey`、`SUAutomaticallyUpdate`、`SUScheduledCheckInterval` 3600，**没有 `SUFeedURL`**

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（`SparkleFeedCatalog`） | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **SparkleAppcastSource**，地址由 `SparkleFeedCatalog` 填入

- Homebrew：`brew search --cask vmpal` 无结果（2026-10-06）
- MAS：`mas search VMPal` 没有这个 app（2026-10-06）
- GitHub：`TablePlus/VMPal-issue-tracker` 只收 issue，不发 release

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.tableplus.VMPal` | — | — | — | ✓ |

只有一条轨：feed 里没有 `<sparkle:channel>`，二进制里没有 beta 相关字符串，同厂 TablePlus 用来切 beta 的请求头 `X-Tiny-Beta-Update: true` 在这里换不出不同的响应（与不带头时字节一致）。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://vmpal.com/apps/version.xml`
- 地址怎么来的：主二进制里 `https://vmpal.com` 和 `apps/version.xml` 是两个相邻的独立字符串（紧挨着 `VMPal/Updates.swift` 和 `VMPal.UpdaterDelegate`），由代码拼起来交给 Sparkle 的 `feedURLStringForUpdater:`。正因为拆成两段，`feed-discover` 对真包给出 `review noCandidate`，需要手工登记。
- 注意事项:
  - feed 的命名空间写法不规范：根元素上是普通属性 `sparkle="…"` 而不是 `xmlns:sparkle`，命名空间只在 `<enclosure>` 自己身上声明。`<enclosure>` 的 `sparkle:version` / `sparkle:shortVersionString` / `sparkle:edSignature` 因此都能读到；但 `<minimumSystemVersion>` 是**裸名**，生产解析器不把它当 Sparkle 的系统下限（`VMPalCoverageTests.unprefixedMinimumSystemVersionIsNotRead` 钉住）。目前它等于 app 自己的 `LSMinimumSystemVersion`（26.0），装得上的机器都满足，所以眼下不漏判；厂商哪天抬高下限而 app 本身不抬，这一层会看不见。
  - 版本方案：`sparkle:shortVersionString` = `CFBundleShortVersionString`（0.36），`sparkle:version` = `CFBundleVersion`（36），两两对得上，无需 `versionIsBuild`。
  - 二进制里有 `feedParametersForUpdater:sendingSystemProfile:`，app 可能带参数请求；不带参数、带 `appVersion=30`、换 UA，三种请求拿到的都是同一份字节。服务端会不会按 app 自己发的参数分流：**未验证**。
  - vmpal.com 对页面的 `HEAD` 回 404，只对 `GET` 正常（`/changelog`、`/release/osx/vmpal_latest` 都是）。拿 `curl -I` 判断页面死活会误判。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 能（现成机制），眼下无可消费 |
| 证据 | 内置 Sparkle 2.10.0 的 `Autoupdate` 含 `BinaryDelta` 字符串 | 2026-10-06 的 feed 里没有 `<sparkle:deltas>` / `deltaFrom` | `VendorAppcastDeltas` + `DeltaApplier` 走 Sparkle 原生格式 |

- 格式: Sparkle binary delta（如果厂商以后发）
- 阻塞项: 无

## Changelog
- 来源: `ChangelogRecipe`，`https://vmpal.com/changelog`
- 跟随 channel: 不适用（单轨）
- Recipe 状态: 已有。页面每个构建一个 `<li class="vp-release">`：`<h2>VMPal 0.36</h2>`、`<time datetime="2026-10-06">`、`<div class="vp-release-body"><ul><li>…`。
- 为什么不用 appcast 内联说明：`<description>` 是 TablePlus feed 同款模板（`<h2>Build 36 - Virtual Machines for Apple Silicon</h2>`、`<h4>Release date…</h4>`、`<ol>`）。生产的 `AppcastHTMLChangelogParser` 把 `<h2>` 当成一条变更，结果每个版本第一条都是「Build 36 - Virtual Machines for Apple Silicon」，日期也是 RFC 822 原文。recipe 在面板里排在内联说明前面，所以不会出现这个问题。
- recipe 抓取失败时（页面取不到或正则不再匹配）：面板先找 `changelogURL`——这个 feed 没有 `releaseNotesLink`，也没登记 `ChangelogCatalog`，所以是 nil——然后退到 feed 的内联 `<description>`（`releaseNotesHTML`），经 `ReleaseNotesText` 按 HTML 渲染，也就是上面那份 TablePlus 模板正文，而不是空态（`WorkbenchWindowView.fallback`）。看到这份模板正文，说明 recipe 失效了。

## 一键安装
- 状态: 支持，走通用 Sparkle 安装路径（dmg + EdDSA 校验 + Team 闸）。**0.35 → 0.36 在真机上跑过两种状态**：app 未运行、以及 app 和一个 VM 都在运行，证据见「如何复验」。后一种有一个已知缺口（VM 进程继续跑旧代码），见「已知问题」
- 格式: dmg（`files.vmpal.com/macos/<version>/VMPal.dmg`，0.36 为 42262248 字节，与 feed 的 `length` 一致）
- **读的是**: 人人可手动下载的 GA。官网下载按钮 `/release/osx/vmpal_latest` 302 到同一个 dmg，feed 只有一条 item，没有设备分桶或灰度参数
- 阻塞: 无

## 已知问题
- **许可证的更新期**：二进制里有 "Your license's updates have ended" / "A newer VMPal is out. Renew your license to get it."，app 自己会拦住超出许可证更新期的版本。duo 一键不知道许可证状态，会照装 feed 上的最新版。装上之后 app 的反应（拒绝启动、降级成试用，还是只提示续费）**未验证**。TablePlus 用的是同一种许可证模式。
- feed 的 `<minimumSystemVersion>` 读不到（见「更新检测」）。
- **VM 进程在升级后继续跑旧版引擎。** 每个运行中的 VM 是一个独立进程，可执行文件在包内 `Contents/Helpers/VMPalMachine.app`。VMPal 主程序退出时它不退出；重启主程序后，0.36 会接管这个仍在运行的进程，在 UI 里停掉再启动 VM 时**复用的也是它**。所以 duo 换包 + `duo restart` 之后，VM 一直跑在 0.35 的引擎上（可执行文件指向已被删掉的旧包），要等这个进程退出（它不会自己退，见下一条），再启动 VM 才会换成 0.36。duo 判断「app 是否在运行」，是拿每个进程的 `bundleURL`（经 `UpdatePolicy.runtimeBundlePath` 归一化）去和 app 路径精确比对（CLI 的 `Check.runningBundlePaths`，菜单栏 app 的 `RunningBundlePathCache`）。helper 的 `bundleURL` 是 `…/Contents/Helpers/VMPalMachine.app`，对不上，所以主程序一退，duo 就当它已经不在运行。实测这种混合版本状态下暂停、恢复、停止都正常；旧包已删除时，helper 按需再加载包内资源会怎样，**未验证**。厂商自己的更新流程会先暂停、保存并关闭所有 VM 再装（"Pause VMs and Update"），正是为了避开这种状态。
  - 补充实测（2026-10-06）：在 VMPal 里 Stop 掉 VM 后，VMPalMachine 进程仍然留着；VMPal 主程序退出、没有任何 VM 在跑时也不退。对它调 `NSRunningApplication.terminate()`，它在 0.4 秒内退出，正在跑的 VM 随之停止，也没有保存状态。用户能走的路是从 Dock 退出这台 VM 自己的图标（每台 VM 一个 `VM.app` 代理，`--for <VMPalMachine pid>`），helper 1 秒内跟着退出。
  - 换包前识别这类进程并拒绝换包，另提为 [jizhi0v0/duo-updater#1004](https://github.com/jizhi0v0/duo-updater/pull/1004)。合并后，VM 在跑时 `duo install VMPal` 会返回 `skipped`，提示「VMPalMachine is running from inside VMPal…」。

## 建议下一步
1. 换包前识别比主程序活得久的嵌套 app 并拒绝换包：见 [jizhi0v0/duo-updater#1004](https://github.com/jizhi0v0/duo-updater/pull/1004)（已在真机上验证：VM 在跑时 `skipped`、包不动；从 Dock 退出 VM 后安装成功）。
2. 菜单栏 app 的一键 + Relaunch 路径没在 VM 运行时单独跑过；按代码它和 CLI 用的是同一套运行检测，结论应该相同（未验证）。
3. 许可证更新期到期后的行为，有过期许可证时再验。

## 如何复验

```bash
# feed：一条 item、无 channel、有 edSignature
curl -sS https://vmpal.com/apps/version.xml
# 真包身份
curl -sSLO https://files.vmpal.com/macos/0.36/VMPal.dmg
hdiutil attach -nobrowse -readonly VMPal.dmg
plutil -p /Volumes/VMPal/VMPal.app/Contents/Info.plist | grep -E 'Identifier|Version|SU|LSMinimum'
codesign -dvvv /Volumes/VMPal/VMPal.app 2>&1 | grep TeamIdentifier
spctl -a -vv -t exec /Volumes/VMPal/VMPal.app
# 生产解析器
swift test --package-path DuoUpdaterCore --filter VMPal
```

一键（旧版 → 新版）：

```bash
curl -sSLO https://files.vmpal.com/macos/0.35/VMPal.dmg   # 旧 dmg 仍可下载
# 挂载后 ditto VMPal.app 到 /Applications，不启动（避免它自己的 Sparkle 抢先更新）
duo check VMPal                    # VMPal  0.35  →  0.36  [Sparkle, in-place]
duo install VMPal --yes --json
```

2026-10-06 的一键结果：`{"applied":true,"bytesDownloaded":42262248,"outcome":"installed","route":"sparkle"}`，退出码 0，耗时约 12 秒。换装后 short 0.36 / build 36、inode 变了、`codesign --verify --deep --strict` 退 0、Team 仍为 `3X57WP8E8V`、`spctl` accepted / Notarized Developer ID；包内 173 项（文件 SHA-256 + 符号链接目标）与厂商 0.36 dmg 里的 `.app` 逐项一致；`duo backups` 里留有 0.35 的回滚点；之后 `duo check` 判为最新；启动 0.36 能正常运行、无 fault 日志，`quit` 后干净退出。

运行中的一键（VMPal 主程序 + 一个 VM 都在运行，VM 停在 Fedora 安装器菜单）：

```bash
duo install VMPal --yes --json     # 换包，不退出 app
duo restart VMPal                  # 优雅退出 + 重启主程序
lsof -p <VMPalMachine pid> | awk '$4=="txt"'   # VM 进程的可执行文件
```

2026-10-06 的结果：`duo install` 约 8 秒完成（`installed` / `applied`），期间主程序和 VM 进程都没被动；`duo restart` 约 2 秒，主程序换成 0.36 的新进程。VM 进程没有变，`lsof` 显示它的可执行文件是 `/Applications/.duoupdater-staged-VMPal.app/…/VMPalMachine`，那份旧包随后从磁盘上消失。0.36 的界面对这个 VM 执行暂停、恢复、停止都正常；停掉后再启动，仍是同一个旧进程。用 AppleEvent 让该进程退出后再启动 VM，新进程的可执行文件 inode 与 0.36 包内的 `VMPalMachine` 一致。整个过程中 VMPal 自己的 Sparkle 没有暂存任何更新。

2026-10-06 的身份与解析结果：`com.tableplus.VMPal`、short 0.36 / build 36、`LSMinimumSystemVersion` 26.0、无 `SUFeedURL`、Team `3X57WP8E8V`、`spctl` "accepted / Notarized Developer ID"、arm64；生产 `SparkleAppcastParser` 解析出 1 条 item（0.36/36，enclosure 为上面的 dmg，`edSignature` 非空，`channel` nil，`minimumSystemVersion` nil）；recipe 在真实页面上取到 1 条（0.36 · 2026-10-06 · "Bug fixes and improvements."）。

## 历史与实测

- 2026-10-06：首次接入。0.36 是当天发布的（feed `pubDate` 03:52:59 UTC），changelog 页和 feed 都只有这一个版本。
- 2026-10-06：一键 0.35 → 0.36 真机跑通（app 未运行），结果见「如何复验」。
- 2026-10-06：一键 0.35 → 0.36 在 app 与 VM 都在运行时跑通，发现 VM 进程升级后继续跑旧引擎，结果见「如何复验」与「已知问题」。旁注：VMPal 用 Fedora 44 netinst 自动安装时，VM 里的安装器报 "Error setting up repositories" 并停在交互菜单；同一时刻宿主经系统代理能取到 Fedora 的 metalink（200），VM 走 NAT 不经该代理，原因未查。
- 2026-10-06：对 recipe 做变异：去掉日期组的 `(?!</li>)` 后，没有 `<time>` 的条目会一直吞到下一个 release，拿走对方的日期和条目，`extractsVMPalEntriesInOrder` 变红；恢复后变绿。
