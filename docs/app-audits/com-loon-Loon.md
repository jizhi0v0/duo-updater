# Loon

## 基本信息
- App: Loon for Mac — 代理 / 网络工具（Loon iOS 的 Mac 版），闭源；GitHub 仓库 `Loon0x00/Loon4Mac` 只放 `appcast.xml`、README 和 release
- Bundle ID: `com.loon.Loon`
- Team ID: `ASX2695DJ4`（Developer ID「Loon Lab Limited」+ 公证）
- 观测版本: 0.1 (42)、0.4.0 (991)、0.5.0 (1009)；观测日期: 2026-10-21
- 自更新机制: Sparkle 2.8.1（EdDSA `SUPublicEDKey`；Info.plist 没有 `SUEnableAutomaticChecks` / `SUAutomaticallyUpdate`）
- 分发: GitHub Releases（dmg）；没有 Homebrew cask，没有 MAS
- 架构 / 系统: universal（x86_64 + arm64），`LSMinimumSystemVersion` = 13.0

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | —        | —   | —      | —           |

当前生效源: **Sparkle**（bundle 自带 `SUFeedURL`，`feed-discover` 判定 `declared`，不需要 recipe）

## Channel 详情

只有一条轨。appcast 的 item 没有 `<sparkle:channel>`；item 标题写「alpha」、dmg 文件名写「beta」，但那是整个产品的阶段，
不是另一条轨：12 个 GitHub release 全部非 prerelease，appcast 只有一份。

覆盖清单：
- **bundle id**: 还能下载的最早 release 0.1 (42)，以及 0.4.0 (991)、0.5.0 (1009) 都是 `com.loon.Loon`，没有改名
- **版本区间**: 0.1 (42) 已带同一个 `SUFeedURL`、同一个 `SUPublicEDKey`、同一个 Team `ASX2695DJ4`，所以 42 – 1009 都能检测，Team 闸也不会拦
- **更早的构建（未验）**: appcast 还列着 0.1 的 17、18、23–29、32、34、39–41 和 0.2.0 (52)，但它们的 GitHub release 已删，
  enclosure 地址 404（2026-10-21 查 17、41、52），拿不到包核对。厂商仓库里 `appcast.xml` 在 build 17 之前就以同一路径创建，
  所以这些副本很可能声明同一个 feed；若不是，结果是检测失败或一键被闸拒绝，不会给错版本
- **发布轨**: 只有 stable

## 更新检测
- 源: Sparkle，`https://raw.githubusercontent.com/Loon0x00/Loon4Mac/refs/heads/main/appcast.xml`
- 版本: `sparkle:version` = 构建号（1009），`sparkle:shortVersionString` = `0.5.0(1009)`；app 自己的 `CFBundleShortVersionString` = `0.5.0`、`CFBundleVersion` = `1009`
- 实测（2026-10-21，channel-verify，真包 0.5.0 dmg）: `winning source Sparkle`，`latest 0.5.0(1009)`，`status up to date`，`release history 27 entries`
- `duo check`（0.4.0 (991) 副本）: `Loon  0.4.0  →  0.5.0(1009)  [Sparkle, in-place]`

## 按架构 / 按 OS 分轨
- universal 单包；appcast 的 item 没有 `minimumSystemVersion` / `maximumSystemVersion`，下限只在包里（13.0）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2.8.1） | 无 | — |
| 证据 | Sparkle.framework | appcast（2026-10-21）没有 `<sparkle:deltas>`；channel-verify `deltas 0` | 若以后发，`VendorAppcastDeltas` / `DeltaApplier` 现成 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 默认不会 | 无 | — |
| 证据 | Info.plist 没有 `SUAutomaticallyUpdate`，Sparkle 只弹提示 | 第二轮启动 0.4.0 (991) 后，`~/Library/Caches` / `Application Support` / `Containers` 没有新的 >8 MB 文件（app 停在激活向导上） | — |

