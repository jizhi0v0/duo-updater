import Foundation

extension GitHubToken {

    /// The Keychain account of the token pasted into Settings ▸ GitHub, under the
    /// app's service. `duo` reads the same item.
    public static let keychainAccount = "github-token"

    /// Where builds from before the Keychain kept that token: a plaintext string in
    /// the app's defaults, readable by any process running as the user and swept
    /// into backups. Migration-only; nothing writes it any more.
    public static let legacyDefaultsKey = "GitHubToken"

    /// The token pasted into Settings, from the Keychain, first moving a plaintext
    /// copy out of `defaults` if a build from before the Keychain left one: into
    /// the Keychain unless it already holds a token (that one is the newer, and is
    /// returned), then off the plist. The app does this at launch and `duo` when it
    /// loads settings, whichever sees the old copy first.
    ///
    /// The plaintext is removed only once the Keychain gives the token back. A
    /// write that did not stick (a locked keychain over SSH, say) leaves the
    /// plaintext where it was, to be moved at the next launch, rather than losing
    /// the only copy.
    ///
    /// `read` and `write` (value, account) are the Keychain, injected for tests.
    public static func storedToken(
        defaults: UserDefaults,
        read: (String) -> String? = { Keychain.string(account: $0) },
        write: (String, String) -> Void = { Keychain.set($0, account: $1) }
    ) -> String? {
        guard let legacy = defaults.string(forKey: legacyDefaultsKey), !legacy.isEmpty else {
            return read(keychainAccount)
        }
        if let current = read(keychainAccount), !current.isEmpty {
            defaults.removeObject(forKey: legacyDefaultsKey)
            return current
        }
        write(legacy, keychainAccount)
        if read(keychainAccount) == legacy {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }
        return legacy
    }
}
