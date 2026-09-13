import Foundation

enum org_pgadmin_pgadmin4 {
    static let set = AppRecipeSet(
        family: "org-pgadmin-pgadmin4",
        probes: [
        // pgAdmin4 — `ftp.postgresql.org/pub/pgadmin/pgadmin4/` lists both version
        // folders (`v9.17/`) and non-version siblings (`apt/`, `autoupdate/`,
        // `snapshots/`, `yum/`, `README`) — none of the siblings carry a digit
        // immediately after the `v`, so anchoring on `href="v([0-9.]+)/"` takes only
        // the releases; `snapshots/` in particular is a trap left alone deliberately
        // (dev builds, not what a stable-channel install should ever be pointed at).
        // The mac artifact is one level deeper (`v9.17/macos/pgadmin4-9.17-arm64.dmg`),
        // which is what makes this the same shape as LibreOffice (`Recipes/org-libreoffice-script.swift`).
        //
        // Verified 2026-08-16 by mounting `pgadmin4-9.17-arm64.dmg`: `pgAdmin 4.app`,
        // CFBundleShortVersionString exactly `"9.17"` (matches the probe 1:1, no
        // build/marketing mismatch here), notarized Developer ID, Team TCHGL2R7C5
        // ("David Page"), spctl accepted.
        VendorProbeRecipe(
            bundleID: "org.pgadmin.pgadmin4",
            url: URL(string: "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/")!,
            mode: .responseBody,
            versionPattern: #"href="v([0-9]+\.[0-9]+)/""#,
            downloadURL: URL(string: "https://www.pgadmin.org/download/pgadmin-4-macos/"),
            changelogURL: URL(string: "https://www.pgadmin.org/docs/pgadmin4/latest/release_notes.html"),
            selectHighest: true,
            // ONE-CLICK via `.versionTemplate` (same reasoning as Opera and
            // LibreOffice: the resolved version, never a first-match regex, on an
            // index whose ordering is alphabetical — `v10.0` will one day sort
            // before `v9.17`, and that day this template still builds the right
            // URL because it is handed the number that won the comparison).
            //
            // Verified 2026-08-16 by mounting `pgadmin4-9.17-arm64.dmg`
            // (233,075,920 B): `pgAdmin 4.app`, org.pgadmin.pgadmin4,
            // CFBundleShortVersionString `9.17` — exactly what the index publishes,
            // so no scheme mismatch — Team TCHGL2R7C5 (David Page), notarized
            // Developer ID, spctl accepted. (`CFBundleVersion` is an unrelated
            // `4280.88`; the recipe compares marketing, which is the field that
            // agrees.) arm64-only artifact, like the other arm64-pinned recipes
            // here; an Intel Mac is refused by the runnable-arch gate rather than
            // given a build it can't run.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/"
                    + "v{version}/macos/pgadmin4-{version}-arm64.dmg"),
                kind: .dmg)),
        ])
}
