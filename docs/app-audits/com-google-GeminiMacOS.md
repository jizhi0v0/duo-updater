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
