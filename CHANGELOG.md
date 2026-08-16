# Changelog

User-facing release notes. The release script (`scripts/publish-release.sh`)
reads the section matching the version being shipped and embeds it in the GitHub
release and the Sparkle appcast, so this file is the single source of truth for
"what's new" — keep each version's prose written for users, not commit-speak.

## 0.3.29

**Installer packages stay the same package from verification to macOS Installer.** DuoUpdater now seals the selected installer before closing or replacing any existing Installer window, checks it again immediately before opening, and refuses the hand-off if another local process changed the file in between. This preserves Sparkle's signature guarantee all the way to the package you see in Installer without making the menu-bar UI pause while large packages are checked.

**Multi-installer disk images handle more real-world package names without guessing.** Versioned beta, release-candidate, Apple Silicon, and universal package names are recognized when they identify one unique product, while similarly named helpers and sibling products remain excluded. Older bundle-style macOS installer packages are supported by the same integrity checks.

**Failed installer downloads are cleaned up immediately.** A bad signature, unreadable disk image, cancelled download, or rejected package no longer leaves a full installer sitting in temporary storage until the next day's cleanup.

## 0.3.28

**Signed Sparkle updates that arrive as installer packages now work.** A few apps publish a perfectly valid, cryptographically signed `.pkg` instead of an app archive. DuoUpdater offered those updates, downloaded them, and then tried to unpack the package as though it were a zip — an update that could never finish. They now go to macOS's own Installer, after DuoUpdater verifies both the Sparkle signature on the download and the installer identity inside it.

**A disk image containing several installers is no longer allowed to make a guess.** Some vendors put a main installer, helpers, and sibling products in one image. Matching on a fragment of the filename could pick a helper simply because its name contained the app's name. DuoUpdater now opens a package only when it is the sole choice or can be identified uniquely; otherwise it stops and leaves the decision to you instead of presenting the wrong installer.

**The App Store helper is more tightly scoped to your login session.** The privileged helper now takes the account identity directly from macOS's authenticated XPC connection and refuses a request whose claimed user does not match. Normal App Store updates behave exactly as before; the change closes off a signed client from redirecting the helper into another user's session.

## 0.3.27

**Release notes show their formatting instead of its punctuation.** Notes that come from a project's GitHub release were rendered exactly as written — `**bold**` with the asterisks, links as `[text](url)`. Bold is now bold and links are links. This affected every app whose updates come from GitHub, which is most of the open-source ones.

**Arrow-keying down the app list no longer crawls.** Holding an arrow key felt like moving one row at a time through mud, and long release notes made it worse. Three things were doing it: a permission check on every app in the list ran again for every row drawn; the notes for whichever app you passed through were re-parsed on each keypress; and a long set of notes — one project's runs to 54,000 characters — was laid out in a single pass, which froze the window for about two seconds. The check is now computed once per list, parsed notes are kept, and long notes are laid out only as far as you have scrolled. Worst measured stall went from ~2.1 s to under 0.6 s, and what remains is the deliberate pause before the detail pane catches up rather than a freeze.

**Input methods are never updated by replacing the app, and 微信输入法 (WeType)'s one-click from 0.3.25 is withdrawn.** Settings were lost on a Mac during the work that added it. What we can show is that the copy in the protected system folder was never actually replaced by DuoUpdater — but an older copy of the input method was installed and launched elsewhere on that machine while testing, inside the window where the settings were rewritten. Nothing here is proven, and an input method's dictionary is not something to test a theory on: WeType now reports its version and sends you to the vendor's installer, which registers the input source with the system — a step that replacing the app bundle skips, and the likely reason that Mac then appeared twice in WeType's own device list.

The refusal is not specific to WeType: DuoUpdater no longer offers a one-click for anything installed as an input method, whichever vendor it comes from. Those apps still report their versions and link out.

## 0.3.26

**Three more apps now report their updates, and all three install with one click.** Hidden Bar, XQuartz and EasyFind were sitting in the list as a grey "unknown".

Hidden Bar is the interesting one: it ships with an update feed configured, so from the outside it looked like it was already covered. The feed answers, and is well-formed, and contains no releases at all — which is indistinguishable from a healthy feed until you look inside it. Its version now comes from its release tags instead. EasyFind ships no updater at all, so a copy installed from the vendor's site had no way to learn about new versions.

