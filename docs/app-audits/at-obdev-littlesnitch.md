# Little Snitch

## 基本信息
- Bundle ID: `at.obdev.littlesnitch`
- Team ID: `MLZF7K7B5R`
- 已验证版本: Stable short/build `6.4.1` / `7212`；Nightly short/build `6.5 nightly (7301)` / `7301`
  （两者均从 obdev 官方 dmg 挂载后直接读 `Info.plist` 得到，2026-08-29；未对安装副本取证，未装机验证）
- 自更新机制: 厂商自研（`Little Snitch Software Update.app`，非 Sparkle）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | —      | ✓           |
| **nightly**  | —       | ✗        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。

- Homebrew cask `little-snitch` 是 `auto_updates: true`（`brew info --cask little-snitch`），按
  `HomebrewCaskSource` 的既有逻辑（`guard !entry.autoUpdates else { return nil }`）被跳过；
  `little-snitch@nightly` 同样 `auto_updates: true`。这正是本次审计的起点：两个 cask 都存在，
  但两个都不能作为检测源。
- 两个真实挂载的 `.app`（stable dmg、nightly dmg）都没有 `SUFeedURL` — 不是 Sparkle。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `at.obdev.littlesnitch` | 共享 | （无信号即为 stable，见下） | VendorProbe `channel: .stable` | ✓ |
| nightly | `at.obdev.littlesnitch` | 共享 | `CFBundleShortVersionString` 内嵌单词 "nightly"（`"6.5 nightly (7301)"`） | `ReleaseChannel.detect()` 新增 0.7 步 + VendorProbe `channel: .nightly` | ✓ |

Pattern：**同 bundle id、无应用内偏好开关**——stable 与 nightly 是两个完全独立的下载
（Homebrew 用 `conflicts_with` 互斥），只是碰巧共享一个 bundle id。这本该是 Pattern D
（不可判定）的形状,但 obdev 把 channel 词直接烤进了 `CFBundleShortVersionString`
本身,所以实际可判定——只是判定逻辑不在既有的任何一步里（既不是 dash-tail 形状,也不是
Mozilla 的 `aN`/`bN`/`esr` 形状,是空格 + 括号构建号）,`ReleaseChannel.detect()` 因此新增了
专门的 bundle-id 限定规则（0.7）。

**FEED-VS-BUNDLE 陷阱**（已在真实机器上验证过、不是猜的）：obdev 自己的版本 feed 把 nightly
条目的 `BundleShortVersionString` 精简成裸的 `"6.5"`，抹掉了真实安装包里的
`" nightly (7301)"` 后缀。channel 判定绝不能信这个字段——`ReleaseChannel.detect()`
读的是**真实安装的** `CFBundleShortVersionString`（来自 `AppScanner` 直接读 plist），
不是 feed 的镜像；而两个 VendorProbe recipe 用 `versionIsBuild: true` 比较 `BundleVersion`
（`7301`/`7212`，与真实 `CFBundleVersion` 逐字节相同），完全绕开了这个被裁剪的字段。

## 更新检测

- **未采用**厂商真实客户端使用的动态端点
  `sw-update.obdev.at/update-feeds/software-update.php`（`Little Snitch Software Update.app`
  二进制里的字符串确认了这个 URL）：明文 GET 直接回 `Malformed Request`，真实请求体的字段
  未知——需要抓包真实客户端的请求才能确认参数（本次未做，见「已知问题」）。
- **采用**了 obdev 另外公开的**静态**版本 feed:
  `https://sw-update.obdev.at/update-feeds/littlesnitch6.plist`。这不是猜的端点——它是
  Homebrew 官方 `little-snitch` cask 的 `livecheck` 块自己用来核对新版本号的同一个 URL
  （`Casks/l/little-snitch.rb`），即第三方（Homebrew）已经在长期依赖这个端点做同一件事。
  是一个 XML plist 数组，每个 release lifecycle（`nightly`/`final`）一条记录,含
  `BundleVersion`/`BundleShortVersionString`/`DownloadURL`/`DownloadPageURL`/
  `ReleaseNotesURL`/`InstallationMechanism`。
- Recipe 用 `entryStartPattern` 把两条记录切开,`final`/`nightly` 关键字锚定各自记录的
  `BundleVersion`,不依赖 feed 里两条记录谁先谁后。
- **版本方案**：feed 的 `BundleVersion` 与真实安装包的 `CFBundleVersion` 逐字节一致
  （stable `7212`、nightly `7301`），`versionIsBuild: true`。
