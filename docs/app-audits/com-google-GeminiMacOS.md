# Gemini

**这不是审计**：family `com-google-GeminiMacOS`（`Recipes/com-google-GeminiMacOS.swift`）里 Gemini `com.google.GeminiMacOS` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-google-GeminiMacOS.swift — stable VendorProbe（Omaha `update2/json`）

转引自 recipe 注释，未复测。唯一的改写：原文 "on the installed copy" 与 "The installed app reports" 按本目录的机器状态规则改成了针对那台被量的机器的说法。第三段原句没写日期；它紧挨着 "(Checked 2026-08-22.)"，引入它的提交也是 `0afc3ef4`（2026-08-22）。

The
published download URL carries no version (`.../release2/Gemini.dmg`,
unchanged across releases so far) and the download page answers a plain
fetch with Google's bot challenge (302 → /sorry, observed 2026-08-16),
so nothing reachable states a version.

Verified 2026-08-16 on the copy installed on the machine verified that day: manifest `1.94.11.734`
against `CFBundleShortVersionString` 1.94.11.734 — the same scheme, so
no build-vs-marketing trap here.

The app installed on the machine checked that day
reports 1.96.4.775, so nothing on that page can ever line up with
the version on this row.

(Checked 2026-08-22.)