## Changelog
- 来源: Sparkle inline（每个 item 的 `<description>` 是 `<ul><li>` 列表，另有 `sparkle:releaseNotesLink` 指向 `https://nsloon.app/Loon4Mac/changelog.html#build-<build>`）
- 结构化（2026-10-21，channel-verify，真包 0.5.0）:
  `changelog pane  source structured: 27 entries; newest 0.5.0(1009): 6 items, headings []`
  ——源文本本身没有分节，`headings []` 不是被压平
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（不运行、运行中两轮真机通过；系统扩展 / helper 的升级只有静态分析，见下）
- 端到端（2026-10-21，真包 0.4.0 (991) → 0.5.0 (1009)，Loon 全程未启动）:
  - `ditto` 0.4.0 (991) 进 `/Applications`；`duo install /Applications/Loon.app --yes --json` →
    `outcome: installed`，`route: sparkle`，`bytesDownloaded: 61875853`（= appcast 的 `length`），9.4 s
  - 之后为 0.5.0 (1009)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，
    Team `ASX2695DJ4`；与厂商 0.5.0 包的 CDHash 相同，全树（文件 sha256 + 符号链接目标）一致；`duo backups` 无 Loon 的备份；
    再跑 `duo check` → `Everything is up to date.`
  - 第二轮（运行中，2026-10-21，另一台 macOS 26.7 的 Mac）：装 0.4.0 (991) 并启动。首启是三步向导
    （激活码 → Helper Tool → System Extension），激活码只能在 Loon iOS app 里生成，所以停在第一步，扩展和 helper 都没装上。
    `duo install --yes --json` → `installed`，`route: sparkle`，13.6 s；盘上 1009，CDHash 同厂商包，10 s 内没被改回。
    `duo restart Loon` → `restarted`，新进程的主二进制 inode 就是新包那份
  - **未验：** 已激活、扩展和 helper 都在跑的副本上换包并重启。没有激活码，做不了。下面是静态分析的结论
- 格式: dmg（根目录 `Loon.app` + `Applications` 链接），EdDSA 签名（`sparkle:edSignature`），Sparkle 路线
- 校验: appcast 的 `sparkle:edSignature` + `length`；Team ID 闸
- **读的是**: 人人可手动下载的 GA（GitHub release 的 dmg）
- 嵌套:
  - `Contents/Library/SystemExtensions/com.loon.Loon.LoonTunnelExtension.systemextension`（网络扩展）
  - `Contents/Library/LaunchServices/com.loon.Loon.LoonHelper`（`SMPrivilegedExecutables`，SMJobBless 特权 helper）
  - `Contents/Dashboard/Loon Dashboard.app`（`com.loon.Loon-Dashboard`，普通 app）
  - 两个版本的对比（0.4.0 (991) / 0.5.0 (1009)）：helper 内嵌 `CFBundleVersion` 1.0.55 / 1.0.57，launchd plist `KeepAlive` + `RunAtLoad`；
    扩展 `CFBundleVersion` 991 / 1009，`NEMachServiceName` 是 `group.com.loon.mac.xpc.<构建号>`，也就是 app 只和同构建号的扩展通信
  - 主二进制里的日志串（`strings`，0.5.0）说明升级由 app 自己在启动时做，不靠更新器：
    - helper：`[HelperLifecycle][App][GuidePrepare] Installed helper version=%@ bundledVersion=%@`、
      `Update not required version=%@`、`Bless start bundledVersion=%@`、`Update verified runningVersion=%@`，即比较内嵌和已装的版本，新了就重新 bless
    - 扩展：`[Startup][SystemExtension] Silent update request submitted`、`VPN disconnect requested`，以及
      `[SystemExtensionCoordinator] Replacement requested existing=%@(%@) new=%@(%@) action=replace`，即启动时先断开 VPN、再提交替换请求
  - 所以 `duo restart` 之后走的是同一条启动路径，和 Loon 自己的 Sparkle 更新装完后重开一样；换包本身只替换 bundle。
    替换扩展时 macOS 会不会再要用户批准，由系统决定，两种更新方式都一样；Apple 论坛里两种情况都有报告（未验）
  - 还没排除的一点：主二进制里有 `SPUUpdaterDelegate` 的 `updater:willInstallUpdate:`、`updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:`、
    `updaterWillRelaunchApplication:` 等选择子名。`strings` 分不出这是 Loon 实现了这些回调，还是只带着协议元数据；
    若 Loon 在 Sparkle 装包前后另做了扩展 / helper 的准备，duo 换包时不会经过那一步（未验）
- 阻塞: 无（运行中一轮待验）

## 已知问题
- 已激活副本上换包、`duo restart` 后系统扩展 / 特权 helper 的升级行为未在真机验证（需要 iOS app 生成的激活码）
- 换包后不重启时，旧进程继续和旧扩展通信（mach 服务名带旧构建号），直到下次启动才替换

## 建议下一步
1. 有激活码时补一轮：装 0.4.0 (991)、激活并完成 helper / 扩展授权，`duo install` + `duo restart Loon`，
   看 `systemextensionsctl list` 里 `com.loon.Loon.LoonTunnelExtension` 是否升到 1009、helper 是否换成 1.0.57

## 如何复验

```sh
gh release download '0.4.0(991)' -R Loon0x00/Loon4Mac
swift run --package-path application-test feed-discover Loon-0.4.0-beta-991.dmg
swift run --package-path application-test channel-verify Loon-0.4.0-beta-991.dmg
```
