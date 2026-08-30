# App Audit Index

Per-app audit checklist. Run `/app-audit <App>` for each, then check off.

> `P` = VendorProbe, `G` = GitHub, `C` = Changelog, `B` = ChannelBinding, `S` = Sparkle(auto)

---

## Multi-channel families (audit covers all channels)

- [x] [**Chrome**](com-google-Chrome.md) · `com.google.Chrome` — P(stable/beta/dev/canary) · 4 channels, independent bundle IDs · 审计 2026-06-04 ✓
- [x] [**Firefox**](org-mozilla-firefox.md) · `org.mozilla.firefox` — P(stable/beta/esr/nightly/dev-edition) · 5 channels · RemotingName 检测（修复 beta/esr 误判）· 5 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Thunderbird**](org-mozilla-thunderbird.md) · `org.mozilla.thunderbird` — P(stable/beta/esr/nightly) · 4 channels · RemotingName 检测（修复 beta bundle id + esr 跨 channel 误推）· 4 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Edge**](com-microsoft-edgemac.md) · `com.microsoft.edgemac` — P(stable/beta/dev) · 3 channels, independent bundle IDs · **全 channel 一键 ✓**（beta/dev 一键接入 2026-07-03，pkg 取 enterprise API `Artifacts[].Location`，Team UBF8T346G9）· **三 channel 真实 bundle 验证 ✓**（pkg 展开取 app）· 版本方案核对通过 · 2026-06-04
- [x] [**Discord**](com-hnc-Discord.md) · `com.hnc.Discord` — P(stable/ptb/canary) · 3 channels, independent bundle IDs · **三 channel 官方 dmg 验证 ✓** · 2026-06-04
- [x] [**微信开发者工具**](com-tencent-wechatdevtools.md) · `com.tencent.wechatdevtools`（登记 id，磁盘上 2.02 是 `com.github.Electron`）— P(stable/rc/nightly) C · 3 channels · 真身份读 app 自带 `package.json`（`versionType`）· 一键 pkg ✓ · **三个渠道真实 pkg + 已装 2.01 全部 channel-verify ✓** · 2026-08-18
- [x] [**Warp**](dev-warp-Warp-Stable.md) · `dev.warp.Warp-Stable` — P(stable/preview/dev) C · 3 active channels, beta/canary 轨道废弃 · stable 一键 ✓ · **stable(scan)+preview+dev(dmg) 验证 ✓** · 2026-06-04
- [x] [**OrbStack**](dev-kdrag0n-MacVirt.md) · `dev.kdrag0n.MacVirt` — P(stable/beta/canary) C B · 3 channels, shared ID + ChannelBinding · 全 channel 一键 ✓ · **stable/beta/canary 三 channel 本机验证 ✓**（beta/canary 经 `updates_optinChannel` 取值验证，改动已还原）· 2026-06-04
- [x] [**Signal**](org-whispersystems-signal-desktop.md) · `org.whispersystems.signal-desktop` — P(stable/beta) · 2 channels, independent bundle IDs · **两 channel 官方 zip 验证 ✓** · 2026-06-04
- [x] [**Element**](im-riot-app.md) · `im.riot.app` — P(stable/nightly) · 2 channels, independent bundle IDs · **两 channel 验证 ✓ + 修复已发布 bug**（nightly id `io.element.nightly`→`im.riot.nightly`）· 2026-06-04
- [x] [**HBuilderX**](io-dcloud-HBuilderX.md) · `io.dcloud.HBuilderX` — P(stable/alpha) C · 2 channels, independent bundle IDs（alpha=`io.dcloud.HBuilderXAlpha`）· **全 channel 一键 ✓**（stable 一键接入 2026-07-03：版本源改 DCloud `release.json` + arm64 dmg，Team YQM5H857L5；alpha 早有一键）· **两 channel 本机验证 ✓**（stable channel-verify 复验 UPDATE 5.07→5.14）· 2026-06-04
- [x] [**Zed**](dev-zed-Zed.md) · `dev.zed.Zed` — G(stable+preview) C(stable+preview) · **两 channel 均经 GitHub 检测 ✓**（收尾补 stable rule 填上原缺口 + 修 Preview channel-gate 回归；`--check dev.zed.Zed-Preview` 全链 winning=GitHub/up-to-date）· 2026-06-04
- [x] [**Tailscale**](io-tailscale-ipn-macsys.md) · `io.tailscale.ipn.macsys` — P(stable) C · stable 一键 ✓ · unstable 未覆盖 · **stable 本机验证 ✓** · 2026-06-04
- [x] [**Fork**](com-DanPristupov-Fork.md) · `com.DanPristupov.Fork` — B(stable/beta) C · 2 channels, shared ID + feed-swap ChannelBinding · **beta（Fork 默认 Developer 渠道）+ stable 两 channel 真机验证 ✓**（stable 经 `applicationUpdateChannel=2` 验证，改动已还原）· 2026-06-04
- [x] [**Surge**](com-nssurge-surge-mac.md) · `com.nssurge.surge-mac` — B(stable/beta) · 2 channels, shared ID + feed-swap ChannelBinding · **beta（IncludeBetaBuilds=true）+ stable 两 channel 真机验证 ✓**（stable 经逐字节备份/还原验证，无需退出进程）· 2026-06-04
- [x] [**TablePlus**](com-tinyapp-tableplus.md) · `com.tinyapp.TablePlus` — B(stable/beta) C · 2 channels, shared ID + header-keyed ChannelBinding · **beta（IsReceiveBetaBuild=1）+ stable 两 channel 真机验证 ✓ + header 翻 710↔711 实证**（stable 经嵌套 pref 取值验证，改动已还原）· 2026-06-04
- [x] [**DuoPaste**](io-duopaste-daemon.md) · `io.duopaste.daemon` — B(stable/beta) · 2 channels, shared ID + channel-tag ChannelBinding · **beta + stable 两 channel 真机验证 ✓**（beta 用 `…-beta` 构建；stable 经 `sparkleIncludePrereleases` 取值验证，改动已还原）· 2026-06-04
- [x] [**CleanShot X**](pl-maketheweb-cleanshotx.md) · `pl.maketheweb.cleanshotx` — C B(license feed) · license-keyed Sparkle feed · **stable 本机验证 ✓**（legit feed head=4.8.8=installed）· 2026-06-04
- [x] [**CapCut**](com-lemon-lvoverseas.md) · `com.lemon.lvoverseas` — P(stable/beta) B · 2 channels, shared ID + ChannelBinding（`joinBeta` 在容器外的 INI）· **全 channel 一键 ✓**（Team 22MMUN2RN5，两轨真实 dmg 挂载核对）· **两轨版本字段是反的**（beta 的 short=`9.3.4531` / version=`9.4.0-beta4`，故 beta `versionIsBuild:true`）· 同 id 有 MAS 副本（19.2.0），靠 `_MASReceipt` 分流 · 2026-08-27
- [x] [**Termius**](com-termius-dmg-mac.md) · 三个独立 bundle id：`com.termius.mac`（MAS，`MacAppStoreSource` 通用覆盖，无 registry）/ `com.termius-dmg.mac`（官网 dmg，P stable，既有）/ `com.termius-beta.mac`（P beta，本次新增）— **全 channel 一键 ✓**（beta 用 universal dmg，Team 6KN952WR85）· stable 既有 recipe 的 arm64-only 一键是刻意的 arm64-pin（DuoUpdater 自身 arm64-only），不是 bug；真正待修的是 `changelogURL` 404，已拆分为独立任务 · issue #91、#102 · 2026-08-27

