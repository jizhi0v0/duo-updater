# Audacity

审计 2026-10-08（重审；2026-06-04 那版只核对了下载包的 Team 与版本，没在新旧两个包上跑生产检测，没确认哪个源应答，
没看 changelog 面板，没跑一键，「Audacity 4 预览共用 bundle id」也没在真包上验过）。

**这份文档覆盖 Audacity 3 与 Audacity 4 两个产品。** 2026-09 起它们是两个 bundle、两个 cask，见下表。文件名仍按 3.x 的 id。

## 基本信息
- Bundle ID（全部在真包上读到）:

  | 构建 | `.app` 名 | `CFBundleIdentifier` | 版本（short / build） | `CFBundleExecutable` |
  |---|---|---|---|---|
  | 3.x stable（3.7.8、3.7.9） | `Audacity.app` | `org.audacityteam.audacity` | `3.7.9.0` / `3.7.9.0` | `Wrapper` |
  | 4.x stable（4.0.0、4.0.1） | `Audacity 4.app` | `org.audacityteam.audacity4` | `4.0.1` / `262721409` | `audacity` |
  | 4.0 alpha 2、4.0 beta 4（GitHub prerelease） | `Audacity 4.app` | `org.audacityteam.Audacity`（**大写 A**） | `4.0.0` / `253031630`、`262401356` | `audacity` |

- Team ID: **3.7.8 及更早是 `AWEYX923UX`**（Developer ID Application: Dmitri Vedenko）；**3.7.9 与全部 4.x（含 alpha / beta）
  是 `6EPAF2X3PR`**（Developer ID Application: MuseScore）。所有包 `codesign --verify --deep --strict` 通过、`spctl` `accepted`
  （`Notarized Developer ID`）
- 观测版本: 3.x `3.7.9.0`（上一版 `3.7.8.0`）；4.x `4.0.1`（上一版 `4.0.0`）；prerelease `4.0.0`（beta 4、alpha 2）
- 自更新机制: 自研检查器，**不自己替换 bundle**。3.x 读 `updates.audacityteam.org/feed/latest.xml`，用户点安装时把 dmg 下到
  `~/Downloads` 再 `Open` 它；4.x（muse 框架）读 `feed/latest.json` 或 `latest.test.json`，下载安装包后退出并「运行安装」
  （macOS 上具体怎么「运行」dmg **未验证**）。两者都没有 Sparkle（4.x 的 Info.plist 有空串 `SUFeedURL`，包里没有框架）
- 开源: `audacity/audacity`（默认分支 `master`；3.x 在 `release-3.7.x` 分支，4.x 在 `release-4.0.x`）
- Homebrew（2026-10-08 API）:
  - `audacity` → **4.0.1**，`app "Audacity 4.app"`，`uninstall quit: org.audacityteam.audacity4`（2026-09-06 的 `audacity 4.0.0` 提交起）
  - `audacity@3` → 3.7.9，`app "Audacity.app"`，`uninstall quit: org.audacityteam.audacity`（2026-09-08 新建）
  - 都没声明 `auto_updates`；Apple silicon 用 `-arm64.dmg`，Intel 用 `-x86_64.dmg`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **3.x stable** (`…audacity`) | — | ✓ 仅 Caskroom 里是 `audacity@3`；✗ 老的 `audacity` cask 装的 3.x（见已知问题） | — | ○ | ○（`latest.xml`，需 `Audacity/` UA） |
| **4.x stable** (`…audacity4`) | — | ✓ `audacity` cask 装的 | — | ○ | ○（`latest.json`） |
| **4.x prerelease** (`…Audacity`) | — | — | — | ✗（见下） | ✗（`latest.test.json` 停在 beta 4） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Homebrew**（`HomebrewCaskSource`），只对 brew 装、且 Caskroom 里的
cask 与 `.app` 文件名对得上的拷贝。直装（GitHub / 官网 dmg）的拷贝没有任何源应答：`channel-verify` 对 3.7.8、3.7.9、4.0.0、
4.0.1、beta 4、alpha 2 六个包都是 `status unknown (no source answered)`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| 3.x stable | `org.audacityteam.audacity` | 独立 | — | Homebrew `audacity@3` | ✓（brew）/ ○（直装） |
| 4.x stable | `org.audacityteam.audacity4` | 独立 | — | Homebrew `audacity` | ✓（brew）/ ○（直装） |
| 4.x prerelease（alpha / beta） | `org.audacityteam.Audacity` | 与 3.x **只差大小写** | bundle id 大小写、`.app` 名 `Audacity 4.app`、主版本 4；没有渠道标记 | 独立下载（GitHub prerelease）；4.x 应用内有 `allowUpdateOnPreRelease` | ✗ 未接（`detect()` 报 stable） |

