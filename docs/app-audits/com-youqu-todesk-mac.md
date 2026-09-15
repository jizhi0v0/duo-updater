# ToDesk

**这不是审计**：family `com-youqu-todesk-mac`（`Recipes/com-youqu-todesk-mac.swift`）里 ToDesk `com.youqu.todesk.mac` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-youqu-todesk-mac.swift — VendorProbe（下载页锚点、灰度风险与没有 changelogURL）

转引自 recipe 注释，未复测。整段原文；（原注释整块没有空行，是一段。）代码里留下的是结论：版本字段是裸变量、pkg 文件名是唯一稳定的字面量、DaaS 链接以 `ToDesk_D…` 开头所以被排除、位置参数里的日期不能当锚、一键按捕获的版本拼 URL、macOS 更新日志页已停更。搬到这里的是：旧锚点的例子与 2026-07-13 的变化经过、位置参数块与 DaaS 链接的具体版本、macOS 更新日志页的条数与版本、Windows 页的日期。「the only `ToDesk_<digits>.pkg` on the page is the consumer GA build」和 Residual risk 一句迁移时已不成立，见下面的更正。唯一的改写：一处本机状态措辞（那台机器装的具体版本），按本目录的机器状态规则改成了针对那台被检查的机器的说法；原句没写日期，这里的 2026-08-22 取自引入那句的提交 `0afc3ef4`。

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
installed on the machine checked on 2026-08-22 is 4.10.0.0. It is not the whole site going stale: the same
host's `windows/uplog.html` was current to 2026.8.18 on the same day.
Pointing the pane at it would show notes for a version the user passed
two minor releases ago, which is the version-mismatch failure the
Notion and Figma changelogs were just moved away from.

更正 2026-09-14：灰度通道已经回到了 `ToDesk_<digits>.pkg` 这个名字、而且排在 GA 前面——正是 Residual risk 预想的情形，但灰度包比 GA **新**，不是「stale-but-real … under-reporting」。一键模板用捕获到的版本拼 `https://dl.todesk.com/macos/ToDesk_{0}.pkg`，拼出来的就是灰度包的地址。代码里改写成当前情形，「rebuilds the GA URL」改成「rebuilds the URL」，并删去那台机器装的版本。

复测 2026-09-14（11:04 UTC，只读 GET，Safari UA；没有核对 app 自己的 UA 是否拿到同样的 body）：`www.todesk.com/download.html` 76,446 B，按 `ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg` 依次匹配到 `5.1.0.0`（`mac_link_gray:"https://dl.todesk.com/macos/ToDesk_5.1.0.0.pkg"`）和 `4.10.1.0`（位置参数块，前面紧挨着日期 `"2026.8.28"`）；DaaS 链接是 `ToDesk_DaaS_v1.1.0.1.pkg` 与 `ToDesk_DaaS-v1.1.0.1_392.pkg`；版本字段是 `mac_version:k`、`mac_version_gray:c`（仍是裸变量）。`update.todesk.com/macos/uplog.html` 7,398 B，最新 `4.8.1.0`（2025.9.5）；`update.todesk.com/windows/uplog.html` 23,792 B，最新 `5.0.2.0`（2026.8.31）。

复测 2026-09-14（12:55 UTC，同一页，只读 GET）：按 `window.__NUXT__` 的参数表还原，`mac_version` = `4.10.1.0`、`mac_version_gray` = `5.1.0.0`、`mac_gray_percent` = `"10"`、`mac_release_date` = `2026.8.28`——厂商只把 5.1.0.0 推给 10% 的用户，而这条 recipe 读到的是灰度包（字段名后面的单字母变量名每次请求不同）。

### Recipes/com-youqu-todesk-mac.swift — VendorProbe（改读配置 API，只取 GA）

2026-09-14。上面两条复测之后 recipe 从下载页换到配置 API、只读 GA 行；代码里留下的是契约（行名锚点、为什么不读 `_gray`、为什么不读下载页、一键用解析出的版本拼 URL、已在灰度线上的拷贝会怎样）。下面是做这个决定时量到的东西。