XQuartz installs through the system installer rather than by replacing the app, because it is not just an app: it lays down a whole X11 stack, and swapping only the app bundle would leave the rest at the old version. macOS asks for the administrator password itself, as it does for any package.

## 0.3.25

**Thirteen more apps now report their updates, twelve of them with one click.** GIMP, MongoDB Compass, Meld, Emacs, Tor Browser, Zotero, GrandPerspective, TigerVNC, qBittorrent, Opera, LibreOffice, pgAdmin 4 and Telegram Desktop were all sitting in the list as a grey "unknown" — installed, with nothing to say about them. Each was worked out by downloading the vendor's actual build and reading its identity out of it, so a one-click only appears where the download is signed by the same developer as the copy you already have. The exception is qBittorrent: its own build isn't signed by an identified developer at all, so it reports its version and sends you to the project's page.

Opera, LibreOffice and pgAdmin 4 nearly joined that exception. All three publish nothing but a directory listing, and listings sort alphabetically — "100" comes before "99" — so the newest release is not the first one on the page. Reading the version was never the problem; building a download link was, because the obvious way to build one would have picked whichever release happened to be listed first. They now download the release that was actually compared. That is the one mistake a signature check cannot catch for you: an older build of the right app, signed perfectly.

**1Password and Inkscape now install with one click too, and both were previously written off.** 1Password's official download turns out to be a small installer program rather than the app — signed and notarised by 1Password, so every safety check passes it, and installing it would have replaced your password manager with its own installer. DuoUpdater now fetches the package that installer itself downloads. Inkscape's download page hands out its file through a one-time link that changes with every release; the same file also sits at a plain, predictable address, which is what gets used.

**微信输入法 (WeType) now installs with one click.** It lives in a folder only an administrator can write to, which is why it used to only report its version. It now goes through the same administrator prompt as any other app in a protected location.

**Release notes for Opera, Inkscape and 1Password.** Opera publishes one page per major version, Inkscape one wiki page per release, and 1Password a feed — all three now render as proper change lists in the app instead of a link out. 1Password's version and its notes both come from that feed now, which is a published interface, rather than from scraping the page beside it.

**Discord's version check works again.** Discord moved its downloads to a different server and the check was still looking at the old address, so DuoUpdater quietly reported "no version" for Discord Stable while everything else kept working. It now keys off the part of the address that names the release channel, which is the part that actually has to be right.

## 0.3.24

**Fifteen more apps now report their updates, and all but one install with one click.** Rancher Desktop, Cherry Studio, RedisInsight, Upscayl, WailBrew, Wave Terminal, Lens, Termius, Unity Hub, iStat Menus, Inkscape, Google Gemini, Antigravity, AnyDesk and Kiro were all showing as a grey "unknown" — installed, with nothing to say about them. Each one was worked out by reading the vendor's own build rather than trusting a download page: the version now comes from wherever that app's own updater looks, and a one-click only appears where the download is signed by the same developer as the copy you already have. Three of them (Google Gemini, Antigravity, Kiro) publish nothing a download page can be scraped for; their real update services answer the same questions their own updaters ask, so that is what DuoUpdater asks too.

**AnyDesk in particular was written off and shouldn't have been.** Its download and changelog pages both refuse anything that isn't a person with a browser, so an earlier sweep concluded the app was unreachable. The plain-text changelog on the same server answers fine — and it is what AnyDesk's own Homebrew entry has always read.

**Updating an app in a location that needs an administrator password now asks, once.** Most apps live in /Applications, which you can write to; a few — input methods, for one — live where only an administrator can. Those used to show an Update button that could never work. Now the button asks for the password, and if you dismiss that prompt DuoUpdater takes the hint: the row switches to Open and stops asking on every release. "Ask for administrator access again" in the row's right-click menu brings the button back. The choice is remembered for that copy of the app specifically, so declining for one install doesn't silence another.

**An up-to-date Xcode beta no longer claims the vendor is behind it.** Under "Show all", a row whose vendor has fallen behind what you have installed shows a muted note saying so — you're ahead, nothing to do. Xcode was getting that note while sitting on exactly the build Apple was offering: it publishes a build number plus a human label ("27.0 beta 5"), and comparing that label against the plain "27.0" the bundle reports made a release look newer than its own beta. The note now settles on the build whenever both sides have one, so the same release is recognised as the same release however it is labelled. A vendor that has genuinely fallen behind is still called out.

## 0.3.23