## Microsoft Office family

> Word/Excel are installed via **MAS** → resolve via App Store (receipt wins the
> chain before VendorProbe). So the `versionIsBuild` VendorProbe path is NOT
> exercised by a MAS install and stays **needs-verify** for a non-MAS Office.
> PowerPoint/Outlook/OneDrive/Teams = `.pkg` casks → skipped (need sudo).

- [~] **Word** · `com.microsoft.Word` — P(stable, versionIsBuild, one-click) · ✓ install detected via **App Store** (VendorProbe path needs-verify)
- [~] **Excel** · `com.microsoft.Excel` — P(stable, versionIsBuild, one-click) · ✓ install detected via **App Store** (VendorProbe path needs-verify)
- [ ] **PowerPoint** · `com.microsoft.Powerpoint` — P(stable, versionIsBuild, one-click) · ⏭ pkg/sudo
- [ ] **Outlook** · `com.microsoft.Outlook` — P(stable, versionIsBuild, one-click) · ⏭ pkg/sudo
- [ ] **OneDrive** · `com.microsoft.OneDrive` — P(stable, one-click) · ⏭ pkg/sudo
- [ ] **Teams** · `com.microsoft.teams2` — P(stable, one-click) · ⏭ pkg/sudo

## Single-channel — VendorProbe + optional Changelog

