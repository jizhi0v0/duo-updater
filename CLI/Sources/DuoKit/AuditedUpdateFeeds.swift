import Foundation
import DuoUpdaterCore

/// Public feed configurations established by the app-audit index, independent
/// of which applications happen to be installed on the nightly runner.
enum AuditedUpdateFeeds {
    enum Source: Sendable {
        case electron(ElectronUpdateConfig)
        case sparkle(feed: URL, publicKey: String?, channelNames: Set<String>)
    }

    struct Entry: Sendable {
        let name: String
        let bundleID: String
        /// The release-channel behavior to evaluate. `trackID` preserves a
        /// vendor's own label when it has no matching `ReleaseChannel` case.
        let channel: ReleaseChannel
        let trackID: String
        /// Separates observed feeds for the same bundle and track, such as
        /// Douchat's pre-migration and current public feed paths.
        let copyGroup: String?
        let source: Source
        /// Repo-relative source of the feed and track facts.
        let auditDocument: String

        var recipeID: String {
            let kind: String
            switch source {
            case .electron: kind = "electron"
            case .sparkle: kind = "sparkle"
            }
            let base = "\(kind):\(bundleID):\(trackID)"
            return copyGroup.map { "\(base):\($0)" } ?? base
        }

        /// A synthetic row for calling production sources without a machine's
        /// installed copy or preferences. Its path is deliberately nonexistent.
        var app: InstalledApp {
            let path = URL(fileURLWithPath:
                "/__duo_audited_feed_catalog__/\(recipeID).app")
            let sparkleFeed: URL?
            let electronUpdate: ElectronUpdateConfig?
            let publicKey: String?
            let channelNames: Set<String>
            let hasElectron: Bool
            switch source {
            case .electron(let config):
                sparkleFeed = nil
                electronUpdate = config
                publicKey = nil
                channelNames = []
                hasElectron = true
            case .sparkle(let feed, let key, let names):
                sparkleFeed = feed
                electronUpdate = nil
                publicKey = key
                channelNames = names
                hasElectron = false
            }
            return InstalledApp(
                name: name, bundleID: bundleID, shortVersion: "0", buildVersion: "0",
                path: path, isMASApp: false, sparkleFeedURL: sparkleFeed,
                electronUpdate: electronUpdate, sparkleChannelNames: channelNames,
                sparkleEdPublicKey: publicKey, hasSelfUpdater: hasElectron,
                hasSparkleUpdater: !hasElectron, releaseChannel: channel,
                channelIsAuthoritative: true)
        }
    }

    struct Gap: Sendable, Hashable {
        let bundleID: String
        let trackID: String
        let auditDocument: String
        let reason: String

        var id: String { "\(bundleID):\(trackID)" }
    }

    struct PublicKeyGap: Sendable, Hashable {
        let bundleID: String
        let auditDocument: String
        let reason: String
    }

    private static let rogueAmoebaAudit = "docs/app-audits/com-rogueamoeba-airfoil.md"
    private static let rogueAmoebaStable: [(name: String, id: String)] = [
        ("Airfoil", "com.rogueamoeba.Airfoil"),
        ("Airfoil Satellite", "com.rogueamoeba.AirfoilSpeakers"),
        ("Farrago", "com.rogueamoeba.farrago"),
        ("Fission", "com.rogueamoeba.Fission"),
        ("Loopback", "com.rogueamoeba.Loopback"),
        ("Piezo", "com.rogueamoeba.Piezo"),
        ("SoundSource", "com.rogueamoeba.soundsource"),
    ]

