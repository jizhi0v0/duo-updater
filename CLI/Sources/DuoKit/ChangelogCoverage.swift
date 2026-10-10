import Foundation
import DuoUpdaterCore

/// Apps that link a changelog page but have no `ChangelogRecipe` to structure it.
///
/// Such an app still shows notes: the pane embeds the vendor's page in a web view.
/// So nothing breaks and no other check says a word, and that is how TRAE went
/// unnoticed after its docs page caught up: the page was readable, the recipe
/// had been ruled out at audit time, and no sweep ever asked again.
///
/// A page comes from a vendor probe's `changelogURL` or from `ChangelogCatalog`.
/// Every app with one gets a finding under `coverage:<bundle id>`:
///   * a recipe exists → `ok`;
///   * no recipe, listed in `acknowledged` → `ok`, counted in the report's summary;
///   * no recipe, not listed → `warn` (`noChangelogRecipe`), which files an issue;
///   * listed, but it has a recipe now or links no page any more → `warn`
///     (`staleAcknowledgement`), so the list does not outlive its reasons.
///
/// An acknowledged gap is `ok` rather than `skipped` on purpose: `Reconcile` closes
/// an issue only on `ok`, and adding an app to the list is how a gap's issue ends
/// when no recipe is coming.
///
/// Static: nothing is fetched. Whether a page CAN be structured is for
/// `/fragile-recipe` to find out; this only keeps the question from being forgotten.
enum ChangelogCoverage {

    /// Gaps nobody needs to be told about again, by bundle id (matched without
    /// regard to case), with the reason there is no recipe. Each one was read
    /// against the live page; the evidence is in the PR that set the reason.
    /// A reason starting with `notWrittenYet` is backlog, not a verdict: a recipe
    /// is possible along the line it names. Delete the line when one lands.
    static let acknowledged: [String: String] = [
        "com.aionui.app":
            "feasible, not written yet: .gitHubReleases on iOfficeAI/AionUi",
        "com.bjango.istatmenus":
            "the page prints 7.5 for version 7.50, which no pattern can pad; newest entry is a placeholder",
        "com.brave.Browser.beta":
            "brave.com/latest lists release-channel versions only; beta notes are not published",
        "com.brave.Browser.nightly":
            "brave.com/latest lists release-channel versions only; nightly builds have no notes",
        "com.figma.DesktopBeta":
            "feasible, not written yet: the stable Figma atom recipe under the beta bundle id",
        "com.getdropbox.dropbox":
            "feasible but weak: one forum post per build, and the offered build often has none",
        "com.google.android.studio":
            "feasible but thin: one entry per channel for the latest train only; beta has none",
        "com.google.Chrome.beta":
            "release-notes page is a stub; the Releases blog's beta posts are a one-line version note",
        "com.google.Chrome.canary":
            "no published Canary notes (the blog label is empty; the release-notes page is a stub)",
        "com.google.Chrome.dev":
            "release-notes page is a stub; the Releases blog's dev posts are a one-line version note",
        "com.hnc.Discord":
            "blog posts keyed by date, with no client version per entry (discord.com/blog)",
        "com.hnc.DiscordCanary":
            "blog posts keyed by date, with no client version per entry (discord.com/blog)",
        "com.hnc.DiscordPTB":
            "blog posts keyed by date, with no client version per entry (discord.com/blog)",
        "com.jetbrains.intellij-EAP":
            "EAP whatsnew in the releases API only links a YouTrack issue table",
        "com.macpaw.site.theunarchiver":
            "feasible but low value: regex on the DevMate notes page; the app has not shipped since 4.3.9",
        "com.microsoft.teams2":
            "monthly cross-platform what's-new with no client version per entry",
        "com.mongodb.compass":
            "feasible, not written yet: .gitHubReleases on mongodb-js/compass, or regex on the docs release notes",
        "com.nssurge.surge-mac":
            "Sparkle feeds carry inline markdownDescription notes on every item; the page is a JS shell",
        "com.robinebers.openusage":
            "feasible, not written yet: .gitHubReleases on robinebers/openusage, stable and beta",
        "com.steipete.codexbar":
            "Sparkle appcast ships inline HTML notes for every item, so the page is never shown",
        "com.surteesstudios.Bartender":
            "feasible, not written yet: feedPagePattern on the appcast's per-version rnotes.html",
        "com.tigervnc.tigervnc":
            "feasible, not written yet: .gitHubReleases on TigerVNC/tigervnc (some bodies are prose only)",
        "com.vivaldi.Vivaldi.snapshot":
            "feasible, not written yet: the stable Vivaldi recipe on the feed's relnotes/snapshot/<version>.html page",
        "dev.commandline.waveterm":
            "feasible, not written yet: .gitHubReleases on wavetermdev/waveterm",
        "dev.warp.Warp-Dev":
            "the dev track publishes no notes: its channel_versions.json entry is a placeholder",
        "im.riot.nightly":
            "nightly build stamps (YYYYMMDDNN) have no tag or notes of their own",
        "net.librewolf.librewolf":
            "release bodies only link Firefox's upstream notes; tags carry a -N build suffix",
        "net.pornel.ImageOptim":
            "Sparkle appcast carries inline description notes, so the page is never shown",
        "net.sourceforge.grandperspectiv":
            "news page is behind a Cloudflare challenge (403); its RSS posts are single prose paragraphs",
        "net.whatsapp.WhatsApp":
            "WhatsApp publishes no Mac release notes; the App Store listing's What's New is boilerplate",
        "org.gimp.gimp":
            "prose release announcements mixed into a news index; no per-version change list",
        "org.gnu.Emacs":
            "feasible but headlines only: the home page's #Releases highlights; full NEWS is one text file per version",
        "org.libreoffice.script":
            "landing page of blurbs; the real notes are per branch, on a bot-walled wiki",
        "tv.plex.desktop":
            "feasible but weak: a forum thread that posts only some releases, via an undocumented JSON clamp",
    ]

