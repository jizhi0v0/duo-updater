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
AutoUpdate and a Defender shim.

Verified 2026-08-19 by parsing the real 2.7 GB suite package.

`FullUpdaterLocation` in the MAU manifest is a standalone 592 MB
OneNote package that declares exactly one destination,
`/Applications/Microsoft OneNote.app` (verified the same way), signed
`Developer ID Installer: Microsoft Corporation (UBF8T346G9)`.