    /// Current rows in `docs/app-audits/README.md`'s Electron-covered and
    /// Sparkle-covered sections, represented only where an exact public feed
    /// and track are established by that row's linked audit.
    static let entries: [Entry] = ([
        sparkle("Acorn 8", "com.flyingmeat.Acorn8", .stable,
                feed: "https://flyingmeat.com/download/acorn8update.xml",
                audit: "docs/app-audits/com-flyingmeat-Acorn8.md"),
        sparkle("Acorn 8 Test Releases", "com.flyingmeat.Acorn8", .beta,
                feed: "https://flyingmeat.com/download/latest/acorn8update.xml",
                audit: "docs/app-audits/com-flyingmeat-Acorn8.md"),
        // The v6 and v26 packages share an ID but declare different appcasts.
        sparkle("Royal TSX v6", "com.lemonmojo.RoyalTSX.App", .stable,
                feed: "https://royaltsx-v6.royalapps.com/updates_stable",
                audit: "docs/app-audits/com-lemonmojo-RoyalTSX-App.md"),
        sparkle("Royal TSX v26 Beta", "com.lemonmojo.RoyalTSX.App", .beta,
                feed: "https://royaltsx-v26.royalapps.com/app/updates",
                channelNames: ["beta"], publicKey: "48ZqGC3v4p507RvAi3q5V02dh3GyoLF7VAuFqN1qTdA=",
                audit: "docs/app-audits/com-lemonmojo-RoyalTSX-App.md"),
        sparkle("Audio Hijack", "com.rogueamoeba.audiohijack", .stable,
                feed: SparkleFeedCatalog.feed(forBundleID: "com.rogueamoeba.audiohijack")!.absoluteString,
                audit: "docs/app-audits/com-rogueamoeba-audiohijack.md"),
        // Audit: docs/app-audits/com-moonshot-kimichat.md
        electron("Kimi", "com.moonshot.kimichat", .stable,
                 url: "https://kimi-img.moonshot.cn/app/upgrade/", channel: "latest",
                 audit: "docs/app-audits/com-moonshot-kimichat.md"),
        // Audit: docs/app-audits/com-kimi-code-desktop.md. Both public regional
        // feeds were observed to match; the bundle declares the mainland URL.
        electron("Kimi Code", "com.kimi.code.desktop", .stable,
                 url: "https://code.kimi.com/kimi-code/desktop/", channel: "latest",
                 copyGroup: "mainland-cn", audit: "docs/app-audits/com-kimi-code-desktop.md"),
        electron("Kimi Code", "com.kimi.code.desktop", .stable,
                 url: "https://code.kimi.ai/kimi-code/desktop/", channel: "latest",
                 copyGroup: "global", audit: "docs/app-audits/com-kimi-code-desktop.md"),
        // Audit: docs/app-audits/com-qodercn-app.md
        electron("Qoder CN", "com.qodercn.app", .stable,
                 url: "https://static.qoder.com.cn/qoder-app/releases", channel: "latest",
                 audit: "docs/app-audits/com-qodercn-app.md"),
        // Audit: docs/app-audits/ai-capy-desktop.md
        electron("Capy", "ai.capy.desktop", .stable,
                 url: "https://d1lfowv2t69uz0.cloudfront.net/stable/", channel: "latest",
                 audit: "docs/app-audits/ai-capy-desktop.md"),
        electron("Capy Nightly", "ai.capy.desktop.nightly", .nightly,
                 url: "https://d1lfowv2t69uz0.cloudfront.net/nightly/", channel: "latest",
                 audit: "docs/app-audits/ai-capy-desktop.md"),
        // Audit: docs/app-audits/app-shift.md
        electron("Shift", "app.shift", .stable,
                 url: "https://shift-editor.github.io/shift/updates/release/darwin/arm64",
                 channel: "latest", audit: "docs/app-audits/app-shift.md"),
        electron("Shift Nightly", "app.shift.nightly", .nightly,
                 url: "https://shift-editor.github.io/shift/updates/nightly/darwin/arm64",
                 channel: "latest", audit: "docs/app-audits/app-shift.md"),
        // Audit: docs/app-audits/ai-thinkany-douchat.md. The old bundle keeps
        // reading the root feed while current copies use /thinkany.
        electron("Douchat", "ai.thinkany.douchat", .stable,
                 url: "https://cdn.douchat.ai", channel: "latest",
                 copyGroup: "legacy-root", audit: "docs/app-audits/ai-thinkany-douchat.md"),
        electron("Douchat", "ai.thinkany.douchat", .stable,
                 url: "https://cdn.douchat.ai/thinkany", channel: "latest",
                 copyGroup: "thinkany", audit: "docs/app-audits/ai-thinkany-douchat.md"),
        // Audit: docs/app-audits/ai-ducoro-desktop.md. `alpha` in release.json
        // is a maturity label; the audited updater has only the default feed.
        electron("Ducoro", "ai.ducoro.desktop", .stable,
                 url: "https://static.ducoro.ai/desktop", channel: "latest",
                 audit: "docs/app-audits/ai-ducoro-desktop.md"),
        // Audit: docs/app-audits/com-deepseek-dsh.md. The manifest channel is
        // literally `nightly`; it serves the stable/RC line, not a nightly app
        // track. Alpha copies use a different VendorProbe route.
        electron("DeepSeek Harness", "com.deepseek.dsh", .stable,
                 url: "https://download.deepseek.com/dsh-desk/feeds/mac-arm64/",
                 channel: "nightly", audit: "docs/app-audits/com-deepseek-dsh.md"),

        // Audit: docs/app-audits/com-luckymarmot-Paw.md. Current copies
        // declare an Ed25519 key; legacy Paw/RapidAPI copies carry DSA only.
        sparkle("RapidAPI for Mac", "com.luckymarmot.Paw", .stable,
                feed: "https://paw.cloud/api/v2/updates/appcast",
                publicKey: "EbtjNsFuPe0o0UZDSFr/514GIusvouXngkfdmiKApHY=",
                copyGroup: "ed25519", audit: "docs/app-audits/com-luckymarmot-Paw.md"),
        sparkle("Paw / RapidAPI for Mac", "com.luckymarmot.Paw", .stable,
                feed: "https://paw.cloud/api/v2/updates/appcast",
                copyGroup: "legacy-dsa", audit: "docs/app-audits/com-luckymarmot-Paw.md"),
        // Audit: docs/app-audits/org-sil-ukelele.md. The signed bundle's
        // literal quotation marks make its declared URL unusable.
        sparkle("Ukelele", "org.sil.ukelele", .stable,
                feed: SparkleFeedCatalog.feed(forBundleID: "org.sil.ukelele")!.absoluteString,
                publicKey: "akGj2v0tJZhSIxt8IgV4Xx5lr7paN6sIshhWKJLPkVw=",
                audit: "docs/app-audits/org-sil-ukelele.md"),
        // Audit: docs/app-audits/com-MagicQuit.md. Both groups use the same
        // appcast, but only the newer ZIP installs ship its Ed25519 key.
        sparkle("MagicQuit", "com.MagicQuit", .stable,
                feed: SparkleFeedCatalog.feed(forBundleID: "com.MagicQuit")!.absoluteString,
                publicKey: "wFrCgZt+qwG6/UbxYscLbW9m2ttAS5AvQMC9ROCZr7g=",
                copyGroup: "ed25519", audit: "docs/app-audits/com-MagicQuit.md"),
        sparkle("MagicQuit legacy DMG", "com.MagicQuit", .stable,
                feed: SparkleFeedCatalog.feed(forBundleID: "com.MagicQuit")!.absoluteString,
                copyGroup: "legacy-no-key", audit: "docs/app-audits/com-MagicQuit.md"),

        // Audit: docs/app-audits/com-googlecode-iterm2.md. No query shard is
        // needed: the audit found it does not change the feed response. The
        // public key comes from the matching installed iTerm2 bundle.
        sparkle("iTerm2", "com.googlecode.iterm2", .stable,
                feed: "https://iterm2.com/appcasts/final_modern.xml",
                publicKey: "xdqAa0KXBPhMbUrutVTe87i6U7yWf7WKaCeRG7AAZ0w=",
                audit: "docs/app-audits/com-googlecode-iterm2.md"),
        sparkle("iTerm2 Test Release", "com.googlecode.iterm2", .beta,
                trackID: "test-release", feed: "https://iterm2.com/appcasts/testing_modern.xml",
                publicKey: "xdqAa0KXBPhMbUrutVTe87i6U7yWf7WKaCeRG7AAZ0w=",
                audit: "docs/app-audits/com-googlecode-iterm2.md"),
        sparkle("iTerm2 Nightly", "com.googlecode.iterm2", .nightly,
                feed: "https://iterm2.com/appcasts/nightly_modern.xml",
                publicKey: "xdqAa0KXBPhMbUrutVTe87i6U7yWf7WKaCeRG7AAZ0w=",
                audit: "docs/app-audits/com-googlecode-iterm2.md"),
        // Audit: docs/app-audits/company-thebrowser-Browser.md. Early Birds
        // requires enrollment and the observed feed path contains a UUID, so
        // only the general public stable feed is catalogued.
        sparkle("Arc", "company.thebrowser.Browser", .stable,
                feed: "https://releases.arc.net/updates.xml",
                audit: "docs/app-audits/company-thebrowser-Browser.md"),
        // Audit: docs/app-audits/company-thebrowser-dia.md. The invite-only RC
        // feed is omitted for the same reason as Arc's.
        sparkle("Dia Browser", "company.thebrowser.dia", .stable,
                feed: "https://releases.diabrowser.com/BoostBrowser-updates.xml",
                publicKey: "PuVxvsbwitqWEvMPriVhNzmiMiVp2AqD8psqG/qcS98=",
                audit: "docs/app-audits/company-thebrowser-dia.md"),
        // Audit: docs/app-audits/com-knollsoft-Rectangle.md
        sparkle("Rectangle", "com.knollsoft.Rectangle", .stable,
                feed: "https://rectangleapp.com/downloads/updates.xml",
                publicKey: "lpt9M3PhocbZ3MZiLH+crEqRfU11kfoNzGxSqiEIdvM=",
                audit: "docs/app-audits/com-knollsoft-Rectangle.md"),
        // Audit: docs/app-audits/com-colliderli-iina.md
        sparkle("IINA", "com.colliderli.iina", .stable,
                feed: "https://www.iina.io/appcast.xml",
                publicKey: "UpwCRYfYOg0OGgQHY6RUdrV29yPcdkvxGlEfq46r6a0=",
                audit: "docs/app-audits/com-colliderli-iina.md"),
        sparkle("IINA", "com.colliderli.iina", .beta,
                feed: "https://www.iina.io/appcast-beta.xml",
                publicKey: "UpwCRYfYOg0OGgQHY6RUdrV29yPcdkvxGlEfq46r6a0=",
                audit: "docs/app-audits/com-colliderli-iina.md"),
        // Audit: docs/app-audits/com-proxyman-NSProxy.md
        sparkle("Proxyman", "com.proxyman.NSProxy", .stable,
                feed: "https://proxyman.com/osx/version.xml",
                publicKey: "moo+qhr/G4+n9W2vxaHqPhJapVgAT/nHteYD0CBsZF4=",
                audit: "docs/app-audits/com-proxyman-NSProxy.md"),
        // Audit: docs/app-audits/app-monitorcontrol-MonitorControl.md. The
        // current feed has no beta-tagged item; see uncoveredTracks below.
        sparkle("MonitorControl", "app.monitorcontrol.MonitorControl", .stable,
                feed: "https://monitorcontrol.app/appcast2.xml",
                publicKey: "ITSTMp8AypsLawojJ+UR3tm2mN18AFoNMvXf1G3t62s=",
                audit: "docs/app-audits/app-monitorcontrol-MonitorControl.md"),
        // Audit: docs/app-audits/com-JH-RuntimeViewer.md
        sparkle("RuntimeViewer", "com.JH.RuntimeViewer", .stable,
                feed: "https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml",
                audit: "docs/app-audits/com-JH-RuntimeViewer.md"),
        sparkle("RuntimeViewer", "com.JH.RuntimeViewer", .beta,
                feed: "https://mxiris-reverse-engineering.github.io/RuntimeViewer/appcast.xml",
                channelNames: ["beta"], audit: "docs/app-audits/com-JH-RuntimeViewer.md"),
        // Audit: docs/app-audits/plus-yellow-AirBuild.md
        sparkle("AirBuild", "plus.yellow.AirBuild", .stable,
                feed: "https://release.air.build/macos/appcast.xml",
                publicKey: "xPc2c4nfaYOLmG2PTK3uDRxSaMsTgeq1qvZ/pFjFk7I=",
                audit: "docs/app-audits/plus-yellow-AirBuild.md"),
        sparkle("AirBuild", "plus.yellow.AirBuild", .beta,
                feed: "https://release.air.build/macos/appcast.xml",
                channelNames: ["beta"],
                publicKey: "xPc2c4nfaYOLmG2PTK3uDRxSaMsTgeq1qvZ/pFjFk7I=",
                audit: "docs/app-audits/plus-yellow-AirBuild.md"),
        // Audit: docs/app-audits/com-superlogical-rex.md
        sparkle("Rex", "com.superlogical.rex", .preview,
                feed: "https://blob.superlogical.com/public/rex-app/preview-arm64/appcast.xml",
                publicKey: "jG2oqfrStpD6pfzWIBAHHbER3yTLaZWToni8eZiBzxE=",
                audit: "docs/app-audits/com-superlogical-rex.md"),
        sparkle("Rex Bleeding Edge", "com.superlogical.rex", .nightly,
                trackID: "snapshot", feed: "https://blob.superlogical.com/public/rex-app/snapshot-arm64/appcast.xml",
                publicKey: "jG2oqfrStpD6pfzWIBAHHbER3yTLaZWToni8eZiBzxE=",
                audit: "docs/app-audits/com-superlogical-rex.md"),
        // Audit: docs/app-audits/org-p0deje-Maccy.md
        sparkle("Maccy", "org.p0deje.Maccy", .stable,
                feed: "https://raw.githubusercontent.com/p0deje/Maccy/master/appcast.xml",
                audit: "docs/app-audits/org-p0deje-Maccy.md"),
        // Audit: docs/app-audits/app-trellisui-trelliswm.md. The newer domain
        // is in current bundles; the older URL remains a byte-identical alias.
        sparkle("TrellisWM", "app.trellisui.trelliswm", .stable,
                feed: "https://trelliswm.app/appcast.xml",
                audit: "docs/app-audits/app-trellisui-trelliswm.md"),
        // Audit: docs/app-audits/com-aone-keka.md. Dev builds read this same
        // untagged feed and resolve to stable; there is no separate dev feed.
        sparkle("Keka", "com.aone.keka", .stable,
                feed: "https://u.keka.io",
                publicKey: "PJ6aXb+39SYsZE/LswCK3Oiw5hjkfwgZ89LpMS58+z0=",
                audit: "docs/app-audits/com-aone-keka.md"),
        // Audit: docs/app-audits/com-vivaldi-Vivaldi.md. Snapshot is a separate
        // audited bundle ID, with its own public feed.
        sparkle("Vivaldi", "com.vivaldi.Vivaldi", .stable,
                feed: "https://update.vivaldi.com/update/1.0/public/mac/appcast.xml",
                audit: "docs/app-audits/com-vivaldi-Vivaldi.md"),
        sparkle("Vivaldi Snapshot", "com.vivaldi.Vivaldi.snapshot", .preview,
                trackID: "snapshot",
                feed: "https://update.vivaldi.com/update/1.0/snapshot/mac/appcast.xml",
                audit: "docs/app-audits/com-vivaldi-Vivaldi.md"),
        // Audit: docs/app-audits/com-obsproject-obs-studio.md. The arm64 feed
        // is the supported host's observed feed; the x86_64 feed is excluded.
        sparkle("OBS", "com.obsproject.obs-studio", .stable,
                feed: "https://obsproject.com/osx_update/updates_arm64_v2.xml",
                channelNames: ["stable"],
                publicKey: "HQ5/Ba9VHOuEWaM0jtVjZzgHKFJX9YTl+HNVpgNF0iM=",
                audit: "docs/app-audits/com-obsproject-obs-studio.md"),
        sparkle("OBS", "com.obsproject.obs-studio", .beta,
                feed: "https://obsproject.com/osx_update/updates_arm64_v2.xml",
                channelNames: ["beta"],
                publicKey: "HQ5/Ba9VHOuEWaM0jtVjZzgHKFJX9YTl+HNVpgNF0iM=",
                audit: "docs/app-audits/com-obsproject-obs-studio.md"),
        // Audit: docs/app-audits/fr-handbrake-HandBrake.md. Use arm64 feeds;
        // the snapshot package is a distinct public track but shares the ID.
        sparkle("HandBrake", "fr.handbrake.HandBrake", .stable,
                feed: "https://handbrake.fr/appcast.arm64.xml",
                publicKey: "aeDqvDkdHhSaNiWXf13dD72+hwWhLz6jD4sdHGP+Vbg=",
                audit: "docs/app-audits/fr-handbrake-HandBrake.md"),
        sparkle("HandBrake Snapshot", "fr.handbrake.HandBrake", .nightly,
                trackID: "snapshot", feed: "https://handbrake.fr/appcast_unstable.arm64.xml",
                publicKey: "aeDqvDkdHhSaNiWXf13dD72+hwWhLz6jD4sdHGP+Vbg=",
                audit: "docs/app-audits/fr-handbrake-HandBrake.md"),
        // Audit: docs/app-audits/ai-openclaw-mac.md. Both public Apple Silicon
        // copy groups are indexed; Intel's x86_64 feed is outside host support.
        sparkle("OpenClaw Universal", "ai.openclaw.mac", .stable,
                feed: "https://raw.githubusercontent.com/openclaw/openclaw/main/appcast.xml",
                copyGroup: "universal", audit: "docs/app-audits/ai-openclaw-mac.md"),
        sparkle("OpenClaw arm64", "ai.openclaw.mac", .stable,
                feed: "https://raw.githubusercontent.com/openclaw/openclaw/main/appcast-arm64.xml",
                copyGroup: "arm64", audit: "docs/app-audits/ai-openclaw-mac.md"),
        // Audit: docs/app-audits/com-superduper-superwhisper.md. Beta feed and
        // preference mapping were not established; see uncoveredTracks.
        sparkle("Superwhisper", "com.superduper.superwhisper", .stable,
                feed: "https://superwhisper.com/appcast.xml",
                publicKey: "LaNqajeJmIalBugxXQ/11U9E7xKcnzBiVMsY1DkpWQM=",
                audit: "docs/app-audits/com-superduper-superwhisper.md"),
        // Audit: docs/app-audits/com-steipete-codexbar.md
        sparkle("CodexBar", "com.steipete.codexbar", .stable,
                feed: "https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml",
                audit: "docs/app-audits/com-steipete-codexbar.md"),
        // Audit: docs/app-audits/com-tddworks-claudebar.md
        sparkle("ClaudeBar", "com.tddworks.claudebar", .stable,
                feed: "https://tddworks.github.io/ClaudeBar/appcast.xml",
                audit: "docs/app-audits/com-tddworks-claudebar.md"),
        // Audit: docs/app-audits/com-prakashjoshipax-VoiceInk.md
        sparkle("VoiceInk", "com.prakashjoshipax.VoiceInk", .stable,
                feed: "https://beingpax.github.io/VoiceInk/appcast.xml",
                audit: "docs/app-audits/com-prakashjoshipax-VoiceInk.md"),
        // Audit: docs/app-audits/uk-co-bzwrd-macperfmonitor.md
        sparkle("Mac Performance Monitor", "uk.co.bzwrd.macperfmonitor", .stable,
                feed: "https://github.com/Zesty0wl/mac-performance-monitor/releases/latest/download/appcast.xml",
                audit: "docs/app-audits/uk-co-bzwrd-macperfmonitor.md"),
        // Audit: docs/app-audits/com-github-CopilotForXcode.md
        sparkle("GitHub Copilot for Xcode", "com.github.CopilotForXcode", .stable,
                feed: "https://githubcopilotide.z13.web.core.windows.net/appcast.xml",
                audit: "docs/app-audits/com-github-CopilotForXcode.md"),
        sparkle("GitHub Copilot for Xcode", "com.github.CopilotForXcode", .beta,
                trackID: "prerelease",
                feed: "https://githubcopilotide.z13.web.core.windows.net/appcast.xml",
                channelNames: ["prerelease"], audit: "docs/app-audits/com-github-CopilotForXcode.md"),
        // Audit: docs/app-audits/com-goodsnooze-MacWhisper.md
        sparkle("MacWhisper", "com.goodsnooze.MacWhisper", .stable,
                feed: "https://macwhisper-site.vercel.app/appcast.xml",
                audit: "docs/app-audits/com-goodsnooze-MacWhisper.md"),
        // Audit: docs/app-audits/ai-perplexity-macv3.md
        sparkle("Perplexity", "ai.perplexity.macv3", .stable,
                feed: "https://macos-download.perplexity.ai/appcast.xml",
                audit: "docs/app-audits/ai-perplexity-macv3.md"),
        // Audit: docs/app-audits/com-typewhisper-mac.md
        sparkle("TypeWhisper", "com.typewhisper.mac", .stable,
                feed: "https://typewhisper.github.io/typewhisper-mac/appcast.xml",
                audit: "docs/app-audits/com-typewhisper-mac.md"),
        sparkle("TypeWhisper", "com.typewhisper.mac", .rc,
                trackID: "release-candidate",
                feed: "https://typewhisper.github.io/typewhisper-mac/appcast.xml",
                channelNames: ["release-candidate"], audit: "docs/app-audits/com-typewhisper-mac.md"),
        sparkle("TypeWhisper", "com.typewhisper.mac", .nightly,
                trackID: "daily",
                feed: "https://typewhisper.github.io/typewhisper-mac/appcast.xml",
                channelNames: ["daily"], audit: "docs/app-audits/com-typewhisper-mac.md"),
        // Audit: docs/app-audits/com-robinebers-openusage.md
        sparkle("OpenUsage", "com.robinebers.openusage", .stable,
                feed: "https://robinebers.github.io/openusage/appcast.xml",
                audit: "docs/app-audits/com-robinebers-openusage.md"),
        sparkle("OpenUsage", "com.robinebers.openusage", .beta,
                feed: "https://robinebers.github.io/openusage/appcast.xml",
                channelNames: ["beta"], audit: "docs/app-audits/com-robinebers-openusage.md"),
        // Audit: docs/app-audits/app-supabit-supacode.md
        sparkle("Supacode", "app.supabit.supacode", .stable,
                feed: "https://supacode.sh/download/latest/appcast.xml",
                audit: "docs/app-audits/app-supabit-supacode.md"),
        sparkle("Supacode Tip", "app.supabit.supacode", .preview,
                trackID: "tip", feed: "https://supacode.sh/download/latest/appcast.xml",
                channelNames: ["tip"], audit: "docs/app-audits/app-supabit-supacode.md"),
        // Audit: docs/app-audits/com-readdle-PDFExpert-Mac.md. Use the live
        // pem3 feed that supersedes the app's frozen public URL.
        sparkle("PDF Expert", "com.readdle.PDFExpert-Mac", .stable,
                feed: "https://downloads.pdfexpert.com/pem3/release/appcast.xml",
                publicKey: "K5sdt9UTWp/TcP48oRVycKUqWUbi0Tp37zrWtFYCCfw=",
                audit: "docs/app-audits/com-readdle-PDFExpert-Mac.md"),
        // Audit: docs/app-audits/app-codeedit-CodeEdit.md. Its only track is
        // labelled `dev` in the feed; this does not mean a beta release.
        sparkle("CodeEdit", "app.codeedit.CodeEdit", .stable,
                feed: "https://github.com/CodeEditApp/CodeEdit/releases/latest/download/appcast.xml",
                channelNames: ["dev"], audit: "docs/app-audits/app-codeedit-CodeEdit.md"),
        // Audit: docs/app-audits/com-dinoki-osaurus.md
        sparkle("Osaurus", "com.dinoki.osaurus", .stable,
                feed: "https://osaurus-ai.github.io/osaurus/appcast.xml",
                channelNames: ["release"], audit: "docs/app-audits/com-dinoki-osaurus.md"),
        // Audit: docs/app-audits/com-coconut-flavour-coconutBattery.md
        sparkle("coconutBattery", "com.coconut-flavour.coconutBattery", .stable,
                feed: "https://coconut-flavour.com/updates/coconutBattery_4.xml",
                audit: "docs/app-audits/com-coconut-flavour-coconutBattery.md"),
        // Audit: docs/app-audits/com-daisydiskapp-DaisyDiskStandAlone.md
        sparkle("DaisyDisk", "com.daisydiskapp.DaisyDiskStandAlone", .stable,
                feed: "https://daisydiskapp.com/downloads/appcastFeed.php",
                audit: "docs/app-audits/com-daisydiskapp-DaisyDiskStandAlone.md"),
        // Audit: docs/app-audits/com-supercmd-SuperCmd.md. v1 is Electron and
        // detection-only; only the v2 Sparkle bundles are catalogued.
        sparkle("SuperCmd", "com.supercmd.SuperCmd", .stable,
                feed: "https://raw.githubusercontent.com/SuperCmdLabs/supercmd-v2-releases/main/appcast.xml",
                publicKey: "SuZyMrxjljAlwkHsFMWbEppSMnTnT9jp/Q8L9NLa1VI=",
                audit: "docs/app-audits/com-supercmd-SuperCmd.md"),
        sparkle("SuperCmd Beta", "com.supercmd.SuperCmd.beta", .beta,
                feed: "https://raw.githubusercontent.com/SuperCmdLabs/supercmd-v2-releases/main/appcast-beta.xml",
                publicKey: "SuZyMrxjljAlwkHsFMWbEppSMnTnT9jp/Q8L9NLa1VI=",
                audit: "docs/app-audits/com-supercmd-SuperCmd.md"),
        // Audit: docs/app-audits/com-superoutman-ShiftBar-prototype.md
        sparkle("ShiftBar", "com.superoutman.ShiftBar.prototype", .stable,
                feed: "https://github.com/Superoutman/ShiftBar/releases/latest/download/appcast.xml",
                audit: "docs/app-audits/com-superoutman-ShiftBar-prototype.md"),
        // Audit: docs/app-audits/com-swiftvm-app.md
        sparkle("SwiftVM", "com.swiftvm.app", .stable,
                feed: "https://github.com/swiftvm-app/swiftvm/releases/latest/download/appcast.xml",
                publicKey: "tFq+VHZspKMGDj7ZF/SVMLTzjdFXEadBu5vMGOMHU2g=",
                audit: "docs/app-audits/com-swiftvm-app.md"),
        sparkle("SwiftVM", "com.swiftvm.app", .beta,
                feed: "https://github.com/swiftvm-app/swiftvm/releases/download/beta-channel/appcast-beta.xml",
                channelNames: ["beta"],
                publicKey: "tFq+VHZspKMGDj7ZF/SVMLTzjdFXEadBu5vMGOMHU2g=",
                audit: "docs/app-audits/com-swiftvm-app.md"),
        // Audit: docs/app-audits/org-cindori-Sensei.md
        sparkle("Sensei", "org.cindori.Sensei", .stable,
                feed: "https://cdn.cindori.com/apps/sensei/updates/update.xml",
                audit: "docs/app-audits/org-cindori-Sensei.md"),
        // Audit: docs/app-audits/com-cindori-Backdrop.md
        sparkle("Backdrop", "com.cindori.Backdrop", .stable,
                feed: "https://cdn.cindori.com/apps/backdrop/updates/update.xml",
                publicKey: "0tE8tm68wzs86WvnbDQL4vK4/yErTHLNc/0XrZ8mPOE=",
                audit: "docs/app-audits/com-cindori-Backdrop.md"),
        // Audit: docs/app-audits/run-kuvo-app.md. The live Box feed replaces
        // the appcast still named by older Box builds.
        sparkle("Kuvo Box", "run.kuvo.app", .stable,
                feed: "https://github.com/serhatandic/box/releases/latest/download/appcast.xml",
                publicKey: "uG/YbzL4kf+DAYCiTTfK8ztEOBo96hkEAuKk9rw9BE4=",
                audit: "docs/app-audits/run-kuvo-app.md"),
        // Audit: docs/app-audits/run-kuvo-code.md
        sparkle("Kuvo Code", "run.kuvo.code", .stable,
                feed: "https://github.com/serhatandic/kuvo-code/releases/latest/download/appcast.xml",
                publicKey: "uG/YbzL4kf+DAYCiTTfK8ztEOBo96hkEAuKk9rw9BE4=",
                audit: "docs/app-audits/run-kuvo-code.md"),
        sparkle("Kuvo Code", "run.kuvo.code", .beta,
                feed: "https://github.com/serhatandic/kuvo-code/releases/latest/download/appcast.xml",
                channelNames: ["beta"],
                publicKey: "uG/YbzL4kf+DAYCiTTfK8ztEOBo96hkEAuKk9rw9BE4=",
                audit: "docs/app-audits/run-kuvo-code.md"),
        // Audit: docs/app-audits/com-xx-seedmux.md. Only the arm64 feed is
        // in scope for the supported Apple Silicon runner.
        sparkle("Seedmux", "com.xx.seedmux", .stable,
                feed: "https://github.com/wishworldbetter/seedmux/releases/latest/download/appcast.xml",
                audit: "docs/app-audits/com-xx-seedmux.md"),
        // Audit: docs/app-audits/sb-moe-tamio.md
        sparkle("Tamio", "sb.moe.tamio", .stable,
                feed: "https://github.com/missuo/tamio/releases/latest/download/appcast.xml",
                publicKey: "FGnM3UVskuCdONiYX+6KbArkar0D5lYS73IeqOmWrps=",
                audit: "docs/app-audits/sb-moe-tamio.md"),
        // Audit: docs/app-audits/com-loon-Loon.md
        sparkle("Loon", "com.loon.Loon", .stable,
                feed: "https://raw.githubusercontent.com/Loon0x00/Loon4Mac/refs/heads/main/appcast.xml",
                publicKey: "uEraTruMBhN4ATxXmON6F27zstasLdhxCx/yht+cEJE=",
                audit: "docs/app-audits/com-loon-Loon.md"),
    ] + rogueAmoebaStable.map { app in
        sparkle(app.name, app.id, .stable, feed: SparkleFeedCatalog.feed(forBundleID: app.id)!.absoluteString,
                audit: rogueAmoebaAudit)
    }).sorted { $0.recipeID < $1.recipeID }

