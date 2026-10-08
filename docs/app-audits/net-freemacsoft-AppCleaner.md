# AppCleaner

审计 2026-10-08（重审；2026-06-04 那版只核对了 bundle 身份（Team、版本、`SUFeedURL`），没在新旧两个包上跑生产检测，
没查渠道，也没跑一键）。

## 基本信息
- Bundle ID: `net.freemacsoft.AppCleaner`
- Team ID: `X85ZX835W9` — Developer ID Application: Julien Ramseier（3.6.8 与 3.7 两个真包相同，均 `Notarized Developer ID`）
- 观测版本: `3.7.0`（`CFBundleVersion` 4485）、上一版 `3.6.8`（4332）。universal（`x86_64 arm64`）
- **系统下限跳了一大步**: 3.7 的 `LSMinimumSystemVersion` 是 **15.6**（feed 条目同为 15.6），3.6.8 是 10.14
- 自更新机制: Sparkle（3.7 带 Sparkle 2.10.0，3.6.8 带 2.4.2）；Info.plist 同时有 `SUPublicEDKey` 和 `SUPublicDSAKeyFile`
- Homebrew: cask `appcleaner`，`auto_updates: true`，`depends_on macos >= 15`；URL 是 `freemacsoft.net/downloads/AppCleaner_3.7.zip`
  （与 feed enclosure 不同地址，`content-length` 同为 4,148,798）
- 不开源。`github.com/freemacsoft/appcleaner` 只放发布用的 zip（仓库根下一个 `AppCleaner_3.6.8.zip`，release `3.7` 一个资产）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —（`auto_updates`，让位） | — | —（release 只是 enclosure 的托管处） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`SparkleAppcastSource`）。Changelog 走 `ChangelogRecipe`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.freemacsoft.AppCleaner` | — | — | 单一 Sparkle feed | ✓ |

**有没有 beta（实测，结论是「没找到」，不等于「确定没有」）：**

- feed 4 条，`<sparkle:channel>` 0 条。
- 主程序、`achelper`、`AppCleaner SmartDelete` 三个可执行文件的字符串里，没有 `allowedChannels`、`feedURLString`、
  `beta`/`prerelease`/`channel`、也没有第二个 feed 地址。唯一沾边的是版本比较用的格式串 `%@[0-9BETAbeta.-]*`。
- 资源里的 `.strings`/`.plist` 没有 beta / pre-release / channel 文案。
- 不开源，没有源码可读。所以写成：**没找到 beta 轨或开关**；若厂商以后在 feed 里发带标签的条目，duo 的
  `SparkleAppcastSource` 对 stable 拷贝不会推（按已装 build 匹配到的条目定渠道）。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover`：`declared  https://freemacsoft.net/appcleaner/updates.xml`）
- 端点: `https://freemacsoft.net/appcleaner/updates.xml`
- feed 形状（2026-10-08）: 4 条，**旧的在前**（3.4 → 3.6 → 3.6.8 → 3.7），选版不依赖文档顺序（实测 3.6.8 → UPDATE 3.7.0）。
  每条只有 `minimumSystemVersion`（10.10 / 10.13 / 10.14 / 15.6）和 `releaseNotesLink`（四条都指向同一张
  `releasenotes.html`），没有 `<description>`、`maximumSystemVersion`、`hardwareRequirements`、`phasedRolloutInterval`、
  deltas。3.4 与 3.6 只有 `dsaSignature`，3.6.8 与 3.7 两种签名都有。
  enclosure 托管四处不一：3.4/3.6 在 `freemacsoft.net/downloads/`，3.6.8 在 `rawcdn.githack.com`（GitHub 仓库文件的 CDN），
  3.7 在 GitHub release `freemacsoft/appcleaner` `3.7`
