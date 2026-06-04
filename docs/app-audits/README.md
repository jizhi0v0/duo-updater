# App Audit Index

Per-app audit checklist. Run `/app-audit <App>` for each, then check off.

> `P` = VendorProbe, `G` = GitHub, `C` = Changelog, `B` = ChannelBinding, `S` = Sparkle(auto)

---

## Multi-channel families (audit covers all channels)

- [x] [**Chrome**](com-google-Chrome.md) · `com.google.Chrome` — P(stable/beta/dev/canary) · 4 channels, independent bundle IDs · 审计 2026-06-04 ✓
- [x] [**Firefox**](org-mozilla-firefox.md) · `org.mozilla.firefox` — P(stable/beta/esr/nightly/dev-edition) · 5 channels · RemotingName 检测（修复 beta/esr 误判）· 5 个真实 bundle 验证 ✓ · 2026-06-04
- [x] [**Thunderbird**](org-mozilla-thunderbird.md) · `org.mozilla.thunderbird` — P(stable/beta/esr/nightly) · 4 channels · RemotingName 检测（修复 beta bundle id + esr 跨 channel 误推）· 4 个真实 bundle 验证 ✓ · 2026-06-04
- [ ] **Edge** · `com.microsoft.edgemac` — P(stable/beta/dev) · 3 channels, independent bundle IDs
- [ ] **Discord** · `com.hnc.Discord` — P(stable/ptb/canary) · 3 channels, independent bundle IDs
- [ ] **Warp** · `dev.warp.Warp-Stable` — P(stable/preview/dev) C · 3 channels, independent bundle IDs
- [ ] **OrbStack** · `dev.kdrag0n.MacVirt` — P(stable/beta/canary) C B · 3 channels, shared ID + ChannelBinding
- [ ] **Signal** · `org.whispersystems.signal-desktop` — P(stable/beta) · 2 channels, independent bundle IDs
- [ ] **Element** · `im.riot.app` — P(stable/nightly) · 2 channels, independent bundle IDs
- [ ] **HBuilderX** · `io.dcloud.HBuilderX` — P(stable/alpha) C · 2 channels, independent bundle IDs
- [ ] **Zed** · `dev.zed.Zed` — G(preview) C(stable+preview) · 2 channels, independent bundle IDs
- [ ] **Tailscale** · `io.tailscale.ipn.macsys` — P(stable) C · multi-channel (stable/rc/unstable)
- [ ] **Fork** · `com.DanPristupov.Fork` — B(stable/beta) · 2 channels, shared ID + ChannelBinding
- [ ] **Surge** · `com.nssurge.surge-mac` — B(stable/beta) · 2 channels, shared ID + ChannelBinding
- [ ] **TablePlus** · `com.tinyapp.tableplus` — B(stable/beta) C · 2 channels, shared ID + header-keyed
- [ ] **DuoPaste** · `io.duopaste.daemon` — B(stable/beta) · 2 channels, shared ID + ChannelBinding
- [ ] **CleanShot X** · `pl.maketheweb.cleanshotx` — C B(license feed) · 2 channels, shared ID + license-keyed

## Microsoft Office family

- [ ] **Word** · `com.microsoft.Word` — P(stable, versionIsBuild, one-click)
- [ ] **Excel** · `com.microsoft.Excel` — P(stable, versionIsBuild, one-click)
- [ ] **PowerPoint** · `com.microsoft.Powerpoint` — P(stable, versionIsBuild, one-click)
- [ ] **Outlook** · `com.microsoft.Outlook` — P(stable, versionIsBuild, one-click)
- [ ] **OneDrive** · `com.microsoft.OneDrive` — P(stable, one-click)
- [ ] **Teams** · `com.microsoft.teams2` — P(stable, one-click)

## Single-channel — VendorProbe + optional Changelog

- [ ] **VS Code** · `com.microsoft.VSCode` — P C (one-click)
- [ ] **Claude Desktop** · `com.anthropic.claudefordesktop` — P (one-click)
- [ ] **Codex** · `com.openai.codex` — P C (one-click)
- [ ] **Cursor** · `com.todesktop.230313mzl4w4u92` — P
- [ ] **Notion** · `notion.id` — P C
- [ ] **Obsidian** · `md.obsidian` — P C
- [ ] **Figma** · `com.figma.Desktop` — P C
- [ ] **Slack** · `com.tinyspeck.slackmacgap` — P C
- [ ] **1Password** · `com.1password.1password` — P C
- [ ] **Sublime Text** · `com.sublimetext.4` — P C
- [ ] **Sublime Merge** · `com.sublimemerge` — P
- [ ] **LM Studio** · `ai.elementlabs.lmstudio` — P C
- [ ] **ChatWise** · `app.chatwise` — P C
- [ ] **Conductor** · `com.conductor.app` — P C
- [ ] **Postman** · `com.postmanlabs.mac` — P C (one-click)
- [ ] **AweSun** · `com.oray.sunlogin.macclient` — P C (one-click, WAF)
- [ ] **VLC** · `org.videolan.vlc` — P C (one-click, two-stage changelog)
- [ ] **Docker** · `com.docker.docker` — P
- [ ] **Raycast** · `com.raycast.macos` — P
- [ ] **Alfred** · `com.runningwithcrayons.Alfred` — P
- [ ] **Shottr** · `cc.ffitch.shottr` — P
- [ ] **The Unarchiver** · `com.macpaw.site.theunarchiver` — P
- [ ] **Orion** · `com.kagi.kagimacOS` — P
- [ ] **Dropbox** · `com.getdropbox.dropbox` — P
- [ ] **Plex** · `tv.plex.desktop` — P
- [ ] **Bartender** · `com.surteesstudios.Bartender` — P
- [ ] **ImageOptim** · `net.pornel.ImageOptim` — P
- [ ] **LibreWolf** · `org.mozilla.librewolf` — P
- [ ] **MacUpdater** · `com.corecode.MacUpdater` — P C
- [ ] **IntelliJ IDEA** · `com.jetbrains.intellij` — P C (EAP via Toolbox)
- [ ] **JetBrains Toolbox** · `com.jetbrains.toolbox` — P C
- [ ] **Android Studio** · `com.google.Android.studio` — P

## Single-channel — GitHub Releases

- [ ] **RustDesk** · `com.carriez.rustdesk` — G C (one-click)
- [ ] **GitHub Desktop** · `com.github.GitHubClient` — G
- [ ] **Stats** · `eu.exelban.Stats` — G
- [ ] **DBeaver** · `org.jkiss.dbeaver.core.product` — G
- [ ] **Beekeeper Studio** · `io.beekeeperstudio.desktop` — G
- [ ] **Insomnia** · `com.insomnia.app` — G
- [ ] **Pearcleaner** · `com.alienator88.Pearcleaner` — G
- [ ] **Macs Fan Control** · `com.crystalidea.macsfancontrol` — G
- [ ] **Alcove** · `com.henrikruscon.Alcove` — G
- [ ] **Zen Browser** · `app.zen-browser.zen` — G C

## Changelog-only (detection via Sparkle or Homebrew)

- [x] [**Ghostty**](com-mitchellh-ghostty.md) · `com.mitchellh.ghostty` — C (two-stage), detection still unknown
- [x] [**Ollama**](com-electron-ollama.md) · `com.electron.ollama` — C, detection still unknown
- [x] [**OpenCode**](ai-opencode-desktop.md) · `ai.opencode.desktop` — listed as C, but recipe/catalog missing
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
