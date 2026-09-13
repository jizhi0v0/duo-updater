import Foundation

enum net_shinyfrog_bear {
    static let set = AppRecipeSet(
        family: "net-shinyfrog-bear",
        appStoreCases: [
        // Bear — Mac App Store–exclusive markdown notes app, continuously
        // maintained since 2016, no reason to expect delisting. Native Mac
        // listing (`mac-software`): exercises `nativeMacVersion` and the
        // `trackViewUrl` zero-redirect path A2 added. Confirmed live
        // 2026-09-04: lookup kind mac-software, trackViewUrl → 0 redirects,
        // `?platform=mac` page carries a parseable `mostRecentVersion` shelf.
        MacAppStoreProbeCase(
            bundleID: "net.shinyfrog.bear", trackId: 1091189122,
            expectedKind: "mac-software", route: .nativeMac),
        ])
}
