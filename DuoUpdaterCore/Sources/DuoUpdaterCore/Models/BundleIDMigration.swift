import Foundation

/// A vendor that renamed its app's bundle id between two releases, recorded
/// so a copy still on the old id is checked and updated as the app it is.
///
/// Recipes are keyed by the NEW id, the one the vendor ships today. Four
/// places read this table, and nothing else does — an entry changes all four:
///  - `InstalledApp.recipeBundleID` files an old-id copy under the new id, so
///    vendor probes, GitHub rules and changelog recipes find it. `bundleID`
///    itself stays the id on disk.
///  - `AppRestarter.runningInstances` queries running processes under both ids
///    of a pair (`relatedBundleIDs`) and then filters by path, so restart and
///    quit reach an old-id process still running from a bundle just swapped
///    to the new id.
///  - `SignatureVerifier.verifyBundleIdentifierMatch` lets a download signed as
///    `to` replace a copy signed as `from` — that one direction, only for the
///    registered Team, only for an installed version below `firstToVersion`.
///    The Team-ID gate still runs first, unchanged.
///  - `BackupStore.keyCandidates` looks for a rollback point under both ids of
///    a pair, at the same path, so the backup an update saved under the old id
///    is found once the bundle is the new one; `BackupStore.restore` then puts
///    it back only through `restoreMigration`, for the registered Team.
///
/// `firstToVersion` is a bound, not a guess at the exact release that switched:
/// a copy still signed as `from` at or above it is not the rename we measured,
/// so it gets neither the recipes nor the swap. Record the versions as observed
/// on real artifacts and say where in the app's audit doc.
public struct BundleIDMigration: Sendable, Equatable {
    public let from: String
    public let to: String
    /// The Team both ids are signed by. A migration never crosses Teams.
    public let teamID: String
    /// The newest release observed still signed as `from`.
    public let lastFromVersion: String
    /// The oldest release observed signed as `to`.
    public let firstToVersion: String
    /// The `to` app is the vendor's rewrite, not the same app under a new id:
    /// features and settings may not carry over. An update across it still
    /// installs, but only after the user confirms it — `UpdateResult`'s
    /// `isVendorRewrite` routes the row through the major-upgrade confirmation,
    /// whatever the source. False for a plain rename.
    public let isRewrite: Bool

    public init(
        from: String, to: String, teamID: String,
        lastFromVersion: String, firstToVersion: String, isRewrite: Bool = false
    ) {
        self.from = from
        self.to = to
        self.teamID = teamID
        self.lastFromVersion = lastFromVersion
        self.firstToVersion = firstToVersion
        self.isRewrite = isRewrite
    }

