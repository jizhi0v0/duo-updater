import Foundation

enum com_smartsheet_desktopapp {
    static let set = AppRecipeSet(
        family: "com-smartsheet-desktopapp",
        sunsets: [
        // Smartsheet Desktop App — Smartsheet's help center (read 2026-10-25): the
        // app "and its browser extensions are deprecated and will be retired on or
        // after January 6th, 2027"; smartsheet.com/platform/desktop-app says
        // "retired on January 6, 2027". Move to app.smartsheet.com. Not integrated
        // otherwise; cask `smartsheet` 1.0.54 (bundle ID read from its dmg).
            "com.smartsheet.desktopapp": ProductSunset(
                endDate: "2027-01-06",
                announcement: URL(string: "https://help.smartsheet.com/articles/2482689-desktop-app")!),
        ])
}
