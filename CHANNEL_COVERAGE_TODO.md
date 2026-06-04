# Channel 覆盖账本

多 channel（beta/dev/canary/nightly/preview/esr/…）的覆盖全景。

> **重建 2026-06-04**（`channel-discovery` skill 试跑产出）。原文件被手动删除后从
> **代码这个权威源头**重新生成。
> - **§1 已覆盖** = 直接从 `VendorProbeRecipe.swift` / `GitHubReleasesSource.swift` /
>   `*Channel.swift` 提取，是当前真实状态（非记忆）。
> - **§2 TODO / §3 死轨** = 结转自删除前的同日调查（2026-06-04 web 搜索 + 实测）；
>   死轨是**已否决项，不要重新调查**（`channel-discovery` 安全规则 4）。
>
> 落地任一条仍须按 `fragile-recipe` 在**真实响应**上验证，多 channel 须 `channel-verify`
> 真机跑绿才算 ✓（见 `app-audit` Phase 3¾）。两类注册位：
> **probe** = `VendorProbeRecipe`（带 `channel:`，源拒跨 channel）；
> **changelog** = `ChangelogRecipe`；**binding** = `ChannelBinding` + `<App>Channel.swift`。

---

## §1 已覆盖（从代码提取，权威）

### Pattern A — 独立 bundle id（各 channel 自带身份，最干净）

| Family | 非 stable channel → bundle id | 源 |
|---|---|---|
| **Chrome** | beta `com.google.Chrome.beta` · dev `.dev` · canary `.canary` | VendorProbe |
| **Edge** | beta `com.microsoft.edgemac.Beta` · dev `.Dev` | VendorProbe（canary 受阻，见 §2） |
| **Firefox** | dev-edition `org.mozilla.firefoxdeveloperedition`（RemotingName `firefox-dev`）· nightly `org.mozilla.nightly` | VendorProbe |
| **Thunderbird** | beta `org.mozilla.thunderbirdbeta` · nightly `org.mozilla.thunderbird-daily` | VendorProbe |
| **Warp** | preview `dev.warp.Warp-Preview` · dev `dev.warp.Warp-Dev` | VendorProbe |
| **Signal** | beta `org.whispersystems.signal-desktop-beta`（显示名 "Signal Beta"）| VendorProbe |
| **Element** | nightly `im.riot.nightly`（2026-06-04 修了误写的 `io.element.nightly`）| VendorProbe |
| **Discord** | ptb `com.hnc.DiscordPTB` · canary `com.hnc.DiscordCanary` | VendorProbe |
| **HBuilderX** | alpha `io.dcloud.HBuilderXAlpha` | VendorProbe |
| **Zed** | preview `dev.zed.Zed-Preview`（`channel: .preview`，2026-06-04 修 channel-gate 回归）| GitHub |

### Pattern A\* — 共享 bundle id，但 Mozilla `RemotingName` 可检测

Firefox/Thunderbird 的 beta/esr 与 stable **共用 bundle id**，靠 `Contents/Resources/
application.ini` 的 `RemotingName`（baked per-channel）区分——`ReleaseChannel.detect()`
的最高优先信号。版本号的 `b`/`esr` 后缀在安装版被剥掉，**不能**用来检测。

| channel | bundle id | RemotingName |
|---|---|---|
| Firefox beta | `org.mozilla.firefox`（共享）| `firefox-beta` |
| Firefox esr | `org.mozilla.firefox`（共享）| `firefox-esr` |
| Thunderbird esr | `org.mozilla.thunderbird`（共享）| `thunderbird-esr` |

### Pattern B/C — 共享 bundle id + app 内开关写的本地信号（ChannelBinding）

这就是"app 内切换渠道"已做成的 6 个。每个读一个具体偏好/凭证：

