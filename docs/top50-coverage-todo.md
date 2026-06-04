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

- [ ] Microsoft Teams — top 50 rank 14.
      Verify direct install / pkg updater behavior; add `VendorProbe` only if a
      stable public version endpoint exists. Document if it is MAU-managed.
- [ ] OneDrive — rank 28.
      Verify direct install / Microsoft AutoUpdate behavior; add coverage or
      document as managed/unworkable.
- [ ] Microsoft PowerPoint — rank 18.
      MAS installs are covered. Verify direct Microsoft AutoUpdate installs and
      decide whether Office apps need a shared MAU-managed path.
- [ ] Microsoft Word — rank 19.
      Same Office/MAU verification as PowerPoint.
- [ ] Microsoft Excel — rank 20.
      Same Office/MAU verification as PowerPoint.
- [ ] Microsoft OneNote — rank 32.
      Same Office/MAU verification as PowerPoint.
- [ ] Microsoft Outlook — rank 38.
      Same Office/MAU verification as PowerPoint.
- [ ] Bartender — rank 27.
      Verify Sparkle first. If no `SUFeedURL`, add `VendorProbe`; add
      `ChangelogRecipe` only if notes are clean and versioned.
- [ ] ImageOptim — rank 22.
      Verify Sparkle/GitHub. Add detection coverage for direct installs if
      Homebrew auto-update behavior is not enough.
- [ ] Transmission — rank 15.
      Verify Sparkle/GitHub. Add detection coverage for direct installs if
      needed.

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
