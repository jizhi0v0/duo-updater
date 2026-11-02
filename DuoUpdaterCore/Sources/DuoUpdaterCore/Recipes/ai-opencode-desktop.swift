import Foundation

enum ai_opencode_desktop {
    static let set = AppRecipeSet(
        family: "ai-opencode-desktop",
        probes: [
        // OpenCode Desktop — 2.0 moved the desktop line off GitHub Releases onto
        // the vendor's own update channel. A 2.x bundle's `app-update.yml` names it
        // (`provider: generic`, `https://opencode.ai/update/api/latest/desktop/opencode/`),
        // and its `latest-mac.yml` is the manifest `ElectronManifestSource` reads; a
        // 1.x bundle still declares `provider: github`, so a 1.x install can only
        // ever resolve 1.19.5 there — this probe is what shows it 2.x at all. The
        // GitHub rule that used to carry this family is gone for that reason:
        // GitHub answers before a probe, so with it in place the probe never ran.
        //
        // The manifest is electron-updater's: one entry per artifact, this app's
        // own `version:`, and the arm64 dmg's sha512 in the same entry (so the
        // download is checked against the vendor's digest before the signature
        // gate). The dmg carries the same bundle id and Team as a 1.x install and
        // is notarized, so it replaces that install in place — that replacement is
        // the 1.x → 2.x migration, the desktop half of what
        // `opencode upgrade --major` does for the CLI. The bytes are recorded in
        // History.
        //
        // arm64 only: the manifest also lists x64 artifacts, but DuoUpdater is an
        // arm64 app (`App/project.yml`), so no host it runs on can use them.
        // History: docs/app-audits/ai-opencode-desktop.md#历史与实测
        VendorProbeRecipe(
            bundleID: "ai.opencode.desktop",
            url: URL(string: "https://opencode.ai/update/api/latest/desktop/opencode/latest-mac.yml")!,
            mode: .responseBody,
            // The document's own top-level field, not the artifact paths: a
            // release whose dmg is still uploading states its version here first.
            versionPattern: #"(?m)^version:\s*([0-9]+(?:\.[0-9]+)+)\s*$"#,
            downloadURL: URL(string: "https://opencode.ai/download")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(?m)^\s*- url: (https://opencode\.ai/files/bin/[0-9]+(?:\.[0-9]+)+\/"#
                        + #"opencode-desktop-mac-arm64\.dmg)$"#),
                kind: .dmg,
                // `sha512:` on the dmg's own entry: electron-updater staples it
                // beside the URL, and it is what the app's own updater checks.
                checksumPattern:
                    #"(?m)^\s*- url: https://opencode\.ai/files/bin/[0-9]+(?:\.[0-9]+)+\/"#
                    + #"opencode-desktop-mac-arm64\.dmg\n\s*sha512: ([A-Za-z0-9+/=]+)$"#,
                checksumFormat: .sha512Base64)),
        ],
        changelogs: [
        // OpenCode (desktop) — the anomalyco/opencode GitHub releases (the repo
        // moved from sst/opencode via GitHub's org-rename redirect; we pin the
        // canonical anomalyco path). The 1.x desktop app and the CLI shared one
        // version line; 2.x still publishes its notes as these releases, which is
        // why the *notes* stay here while the version no longer does. The notes
        // are read exactly as the OpenCode CLI's are (`.opencodeReleases` →
        // `OpencodeRelease.parseNotes`): each body up to its
        // `**Thank you to N community contributors:**` block.
        //
        // This used to scrape github.com/anomalyco/opencode/releases with a
        // `<li>` item pattern, which also took that block as items.
        // History: docs/app-audits/ai-opencode-desktop.md#历史与实测
        ChangelogRecipe(
            bundleID: "ai.opencode.desktop",
            source: OpencodeRelease.listURL,
            mode: .json,
            structuredFormat: .opencodeReleases),
        ])
}