- 版本方案: `sparkle:version` = `CFBundleVersion`（4485），`shortVersionString` = `3.7.0`，与包一致
- **发布日期（修复前读不出来，实测）**: 3.7 的 `pubDate` 写成 `Tue, 22 Sept 2026 12:00:00 +0200`（四字母 `Sept`）。
  用临时测试直接问 `ReleaseDate.publishedFields`：`Sept` 的两条（3.4、3.7）`publishedAt=nil vendorDay=nil`，
  写全称月份的 `2 February 2021`、`5 July 2023` 能读。所以 `release history 2 entries`，**最新版 3.7 在 Release Log
  里没有日期**。属于通用日期解析的缺口，不是 AppCleaner 专属。已修：`ReleaseDate` 在所有 RFC822 格式都拒绝时，把整词 `Sept` 换成
  `Sep` 再试一次（84 个 appcast、1,549 条带日期的条目里只有 AppCleaner 3.7 / 3.4 与 MacWhisper 9.15 / 9.13 这 4 条变化）
- 系统下限: 3.7 只给 macOS ≥ 15.6。15.6 以下的 3.6.8 拷贝，`SparkleAppcastSource` 按下限过滤掉 3.7，
  行上应显示厂商拒绝了这个 macOS（**推断**，没在旧系统上跑）

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不适用 |
| 证据 | 3.7 的 `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta` 等串（Sparkle 2.10.0） | 2026-10-08 feed 4 条都没有 `<sparkle:deltas>` | `channel-verify`：`deltas 0` |

- 格式: —
- 阻塞项: 无（包只有约 4 MB，整包下载即可）

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval` | 否 | 不需要 |
| 按架构 / 按 OS 分轨 | — | 按 OS：每条有 `minimumSystemVersion`，3.7 跳到 15.6；无上限；无架构分轨（universal） | `SparkleAppcastSource` 读下限 |
| 自更新器会不会和我们抢 | 会（Sparkle 默认检查） | 是：同一个 feed | 端到端第二轮未跑 |

## Changelog
- 来源: `ChangelogRecipe`（`Recipes/net-freemacsoft-AppCleaner.swift`，解 `https://freemacsoft.net/appcleaner/releasenotes.html`）
- 结构化: `changelog pane  recipe changelog:net.freemacsoft.AppCleaner:-: 21 entries; newest 3.7: 6 items, headings []; first items ["Added support for macOS 27 (Golden Gate)", "Added a setting to choose the default vi", "AppCleaner now prompts for Full Disk Acc"]`
  （3.6.8、3.7 两个包相同）
- 判断: 页面每版一个 `<h2>` + 一个 `<ul>`，没有分节，`headings []` 是本来就没有，不是压平
- 跟随 channel: 否（只有一条轨）
- Recipe 状态: 已有，2026-10-08 在 live 页面上解出 21 条

## 一键安装
- 状态: 需要验证（通用 Sparkle 路径，整包 zip）
- 端到端: 未跑（原因与 app 本身无关）
- 格式: zip（`AppCleaner_3.7.zip` 4,148,798 B、`AppCleaner_3.6.8.zip` 4,165,467 B，均与 feed `length` 相等，`unzip -t` 无错）
- 校验: feed 没有 SHA 摘要，有 `edSignature`。GitHub release 资产 `AppCleaner_3.7.zip` 带 `digest`
  `sha256:3d7fa614…9e65e`，与下载的 SHA-256 **相同**（但 duo 走的是 Sparkle 源，不读 GitHub digest）。
  3.6.8 下载 SHA-256 `e012f729…d6be`
- **读的是**: 人人可手动下载的 GA（静态 feed，无灰度；同一个包也在官网和 Homebrew）
- Team: 上一版、最新版同为 `X85ZX835W9`
- 嵌套: `Contents/Library/LoginItems/AppCleaner SmartDelete.app`（`net.freemacsoft.AppCleaner-SmartDelete`，`LSUIElement`），
  两个版本都有；另有 Sparkle 的 `Updater.app` 与两个 XPC。主程序字符串里有 `SmartDelete registration failed`、
  `Could not re-enable SmartDelete after upgrade: %@`、`openSystemSettingsLoginItems`，即 SmartDelete 是用
  `SMAppService` 注册的登录项，升级后由主程序重新注册（**推断**，来自字符串）。`Contents/MacOS/achelper` 是包内
  第二个可执行文件，字符串里只有旧版特权 helper 的路径（`/Library/PrivilegedHelperTools/com.freemacsoft.appcleanerd` 等）
