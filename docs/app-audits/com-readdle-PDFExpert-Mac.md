# PDF Expert

## 基本信息
- Bundle ID: `com.readdle.PDFExpert-Mac`
- Team ID: `3L68KQB4HG`（`Developer ID Application: Readdle Technologies Limited`，spctl `source=Notarized Developer ID`）
- 观测版本: `3.13.2` / build `1172`
  （证据全部取自厂商产物：appcast 指向的 `pem3/versions/1172/PDFExpert.zip`，解开后读
  `PDF Expert.app/Contents/Info.plist`，2026-09-04。**这次没有从任何装机副本取证**，
  所以下面凡是需要一份运行中的拷贝才能做的核对，都标了 needs-verify。
  另有一个 `PDF Expert Installer.app`（`com.readdle.PDFExpert-Installer` 1.5.1）——
  那是个下载壳，不是本体，只用来佐证 ATS 例外域名。）
- 自更新机制: Sparkle（`SUFeedURL` + `SUPublicEDKey` + `SUEnableAutomaticChecks` 都在 Info.plist 里）
- 架构: universal（`Mach-O universal (x86_64 arm64)`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | ✓       | ✗        | ✓   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: 官网副本 = **Sparkle**；App Store 副本 = **MAS**。

- Homebrew cask `pdf-expert` 存在、`version 3.13.2,1172`、`url` 就是 pem3 的那个 zip，
  但 `auto_updates: true` → `HomebrewCaskSource` 按既有逻辑跳过。**所以它不是兜底**，
  这一点是下面那个 bug 严重性的关键。
- MAS 有同 bundle id 的副本（`trackId 1055273043`，iTunes lookup `kind=mac-software`，
  版本 3.13.1、比官网轨慢一版）。同 id 两种分发，靠 `_MASReceipt` 分流，
  `MacAppStoreSource` 在优先链里排在 Sparkle 前面。**MAS 副本的 Info.plist 里有没有
  `SUFeedURL` 没有验证**（手上没有那份拷贝）——但也不影响：有 receipt 就先走 MAS。

## 更新检测

### 厂商声明的 feed 是死的（这次改动的全部内容）

app bundle 的 `SUFeedURL` 是：

```
https://downloads.pdfexpert.com/release/appcast.xml
```

这份 feed `Last-Modified: Tue, 12 Jul 2022 14:49:50 GMT`，2542 字节，四个 item，
最新的是 build `764` / `2.5.22`。其中三个有 `sparkle:maximumSystemVersion`
（10.10.999 / 10.11.999 / 10.12.999），**第四个（764）没有**，`minimumSystemVersion 10.13`。

所以在今天的 Mac 上，通用 Sparkle 源不是"什么都读不到"，而是**读到了一个 2022 年的答案**：
`usableItems` 留下 764，`2.5.22` 与 3.13.2 比较 → 旧 → 报"已是最新"。
没有报错、没有 miss、`RecipeHealth` 也不会亮——因为 feed 本身 200 且解析成功。
再加上 cask 是 `auto_updates`（上面），**没有任何一个源会接手**，这个 app 于是永久隐形。

真正在用的 feed 是：

```
https://downloads.pdfexpert.com/pem3/release/appcast.xml
```

`Last-Modified: Mon, 31 Aug 2026 07:30:19 GMT`，五个 item：一个当前版本（3.13.2 / 1172，
`minimumSystemVersion 12.0`，带 `sparkle:deltas` 两条 + `phasedRolloutInterval 86400`），
外加四个给 10.13/10.14/10.15/11 的历史 item，**都带 `maximumSystemVersion`**，
在当前系统上会被 `usableItems` 全部滤掉——即这份 feed 在现代 Mac 上只有一个可用答案，
不存在选错 item 的空间。

### 凭什么断定 pem3 才是这个 app 的 feed

不是"新的那个看起来更像"。三条证据，注意它们的强度不一样：

1. **Apple 的背书（最硬的一条，且与 CDN 路径无关）**：pem3 的 1172 item 链接的 zip 解出来的
   `.app` 是 `Developer ID Application: Readdle Technologies Limited (3L68KQB4HG)` 签名、
   已公证（`spctl -a -vv` → `accepted / source=Notarized Developer ID`）。这是 Apple 对
   "这份产物出自 Readdle" 的背书，握着那个 CDN 路径的人伪造不出来。
2. **第三方独立指向同一处**：Homebrew `pdf-expert` cask（与本仓库无关的人在维护）的 `url`
   就是 `pem3/versions/1172/PDFExpert.zip`，`version 3.13.2,1172`。
3. **feed 内部自洽**（⚠️ **这条是循环的，别当成独立证据**）：zip 里的 `SUPublicEDKey`
   `K5sdt9UTWp/TcP48oRVycKUqWUbi0Tp37zrWtFYCCfw=` 确实能验过那个 item 的 `sparkle:edSignature`
   （Ed25519，2026-09-04 实测，zip sha256
   `44699a8c0d9da411ca875d200bbcb47bfdace535373a867420525982472b6980`）。但**密钥和载荷都来自
   pem3 这棵树**，它证明的是"这份 feed 和它自己的产物对得上"，不是"这把密钥就是用户手上那份
   拷贝持有的那把"。