    public static let all: [BundleIDMigration] = [
        // WorkBuddy, China site: 5.3.14 (2026-08-17) is `com.workbuddy.workbuddy`,
        // 5.5.4 (2026-09-16) and every build since is `com.tencent.workbuddy.mac`;
        // the releases between could not be fetched. The vendor's own updater
        // migrates old copies (its 5.1.0 notes: "macOS Bundle ID 迁移更新器") and
        // the new app carries a helper signed as the old id to unregister the old
        // login item. See docs/app-audits/com-tencent-workbuddy-mac.md, 历史与实测.
        BundleIDMigration(
            from: "com.workbuddy.workbuddy", to: "com.tencent.workbuddy.mac",
            teamID: "FN2V63AD2J", lastFromVersion: "5.3.14", firstToVersion: "5.5.4"),
        // PrintCraft became PdfCraft: v0.2.1 is PrintCraft.app,
        // `ai.storyteller.printcraft`; v0.4.0 is PdfCraft.app,
        // `ai.storyteller.pdfcraft`, the same Team; there is no 0.3.x release.
        // PdfCraft moves PrintCraft's settings folder to its own on first launch
        // (`migrate_legacy_folders` in the vendor's `apps/pdfcraft/src/main.rs`).
        // See docs/app-audits/ai-storyteller-photocraft.md, PdfCraft 改名.
        BundleIDMigration(
            from: "ai.storyteller.printcraft", to: "ai.storyteller.pdfcraft",
            teamID: "DJ6XS33FX8", lastFromVersion: "0.2.1", firstToVersion: "0.4.0"),
        // Moshi's Tauri app hands over to its native rewrite, Moshi Go: every
        // Tauri build (through 0.4.23) is `app.getmoshi.desktop.tauri`, every
        // Moshi Go build (from 0.5.0) is `app.getmoshi.desktop`, the same Team.
        // The vendor's Tauri updater feed itself now serves Moshi Go ("Macs with
        // Apple silicon move to it with a normal update", its 0.4.23 notes), and
        // Moshi Go carries a Tauri settings import (`MigrateFromTauri`, read from
        // its binary; the import itself has not been run here). So a Tauri
        // copy is checked and one-click updated as Moshi Go, through Moshi Go's
        // feed and MyGo key; nothing is keyed by the Tauri id any more.
        // History: docs/app-audits/app-getmoshi-desktop-tauri.md#历史与实测
        BundleIDMigration(
            from: "app.getmoshi.desktop.tauri", to: "app.getmoshi.desktop",
            teamID: "FL442366Y7", lastFromVersion: "0.4.23", firstToVersion: "0.5.0"),
        // WhatCable: v0.2.0 through v0.5.14 are `com.bitmoor.whatcable`; v0.6.0
        // (2026-05-05, the same day) and every release since are
        // `uk.whatcable.whatcable`, the same Team, all notarized. The vendor's
        // v0.6.0 notes call it a one-time change: replacing the app by hand is the
        // supported upgrade, the old in-app updater may refuse it, and
        // preferences, notification permission and launch at login reset.
        // See docs/app-audits/uk-whatcable-whatcable.md, 改名前的 bundle id.
        BundleIDMigration(
            from: "com.bitmoor.whatcable", to: "uk.whatcable.whatcable",
            teamID: "M4RUJ7W6MP", lastFromVersion: "0.5.14", firstToVersion: "0.6.0"),
        // Cork changed its bundle id twice, the same Team throughout: up to
        // 1.4.4 it is `com.davidbures.Cork`, from 1.4.4.1 through 1.5.7
        // `com.davidbures.cork` (also the frozen macOS 13 build, 1.5.6), and
        // from 1.6.0 `eu.davidbures.cork`. The vendor's 1.6.0 post announces
        // the change: settings may reset once and the licence email may have
        // to be entered again. Read off the real zips; see
        // docs/app-audits/eu-davidbures-cork.md, 历史与实测.
        BundleIDMigration(
            from: "com.davidbures.Cork", to: "eu.davidbures.cork",
            teamID: "ZSVA6DVZHM", lastFromVersion: "1.4.4", firstToVersion: "1.6.0"),
        BundleIDMigration(
            from: "com.davidbures.cork", to: "eu.davidbures.cork",
            teamID: "ZSVA6DVZHM", lastFromVersion: "1.5.7", firstToVersion: "1.6.0"),
        // MusicBrainz Picard changed only the case of its id: the 2.0.4 dmg is
        // `org.musicbrainz.picard`, the 2.3.1 dmg and every release since are
        // `org.musicbrainz.Picard`, the same Team. The vendor's mirror carries no
        // 2.1.x or 2.2.x dmg; the repo's `picard.spec` still writes the lower-case
        // id at release-2.1.3 and `PICARD_APP_ID` (the mixed-case id) from release-2.2.0 on.
        // See docs/app-audits/org-musicbrainz-Picard.md, 旧 bundle id.
        BundleIDMigration(
            from: "org.musicbrainz.picard", to: "org.musicbrainz.Picard",
            teamID: "8D89TSJ88H", lastFromVersion: "2.0.4", firstToVersion: "2.3.1"),
        // SwitchHosts: every Electron release read (3.5.8, 4.0.3, 4.1.2, 4.2.0)
        // is `SwitchHosts`; v4.3.0 (a prerelease) and every Tauri v5 release are
        // `net.oldj.switchhosts`, the same Team, all notarized. v5 migrates the
        // v4 data on first launch (the vendor's `src-tauri/src/migration`).
        // See docs/app-audits/net-oldj-switchhosts.md, 旧 bundle id.
        BundleIDMigration(
            from: "SwitchHosts", to: "net.oldj.switchhosts",
            teamID: "J5J6USUX2F", lastFromVersion: "4.2.0", firstToVersion: "4.3.0"),
        // MySQL Workbench 8.0 is the native app, `com.oracle.workbench.MySQLWorkbench`,
        // through 8.0.47 (8.0.46 and 8.0.47 measured); 26.7.0 is the Electron
        // rewrite on MySQL Shell, `com.oracle.mysqlworkbench`, the same Team. 8.0's
        // own "Check for Updates" reads `workbench.mysql.com/current-release`,
        // which answers 26.7.0, so the vendor itself points 8.0 copies at the
        // rewrite. A rewrite, not a rename: the swap is confirmed by the user first.
        // History: docs/app-audits/com-oracle-mysqlworkbench.md#历史与实测
        BundleIDMigration(
            from: "com.oracle.workbench.MySQLWorkbench", to: "com.oracle.mysqlworkbench",
            teamID: "VB5E2TV963", lastFromVersion: "8.0.47", firstToVersion: "26.7.0",
            isRewrite: true),
        // TaskExplorer changed the case of its id with the 3.0 rewrite: the
        // 2.1.0 zip is `com.objective-see.TaskExplorer`, the 3.0.0 and 3.1.0
        // zips are `com.objective-see.taskexplorer`, the same Team; there are
        // no releases between. 2.1.0's own update check reads the same
        // products.json key that now names 3.1.0, so the vendor offers 3.x to
        // 2.x copies as an ordinary update: a rename, not `isRewrite`, although
        // its 3.0.0 notes call the code "a near complete rewrite". See
        // docs/app-audits/com-objective-see-taskexplorer.md, 旧 bundle id.
        BundleIDMigration(
            from: "com.objective-see.TaskExplorer", to: "com.objective-see.taskexplorer",
            teamID: "VBG97UB4TA", lastFromVersion: "2.1.0", firstToVersion: "3.0.0"),
        // AFFiNE's 2023 desktop previews shipped as `com.electron.affine`:
        // v0.5.2 ("AFFiNE Desktop App Preview") says CFBundleShortVersionString
        // 0.0.0, the v0.5.3 prerelease says 0.5.3. Stable releases from v0.6.0
        // are `pro.affine.app` (betas and canaries have their own ids), the same
        // Team; all measured on the real arm64 dmgs. The old id is Electron's
        // default shape, so the Team bound matters: it holds the swap and the
        // rollback to 73YMMDVT2M, but detection files any `com.electron.affine`
        // copy below 0.6.0 under AFFiNE whatever its Team, and a copy from
        // another Team is only refused at the install's Team gate.
        // Marked a rewrite so the swap is confirmed first: whether a preview
        // workspace carries over to 0.27 was not checked.
        // History: docs/app-audits/pro-affine-app.md#已知问题
        BundleIDMigration(
            from: "com.electron.affine", to: "pro.affine.app",
            teamID: "73YMMDVT2M", lastFromVersion: "0.5.3", firstToVersion: "0.6.0",
            isRewrite: true),
        // Museeks' first two Tauri releases shipped with the bare bundle id
        // `Museeks` (0.20.0 and 0.21.1); 0.22.0 went back to `io.museeks.app`,
        // the id the Electron builds had. All three are Team YK6MWU3892 and
        // notarized (measured on the real universal dmgs). A rename, not a
        // rewrite: the Tauri app keeps its data in the same
        // `~/Library/Application Support/museeks` folder across it.
        // History: docs/app-audits/io-museeks-app.md#已知问题
        BundleIDMigration(
            from: "Museeks", to: "io.museeks.app",
            teamID: "YK6MWU3892", lastFromVersion: "0.21.1", firstToVersion: "0.22.0"),
        // Rclone UI: the 1.0.2, 1.4.0, 1.9.0 and 1.9.3 dmgs are `com.stray.app`,
        // the 2.0.0 dmg and every release read since are `com.rclone.ui`, the
        // same Team, all notarized. 1.9.3's own Tauri updater reads the same
        // `latest.json` that now names 3.x, so the vendor offers 2.x to 1.x
        // copies as an ordinary update; its 2.0.0 notes call the id change
        // breaking and ask users to back up their config first.
        // See docs/app-audits/com-rclone-ui.md, 旧 bundle id.
        BundleIDMigration(
            from: "com.stray.app", to: "com.rclone.ui",
            teamID: "8FT82R3S6A", lastFromVersion: "1.9.3", firstToVersion: "2.0.0"),
    ]

