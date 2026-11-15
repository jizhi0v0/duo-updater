# Podman Desktop

2026-11-15 路线更新：当前一键安装使用已在 VM 验证的 ZIP；下文原有 DMG 包与端到端记录保留为历史证据。Duo 的 blockmap 优化以所选 ZIP 的发布方整包校验值为前提，缺少校验值时仍全量下载。详见文末「Electron ZIP 迁移」。

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

### Electron ZIP 迁移（2026-11-15）

安装容器改为 `podman-desktop-1.30.5-arm64.zip`。在 macOS 27.2 Apple Silicon VM 中，从本次对应 DMG 准备的独立副本，经生产 `VendorInstaller.apply` 校验与替换为同版本 ZIP，再通过 LaunchServices 启动指定路径，确认 PID 存活后退出测试实例。版本、bundle ID、Team、arm64 与代码签名检查均通过。本次对应 DMG/ZIP 的 arm64 主程序 CDHash 与 app.asar 相同。既有旧 bundle ID、版本门控、edition 与仅检测渠道的范围沿用原规则；没有新增跨组安装。
整包发布校验值存在时才会尝试 blockmap；旧 GitHub 发布缺少 digest 时仍走全量 ZIP 与原有签名检查。

本次包、逐项结果与限制见 [集中验证记录](../../verify/electron-blockmap-20261115/README.md)。这些是一次验证的结果，不代表应用所有版本或功能均已测试。
