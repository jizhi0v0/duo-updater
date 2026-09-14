# UURemote（网易UU远程）

**这不是审计**：family `com-netease-uuremote`（`Recipes/com-netease-uuremote.swift`）里 UURemote `com.netease.uuremote` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-netease-uuremote.swift — stable VendorProbe（Homebrew cask 为什么接不住）

转引自 recipe 注释，未复测。唯一的改写：末句一处本机状态措辞（那份拷贝的安装来源），按本目录的机器状态规则改成了针对写这句话时那台机器的说法。代码里同一处（类别：那份拷贝的安装来源）改写成了不点名任何一台机器的条件：cask 接不住直接从厂商装的拷贝。

The Homebrew cask can't cover this: its provenance gate (correctly) only
adopts apps brew actually installed, and the copy on the machine this was written on had been installed directly.

### Recipes/com-netease-uuremote.swift — stable VendorProbe（一键 pkg 与 changelog 页）

转引自 recipe 注释，未复测。整段原文，代码里留下的是 `.pkg` 交给系统安装器那几句，以及「2026-08-22 检查时没找到 changelog 页」这个结论。

One-click verified 2026-08-09 on the 4.35.0 package: `pkgutil
--check-signature` reports "Developer ID Installer: Hangzhou Bobo
Technology Co Ltd (PU9BNSBJW7)" — the same team as the installed bundle —
notarized, with a trusted timestamp. A `.pkg` hands off to macOS's own
installer, so the user still confirms it there (same flow as ToDesk and
AweSun); the install spec re-resolves the redirect at download time so it
always fetches the current package, not this version's.
No `changelogURL`: there is no such page. `uuyc.163.com/changelog` and
`/update` both answer 200, but they return byte-identical content to a
path that does not exist — an SPA catch-all serving the homepage, not a
changelog. The download page is a distinct page but contains no
更新日志/更新说明/新增/修复 markers at all. (Checked 2026-08-22.)
