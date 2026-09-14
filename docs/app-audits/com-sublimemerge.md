# Sublime Merge

**这不是审计**：family `com-sublimemerge`（`Recipes/com-sublimemerge.swift`）里 Sublime Merge `com.sublimemerge` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-sublimemerge.swift — stable VendorProbe（HTML 抓取与 "Build NNNN"）

转引自 recipe 注释，未复测。整段原文。代码里："no usable API" 和末句 "Detection only." 是（c），见下面的更正；"Build 2125" 改成了示例；末尾那句改写成描述值的形状，不再说到某份拷贝。

Sublime Merge — self-updates, so it reaches us here. NOTE: HTML scrape
(no usable API; mirrors the Sublime Text 4 recipe in `Recipes/com-sublimetext-4.swift` — same vendor,
same page shape). The /download page's latest marker
`<p class="latest"><i>Version:</i> Build 2125</p>` precedes the descending
history, so the anchored "Build NNNN" is newest. CRITICAL: capture the
FULL "Build NNNN" string — installed CFBundleShortVersionString is
literally "Build 2125", and a bare "2125" would read as a perpetual
phantom update (VersionComparator ranks a number above adjacent text).
Builds are 2xxx (not 4xxx like Sublime Text); the class="latest" anchor
already makes it single-match. Detection only.

更正 2026-09-14：Homebrew 的 `sublime-merge` cask 的 livecheck 读 `https://www.sublimemerge.com/updates/stable_update_check`，那是厂商的 JSON 更新检查，只读 GET 在 07:24 UTC 回 `"latest_version": 2125`、09:08 UTC 回 `2130`——只给裸数字，不是没有接口；代码里改成了「同样的裸数字 JSON 更新检查」。"Detection only." 也不成立：这条 recipe 自 `1ad22b24`（2026-08-09）起带 zip 一键安装。

### Recipes/com-sublimemerge.swift — stable VendorProbe（一键 zip）

转引自 recipe 注释，未复测。整段原文；除末句核对记录外都原样留在代码里。

Same shape as Sublime Text: the page ships the download link as the
literal template `sublime_merge_build_${version}_mac.zip` for JS to
fill, so it's rebuilt from the same "latest" marker, taking the BARE
build number (the version keeps its "Build " prefix to match what the
bundle reports; a URL can't carry it). Verified 2026-08-09 on build
2125: `Sublime Merge.app`, Team Z6D26JE4Y4, accepted by spctl.

复测 2026-09-14（约 09:08 UTC，只读 GET）：`www.sublimemerge.com/download` 的 latest 标记是 `Build 2130`（页上日期 14 September 2026），`/updates/stable_update_check` 回 `"latest_version": 2130`。代码里的 "Build 2125" 因此标成了示例。没有下载 2130。