    /// Whether an installed copy signed as `from` at `version` is this rename.
    /// No version, no match: the bound is the whole guard.
    func covers(installedVersion version: String?) -> Bool {
        guard let version else { return false }
        return VersionComparator.compare(version, firstToVersion) == .orderedAscending
    }

    /// The id an installed copy's recipes are filed under: the new id for a
    /// registered old id below its bound, the id itself otherwise.
    public static func recipeBundleID(
        for bundleID: String, installedVersion: String?, in table: [BundleIDMigration] = all
    ) -> String {
        table.first { $0.from == bundleID && $0.covers(installedVersion: installedVersion) }?.to
            ?? bundleID
    }

    /// The registered rewrite an installed copy signed as `bundleID` at
    /// `installedVersion` is the old app of, or nil. Same bound as
    /// `recipeBundleID`: only a copy that is filed under the new id counts.
    public static func rewrite(
        installed bundleID: String, installedVersion: String?, in table: [BundleIDMigration] = all
    ) -> BundleIDMigration? {
        table.first {
            $0.isRewrite && $0.from == bundleID && $0.covers(installedVersion: installedVersion)
        }
    }

    /// `bundleID` and every id a registered rename pairs it with, in either
    /// direction. For finding processes by path: right after a swap the bundle
    /// on disk is the new id while the process still running from that path is
    /// the old one. Callers must still filter by path; this only widens the
    /// identifier query.
    public static func relatedBundleIDs(
        of bundleID: String, in table: [BundleIDMigration] = all
    ) -> [String] {
        [bundleID] + table.compactMap {
            $0.from == bundleID ? $0.to : ($0.to == bundleID ? $0.from : nil)
        }
    }

