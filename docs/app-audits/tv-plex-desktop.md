# Plex

**这不是审计**：family `tv-plex-desktop`（`Recipes/tv-plex-desktop.swift`）里 Plex `tv.plex.desktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/tv-plex-desktop.swift — VendorProbe（下载 feed 与版本段数）

转引自 recipe 注释，未复测。整段原文。"the `plex` cask has no livecheck" 不成立，写下时（`599e8dde`，2026-06-04）也不成立，代码里改写了，见下面的更正；其余原样，重新折行。

Plex (desktop, mac) — Plex's own downloads feed (plex.tv/api/downloads/
6.json is the desktop product; 7.json is the separate PlexHTPC, and the
`plex` cask has no livecheck, so this is the clean source). Anchor to the
`MacOS` block and capture only the 3-component marketing version
(1.112.0), dropping the feed's full `1.112.0.359-0d79a49f`: the app's
CFBundleShortVersionString is the bare 1.112.0, and keeping the trailing
.359 would compare as +359 over a current install (VersionComparator
treats the missing 4th component as 0) — a permanent phantom update. The
MacOS block's top-level `version` precedes its `releases` array, so the
`[^}]*?` reaches it without crossing a `}` and never grabs the (earlier)
Windows block. One-click: the MacOS block's release `url` is the
`Plex-<full>-universal.zip` on downloads.plex.tv/plex-desktop/ — anchored
to that path so it can't grab the Windows installer. (Plex self-updates via
Squirrel; this is the fallback behind the same-Team gate.)

更正 2026-09-14：Homebrew 的 `plex` cask 有 `livecheck`，读的正是 `https://plex.tv/api/downloads/6.json`（`json.dig("computer", "MacOS", "version")`），而且 cask 是 `auto_updates true`。只读核对：`raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/p/plex.rb` 第 10 行 `livecheck do`；`gh api 'repos/Homebrew/homebrew-cask/contents/Casks/p/plex.rb?ref=aa461148'`（2023-08-09，cask 挪进分片目录的那次提交）与 `?ref=3d410dee`（2025-12-01）的文件里同样在第 10 行。代码里改成：cask 自己的 `livecheck` 读的就是这个 6.json。

### Recipes/tv-plex-desktop.swift — VendorProbe（`versionPattern` 为什么不放宽段数）

转引自 recipe 注释，未复测。整段原文；代码里 "The feed's value is `1.115.0.426-4e960a1d`" 改成 "has the form …"，句末的 "Verified against the live feed 2026-08-19." 并进上一句的括号，加上复测日期；其余原样，重新折行。

NOT widened to a variable segment count like several other probes' patterns. The feed's
value is `1.115.0.426-4e960a1d` and this pattern has no closing
delimiter, so the capture is bounded only by how many segments it
asks for: three yields the marketing version, four would silently
start reporting `1.115.0.426` — a build number the app does not
report, which is a phantom update. Verified against the live feed
2026-08-19.

复测 2026-09-14（14:18 UTC，只读 GET `plex.tv/api/downloads/6.json`，解压后 1,409 B）：`MacOS` 块的 `version` 仍是 `1.115.0.426-4e960a1d`，`versionPattern` 取到 `1.115.0`，安装 pattern 取到 `…/plex-desktop/1.115.0.426-4e960a1d/macos/Plex-1.115.0.426-4e960a1d-universal.zip`。
