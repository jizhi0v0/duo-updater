# Dropbox

**这不是审计**：family `com-getdropbox-dropbox`（`Recipes/com-getdropbox-dropbox.swift`）里 Dropbox `com.getdropbox.dropbox` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-getdropbox-dropbox.swift — stable VendorProbe（一键 `Dropbox%20<ver>.dmg`）

转引自 recipe 注释，未复测。第一段原句没写日期；日期取自引入这句话的提交：`599e8dde`（2026-06-04）。

The target is a
~200 MB dmg, so don't follow — read the small 302 Location
(followRedirects:false).

复测 2026-09-14（05:18 UTC，对 dmg 只发 HEAD）：重定向落到 `Dropbox%20268.4.4124.dmg`，`Content-Length` 398,329,648；`…268.4.4124.arm64.dmg` 是 387,752,941。代码里去掉了具体大小。

(Homebrew
cask has no livecheck; its url/version confirm this host + build.)

复测 2026-09-14（只读 GET `Homebrew/homebrew-cask` 的 `Casks/d/dropbox.rb`）：cask 有 `livecheck`，读的正是 `www.dropbox.com/download?plat=mac&full=1`，Apple silicon 上再加 `&arch=arm64`（`strategy :header_match`）；`url` 是 `edge.dropboxstatic.com/dbx-releng/client/Dropbox%20#{version}#{arch}.dmg`。代码里那句已按这次复测改写。

One-click verified 2026-08-09 on 264.4.3385: the image is labelled
"Dropbox Offline Installer" but holds the real `Dropbox.app` —
com.getdropbox.dropbox, Team G7HH3F8CAK, spctl "Notarized Developer ID",
version matching the redirect filename.