    /// How a reason says "a recipe is possible, nobody has written it".
    static let notWrittenYet = "feasible, not written yet: "

    static func recipeID(_ bundleID: String) -> String {
        "\(Registry.changelogCoverage.rawValue):\(bundleID)"
    }

    /// Bundle id (lowercased) → the spelling to report and the pages it links.
    static func pages(
        probes: [VendorProbeRecipe], catalog: [String: URL]
    ) -> [String: (bundleID: String, urls: [URL])] {
        var out: [String: (bundleID: String, urls: [URL])] = [:]
        func add(_ bundleID: String, _ url: URL) {
            let key = bundleID.lowercased()
            var entry = out[key] ?? (bundleID, [])
            if !entry.urls.contains(url) { entry.urls.append(url) }
            out[key] = entry
        }
        for probe in probes {
            if let url = probe.changelogURL { add(probe.bundleID, url) }
        }
        for (bundleID, url) in catalog.sorted(by: { $0.key < $1.key }) { add(bundleID, url) }
        return out
    }

    static func findings(
        probes: [VendorProbeRecipe] = VendorProbeRegistry.recipes,
        catalog: [String: URL] = ChangelogCatalog.pages,
        recipes: [ChangelogRecipe] = ChangelogRecipeRegistry.recipes,
        acknowledged: [String: String] = Self.acknowledged
    ) -> [Finding] {
        let pages = pages(probes: probes, catalog: catalog)
        let structured = Set(recipes.map { $0.bundleID.lowercased() })
        var listed: [String: (bundleID: String, reason: String)] = [:]
        for (bundleID, reason) in acknowledged { listed[bundleID.lowercased()] = (bundleID, reason) }

        return Set(pages.keys).union(listed.keys).sorted().map { key in
            let page = pages[key]
            let bundleID = page?.bundleID ?? listed[key]?.bundleID ?? key
            let host = page?.urls.first?.host ?? "-"
            func finding(_ status: FindingStatus, _ kind: String? = nil, _ detail: String? = nil) -> Finding {
                Finding(
                    recipeID: recipeID(bundleID), registry: .changelogCoverage,
                    bundleID: bundleID, channel: "-", status: status,
                    failureKind: kind, failureDetail: detail, endpointHost: host)
            }
            switch (structured.contains(key), page, listed[key]) {
            case (true, _, nil), (false, _?, _?):
                return finding(.ok)
            case (true, _, _?):
                return finding(.warn, "staleAcknowledgement",
                    "has a ChangelogRecipe now — delete its line from ChangelogCoverage.acknowledged")
            case (false, nil, _):
                return finding(.warn, "staleAcknowledgement",
                    "no recipe links a changelog page for it any more — delete its line "
                        + "from ChangelogCoverage.acknowledged")
            case (false, let page?, nil):
                let links = page.urls.map(\.absoluteString).joined(separator: ", ")
                return finding(.warn, "noChangelogRecipe",
                    "links a changelog page (\(links)) but has no ChangelogRecipe, so the "
                        + "app embeds the page instead of showing structured notes. Write one "
                        + "(/fragile-recipe), or add the bundle id to "
                        + "ChangelogCoverage.acknowledged with the reason there will not be one")
            }
        }
    }

    /// For the report's summary: how many of these findings are gaps the list
    /// accepts. nil when the sweep produced none of this registry's findings.
    static func summary(_ findings: [Finding]) -> String? {
        let mine = findings.filter { $0.registry == .changelogCoverage }
        guard !mine.isEmpty else { return nil }
        let keys = Set(acknowledged.keys.map { $0.lowercased() })
        let accepted = mine.filter { $0.status == .ok && keys.contains($0.bundleID.lowercased()) }
        let backlog = accepted.filter { finding in
            acknowledged.first { $0.key.lowercased() == finding.bundleID.lowercased() }?.value
                .hasPrefix(notWrittenYet) == true
        }
        return "\(accepted.count) of \(mine.count) apps with a changelog page have no recipe "
            + "and are listed in ChangelogCoverage.acknowledged (\(backlog.count) feasible, "
            + "not written yet)"
    }
}