> ✓ marks = on-machine verified 2026-06-04 via `channel-verify` against a real
> installed bundle (full production chain). The sweep's raw output is an
> installed-app inventory, so it stays local (`application-test/records/`,
> gitignored) — per-app conclusions live in each app's audit instead.

- [x] **VS Code** · `com.microsoft.VSCode` — P C (one-click) · ✓ src=Vendor
- [x] **Claude Desktop** · `com.anthropic.claudefordesktop` — P (one-click) · ✓ src=Vendor
- [x] **Codex** · `com.openai.codex` — P C (one-click) · ✓ src=Vendor
- [x] **Cursor** · `com.todesktop.230313mzl4w4u92` — P · ✓ src=Vendor
- [x] **Notion** · `notion.id` — P C · ✓ src=Vendor
- [x] **Obsidian** · `md.obsidian` — P C · ✓ src=Vendor
- [x] [**Figma**](com-figma-Desktop.md) · `com.figma.Desktop` (+beta `com.figma.DesktopBeta`) — P(stable/beta) C (one-click) · 2 独立 bundle, Pattern A · 真机验证 2026-06-06 ✓
- [x] **Slack** · `com.tinyspeck.slackmacgap` — P C · ✓ src=Vendor
- [x] **1Password** · `com.1password.1password` — P C · ✓ src=Vendor
- [x] **Sublime Text** · `com.sublimetext.4` — P C · ✓ src=Vendor
- [x] **Sublime Merge** · `com.sublimemerge` — P · ✓ src=Vendor
- [x] **LM Studio** · `ai.elementlabs.lmstudio` — P C · ✓ src=Vendor
- [x] **ChatWise** · `app.chatwise` — P C · ✓ src=Vendor
- [x] **Conductor** · `com.conductor.app` — P C · ✓ src=Vendor
- [x] **Postman** · `com.postmanlabs.mac` — P C (one-click) · ✓ src=Vendor
- [x] **AweSun** · `com.oray.sunlogin.macclient` — P C (one-click, WAF) · ✓ src=Vendor
- [x] [**VLC**](org-videolan-vlc.md) · `org.videolan.vlc` — P C (one-click, two-stage changelog) · ✓ src=Vendor · nightly 共享 bundle id，未签名 → **一键永久不可**，检测已可行（#93 已解决），尚未接 recipe（issue #95）
- [ ] **Docker** · `com.docker.docker` — P · ⏭ skipped (cask now needs sudo to install)
- [x] **Raycast** · `com.raycast.macos` — P · ✓ src=Vendor
- [x] **Alfred** · `com.runningwithcrayons.Alfred` — P · ✓ src=Vendor
- [x] **Shottr** · `cc.ffitch.shottr` — P · ✓ src=Vendor
- [x] **The Unarchiver** · `com.macpaw.site.theunarchiver` — P · ✓ src=Vendor
- [x] **Orion** · `com.kagi.kagimacOS` — P · ✓ src=Vendor
- [x] **Dropbox** · `com.getdropbox.dropbox` — P · ✓ src=Vendor
- [x] **Plex** · `tv.plex.desktop` — P · ✓ src=Vendor
- [x] **Bartender** · `com.surteesstudios.Bartender` — P · ✓ src=Sparkle
- [x] **ImageOptim** · `net.pornel.ImageOptim` — P · ✓ src=Sparkle
- [x] [**LibreWolf**](net-librewolf-librewolf.md) · `net.librewolf.librewolf` — P · ✓ **修复 bundle id + 端点(GitLab→Codeberg)** · **detection-only（不可一键）**：dmg ad-hoc 签名/无 Developer ID/未公证，过不了签名闸（2026-07-03 实测）
- [x] **MacUpdater** · `com.corecode.MacUpdater` — P C · ✓ src=Vendor (upstream discontinued)
- [x] **IntelliJ IDEA** · `com.jetbrains.intellij` — P C (EAP via Toolbox) · ✓ src=Toolbox(managed)
- [x] **JetBrains Toolbox** · `com.jetbrains.toolbox` — P C (one-click) · ✓ src=Vendor · **一键接入 2026-07-03**（macM1 dmg 取 releases API，Team 2ZEFAR8TH3）· channel-verify 复验 ✓
- [x] **Android Studio** · `com.google.android.studio` — P · ✓ src=Toolbox(managed)
- [x] [**WeChat (微信 官网版)**](com-tencent-xinWeChat.md) · `com.tencent.xinWeChat` — P C (one-click dmg) · ✓ src=Vendor · 检测=公开 Sparkle appcast 截 3 段 marketing（4.1.10.53→4.1.10，不比 build）· changelog=官网 per-version 页 sourceTemplate · live smoke=up to date · 2026-06-16
- [x] [**Wispr Flow**](com-electron-wispr-flow.md) · `com.electron.wispr-flow` — P (detection-only) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Granola**](com-granola-app.md) · `com.granola.app` — P (one-click universal dmg) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Longbridge Desktop（长桥桌面版）**](com-longbridge-app-desktop.md) · `com.longbridge.app.desktop` — P+C (stable, one-click arm64 dmg) · `release_notes.en` · stable + retired preview real DMGs verified ✓ · 2026-08-25
- [x] [**Comet**](ai-perplexity-comet.md) · `ai.perplexity.comet` — P (detection-only) · redirect version avoids stale rollout API · real DMG + live probe ✓ · 2026-08-17
- [x] [**Devin Desktop**](com-exafunction-windsurf.md) · `com.exafunction.windsurf` — P (detection-only) · former Windsurf bundle · real DMG + live probe ✓ · 2026-08-17
- [x] [**AionUi**](com-aionui-app.md) · `com.aionui.app` — P (detection-only) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Msty Studio**](MstyStudio.md) · `MstyStudio` — P (detection-only) · real DMG + live probe ✓ · 2026-08-17
- [x] [**Grok Bot**](com-anysphere-sand.md) · `com.anysphere.sand` — P (one-click arm64 dmg, Team DCNK4UB866) · xAI 的产品但由 Anysphere 构建，走 Cursor 的更新基建（`api2.cursor.sh` / `downloads.cursor.com`），接口上的 app name 是 `sand` · asar 里的 nightly/dogfood 两轨客户端与服务端都不可达，故单 channel · 官网按钮那条无版本号、cask livecheck 那条最新时回 204，都不用 · 真实 DMG + live probe ✓ · 2026-08-29
- [x] [**TimeMachineEditor**](com-tclementdev-timemachineeditor-application.md) · `com.tclementdev.timemachineeditor.application` — P (one-click pkg, Team 68GTH78H6S) · cask `auto_updates:true` 被跳过，故 vendor 主页是唯一版本源 · 无 JSON API，读首页下载链接文字里的版本号，与 Homebrew 自己的 livecheck 独立印证 · pkg 装了 LaunchDaemon，故一键必须走 `.pkg` 而非 dmg/zip · 真实 pkg 展开验证 + live probe ✓ · 2026-08-29

