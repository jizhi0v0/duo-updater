# Microsoft OneNote

**这不是审计**：family `com-microsoft-onenote-mac`（`Recipes/com-microsoft-onenote-mac.swift`）里 Microsoft OneNote `com.microsoft.onenote.mac` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-microsoft-onenote-mac.swift — stable VendorProbe（MAU manifest，一键 `FullUpdaterLocation` pkg）

转引自 recipe 注释，未复测。

It used to use the suite fwlink (linkid=525133), on the reasoning that
there is no dedicated OneNote fwlink and the suite reports the same
version. That is true for DETECTION and wrong for INSTALL: that link
serves `Microsoft_365_and_Office_<build>_Installer.pkg`, which declares
eight destinations — Word, Excel, PowerPoint, Outlook, OneNote, OneDrive,
AutoUpdate and a Defender shim. Someone who has only OneNote installed
and clicks Update would have had the entire Office suite put on their
machine. Verified 2026-08-19 by parsing the real 2.7 GB suite package.

`FullUpdaterLocation` in the MAU manifest is a standalone 592 MB
OneNote package that declares exactly one destination,
`/Applications/Microsoft OneNote.app` (verified the same way), signed
`Developer ID Installer: Microsoft Corporation (UBF8T346G9)`.

### 2026-10-10 — manifest 换主机（与 Outlook 同一件事）

`officecdn.microsoft.com/pr/…/0409ONMC2019.xml` 仍返回 200，但停在 `16.109.26053122`（manifest 日期 2026-05-31）。`res.public.onecdn.static.microsoft/mro1cdnstorage/` 同路径是 `16.113.26100421`（2026-10-04），App ID 仍为 `ONMC2019`。recipe 的 `url` 已改到新主机，正则未改。新主机上 `FullUpdaterLocation` 解析到 `Microsoft_OneNote_16.113.26100421_Updater.pkg`：200，628294615 字节，签名 `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`，pkg-ref 只有 `com.microsoft.onenote.mac`，`customLocation="/Applications"`，bundle 16.113.4 / 16.113.26100421。各主机对比表、官方文档出处、对用户的影响见 [Outlook 的同日记录](com-microsoft-Outlook.md#历史与实测)。

真机一键 2026-10-10：16.109.26053122（不运行）→ `duo install` 打开 Installer.app 装 `Microsoft_OneNote_16.113.26100421_Updater.pkg` → 16.113.26100421，签名/公证/receipt 均通过。细节见 [Outlook 的同日记录](com-microsoft-Outlook.md#历史与实测)。
