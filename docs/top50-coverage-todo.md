# TOP50 coverage TODO

Source: MacUpdater "Top Mac Apps - Most Popular 1000 Apps", checked against the
top 50 on 2026-06-04.

This is a handoff list for future agents. Mark an item done only after verifying
the installed app's actual update channel and adding the right coverage:

- Sparkle in `Info.plist` means no bespoke detection recipe is needed.
- Homebrew cask only counts as detection coverage when the cask is
  `auto_updates:false`; `auto_updates:true` needs Sparkle, GitHubReleaseRule, or
  VendorProbe coverage for direct/self-updating installs.
- MAS apps should stay MAS-managed. Do not add vendor recipes for App Store-only
  installs unless there is a separate direct-download build worth supporting.
- Every new fragile recipe must be live-validated and covered by an offline
  fixture test.

## High priority

- [x] Microsoft Teams — top 50 rank 14.
      Verify direct install / pkg updater behavior; add `VendorProbe` only if a
      stable public version endpoint exists. Document if it is MAU-managed.
- [x] OneDrive — rank 28.
      Verify direct install / Microsoft AutoUpdate behavior; add coverage or
      document as managed/unworkable.
- [x] Microsoft PowerPoint — rank 18.
      MAS installs are covered. Verified direct MAU installs — fwlink 302 detection
      added (all Office apps share unified 16.x.y versioning).
- [x] Microsoft Word — rank 19.
      Same fwlink detection as PowerPoint.
- [x] Microsoft Excel — rank 20.
      Same fwlink detection as PowerPoint.
- [x] Microsoft OneNote — rank 32.
      Uses Office suite fwlink (linkid=525133); all Office apps share the same
      unified 16.x version.
- [x] Microsoft Outlook — rank 38.
      Uses Office AutoUpdate XML manifest endpoint. MAU-managed, detection-only.
- [x] Bartender — rank 27.
      Sparkle appcast confirmed at AppcastB6.xml. Uses ascending feed
      (selectHighest). Detection-only — SparkleAppcastSource takes priority if
      SUFeedURL is in Info.plist.
- [x] ImageOptim — rank 22.
      Sparkle appcast confirmed at imageoptim.com/appcast.xml. Detection-only.
- [x] Transmission — rank 15.
      Verified Transmission has SUFeedURL in Info.plist → SparkleAppcastSource
      handles it automatically. No recipe needed.

## Medium priority

- [ ] AppCleaner — rank 1.
      `ChangelogRecipe` exists, but detection coverage still needs verification.
      Confirm whether Sparkle/direct endpoint/Homebrew handles it; otherwise add
      `VendorProbe`.
- [ ] CheatSheet — rank 33.
      Verify Sparkle/direct endpoint; otherwise document as stale/unworkable.
- [ ] Hidden Bar — rank 24.
      Likely GitHub-backed; verify bundle id and add `GitHubReleaseRule` if
      direct installs are otherwise unknown.
- [ ] EasyFind — rank 23.
      Verify MAS/direct/Homebrew behavior; document if MAS-only.
- [ ] Google Earth Pro — rank 44.
      Verify direct updater or Homebrew coverage; document if not worth bespoke
      support.
- [ ] XQuartz — rank 35.
      Verify cask/system-component behavior. Avoid adding noisy update prompts
      if it is better treated as managed infrastructure.
- [ ] Skype — rank 36.
      Verify Microsoft updater behavior and whether it shares the MAU path.
- [ ] Android File Transfer — rank 10.
      Old app. Verify whether a stable source still exists; otherwise document
      as stale/no-source.

## Low priority / likely stale

- [ ] Caffeine — rank 45.
      Old app. Verify whether a current maintained source exists.
- [ ] Intel Power Gadget — rank 46.
      Old/discontinued-looking app. Document as stale if no maintained source.
- [ ] Logitech Unifying Software — rank 47.
      Old device utility. Verify whether Logi Options+/Bolt supersedes it before
      adding any recipe.
- [ ] Latest — rank 40.
      It is itself an updater. Only add coverage if it has a clean Sparkle/GitHub
      path and does not create confusing nested-updater behavior.

## Already covered or intentionally excluded from this TODO

- Covered explicitly or via existing generic source: VLC, The Unarchiver, Google
  Chrome, IINA, Firefox, HandBrake, Alfred, Discord, 1Password, Macs Fan Control,
  iTerm, Visual Studio Code.
- MAS-managed top-50 entries: Pages, iMovie, Numbers, Keynote, GarageBand,
  Speedtest, Amphetamine, Shazam, Magnet, Twitter, WireGuard, Xcode,
  iBooks Author, Save to Pocket.
- Known no-go / do not re-attempt casually: Spotify, WhatsApp. See
  `docs/app-onboarding-status.md` and the `Known-unfeasible` comments in
  `VendorProbeRecipe.swift`.
