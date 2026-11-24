# Ollama

## 基本信息

- Bundle ID 为 `com.electron.ollama`。已核对正式版和 Preview 使用相同的 Team ID `3MU9H2V9Y9`。
- 官方 macOS App 有内置更新器。Homebrew 的 `ollama-app` cask（旧名 `ollama`）标记了 `auto_updates`。已由 Homebrew 管理的拷贝继续遵循 Duo 的来源偏好和 Homebrew 所有权规则。

## Channel 详情

| Duo 发布通道 | 更新请求 | 使用方式 |
|---|---|---|
| Stable（默认） | 官方桌面更新 API 接收当前版本 | 默认用于每份安装，包括手动装入的预发行包 |
| Preview | 同一 API 加 `channel=preview` | 在 Duo 的 Ollama 行菜单选择「发布通道 → 预览版」，按安装路径保存 |

Ollama 的设置开关控制自动下载。Duo 的频道选择独立保存，切回 Stable 后按官方接口的结果复查。官方文档也提供 [手动安装 Preview 的入口](https://docs.ollama.com/faq#how-do-i-install-a-pre-release)。

## 更新检测

- 复用 [Ollama 的桌面更新 API](https://raw.githubusercontent.com/ollama/ollama/v0.40.17/app/updater/updater.go)，发送 `os=darwin`、`arch=arm64` 和本机的完整版本。公开请求已实测可凭系统、架构和版本这三项查询。
- `204` 表示服务端当前没有为该拷贝提供更新。返回 ZIP 时，从同一条 `url` 的 GitHub tag 路径读出完整版本，用该 URL 下载。若返回正文不符合预期，按探针失败处理。
- GitHub Releases 用于发布说明和承载 API 选定的 ZIP。之前直接查询 `/releases/latest` 的检测已由该 API 取代。

## Changelog
- 来源: `ChangelogRecipe` + `ChangelogCatalog`
- 按 Duo 选定的频道显示。Stable 显示正式版，Preview 按精确 tag 读取候选版和正式版说明。
- Recipe 状态: 已有，GitHub releases page（`https://github.com/ollama/ollama/releases`）
- 条目取 `<li>`；有的发布整篇是散文、一个 `<li>` 都没有（2026-09-11 实测 v0.34.0、v0.32.12），
  这时走第二条 `<p>` pattern，跳过 "Full Changelog: vA...vB" 对比链接行（当天第一页 10 条发布都以它收尾）。
  没有这条兜底时，没条目的发布会被丢掉，最新一条恰好是散文时整个面板就落后一个版本（#507）。
- Stable 跳过 Pre-release：版本取自 sr-only `<h2>`，那是发布**名称**不是 tag，而 Ollama 的候选版按目标版本命名
  （tag `v0.40.0-rc3` 的 h2 是 `v0.40.0`）。结构化列表保留正式版（#872）。过滤依据是 section 里位于 h2 与
  `<relative-time>` 之间的 "Pre-release" 标签，
  因为出现过纯 `v<x.y.z>` tag 的 prerelease（见「历史与实测」2026-10-06 一节）。

## 一键安装

API 返回的 `Ollama-darwin.zip` 内包含 `Ollama.app`，使用现有 Vendor ZIP 安装和签名检查。运行中的 Ollama 由标准安装后重启流程处理。

## 夜扫覆盖

- 检测 probe 为 `vendor:com.electron.ollama:stable` 和 `vendor:com.electron.ollama:preview`。夜扫在两个请求中省略本机版本。
- 发布说明为 `changelog:com.electron.ollama:-` 和 `changelog:com.electron.ollama:preview`。
- `duo verify-install` 验证两个频道各自提供的 ZIP。Stable 延续旧 GitHub 检查的身份记录。按本机版本返回 `204`、逐拷贝保存频道以及 Homebrew 来源偏好均由 Core 测试覆盖。 Preview 的频道校验核对请求 URL 中的 `channel=preview` 参数。实测 `duo verify --no-installed --only com.electron.ollama` 为 5 项通过，两份 ZIP 均由 `duo verify-install --only com.electron.ollama --full` 验证通过。Preview 身份为独立的首次记录。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### 2026-11-24 更换默认更新来源

本机 GitHub `/releases/latest` 曾返回 tag `v0.40.18-rc0`，且当时的 `prerelease` 为 `false`。旧规则展示成 `0.40.18`，下载的 ZIP 实际仍是 `0.40.18-rc0`，导致同包重复安装。

在 macOS 27.2 arm64 VM，Ollama 自己的更新器从 `0.40.16` 下载并安装 `0.40.17`。启动新版后，官方 App 记录更新请求返回 `204`。官方 Preview 下载链接单独指向 `0.40.18-rc0`，此包可以安装并运行，运行中的 `/api/version` 返回完整版本，App 的更新检查也返回 `204`。公开的默认更新 API 对 `0.40.16` 返回 `{"url":"https://github.com/ollama/ollama/releases/download/v0.40.17/Ollama-darwin.zip"}`，对 `0.40.17` 与 `0.40.18-rc0` 返回 `204`，省略版本时返回 `0.40.17` ZIP。

同一台 VM 用 Developer ID 签名的 Duo Release CLI 检测并完成 `0.40.16 → 0.40.17` 的 Vendor 原地安装，装完版本和构建号均为 `0.40.17`，Gatekeeper 接受为 Notarized Developer ID。对 `0.40.17` 与手动装入的 `0.40.18-rc0` 复查均为 `up-to-date`，后者的安装计划为空。

### 2026-11-24 接入 Preview 通道

接入时，官方 API 的默认请求提供 `0.40.17`。同一 API 加 `channel=preview` 后提供 `0.40.18`，GitHub 将该 tag 标为预发行。Preview 中已安装 `0.40.17` 或 `0.40.18-rc0` 的拷贝收到 `0.40.18`，已安装 `0.40.18` 的拷贝收到 `204`。使用 Stable 查询 `0.40.18` 同样收到 `204`。下载的 Preview ZIP 版本和构建均为 `0.40.18`，签名标识为 `com.electron.ollama`，Team ID 为 `3MU9H2V9Y9`，Gatekeeper 接受为 Notarized Developer ID。

在 macOS 27.2 arm64 VM，签名的 Duo Release CLI 先检查 `0.40.17`，默认 Stable 显示已是最新。设置这一安装路径的 Preview 偏好后，新开的 CLI 进程检测并原地安装 `0.40.18`，磁盘版本和构建号均匹配，Gatekeeper 通过。Preview 复查显示已是最新。切回默认 Stable 后复查同样为已是最新，安装计划为空。VM 使用与行菜单相同的持久化偏好载入路径，菜单由 App 测试构建覆盖。

当天 16:36（北京时间）复测，[同一 GitHub release 记录](https://api.github.com/repos/ollama/ollama/releases/456227993)的标题和 tag 均为 `v0.40.18`，`prerelease` 为 `false`。早些时候记录的标题已是 `v0.40.18`，tag 仍为 `v0.40.18-rc0`。Stable 和 Preview 此次都返回同一个 `v0.40.18/Ollama-darwin.zip`。Duo 按官方请求返回的 ZIP 决定该安装拷贝能收到的版本。

### Recipes/com-electron-ollama.swift — ChangelogRecipe（GitHub releases 页）

转引自 recipe 注释，未复测。

Most releases are a bullet list, but some are written as prose with no
<li> at all — v0.34.0 and v0.32.12 on the live page, 2026-09-11. An entry
that yields no items is dropped, so the newest release vanished from the
pane and `duo verify` read the changelog as a whole release behind
(#507).

It skips the "Full Changelog: vA...vB" compare-link line
(all ten releases on the page that day end with it), which would
otherwise be a prose release's last item.

### Recipes/com-electron-ollama.swift — ChangelogRecipe 跳过 Pre-release（#872）

实测 2026-10-06（不是转引；日期是 UTC+8 本地时间，UTC 为 2026-10-05 19:07 首次抓取、19:27 复抓，结果相同）。

`duo verify` 自 2026-09-25 起把这条 changelog 标成 degraded：最新条目读得比 GitHub 探针新。
#872 里每次扫描附带的抓取样本（issue 正文与评论，按时间）：

| 扫描 | section id（tag） | sr-only h2（名称） | 样本里有 Pre-release 标签 |
|---|---|---|---|
| 2026-09-25（正文） | `release-v0.40.0-rc0` | `v0.40.0` | 是 |
| 2026-09-29 02:22 | `release-v0.35.0` | `v0.35.0` | 是 |
| 2026-09-29 20:24 | `release-v0.35.1-rc0` | `v0.35.1` | 是 |
| 2026-09-30 | —（自愈，样本无 section） | — | 否 |
| 2026-10-05 | `release-v0.40.0-rc3` | `v0.40.0` | 是 |

2026-09-29 02:22 那一行是纯 tag `v0.35.0` 却挂 Pre-release 标签——只认 `-rc` 后缀的判据会漏掉它，
所以 recipe 以标签为判据。

2026-10-06 抓 `https://github.com/ollama/ollama/releases` 第一页（10 个 section）：只有
`release-v0.40.0-rc3`（h2 `v0.40.0`）带标签，它的 section 里 `>Pre-release<` 出现两次（宽屏、窄屏各一个），
都在 h2 之后、第一个 `<relative-time>` 之前（section 内第一个标签在偏移 913，第一个 `<relative-time>` 在 12444）；`release-v0.35.1` 带 "Latest"。
同日 `api.github.com/repos/ollama/ollama/releases/latest` 回 `v0.35.1`。修复后对实时页面跑
`duo verify --changelog --only com.electron.ollama`：`✓ 1  ⚠ 0  ✗ 0`。

### Recipes/com-electron-ollama.swift — stable GitHubReleaseRule（一键 `Ollama-darwin.zip`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`0ca0f173`（2026-06-06）、`df241b20`（2026-06-06）。唯一的改写：一处本机状态措辞（那台机器上那份拷贝的版本），按本目录的机器状态规则改成了针对那台被量的机器的说法。第一句里的 "with no detection source — only a changelog recipe" 说的是这条 rule 接入之前（同一个提交接入）；代码里已改写成「那次检查的 bundle 也没有 `SUFeedURL`，这样的拷贝没有别的检测源，没有这条 rule 时行里只有 changelog recipe」。

Ollama — Electron app distributed via an `auto_updates` Homebrew cask,
which falls through `HomebrewCaskSource` and leaves no `SUFeedURL`, so
the copy installed on the machine measured then drifts (0.24.0 while GitHub ships v0.30.6) with no
detection source — only a changelog recipe. The macOS app is the same
GitHub `/releases/latest`: ollama.com/install.sh and ollama.com/download
both 307→ github releases/latest/download (`Ollama-darwin.zip` / the
`Ollama.dmg` asset).

复测 2026-09-14（03:12 UTC，HEAD 不跟随重定向）：`ollama.com/install.sh` 307 到 `…/releases/latest/download/install.sh`（不是 app 资产）；`ollama.com/download` 回 200 页面；`ollama.com/download/Ollama.dmg` 与 `ollama.com/download/Ollama-darwin.zip` 各自 307 到 `github.com/ollama/ollama/releases/latest/download/` 下的同名资产。代码里那句已按这次复测改写。

复测 2026-09-14（只读 GET `https://ollama.com/install.sh` 的脚本文本，跟随它的 307，没有执行）：第 48 行判断 `Darwin`，第 58 行 `DOWNLOAD_URL="https://ollama.com/download/Ollama-darwin.zip${VER_PARAM}"`，第 73、76 行下载并 `unzip` 这个 zip——代码里「`install.sh` fetches `Ollama-darwin.zip`」据此。

Verified end-to-end 2026-06-06: the .app inside
the latest zip self-reports CFBundleShortVersionString 0.30.6 (homogeneous,
no ghost update).

Ollama ships its own updater, but it drifts in practice (seen stuck on
0.24.0 while GitHub was on v0.30.6), so rather than refuse to act we offer
the swap as a fallback when its updater hasn't kept up.
