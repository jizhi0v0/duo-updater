import Foundation

enum com_qoder_app {
    static let set = AppRecipeSet(
        family: "com-qoder-app",
        probes: [
        // Shared rationale for Qoder (2026-09-06): Recipes/com-qoder-ide.swift.

        // History: docs/app-audits/com-qoder-app.md#历史与实测
        // Qoder (the app) — the vendor publishes a small `manifest.json` beside
        // the artifacts for its own installer to read: a top-level `version` plus
        // one entry per platform with a sha256. Unconditional, tiny, and JSON, so
        // it is preferred over every HTML surface this product has.
        //
        // `"version"` cannot be satisfied by `"schemaVersion"`, which sits above it
        // in the document and would otherwise win the first match. THREE things
        // keep it out and any ONE of them suffices — measured against the real
        // body and against a variant that quotes the schema version, rather than
        // ranked by intuition (an earlier draft called case-sensitivity the
        // load-bearing one; dropping it alone changes nothing):
        //
        //   • the key is matched with its own opening quote, and the character
        //     before `Version` in `"schemaVersion"` is `a`;
        //   • `extractVersion` compiles with NO regex options, so the match is
        //     case-sensitive and `schemaVersion` spells it with a capital V;
        //   • `schemaVersion`'s value is an unquoted integer.
        //
        // `appReadsTheManifestVersionAndNotTheSchemaVersion` removes the third and
        // shows the other two still hold; only a pattern that gives up the first
        // TWO reads "1.0".
        //
        // ⚠️ Same coupling caveat as the IDE (`Recipes/com-qoder-ide.swift`): the install pattern's
        // `[0-9.]+` path segment is not required to equal the `version` this
        // reports, and `versionTemplate` is not used for the same reason.
        //
        // The download page hands a human `Qoder-Installer-mac-arm64.zip`: a stub
        // (`com.qoder.installer`, its own bundle id) whose
        // `Contents/Resources/payload/Qoder-<version>-mac-arm64.zip` holds the
        // real app — the DoubaoIme shape `nestedArchivePath` exists for, and one
        // this recipe deliberately does NOT need. The same release ships
        // unwrapped beside it as `Qoder-mac-arm64.zip`, which is what the manifest
        // names and what this installs; the payload path could not be spelled as
        // a fixed `nestedArchivePath` anyway, since it carries the version.
        //
        // On the artifact the manifest resolved to, short == build == the
        // manifest's `version` (verified 2026-09-06; History has the check).
        //
        // HOST SPLIT, deliberately followed rather than rewritten: the manifest is
        // served from `download.qoder.com` and its artifact URLs point at
        // `download.qoder.com.cn`. Both are Aliyun OSS and both answer the same
        // object (HEAD, identical byte count, 2026-09-06), and the vendor's own
        // installer downloads the `.com.cn` one — so the pattern accepts either
        // rather than pinning the host we happened to fetch from.
        VendorProbeRecipe(
            bundleID: "com.qoder.app",
            url: URL(string: "https://download.qoder.com"
                + "/qoder-app/releases/latest/manifest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://qoder.com/download"),
            changelogURL: URL(string: "https://docs.qoder.com/release-notes/qoder"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://download\.qoder\.com(?:\.cn)?"#
                    + #"/qoder-app/releases/[0-9.]+/Qoder-mac-arm64\.zip)""#),
                kind: .zip)),
        ],
        changelogs: [
        // The app's page spells its version "Qoder 0.1.8" where the IDE's is a
        // bare "1.28.0" — the shared pattern makes that prefix optional rather
        // than forking the recipe, since both pages come off one docs build and a
        // fix to one belongs to both.
        ChangelogRecipe(
            bundleID: "com.qoder.app",
            source: URL(string: "https://docs.qoder.com/release-notes/qoder")!,
            entryPattern: ChangelogRecipeRegistry.qoderEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
