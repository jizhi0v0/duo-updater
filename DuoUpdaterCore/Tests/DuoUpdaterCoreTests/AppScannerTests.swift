import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func scanFindsRealApps() {
    let apps = AppScanner().scan()
    #expect(!apps.isEmpty, "expected to find at least one app in /Applications")
}