**44 more apps now report their updates.** Apps that publish on GitHub but ship no update feed of their own used to sit in the list as a grey "unknown" — DuoUpdater could see them installed and had nothing to say about them. Bruno, UTM, kitty, KeePassXC, Godot, Bitwarden, VSCodium, draw.io, Podman Desktop, Anki, Raspberry Pi Imager, LuLu, MarkEdit, Clash Verge, Freelens, Tabby, Espanso, Moonlight, SwiftBar, Sequel Ace, balenaEtcher, DB Browser for SQLite, OpenLens, Headlamp, OpenMTP, Goose, Caffeine, noTunes, KeepingYouAwake, MiddleClick and a dozen more now show a real version, and 36 of them install with one click like any other app. Which ones was decided by downloading each vendor's actual build and reading the identity out of it, so a one-click only appears where the download is signed by the same developer as the copy you already have. Seven — Alacritty, Flameshot, MarkText, darktable, OWASP ZAP, BlueBubbles and Wine — publish builds Apple hasn't notarised, so those report their version and send you to the vendor rather than installing anything. LocalSend is report-only for a different reason, corrected here after this version shipped: its builds are notarised, but its newest release attaches no macOS download at all, so there is nothing to install until the project starts publishing one again.

Apps that already carry a Sparkle feed needed nothing: they were checked as part of this sweep and were already working, which is why names like Rectangle, Maccy, iTerm2 and Telegram aren't in the list above.

**An update that your Mac couldn't run is now refused rather than installed.** Where a developer publishes one download per processor, DuoUpdater picks between them by the file's name — and names are not always honest: three of the apps above ship an Apple silicon build under a name that says nothing about it, or says the opposite. Before an app is replaced, its new version is now checked against the processor in your Mac, read out of the program itself instead of its name. If it can't run here, the update stops and your working copy is left exactly as it was. Nothing about a normal update changes; this is the case that used to end with an app that no longer opened.

**An unanswered permission prompt no longer leaves the update check hanging.** To tell a TestFlight build apart from an App Store one, DuoUpdater reads TestFlight's own database, and macOS keeps that behind the "access data from other apps" permission. Until that was answered the read didn't fail — it waited, indefinitely, for a prompt that might be sitting behind another window or might never be answered at all, and the scan behind it simply never finished. Nothing timed out and nothing said why. It now waits a few seconds and then carries on without TestFlight's side of the story; the only thing missing in the meantime is whether those particular apps came from TestFlight, and it sorts itself out on the next scan once the permission is granted.

**Homebrew updates work behind a proxy.** If your Mac reaches the internet through a proxy, upgrading brew packages failed with `curl: (28) Failed to connect` while every other update went through fine. Homebrew shells out to `curl`, which — unlike the rest of DuoUpdater's networking — doesn't read the proxy you configured in System Settings; it only reads proxy environment variables, and an app launched from the Dock or at login has none. DuoUpdater now passes your system proxy settings down to Homebrew itself. Nothing changes on a machine with no proxy configured, and a proxy you've already exported in your own shell still wins.

## 0.3.22

**Claude's updates now show up while they're still rolling out.** Anthropic releases Claude in stages: a build goes to a fraction of Macs at a time, and the public download page only catches up at the end. DuoUpdater was reading that public page, so for the whole of a rollout — most of a day, in the case of 1.30096.5 — it told you Claude was up to date while Claude itself had already quietly downloaded the new version and was waiting for a relaunch. It now also asks the same endpoint Claude's own updater asks, which answers for *your* Mac specifically, and offers whichever of the two is further ahead. Nothing about which build you're offered has changed: it is either the public release or the one your Mac was already allocated. Claude also gains real publication times, so its releases now appear in the Release Log with the moment Anthropic shipped them rather than an estimate.

**A superseded package update no longer leaves its window sitting there.** Updates that go through macOS's own installer — Microsoft Office, AweSun, ToDesk — open an Installer window and then wait for you. If you left one open and a newer release came along, installing that one opened a second window, and they stacked up. The older window is now closed once its replacement is ready, and its download cleaned up with it. A window that's mid-install, or asking for your password, is left strictly alone.

## 0.3.21

**`duo` says which copy is which when two apps share a name.** Naming an app that is installed twice — two Xcode betas, say — printed both candidates as a bare "Xcode" and told you to name one exactly, which matches both again. The listing now carries each copy's version, and when the matches genuinely share a name it asks for the path instead of repeating advice that cannot work.