- **是"轨道最新"还是"本机被分配"**：这个端点不带任何设备标识或分批参数,是一份公开的静态
  文件,人人拿到同一份内容,且每个 lifecycle 都有一个公开、免登录的官网下载页
  （`obdev.at/littlesnitch/download.html` / `download-nightly.html`）——即这个端点读到的
  版本,任何人都能在官网手动下载到同一个构建,不存在"厂商还没把这个构建分配给这台机器"的风险,
  与 Claude `/latest` 那类端点是同一类安全论证。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | feed 每条记录的 `InstallationMechanism` 都是字面量 `"ReplaceBundle"`（整包替换,不是增量补丁）;`Little Snitch Software Update.app` 二进制的字符串里没有 `delta`/`bspatch`/`hdiff`/`diffpatch` 等任何增量相关词（`strings -a` 扫描,2026-08-29） | 同一份 feed 记录里除 `DownloadURL` 外没有任何 delta/patch 字段 | — |

- 格式: 厂商自有更新机制,整包替换,无增量。
- 阻塞项: 无（本身就不需要增量）。

## Changelog

- Stable 有公开的整页发布历史 `https://obdev.at/products/littlesnitch/releasenotes6.html`
  （200,77KB,人类可读的分版本页面）,已设为 stable recipe 的 `changelogURL`。
- Nightly **没有**对应的整页历史,只有 feed 里指向 `releasenotes-legacy-swu.php?version=<build>`
  的单版本片段接口——把它写死进 recipe 会随着下一个 nightly 发布而失效（版本号写死了）,所以
  nightly recipe 的 `changelogURL` 留空,渲染为"无发布说明"而不是一个会静默过期的链接。
- Recipe 状态: 已有（stable）/ 故意不加（nightly）。

## 一键安装

- 状态: **仅检测,未接一键**。
- 阻塞: Little Snitch 是内核扩展类安全软件的现代等价物——真实挂载的 stable dmg 显示它现在用的
  是 **System Extension**（`Contents/Library/SystemExtensions/at.obdev.littlesnitch.networkextension.systemextension`,
  内含 XPC 服务 `at.obdev.littlesnitch.networking.xpc`）而非传统 kext（cask 的 `zap` 块里那条
  `/Library/Extensions/LittleSnitch.kext` 路径是历史遗留清理项,不是当前机制）,外加一个
  根目录下的守护体系（`/Library/Little Snitch/`）。feed 把 `InstallationMechanism` 标成
  `ReplaceBundle`——这与本仓库 `VendorInstaller` 做的事（校验 Team ID 后整包替换 `.app`）
  形状一致,理论上应该可行,厂商自己的更新器显然就是这么做的。但这条路径**没有在真实机器上
  跑通验证**：单纯换 `.app` 是否会让系统在下次启动时正确重新激活/续期已批准的 System
  Extension,还是会触发用户需要重新走一遍系统授权（甚至短暂断网防护）,未经实测确认，而
  Little Snitch 是一个防火墙,这类失效的代价（悄悄失去防护或短暂全断网）比大多数 app 高得多。
  按 CLAUDE.md「只做被要求的事」,本次只接测速,一键留给后续单独验证任务。
- 若要继续: 需要在一台真实安装了 Little Snitch 的机器上,用旧版 dmg 装出一个可升级的旧构建,
  跑一次真正的 `VendorInstaller` 换包,观察系统扩展批准状态是否保留、网络过滤是否无缝衔接。

## 已知问题

- 真实客户端使用的动态端点 `software-update.php` 的请求参数未知（明文 GET 回
  `Malformed Request`）。目前不需要它——静态 `littlesnitch6.plist` 已经覆盖了两个 channel——
  但如果 obdev 未来收紧或撤下这个 Homebrew 也在用的静态 feed,需要抓包真实客户端才能迁移。
  这一点现场无法确认,记录在此。
- `littlesnitch6.plist` 按主版本号命名（`6`）,Little Snitch 发布 7.x 之后这个 URL 会需要改成
  `littlesnitch7.plist`（Homebrew 的 livecheck 同样受此限制,不是本仓库独有的脆弱点）。

## 建议下一步

1. 一键安装可行性: 需要一台真实安装了 Little Snitch 的机器做红→绿验证（装旧版 → 用
   `VendorInstaller` 换包 → 确认 System Extension 批准状态与网络过滤不受影响）,再决定是否给
   两个 recipe 加 `install:`。
2. 如果之后需要迁移掉 `littlesnitch6.plist`（主版本号硬编码,或 obdev 撤下该端点）,需要抓包
   真实 `Little Snitch Software Update.app` 对 `software-update.php` 发出的请求,确认参数形状。
