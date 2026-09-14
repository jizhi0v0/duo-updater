# Anki

**这不是审计**：family `net-ankiweb-anki`（`Recipes/net-ankiweb-anki.swift`）里 Anki `net.ankiweb.anki` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/net-ankiweb-anki.swift — GitHubReleaseRule（已关闭的 folded-build 缺口）

转引自 recipe 注释，未复测。整段原文；代码里只去掉了开头括号里说明在哪台机器上核对的那个从句（类别：核对所在的机器），日期留在代码里。唯一的改写：一处本机状态措辞（核对所在的机器），按本目录的机器状态规则改成了针对那台被核对的机器的说法。

CLOSED GAP (was verified on the machine checked on 2026-08-16, and was never a rule
bug): Anki stamps `CFBundleVersion` as a literal "1" for every build. When
the installed short version has no patch component (26.08 → app reports
"26.8"), `UpdateChecker.evaluate`'s "vendor folded the build into the
version" fallback rebuilt it as "26.8" + "1" = "26.8.1" and concluded the
app was already current — hiding exactly the x.y → x.y.1 patch. Every
other step (26.8.1 → 26.9) always reported normally.
