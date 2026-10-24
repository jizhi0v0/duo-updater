# Gemini

**这不是审计**：family `com-google-GeminiMacOS`（`Recipes/com-google-GeminiMacOS.swift`）里 Gemini `com.google.GeminiMacOS` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-google-GeminiMacOS.swift — stable VendorProbe（Omaha `update2/json`）

转引自 recipe 注释，未复测。唯一的改写：第二段和第三段各一处本机状态措辞（核对所在的拷贝、那份拷贝报出的版本），两处都按本目录的机器状态规则改成了针对那台被量的机器的说法。第三段原句没写日期；它紧挨着 "(Checked 2026-08-22.)"，引入它的提交也是 `0afc3ef4`（2026-08-22）。

The
published download URL carries no version (`.../release2/Gemini.dmg`,
unchanged across releases so far) and the download page answers a plain
fetch with Google's bot challenge (302 → /sorry, observed 2026-08-16),
so nothing reachable states a version.

复测 2026-09-14（05:18 UTC，只读 GET，不跟随重定向，默认 UA 与 Safari UA 各一次）：`https://gemini.google.com/download` 两次都回 404，没有 `Location`——不再是 302 到 /sorry。代码里只留下「没有能访问到的页面给出版本号」。

复测 2026-09-14（05:29–05:31 UTC，只读 GET/HEAD，不跟随重定向）：只用 Safari UA 请求的——`gemini.google.com/mac`、`gemini.google.com/download/mac` 同样 404；`gemini.google/mac` 与 `gemini.google/mac/` 301 到 `https://gemini.google/desktop/`。默认 UA 与 Safari UA 各一次的——`/desktop/` 200，标题 "Gemini for desktop: download the AI app for Windows & macOS"，全文没有版本号。`downloadURL` 因此改成这一页。页上 "Download for macOS" 按钮是 `/download/mac/`，它 302 到 `https://dl.google.com/release2/j33ro/release/Gemini.dmg`——不拿它当 `downloadURL`：“Open page” 打开它会直接下载文件，而 `PageURLTests` 只看扩展名，看不出来。同一时刻 Omaha 那条 POST 回 200，manifest `1.113.6.866`，拼出 `https://dl.google.com/release2/gemini/jkwdnlueryriaqpop7vitq2c7i_1.113.6.866/Gemini-1.113.6.866.dmg`，HEAD 200、`content-length` 139838410 与 manifest 的 `size` 一致（没下载）。回应比 2026-08-16 的 fixture 多了 `actions` 块和 `www.google.com/dl` 两个 codebase，两条字段 pattern 取到的仍是上面这个 URL。

复测 2026-09-14（07:18 UTC，同样只读、不跟随重定向，默认 UA 与 Safari UA 各一次，本机经代理出网）：`gemini.google.com/download`、`gemini.google.com/mac` 两个 UA 都 302 到 `www.google.com/sorry`——两小时前还是 404。所以旧域名这几个路径在 404 和 bot 验证之间来回变，哪一种都不是能给人打开的页；`gemini.google/mac`、`/mac/` 默认 UA 下也是 301 到 `/desktop/`，`/desktop/` 两个 UA 仍 200。

Verified 2026-08-16 on the copy installed on the machine verified that day: manifest `1.94.11.734`
against `CFBundleShortVersionString` 1.94.11.734 — the same scheme, so
no build-vs-marketing trap here.

The app installed on the machine checked that day
reports 1.96.4.775, so nothing on that page can ever line up with
the version on this row.

(Checked 2026-08-22.)

### Recipes/com-google-GeminiMacOS.swift — 一键接上 sha256（2026-10-07）

原注释里「manifest 有 sha256 但用不上」不再成立：`VendorInstallSpec.checksumFormat: .sha256Hex`（#1016）之后，下载会先对包条目的
`hash_sha256` 核对。

实测（2026-10-07，按 recipe 的请求体 POST `update.googleapis.com/service/update2/json`）：manifest `1.128.2.1001`，`packages.package`
只有一个条目，键依次是 `hash_sha256, size, name, fp, required, hash`；`actions` 块里也出现同一个 dmg 名（键是 `run`）。下载
`dl.google.com/…_1.128.2.1001/Gemini-1.128.2.1001.dmg`（176,602,023 B，等于 `size`）后实算：SHA-256 等于 `hash_sha256`
（`37f5a9bd…9bb1`），base64 SHA-1 等于 `hash`（`XFUQOg+le3g42ptq+6mg9w6Z4is=`）。`duo install Gemini` 1.113.6.866 → 1.128.2.1001：
`extracting` 前出现 `verifyingSignature`（摘要闸），安装成功，`spctl` accepted，Notarized Developer ID，Google LLC (EQHXZ8M8AV)。

### Recipes/com-google-GeminiMacOS.swift — 灰度按 Omaha `cohort` 分组，请求体回显上次回复分配的 cohort（2026-10-24，#1621）

#1621：一键更新在安装前复查时报 "The update source answered 1.135.1.1291, then 1.131.4.1198 — nothing was installed."，即 `PreInstallGate` 的 `.answerRegressed`，闸本身按设计工作。

