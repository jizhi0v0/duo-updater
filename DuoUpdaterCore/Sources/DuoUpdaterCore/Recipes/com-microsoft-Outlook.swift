import Foundation

enum com_microsoft_Outlook {
    static let set = AppRecipeSet(
        family: "com-microsoft-Outlook",
        probes: [
        // History: docs/app-audits/com-microsoft-Outlook.md#历史与实测
        // Microsoft Outlook — Office suite, unified version. Uses the Office
        // AutoUpdate XML manifest (same CDN product tree as the fwlinks), an
        // ARRAY of update dicts. MAU-managed.
        //
        // The manifest is a plist, so each dict's keys are ALPHABETICAL and the
        // newest release comes first, which is why every first-match pattern here
        // reads out of the same (first) dict.
        //
        // The manifest's payload keys, and what each points at:
        //
        //   Location / Payload      → `Outlook_<baseline>_to_<new>_Delta.pkg` on
        //                             the delta entries — a PARTIAL payload
        //   BinaryUpdaterLocation   → `…_BinaryDelta.pkg`, a binary patch
        //   FullUpdaterLocation     → `Microsoft_Outlook_<build>_Updater.pkg`, the
        //                             full standalone package (choice customLocation
        //                             /Applications)
        //
        // Only the full updater is installable. Neither delta carries a baseline
        // guard — their `InstallationCheck()` only tests the min OS version — so
        // running one against the wrong installed build would silently lay down a
        // partial Outlook.
        //
        // The URL is READ from `FullUpdaterLocation`, not assembled from the
        // version — same call as AweSun's 0.3.13 fix (building the filename from
        // the version broke the moment Oray renamed the file). It also means the
        // CDN move Microsoft is midway through follows automatically: payload URLs
        // now point at `res.public.onecdn.static.microsoft` while only the manifest
        // itself still lives on `officecdn.microsoft.com`. Both patterns take the
        // first match, so both read out of the same first dict — the pkg is the
        // build we report (`duo verify` re-checks that against the live endpoint,
        // and `microsoftOutlookInstallURLMatchesProbedBuild` guards it in CI).
        //
        // The `Microsoft_Outlook_<build>_Updater.pkg` shape is part of the pattern
        // on purpose: key order inside a dict is alphabetical, so BinaryUpdater
        // (B) and the delta `Location` (L) bracket the one key we want, and the
        // filename guard is what makes a delta unmatchable no matter how the
        // manifest is reordered.
        //
        // Version scheme: `Update Version` is the BUILD (e.g. 16.109.26053122), not the
        // marketing string — the pkg's own Distribution declares both (e.g.
        // CFBundleShortVersionString 16.109.3 / CFBundleVersion 16.109.26053122) —
        // hence `versionIsBuild`. Signed `Developer ID Installer: Microsoft
        // Corporation (UBF8T346G9)`, the same Team as the installed app (read from
        // the pkg's xar signature).
        VendorProbeRecipe(
            bundleID: "com.microsoft.Outlook",
            url: URL(string: "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409OPIM2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/outlook/outlook-for-business")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>FullUpdaterLocation</key>\s*<string>(https://[^<\s]+/Microsoft_Outlook_[0-9.]+_Updater\.pkg)</string>"#),
                kind: .pkg)),
        ])
}
