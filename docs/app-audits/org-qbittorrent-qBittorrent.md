# qBittorrent

**这不是审计**：family `org-qbittorrent-qBittorrent`（`Recipes/org-qbittorrent-qBittorrent.swift`）里 qBittorrent `org.qbittorrent.qBittorrent` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-qbittorrent-qBittorrent.swift — GitHubReleaseRule（为什么只检测）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（包的签名是自建证书、没有 Team，`spctl -a -t install` 拒绝；核对的是从本仓库 release 下载并挂载的 dmg，bundle id 与 universal，checked 2026-08-16），dmg 文件名、字节数与版本号搬到这里；其余原样，重新折行。

qBittorrent — DETECTION ONLY, and this is upstream's own signature, not
a property of where we read from: the macOS dmg on GitHub is the SAME
artifact SourceForge serves, signed `Authority=qbittorrent macos` with
`TeamIdentifier=not set` (a self-made certificate, not a Developer ID),
and `spctl -a -t install` rejects it. Verified 2026-08-16 by downloading
`qbittorrent-5.2.3.dmg` (48,317,381 B) straight from this repo's release
and mounting it — org.qbittorrent.qBittorrent, 5.2.3, universal, and
rejected. No `installAssetPattern`, so the row shows the version and
opens qbittorrent.org.
