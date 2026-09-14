# Meld

**这不是审计**：family `org-gnome-Meld`（`Recipes/org-gnome-Meld.swift`）里 Meld `org.gnome.Meld` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-gnome-Meld.swift — VendorProbe（上游与 macOS 重打包的版本陷阱）

转引自 recipe 注释，未复测。整段原文；代码里上游版本号与重打包停留的上游版本换成了不带具体值的说法，并注明核对日期（原句没写日期，引入它的提交是 `b49d0a30`，2026-08-16，同一段的探测写着 2026-08-16）；探测的状态码、字节数与条数搬到这里；`v3.22.3+105` 标成了示例。

Meld — TRAP: upstream GNOME Meld (gitlab.gnome.org) is at 3.24.0, but
there is no official macOS build; the only one is a third-party repack
by dehesselle (`gitlab.com/dehesselle/meld_macos`) that stalled the
wrapped app at upstream 3.22.3 and instead versions ITS OWN repacks with
a trailing `+<build>` (`v3.22.3+105`). Reading gitlab.gnome.org would
report an update (3.24.0) this macOS build can never actually install.
Probed `gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases`
(status 200, 24296 bytes / 7 releases when checked 2026-08-16), whose
default order (`order_by=released_at&sort=desc`, confirmed by the
response's own `Link` header) puts the newest release first, so
first-match is correct without `selectHighest`.

复测 2026-09-14（14:02 UTC，只读 GET）：`gitlab.gnome.org/api/v4/projects/GNOME%2Fmeld/repository/tags?per_page=5` 第一个 tag 是 `3.24.0`，tag message 开头 "2026-06-20 meld 3.24.0"（带 Safari UA 与压缩的请求回 406，裸 curl 回 200）；`gitlab.com/api/v4/projects/dehesselle%2Fmeld_macos/releases` 200，解压后 24,387 B，7 个 release，新到旧：`v3.22.3+105`（2025-03-03）、`v3.22.3+100`、`v3.22.3+96`、`v3.22.2+81`、`v3.22.2+68`、`v3.22.2+26`、`v3.22.2+19`。响应头里的 `Link` 没有复测。

### Recipes/org-gnome-Meld.swift — VendorProbe（build 号与包身份）

转引自 recipe 注释，未复测。整段原文；代码里只把末句句首的 "Installed-bundle identity confirmed 2026-08-16:" 改成 "Bundle identity: … (checked 2026-08-16)"，核对到的 bundle id、Team 与 spctl 结果不变。

The mounted arm64 dmg's `CFBundleShortVersionString` is `3.22.3` and
`CFBundleVersion` is `105` — i.e. the tag's two halves map to the
bundle's two DIFFERENT version fields. Three separate releases share
marketing `3.22.3` with different builds (`+96`, `+100`, `+105`, all
2025 repack-only bumps with no upstream version change) — comparing
only the marketing half would silently miss those updates (the
"folded-build" gap). So `versionPattern` captures ONLY the build
integer and `versionIsBuild` routes it against `CFBundleVersion`;
`displayVersionPattern` captures the full `3.22.3+105` string so the
row still shows the vendor's own scheme instead of a bare `105`.
The feed carries no base64 SHA-512 (GitLab's `x-checksum-sha256`
response header is hex, and isn't in the body anyway), so no
`checksumPattern`; the downloaded arm64 dmg's sha256 was independently
verified to match that header byte-for-byte, but that's outside what
`checksumPattern` can express (base64 SHA-512 only).
Installed-bundle identity confirmed 2026-08-16: `org.gnome.Meld`,
notarized Developer ID, Team SW3D6BB6A6 (Rene de Hesselle) — `spctl`
accepted as "Notarized Developer ID".
