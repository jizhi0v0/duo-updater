# Alacritty

**这不是审计**：family `org-alacritty`（`Recipes/org-alacritty.swift`）里 Alacritty `org.alacritty` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-alacritty.swift — 「Detection-only」共享说明（七条只检测的 GitHub rule）

转引自 recipe 注释，未复测。整段原文；代码里只把句首的核对句改成挂在前一句末尾的括号 "(checked 2026-08-16 by running `codesign`/`spctl` on each downloaded artifact)"：日期与做法不变，"the downloaded artifact" 写成了 "each downloaded artifact"（这段说的是七个文件的产物）。

Each of these seven — this file, `Recipes/org-flameshot-Flameshot.swift`,
`Recipes/com-github-marktext-marktext.swift`, `Recipes/org-darktable.swift`,
`Recipes/org-zaproxy-zap-ZAP.swift`, `Recipes/com-BlueBubbles-BlueBubbles-Server.swift`
and `Recipes/org-winehq-wine-staging-wine.swift` — resolves a correct version,
but its macOS artifact is NOT a
notarized Developer ID build (ad-hoc signed or unsigned), so
`VendorInstaller` would refuse the swap anyway. Leaving
`installAssetPattern` nil states that up front: we surface the version and
send the user to the releases page. Verified 2026-08-16 by running
`codesign`/`spctl` on the downloaded artifact.

### Recipes/org-alacritty.swift — 三条改为 digest-only（2026-10-02）

共享说明改写：七条里 Alacritty、Flameshot、darktable 改成 `installTrust: .publishedDigestOnly`（用户在设置里打开后，按 GitHub API 给该资产的 `digest` 校验 SHA-256 再一键），另外四条仍只检测。实测（2026-10-02，`curl` 下载、`hdiutil attach -nobrowse -readonly` 挂载，未运行任何 app）：

| 产物 | API `digest` 与 `shasum -a 256` | Info.plist id / 版本 | 签名 | `codesign --verify --deep --strict` |
|---|---|---|---|---|
| `Alacritty-v0.17.0.dmg` | 一致 | org.alacritty / 0.17.0 | ad-hoc，签名标识 org.alacritty，无 Team，资源已封 | 通过，universal |
| `Flameshot-14.0-macos-arm64.dmg` | 一致 | org.flameshot.Flameshot / 14.0.0 | ad-hoc，资源已封 | 通过，arm64 |
| `darktable-5.6.1-arm64.dmg` | 一致 | org.darktable / 5.6.1 | ad-hoc，资源已封 | 通过，arm64 |
| `marktext-mac-arm64-0.20.0.dmg`/`.zip` | 一致 | com.github.marktext.marktext / 0.20.0 | ad-hoc linker-signed，`Sealed Resources=none`，签名标识 `Electron` | 失败（-67056） |
| `ZAP_2.17.0_aarch64.dmg` | 一致 | org.zaproxy.zap.ZAP / 2.17.0 | 外层未签名（可执行文件是 `ZAP.sh`） | 失败（-67062） |
| `wine-staging-11.18-osx64.tar.xz` | 一致 | org.winehq.wine-staging.wine / 11.18 | 未签名，仅 x86_64 | 失败（-67062） |
| `BlueBubbles-1.9.9-arm64.dmg` | API 为 null | com.BlueBubbles.BlueBubbles-Server / 1.9.9 | Developer ID（WPV275H8W7），`spctl`：Unnotarized Developer ID | 通过 |

`digest` 在 2025 年中以前上传的资产上一律为 null（Alacritty v0.15.1、darktable 5.0.1、BlueBubbles 1.9.9），之后的都有——GitHub 没有回填。资产名模式按各仓库全部稳定 release 的资产名核过：每个 release 每个架构恰好命中一个 dmg。