第 3 条**没法做成独立的**：死 feed 那棵树上的三个构建（764 / 936 / 964，range-read 出
Info.plist，2026-09-04）**一个都没有 `SUPublicEDKey`**，而四个构建的 `SUFeedURL` 全是同一个
死地址。所以能与装机副本对照的公钥只存在于新 feed 自己发的那份产物里。

**这条推论对一键安装有实际后果**：真正卡住的用户（3.13 以前的任何一版，也正是这次改动要救的
那批）`app.sparkleEdPublicKey` 是 nil，`UpdatePolicy` 走的是 **unsigned-feed 分支**——闸是
代码签名 + 同 Team + 同 bundle id，**EdDSA 对他们根本不生效**。下面「一键安装」一节里那些
关于签名的话是在 1172 上量的，不描述真正会按那个按钮的人。

### 接法：匹配死地址，不是匹配 bundle id

`SparkleFeedCatalog` 原本只有一张 `feeds` 表，语义是**填空**——只在 bundle 一个地址都没写时
才给地址，注释里明写"绝不覆盖 bundle 自己发布的 feed"。PDF Expert 是它没覆盖到的第二种形状：
**bundle 写了地址，但那个地址被厂商废弃了**。

新表 `supersededFeeds` 存的是一对 `(declared, live)`，`replacement(forBundleID:declaredFeed:)`
**只在 `declaredFeed` 与记录的死地址逐字节相同时**才返回 live。这一条是刻意的：

- 按 bundle id 查会把这个 app 永久钉在我们 2026 年对 Readdle 基础设施的理解上。哪天他们
  把 `SUFeedURL` 改成 pem3（或第四个地址），按 id 查会**继续**用我们的表覆盖他们的新地址，
  而且看起来跟正常工作一模一样。
- 按地址查则会在那一刻自动失效，回到"bundle 自己说了算"。

调用点在 `AppScanner.readApp(at:)`，排在 `feeds` 填空之后、`ChannelBinding` 之前：
`ChannelBinding.feedOverride` 是**渠道决定**（Fork/Surge 换轨），仍然优先级更高。
也**不**设 `channelIsAuthoritative`——pem3 的 item 一个 `sparkle:channel` 都没有，
渠道照旧从 feed 自己的条目推断，与 Helium 那条走同一条路径。

## Changelog

- appcast 的 `sparkle:releaseNotesLink` 是 `pdfexpert.com/pem3/changelog.html`，3480 字节，
  **只有最新一版**那一段话 + 一句"以前的版本见 /pem3/changelog"。
- 完整历史在 `sparkle:fullReleaseNotesLink` = `pdfexpert.com/pem3/changelog`（38 KB，
  **88 个标题、85 个不同版本号**——`3.10.23` / `3.10.22` / `3.9.2` 各出现两次，其中两对的正文
  完全不同；`ChangelogExtractor` 按 version + title 去重，这里 title 是 nil，所以每对的第二份
  正文被静默丢掉。没有绕开：两段同号正文哪份算数是厂商的问题，不是正则的问题）。**`SparkleAppcastParser` 根本不读 `fullReleaseNotesLink` 这个元素**
  （全仓 grep 零命中），所以这里只能用 ChangelogRecipe，不是补一个 feed 字段的事。
- 页面异常干净：整篇只有 `p` / `strong` / `br` / `body` 四种标签，零链接、零图片、**零日期**
  （所以 recipe 没有 `date` 捕获组）。每条形如
  `<p><strong>Version 3.13.2 </strong></p> 正文<br />正文<br />`，
  标题里的尾随空格时有时无。
- item 用 `(?:^|>)\s*(?:-\s+)?(?<item>[^<]+)`：`(?:^|>)` 是必须的——没有它，正则会从
  停下的那个 `<` 后一个字符继续，于是第一条之后每条都读成 `br />…`（实测踩过）。
  `-\s+` 去掉 3.1 以前那批条目自己写的短横线项目符号。
- `maxEntries: 20`。空行（老条目用 `<br /><br />` 分段）清洗后为空，被默认的 `minItemLength: 1`
  滤掉；**没有设更高的下限**——全页 88 条里没有一条清洗后短于四个字符，设了就是一个没有任何输入
  在量的旋钮，还会在第一条短说明出现时把它吃掉。
- 标题匹配写成 `<p[^>]*>` 而不是页面当前用的裸 `<p>`。这条 recipe 的失效形状不是常见的"零条目"：
  终止锚一旦失配，第一块会一路跑到 `</body>`，结果是**一条**版本号正确的条目挂着整页正文，而
  `duo verify` 只记录最新版本号、不记条目数，**这种失效会扫成绿的**。厂商在 `<p>` 上加一个 class
  就够了。