- 常驻 helper 的影响: SmartDelete 开着时一直在跑。`NestedAppGuard` 有意**不**拦登录项（它的文档里就以 AppCleaner
  SmartDelete 为例），换包后它继续跑旧代码，直到下次登录或主程序重新注册。SmartDelete 的作用是在 app 被拖进废纸篓时
  提示清理（**推断**，来自产品说明，没读代码），跑旧版本的后果有限，不阻止一键
- 阻塞: 无已知

## 已知问题
- 3.7 要求 macOS 15.6，旧系统上的拷贝停在 3.6.8
- 一键端到端两轮都未跑；SmartDelete 换包后是否被重新注册未验证

## 建议下一步
1. 一键端到端（协调会话）：3.6.8 → 3.7。第一轮之后看 SmartDelete 进程跑的是哪个版本。
2. （已做）通用日期解析认 `Sept`（见「更新检测」）。
   单独开任务。
3. 渠道：不需要动作；不开源，没找到 beta 开关或轨。

## 如何复验

2026-10-08，包从 feed 的 enclosure 直接下载，长度与 feed `length` 相等，`unzip -t` 无错，`ditto -x -k` 解包，不安装、不启动。

```bash
curl -sS -o feed.xml https://freemacsoft.net/appcleaner/updates.xml
grep -c "<item" feed.xml                      # 4
grep -c "<sparkle:channel" feed.xml           # 0
curl -fL -C - -O https://github.com/freemacsoft/appcleaner/releases/download/3.7/AppCleaner_3.7.zip
curl -fL -C - -O https://rawcdn.githack.com/freemacsoft/appcleaner/8c3b52858a454d14fba343cf565ff710eaff4bcd/AppCleaner_3.6.8.zip
ditto -x -k AppCleaner_3.7.zip new/        # prev/ 同理
swift run --package-path application-test feed-discover new/AppCleaner.app
swift run --package-path application-test channel-verify new/AppCleaner.app   # prev/ 同理
gh api repos/freemacsoft/appcleaner/releases -q '.[] | .assets[] | .name + " " + .digest'
```

| 包 | bundle id | short / build | Team | `LSMinimumSystemVersion` | detected | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 3.6.8 | `net.freemacsoft.AppCleaner` | 3.6.8 / 4332 | X85ZX835W9 | 10.14 | stable | **UPDATE → 3.7.0** | recipe: 21 entries; newest 3.7: 6 items, headings [] |
| 3.7 | 同上 | 3.7.0 / 4485 | X85ZX835W9 | 15.6 | stable | **up to date** | 同上 |

两个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`、来源 `Notarized Developer ID`，`lipo -archs` 为 `x86_64 arm64`。
`channel-verify` 两个包都是 `winning source  Sparkle`、`deltas 0`、`release history 2 entries`、
`release notes 0 chars inline, changelogURL https://freemacsoft.net/appcleaner/releasenotes.html`。

日期解析用的是一个跑完即删的临时 Swift Testing 用例，直接调用 `ReleaseDate.publishedFields(from:)`：

```
Wed, 21 Sept 2016 15:00:00 +0200 -> publishedAt=nil vendorDay=nil   （修复前）
Tue, 2 February 2021 13:30:00 +0200 -> publishedAt=Optional(2021-02-02 11:30:00 +0000) vendorDay=nil
Wed, 5 July 2023 14:00:00 +0200 -> publishedAt=Optional(2023-07-05 12:00:00 +0000) vendorDay=nil
Tue, 22 Sept 2026 12:00:00 +0200 -> publishedAt=nil vendorDay=nil   （修复前）
```
