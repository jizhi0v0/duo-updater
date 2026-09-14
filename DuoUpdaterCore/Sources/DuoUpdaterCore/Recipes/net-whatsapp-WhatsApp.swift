import Foundation

enum net_whatsapp_WhatsApp {
    static let set = AppRecipeSet(
        family: "net-whatsapp-WhatsApp",
        probes: [
        // History: docs/app-audits/net-whatsapp-WhatsApp.md#历史与实测
        // WhatsApp — the downloads page's link 302s to a versioned dmg on fbcdn:
        // e.g. `…/WhatsApp-2.26.31.27.dmg`. Read the Location header rather than
        // following it: the target IS the full installer, a few hundred MB, so a
        // HEAD-follow would be answered by the CDN with the real payload's headers
        // and any GET would fetch it outright.
        //
        // VERSION SCHEME TRAP: the filename carries a leading `2.` the app does
        // not — e.g. the bundle reports `26.22.20`, the file is
        // `WhatsApp-2.26.31.27.dmg`.
        // Capturing the whole thing would compare `2.26.31.27` against `26.22.20`
        // and conclude the installed copy is NEWER, hiding every update forever.
        // The pattern deliberately anchors on `WhatsApp-2.` and takes only the three
        // segments after it.
        //
        // One-click: the image holds `WhatsApp.app` whose bundle id and Team
        // (57T9237FN3) match the installed copy, its `CFBundleShortVersionString`
        // equals what the probe reports, and `spctl` accepts it as "Notarized
        // Developer ID" (mounted and checked 2026-08-09; History has the version).
        // WhatsApp also updates itself, so this row usually just confirms what
        // already happened — but when its own updater is behind, the swap is ours
        // to make.
        VendorProbeRecipe(
            bundleID: "net.whatsapp.WhatsApp",
            url: URL(string: "https://web.whatsapp.com/desktop/mac_native/release/?configuration=Release&src=whatsapp_downloads_desktop_page")!,
            mode: .redirectFilename,
            versionPattern: #"WhatsApp-[0-9]+\.([0-9]+(?:\.[0-9]+){1,2})\.dmg"#,
            changelogURL: URL(string: "https://web.whatsapp.com/desktop/mac_native/release-notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://web.whatsapp.com/desktop/mac_native/release/?configuration=Release&src=whatsapp_downloads_desktop_page")!),
                kind: .dmg),
            followRedirects: false),
        ],
        appStoreCases: [
        // WhatsApp — `kind == "software"` (an iOS listing), but its Mac build
        // publishes on its own release line: the `?platform=mac` product
        // page's `mostRecentVersion` shelf carries a DIFFERENT version than
        // the plain lookup's `version` field. Apple's own storefront cache is
        // internally inconsistent — when checked (2026-09-04; History has the
        // values) a single and a batched lookup in the same minute disagreed by a
        // patch release — which is exactly why this sweep must never assert a
        // version value, only that the shelf is THERE and parseable.
        // Exercises `iosOnMacVersion`.
        MacAppStoreProbeCase(
            bundleID: "net.whatsapp.WhatsApp", trackId: 310633997,
            expectedKind: "software", route: .iosOnMac),
        ],
        changelogPages: [
        // WhatsApp — iOS-on-Mac (kind=software); MAS source scrapes the Mac page
        // for version comparison, but `remote` may be nil at render time if the
        // check hasn't finished. This catalog entry ensures the Mac App Store page
        // always shows as changelog fallback regardless of check timing.
        // `?platform=mac` redirects correctly regardless of storefront region.
        // Key MUST be lowercase — `url(forBundleID:)` lowercases its argument
        // before the lookup, so a mixed-case key here is simply unreachable — this
        // entry once was one (History has it); `keysAreLowercased` guards the
        // whole table.
        "net.whatsapp.whatsapp": URL(string: "https://apps.apple.com/app/id310633997?platform=mac")!,
        ])
}
