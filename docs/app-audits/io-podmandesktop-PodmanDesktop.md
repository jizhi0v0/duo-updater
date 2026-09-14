# Podman Desktop

**这不是审计**：family `io-podmandesktop-PodmanDesktop`（`Recipes/io-podmandesktop-PodmanDesktop.swift`）里 Podman Desktop `io.podmandesktop.PodmanDesktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/io-podmandesktop-PodmanDesktop.swift — GitHubReleaseRule（airgap 变体）

转引自 recipe 注释，未复测。整段原文；代码里只把「a 1.1 GB」换成了「a gigabyte-scale」。原句没写日期，引入它的提交是 `3edaa6fb`（2026-08-16）。

Podman Desktop — the release also carries `podman-desktop-airgap-<ver>-
arm64.dmg`, a 1.1 GB bundle-everything build. The `^podman-desktop-<ver>-`
anchor keeps the airgap variant out; without it a substring match would
hand the user a gigabyte download for the same app.
One-click: io.podmandesktop.PodmanDesktop, Team HYSCB8KRL2, notarized.

### Recipes/io-podmandesktop-PodmanDesktop.swift — GitHubReleaseRule（repo 改名）

转引自 recipe 注释，未复测。整段原文；代码里留下的是警告（规范名是故意钉的：旧 slug 301，URLSession 跟随时丢 `Authorization`，拿回发布的那次请求是匿名的），「measured 2026-08-29」、`x-ratelimit-limit: 60` 和「Three rules were quietly doing that」搬到这里，与 [com-electron-goose.md](com-electron-goose.md) 的同一段处理一致。

⚠️ Renamed containers/podman-desktop
-> podman-desktop/podman-desktop (measured 2026-08-29). The canonical
name is pinned here on purpose, and it is not cosmetic: GitHub answers the
old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
`Authorization` while following it — the fetch that actually returns
the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
whatever token the user configured. Three rules were quietly doing
that. See #135.
