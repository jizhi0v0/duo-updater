# GitHub Desktop

**这不是审计**：family `com-github-GitHubClient`（`Recipes/com-github-GitHubClient.swift`）里 GitHub Desktop `com.github.GitHubClient`（stable 与 beta 两轨共用这个 bundle id）的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### 2026-11-20：稳定版改用官方下载入口（#2123）

`desktop/desktop` 的 latest Release 仍报 `3.6.11`，官方稳定版 Apple silicon 下载入口已经指向 `3.7.0`。
`VendorProbeRecipe` 从 `central.github.com/deployments/desktop/desktop/latest/darwin-arm64` 的 `Location` 读取稳定版版本号和同一个 arm64 ZIP 地址。`-betaN` 副本继续从 Releases 的 beta 规则查版本，两个渠道各自沿用现有更新日志。

## 夜扫覆盖

- 检测和安装包检查由现有 Vendor/GitHub 注册表枚举，稳定版为 `vendor:com.github.GitHubClient:stable`，beta 为 `github:desktop/desktop:beta`。两条都配置了 arm64 ZIP。
- 原稳定版在检测基线、安装基线和身份记录的键同步迁移至新 recipe ID，保留既有 bundle ID、Team、架构和版本历史。Beta 的 key 保持原样。
- Apple Silicon macOS 27.2 VM：`duo verify --only com.github.GitHubClient --no-installed` 通过 5 项检查，包括两条版本源、两组更新日志和日志覆盖。安装包及升级实测命令和结果见关联 PR。

## 原 recipe 注释

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-github-GitHubClient.swift — stable / beta GitHubReleaseRule（一键 `GitHub.Desktop-arm64.zip`）

转引自 recipe 注释，未复测。唯一的改写：末句一处本机状态措辞（那台机器装的是哪个渠道的拷贝），按本目录的机器状态规则改成了针对那台被验证的机器的说法。

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
is 4 (`release-3.4.16-beta1`→`release-3.4.13-beta2`). 8 keeps 2x
headroom over that.

复测 2026-09-14（03:15 UTC，只读 GET `repos/desktop/desktop/releases?per_page=100`）：首个 `release-X.Y.Z-betaN` 在第 0 位（`release-3.6.6-beta1`），相邻两个之间最多隔 3 个 release，100 条里 61 个 beta tag。
