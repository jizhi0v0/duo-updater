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
    /// regard to case), with the reason there is no recipe. Replace
    /// `notAssessed` with the real reason once someone has looked, or delete the
    /// line when a recipe lands.
    static let acknowledged: [String: String] = [
        "at.obdev.littlesnitch": notAssessed,
        "cc.ffitch.shottr": notAssessed,
        "com.aionui.app": notAssessed,
        "com.bjango.istatmenus": notAssessed,
        "com.bombich.ccc": notAssessed,
        "com.brave.Browser.beta": notAssessed,
        "com.brave.Browser.nightly": notAssessed,
        "com.exafunction.windsurf": notAssessed,
        "com.figma.DesktopBeta": notAssessed,
        "com.getdropbox.dropbox": notAssessed,
        "com.google.android.studio": notAssessed,
        "com.google.Chrome.beta": notAssessed,
        "com.google.Chrome.canary": notAssessed,
        "com.google.Chrome.dev": notAssessed,
        "com.hnc.Discord": notAssessed,
        "com.hnc.DiscordCanary": notAssessed,
        "com.hnc.DiscordPTB": notAssessed,
        "com.jetbrains.intellij-EAP": notAssessed,
        "com.kagi.kagimacOS": notAssessed,
        "com.macpaw.site.theunarchiver": notAssessed,
        "com.microsoft.edgemac": notAssessed,
        "com.microsoft.edgemac.Beta": notAssessed,
        "com.microsoft.Excel": notAssessed,
        "com.microsoft.OneDrive": notAssessed,
        "com.microsoft.onenote.mac": notAssessed,
        "com.microsoft.Outlook": notAssessed,
        "com.microsoft.Powerpoint": notAssessed,
        "com.microsoft.teams2": notAssessed,
        "com.microsoft.VSCodeInsiders": notAssessed,
        "com.microsoft.Word": notAssessed,
        "com.mongodb.compass": notAssessed,
        "com.nssurge.surge-mac": notAssessed,
        "com.robinebers.openusage": notAssessed,
        "com.runningwithcrayons.Alfred": notAssessed,
        "com.sogou.inputmethod.sogou": notAssessed,
        "com.steipete.codexbar": notAssessed,
        "com.sublimemerge": notAssessed,
        "com.surteesstudios.Bartender": notAssessed,
        "com.tdesktop.Telegram": notAssessed,
        "com.termius-dmg.mac": notAssessed,
        "com.tigervnc.tigervnc": notAssessed,
        "com.vivaldi.Vivaldi.snapshot": notAssessed,
        "dev.commandline.waveterm": notAssessed,
        "dev.warp.Warp-Dev": notAssessed,
        "im.riot.app": notAssessed,
        "im.riot.nightly": notAssessed,
        "MstyStudio": notAssessed,
        "net.librewolf.librewolf": notAssessed,
        "net.pornel.ImageOptim": notAssessed,
        "net.sourceforge.grandperspectiv": notAssessed,
        "net.whatsapp.WhatsApp": notAssessed,
        "org.gimp.gimp": notAssessed,
        "org.gnome.Meld": notAssessed,
        "org.gnu.Emacs": notAssessed,
        "org.libreoffice.script": notAssessed,
        "org.mozilla.firefox": notAssessed,
        "org.mozilla.firefoxdeveloperedition": notAssessed,
        "org.mozilla.nightly": notAssessed,
        "org.pgadmin.pgadmin4": notAssessed,
        "org.whispersystems.signal-desktop": notAssessed,
        "org.whispersystems.signal-desktop-beta": notAssessed,
        "org.zotero.zotero": notAssessed,
        "tv.plex.desktop": notAssessed,
    ]

    /// What every entry said when the list was started from the gaps that existed
    /// then (2026-10-10). Not a reason, a backlog marker.
    static let notAssessed = "not assessed yet — a gap when this list was started"

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
        let unassessed = accepted.filter { finding in
            acknowledged.first { $0.key.lowercased() == finding.bundleID.lowercased() }?.value
                == notAssessed
        }
        return "\(accepted.count) of \(mine.count) apps with a changelog page have no recipe "
            + "and are listed in ChangelogCoverage.acknowledged (\(unassessed.count) not assessed yet)"
    }
}
