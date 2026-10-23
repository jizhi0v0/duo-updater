import Foundation

enum company_thebrowser_Browser {
    static let set = AppRecipeSet(
        family: "company-thebrowser-Browser",
        sunsets: [
        // Arc — The Browser Company's "A farewell to Arc" on arc.net (read
        // 2026-10-23): from 2026-12-22 Arc can no longer be accessed or used on
        // macOS. History: docs/app-audits/company-thebrowser-Browser.md#产品终止
            "company.thebrowser.Browser": ProductSunset(
                endDate: "2026-12-22",
                announcement: URL(string: "https://arc.net/")!),
        ])
}
