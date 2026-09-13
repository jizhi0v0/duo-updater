import Foundation

enum org_zaproxy_zap_ZAP {
    static let set = AppRecipeSet(
        family: "org-zaproxy-zap-ZAP",
        githubRules: [
        // Shared rationale for 2026-08-16 coverage batch: Recipes/com-ccswitch-desktop.swift.
        // Shared rationale for Detection-only: Recipes/org-alacritty.swift.

        // OWASP ZAP — unsigned.
        GitHubReleaseRule(
            bundleID: "org.zaproxy.zap.ZAP",
            owner: "zaproxy", repo: "zaproxy"),
        ])
}
