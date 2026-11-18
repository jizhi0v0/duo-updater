import Foundation

enum com_anthropic_claudefordesktop {
    private static func rollout(channel: ReleaseChannel) -> VendorProbeRecipe {
        let isLatest = channel == .latest
        let endpoint = "https://api.anthropic.com/api/desktop/darwin/universal/squirrel/update"
            + "?device_id=__IDENTITY__&os_version=__HOST_OS_VERSION__"
            + (isLatest ? "&channelUuid=77a14fc4-808e-4345-ac3e-090be671bf94" : "")
        let archiveDirectory = isLatest ? "releases-latest" : "releases"
        let archivePath = #"https://downloads\.claude\.ai/"# + archiveDirectory + "/darwin/universal/"
        let zipName = #"Claude-[0-9a-f]+\.zip"#
        let zip = archivePath + #"[0-9.]+/"# + zipName
        let zipField = #""url"\s*:\s*""#
        let zipFieldPattern = zipField + zip + "\""
        let currentRelease = #""currentRelease"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#
        // Require an actual Latest archive whose first ZIP agrees with
        // currentRelease, in case the service answers with a Stable build.
        let latestVersion = #"(?s)\A(?=.*\#(currentRelease))(?:(?!\#(zipFieldPattern)).)*\#(zipField + archivePath)\1/\#(zipName)""#
        return VendorProbeRecipe(
            bundleID: ClaudeDesktopChannel.bundleID,
            url: URL(string: endpoint)!,
            mode: .responseBody,
            versionPattern: isLatest ? latestVersion : currentRelease,
            downloadURL: isLatest
                ? URL(string: "https://support.claude.com/en/articles/10065433-install-claude-desktop")
                : URL(string: "https://claude.ai/download"),
            publishedAtPattern: #""pub_date"\s*:\s*"([0-9T:.\-]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(zipField + "(\(zip))\""),
                kind: .zip,
                // Read the SHA-256 from the object that names the first ZIP.
                checksumPattern:
                    #"\A(?:(?!\#(zipFieldPattern))[\s\S])*?\{(?=[^{}]*\#(zipFieldPattern))[^{}]*?"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
            channel: channel,
            identities: [ProbeIdentity(
                applicationSupportPath: "Claude/ant-did",
                encoding: .base64,
                validationPattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#)],
            variant: isLatest ? nil : "rollout")
    }

    static let set = AppRecipeSet(
        family: "com-anthropic-claudefordesktop",
        probes: [
        // History: docs/app-audits/com-anthropic-claudefordesktop.md#历史与实测
        // Stable combines the public GA redirect with the Squirrel rollout for
        // this Mac. During a ramp either can lead. The GA URL's /latest segment
        // means the current public release. GET without following the redirect
        // reads the version and ZIP URL from Location without fetching the ZIP.
        VendorProbeRecipe(
            bundleID: ClaudeDesktopChannel.bundleID,
            url: URL(string: "https://api.anthropic.com/api/desktop/darwin/universal/zip/latest/redirect")!,
            mode: .redirectFilename,
            versionPattern: #"/darwin/universal/([0-9]+(?:\.[0-9]+){1,3})/"#,
            downloadURL: URL(string: "https://claude.ai/download"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://downloads\.claude\.ai/releases/darwin/universal/[0-9.]+/Claude-[0-9a-f]+\.zip)"#),
                kind: .zip),
            followRedirects: false,
            variant: "ga"),

        // Both Squirrel requests use Claude's real device ID for cohort targeting
        // and the host OS for release eligibility. Latest adds the channel UUID
        // from Claude's updater and accepts only the releases-latest archive path.
        rollout(channel: .stable),
        rollout(channel: .latest),
        ],
        changelogs: [
        // Claude Desktop — the official docs changelog at
        // claude.com/docs/cowork/changelog. We fetch the `.md` twin (Mintlify serves a
        // text/markdown form of every docs page): server-rendered, on a stable URL, and
        // free of the hashed-JS + zstd-cache fragility of the in-app "What's new" popup
        // (which reads an inline array baked into claude.ai's web bundle — variable
        // names rotate every deploy). Each release starts at a line that is only
        //   **v3.1623.0**
        // and runs to the next one (it used to be an
        // `<Update label="v…" description="<date>">` block; the decoder reads both).
        // version = the label minus its leading "v" (matches the
        // com.anthropic.claudefordesktop build the VendorProbe reads); date = the old
        // block's description, none in the bold shape (the `.md` no longer carries
        // dates). Inside, notes are grouped into `**General**`, `**Code**`,
        // `**Cowork**`, and `**3P**` sections of `* ` markdown bullets.
        //
        // Decoded, not regex-extracted: the regex recipe that used to live here
        // flattened General + Code + Cowork into one unheaded list, which is not what
        // the in-app popup shows — it shows the Code tab's General + Code notes grouped
        // as New / Improved / Fixed. `decodeClaudeDesktop` reproduces that, and says
        // where the reproduction is inferred. A parse miss falls back to embedding the
        // page.
        ChangelogRecipe(
            bundleID: ClaudeDesktopChannel.bundleID,
            source: URL(string: "https://claude.com/docs/cowork/changelog.md")!,
            maxEntries: 20,
            structuredFormat: .claudeDesktopChangelog),
        ],
        channelProofs: [
            ChannelProofKey(ClaudeDesktopChannel.bundleID, .latest):
                .artifact(#"^https://downloads\.claude\.ai/releases-latest/darwin/universal/"#),
        ])
}