- [x] [**搜狗输入法 (SogouInput)**](com-sogou-inputmethod-sogou.md) · `com.sogou.inputmethod.sogou` — P · 版本读**厂商自己的条件更新接口**（pin `v=0.0.0.1` 装成很旧的客户端去问；已验证不做分段升级，六个历史版本都答同一个最新版）· 返回的版本与 `CFBundleShortVersionString` 四段完全一致，无需任何裁剪 · 哨兵 `1.0.0.1` 由 `update_pack_url` 守卫挡掉 · 不发设备 hash · notes 走更新日志页 · detection-only（装机附带两个 LaunchAgent + QuickLook + 用户目录迁移；自更新 payload 另有 pre/post/switch 脚本）· 2026-08-28
- [x] [**豆包输入法 (DoubaoIme)**](com-bytedance-inputmethod-doubaoime.md) · `com.bytedance.inputmethod.doubaoime` — P+C · 比厂商 version code（装机侧在自定义键 `Wave Build Version Number`，CFBundleVersion 是废号 1）· changelog 走 app 自己的更新接口 · detection-only（输入法整类闸）· channel-verify ✓ · 2026-08-21
- [x] [**微信输入法 (WeType)**](com-tencent-inputmethod-wetype.md) · `com.tencent.inputmethod.wetype` — P+C · 读厂商安装器自己读的 InstallInfo manifest（此前抓的是**安装器壳的版本**，用错 namespace 不会失败、只会答错号）· **一键 ✓（2026-08-28 重新接入，Contents 轮换 + 用户数据快照）**——0.3.25 上线当天撤回的那条，证据链与复活理由都在文档里 · 真机红→绿 656→657 + 回滚实测 ✓（历史 payload 仍可取，用来造红）· 2026-08-28

