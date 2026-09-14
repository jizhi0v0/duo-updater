# Sublime Text 4

**这不是审计**：family `com-sublimetext-4`（`Recipes/com-sublimetext-4.swift`）里 Sublime Text `com.sublimetext.4` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-sublimetext-4.swift — stable VendorProbe（HTML 抓取）

转引自 recipe 注释，未复测。整段原文。括号里的理由和末句 "Detection only." 是（c），见下面的更正；其余原样留在代码里。

Sublime Text 4 — self-updates, so it reaches us here. NOTE: HTML scrape
(no usable API: the /updates/.../updatecheck endpoint 404s and the cask
has no livecheck). The /download page is server-rendered: its latest
marker `<p class="latest"><i>Version:</i> Build 4200</p>` precedes the
descending history, so the FIRST "Build NNNN" is newest. CRITICAL:
capture the FULL "Build NNNN" string, not the bare 4-digit build — the
installed CFBundleShortVersionString is literally "Build 4200" (with the
space), and VersionComparator ranks a number above adjacent text, so a
bare "4200" vs "Build 4200" reads as a perpetual phantom update. Keeping
the "Build " prefix makes it compare like-for-like. Detection only.

更正 2026-09-14：`sublime-text` cask 有 livecheck（cask 历史里 2024-11-25 就有 "sublime-text: update livecheck"，早于这句注释），读的是 `https://www.sublimetext.com/updates/4/stable_update_check`，只读 GET 回 200、`"latest_version": 4200`——一个裸数字，不是 bundle 报的 "Build NNNN"；代码里改成了这个说法。原文说 404 的那个 "/updates/.../updatecheck" 地址认不出是哪一个，没有核对。"Detection only." 也不成立：这条 recipe 自 `f656fbb1`（2026-08-09）起带 zip 一键安装。

### Recipes/com-sublimetext-4.swift — stable VendorProbe（一键 zip）

转引自 recipe 注释，未复测。

One-click verified 2026-08-09 on build 4200: `Sublime Text.app` in the
archive, bundle id and Team (Z6D26JE4Y4) matching the installed copy,
its CFBundleShortVersionString literally "Build 4200" like the probe's
value, spctl "Notarized Developer ID".