## 一键安装

- 走通用 Sparkle 安装路径：enclosure 是 zip，带 `sparkle:edSignature`。⚠️ `SUPublicEDKey`
  **只有 3.13.x 有**（见上），所以对需要更新的旧版本用户，闸是代码签名 + Team + bundle id，
  不是 EdDSA。
  zip 里的 `.app` 是 `Developer ID` 签名 + 已公证、Team `3L68KQB4HG`，universal 二进制在
  arm64 宿主上可运行。这几个闸的输入都已经核实过（见上），**但没有端到端跑过一次安装**
  ——那需要一份装机副本，这次没有。标 needs-verify。
- `sparkle:deltas` 在 feed 里（1172←1171 是 781 KB，对 128 MB 全量包），由
  `SparkleAppcastParser` 自己解、`SparkleAppcastSource` 带出来（`channel-verify` 打的
  `deltas 2` 就是它）。**不是 `VendorAppcastDeltas`**——那个只从 `VendorProbeSource` 走，
  这个 app 到不了。增量是否真的能应用未实测。

## 如何复验

产物取自 appcast 的 enclosure，展开后用 `channel-verify` 跑**生产的整条源链**
（`ReleaseChannel.detect` → `UpdateChecker.check`，不是 harness 自己的近似）：

```sh
curl -o PDFExpert.zip https://downloads.pdfexpert.com/pem3/versions/1172/PDFExpert.zip
ditto -x -k PDFExpert.zip out
swift run --package-path application-test channel-verify "out/PDF Expert.app"
```

2026-09-04 实测，**红 → 绿都在同一份真实 bundle 上跑过**：

- 改动前（harness 还没学会这一步时的输出，等价于线上行为）：
  `SUFeedURL https://downloads.pdfexpert.com/release/appcast.xml` /
  `winning source Sparkle` / `latest 2.5.22` / `deltas 0` / `status up to date`
  ——**装着 3.13.2 被告知已是最新**。
- 改动后：`SUFeedURL …/pem3/release/appcast.xml`（并打印一行 `superseded` 说明原地址被换掉）/
  `latest 3.13.2` / `download …/pem3/versions/1172/PDFExpert.zip` / `deltas 2` / `status up to date`。
- 把同一份 bundle 的 `CFBundleShortVersionString`/`CFBundleVersion` 改成 `3.13.1`/`1171` 再跑：
  `status UPDATE → 3.13.2`。

⚠️ `channel-verify` 自己**不**走 `AppScanner.readApp`，它另起一段代码组装 `InstalledApp`；
这次顺手把新的这一步补进去了。不补的话它会继续报旧 feed，而它存在的全部意义就是不与生产分歧
（文件里已经为 Helium 那次分歧写过同样的话）。

changelog recipe 打真实页面：

```sh
duo verify --only pdfexpert --samples
```

2026-09-04：`changelog ✓ 1`，`version 3.13.2`。（`duo verify` 用的是**已安装的** CLI，
先 `make cli`。）

## 已知问题 / 未做的事

- **`phasedRolloutInterval 86400` 我们不读**（全仓 grep 零命中）。Sparkle 自己会按这个把一次
  发布摊到 24 小时里逐步放出，我们会在 feed 一更新就提供更新。对用户没有坏处（拿到的是
  厂商已经公开发布的构建，任何人都能从同一个 URL 下到），但它确实是"我们比厂商自己的更新器
  更早提示"的一个来源。这是全局行为，不是 PDF Expert 专属的，没有在这次改动里动。
- **`SparkleFeedCatalog` 不在 `duo verify` 的扫描范围里**（verify 只扫 VendorProbe / GitHub /
  Changelog 三张 registry）。所以 pem3 这个地址哪天再死一次，夜间扫描不会发现——发现它的
  仍然只有用户。这次新加的 changelog recipe 倒是进了 verify。要补的话是给 verify 加第四类
  registry，超出本次范围。
  ⚠️ 这条比它看起来重要，因为**这次改动改变了这张表的风险形状**：以前 `SparkleFeedCatalog`
  只能"填空"，最坏是没填上；现在它能"覆盖"，即我们对着一个 bundle 明说的地址断言另一个地址。
  能给出**错误答案**的那一半，恰恰是没有任何常设检查在看的那一半。
- **`feed-discover --gaps` 结构上看不到这一类 app**：它只留下"一个地址都没写"的 bundle。
  写了地址但地址是死的，不在它的筛子里。这次给 `FeedDiscovery` 加了 `.superseded` verdict，
  所以至少全量 `--scan` 会明说"这个声明的地址被换掉了"，而不再打印"已被 SparkleAppcastSource
  覆盖"这句假话；但 `--gaps` 的筛法没动。
- MAS 副本这次没有取到实物，`_MASReceipt` 分流路径没有在这个 app 上实测过（机制本身是通用的）。
