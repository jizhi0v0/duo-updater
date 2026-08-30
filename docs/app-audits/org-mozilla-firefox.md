# Firefox

> 审计 2026-06-04 · **本机严格验证后修复**（5 个真实 bundle 跑 `channel-verify`）。
> 早先"靠版本后缀区分 channel"的结论被实测推翻：beta/esr 安装把后缀剥掉了,曾被误判
> stable（esr 还会被跨 channel 推 stable）。已改用 `application.ini` 的 `RemotingName`。
> 真实 bundle 验证证据见下文「如何复验」。

## 基本信息
- Bundle ID: `org.mozilla.firefox`（Release/Beta/ESR 共享）；Developer Edition =
  `org.mozilla.firefoxdeveloperedition`；Nightly = `org.mozilla.nightly`
- Team ID: `43AQ936H96`
- 已安装版本: `151.0.3`（`CFBundleShortVersionString`）/ build `15126.6.1`（`CFBundleVersion`）
- 自更新机制: **Firefox 自带更新器**（无 Sparkle feed，`SUFeedURL` 不存在）。
  我们 **只检测、不一键** —— 升级交给 app 自身。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|                       | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-----------------------|---------|----------|-----|--------|-------------|
| **stable**            | —       | ✗(auto)  | —   | —      | ✓           |
| **beta**              | —       | —        | —   | —      | ✓           |
| **esr**               | —       | —        | —   | —      | ✓           |
| **dev-edition**       | —       | —        | —   | —      | ✓           |
| **nightly**           | —       | —        | —   | —      | ✓           |

当前生效源（优先链中第一个应答的）: **VendorProbe**
（Firefox 无 Sparkle/MAS；Homebrew cask 是 `auto_updates`，`HomebrewCaskSource`
返回 nil 后落到 VendorProbe）。

## Channel 详情

这是**混合形态**：Release/Beta/ESR 是 Pattern C（同一 bundle id），Dev Edition 与
Nightly 是 Pattern A（各自独立 bundle id）。下表"真实短版本/RemotingName"列均为
2026-06-04 对官方 DMG 实测值。

| Channel | Bundle ID | 真实短版本 | `RemotingName` | detect() | 状态 |
|---------|-----------|-----------|----------------|----------|------|
| stable      | `org.mozilla.firefox`                  | `151.0.3` | `firefox`         | stable | ✓ |
| beta        | `org.mozilla.firefox`（共享）          | `152.0`（无 b7） | `firefox-beta`    | beta   | ✓ |
| esr         | `org.mozilla.firefox`（共享）          | `140.11.0`（无 esr） | `firefox-esr` | esr    | ✓ |
| dev-edition | `org.mozilla.firefoxdeveloperedition`  | `152.0`（无 b7） | `firefox-dev`     | dev    | ✓ |
| nightly     | `org.mozilla.nightly`                  | `153.0a1` | `firefox-nightly` | nightly| ✓ |

**Channel 检测**（`ReleaseChannel.detect`，第 0 级最高优先）：权威信号是
`Contents/Resources/application.ini` 的 `RemotingName`，`AppScanner` 对 `org.mozilla.*`
读取。**关键**：安装包的 `CFBundleShortVersionString` 把 `b`/`esr` 后缀剥掉了
（beta 报 `152.0`、esr 报 `140.11.0`），且 beta/esr 与 stable **共享** `org.mozilla.firefox`、
app 名都叫 "Firefox" —— 所以版本后缀/名字都不可靠,RemotingName 是唯一可靠信号。
Dev Edition 的 `RemotingName=firefox-dev` 归 `.dev`（旧"版本是 bN → 归 .beta"的假设也错了,
它报 `152.0`）。见 `ChannelGuardTests.mozillaRemotingNameIsAuthoritative`。

**多 recipe 路由**：`org.mozilla.firefox` 在 `VendorProbeRecipe` 里挂了 3 条 recipe
（stable/beta/esr），`VendorProbeSource` 按安装实例的 detected channel 选对应那条，
各自从同一份 JSON 抽不同字段。`ChannelGuardTests.firefoxSharedBundleResolvesPerChannel`
（live）断言三者解析出不同版本、且 b/esr 后缀正确。

## 更新检测
- 源: `https://product-details.mozilla.org/1.0/firefox_versions.json`（一份 JSON 含全 channel）
- 字段映射（2026-06-04 实测）:
  | Channel | JSON key | 实测值 | 正则 |
  |---------|----------|-------|------|
  | stable      | `LATEST_FIREFOX_VERSION`                | `151.0.3` | `"LATEST_FIREFOX_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"` |
  | beta        | `LATEST_FIREFOX_RELEASED_DEVEL_VERSION` | `152.0b7` | `…"([0-9]+\.[0-9]+b[0-9]+)"` |
  | esr         | `FIREFOX_ESR`                           | `140.11.0esr` | `…"([0-9]+(?:\.[0-9]+)+esr)"` |
  | dev-edition | `FIREFOX_DEVEDITION`                    | `152.0b7` | `…"([0-9]+\.[0-9]+b[0-9]+)"`（recipe channel `.dev`）|
  | nightly     | `FIREFOX_NIGHTLY`                       | `153.0a1` | `…"([0-9]+\.[0-9]+a[0-9]+)"` |
