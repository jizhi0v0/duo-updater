# Mac Mouse Fix

> 审计日期 2026-09-12 · 模式 INVESTIGATE→接入 · 结论：**stable/beta 两 channel，ChannelBinding，Sparkle feed-swap；无 ChangelogRecipe（两条 feed 都用 `<sparkle:releaseNotesLink>`，已被 #553 覆盖）**

## 基本信息
- Bundle ID: `com.nuebling.mac-mouse-fix`（两 channel **共用**）
- Team ID: `LM5Z78756B`
- 观测版本: stable `3.0.8`（`CFBundleVersion` 24310）；preview 轨最新 `3.1.0 Beta 1`（`CFBundleVersion` 24830）
- 自更新机制: Sparkle。开源仓库 `noah-nuebling/mac-mouse-fix`，`update-feed` 分支下的 `generate_releases.py` 生成两份 appcast。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(feed-swap) | — | — | — | — |
| **beta**     | ✓(feed-swap) | — | — | — | — |

当前生效源: **SparkleAppcastSource**（`ChannelBinding` → `MacMouseFixChannel` 提供 `feedOverride`；应用自带 `SUFeedURL` 始终指向 stable feed，preview 是应用自己在运行时用 `SUUpdater.sharedUpdater.feedURL = …` 换掉的，plist 里看不出来）。

## Channel 详情（Pattern B — 共享 bundle id，偏好切换 feed）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.nuebling.mac-mouse-fix` | 共享 | `General.checkForPrereleases = false`（或文件/键缺失）| feed-swap → `…/update-feed/appcast.xml` | ✓ |
| beta    | `com.nuebling.mac-mouse-fix` | 共享 | `General.checkForPrereleases = true` | feed-swap → `…/update-feed/appcast-pre.xml` | ✓ |

两条 feed 的完整地址：
- stable: `https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed/appcast.xml`
- preview: `https://raw.githubusercontent.com/noah-nuebling/mac-mouse-fix/update-feed/appcast-pre.xml`

（`kMFUpdateFeedRepoAddressRaw` + `kSUFeedURLSub`/`kSUFeedURLSubBeta`，`Shared/Constants.h`；实际换 feed 的调用点是 `App/Update/SparkleUpdaterController.m` 的 `+enablePrereleaseChannel:`。）

`General.checkForPrereleases` **不在** UserDefaults/CFPreferences 里——Mac Mouse Fix 自己管一份配置文件：`~/Library/Application Support/com.nuebling.mac-mouse-fix/config.plist`，顶层 dict 的 `"General"` 键下再是一个 dict，`"checkForPrereleases"` 是其中一个 Bool（对照应用自带的 `Contents/Resources/default_config.plist` 确认了这个嵌套形状，默认值 `false`）。`MacMouseFixChannel.readCheckForPrereleases()` 直接读这份文件；文件或键缺失时回落到 stable。

### `generate_releases.py` 对两条轨道的定义（读自 `update-feed` 分支的源码，非推测）

- `is_prerelease = r['prerelease']` 直接取自 GitHub Releases API 的 `prerelease` 标志位。
- stable feed（`appcast_items`）只收 `not is_prerelease` 的条目；preview feed（`appcast_pre_items`）收**全部**条目，prerelease 和正式版都在——所以 preview 是 stable 的超集,不是并列的独立轨道,且脚本没有重新排序，两条 feed 都保留 GitHub Releases API 本身的时间倒序（最新在前)。
- `sparkle:shortVersionString` 写的是 `r['name']`——GitHub Release 的显示名原文，例如验证到的最新 preview 条目 `"3.1.0 Beta 1"`（空格、大写 B）；`sparkle:version` 写的是从**真实下载并解压后的 bundle** 里读出的 `CFBundleVersion`。下载该资产（build 24830，观测于 2026-09-12）确认这两个字段和装机后的 bundle 完全一致：其 `CFBundleShortVersionString` 就是字面的 `"3.1.0 Beta 1"`，`CFBundleVersion` 就是 `24830`——不存在 Mozilla 那种「feed 与 bundle 不一致」的坑，`RemoteVersion.marketingMatchesBundle: true` 是对的。
- 下载到的 preview 包签名 `Developer ID Application: Noah Nuebling (LM5Z78756B)`，与已装 stable 副本一致——一键安装不会跨 Team ID。

### 版本比较：真实跑过 `"3.1.0 Beta 1"`，不是假设

- `VersionComparator.comparableMarketingVersion` 拒绝任何带空白的字符串，`"3.1.0 Beta 1"` 因此落在这条规则外；`isMarketingDowngrade` 对这类字符串只会答"看不出来"（即"不是降级"）——这正是安全的方向,因为调用方只用这个判断来**拦截**报价,从不用来**发起**报价。
- `UpdateChecker.evaluate` 优先走 build 号分支：两侧都带 `sparkle:version` 时，`24830` 对已装 `24310` 用 `VersionComparator.isNewer` 判定为更新，上面的降级保护不会推翻这个结论——于是 beta 会被正确报价。这不是这一对版本号运气好：Mac Mouse Fix **自己的** Sparkle 代理（`App/Update/CoolSUComparator.m`）解决同一个歧义用的是同一个思路——先把版本串砍到只剩开头的数字和点号再比较（所以 `"3.1.0"` 和 `"3.1.0 Beta 1"` 比较结果是相等），相等时再用 build 号断胜负。两处独立实现都依赖同一个事实：这里的 `CFBundleVersion` 是真实的、单调递增的 build 号。

## Changelog
- 无 ChangelogRecipe。两条 feed 都用 `<sparkle:releaseNotesLink>`（按语言给一条链接），这个形状已经被 #553 处理，不需要新东西。
- Recipe 状态: 不需要

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 没查 | 没查 |
| 证据 | — | — | — |

（超出本次 issue 范围，未投入时间验证；两条 feed 的条目里都没看到 `sparkle:deltaFrom`。）

## 一键安装
- 状态: 仅检测（本次未接一键；两轨都可以走通用 Sparkle 安装路径，未验证是否需要额外处理）
- 格式: `.zip`（`MacMouseFixApp.zip`）
- 读的是: 人人可手动下载的 GA —— stable 和 preview 都是 GitHub Releases 上公开挂出的资产，与厂商自己 Sparkle 更新器分发的是同一份文件，不存在"轨道最新但未分配"的问题
- 阻塞: 无已知阻塞，只是本次未做

## 已知问题
- 无

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `AppScanner` → `ChannelBinding` → `SparkleAppcastSource`（不是重实现）。原始验证 2026-09-12。

stable 端到端（真实网络请求，命中当时线上的 stable feed）：

```
swift run --package-path application-test channel-verify --check com.nuebling.mac-mouse-fix --expect stable
```

结果：`detected channel → stable`，`winning source → Sparkle`，`latest → 3.0.8`，`status → up to date`——与观测版本一致。

beta 侧**未在真机上翻转** `General.checkForPrereleases`（该文件在审计时不存在，需要新建才能翻转，而不是像 Surge/Fork 那样逐字节备份/还原一份已存在的文件，风险不对称，故未做）。beta 的证据链是：
1. `MacMouseFixChannel.resolve(checkForPrereleases: true)` 的映射关系由单元测试直接钉住;
2. `MacMouseFixChannel.checkForPrereleases(fromConfig:)` 的嵌套 key 解析由单元测试针对"拍平成顶层 key"这个具体的失效模式做了变异验证（人工引入该变异，两条相关用例按预期变红）；
3. preview feed 最新条目对应的真实资产已下载解压，`Contents/Info.plist` 逐字段核对过（见上文）。
