import Foundation
import Testing

@testable import DuoUpdaterCore

/// The window-server list as it looked during the reproduction on 2026-09-01, in
/// front-to-back order: the popover panel the click came from (layer 101), the row
/// menu still tearing down (layer 102), some other app's windows, and the workbench
/// eight ordinary windows deep. Numbers are stand-ins; the layers and the order are
/// what was observed.
private let workbench = 4242

private func reproduction(workbenchOnScreen: Bool, workbenchDepth: Int) -> [WindowInfo] {
    var windows = [
        WindowInfo(number: 1, layer: 102, isOnScreen: true),   // the row menu
        WindowInfo(number: 2, layer: 101, isOnScreen: true),   // the popover panel
    ]
    for i in 0..<workbenchDepth {
        windows.append(WindowInfo(number: 100 + i, layer: 0, isOnScreen: true))
    }
    windows.append(WindowInfo(number: workbench, layer: 0, isOnScreen: workbenchOnScreen))
    return windows
}

@Test func aWindowBehindOtherAppsIsNotFrontmost() {
    // The measured failure: on screen, and eight windows deep.
    #expect(!WindowOrder.isFrontmost(workbench, in: reproduction(workbenchOnScreen: true, workbenchDepth: 8)))
}

@Test func aWindowAtTheFrontIsFrontmost() {
    #expect(WindowOrder.isFrontmost(workbench, in: reproduction(workbenchOnScreen: true, workbenchDepth: 0)))
}

@Test func thePopoverAndItsMenuAreNotCompetitors() {
    // The click arrives through a layer-101 popover with a layer-102 menu on top of
    // it, and both are above every ordinary window while they are up. Counting them
    // would make this answer "not in front" for as long as the menu is open — so the
    // caller would go on re-ordering a window that is already where it belongs, and
    // the check would never be able to say the surfacing worked.
    let windows = [
        WindowInfo(number: 1, layer: 102, isOnScreen: true),
        WindowInfo(number: 2, layer: 101, isOnScreen: true),
        WindowInfo(number: workbench, layer: 0, isOnScreen: true),
    ]
    #expect(WindowOrder.isFrontmost(workbench, in: windows))
}

@Test func aWindowThatIsNotOnScreenIsNotFrontmost() {
    // ⌘W leaves the `NSWindow` alive and off screen — measured, and the reason the
    // reopen is fast where the first open of a session is not. Not visible is not in
    // front, and it is the state worth retrying from.
    #expect(!WindowOrder.isFrontmost(workbench, in: reproduction(workbenchOnScreen: false, workbenchDepth: 0)))
    #expect(!WindowOrder.isFrontmost(workbench, in: []))
}

@Test func anOffScreenWindowInFrontOfItDoesNotCount() {
    // A closed-but-alive window of any app can sit ahead of ours in the list while
    // being invisible. Only what is actually on screen can be in front of us.
    let windows = [
        WindowInfo(number: 7, layer: 0, isOnScreen: false),
        WindowInfo(number: workbench, layer: 0, isOnScreen: true),
    ]
    #expect(WindowOrder.isFrontmost(workbench, in: windows))
}
