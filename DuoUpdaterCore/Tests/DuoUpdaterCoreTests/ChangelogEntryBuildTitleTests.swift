import XCTest
@testable import DuoUpdaterCore

final class ChangelogEntryBuildTitleTests: XCTestCase {
    private func entry(title: String?, version: String) -> Changelog.Entry {
        Changelog.Entry(title: title, version: version, date: nil, items: ["A note."])
    }

    func testVersionAndBuildTitleIsRecognised() {
        XCTAssertTrue(entry(title: "1.1 (25)", version: "1.1").titleNamesVersionAndBuild)
        XCTAssertTrue(entry(title: "0.1.0 (1925)", version: "0.1.0").titleNamesVersionAndBuild)
    }

    /// Post-style titles keep the version shown beside them.
    func testOtherTitlesAreNot() {
        XCTAssertFalse(entry(title: nil, version: "1.1").titleNamesVersionAndBuild)
        XCTAssertFalse(entry(title: "Rockxy 0.38.3 (build 58)", version: "0.38.3").titleNamesVersionAndBuild)
        XCTAssertFalse(entry(title: "Big summer update", version: "2.0").titleNamesVersionAndBuild)
        XCTAssertFalse(entry(title: "1.10 (3)", version: "1.1").titleNamesVersionAndBuild)
        XCTAssertFalse(entry(title: "(25)", version: "").titleNamesVersionAndBuild)
    }
}
