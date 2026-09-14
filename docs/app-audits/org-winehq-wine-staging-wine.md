# Wine Staging

**这不是审计**：family `org-winehq-wine-staging-wine`（`Recipes/org-winehq-wine-staging-wine.swift`）里 Wine Staging `org.winehq.wine-staging.wine` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-winehq-wine-staging-wine.swift — staging GitHubReleaseRule（只检测的原因）

转引自 recipe 注释，未复测。整段原文。"ship as `.tar.xz`, which the installer doesn't unpack" 按当前代码不成立，代码里改写了，见下面的更正；其余原样，重新折行。

Wine (staging) — Gcenx's macOS builds are unsigned, and ship as `.tar.xz`,
which the installer doesn't unpack. Detection only. Each release tags one
upstream version and carries BOTH a `wine-devel-` and a `wine-staging-`
tarball, so this rule is safe for the staging bundle id — see the note
below for why the stable bundle id gets no rule.

更正 2026-09-14：这句写下时（`3edaa6fb`，2026-08-16）就已不成立。`VendorInstaller` 对 `.tarGz` 把下载改名成 `download.tar.gz`（`Install/VendorInstaller.swift:317`），`ArchiveExtractor` 对 `gz`、`xz` 等扩展名一律走 `tar -xf`（`Install/ArchiveExtractor.swift:61`、`:129`），不带压缩参数，tar 自己识别 xz；`Recipes/net-pornel-ImageOptim.swift` 的一键 `.tar.xz` 就靠这条，自 `1ad22b24`（2026-08-09）起。只检测的真实原因是包没签名（本 family 登记在 `Recipes/org-alacritty.swift` 的 Detection-only 共享说明下）。代码里改成：没签名才是只检测的原因，`.tar.xz` 不是阻碍。没有下载 tarball 核对里面是不是一个 `.app`（`gh api 'repos/Gcenx/macOS_Wine_builds/releases?per_page=5'` 只看到资产名 `wine-devel-11.17-osx64.tar.xz` 与 `wine-staging-11.17-osx64.tar.xz`）。

### Recipes/org-winehq-wine-staging-wine.swift — stable 为什么不接

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（这个仓库的 release 是 devel/staging 轨，stable 装机在另一条老得多的线上），两条线的版本号搬到这里（devel/staging 那个带 2026-08-16，stable 那个原句没写日期，引入它的提交是 `3edaa6fb`，2026-08-16）；其余原样，重新折行。

Deliberately NOT covered — Wine (stable), `org.winehq.wine-stable.wine`.
The same repo's releases are the devel/staging train (11.15 on
2026-08-16) while a stable install sits on its own much older line
(11.0_1). A rule keyed on `/releases/latest` would tell every stable user
that a devel build is their update. Distinguishing the trains needs
per-asset filtering (`wine-stable-*`), which a release rule can't express.

复测 2026-09-14（13:57 UTC，`gh api 'repos/Gcenx/macOS_Wine_builds/releases?per_page=5'`）：最新 5 个 release 依次是 `11.17`（2026-09-11）、`11.16`、`11.15`（2026-08-08）、`11.14`、`11.13`，都没标 prerelease。stable 那条线没有复测。