## 0.3.20

**"Open download page" no longer downloads a file.** On apps whose page DuoUpdater knows — ToDesk and UU Remote among them — that button handed your browser the installer package instead of opening anything: the link it used was the same one the updater downloads from, so clicking it started a download you didn't ask for. The page and the package are now kept apart, and the button opens the vendor's actual download page. Where a source only ever publishes a package and no page at all — a bare Sparkle feed — there is now no button rather than one that downloads something.

**The app list responds to the arrow keys again.** Opening the workbench window left the keyboard focus nowhere in particular, so ↑ and ↓ did nothing until you clicked a row — and after clicking into the release notes on the right, or switching to another app and back, they stopped working again. The list now takes the keyboard when it opens and takes it back at the points it used to lose it. Typing in the search box is untouched: a search you've started keeps the caret.

**The Brew section starts collapsed.** Casks and command-line formulae are a side channel for most people, and having that tree open by default pushed your actual apps up the sidebar every time the window opened. It now starts closed and remembers however you leave it.

**Xcode betas and release candidates are now detected, and two copies can be told apart.** Xcode was a grey "v27.0" with no update information at all, and if you keep more than one build around — a current beta beside the previous one — they were indistinguishable: same name, same version, same icon. Each row now reads its real build, so an update shows as "27.0 beta 1 (27A5194q) → 27.0 beta 5 (27A5237l)". Which track a copy belongs to is worked out from Apple's published builds rather than guessed from what you named the folder, and you'll only ever be pointed at something at least as finished as what you have — a beta can be superseded by a beta, a release candidate or the finished release, never the other way round. Updating still means going to Apple: the downloads need you signed in with your Apple ID, so the row links to Apple's download page and its release notes.

**Cursor's release notes are shown properly instead of an embedded web page.** Cursor writes its changelog as dated posts rather than numbered releases, so the notes pane fell back to loading the website. Each post is now shown as its own entry — its date, its headline and its changes — the same as every other app with readable notes.

**`duo check` now shows what changed when the version number doesn't.** Updates that keep the same version and only move the build — Surge, the JetBrains previews — printed as "6.9.0 → 6.9.0" on the command line, which was accurate and told you nothing. It now shows the builds, matching what the menu bar has always shown.

## 0.3.19

**Apps that ship their own updater are now updated directly by default.** These are the ones like Chrome, VS Code, Cursor and the Electron apps — and because they are also the apps you tend to leave running all day, the old default of stepping aside while they were open meant they were almost never updated at all: the row offered to open the app and left the rest to you. DuoUpdater now downloads the vendor's own installer and applies it whether or not the app is running, then quits and relaunches it so the new version takes effect. Anything that installs background components alongside the app — Tailscale, Office — ships a package that macOS's own installer handles, so those pieces are still put in place properly. If you would rather nothing was touched while an app is open, **Settings → General → Self-updating apps** still has the old behaviour, and changing it back does not affect anything already installed.

## 0.3.18

**An app whose developer changed its update signing key can be updated again.** Apps that update through Sparkle sign each release with a key, and the copy you already have carries the matching public key to check it against. If a developer generates a new key and ships it without a hand-over release signed by the old one, that check fails for everybody — the app's own updater is just as stuck as DuoUpdater was, and the update sits there refusing to install with a signature error. DuoUpdater now recognises that specific situation: when the new download carries a different key of its own and the release was signed with it, it stops trusting the signature and falls back to the same checks it uses for apps that publish no signature at all — the download must be validly signed by Apple's developer certificates, and by the *same* developer as the app it is replacing, for the *same* app. A download that fails any of that is still refused, as is a bad signature that isn't explained by a key change. Mirage Beacon 1.3.0 was the first to hit this.

## 0.3.17

**Update All no longer says a running app is finished before its restart.** When an update had already replaced an app on disk but Update All was still busy with other installers, the row briefly showed a green checkmark and disappeared even though the old version was still running. The app now stays visible with its running and installed versions, explains that it is waiting for the batch restart, and offers **Restart now**. The completion checkmark appears only when the update is actually in effect.

## 0.3.16

