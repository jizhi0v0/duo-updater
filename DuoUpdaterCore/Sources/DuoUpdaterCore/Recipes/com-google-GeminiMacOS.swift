import Foundation

enum com_google_GeminiMacOS {
    static let set = AppRecipeSet(
        family: "com-google-GeminiMacOS",
        probes: [
        // History: docs/app-audits/com-google-GeminiMacOS.md#历史与实测
        // Gemini — Google's Omaha update service, which answers only a POST. The
        // published download URL carries no version (`.../release2/Gemini.dmg`,
        // unchanged across releases so far) and the download page answers a plain
        // fetch with Google's bot challenge (302 → /sorry),
        // so nothing reachable states a version. This service does; it was found
        // by reading the app's own update request. Asking as version `0.0.0.0`
        // makes it answer with the manifest for the newest build, not "noupdate".
        //
        // The manifest version is the same scheme as `CFBundleShortVersionString`,
        // so no build-vs-marketing trap here. The reply is prefixed with Google's
        // `)]}'` anti-hijacking line, which the regex simply skips.
        //
        // The manifest publishes a sha256, but `checksumPattern` verifies a
        // base64 SHA-512, so it goes unused; the signature gate still applies.
        // No `changelogURL`: `gemini.google/release-notes` is the Gemini *Apps*
        // product feed — model and feature announcements keyed by DATE
        // (e.g. 2023.04.10), with no desktop build number anywhere. The app's own
        // version is four-part (e.g. 1.96.4.775), so nothing on that page
        // can ever line up with the version on this row. Exactly the mismatch the
        // Notion changelog was moved off of; wiring it here would reintroduce it.
        VendorProbeRecipe(
            bundleID: "com.google.GeminiMacOS",
            url: URL(string: "https://update.googleapis.com/service/update2/json")!,
            mode: .responseBody,
            versionPattern: #""manifest":\{"version":"([0-9][0-9.]*)""#,
            downloadURL: URL(string: "https://gemini.google.com/download"),
            install: VendorInstallSpec(
                // The manifest splits the download in two: a list of CDN bases
                // and the package name. Join Google's own host with the name.
                urlSource: .bodyTemplate("{0}{1}", fields: [
                    #""codebase":"(https://dl\.google\.com/[^"]+)""#,
                    #""name":"(Gemini-[0-9.]+\.dmg)""#,
                ]),
                kind: .dmg),
            requestBody: .init(json: """
                {"request":{"protocol":"3.0","os":{"platform":"mac","arch":"arm64"},\
                "app":[{"appid":"com.google.GeminiMacOS","tag":"m1-prod",\
                "version":"0.0.0.0","updatecheck":{}}]}}
                """)),
        ])
}