实测（2026-10-24 ~02:00 UTC，按 recipe 原请求体 POST `update.googleapis.com/service/update2/json`）：

- 不带 `cohort`：20 次里 12 × `1.131.4.1198`（`cohortname` "Prod"，回 `cohort` `1:3j3x:3wu9@0.3`）、8 × `1.135.1.1291`（"Rollout - Prod"，`1:3j3x/3wu9:`）。
- 固定 `userid`、或固定 `requestid` + `sessionid`：仍随机（8:2、9:1）。
- 带 `cohort: "1:3j3x:3wu9@0.3"`：15/15 `1.131.4.1198`；带 `"1:3j3x/3wu9:"`：15/15 `1.135.1.1291`。
- 带本机旧值 `1:3j3x:3wu9@0.1`、`1:3j3x:`、`1:3j3x:3wu9`、`garbage`、空串：各 10 次都重新抽签（5:5 到 8:2）。所以只有服务端当期刚发的 cohort 是粘的，写死任何一个都会在下次灰度比例变化后失效。

包内部（`/Applications/Gemini.app` 1.135.1.1291）：

- `Info.plist` 只有 `KSChannelID` = `m1-prod`（即请求里的 `tag`）。
- 二进制里有自带的 Omaha 更新器（`googlemac/Janus/MacApplication/Components/Updater/OmahaUpdater/OmahaService.swift`，同一端点；`checkForUpdate(appId:currentVersion:tag:platform:)` 签名里没有 cohort，持久化键只有 `com.google.Gemini.OmahaMetrics.*`）。它由 `app_useOmahaUpdater` 开关控制，本机 `com.google.GeminiMacOS` 与 `group.com.google.gemini` 里都是 `{"defaultValue":{"_0":false}}`——关着。它不发 cohort，见下面的抓包。
- 本机实际更新 Gemini 的是系统 GoogleUpdater：`~/Library/Application Support/Google/GoogleUpdater/prefs.json` → `updateclientdata.apps["com.google.geminimacos"]` 存 `cohort`、`cohortname`、`pv`。`updater_history.jsonl` 里它的 cohort 从 `1:3j3x:` → `1:3j3x:3wu9@0.1`（pv 1.131.4.1198），之后某次检查被抽进 `1:3j3x/3wu9:`（"Rollout - Prod"），装上 1.135.1.1291。`/Library/Application Support/Google/GoogleUpdater` 本机不存在。

抓包（用户提供，2026-10-24 06:52Z，macOS 26.7 的另一台 Mac）：app 自带更新器与 `GeminiAppLauncher` 各 POST 一次同一端点，请求体只有 `appid`、`version`（已装的 1.135.1.1291）、`tag`、`ping`（含 `ping_freshness`）、`os`——**不带 `cohort`**。所以走 app 自带更新器的 Mac，Gemini 自己每次检查也是重新抽签；没有「本机 cohort」可读。回复是 `cohort` `1:3j3x:`、"Prod"、`noupdate`。

为什么没用 GoogleUpdater 存的 cohort（先实现过，复审后撤回）：GoogleUpdater 被分进 Rollout 的那次回复同时带了更新（`status: ok`），它随即自己装上新版；存的 cohort 是当期 Prod 时 duo 答旧版＝已装版，不出 offer。duo 真正会出 offer 的只剩存的 cohort 过期、每次重抽的情形，复查照样约 1−p 概率倒退。app 自带更新器的 Mac 上则根本没有可读的值。

灰度结束：07:00Z 起原请求体（无 cohort）20/20 `1.135.1.1291`，`cohort` `1:3j3x:`、"Prod"。官网的不带版本号地址 `dl.google.com/release2/j33ro/release/Gemini.dmg` HEAD 10 次一致：`content-length` 256237111（等于 1.135.1.1291 包的 `size`），`last-modified` 05:49:16Z——它跟的是全量版，灰度期间停在旧版。同一时刻 Chrome（同一服务）在灰度：不带 cohort 20 次 11 Stable / 5 "156.0.8078.47 Rollout" / 4 Control；回显 Rollout、Stable 各 10/10 不变。服务端回的 cohort 可以与送去的不同（送 `1:1y5/3wo9:3vo3@0.0,3wol@0.5,3w59@0.0`，回 `1:1y5/3wo9:3wol@0.5`），所以每次回复都要重新存。

改法：请求体加 `"cohort":"__COHORT__"`，填上次回复分配的值（`RequestBody.EchoedField`，存在 `EchoedFieldStore`，菜单栏与 `duo` 共用一个文件）；什么都没存时填空串，等于改动前的请求（协议文档写请求的 `cohort` "Default: \"\""；回复的 `cohort` "The client should update the cohort of this application to the new value"——<https://chromium.googlesource.com/chromium/src/+/main/docs/updater/protocol_3_1.md>，2026-10-24 用 curl 取原文核对）。检查拿到的 cohort 被复查原样送回，两次由同一组回答。代价：灰度期间 duo 可能比本机 Gemini 自己的更新器先看到新版（同一个官方签名包）。