**Apps installed by a `.pkg` can now be rolled back.** DuoUpdater keeps a copy of the previous version before it updates an app, so a bad update can be undone. Apps that install through macOS's own installer — Microsoft Office, AweSun, ToDesk and the like — never got that copy: the rollback was skipped for them entirely, so the one kind of update DuoUpdater can't watch land was also the one you couldn't back out of. They're now backed up like everything else.

**Rollback no longer refuses apps that write inside their own bundle.** Some apps keep working files in amongst their own program files — ToDesk stores its settings database and logs there, and doing so breaks the seal Apple puts on an app. DuoUpdater checked that seal before restoring a backup, so for those apps it declared a perfectly good backup damaged and refused to put it back. It now checks the copy against a fingerprint taken when the copy was made, which is the thing that actually matters: that what's being restored is exactly what was saved. Tampering with a stored backup is still caught, and still refused.

**When a backup isn't possible, it says so instead of failing quietly.** A few apps keep program files that your account simply can't read — EasyConnect is one — and no copy of those can be made. Rather than attempting it and reporting a failure part-way through an update, DuoUpdater now checks first, tells you which file is in the way, and updates anyway; you just don't get a rollback point for that one app.

## 0.3.15

**The same app no longer appears several times over.** Some apps leave a dated copy of themselves behind every time they update — DuoPaste, for one, parks a `DuoPaste.backup-20260716-183428.app` next to the real thing on each self-update. Those copies are complete, working app bundles as far as anything on disk can tell, so DuoUpdater listed each one as its own app: three identical DuoPaste rows, each offering the same update. Worse, taking one of those offers would have installed the new version *into the backup*, leaving the app you actually use untouched and creating another stray copy. Backup and duplicate bundles are now recognised for what they are and left out of the list, as are exact clones of an app found in two places. Genuinely separate installs that happen to share an identity — Firefox alongside Firefox Beta, two versions of Android Studio kept side by side — still each get their own row.

**The list now reliably notices apps appearing and disappearing.** DuoUpdater watches your Applications folders so that an app updating itself in the background, or one you drag to the Trash, is reflected within a few seconds. That watch could quietly stop working — nothing crashed, nothing was reported, it simply stopped hearing about changes, and the list then went stale until you reopened the window. It's now rebuilt periodically and after your Mac wakes from sleep, with a fresh scan each time, so a watch that dies recovers on its own instead of staying dead for the rest of the session.

## 0.3.14

**An app that gets restarted after an update no longer jumps in front of what you're doing.** When DuoUpdater updates an app that's currently running, it quits and reopens it so the new version actually takes effect. Reopening it also pulled it to the front — so an update to something sitting quietly in the background could drop a window on top of the thing you were typing into. The app's position now survives the restart: whatever was in front comes back in front, and whatever was in the background comes back in the background, still there and still updated, just not in your way. The same applies to apps DuoUpdater reopens after an App Store update. Apps that weren't running at all are, as before, updated on disk and left closed — updating an app never starts it up.

## 0.3.13

**Fixes AweSun's update failing with "the server returned HTTP 404".** DuoUpdater worked out where to download AweSun's installer by building the filename itself from the version number. Oray then renamed the file — the same 16.6.0 build, one letter's difference — and every attempt at the update hit a dead link. It now takes the filename straight from Oray's own download listing rather than guessing at it, so a future rename won't break it again.

## 0.3.12

**An installer you've already downloaded no longer downloads again.** Some apps update through an installer package that macOS opens for you to confirm. If you closed that window without finishing — or quit DuoUpdater and came back — the row went back to offering "Update", and taking it fetched the whole package a second time. ToDesk's is 375 MB. The download was on your disk the entire time; nothing was pointing at it. Those rows now offer "Install" instead, which just re-opens the file you already have. If the installer window is still open it comes forward rather than opening a second one, and the offer stands until either the download is gone or a newer version comes out — at which point the old package would be the wrong one, so the row goes back to a normal "Update".

**Homebrew packages that aren't apps now show up.** DuoUpdater tracked outdated Homebrew formulae, and left casks alone on the grounds that a cask installs an app, which already gets its own row. That holds right up until a cask installs no app — a command-line tool like `codex`, a font, a driver. Those had no row anywhere: nothing for the app list to find, and not a formula either. `codex` sat three versions behind without a word. They're now part of the Homebrew panel, which reads "packages" rather than "formulae" to match. Casks that do install an app are still managed per-app exactly as before, and apps that update themselves are still left to their own updater.

## 0.3.11