| App | bundle id（共享）| 读的信号 | 门控方式 |
|---|---|---|---|
| **Fork** | `com.DanPristupov.Fork` | `applicationUpdateChannel` | feed-swap（`feed.xml` ↔ `feed-stable.xml`）|
| **Surge** | `com.nssurge.surge-mac` | `IncludeBetaBuilds` | feed-swap（`appcast-signed.xml` ↔ `-beta.xml`）|
| **TablePlus** | `com.tinyapp.TablePlus` | `IsReceiveBetaBuild` | header 注入（`X-Tiny-Beta-Update`）|
| **DuoPaste** | `io.duopaste.daemon` | `sparkleIncludePrereleases` | channel-tag |
| **OrbStack** | `dev.kdrag0n.MacVirt` | `updates_optinChannel`(=`beta`) | channel-tag |
| **CleanShot X** | `pl.maketheweb.cleanshotx` | `activationKey` | license-keyed legit feed（`legit.maketheweb.io/api/v1/appcast`）|

### 其它 multi-channel

- **Tailscale** `io.tailscale.ipn.macsys` — 厂商有 stable/rc/unstable；当前只接 stable
  （probe + changelog）。rc/unstable 未覆盖。

---

## §2 TODO — Pattern A 未覆盖（可做，独立 bundle id）

> 候选已于 **2026-06-04 用 `brew info --cask` 实测复核**（时效性：cask 名/版本会变）。

- [ ] **VS Code — Insiders** · bundle id（待实测，应为 `com.microsoft.VSCodeInsiders`）
      cask `visual-studio-code@insiders` ✓现存，app `Visual Studio Code - Insiders.app`，
      `auto_updates`（落穿→需 probe/GitHub 检测），实测版本 `1.124.0-insider`。
      probe 与 stable 同机制（VSCode update API），改 channel=insider。changelog 价值低。
      → `/app-audit "VS Code Insiders"` 装一个确认 bundle id，再加 channel=insider 的 probe。
- [ ] **Android Studio — Canary + Beta**（**两条轨**，旧调查只记了 Canary）
      ⚠️ **cask 已改名**：旧的 `android-studio-canary` 不存在；现为
      `android-studio-preview@canary`（`Android Studio Preview Canary.app`，`2026.1.2.4`）
      和 `android-studio-preview@beta`（`Android Studio Preview Beta.app`，`2026.1.1.7`）。
      ⚠️ **bundle id 存疑**：旧写的 `com.google.android.studio-EAP` 早于这次改名，须装后实测
      （可能已变 `...-canary`/`-beta`）。两轨都 `auto_updates`（落穿）。changelog
      `developer.android.com/studio/preview/features`（preview 全 channel 同页）。
      → `/app-audit "Android Studio Preview"`（先实测 canary/beta 各自 bundle id）。
- [ ] ~~**Edge — Canary**~~ · `com.microsoft.edgemac.Canary` —— **受阻**：
      `edgeupdates.microsoft.com/api/products?view=enterprise` 只列 Stable/Beta/Dev，
      不含 Canary（Canary 走 EdgeUpdate/Omaha，无公开企业 JSON）。暂搁。

---

## §3 死轨 — Pattern D / 不可行（已否决，**勿重开**）

同 stable bundle id 会就地覆盖、或纯应用内/服务端 opt-in 无本地痕迹、或已停产。

