# ToDesk

**这不是审计**：family `com-youqu-todesk-mac`（`Recipes/com-youqu-todesk-mac.swift`）里 ToDesk `com.youqu.todesk.mac` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-youqu-todesk-mac.swift — VendorProbe（下载页锚点、灰度风险与没有 changelogURL）

转引自 recipe 注释，未复测。整段原文；（原注释整块没有空行，是一段。）代码里留下的是结论：版本字段是裸变量、pkg 文件名是唯一稳定的字面量、DaaS 链接以 `ToDesk_D…` 开头所以被排除、位置参数里的日期不能当锚、一键按捕获的版本拼 URL、macOS 更新日志页已停更。搬到这里的是：旧锚点的例子与 2026-07-13 的变化经过、位置参数块与 DaaS 链接的具体版本、macOS 更新日志页的条数与版本、Windows 页的日期。「the only `ToDesk_<digits>.pkg` on the page is the consumer GA build」和 Residual risk 一句迁移时已不成立，见下面的更正。唯一的改写：一处本机状态措辞（那台机器装的具体版本），按本目录的机器状态规则改成了针对那台被检查的机器的说法。

ToDesk (远程控制) — Hainan Youqu's remote-desktop app. No standard source
resolves it; its in-app appcast sits behind a JS bot-challenge (the reason
it was long left "unknown"). The public download page is the way in: a
Nuxt/Vue SPA whose macOS pkg URL is SERVER-RENDERED into the inline data
blob (no JS needed). ANCHOR ON THE `macos/` pkg FILENAME `ToDesk_<ver>.pkg`.
History: we used to key off a quoted `mac_version:"4.9.7.2"` literal, but
2026-07-13 the vendor variable-ized every macOS version field
(`mac_version:l`, `mac_version_gray:l` — bare vars, no quoted digits), so
that anchor stopped matching → "probe resolved no version". The GA marketing
version now survives only in the positional-arg block
(`("",false,"-1","2026.7.10","…/macos/ToDesk_4.9.7.4.pkg",…`); the pkg
filename is the one durable literal. Two other pkg links share the page —
the DaaS (enterprise) GA `…/daas/mac/ToDesk_DaaS_v1.1.0.1.pkg` and its gray
`ToDesk_DaaS-v1.1.0.1_392.pkg` — but both read `ToDesk_D…`, so anchoring on
`ToDesk_<digit>` excludes them; the only `ToDesk_<digits>.pkg` on the page
is the consumer GA build. NB `2026.7.10` is a release DATE that precedes the
pkg URL — never anchor on it; the real marketing version (==
CFBundleShortVersionString) lives in the filename. Non-build recipe, first
match, no selectHighest.
Residual risk: if the vendor ever moves the consumer GRAY channel back to a
`ToDesk_<digits>.pkg` name that precedes GA in the body, first-match would
grab the (older) gray build — a stale-but-real version, i.e. under-reporting
rather than inventing an update (safe direction). Revisit then.
One-click pkg install rebuilds the GA URL from the captured filename version
(template), on the vendor's own dl.todesk.com, signed by the same Team
KM56KD59W4 (Hainan Youqu Technology) as the installed app — the
VendorInstaller signature gate enforces it.
No `changelogURL`: the vendor's macOS log page exists but is abandoned.
`update.todesk.com/macos/uplog.html` is server-rendered with 30 real
versions, and its newest is 4.8.1.0 (2025.9.5) — while the copy
installed on the machine checked that day is 4.10.0.0. It is not the whole site going stale: the same
host's `windows/uplog.html` was current to 2026.8.18 on the same day.
Pointing the pane at it would show notes for a version the user passed
two minor releases ago, which is the version-mismatch failure the
Notion and Figma changelogs were just moved away from.

更正 2026-09-14：灰度通道已经回到了 `ToDesk_<digits>.pkg` 这个名字、而且排在 GA 前面——正是 Residual risk 预想的情形，但灰度包比 GA **新**，不是「stale-but-real … under-reporting」。一键模板用捕获到的版本拼 `https://dl.todesk.com/macos/ToDesk_{0}.pkg`，拼出来的就是灰度包的地址。代码里改写成当前情形，「rebuilds the GA URL」改成「rebuilds the URL」，并删去那台机器装的版本。

复测 2026-09-14（11:04 UTC，只读 GET，Safari UA；没有核对 app 自己的 UA 是否拿到同样的 body）：`www.todesk.com/download.html` 76,446 B，按 `ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg` 依次匹配到 `5.1.0.0`（`mac_link_gray:"https://dl.todesk.com/macos/ToDesk_5.1.0.0.pkg"`）和 `4.10.1.0`（位置参数块，前面紧挨着日期 `"2026.8.28"`）；DaaS 链接是 `ToDesk_DaaS_v1.1.0.1.pkg` 与 `ToDesk_DaaS-v1.1.0.1_392.pkg`；版本字段是 `mac_version:k`、`mac_version_gray:c`（仍是裸变量）。`update.todesk.com/macos/uplog.html` 7,398 B，最新 `4.8.1.0`（2025.9.5）；`update.todesk.com/windows/uplog.html` 23,792 B，最新 `5.0.2.0`（2026.8.31）。