**"Update All" now includes apps that install from a package.** A handful of apps — ToDesk and AweSun among them — ship their update as an installer package rather than something DuoUpdater can swap into place on its own. Those were quietly left out of "Update All" and had to be updated one row at a time; if such an app was the only other update pending, the button disappeared altogether rather than acting on just one. They're now part of the batch, and they run at the very end: everything that updates unattended finishes first, so nothing opens a window or asks for your admin password until the rest is already done. One caveat worth knowing — DuoUpdater can't tell when macOS's installer has finished, so if two package updates come up in the same batch, both installer windows open one after the other rather than waiting in line.

## 0.3.10

**Fixes updates going unnoticed for days at a time.** DuoUpdater re-uses the answers it gets from each app's version feed so it isn't re-downloading the same file every few minutes. The problem was how long it trusted a stored answer: when a vendor's server doesn't say how long its reply stays valid, macOS guesses — and it guesses longer the longer that feed has gone unchanged. So the very feeds that had been quiet for a while were exactly the ones DuoUpdater stopped re-reading, and a new release could sit there for days with the app still reporting "up to date" and no error to show for it. Every version check now always asks the server whether anything changed, while still skipping the download when nothing has. OrbStack 2.2.2 is the release that surfaced this; the same blind spot applied to most apps checked directly against their vendor, including Chrome, Cursor, Claude, ChatGPT, Warp, Spotify, and Visual Studio Code.

**Homebrew-managed apps no longer get stuck at the version they were on when DuoUpdater started.** The catalog DuoUpdater reads to learn the latest version of a Homebrew app was loaded once per launch and never refreshed, which is invisible if you quit the app daily and wrong if you leave it running for weeks. It now refreshes periodically. As a bonus, machines with no Homebrew casks installed no longer download that 5 MB catalog at all.

## 0.3.9

**Uses less memory and does less work in the background.** This release is entirely under the hood — nothing about what DuoUpdater does has changed, only what it costs to leave running. Every update it downloaded used to leave a small amount of memory behind that was never reclaimed; harmless once, but it adds up over the weeks a menu-bar app tends to stay open. Separately, while the main window was open DuoUpdater re-read every installed app from disk every 15 seconds and started a system process each time to see what was running — that now happens every three minutes, since the filesystem watcher already notices a real change the moment it happens. Recording the release history after each check also used to save its file once per app rather than once per check, and release notes could be fetched more than once when the same page was already on its way in.

## 0.3.8

**No more beachball while an app is relaunching.** Clicking Update on another app while one was being quit and relaunched could freeze DuoUpdater for a moment — the spinning rainbow cursor, an unresponsive window, a click that seemingly did nothing. Relaunching an app now happens in the background instead of on the interface, so the rest of the list stays live and clickable throughout. The same freeze could show up when opening an app from a row's right-click menu, or when handing an update off to an app's own updater; both are fixed too.

## 0.3.7

**Backups from uninstalled apps are now cleaned up automatically.** DuoUpdater keeps one backup of an app's previous version so an update can be rolled back. Backups for apps you've since uninstalled or moved were never reclaimed and could quietly pile up gigabytes of disk space over time. They're now deleted automatically during the regular update check. Settings shows how much space backups are currently using, with a toggle to turn off the automatic cleanup and a "Clean Up Now" button to run it on demand.

**JetBrains Toolbox apps no longer show a stuck or incorrect "update available."** Version checks for Toolbox-managed apps (IntelliJ, Android Studio, Fleet, Air, and others) now always ask live rather than sometimes falling back to a local cache that could never actually report a new version — it fixes both a status that lingered after Toolbox had already installed the update, and one that never appeared in the first place.

**Claude Desktop's release notes are now shown in DuoUpdater.** Update entries for Claude Desktop now include Anthropic's own per-version changelog instead of a generic notice.

## 0.3.6

**Update All now also relaunches apps that were only waiting on a restart.** If an app had already downloaded its update and just needed a relaunch to finish — Claude, for instance — clicking Update All used to skip it, leaving a stray "Relaunch" button behind. It now relaunches those too, in the same pass, whenever automatic restart-after-update is on.

**App Store updates recover from a receipt hiccup instead of just failing.** Occasionally a Mac App Store update downloads in full but the very last install step trips over a "receipt" error — a transient App Store glitch that a second attempt usually clears. DuoUpdater now retries once automatically. If it still doesn't take, the row offers an "Open App Store" button to finish the update from the App Store's Updates page, instead of leaving a raw error on screen.

