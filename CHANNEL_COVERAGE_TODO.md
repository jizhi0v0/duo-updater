# 遗漏 Channel 待接清单

我们对很多 app 只接了 Stable，但厂商常并行发 Beta/Dev/Canary/Nightly 等轨。
本清单记录 **已维护 app 的遗漏 channel**，逐个填充。完成一个把 `[ ]` 改 `[x]`。

> 数据来源：2026-06-04 一轮 haiku web 搜索 + 关键 bundle id 实测核实。
> ⚠️ 每条落地前仍须按 `fragile-recipe` 在**真实响应**上验证：channel 的 bundle id 后缀、
> 版本同构性（versionIsBuild 陷阱见 [[duo-updater-vendor-version-scheme-traps]]）、端到端 evaluate。
>
> 两类注册位：
> - **probe** = `VendorProbeRecipe`（检测/一键，须带 `channel: .xxx`，源会拒绝跨 channel 应用）
> - **changelog** = `ChangelogRecipe` / `ChangelogCatalog`（只抽 notes）

---

## A. 可加 — 独立 bundle id，已实测安全共存

这些 channel 装成**独立 .app、独立 bundle id**，与 stable 不会互相覆盖，优先做。

- [ ] ~~**Microsoft Edge — Canary**~~ · `com.microsoft.edgemac.Canary` —— **受阻**：
      实测 `edgeupdates.microsoft.com/api/products?view=enterprise` 只列 Stable/Beta/Dev，
      **不含 Canary**（现有代码注释已记录此点，2026-06-04 复测仍成立）。要接得换端点
      （Canary 走 EdgeUpdate/Omaha，无公开企业 JSON），暂搁。changelog 同全 channel 页。
- [ ] **VS Code — Insiders** · `com.microsoft.VSCodeInsiders`
      probe：与 stable 同机制（VSCode update API），改 channel=insider。
      changelog：`https://github.com/microsoft/vscode/wiki/Insiders-Release-Notes`（无正式 notes，日更，价值低）
- [x] **Discord — PTB** · `com.hnc.DiscordPTB` —— **已接**（probe + .ptb channel + 测试）。
      probe 走 `updates.discord.com/.../manifests/latest?channel=ptb`，与 stable 同套。
      新增 `ReleaseChannel.ptb`（靠显示名 "Discord PTB" 检测）。changelog `discord.com/blog`。
- [x] **Discord — Canary** · `com.hnc.DiscordCanary` —— **已接**（probe + .canary channel + 测试）。
      probe `…?channel=canary`，名字 "Discord Canary" 命中 .canary。changelog `discord.com/blog`。
- [ ] **Android Studio — Canary** · `com.google.android.studio-EAP`（与 stable `com.google.android.studio` 不同 id）
      ⚠️ 核实 bundle id 来自 homebrew cask，落地时实测装一个确认。
      changelog：`https://developer.android.com/studio/preview/features`（preview 全 channel 同页）

---

## B. 待核实端点后再加 — channel 存在但 bundle id / 版本同构待定

> **2026-06-04 全清：** 逐条核实后全部移入 C 区。详见各条的移入原因。
> 拦截的共性原因有三：
> 1. 同 stable bundle id 且 macOS 侧无检测信号（显示名/plist/版本后缀均无标识）
> 2. ~~GitHub 源 app 的 `GitHubReleaseRule` 尚无 `channel` 字段~~ **已解决**（2026-06-04
>    加了 `channel: ReleaseChannel` + 源端 channel gate + 双断言测试），但 C 区条目
>    仍受原因 1（同 id 无检测信号）拦截，需等检测手段再推进
> 3. 个别已停产（Postman Canary）或纯应用内 opt-in（Raycast/Figma）

（空 — 已全部移入 C）

---

## C. 不加 — 同 bundle id 会覆盖 / 无法按 bundle id 检测

实测同 stable bundle id 或纯应用内开关，做成独立轨会**就地覆盖 stable** 或根本测不出。

- ✗ **Sublime Text — Dev** · 同 `com.sublimetext.4`，license 门控，就地替换 stable
- ✗ **Sublime Merge — Dev** · 同 `com.sublimemerge`，同上
- ✗ **Slack — Beta** · 同 `com.tinyspeck.slackmacgap`，应用内 opt-in，无独立下载
      （beta 有独立 changelog `slack.com/release-notes/mac-beta`，但无法区分安装，不接）
- ✗ **MS Office (Word/Excel/…) — Insider Slow/Fast** · 与 Production 同 bundle id，MAU 内部 ring 切换，无独立端点
- ✗ **MS Teams — Public Preview** · 应用内开关，非独立构建
- ✗ **Obsidian — Insider** · 付费 Catalyst 早鸟，无独立 macOS 自更新 feed
- ✗ **Dropbox — Beta** · 论坛分发，口径混乱
- ✗ **Bartender — Test Builds** · 同 feed
- ✗ **Plex — Beta** · Plex Pass 应用内，非独立下载
- ✗ **Audacity 4 预览** · 尚未成轨
- ✗ **Edge — Extended Stable** · 只是更慢的 stable，不单独成轨
- ✗ **MacUpdater** · 2026-01-01 已停更
- ✗ **Zen Browser — Twilight(nightly)** · 同 `app.zen-browser.zen`，GitHub 源（`GitHubReleaseRule` 无 channel 字段）；
      twilight 是 prerelease tag，stable rule 已用 `usePrereleases: false` 排除；加需先给 GitHub 源加 channel 基建
