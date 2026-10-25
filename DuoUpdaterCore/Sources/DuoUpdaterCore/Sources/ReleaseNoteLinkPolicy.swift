import Foundation

/// Which links inside rendered release notes are opened when clicked.
///
/// A note is text a vendor (or whoever can answer for the vendor's feed) wrote,
/// and its inline links reach `Text` as `.link` runs. SwiftUI's default
/// `openURL` passes whatever the run holds to `NSWorkspace`, which launches the
/// handler of any registered scheme: `smb:`, `ssh:`, `vnc:`, `shortcuts:`, a
/// third-party app's own scheme. Notes only ever need a web page or a mail
/// address, so only those two are opened and everything else is dropped.
///
/// This is about what a click may *launch*. It does not look at the host, and it
/// is not `ChangelogURLPolicy`, which decides what the app fetches or loads.
public enum ReleaseNoteLinkPolicy {
    public static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "mailto"
    }
}
