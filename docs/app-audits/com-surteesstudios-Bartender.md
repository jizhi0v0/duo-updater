# Bartender

**这不是审计**：family `com-surteesstudios-Bartender`（`Recipes/com-surteesstudios-Bartender.swift`）里 Bartender `com.surteesstudios.Bartender` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-surteesstudios-Bartender.swift — stable VendorProbe（检测上是死的，留作 sweep 锚点）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（bundle 声明的 `SUFeedURL` 就是这个地址，所以 `SparkleAppcastSource` 先应答，保留了读取日期），当年那句保留意见和读的是哪个版本搬到这里。

DEAD FOR DETECTION, kept as a sweep anchor. The hedge this comment used
to carry ("if the installed app has SUFeedURL … Sparkle takes priority")
was settled on 2026-08-31 by reading the real 6.6.2 bundle: it declares
`SUFeedURL = https://www.macbartender.com/B2/updates/AppcastB6.xml`, the
same address as below, so `SparkleAppcastSource` answers first and this
recipe never runs in production. It stays because `duo verify` sweeps the
recipe registries and nothing sweeps Sparkle feeds — deleting the row
would leave the endpoint unwatched. Do not "fix" this by re-pointing it.

### Recipes/com-surteesstudios-Bartender.swift — stable VendorProbe（一键 zip）

转引自 recipe 注释，未复测。整段原文；括号里那句原样留在代码里。

Verified 2026-08-09 on 6.6.2: `Bartender 6.app` in the archive, bundle
id com.surteesstudios.Bartender, Team 24J875RH8J, spctl "Notarized
Developer ID". (Note the older entries are served from macbartender.com
and the recent ones from downloads.macbartender.com — the pattern
accepts either host.)

复测 2026-09-14（约 07:30 UTC，只读 GET；`www.macbartender.com/B2/updates/AppcastB6.xml` 先 307 到 `downloads.macbartender.com` 同一路径）：16 个 `<item>`，第一个 enclosure 是 6.0.0（`macbartender.com/B2/updates/6-0-0/…`），最后一个是 6.6.2（`downloads.macbartender.com/…/6-6-2/…`）。代码里 "the first enclosure is 6.0.0" 和两个主机的说法因此原样保留。

### Recipes/com-surteesstudios-Bartender.swift — ChangelogRecipe（`feedPagePattern`，2026-10-10 接入）

只读 GET，2026-10-10。appcast（`www.` 307 到 `downloads.macbartender.com`）16 个 `<item>`，升序，最新 6.6.2
（= baseline `vendor:com.surteesstudios.Bartender:stable` 的 `lastGoodVersion`），每个 item 一个
`<sparkle:releaseNotesLink>`，无 `xml:lang`。6.0.0–6.4.1 链接 `macbartender.com/B2/updates/<6-x-y>/rnotes.html`，
6.5.1 起是 `downloads.macbartender.com/…`。16 个链接全部被 `feedPagePattern` 接受；逐个 GET：6.1.2、6.1.3、6.2.1、
6.3.0、6.3.1、6.4.1 共 6 个 404，其余 10 个 200。

生产解析器（`ChangelogExtractor`，临时测试）在 10 个活页上都出 1 条，版本 = 链接版本，唯独 6.0.0 页标题是
"Bartender 6"，版本读成 `6`；该页正文多数是 `<h4>` 下的散文，只有末尾 4 条 `<li>`（已知问题）成为条目，
6 个 `<h4>` 成为 heading。6.0.3 页没有列表，落到 `<p>`（1 条）。`ChangelogService.loadDiagnostic(feedPage: nil)`
从 appcast 解析出 `…/6-6-2/rnotes.html`（200），1 条 `6.6.2`、8 条、heading `Fixes`，首条
"Memory usage should no longer creep up over longer sessions for users with triggers enabled."；
`ChangelogService.load(forBundleID:)` 按设计返回 nil（没有更新结果可取页面）。

### Recipes/com-surteesstudios-Bartender.swift — VendorProbe `changelogURL`（2026-10-10 改）

接入前 probe 的 `changelogURL` 是 appcast `www.macbartender.com/B2/updates/AppcastB6.xml`（307 到
`downloads.macbartender.com`）。appcast XML 不是 changelog 页，所以改值；但这个字段只在 probe 自己应答时才用到，
生产上不会：`SourceStack` 里 `SparkleAppcastSource` 排在 `VendorProbeSource` 前，`UpdateChecker` 取第一个应答的源，
`RemoteVersion.changelogURL` = `best.releaseNotesLink`，`ChangelogRecipeSelection.fallbackPage` 用的就是它。
所以 recipe 出不了内容时 pane 嵌的是该版本的 `rnotes.html`；6.1.2、6.1.3、6.2.1、6.3.0、6.3.1、6.4.1 那 6 页是 404，
嵌的就是 404 页——已知缺口，本次不改行为。（本节初稿和那次提交说明写成「pane 会嵌原始 XML」，是错的。）
只读 GET 找人读的页面：
`/Bartender6/support/` 链出 `/Bartender6/release_notes/`（200，9314 B，标题 "Bartender 6 - Release Notes"，
同页列出 6.x 各版说明，最新 6.6.2；另有 "Test Builds" 一节）；`/Bartender6/releasenotes/`、`/Bartender6/changelog/`、
`/B2/updates/` 均 404。改指 `/Bartender6/release_notes/`。它不匹配 `feedPagePattern`，若被用到也只会被嵌入，不会被 recipe 解析。
同一 support 页还链出 `/Bartender7/release_notes/` 与 Bartender 7 的 dmg：Bartender 7 已存在，本次未调查。
