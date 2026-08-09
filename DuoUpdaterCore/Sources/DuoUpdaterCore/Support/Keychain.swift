import Foundation
import Security

/// Tiny wrapper over the macOS Keychain for the handful of user-supplied secrets we
/// persist (currently just the GitHub token). A secret belongs here, not in
/// UserDefaults: a `~/Library/Preferences` plist is plaintext, readable by any
/// process running as the user and swept into unencrypted backups. Stored as a
/// generic password, `AfterFirstUnlockThisDeviceOnly` (available to background
/// refreshes after the first unlock, never synced off the device).
///
/// The service name is the app's, and it is shared with the `duo` CLI on
/// purpose: one token entered once, honoured by both. macOS scopes a generic
/// password's ACL to the program that created it, so the *first* read from a
/// different binary raises the system "wants to access" prompt — expected, and
/// answered once with Always Allow. `duo doctor` says so rather than letting it
/// arrive unexplained during a check.
public enum Keychain {
    private static let service = "com.duoupdater.app"

    /// The stored secret for `account`, or nil if absent.
    public static func string(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    /// Store `value` for `account`, replacing any existing entry. An empty value
    /// deletes the entry (so "clear the token" leaves nothing behind).
    public static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard !value.isEmpty else {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
