# 1Password

**这不是审计**：family `com-1password-1password`（`Resources/Recipes/com-1password-1password.json5`）里 1Password 8 `com.1password.1password` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-1password-1password.swift — stable VendorProbe（一键 `1Password-latest-aarch64.zip`）

转引自 recipe 注释，未复测。

Verified by
downloading the aarch64 one (214,254,924 B): it unzips to `1Password.app`
itself — com.1password.1password, 8.12.33, Team 2BUA8C4S2C, notarized
Developer ID, spctl accepted, arm64.

### Recipes/com-1password-1password.swift — stable VendorProbe + ChangelogRecipe（未写日期的数字）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`a780fb9e`（2026-08-16）、`af657869`（2026-08-16）。

`selectHighest` rather than first-match, because the feed is ASCENDING
(8.7.0 from 2022 is item 1 of 89) — first-match here would report a
four-year-old release as current, which reads as "up to date" forever.

`downloads.1password.com/mac/1Password.zip` looks perfect (stable URL,
Developer ID 2BUA8C4S2C, notarized) and is a trap: it contains
`1Password Installer.app` (`com.1password.1password-installer`, 21 MB), a
stub that fetches the real app.

```
items are ASCENDING (8.7.0 from 2022 first, 89 of them), so
    `newestLast` flips them — the HTML page was newest-first;
```

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`releases.1password.com/mac/stable/index.xml` 有 91 个 `1Password for Mac` 条目，第一个是 `8.7.0`、最后一个是 `8.12.36`。
