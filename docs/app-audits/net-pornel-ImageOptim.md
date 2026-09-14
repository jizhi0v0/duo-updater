# ImageOptim

**这不是审计**：family `net-pornel-ImageOptim`（`Recipes/net-pornel-ImageOptim.swift`）里 ImageOptim `net.pornel.ImageOptim` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/net-pornel-ImageOptim.swift — VendorProbe（检测已被 Sparkle 接管）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论和日期（真实 bundle 声明的 `SUFeedURL` 就是这个地址，所以 Sparkle 先应答），被量的版本 1.9.3 搬到这里。

DEAD FOR DETECTION, kept as a sweep anchor — same as Bartender (`Recipes/com-surteesstudios-Bartender.swift`).
Measured on the real 1.9.3 bundle (2026-08-31): it declares
`SUFeedURL = https://imageoptim.com/appcast.xml`, this exact address, so
Sparkle answers first and this row only keeps the endpoint in the sweep.

### Recipes/net-pornel-ImageOptim.swift — VendorProbe（一键 `.tar.xz` 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（归档里是 `ImageOptim.app`、bundle id、Team 59KZTZA4XR、spctl 接受，checked 2026-08-09），被核对的版本 1.9.3 搬到这里；`.tarGz` 能解 xz 那句原样留下。

One-click verified 2026-08-09 on 1.9.3: `ImageOptim.app` in the
archive, bundle id net.pornel.ImageOptim, Team 59KZTZA4XR, accepted by
spctl. The enclosure is a `.tar.xz`, which `.tarGz` handles despite the
name — `VendorInstaller` renames by kind and `ArchiveExtractor` runs
`tar -xf` with no compression flag, so tar sniffs xz itself (checked by
extracting a deliberately misnamed copy).