- [x] [**WorkBuddy (Tencent)**](com-workbuddy-workbuddy.md) · `com.workbuddy.workbuddy-ai` + `com.workbuddy.workbuddy` — P (one-click, both sites) · 两站两个独立 app，非 channel · 每站按架构分两条 recipe · 两站真实 DMG channel-verify ✓ · 2026-08-27
- [x] [**Canva**](com-canva-CanvaDesktop.md) · `com.canva.CanvaDesktop` — P (one-click, dmg + feed sha512) · Electron 套壳，端点取自 app 自带 `app-update.yml` · cask 是 `auto_updates` 且滞后一版 · beta 轨道 2024-11 起废弃，pattern 以数字点结尾拒读 · 真实 DMG + live probe + `duo check` 全链 ✓ · 2026-08-27
- [x] [**Little Snitch**](at-obdev-littlesnitch.md) · `at.obdev.littlesnitch` — P(stable/nightly) C(stable only) · 2 channels，共享 bundle id，channel 词烤进 `CFBundleShortVersionString`（`ReleaseChannel.detect()` 新增 0.7 步）· 端点是 Homebrew cask 自己 livecheck 也在用的 obdev 静态 feed，两 cask 均 `auto_updates` 故原本 `.unknown` · **detection-only**：网络防火墙 + System Extension，一键需要真机红→绿验证才能开 · 未装机审计，从官方 dmg 挂载验证 · 2026-08-29
- [x] [**Carbon Copy Cloner**](com-bombich-ccc.md) · `com.bombich.ccc` — P(CCC5/CCC6/CCC7 stable + CCC7 beta，均 detection-only) · **三个独立、仍在维护的大版本代际共用同一 bundle id**（真机核实），`?v=latest` 只给最新的 CCC7，跨代际比较会把 CCC5/6 用户导向一次付费大版本升级——修法是新增 `VendorProbeRecipe.installedVersionPattern`（`hostRequirement` 的对偶，锁定装机代际）+ `VendorProbeSource` 新增一道过滤，四条 recipe 各自独立 `variant` · 有 `SUFeedURL` 但两条(CCC7 自己的 + CCC5/6 共用的)都回空 body，Sparkle 静默失效；改读 cask 自带 livecheck 同款的 `download_ccc.php?v=<latest|ccc6|ccc5>` 重定向文件名 · cask 是 `auto_updates` · beta 用 `?v=latestbeta`（无连字符，2026-08-29 补齐）· channel 信号是版本串 `-b<N>` 短后缀，`ReleaseChannel.detect()` 新增 step 0.8 · 2026-08-29

