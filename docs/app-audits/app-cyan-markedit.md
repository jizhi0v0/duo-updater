# MarkEdit

**这不是审计**：family `app-cyan-markedit`（`Recipes/app-cyan-markedit.swift`）里 MarkEdit `app.cyan.markedit` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/app-cyan-markedit.swift — GitHub rule（universal dmg）

转引自 recipe 注释，未复测。原注释在两段之间还有一句 "and would have offered an arm64-only build to an Intel Mac"，没有搬：DuoUpdater 自 2026-08-14（a8295aee）起 `ARCHS: arm64`，不在 Intel Mac 上运行（见 PR 的 (c) 表）。

Verified with `file`: the plain dmg is a
universal binary (x86_64 + arm64) while `-apple-silicon` is a single arm64
slice — and `apple-silicon` was not a token the asset picker recognised, so
pinning it read as arch-neutral

(The token is recognised now, but the universal dmg is
still the better pin: one artifact that runs everywhere, no arch branch.)
