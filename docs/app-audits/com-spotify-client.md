# Spotify

**这不是审计**：family `com-spotify-client`（`Recipes/com-spotify-client.swift`）里 Spotify `com.spotify.client` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-spotify-client.swift — stable VendorProbe（`.zipEntryPlist`，一键 dmg）

转引自 recipe 注释，未复测。整段原文（原注释是一整块，中间没有空行）；代码里留下的是结论（stub 与客户端版本同步，2026-06-16 核对时比 Homebrew cask 新；2026-08-22 检查时找不到桌面端发布说明），两个大小、当天的版本号和找到的论坛帖子搬到这里。1.8MB 与 164MB 原句没写日期，引入它们的是 2026-06-16 那次核对所在的提交 `b57ecd21`。唯一的改写：原文说"装着的 app"也落后一个 build，按本目录的机器状态规则改成了针对那台被核对的机器的说法。

Spotify — no cheap public version API (the cohort `upgrade.scdn.co`
endpoint is session-token-gated, not a configurable key). BUT the 1.8MB
"stub" web installer `download.scdn.co/SpotifyInstaller.zip` bundles an
`Install Spotify.app` whose CFBundleShortVersionString tracks the latest
CLIENT version in lockstep — verified 2026-06-16: stub `1.2.92.148` while
the app installed on the machine verified that day AND Homebrew's cask both lagged at `.147`, so the stub
is the FRESHEST surface (even ahead of brew's heavyweight `extract_plist`
of the 164MB dmg). The version sits behind two layers — a
deflate-compressed zip entry + a binary plist — so it needs the
`.zipEntryPlist` mode (text-regex / redirect modes can't reach it); the
pattern just validates the extracted string is a dotted version. Same
marketing scheme the app reports (4-component `1.2.x.y`), so not a build
recipe. One-click install pulls the full always-latest universal dmg
(`download.scdn.co/SpotifyARM64.dmg`, 164MB, fetched only at apply time) —
an in-place app swap gated by Spotify's Team 2FNC3A47ZF. changelogURL is
nil on purpose: spotify.com/release-notes tracks a DIFFERENT (mobile/web)
version scheme (`1.2.534.x`), so embedding it for a `1.2.92.x` desktop
build would show an unrelated page — better the honest "no notes" state.
No `changelogURL`, and not an oversight: Spotify publishes no release
notes for the desktop client anywhere. Checked 2026-08-22 — the only
things that exist are one-off community forum posts from a decade ago
(0.9.x, 1.0.9) and long-running threads asking for a changelog.

复测 2026-09-14（约 08:10 UTC，只读 HEAD）：`SpotifyInstaller.zip` 1,868,153 B，`SpotifyARM64.dmg` 165,724,956 B。没有下载，所以 stub 里的版本与 dmg 的架构都没有复核。
