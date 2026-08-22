import Testing
@testable import DuoUpdaterCore

struct AppStoreQuitPolicyTests {

    /// Regression (2026-08-22, DingTalk 8.3.15 → 8.5.0): the install succeeded,
    /// `storedownloadd` terminated the running app to swap its bundle, and
    /// nothing reopened it. The row showed "Updated ✓" and the user's open app
    /// was simply gone. Arming used to require the user answering *our* quit
    /// prompt, so a `mas` install — which raises no prompt at all — never armed.
    @Test func aRunningAppStoreInstallArmsTheReopen() {
        #expect(AppStoreQuitPolicy.armsReopen(route: .appStore, wasRunningBeforeInstall: true))
    }

    /// An app that wasn't running has nothing to come back to. Reopening it
    /// would start an app the user never had open.
    @Test func aStoppedAppStoreInstallDoesNotArmTheReopen() {
        #expect(!AppStoreQuitPolicy.armsReopen(route: .appStore, wasRunningBeforeInstall: false))
    }

    /// Every other route quits and relaunches through `restart()`, which we own.
    /// Arming here too would race that and could open the app twice. Written as
    /// a sweep over `Route` so a route added later has to make this decision
    /// explicitly instead of inheriting whichever answer the default gives.
    @Test func routesWeRelaunchOurselvesNeverArmTheReopen() {
        for route in InstallCoordinator.Route.allCases where route != .appStore {
            #expect(
                !AppStoreQuitPolicy.armsReopen(route: route, wasRunningBeforeInstall: true),
                "\(route.rawValue) must not arm the App Store reopen")
        }
    }
}