**旧文档「Audacity 4 预览与 stable 共用 bundle id」——更正（真包实测）:** prerelease（alpha 2、beta 4）的 id 是
`org.audacityteam.Audacity`，与 3.x 的 `org.audacityteam.audacity` 只差大小写；**4.x 正式版换成了 `org.audacityteam.audacity4`**，
所以 prerelease 和 4.x stable 并不共用 id。duo 的 changelog 注册表按小写查 id（`ChangelogRecipeRegistry` 注释写明
case-insensitive），实测 beta 4 / alpha 2 两个包的 changelog 面板都选中了 3.x 的 recipe，显示 3.7.9 的说明——串了产品。

**prerelease 怎么区分（客户端，源码）:** 4.x 的 `SetupConfigure.cmake` 按 `BUILD_MODE` 设 `MUSE_APP_RELEASE_CHANNEL`
（`dev` / `testing` / `stable`）与 `AU4_ALLOW_UPDATE_ON_PRERELEASE`；muse 框架的 `UpdateConfiguration::checkForAppUpdateUrl()`
在 `allowUpdateOnPreRelease` 为真时读 `latest.test`，否则读 `latest`。默认值：`release-4.0.1` 的 RELEASE 构建为 OFF、TESTING
构建为 ON；`release-4.0.0-beta4` 分支里 RELEASE 也是 ON。偏好键是 muse `Settings` 的 `application/allowUpdateOnPreRelease`；
它落在哪个文件**没查到**（cask 的 zap 列了 `~/Library/Preferences/org.audacityteam.Audacity4.plist`，**推断**在那里），
应用内也**没找到**改它的界面（`updatepreferencesmodel.cpp` 里只看到「检查更新」开关，没有逐个界面核对）。真包的 Info.plist 键集合在
beta 4 与 4.0.0 之间只差 bundle id 和版本，`MUSE_APP_RELEASE_CHANNEL` 没有落进 plist。

**各 feed 实测（2026-10-08，`updates.audacityteam.org`，Cloudflare）:**

| 地址（谁读它） | 浏览器 UA / curl UA | `Audacity/3.7.9` UA | 内容 |
|---|---|---|---|
| `/feed/latest.xml`（3.x RELEASE 构建） | **404** | 200，4375 B | `<Macos><Version>3.7.9</Version><Link>…/audacity-macOS-3.7.9-universal.dmg</Link>`；`<Changelog>` 里按 `version=` 标注的条目（3.7.8、3.7.7）；一条推广 Audacity 4 的 `<Notification>` |
| `/builds/alpha.xml`、`/builds/beta.xml`（3.x 非 RELEASE 构建） | 403 | 403 | S3 `AccessDenied` |
| `/feed/latest.json`（4.x，未开 prerelease） | 404 | 200，8015 B | `tag_name` `v4.0.1`，`bodyMarkdown`（`## Features` / `## Accessibility` / `## Bug fixes`），macOS 资产只有 `audacity-macOS-4.0.1-universal.dmg`（92,003,045 B） |
| `/feed/latest.test.json`（4.x，开了 prerelease） | 404 | 200，2697 B | `tag_name` `v4.0.0-beta.4`，资产 `Audacity-4.0.0-beta4-universal.dmg`——**停在 beta 4**，比 stable 4.0.1 还旧 |
| `/feed/all.json`、`/feed/all.test.json` | 403 | 403 | — |

3.x 客户端的真实 UA 是 `Audacity/<ver> (<OS 串>)`（`lib-network-manager/curl/CurlHandleManager.cpp`）。开了匿名统计时
URL 还会带 `?audacity-instance-id=<id>`；带空参数时回的正文与不带时同为 4375 B。

**GitHub prerelease（2026-10-08）:** `Audacity-4.0.0-alpha-2`（2025-11-03）、`Audacity-4.0.0-beta-2`（2026-06-11，只有 universal）、
`Audacity-4.0.0-beta-4`（2026-08-28），都是 `prerelease: true`；更早还有 3.3.0 / 3.4.0 / 3.5.0 的 beta。4.0.0 正式版之后没有新的
prerelease。所以「4.x 预览轨」现在没有比 stable 新的构建，`latest.test.json` 也停在 beta 4。

