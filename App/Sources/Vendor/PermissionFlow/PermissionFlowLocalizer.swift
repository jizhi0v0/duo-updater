#if os(macOS)
import Foundation

/// Vendored from jaywcjlove/PermissionFlow (MIT) — see LICENSE in this folder.
///
/// The upstream localizer resolves strings from the package's `.lproj`
/// resources via `Bundle.module`. We vendor only the source files (no resource
/// bundle), so this stub returns the caller-supplied English `defaultValue`.
/// Every call site already passes a sensible default, so behaviour matches the
/// upstream English locale. Re-introduce a resource bundle here if we ever need
/// localized permission copy.
@available(macOS 13.0, *)
enum PermissionFlowLocalizer {
    static func string(
        _ key: String,
        defaultValue: String,
        localeIdentifier: String?
    ) -> String {
        defaultValue
    }
}
#endif