- ✗ **Sublime Text — Dev** · 同 `com.sublimetext.4`，license 门控，就地替换 stable
- ✗ **Sublime Merge — Dev** · 同 `com.sublimemerge`，同上
- ✗ **Slack — Beta** · 同 `com.tinyspeck.slackmacgap`，应用内 opt-in，无独立下载（beta 有独立 changelog 但无法区分安装）
- ✗ **MS Office（Word/Excel/…）— Insider Slow/Fast** · 与 Production 同 bundle id，MAU 内部 ring 切换，无独立端点
- ✗ **MS Teams — Public Preview** · 应用内开关，非独立构建
- ✗ **Obsidian — Insider** · 付费 Catalyst 早鸟，无独立 macOS 自更新 feed
- ✗ **Dropbox — Beta** · 论坛分发，口径混乱
- ✗ **Bartender — Test Builds** · 同 feed
- ✗ **Plex — Beta** · Plex Pass 应用内，非独立下载
- ✗ **Audacity 4 预览** · 尚未成轨
- ✗ **Edge — Extended Stable** · 只是更慢的 stable，不单独成轨
- ✗ **MacUpdater** · 2026-01-01 已停更
- ✗ **Zen Browser — Twilight(nightly)** · 同 `app.zen-browser.zen`，twilight 是 prerelease tag，stable rule 已用 `usePrereleases:false` 排除；无检测信号
- ✗ **Ghostty — Tip(nightly)** · 同 `com.mitchellh.ghostty`，tip 滚动 tag 的 dmg 与 stable 同名同 id，无检测信号
- ✗ **JetBrains Toolbox — EAP** · 同 `com.jetbrains.toolbox`，无独立 EAP cask，无检测信号
- ✗ **Cursor — Nightly** · 同 `com.todesktop.230313mzl4w4u92`，无独立 nightly 下载/信号
- ✗ **LM Studio — Beta** · 同 `ai.elementlabs.lmstudio`，版本 API 无 channel 参数
- ✗ **DBeaver — Early Access** · 同 `org.jkiss.dbeaver.core.product`，EA 共享 id、标签格式同 stable
- ✗ **Beekeeper Studio — Beta** · 同 `io.beekeeperstudio.desktop`，同 repo prerelease，stable rule 已排除
- ✗ **Insomnia — Beta/Alpha** · 同 `com.insomnia.app`，monorepo tag 无法路由到独立安装
- ✗ **Postman — Canary** · 已停产（cask `postman@canary` 2025-11-15 disabled）
- ✗ **RustDesk — Nightly** · 同 `com.carriez.rustdesk`，同 repo prerelease，stable rule 已排除
- ✗ **1Password — Beta** · 同 `com.1password.1password`，cask 装同名同 id；vendor API 仅服务 NIGHTLY 且需 auth
- ✗ **Raycast — Beta(v2)** · 应用内 opt-in，无独立下载/bundle id
- ✗ **VLC — Nightly** · 同 `org.videolan.vlc`，nightlies 滚动构建无版本语义，不可区分
- ✗ **Blender — Daily/Alpha/Beta** · 同 bundle id，builder.blender.org 滚动构建，无检测信号
- ✗ **Figma — Beta** · 应用内 feature flag，无独立下载/bundle id
- ✗ **GitHub Desktop — Beta** · 同 `com.github.GitHubClient`，beta tag 是 prerelease，stable rule 已排除

> **IntelliJ IDEA — EAP**：不在死轨——EAP 是独立 id `com.jetbrains.intellij-EAP`，
> 检测已由 **ToolboxSource** 覆盖（Toolbox 纳管走 eap API）。stable changelog 已接，
> EAP changelog 未接（结构化价值低）。

### Warp 死轨（JSON 仍列但已停更，recipe 已删）

`releases.warp.dev/channel_versions.json` 列 5 轨，但 beta（2024-12 停）、canary
（2022-09 停）早废。`dev.warp.Warp-Beta` / `-Canary` 两个 recipe **已删**——探测只会
拿到数年前的 latest，比干净的 unknown 更糟。bundle-id 后缀仍会给这类安装打 channel 标签
（UI 用），只是没版本源。活跃 3 轨（stable/preview/dev）已接 ✓。

---

## 已全覆盖的单 channel app（存档参考）

只有 stable、无其它轨需接的：Claude / Codex / ChatWise / Ollama / Conductor / opencode /
Alfred / CleanShot(单轨部分) / Shottr / AppCleaner / Unarchiver / ImageOptim / Pearcleaner /
Stats / MacsFanControl / Calibre / Notion / JetBrains Air / LibreWolf / Plex / Dropbox /
Orion / VS Code(stable) / Cursor / Figma / Slack / 1Password / Sublime（Text/Merge）/
RustDesk / GitHub Desktop / DBeaver / Beekeeper / Insomnia / Macs Fan Control / Alcove 等。
