import SwiftUI

@main
struct DuoUpdaterApp: App {
    @State private var model = AppListModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            // Badge the menu bar icon with the number of pending updates.
            if model.updateCount > 0 {
                Image(systemName: "\(min(model.updateCount, 50)).circle.fill")
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