**ToDesk update detection fixed.** A change to ToDesk's download page stopped DuoUpdater from reading its latest Mac version, so ToDesk updates went unnoticed. Detection now reads the version reliably again.

## 0.3.5

**App Store updates no longer show a scary error for an app that's already up to date.** If the Mac App Store had quietly updated an app in the background — TestFlight, say — DuoUpdater's row could go stale and, on Update, try to reinstall the version that was already there. macOS's installer rejects that with an alarming red "The upgrade failed", even though nothing was actually wrong. DuoUpdater now confirms an App Store app really is behind before reinstalling, and treats a no-op reinstall as "already up to date" — settling the row quietly instead of showing an error.

## 0.3.4

**App Store updates now ride out network hiccups.** A brief connection drop mid-update — a flaky link, or a proxy resetting the connection — used to fail an App Store update outright with a "could not connect to the server" error. Those updates now retry automatically a few times before giving up, so a momentary blip no longer strands an update that a second attempt lands cleanly. Clicking Update again after a failure also clears the old error immediately, instead of leaving it on screen next to the spinner.

**Apps that update themselves clear from the list faster.** When an app like Chrome finishes updating itself in the background while an App Store update is running, its "update available" row now clears promptly — it no longer lingers until the rest of the queue finishes.

## 0.3.3

**One-click updates for four more apps.** HBuilderX, JetBrains Toolbox, and Microsoft Edge's Beta and Dev channels now update in place with a single click, instead of only telling you that an update exists. HBuilderX also now reads its version straight from DCloud's own release feed, so it picks up new builds sooner and more reliably.

## 0.3.2

**Self-updating apps stay in their own lane.** A running app that ships its own Sparkle updater is now handed off to that updater — the same courtesy DuoUpdater already gave other self-updating apps — instead of being replaced underneath it, unless you've chosen "Always replace" in Settings.

**Fixes**

- The running-app dot and "Relaunch" badge no longer briefly lose track of an app right after an in-place update, when macOS keeps its process pinned to the temporary swap location for a moment.
- When you restart an app yourself after it updated in the background, the "Relaunch" badge now clears the moment the app comes back up — instead of lingering until the next background check.

## 0.3.1

**Fixes**

- When you restart an app yourself after it updated in the background, the "Relaunch" badge now clears the moment the app comes back up — instead of lingering until the next background check.

## 0.3.0

**See when your apps actually ship.** DuoUpdater now keeps a Release Log: a running timeline of every release the apps you track put out, each stamped with its publish time. Open it from the clock icon at the bottom of the popover.

**Release-habit heatmap.** A new Patterns view charts releases by weekday and hour, so you can see when an app tends to ship — pick any single app for its own pattern and version history, or view all of them together. History is backfilled from each app's update feed, so the heatmap is useful right away instead of starting empty.

**Honest about what it can't time.** Apps that publish an exact release date (Sparkle, GitHub, Alcove) are timed to the minute. Apps that only expose a version number get a clearly-marked "≈" estimated window — bounded by when DuoUpdater last saw the old version and first saw the new one — and never skew the heatmap.

**Fixes**

- ToDesk update checks no longer report an older grayscale build; they now track the version actually offered for download.

## 0.2.0

**Passwordless App Store updates.** Updating Mac App Store apps no longer interrupts you for your password every time. DuoUpdater now installs a small, signed privileged helper (one-time approval) and bundles `mas`, so App Store updates apply directly in the background.

**Cleaner "Restart to finish" lines.** When an app updates itself on disk while it's still running, the pending-restart line now shows the real marketing version on both sides — e.g. `1.8.x (build) → 1.9.0 (build)` instead of a bare build number on the left.

**Fixes**

- Fixed a build issue on Xcode 26.5 (changelog extractor name collision).

## 0.1.9

**Apps that update themselves now clear correctly.** If an app updated through its own updater (for example, Chrome via "About Chrome") while DuoUpdater was busy installing other updates, it could keep showing a stale "update available" row long after it was already current. DuoUpdater now re-checks the moment the installs finish, so the row clears right away instead of lingering.

**"Update All" shows the whole queue.** Every app in an "Update All" run now shows a "Queued" state immediately, instead of leaving the ones further down the list looking idle with a clickable Update button. Clicking Update on an app that's already queued can no longer start a second install of it.
