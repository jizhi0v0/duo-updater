import Testing
import Foundation
@testable import DuoUpdaterCore

struct ProductSunsetTests {

    /// The end date itself is already ended. Mutation: `<=` for `<` → red.
    @Test func thePhaseTurnsOnTheEndDate() {
        let sunset = ProductSunset(endDate: "2026-12-22", announcement: URL(string: "https://arc.net/")!)
        #expect(sunset.phase(today: "2026-10-23") == .upcoming)
        #expect(sunset.phase(today: "2026-12-21") == .upcoming)
        #expect(sunset.phase(today: "2026-12-22") == .ended)
        #expect(sunset.phase(today: "2027-01-01") == .ended)
    }

    /// Mutation: look the id up without lowercasing it → red.
    @Test func lookupIgnoresCase() {
        #expect(ProductSunsetCatalog.sunset(forBundleID: "company.thebrowser.Browser")?.endDate == "2026-12-22")
        #expect(ProductSunsetCatalog.sunset(forBundleID: "COMPANY.THEBROWSER.BROWSER") != nil)
        #expect(ProductSunsetCatalog.sunset(forBundleID: "company.thebrowser.dia") == nil)
        #expect(ProductSunsetCatalog.sunset(forBundleID: nil) == nil)
    }

    /// Every entry is a real calendar day and links the vendor's page over https:
    /// the date is compared as a string, so a malformed one would misorder.
    /// Mutation: write an entry's date as `2026-12-2` or its link as http → red.
    @Test func everyEntryIsWellFormed() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        #expect(!ProductSunsetCatalog.sunsets.isEmpty)
        for (id, sunset) in ProductSunsetCatalog.sunsets {
            let date = f.date(from: sunset.endDate)
            #expect(date.map { f.string(from: $0) } == sunset.endDate, "\(id): \(sunset.endDate)")
            #expect(sunset.announcement.scheme == "https", "\(id): \(sunset.announcement)")
        }
    }

    @Test func todayIsISOInTheUsersDay() {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (2026, 3, 4, 12)
        let date = Calendar(identifier: .gregorian).date(from: c)!
        #expect(ProductSunsetCatalog.today(date) == "2026-03-04")
    }
}