## Single-channel — GitHub Releases

- [x] **RustDesk** · `com.carriez.rustdesk` — G C (one-click) · ✓ src=GitHub
- [x] **GitHub Desktop** · `com.github.GitHubClient` — G · ✓ src=GitHub
- [x] **Stats** · `eu.exelban.Stats` — G (one-click) · ✓ src=GitHub · [audit](eu-exelban-Stats.md)
- [x] **DBeaver** · `org.jkiss.dbeaver.core.product` — G · ✓ src=GitHub
- [x] **Beekeeper Studio** · `io.beekeeperstudio.desktop` — G · ✓ src=GitHub
- [x] [**KeePassXC**](org-keepassxc-keepassxc.md) · `org.keepassxc.keepassxc` — G (one-click) · ✓ src=GitHub · snapshot 共享 bundle id，完全无签名 → **一键永久不可**，检测已可行（#93 已解决），尚未接 recipe（issue #95）
- [x] [**Insomnia**](com-insomnia-app.md) · `com.insomnia.app` — G C (one-click) · ✓ src=GitHub · changelog=insomnia.rest(`__NEXT_DATA__` JSON) · 修 stable 跨渠道误推（pattern 加 `$` 锚，2026-06-06）· beta/alpha 受阻于 detect() 不解析 `-beta.N` 后缀
- [x] **Pearcleaner** · `com.alienator88.Pearcleaner` — G · ✓ src=GitHub
- [x] **Macs Fan Control** · `com.crystalidea.macsfancontrol` — G · ✓ src=GitHub
- [x] **Alcove** · `com.henrikruscon.Alcove` — P(stable, detection-only) · ✓ src=Vendor `download.tryalcove.com/latest`（GitHub 镜像滞后已删；`update.tryalcove.com` 2026-07-29 起 NXDOMAIN，recipe 已改指 `/latest`）· 公开下载是滞后的 trial 构建（metadata 1.7.9 时 dmg 仍 1.7.7）故**不给一键** · 授权用户走 `AlcoveUpdateSource`（changelog + published_at + 一键）· 2026-07-29
- [ ] **Zen Browser** · `app.zen-browser.zen` — G C · (not installed; prerelease-tag channel, not a pure single-channel sweep target)
- [x] [**OpenCode Desktop**](ai-opencode-desktop.md) · `ai.opencode.desktop` — G C (one-click, native arch dmg) · real DMG verified ✓ · 2026-08-17
- [x] [**OpenChamber**](dev-openchamber-desktop.md) · `dev.openchamber.desktop` — G (one-click, native arch dmg) · real DMG verified ✓ · 2026-08-17
- [x] [**Jan**](jan-ai-app.md) · `jan.ai.app` — G (one-click universal zip) · real app verified ✓ · 2026-08-17
- [x] [**Chatbox**](xyz-chatboxapp-app.md) · `xyz.chatboxapp.app` — P (one-click arm64 dmg + feed sha512) · 真包 1.22.6 挂载验证 ✓ · 2026-08-30

## Changelog-only (detection via Sparkle or Homebrew)

- [x] [**Ghostty**](com-mitchellh-ghostty.md) · `com.mitchellh.ghostty` — C (two-stage), detection still unknown
- [x] [**Ollama**](com-electron-ollama.md) · `com.electron.ollama` — C, detection still unknown
- [x] [**AppCleaner**](net-freemacsoft-AppCleaner.md) · `net.freemacsoft.AppCleaner` — C + Sparkle verified
- [x] [**Calibre**](net-kovidgoyal-calibre.md) · `net.kovidgoyal.calibre` — C + Homebrew
- [x] [**Audacity**](org-audacityteam-audacity.md) · `org.audacityteam.audacity` — C + Homebrew
- [x] [**Blender**](org-blenderfoundation-blender.md) · `org.blenderfoundation.blender` — C (version-pinned) + Homebrew
- [x] [**JetBrains Air**](com-jetbrains-air.md) · `com.jetbrains.air` — C + Toolbox/Sparkle

