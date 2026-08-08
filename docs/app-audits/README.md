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
- [x] [**Warp**](dev-warp-Warp-Stable.md) · `dev.warp.Warp-Stable` — P(stable/preview/dev) C · 3 active channels, beta/canary 轨道废弃 · stable 一键 ✓ · **stable(scan)+preview+dev(dmg) 验证 ✓** · 2026-06-04
- [x] [**OrbStack**](dev-kdrag0n-MacVirt.md) · `dev.kdrag0n.MacVirt` — P(stable/beta/canary) C B · 3 channels, shared ID + ChannelBinding · 全 channel 一键 ✓ · **stable/beta/canary 三 channel 本机验证 ✓**（beta/canary 临时翻 `updates_optinChannel`→`--scan`→删键还原）· 2026-06-04
- [x] [**Signal**](org-whispersystems-signal-desktop.md) · `org.whispersystems.signal-desktop` — P(stable/beta) · 2 channels, independent bundle IDs · **两 channel 官方 zip 验证 ✓** · 2026-06-04
- [x] [**Element**](im-riot-app.md) · `im.riot.app` — P(stable/nightly) · 2 channels, independent bundle IDs · **两 channel 验证 ✓ + 修复已发布 bug**（nightly id `io.element.nightly`→`im.riot.nightly`）· 2026-06-04
- [x] [**HBuilderX**](io-dcloud-HBuilderX.md) · `io.dcloud.HBuilderX` — P(stable/alpha) C · 2 channels, independent bundle IDs（alpha=`io.dcloud.HBuilderXAlpha`）· **全 channel 一键 ✓**（stable 一键接入 2026-07-03：版本源改 DCloud `release.json` + arm64 dmg，Team YQM5H857L5；alpha 早有一键）· **两 channel 本机验证 ✓**（stable channel-verify 复验 UPDATE 5.07→5.14）· 2026-06-04
- [x] [**Zed**](dev-zed-Zed.md) · `dev.zed.Zed` — G(stable+preview) C(stable+preview) · **两 channel 均经 GitHub 检测 ✓**（收尾补 stable rule 填上原缺口 + 修 Preview channel-gate 回归；`--check dev.zed.Zed-Preview` 全链 winning=GitHub/up-to-date）· 2026-06-04
- [x] [**Tailscale**](io-tailscale-ipn-macsys.md) · `io.tailscale.ipn.macsys` — P(stable) C · stable 一键 ✓ · unstable 未覆盖 · **stable 本机验证 ✓** · 2026-06-04
- [x] [**Fork**](com-DanPristupov-Fork.md) · `com.DanPristupov.Fork` — B(stable/beta) C · 2 channels, shared ID + feed-swap ChannelBinding · **beta（Fork 默认 Developer 渠道）+ stable 两 channel 本机验证 ✓**（stable 临时写 `applicationUpdateChannel=2`→`--scan`→删键还原，未退出）· 2026-06-04
- [x] [**Surge**](com-nssurge-surge-mac.md) · `com.nssurge.surge-mac` — B(stable/beta) · 2 channels, shared ID + feed-swap ChannelBinding · **beta（IncludeBetaBuilds=true）+ stable 两 channel 本机验证 ✓**（stable 用文件逐字节备份/还原，**未退出 Surge**）· 2026-06-04
- [x] [**TablePlus**](com-tinyapp-tableplus.md) · `com.tinyapp.TablePlus` — B(stable/beta) C · 2 channels, shared ID + header-keyed ChannelBinding · **beta（IsReceiveBetaBuild=1）+ stable 两 channel 本机验证 ✓ + header 翻 710↔711 实证**（stable 翻嵌套 pref→`--scan`→还原）· 2026-06-04
- [x] [**DuoPaste**](io-duopaste-daemon.md) · `io.duopaste.daemon` — B(stable/beta) · 2 channels, shared ID + channel-tag ChannelBinding · **beta + stable 两 channel 本机验证 ✓**（本机装 beta 构建；stable 临时翻 `sparkleIncludePrereleases`→`--scan`→还原）· 2026-06-04
- [x] [**CleanShot X**](pl-maketheweb-cleanshotx.md) · `pl.maketheweb.cleanshotx` — C B(license feed) · license-keyed Sparkle feed · **stable 本机验证 ✓**（legit feed head=4.8.8=installed）· 2026-06-04

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
> installed bundle (full production chain). Evidence: `application-test/records/_single-channel-sweep.md`.

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
- [x] **VLC** · `org.videolan.vlc` — P C (one-click, two-stage changelog) · ✓ src=Vendor
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

## Single-channel — GitHub Releases

- [x] **RustDesk** · `com.carriez.rustdesk` — G C (one-click) · ✓ src=GitHub
- [x] **GitHub Desktop** · `com.github.GitHubClient` — G · ✓ src=GitHub
- [x] **Stats** · `eu.exelban.Stats` — G (one-click) · ✓ src=GitHub · [audit](eu-exelban-Stats.md)
- [x] **DBeaver** · `org.jkiss.dbeaver.core.product` — G · ✓ src=GitHub
- [x] **Beekeeper Studio** · `io.beekeeperstudio.desktop` — G · ✓ src=GitHub
- [x] [**Insomnia**](com-insomnia-app.md) · `com.insomnia.app` — G C (one-click) · ✓ src=GitHub · changelog=insomnia.rest(`__NEXT_DATA__` JSON) · 修 stable 跨渠道误推（pattern 加 `$` 锚，2026-06-06）· beta/alpha 受阻于 detect() 不解析 `-beta.N` 后缀
- [x] **Pearcleaner** · `com.alienator88.Pearcleaner` — G · ✓ src=GitHub
- [x] **Macs Fan Control** · `com.crystalidea.macsfancontrol` — G · ✓ src=GitHub
- [x] **Alcove** · `com.henrikruscon.Alcove` — G · ✓ src=GitHub
- [ ] **Zen Browser** · `app.zen-browser.zen` — G C · (not installed; prerelease-tag channel, not a pure single-channel sweep target)

## Changelog-only (detection via Sparkle or Homebrew)

- [x] [**Ghostty**](com-mitchellh-ghostty.md) · `com.mitchellh.ghostty` — C (two-stage), detection still unknown
- [x] [**Ollama**](com-electron-ollama.md) · `com.electron.ollama` — C, detection still unknown
- [x] [**OpenCode**](ai-opencode-desktop.md) · `ai.opencode.desktop` — C, detection still unknown
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
