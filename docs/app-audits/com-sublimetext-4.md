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

### Recipes/com-sublimetext-4.swift — ChangelogRecipe（版本改成完整的 "Build NNNN"）

实测 2026-10-10。

- 起因：写 Sublime Merge 的 changelog recipe（#1161）时发现，这条 recipe 的条目版本是裸数字 `4215`，而 probe 报的、bundle 自己写的都是 `Build 4215`。
- bundle：用 HTTP Range 只读了 `https://download.sublimetext.com/sublime_text_build_4215_mac.zip`（53301345 字节）里的 `Sublime Text.app/Contents/Info.plist`，读到 `CFBundleIdentifier = com.sublimetext.4`、`CFBundleShortVersionString = "Build 4215"`、`CFBundleVersion = "4215"`。`verify/baseline.json` 里 `vendor:com.sublimetext.4:stable` 记的是 `Build 4215`。
- 页面：当天的 `/download` 有 17 个 `<article>`。旧正则读出 `4215` … `4107`，新正则读出 `Build 4215` … `Build 4107`，条数、日期、条目都一样，只多了前缀。第一版 v4 的标题是 `4 (Build 4107)`，新正则去掉 `4 (` 和 `)`。
- 影响面：原报告说的 `WorkbenchWindowView` 里那个 `isRunning`（`==` 比较），只有 duo 自己的更新日志和 CLI 工具工作台会传 `runningVersion`，app 的厂商 changelog 一律传 nil，所以 Sublime Text 的面板本来就不标「当前版本」，改不改都一样。`Changelog.carries(version:)` 也不受影响：`Build 4215` 不是 version-shaped（含空格），对任何条目都直接返回 true。能看到的差别是条目标题从 `4215` 变成 `Build 4215`，和 probe 报的、bundle 写的是同一种写法（UI 没有开起来看）。
- `duo verify`：lag 检查（`changelogLagComplaint`）要两边都以数字开头，被检测的版本一直是 `Build 4215`，所以改前就跳过；lead 检查（`changelogLeadsProbeComplaint`）要求 probe 行都以数字开头，`Build 4215` 也让它改前就跳过。改后照旧跳过，没有少掉覆盖。
- baseline：只改 recipe 不改 baseline，`duo verify --only sublimetext` 对 baseline 副本报 `version went BACKWARDS since the last sweep (4215 → Build 4215)`，退出码 1；`VersionComparator` 把数字排在文字前面，而且回退的值不会写进 baseline，这条会一直报到 reconcile 开 issue。所以同一个提交里把 `changelog:com.sublimetext.4:-` 的 `lastGoodVersion` 改成 `Build 4215`，重跑退出码 0。把 baseline 副本换成 `Build 4216` 再跑，仍报 `Build 4216 → Build 4215`，说明新写法下回退检查照样有效。
- 缓存：`entryPattern` 改了已缓存版本的解析结果，所以 `Changelog.parserGeneration` 从 17 升到 18，已缓存的 `4215` 条目会被当作未命中重新抓取。
