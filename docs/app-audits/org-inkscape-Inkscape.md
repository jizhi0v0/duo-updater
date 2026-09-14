# Inkscape

**这不是审计**：family `org-inkscape-Inkscape`（`Recipes/org-inkscape-Inkscape.swift`）里 Inkscape `org.inkscape.Inkscape` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-inkscape-Inkscape.swift — VendorProbe（一键 dmg 的地址）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（下载页经 meta refresh 跳到带 release id 的 gallery 路径，模板猜不到；同一文件在媒体主机上有按版本命名的路径，checked 2026-08-16）；「以前这里说 dmg 拿不到」的经过、1.4.4 那个 gallery id、两个版本的应答与字节数搬到这里。

ONE-CLICK via `.versionTemplate`. An earlier note here said the dmg was
unreachable, because the download PAGE hands the file out through an
HTML `<meta http-equiv="Refresh">` to `/gallery/item/<id>/…` with a
per-release id (59498 for 1.4.4_arm64) that no template can predict.
That was the wrong place to look: the same file also sits at a plain
version-named path on the media host, no gallery id involved —
`media.inkscape.org/dl/resources/file/Inkscape-<ver>_arm64.dmg`
(2026-08-16: 1.4.4 → 200, 156,920,591 B; 1.4.3 → 200).

### Recipes/org-inkscape-Inkscape.swift — VendorProbe（挂载核对与架构）

转引自 recipe 注释，未复测。整段原文。前面带日期的挂载核对原样留在代码里，同段加了 `snapshot-lint:allow` 标记：`Recipes/dev-commandline-waveterm.swift` 的「2026-08-16 vendor batch」那段点名了本文件，说每个被点名的文件都写明从产物上读到的内容（同 iStat Menus、Termius stable、Wave 的做法）。末句 "so an Intel Mac is refused by the runnable-arch gate rather than handed a build it can't run" 按当前代码不成立，代码里改写了，见下面的更正。

Verified 2026-08-16 by mounting the 1.4.4 dmg: `Inkscape.app`,
org.inkscape.Inkscape, CFBundleShortVersionString `1.4.4` — same scheme
the redirect publishes — Team SW3D6BB6A6 (Rene de Hesselle, who also
signs Meld, `Recipes/org-gnome-Meld.swift`), notarized Developer ID, spctl accepted. arm64-only
artifact, so an Intel Mac is refused by the runnable-arch gate rather
than handed a build it can't run.

更正 2026-09-14：DuoUpdater 只有 arm64 构建（`App/project.yml:23` `ARCHS: arm64`），没有 Intel 宿主，所以「Intel Mac 被 runnable-arch 闸拒掉」这条路径不存在。代码里改成：arm64-only 的产物，正是 DuoUpdater 运行的每一台宿主（`App/project.yml`，`ARCHS: arm64`）。

### Recipes/org-inkscape-Inkscape.swift — ChangelogRecipe（为什么 item pattern 只收裸 `<li>`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（放开属性会把整棵导航读成 "changes"），1.4.4 页上 TOC 条目与真实条目的计数和抓取日期搬到这里。

The item pattern matches a BARE `<li>` on purpose. MediaWiki's table of
contents is a nested list whose items all carry
`class="toclevel-N tocsection-N"`, and the page footer's are
`<li id="footer-info-…">` — allowing attributes would turn the whole
navigation into "changes" (35 TOC entries against 116 real ones on the
1.4.4 page, captured 2026-08-16).