    /// Entire rows excluded because their audit does not establish a live public
    /// feed that this catalog can honestly monitor.
    static let uncoveredRows: [Gap] = [
        Gap(
            bundleID: "now.typeless.desktop", trackID: "sparkle-row",
            auditDocument: "docs/app-audits/now-typeless-desktop.md",
            reason: "The index groups Typeless here, but its audit says the active source is a VendorProbe electron-builder feed, not Sparkle; VendorProbe is outside this inventory."),
        Gap(
            bundleID: "com.openai.atlas", trackID: "stable",
            auditDocument: "docs/app-audits/com-openai-atlas.md",
            reason: "OpenAI stopped the app and the audited appcast is frozen; this is a sunset feed, not a current update source."),
    ]

    /// Tracks named by an audit but intentionally not represented as live feed
    /// entries because the public feed or the track itself is not established.
    static let uncoveredTracks: [Gap] = [
        Gap(
            bundleID: "org.sil.ukelele", trackID: "beta",
            auditDocument: "docs/app-audits/org-sil-ukelele.md",
            reason: "The shared appcast retains historical beta items whose enclosures all returned 404. Beta copies can graduate to the current stable release, which is monitored."),
        Gap(
            bundleID: "com.rogueamoeba.soundsource", trackID: "legacy-5",
            auditDocument: rogueAmoebaAudit,
            reason: "SoundSource 5 is retired and its last signed app excludes macOS 27 onward. Its version-qualified public feed is available on supported older hosts."),
        Gap(
            bundleID: "com.kimi.code.desktop", trackID: "canary",
            auditDocument: "docs/app-audits/com-kimi-code-desktop.md",
            reason: "The canary builds are in a private GitHub repository; no public feed is available."),
        Gap(
            bundleID: "company.thebrowser.Browser", trackID: "rc",
            auditDocument: "docs/app-audits/company-thebrowser-Browser.md",
            reason: "Early Birds requires enrollment and the only observed RC feed URL contains a copy-specific UUID; no general public RC endpoint is established."),
        Gap(
            bundleID: "company.thebrowser.dia", trackID: "rc",
            auditDocument: "docs/app-audits/company-thebrowser-dia.md",
            reason: "Early Birds requires enrollment and the only observed RC feed URL contains a copy-specific UUID; no general public RC endpoint is established."),
        Gap(
            bundleID: "ai.deepseek.dsh", trackID: "alpha",
            auditDocument: "docs/app-audits/com-deepseek-dsh.md",
            reason: "Alpha uses the versioned-DMG VendorProbe route; the shared Electron nightly feed is stale for alpha builds."),
        Gap(
            bundleID: "ai.openclaw.mac", trackID: "beta,extended-stable",
            auditDocument: "docs/app-audits/ai-openclaw-mac.md",
            reason: "The app supports these Sparkle labels, but the audited public feed has no tagged beta or extended-stable items."),
        Gap(
            bundleID: "com.superduper.superwhisper", trackID: "beta",
            auditDocument: "docs/app-audits/com-superduper-superwhisper.md",
            reason: "The beta preference/feed mapping is unverified and no public beta feed was established."),
        Gap(
            bundleID: "app.monitorcontrol.MonitorControl", trackID: "beta",
            auditDocument: "docs/app-audits/app-monitorcontrol-MonitorControl.md",
            reason: "The audited appcast has no beta-tagged items; the preference is ready for a future feed change only."),
        Gap(
            bundleID: "com.coconut-flavour.coconutBattery", trackID: "beta",
            auditDocument: "docs/app-audits/com-coconut-flavour-coconutBattery.md",
            reason: "The audited beta mapping has no beta-tagged items. A live testing-tagged item was observed; its mapping to installed beta preferences has not been established."),
        Gap(
            bundleID: "com.dinoki.osaurus", trackID: "beta",
            auditDocument: "docs/app-audits/com-dinoki-osaurus.md",
            reason: "A live feed beta item was observed after the audit, but its mapping to installed beta copies/preferences has not been established; only the audited release track is catalogued."),
    ] + rogueAmoebaStable.map {
        Gap(bundleID: $0.id, trackID: "test-releases", auditDocument: rogueAmoebaAudit,
            reason: "The vendor's stable appcast has no test-release items and no verified public test feed is mapped to installed copies.")
    }