    /// The registered rename that lets a rollback put a backup whose bundle id is
    /// `backup` over an installed copy whose id is `installed`, or nil. Either
    /// direction: rolling back across the rename puts `from` over `to`. Both
    /// Teams must be the entry's, and the copy on the `from` side must be below
    /// the bound — the same three conditions an update across it has to meet.
    public static func restoreMigration(
        backup: String, installed: String, backupVersion: String?, installedVersion: String?,
        backupTeam: String?, installedTeam: String?, in table: [BundleIDMigration] = all
    ) -> BundleIDMigration? {
        table.first {
            guard backupTeam == $0.teamID, installedTeam == $0.teamID else { return false }
            if $0.from == backup, $0.to == installed {
                return $0.covers(installedVersion: backupVersion)
            }
            if $0.to == backup, $0.from == installed {
                return $0.covers(installedVersion: installedVersion)
            }
            return false
        }
    }

    /// The registered rename that lets a download signed as `downloaded` replace
    /// a copy signed as `installed`, or nil. Both Teams must be the entry's.
    public static func migration(
        installed: String, downloaded: String, installedVersion: String?,
        installedTeam: String?, downloadedTeam: String?, in table: [BundleIDMigration] = all
    ) -> BundleIDMigration? {
        table.first {
            $0.from == installed && $0.to == downloaded
                && installedTeam == $0.teamID && downloadedTeam == $0.teamID
                && $0.covers(installedVersion: installedVersion)
        }
    }
}
