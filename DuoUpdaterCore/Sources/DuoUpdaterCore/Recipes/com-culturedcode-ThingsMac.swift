import Foundation

enum com_culturedcode_ThingsMac {
    static let set = AppRecipeSet(
        family: "com-culturedcode-ThingsMac",
        appStoreCases: [
        // Things 3 — Mac App Store–exclusive task manager, shipping since
        // 2017. A second `mac-software` case so one app's page having a bad
        // minute doesn't take the whole route dark for a sweep. Confirmed
        // live 2026-09-04, same shape as Bear.
        MacAppStoreProbeCase(
            bundleID: "com.culturedcode.ThingsMac", trackId: 904280696,
            expectedKind: "mac-software", route: .nativeMac),
        ])
}