**duo 今天的行为（实测，Caskroom 注入，见「如何复验」）:**

| 包 | 注入的 Caskroom | 应答源 | latest | 结论 |
|---|---|---|---|---|
| 3.7.8 | `audacity@3` | Homebrew（`audacity@3`） | 3.7.9 | `UPDATE → 3.7.9` |
| 3.7.9 | `audacity@3` | Homebrew | 3.7.9 | `up to date`（`3.7.9.0` 与 `3.7.9` 比较相等） |
| 3.7.8 | `audacity`（9 月前用老 `audacity` cask 装 3.x 的人） | **无** | — | **`unknown`** |
| 4.0.0 | `audacity` | Homebrew（`audacity`） | 4.0.1 | `UPDATE → 4.0.1` |
| 4.0.1 | `audacity` | Homebrew | 4.0.1 | `up to date` |
| beta 4 | `audacity` | Homebrew | 4.0.1 | `UPDATE → 4.0.1`（`.app` 名对上 `audacity` cask） |
| beta 4 | `audacity@3` | 无 | — | `unknown` |

## 更新检测
- 源: `HomebrewCaskSource`，按 `.app` 文件名找 cask（`Audacity.app` → `audacity@3`，`Audacity 4.app` → `audacity`），
  再要求 Caskroom 里有**那个** cask
- 版本方案: 3.x 包里是四段 `3.7.9.0`，cask / feed / GitHub 是三段 `3.7.9`，比较相等（实测）；4.x 包里 `CFBundleShortVersionString`
  是三段、`CFBundleVersion` 是构建时间戳（`262721409`，看形状是「年后两位 + 年内第几天 + 时分」：beta 4 `262401356` 对应
  8 月 28 日 13:56，与 GitHub 发布时间同一天，**推断**），比较走 short 版本没问题
- prerelease 的 short 版本是 `4.0.0`，与 4.0.0 正式版相同，没有后缀；只靠版本串分不出 beta 4 与 4.0.0
- 直装拷贝要接检测（未实现）：3.x 和 4.x 都可以用 GitHub rule（`audacity/audacity`，tag `Audacity-<v>`，资产
  `audacity-macOS-<v>-{arm64,x86_64,universal}.dmg`，有 digest；3.x 要用 `installedVersionPattern` / 主版本限定，否则 3.x 会被推
  4.x）；或 VendorProbe 读厂商 feed（3.x 的 `latest.xml` 要带 `Audacity/` UA）

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 包里没有 `Sparkle.framework`；3.x / 4.x 更新代码只下载完整安装包 | `latest.xml` 只有一个 `<Link>`（完整 dmg）；`latest.json` 只列完整安装包 | — |

- 格式: —
- 阻塞项: —

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 3.x 可带 `audacity-instance-id` / `user_id` 参数 | 没看到：带不带空 id 参数正文相同（4375 B）；没用真实 id 测 | 不需要（cask 与 GitHub 对所有人相同） |
| 按架构 / 按 OS 分轨 | 架构: GitHub 发 arm64 / x86_64 / universal 三种 dmg；OS: 3.x `LSMinimumSystemVersion` 10.13，4.x 10.15 | feed 只给 universal；cask 按架构给 arm64 / x86_64；没有 OS 上限 | cask 路线由 brew 按架构选 |
| 自更新器会不会和我们抢 | 3.x: 否（下到 Downloads 后打开 dmg，由用户拖）；4.x: 下载后退出并运行安装包（macOS 行为未验证） | 是：两个 feed 都在发 | 一键第二轮未跑 |

## Changelog
- 来源: `ChangelogRecipe`（`https://github.com/audacity/audacity/releases` 第一页），bundle id `org.audacityteam.audacity`
- 结构化（`channel-verify` 原文）:
  - 3.7.8、3.7.9 两个包: `changelog pane  recipe changelog:org.audacityteam.audacity:-: 5 entries; newest 3.7.9: 8 items, headings []; first items ["#11690 Enabled ASIO support for the Wind", "#11679 Added FFmpeg 9 support", "#11714 Fixed several sources of project "]`
  - 4.0.0、4.0.1 两个包: `changelog pane  none — the pane says there are no release notes`（brew 应答时也一样：Caskroom 注入下 recipe 无、回退页 nil）
  - beta 4、alpha 2 两个包: 与 3.x 相同的那一行（**串到 3.x 的说明**，见上）
