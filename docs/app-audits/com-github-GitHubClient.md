# GitHub Desktop

**这不是审计**：family `com-github-GitHubClient`（`Recipes/com-github-GitHubClient.swift`）里 GitHub Desktop `com.github.GitHubClient`（stable 与 beta 两轨共用这个 bundle id）的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-github-GitHubClient.swift — stable / beta GitHubReleaseRule（一键 `GitHub.Desktop-arm64.zip`）

转引自 recipe 注释，未复测。唯一的改写：原文末句用第一人称的“这台机器”说 beta 是装着的那份，按本目录的机器状态规则改成了针对那台被验证的机器的说法。

Both verified end-to-end 2026-06-06: stable `GitHub.Desktop-arm64.zip`
(3.5.12) and beta (3.5.12-beta2) are the same notarized Developer ID build
(Team VEKTX9H2N7, GitHub), same bundle id; the beta was the copy installed
on the machine verified that day.

### Recipes/com-github-GitHubClient.swift — beta GitHubReleaseRule（`listPageSize`）

转引自 recipe 注释，未复测。代码里只留下为什么需要这个页大小（条件），带日期的位置与间隔都在这里。

listPageSize: not installed on the measuring machine, so measured
directly against the live endpoint (2026-09-04, newest 100 releases):
first-match index 1 (the newest release is often the stable
`release-…` tag one spot above), worst run between two `-betaN` tags
is 4 (`release-3.4.16-beta1`→`release-3.4.13-beta2`).

复测 2026-09-14（03:15 UTC，只读 GET `repos/desktop/desktop/releases?per_page=100`）：首个 `release-X.Y.Z-betaN` 在第 0 位（`release-3.6.6-beta1`），相邻两个之间最多隔 3 个 release，100 条里 61 个 beta tag。
