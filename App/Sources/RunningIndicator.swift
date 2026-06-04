import SwiftUI

/// A small green "live" LED dot shown next to an app's name (right after it) when
/// it currently has a running process. Mirrors the convention of a status list (a
/// green dot = active): it lets the user tell at a glance which apps are open, so
/// they know a Restart will interrupt something — or that an in-place update will
/// leave the running instance on old code until they relaunch.
///
/// Rendered only when the app is running; the call sites gate on
/// `model.isRunning(_:)`, so this view itself is always the "on" state. A plain
/// small filled circle — deliberately understated, sitting inline with the name
/// rather than badged onto the icon.
struct RunningIndicator: View {
    /// Diameter of the dot. Small by default to read as an unobtrusive LED;
    /// larger headers pass a bigger size to stay proportional to the title.
    var size: CGFloat = 5

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: size, height: size)
            .help("Running now")
            .accessibilityLabel("Running")
    }
}