- 3.x 观测版本的条目都在：5 条是 `3.7.9, 3.7.8, 3.7.7, 3.7.6, 3.7.5`（实测）。`headings []` 是对的：3.7.9 的 release 正文就是
  一句引言加 8 个平铺的列表项，没有小标题
- 第一页 10 个 release 的标题: `Audacity-4.0.1`、`Audacity-4.0.0`、`Audacity 3.7.9`、`Audacity 4.0.0 Beta 4`、`Audacity 3.7.8`、
  `Audacity 4.0.0 Beta 2`、`Audacity 3.7.7`、`Audacity 3.7.6`、`Audacity-4.0.0.alpha-2`、`Audacity 3.7.5`。recipe 要求
  `Audacity <x.y.z></h2>`，所以 4.x 正式版（连字符）与 beta（后面跟 ` Beta N`）都不进条目。注意：recipe 注释说靠「连字符」跳过
  prerelease，实际挡住 beta 行的是 `</h2>` 紧跟版本号这一条
- 风险: 4.x 继续发版后，3.x 的 release 会被挤出第一页，recipe 解析为 0 条后面板回退到网页（推断，取决于 4.x 发版节奏）
- 厂商 feed 自带结构化说明：3.x `latest.xml` 的 `<Changelog><Item version="…">`，4.x `latest.json` 的 `bodyMarkdown`（带分节标题）
- 跟随 channel: 否
- Recipe 状态: 3.x 已有、今天可用；4.x **需要**（`org.audacityteam.audacity4` 没有 recipe）；prerelease 的 id 不该命中 3.x recipe

## 一键安装
- 状态: ✓ 仅 brew 装的拷贝（brew 路线：3.x 跑 `brew install --cask --force audacity@3`，4.x 跑 `… audacity`）；直装拷贝没有检测
- 端到端（2026-10-08，第一轮，不启动）:
  - 4.x：brew 装的 4.0.0（`Audacity 4.app`，`org.audacityteam.audacity4`）→ `duo check` `update 4.0.1`、`source Homebrew`；
    `duo install --yes --json` → `installed`、`route homebrew`，约 19 s。装后 4.0.1，strict 通过，`Notarized Developer ID`，
    Team `6EPAF2X3PR`；与厂商 4.0.1 dmg 逐文件比，592 个文件、139 个软链接全部相同。
  - 3.x：`audacity@3` 从没有 3.7.8 这一版，所以把当前 cask 的 version / sha256 改成 3.7.8 的值装上（Team `AWEYX923UX`）→
    `duo check` `update 3.7.9`、`source Homebrew`；`duo install` → `installed`、`route homebrew`。装后 3.7.9.0，strict 通过，
    `Notarized Developer ID`，Team **`6EPAF2X3PR`**；与厂商 3.7.9 dmg 逐文件比，273 个文件、32 个软链接全部相同。
    **实测确认 Team 变化不挡 brew 路线**（下一条是原因）。
  造旧版的办法：临时本地 tap（`brew tap-new --no-git`）里放旧版 cask，按全名 `brew install --cask` 装上；
  新版包事先放进 brew 的下载缓存（与 cask 的 sha256 一致，brew 照常校验），所以 `bytesDownloaded 0`。测完删 `.rb`、
  `brew untap`、`brew untrust --cask`。装后 Caskroom 回执的 `source.tap` 是 `homebrew/cask`
- 格式: dmg
- 校验: brew 校验 cask sha256；duo 的 brew 路线不过 Team 闸（`InstallCoordinator` 的 `.homebrew` 分支直接交给 brew），所以
  3.7.8 → 3.7.9 的 **Team 变化不挡 brew 路线**。下载哈希与 GitHub `digest` 全部一致（见「如何复验」）
- **读的是**: 人人可手动下载的 GA（cask = GitHub release 资产，无分桶）
- **Team 变化（实测）:** 3.7.8 `AWEYX923UX` → 3.7.9 `6EPAF2X3PR`。以后若给直装拷贝接 vendor / GitHub 一键，`SignatureVerifier`
  要求 Team 完全相同，3.7.8 及更早的拷贝升 3.7.9 会被安全地拒绝，需要用户手动更新一次（4.x 全部是 `6EPAF2X3PR`，不受影响）
- 嵌套: 3.x 与 4.x 包里都没有嵌套 `.app` / `.xpc` / `.appex`。3.x 的 `CFBundleExecutable` 是启动器 `Wrapper`（见下）
- 阻塞: 直装拷贝无检测；老 `audacity` cask 装的 3.x 无检测