## Sparkle-covered (auto-detected, no custom recipe)

- [x] [**iTerm2**](com-googlecode-iterm2.md) · `com.googlecode.iterm2` — S
- [x] [**Arc**](company-thebrowser-Browser.md) · `company.thebrowser.Browser` — S
- [x] [**Rectangle**](com-knollsoft-Rectangle.md) · `com.knollsoft.Rectangle` — S
- [x] [**IINA**](com-colliderli-iina.md) · `com.colliderli.iina` — S
- [x] [**Proxyman**](com-proxyman-NSProxy.md) · `com.proxyman.NSProxy` — S
- [x] [**MonitorControl**](app-monitorcontrol-MonitorControl.md) · `app.monitorcontrol.MonitorControl` — S
- [x] [**Maccy**](org-p0deje-Maccy.md) · `org.p0deje.Maccy` — S
- [ ] [**Keka**](com-aone-keka.md) · `com.aone.keka` — S, needs download verification
- [x] [**Vivaldi**](com-vivaldi-Vivaldi.md) · `com.vivaldi.Vivaldi` — S
- [ ] [**OBS**](com-obsproject-obs-studio.md) · `com.obsproject.obs-studio` — S, needs download verification
- [x] [**HandBrake**](fr-handbrake-HandBrake.md) · `fr.handbrake.HandBrake` — S
- [x] [**Typeless**](now-typeless-desktop.md) · `now.typeless.desktop` — P+C · electron-builder feed (VendorProbe) · 一键 dmg + sha512 · 结构化 changelog（gzip __NEXT_DATA__，含图）· channel-verify ✓ · 2026-06-19
- [x] [**OpenClaw**](ai-openclaw-mac.md) · `ai.openclaw.mac` — S · real DMG/feed verified ✓ · 2026-08-17
- [x] [**Superwhisper**](com-superduper-superwhisper.md) · `com.superduper.superwhisper` — S · real zip/feed verified ✓ · 2026-08-17
- [x] [**Perplexity Mac**](ai-perplexity-macv3.md) · `ai.perplexity.macv3` — S detection; current dmg unnotarized, no one-click · 2026-08-17
- [x] [**Dia Browser**](company-thebrowser-dia.md) · `company.thebrowser.dia` — S · real DMG/feed verified ✓ · 2026-08-17

## Investigated — blocked safely

- [x] [**TRAE**](com-trae-app.md) · `com.trae.app` — official API `2.3.61406` != real app `3.5.81`; no comparable remote version, deliberately left unknown · 2026-08-17

## 未编入分类（补录 2026-08-30）

这些审计文档早已存在但没有出现在本索引里，`scripts/check_app_audits.py` 上线时发现。

- [x] [**Amp**](com-ampcode-amp-macos.md) · `com.ampcode.amp.macos` — marketing 长期恒 `1.0`，只有 build 走动
- [x] [**百度网盘**](com-baidu-BaiduNetdisk-mac.md) · `com.baidu.BaiduNetdisk-mac`
- [x] [**Raycast**](com-raycast-macos.md) · `com.raycast.macos` — `CFBundleVersion = 0`，不可用作比较
- [x] [**QQ音乐**](com-tencent-QQMusicMac.md) · `com.tencent.QQMusicMac`
- [x] [**VSCodium Insiders**](com-vscodium-VSCodiumInsiders.md) · `com.vscodium.VSCodiumInsiders`

## 非 app 文档

- [Issue #111 — Sparkle appcast channel population](issue-111-appcast-channel-population.md) ·
  一次性测量任务的产出，不是 app 审计。留在此目录是历史原因。
