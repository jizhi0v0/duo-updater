import Testing
@testable import DuoUpdaterCore

/// The incremental (AX) App Store route is deliberately unlisted: it drives App Store's
/// own UI and is still under evaluation, so the only way in is
/// `defaults write com.duoupdater.app AppStoreUpdateStrategy incremental`.
/// These pin the two halves of "hidden, but not a trap".
struct AppStoreStrategyVisibilityTests {

    /// Nobody is offered the unlisted route by the Settings picker.
    @Test func settingsOffersOnlyTheFullDownloadRoute() {
        #expect(AppStoreUpdateStrategy.visibleCases(current: .full) == [.full])
    }

    /// But whoever set it by hand must see it. A SwiftUI picker whose selection is not
    /// among its own tags renders empty and rewrites the setting as soon as it is
    /// touched — so hiding the *active* value would both misreport the state and turn
    /// the route off behind the user's back.
    @Test func theActiveRouteIsAlwaysListedEvenWhenUnlisted() {
        let cases = AppStoreUpdateStrategy.visibleCases(current: .incremental)
        #expect(cases.contains(.incremental))
        #expect(cases.contains(.full), "and it must stay possible to switch back")
    }

    /// No duplicates, whatever the current value — a repeated tag breaks the picker.
    @Test func everyStrategyListsEachCaseOnce() {
        for current in AppStoreUpdateStrategy.allCases {
            let cases = AppStoreUpdateStrategy.visibleCases(current: current)
            #expect(Set(cases).count == cases.count, "\(current.rawValue) listed a duplicate")
            #expect(cases.contains(current), "\(current.rawValue) must list itself")
        }
    }

    /// The raw value is the documented gesture — renaming it would silently break
    /// every machine already running the unlisted route.
    @Test func theDefaultsValueSpellingIsPartOfTheContract() {
        #expect(AppStoreUpdateStrategy(rawValue: "incremental") == .incremental)
        #expect(AppStoreUpdateStrategy(rawValue: "full") == .full)
    }
}