    /// Sparkle identities whose complete public EdDSA key was not available in
    /// the matching installed app plist or the linked published audit. A missing
    /// value stays nil in `Source.sparkle`; these records make that limitation
    /// explicit for archive-verification consumers.
    static let unavailablePublicKeys: [PublicKeyGap] = [
        PublicKeyGap(bundleID: "com.flyingmeat.Acorn8",
                     auditDocument: "docs/app-audits/com-flyingmeat-Acorn8.md",
                     reason: "The verified stable and test release archives use a legacy DSA key and carry no SUPublicEDKey."),
        PublicKeyGap(bundleID: "com.MagicQuit",
                     auditDocument: "docs/app-audits/com-MagicQuit.md",
                     reason: "The legacy 1.4 DMG predates Sparkle and ships no SUPublicEDKey. The 2.0 ZIP matches the independently recorded Ed25519 key."),
        PublicKeyGap(bundleID: "com.lemonmojo.RoyalTSX.App",
                     auditDocument: "docs/app-audits/com-lemonmojo-RoyalTSX-App.md",
                     reason: "Royal TSX v6 uses legacy DSA only. The v26 beta has a separately recorded Ed25519 key."),
        PublicKeyGap(bundleID: "com.rogueamoeba.audiohijack",
                     auditDocument: "docs/app-audits/com-rogueamoeba-audiohijack.md",
                     reason: "Both verified direct bundles have no SUPublicEDKey. The Sparkle install uses the Developer ID and Team ID checks."),
        PublicKeyGap(bundleID: "ai.openclaw.mac", auditDocument: "docs/app-audits/ai-openclaw-mac.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "ai.perplexity.macv3", auditDocument: "docs/app-audits/ai-perplexity-macv3.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "app.codeedit.CodeEdit", auditDocument: "docs/app-audits/app-codeedit-CodeEdit.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "app.supabit.supacode", auditDocument: "docs/app-audits/app-supabit-supacode.md",
                     reason: "The audit states that the bundle has no SUPublicEDKey; its installer path uses code-signature and Team checks."),
        PublicKeyGap(bundleID: "app.trellisui.trelliswm", auditDocument: "docs/app-audits/app-trellisui-trelliswm.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.JH.RuntimeViewer", auditDocument: "docs/app-audits/com-JH-RuntimeViewer.md",
                     reason: "The audit establishes that current bundles have a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.coconut-flavour.coconutBattery", auditDocument: "docs/app-audits/com-coconut-flavour-coconutBattery.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.daisydiskapp.DaisyDiskStandAlone", auditDocument: "docs/app-audits/com-daisydiskapp-DaisyDiskStandAlone.md",
                     reason: "The audit states that the bundle has no SUPublicEDKey and uses legacy DSA only; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.dinoki.osaurus", auditDocument: "docs/app-audits/com-dinoki-osaurus.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.github.CopilotForXcode", auditDocument: "docs/app-audits/com-github-CopilotForXcode.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.goodsnooze.MacWhisper", auditDocument: "docs/app-audits/com-goodsnooze-MacWhisper.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.luckymarmot.Paw", auditDocument: "docs/app-audits/com-luckymarmot-Paw.md",
                     reason: "The legacy-dsa group (verified Paw 3.4.0 and RapidAPI 4.5.2) has no SUPublicEDKey; code-signature and Team checks still apply. Current copies have the separately recorded Ed25519 key."),
        PublicKeyGap(bundleID: "com.prakashjoshipax.VoiceInk", auditDocument: "docs/app-audits/com-prakashjoshipax-VoiceInk.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.robinebers.openusage", auditDocument: "docs/app-audits/com-robinebers-openusage.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.steipete.codexbar", auditDocument: "docs/app-audits/com-steipete-codexbar.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.superoutman.ShiftBar.prototype", auditDocument: "docs/app-audits/com-superoutman-ShiftBar-prototype.md",
                     reason: "The audit confirms signed feed items but does not publish the full public key; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.tddworks.claudebar", auditDocument: "docs/app-audits/com-tddworks-claudebar.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.typewhisper.mac", auditDocument: "docs/app-audits/com-typewhisper-mac.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
        PublicKeyGap(bundleID: "com.vivaldi.Vivaldi", auditDocument: "docs/app-audits/com-vivaldi-Vivaldi.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.vivaldi.Vivaldi.snapshot", auditDocument: "docs/app-audits/com-vivaldi-Vivaldi.md",
                     reason: "The audit establishes that the Snapshot bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "com.xx.seedmux", auditDocument: "docs/app-audits/com-xx-seedmux.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "company.thebrowser.Browser", auditDocument: "docs/app-audits/company-thebrowser-Browser.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "org.cindori.Sensei", auditDocument: "docs/app-audits/org-cindori-Sensei.md",
                     reason: "The audit establishes that the bundle has a public key but does not publish its full value; no matching installed copy was available."),
        PublicKeyGap(bundleID: "org.p0deje.Maccy", auditDocument: "docs/app-audits/org-p0deje-Maccy.md",
                     reason: "The matching installed copy's Info.plist has no SUPublicEDKey; the audit records the signature and Team fallback, not an EdDSA key."),
        PublicKeyGap(bundleID: "uk.co.bzwrd.macperfmonitor", auditDocument: "docs/app-audits/uk-co-bzwrd-macperfmonitor.md",
                     reason: "No matching installed copy or full public key in the linked audit was available from the permitted sources."),
    ] + rogueAmoebaStable.map {
        PublicKeyGap(bundleID: $0.id, auditDocument: rogueAmoebaAudit,
                     reason: "The verified direct bundle has no SUPublicEDKey. Installation checks the Developer ID seal, Team ID, bundle ID and offered build.")
    }

    private static func electron(
        _ name: String, _ bundleID: String, _ channel: ReleaseChannel,
        trackID: String? = nil, url: String, channel manifestChannel: String,
        copyGroup: String? = nil, audit: String
    ) -> Entry {
        Entry(
            name: name, bundleID: bundleID, channel: channel,
            trackID: trackID ?? channel.rawValue, copyGroup: copyGroup,
            source: .electron(ElectronUpdateConfig(
                provider: "generic", url: url, owner: nil, repo: nil,
                channel: manifestChannel)),
            auditDocument: audit)
    }

    private static func sparkle(
        _ name: String, _ bundleID: String, _ channel: ReleaseChannel,
        trackID: String? = nil, feed: String, channelNames: Set<String> = [],
        publicKey: String? = nil, copyGroup: String? = nil, audit: String
    ) -> Entry {
        Entry(
            name: name, bundleID: bundleID, channel: channel,
            trackID: trackID ?? channel.rawValue, copyGroup: copyGroup,
            source: .sparkle(
                feed: URL(string: feed)!, publicKey: publicKey, channelNames: channelNames),
            auditDocument: audit)
    }
}