**红**（只读 GET，`VendorProbeSource` 的 Safari UA）：`www.todesk.com/download.html` 解压后 74,534 B；旧 pattern `ToDesk_([0-9]+(?:\.[0-9]+)+)\.pkg` 依次匹配 `5.1.0.0`、`4.10.1.0`，first-match 取 `5.1.0.0`。`window.__NUXT__` 的形参 `a…F` 按实参还原：`mac_version:l` → `4.10.1.0`、`mac_release_date:m` → `2026.8.28`、`mac_link:n` → `https://dl.todesk.com/macos/ToDesk_4.10.1.0.pkg`、`mac_version_gray:c` → `5.1.0.0`、`mac_gray_percent:f` → `"10"`；`mac_link_gray` 是字面量 `…/macos/ToDesk_5.1.0.0.pkg`。变量 `n` 在 body 里被 `mac_link` 和 `mac_link_new` 两处引用——GA 链接进位置参数是因为这两个字段恰好同值，所以下载页上没有一个锚点能说"这是 GA 字段"。

**配置 API**：页面 JS 里 `/dist/1812cb8.js` 定义 `getConfig:"/api/config/getConfig"`，`/dist/62a4a83.js` 以 `{params:{type:1}}` 调用、返回值映射成页面的 `clientInfo`；灰度由 `dealGray` / `setMacGray` 拿 `$cookies` 算的桶跟 `*_gray_percent` 比（`setMacGray` 也在 `1812cb8.js`）。经 URLSession（Safari UA）`GET https://www.todesk.com/api/config/getConfig?type=1`：200、`application/json; charset=utf-8`、10,013 B、无 `Cache-Control` / `ETag`，`data.list` 114 行，`{"id","type","name","value"}`。mac 相关行：`mac_version` 4.10.1.0（id 8）、`mac_release_date` 2026.8.28、`mac_link` …/ToDesk_4.10.1.0.pkg（id 10）、`mac_link_new` 同值（id 67）、`mac_gray_percent` 10（id 78）、`mac_link_gray` …/ToDesk_5.1.0.0.pkg（id 80）、`mac_version_gray` 5.1.0.0（id 81）、`daas_mac_*` 1.1.0.1（gray percent -1）、`mac_downloader_version` 4.10.1.0 / `_gray` 5.1.0.0（gray percent 30，`…/official/ToDesk_Installer.dmg`）。新 pattern 在这份 body 上只匹配一次 `4.10.1.0`；旧的 pkg 文件名 pattern 在它上面依次是 `4.10.1.0`、`4.10.1.0`、`5.1.0.0`——按 id 序 GA 恰好在前，这是回归测试要把灰度行挪到前面再断言一遍的原因。

**一键拿到的是不是 pkg**：`curl`（UA `DuoUpdater/0.1` 或 Safari UA，都经本机代理；`DuoUpdater/0.1` 另用 `--noproxy` 跑过一次，结果相同，Safari UA 没有这样跑过；Surge 对 `.todesk.com` 的规则是 DIRECT）GET 两个 pkg URL 都拿到 200 `text/html` 2,174–2,175 B 的 Tencent EdgeOne「Security Verification」验证码页，`pkgutil --check-signature` 对它报 `Could not open package`。换成生产客户端 URLSession、同样的 `User-Agent: DuoUpdater/0.1` + `Accept-Encoding: identity`，只读头和前 64 字节：`ToDesk_4.10.1.0.pkg` 200、`Content-Type: text/plain`、`Content-Length` 376,661,630，开头 `xar!`；`ToDesk_5.1.0.0.pkg` 同样 `xar!`、410,812,880。和 `PackageInstaller.swift` 那段「curl is not a stand-in」的记录一致，一键没有问题。

**已被推上灰度线的拷贝**（per-copy）：2026-09-14 检查的那台机器上装的那份拷贝是 `5.0.0.0`，是 2026-08-31 16:12:38 UTC 经 Vendor 源从 `4.10.1.0` 装上的（下载 403,500,628 B），也就是旧 recipe 推的灰度包。GA 读法下这份拷贝比 feed 新，收不到 5.1.0.0，`duo verify` 在那台机器上报 remote behind installed。按拷贝判轨的规则拆到 #628。

改写 2026-09-15：上面这一段有一处本机状态措辞（安装路径与那台机器的记录来源），按本目录的机器状态规则改成了针对那份拷贝的说法；版本、日期、字节数与结论不变。

**baseline**：`verify/baseline.json` 的 `vendor:com.youqu.todesk.mac:stable` 从 `5.1.0.0` 改成 `4.10.1.0`。不改的话下一轮巡检报「version went BACKWARDS」，而 `Baseline.reconcile` 拒绝记下更低的值，警告会每轮重复（同 #622 对 Raycast 的处理）。
