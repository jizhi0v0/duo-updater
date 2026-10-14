**Blocking findings: 1**

1. `docs/app-audits/rocks-spotifast-Spotifast.md:87`: copies still on the pre-rename id `me.paolino.fastpotify` (Fastpotify 0.1.0–0.9.1, same Team) get no detection. The audit doesn't decide to leave them out. It puts off the decision, even though the repository already has the mechanism for this case (`BundleIDMigration`). Under REVIEW.md ("A gap recorded as a decision needs a reason that holds"), that means the group is neither covered nor recorded.
   - Trigger: a user has Fastpotify 0.9.1 (or any 0.1.0–0.9.1 build) installed. Its bundle id is `me.paolino.fastpotify`. The only rule is keyed by `rocks.spotifast.Spotifast`, and `BundleIDMigration.all` only lists WorkBuddy, so `InstalledApp.recipeBundleID` leaves the id unchanged. There is no Sparkle feed and no Homebrew cask to fall back on. The copy silently gets no update detection, while releases/latest is v0.13.1.
   - Evidence: the audit says the copy goes undetected, then leaves the choice open:
     > `规则只按新 id 注册，所以旧 id 副本不会被检测到；没有加 BundleIDMigration。上游自己在 e10a8d4a6（2026-10-03）已删掉 updater 里的旧名字、旧 bundle id 和旧安装路径，0.9.0 及更早直接升级的用户会拿到一个新 profile。要不要为旧 id 加迁移条目留给维护者决定` (lines 88–90)

     "建议下一步" at lines 113–114 even lists the entry's bounds (`lastFrom 0.9.1，firstTo 0.10.0`) as something still to decide. The only reason given, "upstream dropped its own old-id handling", does not explain why `BundleIDMigration` wouldn't apply.
     - The upstream commit (GitHub API, `repos/crmne/spotifast/commits/e10a8d4a6`) only removes profile-moving from the new app: "Someone updating straight from 0.9.0 or older starts with a fresh profile; their old files stay where they were." So the vendor still expects old copies to update straight to current builds, and our swap would do the same thing.
     - `BundleIDMigration` (`Models/BundleIDMigration.swift:3-22`) is the table built for exactly this case: same Team, measured bounds, and a recipe lookup under the new id.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/rocks-spotifast-Spotifast.swift:31`: "One-click: Team JPL7999US3 on 0.12.0 and 0.13.0, notarized dmg, one executable and no nested apps or helpers". The rule uses the default `.developerID` trust. If a future dmg is signed by a different Team or isn't notarized, one-click is refused. If the bundle does carry a helper or nested app, the install path is wrong for it.
- `docs/app-audits/rocks-spotifast-Spotifast.md:59`: the upstream updater only swaps on "Restart to update", and there is no "auto-swap a staged build on quit". If that is false, the vendor's staged build could overwrite a version DuoUpdater just installed. The audit itself says this is read from source, not tested.
- `docs/app-audits/rocks-spotifast-Spotifast.md:5`: 0.10.0 / 0.12.0 / 0.13.0 are signed by Team `JPL7999US3`. If any of them differs, the Team-ID gate refuses the install for copies on that version.

**Other unverified external claims**

- `docs/app-audits/rocks-spotifast-Spotifast.md:34`: the upstream updater defaults to `Prereleases::Never` and pushes rc builds only to stable ("settled from source: fastframe-update README").
- `docs/app-audits/rocks-spotifast-Spotifast.md:9`: there is no official homebrew-cask entry for `spotifast` or `fastpotify` (`brew info --cask` was unavailable on 2026-10-14).
- `docs/app-audits/rocks-spotifast-Spotifast.md:64-66`: the changelog pane shows "19 entries; newest 0.13.0: 42 items, headings [\"New\", \"Fixed\"]", and the channel-verify results for 0.12.0 → 0.13.0 (local runs).
- `docs/app-audits/rocks-spotifast-Spotifast.md:46`: the 0.12.0 and 0.13.0 dmgs have `LSMinimumSystemVersion` = `11.0` and are universal.
- `docs/app-audits/rocks-spotifast-Spotifast.md:100-101`: the v0.10.0 dmg contains `rocks.spotifast.Spotifast` and the v0.9.1 dmg contains `me.paolino.fastpotify` (mounted locally).
