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
