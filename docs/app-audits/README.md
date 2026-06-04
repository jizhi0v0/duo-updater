# App Audit Index

Per-app audit checklist. Run `/app-audit <App>` for each, then check off.

> `P` = VendorProbe, `G` = GitHub, `C` = Changelog, `B` = ChannelBinding, `S` = Sparkle(auto)

---

## Multi-channel families (audit covers all channels)

- [x] [**Chrome**](com-google-Chrome.md) · `com.google.Chrome` — P(stable/beta/dev/canary) · 4 channels, independent bundle IDs · 审计 2026-06-04 ✓
- [x] [**Firefox**](org-mozilla-firefox.md) · `org.mozilla.firefox` — P(stable/beta/esr/nightly/dev-edition) · 5 channels · RemotingName 检测（修复 beta/esr 误判）· 5 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Thunderbird**](org-mozilla-thunderbird.md) · `org.mozilla.thunderbird` — P(stable/beta/esr/nightly) · 4 channels · RemotingName 检测（修复 beta bundle id + esr 跨 channel 误推）· 4 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Edge**](com-microsoft-edgemac.md) · `com.microsoft.edgemac` — P(stable/beta/dev) · 3 channels, independent bundle IDs · stable 一键 ✓ · **三 channel 真实 bundle 验证 ✓**（pkg 展开取 app）· 版本方案核对通过 · 2026-06-04
- [x] [**Discord**](com-hnc-Discord.md) · `com.hnc.Discord` — P(stable/ptb/canary) · 3 channels, independent bundle IDs · **三 channel 官方 dmg 验证 ✓** · 2026-06-04
- [x] [**Warp**](dev-warp-Warp-Stable.md) · `dev.warp.Warp-Stable` — P(stable/preview/dev) C · 3 active channels, beta/canary 轨道废弃 · stable 一键 ✓ · **stable(scan)+preview+dev(dmg) 验证 ✓** · 2026-06-04
- [x] [**OrbStack**](dev-kdrag0n-MacVirt.md) · `dev.kdrag0n.MacVirt` — P(stable/beta/canary) C B · 3 channels, shared ID + ChannelBinding · 全 channel 一键 ✓ · **stable/beta/canary 三 channel 本机验证 ✓**（beta/canary 临时翻 `updates_optinChannel`→`--scan`→删键还原）· 2026-06-04
- [x] [**Signal**](org-whispersystems-signal-desktop.md) · `org.whispersystems.signal-desktop` — P(stable/beta) · 2 channels, independent bundle IDs · **两 channel 官方 zip 验证 ✓** · 2026-06-04
- [x] [**Element**](im-riot-app.md) · `im.riot.app` — P(stable/nightly) · 2 channels, independent bundle IDs · **两 channel 验证 ✓ + 修复已发布 bug**（nightly id `io.element.nightly`→`im.riot.nightly`）· 2026-06-04
- [x] [**HBuilderX**](io-dcloud-HBuilderX.md) · `io.dcloud.HBuilderX` — P(stable/alpha) C · 2 channels, independent bundle IDs（alpha=`io.dcloud.HBuilderXAlpha`）· **两 channel 本机验证 ✓** · 2026-06-04
- [x] [**Zed**](dev-zed-Zed.md) · `dev.zed.Zed` — G(preview) C(stable+preview) · **preview 本机验证 ✓**；⚠️ **stable 无更新源缺口已在真实 dmg 上坐实**（detect ✓ 但 probe/GitHub 均不应答）· 2026-06-04
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
- [x] **Figma** · `com.figma.Desktop` — P C · ✓ src=Vendor
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
- [x] [**LibreWolf**](net-librewolf-librewolf.md) · `net.librewolf.librewolf` — P · ✓ **修复 bundle id + 端点(GitLab→Codeberg)**
- [x] **MacUpdater** · `com.corecode.MacUpdater` — P C · ✓ src=Vendor (upstream discontinued)
- [x] **IntelliJ IDEA** · `com.jetbrains.intellij` — P C (EAP via Toolbox) · ✓ src=Toolbox(managed)
- [x] **JetBrains Toolbox** · `com.jetbrains.toolbox` — P C · ✓ src=Vendor
- [x] **Android Studio** · `com.google.android.studio` — P · ✓ src=Toolbox(managed)

## Single-channel — GitHub Releases

- [x] **RustDesk** · `com.carriez.rustdesk` — G C (one-click) · ✓ src=GitHub
- [x] **GitHub Desktop** · `com.github.GitHubClient` — G · ✓ src=GitHub
- [x] **Stats** · `eu.exelban.Stats` — G · ✓ src=GitHub
- [x] **DBeaver** · `org.jkiss.dbeaver.core.product` — G · ✓ src=GitHub
- [x] **Beekeeper Studio** · `io.beekeeperstudio.desktop` — G · ✓ src=GitHub
- [x] **Insomnia** · `com.insomnia.app` — G · ✓ src=GitHub
- [x] **Pearcleaner** · `com.alienator88.Pearcleaner` — G · ✓ src=GitHub
- [x] **Macs Fan Control** · `com.crystalidea.macsfancontrol` — G · ✓ src=GitHub
- [x] **Alcove** · `com.henrikruscon.Alcove` — G · ✓ src=GitHub
- [ ] **Zen Browser** · `app.zen-browser.zen` — G C · (not installed; prerelease-tag channel, not a pure single-channel sweep target)

## Changelog-only (detection via Sparkle or Homebrew)

- [ ] **Ghostty** · `com.mitchellh.ghostty` — C (two-stage)
- [ ] **Ollama** · `com.electron.ollama` — C
- [ ] **OpenCode** · `ai.opencode.desktop` — C
- [ ] **AppCleaner** · `net.freemacsoft.AppCleaner` — C
- [ ] **Calibre** · `net.kovidgoyal.calibre` — C
- [ ] **Audacity** · `org.audacityteam.audacity` — C
- [ ] **Blender** · `org.blenderfoundation.blender` — C (version-pinned)
- [ ] **JetBrains Air** · `com.jetbrains.air` — C

## Sparkle-covered (auto-detected, no custom recipe)

- [ ] **iTerm2** — S
- [ ] **Arc** — S
- [ ] **Rectangle** — S
- [ ] **IINA** — S
- [ ] **Proxyman** — S
- [ ] **MonitorControl** — S
- [ ] **Maccy** — S
- [ ] **Keka** — S
- [ ] **Vivaldi** — S
- [ ] **OBS** — S
- [ ] **HandBrake** — S
