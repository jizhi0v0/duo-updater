import Foundation
import AppKit

/// Which app bundles currently have a live process.
///
/// `NSWorkspace` works from a plain command-line tool — it asks the launch
/// services daemon rather than needing a GUI session of its own — but it is the
/// one place the CLI touches AppKit, so it is fenced off here instead of leaking
/// the import into the policy code.
enum RunningApps {
    static func bundleURLs() -> [URL] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
    }
}
