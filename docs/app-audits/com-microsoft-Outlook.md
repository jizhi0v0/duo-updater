# Microsoft Outlook

**这不是审计**：family `com-microsoft-Outlook`（`Recipes/com-microsoft-Outlook.swift`）里 Microsoft Outlook `com.microsoft.Outlook` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-microsoft-Outlook.swift — stable VendorProbe（MAU manifest，一键 `FullUpdaterLocation` pkg）

转引自 recipe 注释，未复测。唯一的改写：原文 "the same Team as the installed app" 按本目录的机器状态规则改成了针对那台被量的机器的说法。

One-click repaired 2026-08-09. The old install spec read
`<key>Update Version Location</key>`, a key Microsoft has since removed
— the version still resolved, so the row quietly degraded to
detection-only with no error anywhere. Today's payload keys, and what
each actually points at (verified against the live manifest):

```
  Location / Payload      → `Outlook_<baseline>_to_<new>_Delta.pkg` on
                            the 24 delta entries — a PARTIAL payload
                            (504MB, 185 bundles, installKBytes 1117435)
  BinaryUpdaterLocation   → `…_BinaryDelta.pkg`, a 18–216MB binary patch
  FullUpdaterLocation     → `Microsoft_Outlook_<build>_Updater.pkg`, the
                            full standalone package (1.29GB, 210 bundles,
                            installKBytes 2664652, choice customLocation
                            /Applications)
```

Signed `Developer ID Installer: Microsoft
Corporation (UBF8T346G9)`, the same Team as the app installed on the machine checked that day (read from
the pkg's xar signature 2026-08-09, no full download needed).

复测 2026-09-14（03:15 UTC，只读 GET `0409OPIM2019.xml`）：manifest 里的 payload URL 都在 `res.public.onecdn.static.microsoft`（另有 `go.microsoft.com` 链接），payload 键是 `BinaryUpdaterLocation` / `FullUpdaterLocation` / `Location`；第一个 dict 的 `Update Version` 是 `16.109.26053122`，`FullUpdaterLocation` 是 `…/Microsoft_Outlook_16.109.26053122_Updater.pkg`；`_Delta.pkg` 这个串出现 48 次（没有按 entry 去数）。没有复查包大小与 bundle 数。
