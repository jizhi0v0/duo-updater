import Foundation

enum org_zaproxy_zap_ZAP {
    static let set = AppRecipeSet(
        family: "org-zaproxy-zap-ZAP",
        githubRules: [
        // OWASP ZAP — unsigned.
        GitHubReleaseRule(
            bundleID: "org.zaproxy.zap.ZAP",
            owner: "zaproxy", repo: "zaproxy"),
        ])
}