## 打包形状（runtime 标记相关）
- 3.x 的 `CFBundleExecutable` 是 **`Wrapper`**，不是 `Audacity`：70,080 字节的启动器，`otool -L` 只有
  `libSystem.B.dylib`，`strings` 里只有 `Audacity` 和 `AUDACITY_PRESERVE_LIBRARY_PATH`——
  作用是设好 dylib 搜索路径再 exec 同目录的 `Audacity`（21,251,232 字节，链 AppKit）。
- 3.x 的 `Contents/Frameworks` 里 **144 个 `lib-*.dylib`，一个 `.framework` 都没有**（3.7.8、3.7.9 都是 144），所以按布局判定
  runtime 的规则全部落空。
- 后果：`AppRuntimeDetector` 原来把标记读在 `Wrapper` 上，Audacity 一行没有 runtime 徽章。
  2026-09-05 加了「退到 `Contents/MacOS/<bundle 名>` 再读一次」的规则后判为 `native` +
  `Links AppKit`。实测于 3.7.8.0（macOS 26.6）。
- 4.x 是 Qt 应用，`CFBundleExecutable` 就是 `audacity`，`Contents/Frameworks` 72（4.0.0）/ 87（4.0.1）项；runtime 徽章没查

## 已知问题
- **9 月前用 `audacity` cask 装的 3.x 拷贝现在是 unknown**（实测）：`Audacity.app` 只对得上 `audacity@3`，而 Caskroom 里是
  `audacity`。同一时间 `brew upgrade` 会把这个 cask 升成 4.0.1，装出的是另一个 bundle（`Audacity 4.app` / `…audacity4`）——
  这一半是从 cask 定义**推断**的，没跑 brew
- prerelease（`org.audacityteam.Audacity`）的 changelog 面板显示 3.x 的说明（实测）；brew 装了 4.x 又被 beta 覆盖时（`.app`
  同名），会被推 4.0.1（实测，方向对，但渠道报 stable）
- 4.x 没有 changelog（实测 `none`）
- 直装拷贝（3.x、4.x、prerelease）全部 unknown

## 建议下一步
1. 4.x changelog：`/fragile-recipe Audacity 4`（ChangelogRecipe，bundle `org.audacityteam.audacity4`）。来源二选一：GitHub releases
   （标题是 `Audacity-<v>` 或空名回落到 tag，正文有 `## Features` 等分节，要 `headingPattern`），或厂商 `latest.json` 的
   `bodyMarkdown`（只有最新一版，且要 `Audacity/` UA）
2. 3.x recipe 加版本窗口（`installedVersionPattern` / 版本 scope 到 `3.`），让 `org.audacityteam.Audacity` 的 4.0.0 prerelease
   不再命中；同时考虑 3.x 的条目被挤出 GitHub 第一页的问题（`latest.xml` 的 `<Changelog>` 按版本标注，可作替代来源）
3. 老 `audacity` cask 装的 3.x：在 `HomebrewCaskSource` 里怎么处理是产品决定（跟 brew 一起跨到 4.x 是换产品、换 bundle id），
   先在 `CHANNEL_COVERAGE_TODO.md` 记下，不要顺手改
4. 直装检测：GitHub rule 分别给 3.x（限定主版本 3）与 4.x（`…audacity4`）；3.x 一键要在文档里写明 3.7.8 → 3.7.9 的 Team 变化
5. prerelease：现在没有比 stable 新的 prerelease，`latest.test.json` 也停在 beta 4。等 4.1 之类的 beta 出现时，再看它的 bundle id
   是否仍是 `org.audacityteam.Audacity`；在那之前不接
6. 一键第二轮（Audacity 运行中）未跑；第一轮已过（见「一键安装」）

## 如何复验

2026-10-08。包从 GitHub release 资产下载（cask 指向的就是它们），每个包放各自的空目录；`hdiutil attach -nobrowse -readonly`
挂载检查，不安装、不启动。

```bash
gh api "repos/audacity/audacity/releases?per_page=12" --jq '.[] | [.tag_name, .prerelease, .published_at] | @tsv'
curl -sS -A "Mozilla/5.0"     -o /dev/null -w '%{http_code}\n' https://updates.audacityteam.org/feed/latest.xml   # 404
curl -sS -A "Audacity/3.7.9"  https://updates.audacityteam.org/feed/latest.xml                                     # 200, 3.7.9
curl -sS -A "Audacity/4.0.1"  https://updates.audacityteam.org/feed/latest.json                                    # v4.0.1
curl -sS -A "Audacity/4.0.1"  https://updates.audacityteam.org/feed/latest.test.json                               # v4.0.0-beta.4
G=https://github.com/audacity/audacity/releases/download
curl -fL --retry 5 -C - -O $G/Audacity-3.7.8/audacity-macOS-3.7.8-arm64.dmg
swift run --package-path application-test channel-verify audacity-macOS-3.7.8-arm64.dmg
```

