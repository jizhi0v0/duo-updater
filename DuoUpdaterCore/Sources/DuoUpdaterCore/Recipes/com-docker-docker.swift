import Foundation

enum com_docker_docker {
    static let set = AppRecipeSet(
        family: "com-docker-docker",
        probes: [
        // History: docs/app-audits/com-docker-docker.md#历史与实测
        // Docker's backend uses the stable JSON appcast. AppVersion and
        // BuildNumber are the app bundle's marketing version and build.
        // Only the selected release's full DMG is eligible for the app swap.
        // It contains the notarized Docker.app (Team 9BNSXJN65R).
        VendorProbeRecipe(
            bundleID: "com.docker.docker",
            url: URL(string: "\(downloadBase)/appcast.json")!,
            mode: .dockerAppcast,
            versionPattern: #""AppVersion"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            changelogURL: URL(string: "https://docs.docker.com/desktop/release-notes/"),
            publishedAtPattern: #""Date"\s*:\s*"([0-9T:Z.+-]+)""#,
            minimumSystemVersionPattern: #""MinOSVersion"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""URL"\s*:\s*"([^"]+)""#),
                kind: .dmg,
                checksumPattern: #""Checksum"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex)),
        ],
        changelogs: [
        // Docker Desktop — the release-notes page in its Markdown source form.
        // `docs.docker.com/desktop/release-notes.md` serves `text/markdown`
        // directly (the `.md` twin of the HTML page).
        //
        // The `- [Windows](…)` / `- [Mac …]` / `- [Linux …]` installer links each
        // release opens with are excluded by the item pattern's negative lookahead:
        // they are the same seven download URLs every time and say nothing about
        // what changed. Everything after them — the `### Updates` component list
        // and the `### Bug fixes and enhancements` sections — is kept.
        //
        // `markdownSource` because the notes link out mid-sentence
        // (e.g. `[Docker Compose v5.4.0](…)`); without it a plain-text render prints the
        // brackets and the URL.
        ChangelogRecipe(
            bundleID: "com.docker.docker",
            source: URL(string: "https://docs.docker.com/desktop/release-notes.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+)\n\n"#
                + #"<em[^>]*>(?<date>[0-9-]+)</em>"#
                + #"(?<body>[\s\S]*?)(?=\n## |\z)"#,
            itemPatterns: [#"(?:^|\n)- (?!\[(?:Windows|Mac|Linux))(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 20,
            minItemLength: 6),
        ])

    private static let downloadBase = "https://desktop.docker.com/mac/main/arm64"
    private static let dottedVersion = #"\A[0-9]+(?:\.[0-9]+)+\z"#

    private struct Release {
        let marketing: String
        let build: String
        let minimumOS: String
        let fields: [String: Any]

        init?(_ fields: [String: Any]) {
            guard let marketing = fields["AppVersion"] as? String,
                  marketing.range(of: dottedVersion, options: .regularExpression) != nil,
                  let build = fields["BuildNumber"] as? String, !build.isEmpty,
                  build.utf8.allSatisfy({ (48...57).contains($0) }),
                  let visibility = (fields["Visibility"] as? String).flatMap(Int.init),
                  (1...100).contains(visibility),
                  let minimumOS = fields["MinOSVersion"] as? String,
                  minimumOS.range(of: dottedVersion, options: .regularExpression) != nil
            else { return nil }
            self.marketing = marketing
            self.build = build
            self.minimumOS = minimumOS
            self.fields = fields
        }

        var version: VersionSide {
            VersionSide(marketing: marketing, build: build)
        }
    }

    /// Project one release into the normal probe path. PreviousBuild can name
    /// a different starting build even when the native updater offers this DMG.
    /// A positive Visibility marks a published rollout; this isn't a prediction
    /// of which cohort Docker assigns this copy to.
    static func releaseBody(
        from body: String, hostOSVersion: String
    ) -> (text: String, version: VersionSide)? {
        guard let appcast = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let items = appcast["Items"] as? [[String: Any]]
        else { return nil }
        let releases = items.compactMap(Release.init).sorted {
            VersionComparator.isNewer($0.version, than: $1.version)
        }
        // If none can run, let the normal probe issue its OS-window refusal
        // for the newest release instead of classifying this as a parse failure.
        guard let release = releases.first(where: {
            SignatureVerifier.canRun(minimumSystemVersion: $0.minimumOS, on: hostOSVersion)
        }) ?? releases.first else { return nil }

        var selected = ["AppVersion": release.marketing, "MinOSVersion": release.minimumOS]
        selected["Date"] = release.fields["Date"] as? String

        let expectedURL = "\(downloadBase)/\(release.build)/Docker.dmg"
        let images = (release.fields["Artifacts"] as? [[String: Any]] ?? []).filter {
            $0["Type"] as? String == "dmg" && $0["URL"] as? String == expectedURL
        }
        if images.count == 1,
           let checksum = (images.first?["Checksum"] as? String)?.lowercased(),
           checksum.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil {
            selected["URL"] = expectedURL
            selected["Checksum"] = checksum
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: selected, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return (String(decoding: data, as: UTF8.self), release.version)
    }
}
