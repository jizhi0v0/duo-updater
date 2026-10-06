import Foundation

enum com_google_GeminiMacOS {
    static let set = AppRecipeSet(
        family: "com-google-GeminiMacOS",
        probes: [
        // History: docs/app-audits/com-google-GeminiMacOS.md#历史与实测
        // Gemini — Google's Omaha update service, which answers only a POST. The
        // published download URL carries no version (`.../release2/Gemini.dmg`,
        // unchanged across releases so far) and no reachable page states a version
        // (History has what the download page answered when checked). This service
        // does; it was found
        // by reading the app's own update request. Asking as version `0.0.0.0`
        // makes it answer with the manifest for the newest build, not "noupdate".
        //
        // The manifest version is the same scheme as `CFBundleShortVersionString`,
        // so no build-vs-marketing trap here. The reply is prefixed with Google's
        // `)]}'` anti-hijacking line, which the regex simply skips.
        //
        // The download is checked against the package's `hash_sha256` (hex), on
        // top of the Team-ID gate. The checksum pattern takes the package object
        // holding the same `Gemini-<version>.dmg` `name` the URL reads, whatever
        // the key order (Google lists `hash_sha256` before `name`); if that object
        // has none, it matches nothing rather than another entry's digest. The
        // `hash` beside it is base64 SHA-1 and is not used.
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
            downloadURL: URL(string: "https://gemini.google/desktop/"),
            install: VendorInstallSpec(
                // The manifest splits the download in two: a list of CDN bases
                // and the package name. Join Google's own host with the name.
                urlSource: .bodyTemplate("{0}{1}", fields: [
                    #""codebase":"(https://dl\.google\.com/[^"]+)""#,
                    #""name":"(Gemini-[0-9.]+\.dmg)""#,
                ]),
                kind: .dmg,
                checksumPattern:
                    #"\A(?:(?!"name"\s*:\s*"Gemini-[0-9.]+\.dmg")[\s\S])*?\{(?=[^{}]*"name"\s*:\s*"Gemini-[0-9.]+\.dmg")[^{}]*?"hash_sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
            requestBody: .init(json: """
                {"request":{"protocol":"3.0","os":{"platform":"mac","arch":"arm64"},\
                "app":[{"appid":"com.google.GeminiMacOS","tag":"m1-prod",\
                "version":"0.0.0.0","updatecheck":{}}]}}
                """)),
        ])
}
