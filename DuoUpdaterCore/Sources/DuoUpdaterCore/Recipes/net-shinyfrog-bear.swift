import Foundation

enum net_shinyfrog_bear {
    static let set = AppRecipeSet(
        family: "net-shinyfrog-bear",
        appStoreCases: [
        // History: docs/app-audits/net-shinyfrog-bear.md#历史与实测
        // Bear — Mac App Store–exclusive markdown notes app, continuously
        // maintained since 2016, no reason to expect delisting. Native Mac
        // listing (`mac-software`): exercises `nativeMacVersion` and the
        // `trackViewUrl` zero-redirect path A2 added.
        MacAppStoreProbeCase(
            bundleID: "net.shinyfrog.bear", trackId: 1091189122,
            expectedKind: "mac-software", route: .nativeMac),
        ])
}
