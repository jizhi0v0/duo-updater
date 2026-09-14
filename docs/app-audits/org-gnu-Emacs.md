# Emacs for Mac OS X

**这不是审计**：family `org-gnu-Emacs`（`Recipes/org-gnu-Emacs.swift`）里 Emacs `org.gnu.Emacs` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-gnu-Emacs.swift — VendorProbe（一键 dmg 的挂载核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（dmg 里的 Emacs.app 是 org.gnu.Emacs、Team 5BRAQAFB8B、Notarized Developer ID，checked 2026-08-16），挂载的是哪个 dmg、读到的 `CFBundleShortVersionString` 搬到这里（上一段仍在代码里用 30.2-2 解释 `-N` 后缀的陷阱）。

One-click verified 2026-08-16 by mounting the 30.2-2 dmg: Emacs.app is
org.gnu.Emacs, CFBundleShortVersionString 30.2, Team 5BRAQAFB8B
(Galvanix), notarized Developer ID. The install pattern reuses the same
`<title>`-scoped entry's `<link type="binary/octet-stream">` href, so it
always fetches the dmg for the version just matched (suffix included,
since that's the real filename) rather than a template that would guess
wrong when a repack bumps only the suffix.
