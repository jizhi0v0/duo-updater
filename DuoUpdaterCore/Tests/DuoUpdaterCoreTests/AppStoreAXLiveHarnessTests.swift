#if os(macOS)
import Testing
import Foundation
@testable import DuoUpdaterCore

/// Drives the AX offer-button lookup (#471) against a REAL App Store product page —
/// but only reads it, never presses anything. Gated behind an env var and off by
/// default, same shape as `DUO_DOWNLOAD_GATE` (`VendorInstallTests.swift`): it needs a
/// real GUI session with Accessibility trust and a real App Store, none of which a
/// hosted CI runner has, and it is slow (waits real seconds for a real page to render).
///
/// Why TestFlight (trackID 899247664): it's Apple's own app, so on any dev Mac it is
/// either already installed (as here) or installable with no purchase involved either
/// way, and its trackID is already a known-good fixture elsewhere in this suite
/// (`MASInstallerTests.swift`). `bind` locates the button purely by `AXIdentifier` and
/// never reads its title — an "Open" button on an already-current TestFlight locates
/// exactly the same way an "Update" one would, which is what makes it safe to use here:
/// `locateOfferButtonForTesting` never performs `AXPress` on anything, so it is safe to
/// run against an app whatever its update state is.
///
/// What this proves, and what it doesn't: it proves `bind`/`waitForOfferButton` still
/// locate a real product page's offer button end-to-end with the #471 stability gate in
/// place (`offerButtonIsStable` requiring two consecutive polls doesn't regress the
/// ordinary, stable case). It does NOT reproduce the ~57-59ms rebuild race itself — that
/// depends on App Store's own timing right after a real navigation, which isn't
/// controllable from outside a test. The race's exact rule (found once vs. found twice
/// in a row) is pinned instead by the unit tests in `AppStoreOfferButtonTests.swift`
/// (`offerButtonIsStable`), which are deterministic and run on every `make test`.
@Test func liveAppStoreOfferButtonIsLocatedWithoutBeingPressed() async throws {
    let stderr = FileHandle.standardError
    func log(_ s: String) { stderr.write((s + "\n").data(using: .utf8)!) }

    guard ProcessInfo.processInfo.environment["DUO_LIVE_APPSTORE_AX_GATE"] == "1" else {
        log("""
            ⚠️ live App Store AX harness SKIPPED — it launches the real App Store app and \
               reads its AX tree (never presses). Run it with \
               `DUO_LIVE_APPSTORE_AX_GATE=1 swift test --filter \
               liveAppStoreOfferButtonIsLocatedWithoutBeingPressed`. It does not run on CI.
            """)
        return
    }
    guard AppStoreAXInstaller.isTrusted else {
        Issue.record(Comment(rawValue: """
            DUO_LIVE_APPSTORE_AX_GATE=1 was set, but this process is not Accessibility- \
            trusted (AXIsProcessTrusted() == false). Grant Accessibility to whatever \
            runs `swift test` and re-run.
            """))
        return
    }
    guard FileManager.default.fileExists(atPath: "/Applications/TestFlight.app") else {
        log("· TestFlight.app not installed here — SKIPPED (nothing to navigate to)")
        return
    }

    let trackID = 899_247_664  // TestFlight — see the type doc comment above for why.
    let names = AppStoreAXInstaller.AppNames(bundle: "TestFlight", store: "TestFlight", localized: "TestFlight")
    let installer = AppStoreAXInstaller()

    let located = try await installer.locateOfferButtonForTesting(trackID: trackID, names: names)
    if located {
        log("· located AppStore.offerButton on TestFlight's product page — not pressed")
    } else {
        Issue.record(Comment(rawValue: """
            Offer button not located within the wait budget. This can be an environment \
            gap rather than a code bug — sign in to the App Store, or a slow-rendering \
            page — not necessarily a regression; see the type doc comment above for what \
            this harness can and can't prove. Re-run with more patience, or by hand, \
            before treating this as red.
            """))
    }
}
#endif
