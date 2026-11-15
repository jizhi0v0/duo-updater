import Foundation

enum run_kuvo_app {
    static let set = AppRecipeSet(
        family: "run-kuvo-app",
        supersededFeeds: [
            // History: docs/app-audits/run-kuvo-app.md#历史与实测
            // Kuvo's Docker app is now Kuvo Box. The old repository address
            // serves the unrelated Kuvo Code product, signed by the same Team
            // and update key. Keep the products separate by their bundle ids;
            // this feed move is not a BundleIDMigration. The Box appcast's
            // absolute release URLs move to the new repository with it.
            "run.kuvo.app": SparkleFeedCatalog.SupersededFeed(
                declared: URL(string: "https://github.com/serhatandic/kuvo/releases/latest/download/appcast.xml")!,
                live: URL(string: "https://github.com/serhatandic/box/releases/latest/download/appcast.xml")!,
                justification: .declaredFeedServesDifferentProduct),
        ],
        changelogPages: [
            "run.kuvo.app": URL(string: "https://github.com/serhatandic/box/releases")!,
        ])
}
