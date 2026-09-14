# DBeaver Community

**这不是审计**：family `org-jkiss-dbeaver-core-product`（`Recipes/org-jkiss-dbeaver-core-product.swift`）里 DBeaver Community `org.jkiss.dbeaver.core.product` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-jkiss-dbeaver-core-product.swift — GitHubReleaseRule（一键 dmg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（dmg 里的 app、bundle id、Team、spctl，checked 2026-08-09），核对时的版本号搬到这里；其余原样，重新折行。

One-click verified 2026-08-09 on 26.1.4: `dbeaver-ce-<ver>-macos-aarch64.dmg`
holds `DBeaver.app`, bundle id org.jkiss.dbeaver.core.product, Team
42B6MDKMW8, spctl "Notarized Developer ID". The pattern pins `aarch64` so
the x86_64 asset published alongside it can never be picked on an Apple
Silicon Mac.
