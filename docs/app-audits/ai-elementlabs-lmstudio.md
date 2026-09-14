# LM Studio

**这不是审计**：family `ai-elementlabs-lmstudio`（`Recipes/ai-elementlabs-lmstudio.swift`）里 LM Studio `ai.elementlabs.lmstudio` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/ai-elementlabs-lmstudio.swift — ChangelogRecipe（`lmstudio.ai/changelog/lmstudio`）

转引自 recipe 注释，未复测。

2026-08-09: the bare `/changelog` root is NOT this app's changelog any
more — Element Labs repurposed it for **Bionic**, a different product
("Bionic Changelog | LM Studio", entries `bionic-v1.0.6` /
`<span class="sr-only">Bionic 1.0.6</span>`). LM Studio itself is still on
the 0.4.x train (`versions-prod.lmstudio.ai` says 0.4.20) and its notes
moved to `/changelog/lmstudio`, with the per-version slug nested one level
deeper.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`lmstudio.ai/changelog` 列出的仍是 Bionic 条目（首条 `Bionic 1.1.2`）；`versions-prod.lmstudio.ai/update/darwin/arm64/0.0.0` 答 `0.4.24`；`/changelog/lmstudio` 首条是嵌套 slug `lmstudio/lmstudio-v0.4.24`。
