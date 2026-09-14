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