- 注意事项:
  - **stable 版本方案 ✓ 安全**：endpoint `151.0.3` == 安装 app 短版本，普通 recipe。
  - **feed 带后缀,安装版剥后缀,但仍安全**：probe 抽出的 `152.0b7`/`140.11.0esr` 比
    安装版的 `152.0`/`140.11.0` 多一截 `b`/`esr`,而比较器把预发布串排在正式版**之下**
    （`VersionComparator`：`152.0b7 < 152.0`），所以当前版判"已是最新"、**不会误报**；
    真正升版（`140.11.0esr`→`140.12.0esr`）仍比得出更新。已用 `channel-verify` 实测确认。
  - **beta→beta 周期内不可检测**：安装版整周期恒 `152.0`，只能检测跨大版本。
  - `FIREFOX_ESR_NEXT` 当前为空 —— ESR 切版重叠期会同时存在两条 ESR 轨，目前只跟
    `FIREFOX_ESR`，不影响主流程（次要边角）。

## Changelog
- 来源: **WebView 内嵌官网 release notes**，每条 recipe 自带 `changelogURL`：
  stable `firefox/notes/`、beta `firefox/beta/notes/`、esr `firefox/organizations/notes/`、
  nightly `firefox/nightly/notes/`。
- 跟随 channel: **是**（每 channel 一个 notes 页）。
- Recipe 状态: **不需要**专门的 `ChangelogRecipe`（`ChangelogRecipe.swift` 无 Firefox 条目）。
  官网 notes 页直接 WebView 展示即可。

## 一键安装
- 状态: **已接入**，stable / beta / esr 三条 recipe 都带 `install: VendorInstallSpec`
  （`download.mozilla.org/?product=firefox{,-beta,-esr}-latest` 302 → dmg，Team `43AQ936H96`）。
  此前本节记为「仅检测（设计如此）」，是旧策略的残留。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- ⚠️ **Mozilla 的更新器既不是 Squirrel 也不是 Sparkle**，所以 `SelfUpdaterStaging` 那层
  「它已经下好了就让位」的保护**不覆盖 Firefox**（判据是 `Squirrel.framework` 是否存在）。
  这里唯一的闸就是 `vendorInstallPolicy`。
- `downloadURL` 是"去官网下载"的展示链接，不是安装产物；产物由 `install` 的重定向解析。

## 已修（2026-06-04）
- detect() 加 `RemotingName` 信号（修 beta 漏检 + esr 跨 channel 误推 stable）。
- dev-edition recipe channel `.beta` → `.dev`（实测 `RemotingName=firefox-dev`、版本 `152.0`）。
- 与 Thunderbird 同一根因、同一次修复，见 [`org-mozilla-thunderbird.md`](org-mozilla-thunderbird.md)。

## 已知限制 / 下一步
- beta→beta 周期内不可检测（安装版恒 `152.0`），只跟跨大版本。已接受。
- `FIREFOX_ESR_NEXT` 当前为空；ESR 重叠期双轨低优先级，暂不加。
- **nightly/daily 周期内同样不可检测，而且比 beta 严重**（测于 2026-08-30）。
   Mozilla 的 nightly **每天**出构建，整个周期全叫 `157.0a1`；product-details 报的
   marketing 串与安装版逐字相同，recipe 又不发 build，于是 `UpdateChecker.evaluate()`
   走 marketing 分支、`isNewer("157.0a1","157.0a1")` 恒假 → **整整一个 ~4 周周期一次
   更新都不报**。beta 至少每两天才漏一次，nightly 是天天漏。适用 `org.mozilla.nightly`
   与 `org.mozilla.thunderbird-daily`。
   2026-06-04 那次记录把「远程 == 安装版」记成了 ✓（确实没有幽灵更新），没有往下推出
   「因此新构建永远看不见」这一步。
- **远程侧的 BuildID 来源已找到：Mozilla 自己的 AUS**（`aus5.mozilla.org`，即
   `application.ini` 里 `[AppUpdate] URL` 指的那个）。它直接返回
   `buildID="20260826090609"`，与安装版 `application.ini` 的 `BuildID` **逐字节相同**，
   同时给 `displayVersion="155.0 Beta 5"`。2026-08-30 实测 5 条通道全部作答
   （FF beta / FF aurora=DevEdition / FF nightly / TB beta / TB daily），
   且与 `…-latest` 下载链接给的包一致。
   URL 形状：`/update/6/<Product>/<Version>/<BuildID>/Darwin_aarch64-gcc3/en-US/<channel>/Darwin%2025.0.0/default/default/default/update.xml`
   —— 注意必须凑满 10 段（漏掉 `%SYSTEM_CAPABILITIES%` 会返回空）。
   **未解决的一点**：AUS 的应答取决于**传入的版本号**，传 `100.0` 会返回 watershed 的
   `125.0 Beta 9` 而不是最新；所以锚点不能写死（约两年后静默退化，且 verify 抓不到，
   因为 watershed 的 build id 是往上走的、不构成版本回退）。正确做法是代入**已装版本**，
   而 `resolveEndpoint` 目前拿不到 `InstalledApp` —— 那是共享请求路径的改动，
   另案处理，不在本次范围。
   （已排除的两条路：buildhub 的「频道最新」是已构建未推送的 `156.0b1`，与
   `beta-latest` 实际服务的 `155.0b5` 不一致，用它会造成永久幻影；`firefox.json`
   的 key 是按字符串排序的全量历史，`entryStartPattern` 切片会吞掉文件尾部。）
- **部署**：改的是 core 检测逻辑，菜单栏 App 需 `xcodebuild` 重建才生效。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
# DMG redirector: https://download.mozilla.org/?product=firefox{,-beta,-devedition,-esr,-nightly}-latest-ssl&os=osx&lang=en-US
swift run --package-path application-test channel-verify "/tmp/ff-esr.dmg"  --expect esr
swift run --package-path application-test channel-verify "/tmp/ff-beta.dmg" --expect beta
swift run --package-path application-test channel-verify "/tmp/ff-dev.dmg"  --expect dev
```
