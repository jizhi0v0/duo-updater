import Foundation

enum ai_deepseek_dsh_desktop {
    static let set = AppRecipeSet(
        family: "ai-deepseek-dsh-desktop",
        githubRules: [
        // DSH Desktop — the DeepSeek Harness desktop client (anywhere-labs).
        // No SUFeedURL; v-tags, one universal dmg per release beside a Windows
        // setup.exe. The bundle is ai.deepseek.dsh.desktop, short == build ==
        // tag, Team UM3Z9G5DNH, notarized. Up to v2.0.15 the dmg was
        // `DSH.Desktop-` (GitHub's dot for the space in "DSH Desktop"); from
        // v2.0.16 it is `DSH-Desktop-`. Each tag also has a `-beta.N`
        // prerelease (`DSH-Desktop-Beta-…`) and a `-next` release
        // (`DSH-NEXT-…`) beside it; the tag anchor and the digit right after
        // `Desktop-` keep both out.
        GitHubReleaseRule(
            bundleID: "ai.deepseek.dsh.desktop",
            owner: "anywhere-labs", repo: "dsh-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
            installAssetPattern: #"^DSH[.-]Desktop-[0-9.]+-universal\.dmg$"#,
            installerKind: .dmg),

        // DSH NEXT — the same client's pre-release train, installed as its own
        // app under its own bundle id (`…desktop.next`) beside DSH Desktop, not
        // an edition of that bundle. It publishes in parallel with the stable
        // line, so a NEXT install needs its own rule: the stable rule's tag
        // anchor rejects every `-next` tag.
        //
        // Its releases sit beside the stable ones in the same repo and are the
        // same shape: `vX.Y.Z-next` tags (not GitHub prereleases) and one
        // `DSH-NEXT-<version>-next-universal.dmg`. The `-beta.N` release of the
        // same version carries `DSH-Desktop-Beta-…` and belongs to the stable
        // bundle, so it is not a beta sibling of this one. The version group
        // keeps the `-next` suffix because that is exactly what the bundle's
        // CFBundleShortVersionString says; capturing only `X.Y.Z` would compare
        // correctly but show a string the bundle never carries. The asset anchor
        // takes only the `-next` dmg, so the stable and beta assets of the same
        // repository can never be installed here.
        //
        // `variant` keeps this rule's recipe id, health row and verify baseline
        // apart from the stable rule's: both read the same repo on the same
        // channel, and without it they would share all three.
        GitHubReleaseRule(
            bundleID: "ai.deepseek.dsh.desktop.next",
            owner: "anywhere-labs", repo: "dsh-desktop",
            versionPattern: #"^v([0-9]+(?:\.[0-9]+)+-next)$"#,
            installAssetPattern: #"^DSH-NEXT-[0-9.]+-next-universal\.dmg$"#,
            installerKind: .dmg,
            variant: "next"),
        ])
}
