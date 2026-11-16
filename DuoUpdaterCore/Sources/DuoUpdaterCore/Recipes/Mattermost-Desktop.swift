import Foundation

enum Mattermost_Desktop {
    // History: docs/app-audits/Mattermost-Desktop.md#历史与实测
    static let set = AppRecipeSet(
        family: "Mattermost-Desktop",
        changelogs: ["Mattermost.Desktop", "com.electron.electron-mattermost", "com.electron.mattermost"].map { bundleID in
            // The vendor docs' Markdown source contains the actual changes;
            // GitHub release bodies are download lists. Each bold full-version
            // marker owns its notes, including patch releases nested under a
            // minor heading. Stop at the next marker so a patch never inherits
            // the original minor release's changes. Retain section/platform
            // headings and omit the download line and "Original ... release".
            ChangelogRecipe(
                bundleID: bundleID,
                source: URL(string: "https://raw.githubusercontent.com/mattermost/mattermost/master/docs/main/product-overview/desktop-app-changelog.mdx")!,
                entryPattern:
                    #"(?:^|\n)(?:- )?\*\*v(?<version>[0-9]+\.[0-9]+\.[0-9]+)(?: release day: |, released? )(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\*\*"#
                    + #"(?<body>.*?)(?=\n(?:- )?\*\*v[0-9]|\n## |\z)"#,
                itemPatterns: [#"(?:^|\n)[ \t]*- (?<item>(?!(?:\*\*v|Original v[0-9.]+ release))[^\n]+)"#],
                stripTags: false,
                markdownSource: true,
                channel: .stable,
                excludedChannels: [.rc, .nightly],
                headingPattern: #"(?:^|\n)#{3,4} (?<heading>[^\n]+)"#)
        },
        githubRules: [
            // Direct downloads carry electron-builder's GitHub publish config,
            // not a constructible generic Electron manifest URL. The app's
            // UpdateNotifier reads releases.mattermost.com/desktop/latest.txt
            // (or rc.txt) and opens the installer in the browser on request;
            // it does not stage a background self-update.
            //
            // Stable tags are dotted versions with an optional v prefix.
            // ZIPs name their architecture arm64 or, in older releases, m1.
            // The selected current ARM ZIP is Mattermost.Desktop, notarized,
            // Team UQ8HT4Q2XM. Old same-id copies with no matching Team remain
            // subject to the unchanged installer signature gate.
            GitHubReleaseRule(
                bundleID: "Mattermost.Desktop", owner: "mattermost", repo: "desktop",
                versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
                installAssetPattern: #"^mattermost-desktop-[0-9]+(?:\.[0-9]+)+-mac-(?:arm64|m1)\.zip$"#,
                installerKind: .zip),

            // Published RC bundles retain -rc.N (older tags spell -rcN).
            // Generic channel detection leaves those stable, so exact installed
            // tag discovery proves their RC identity before selecting a rule.
            // RC backports can be published after a newer major's RC; compare
            // versions within the page instead of taking publication order.
            // Neither version nor asset pattern accepts stable releases.
            GitHubReleaseRule(
                bundleID: "Mattermost.Desktop", owner: "mattermost", repo: "desktop",
                usePrereleases: true, listPageSize: 100,
                versionPattern: #"^v([0-9]+(?:\.[0-9]+)+-rc\.?[0-9]+)$"#,
                candidateScope: .highestVersion,
                installedTagPrefix: "v",
                installAssetPattern: #"^mattermost-desktop-[0-9]+(?:\.[0-9]+)+-rc\.?[0-9]+-mac-(?:arm64|m1)\.zip$"#,
                installerKind: .zip,
                channel: .rc),

            // The original electron-mattermost bundles are unsigned and use a
            // different id. They can read the current stable version and notes,
            // but a same-Team BundleIDMigration cannot authorize their swap.
            GitHubReleaseRule(
                bundleID: "com.electron.electron-mattermost",
                owner: "mattermost", repo: "desktop",
                versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
                variant: "legacy-electron"),
            GitHubReleaseRule(
                bundleID: "com.electron.mattermost",
                owner: "mattermost", repo: "desktop",
                versionPattern: #"^v?([0-9]+(?:\.[0-9]+)+)$"#,
                variant: "legacy-mattermost"),
        ],
        githubChannelProofs: [
            ChannelProofKey("Mattermost.Desktop", .rc):
                .artifact(#"/mattermost-desktop-[0-9.]+-rc\.?[0-9]+-mac-(?:arm64|m1)\.zip$"#),
        ])
}