- ✗ **Ghostty — Tip(nightly)** · 同 `com.mitchellh.ghostty`，tip 滚动 tag 发布的 Ghostty.dmg 与 stable 同名同 id；
      无检测信号（显示名 "Ghostty" 无 channel 词，无 plist channel key），无法区分安装
- [x] **IntelliJ IDEA — EAP** · 独立 bundle id `com.jetbrains.intellij-EAP`（显示名 "IntelliJ IDEA-EAP"，
      版本 `EAP IU-262.6653.22`）—— **检测已由 ToolboxSource 覆盖**：Toolbox 纳管的 EAP 走
      channel 的 `quality_filter.order_value`(40000→eap) → `?code=IIU&latest=true&type=eap` API，
      实测显示绿点 up to date。⚠️ 教训：`UPDATE_CHANNEL_TYPE` 是 IDE 内置更新器的更新**偏好**，
      不是安装身份；早期误用它做 ChannelBinding 会把 stable 误标 PREVIEW，已回退。
      stable changelog recipe 已加（`com.jetbrains.intellij`，type=release）；EAP changelog 未接
      （`whatsnew` 仅一句"EAP N is out, see release notes"+链接，结构化价值低）
- ✗ **JetBrains Toolbox — EAP** · 同 `com.jetbrains.toolbox`，无独立 EAP cask，无检测信号
- ✗ **Cursor — Nightly** · 同 `com.todesktop.230313mzl4w4u92`，无独立 nightly cask/下载，无检测信号
- ✗ **LM Studio — Beta** · 同 `ai.elementlabs.lmstudio`，版本 API 无 channel 参数，无独立 beta 安装
- ✗ **DBeaver — Early Access** · 同 `org.jkiss.dbeaver.core.product`，GitHub 源无 channel 字段；
      EA 构建共享 bundle id，标签格式同 stable
- ✗ **Beekeeper Studio — Beta** · 同 `io.beekeeperstudio.desktop`，GitHub 源无 channel 字段；
      beta 是同 repo prerelease，stable rule 已用 `usePrereleases: false` 排除
- ✗ **Insomnia — Beta / Alpha** · 同 `com.insomnia.app`，GitHub 源无 channel 字段；
      monorepo tags `core@X.Y.Z-beta.N` 存在但无法路由到独立安装
- ✗ **Postman — Canary** · **已停产**：Homebrew cask `postman@canary` 于 2025-11-15 disabled（reason: no_longer_available）
- ✗ **RustDesk — Nightly** · 同 `com.carriez.rustdesk`，GitHub 源无 channel 字段；
      nightly 是同 repo prerelease，stable rule 已排除
- ✗ **1Password — Beta** · 同 `com.1password.1password`，cask `1password@beta` 装 "1Password.app" 同名同 id；
      vendor check API 仅服务 NIGHTLY 且需 auth，stable HTML scrape 无法区分 beta 安装
- ✗ **Raycast — Beta(v2)** · 应用内 opt-in（Raycast 内部设置切换），无独立下载/bundle id
- ✗ **VLC — Nightly** · 同 `org.videolan.vlc`，nightlies.videolan.org 是滚动构建无版本号语义；
      无检测信号，nightly 与 stable 安装不可区分
- ✗ **Blender — Daily / Alpha / Beta** · 未安装、无 cask 变体；builder.blender.org 滚动构建，
      同 bundle id，macOS 侧无检测信号
- ✗ **Figma — Beta** · 应用内 opt-in（Figma 内部 feature flag），无独立下载/bundle id
- ✗ **GitHub Desktop — Beta** · 同 `com.github.GitHubClient`，GitHub 源无 channel 字段；
      beta tags `release-X.Y.Z-betaN` 是 prerelease，stable rule 已排除

---

## D. 复核项 — Warp 死轨

`releases.warp.dev/channel_versions.json` 实测 5 轨都在，但 beta/canary 早已停更：

| channel | 最新版本日期 | 状态 |
|---|---|---|
| stable / preview / dev | 2026-05~06 | 活跃，已接 ✓ |
| **beta** | 2024-12 | 停更 ~1.5 年 → **已删** `dev.warp.Warp-Beta` recipe |
| **canary** | 2022-09 | 停更 ~4 年 → **已删** `dev.warp.Warp-Canary` recipe |

- [x] 清掉 Warp-Beta / Warp-Canary 两个死 recipe —— **已删**。
      理由：JSON 仍列这俩，但探测只会拿到数年前的"latest"，比干净的 "unknown" 更糟。
      bundle-id 后缀检测仍会给这类安装打 channel 标签（UI 用），只是没有版本源。
      live 测试 `warpSignalElementChannelsResolve` 本就只测 Preview/Dev，删除不破坏任何测试。

---

## 已全覆盖（无遗漏，存档参考）

Chrome(4)、Firefox(5)、Thunderbird(4)、LibreWolf、Zed(Stable/Preview)、TablePlus(Stable/Beta)、
Signal(Stable/Beta)、Element(Stable/Nightly)、OrbStack(Stable/Canary)、Tailscale(Stable/RC/Unstable)、
HBuilderX(Stable/Alpha)、Warp(活跃 3 轨)，以及一众单轨 app（Claude/Codex/ChatWise/Ollama/Conductor/
Alfred/CleanShot/Shottr/AppCleaner/Unarchiver/ImageOptim/Pearcleaner/Stats/MacsFanControl/
Calibre/Notion/JetBrains Air）。

OpenCode 复核结果（2026-06-04）：audit backlog 曾列为 `C`，但代码中没有
`ai.opencode.desktop` 的 ChangelogRecipe / ChangelogCatalog；cask `opencode-desktop`
是 `auto_updates:true`，检测也不会由 Homebrew 覆盖。