| 包 | 大小 | SHA-256（= GitHub `digest`） |
|---|---|---|
| `audacity-macOS-3.7.8-arm64.dmg` | 31,818,104 | `2888d2bef5321990d3a11507f9b5cf9461831725a50f391fffd558f7404ffcf8` |
| `audacity-macOS-3.7.9-arm64.dmg` | 31,370,830 | `fafeb7fa963d3e2ba05ee7aba5290c966362ac5f5feca86eb8b1f61c7819d499`（= `audacity@3` cask） |
| `audacity-macOS-4.0.0-arm64.dmg` | 46,806,707 | `266201f3151b09e46a5ab8e0ce1a16cefdd53a66fc7c979e943b2c88d6500c51`（= `audacity 4.0.0` cask 提交） |
| `audacity-macOS-4.0.1-arm64.dmg` | 50,034,126 | `278c8647b78c77af7f07dbd5e7d9bfc950bc14168047b65738716b61d12055ec`（= `audacity` cask） |
| `Audacity-4.0.0-beta4-arm64.dmg` | 45,833,321 | `3fba43f3a92ad2155bbfdbf2693af93b52875b476a74e84314d1c6fcfc643c2b` |
| `Audacity-4.0.0.253031629.f3e3e3b.dmg`（alpha 2，universal） | 103,469,895 | `c09f375ee3d7f49369eb2c34d96a6954b18b8cb6387aa9b5ad568a921218eea5` |

`channel-verify` 摘录:

```
3.7.8   bundle id org.audacityteam.audacity   short 3.7.8.0   detected stable   winning source <none>   status unknown (no source answered)
3.7.9   bundle id org.audacityteam.audacity   short 3.7.9.0   detected stable   winning source <none>   status unknown (no source answered)
4.0.0   bundle id org.audacityteam.audacity4  short 4.0.0  build 262451605   detected stable   status unknown (no source answered)
4.0.1   bundle id org.audacityteam.audacity4  short 4.0.1  build 262721409   detected stable   status unknown (no source answered)
beta 4  bundle id org.audacityteam.Audacity   short 4.0.0  build 262401356   detected stable   status unknown (no source answered)
alpha 2 bundle id org.audacityteam.Audacity   short 4.0.0  build 253031630   detected stable   status unknown (no source answered)
```

`channel-verify` 读的是真实 Caskroom，没有对应 cask 时 Homebrew 不应答，所以上面是「直装拷贝」的结果。brew 装的拷贝用一个
临时测试量（跑完删掉）：真包 `AppScanner.readApp` → `HomebrewCaskSource(inventory: BrewLocalInventory(installedTokens: …))`
→ `UpdateChecker.check`，cask 目录是线上 formulae.brew.sh，结果即「duo 今天的行为」那张表。

签名摘录（`codesign -dvv`）:

```
3.7.8   Authority=Developer ID Application: Dmitri Vedenko (AWEYX923UX)   TeamIdentifier=AWEYX923UX
3.7.9   Authority=Developer ID Application: MuseScore (6EPAF2X3PR)        TeamIdentifier=6EPAF2X3PR
4.0.0 / 4.0.1 / beta 4 / alpha 2    TeamIdentifier=6EPAF2X3PR
```

## 审计记录
- 2026-06-04: 首版，只从 cask 下载包读了 Team `AWEYX923UX` 与版本 3.7.7.0。
- 2026-09-05: runtime 徽章规则（见「打包形状」）。
- 2026-10-08: 重审。旧版的错与漏：Team 已在 3.7.9 换成 `6EPAF2X3PR`；`audacity` cask 已改发 4.x（新 bundle id
  `org.audacityteam.audacity4`），3.x 搬到 `audacity@3`，老 cask 装的 3.x 因此失去检测；「4 预览共用 stable bundle id」不准确
  （prerelease 是大小写不同的 `org.audacityteam.Audacity`，4.x 正式版另起 id），而这个大小写差异让 prerelease 命中了 3.x 的
  changelog recipe；厂商有自己的版本 feed（UA 门控），旧版写的「no `SUFeedURL`」不等于没有可读的端点。
