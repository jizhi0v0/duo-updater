import Testing
import Foundation
@testable import DuoUpdaterCore

/// `GitHubToken.storedToken`: the Keychain read both the app and `duo` make, with
/// the move of an old plaintext copy out of the defaults plist.
///
/// The Keychain is a dictionary here and the defaults a scratch suite: nothing
/// reads or writes the user's token, and no prompt can come up.
@Suite(.serialized) struct GitHubTokenStorageTests {

    /// A Keychain that can refuse writes, as a locked one does.
    private final class FakeKeychain: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: String]
        private let refusesWrites: Bool
        private var _writes: [String] = []
        init(_ items: [String: String] = [:], refusesWrites: Bool = false) {
            self.items = items
            self.refusesWrites = refusesWrites
        }
        func read(_ account: String) -> String? { lock.withLock { items[account] } }
        func write(_ value: String, _ account: String) {
            lock.withLock {
                _writes.append(account)
                if !refusesWrites { items[account] = value }
            }
        }
        var writes: [String] { lock.withLock { _writes } }
    }

    private func stored(_ keychain: FakeKeychain, _ defaults: UserDefaults) -> String? {
        GitHubToken.storedToken(defaults: defaults, read: keychain.read, write: keychain.write)
    }

    /// No plaintext copy: the Keychain's value, and nothing is written.
    @Test func withoutALegacyCopyItIsAPlainRead() {
        let scratch = ScratchDefaults("github-token-plain")
        defer { scratch.clear() }
        let keychain = FakeKeychain([GitHubToken.keychainAccount: "from-keychain"])
        #expect(stored(keychain, scratch.defaults) == "from-keychain")
        #expect(stored(FakeKeychain(), scratch.defaults) == nil)
        #expect(keychain.writes.isEmpty)
    }

    /// The old copy goes into the Keychain and off the plist.
    ///
    /// Mutation: drop the `removeObject` after the write → the plaintext stays.
    @Test func aLegacyCopyMovesToTheKeychainAndOffThePlist() {
        let scratch = ScratchDefaults("github-token-migrate")
        defer { scratch.clear() }
        scratch.defaults.set("ghp_legacy", forKey: GitHubToken.legacyDefaultsKey)
        let keychain = FakeKeychain()

        #expect(stored(keychain, scratch.defaults) == "ghp_legacy")
        #expect(keychain.read(GitHubToken.keychainAccount) == "ghp_legacy")
        #expect(scratch.defaults.object(forKey: GitHubToken.legacyDefaultsKey) == nil)
        // And the next read is the Keychain's.
        #expect(stored(keychain, scratch.defaults) == "ghp_legacy")
        #expect(keychain.writes.count == 1)
    }

    /// A token already in the Keychain is the newer one: it is kept and returned,
    /// and the plaintext is scrubbed all the same.
    ///
    /// Mutation: write the legacy value unconditionally → the pasted token is lost.
    @Test func aTokenAlreadyInTheKeychainIsNotOverwritten() {
        let scratch = ScratchDefaults("github-token-keep")
        defer { scratch.clear() }
        scratch.defaults.set("ghp_legacy", forKey: GitHubToken.legacyDefaultsKey)
        let keychain = FakeKeychain([GitHubToken.keychainAccount: "ghp_pasted"])

        #expect(stored(keychain, scratch.defaults) == "ghp_pasted")
        #expect(keychain.read(GitHubToken.keychainAccount) == "ghp_pasted")
        #expect(keychain.writes.isEmpty)
        #expect(scratch.defaults.object(forKey: GitHubToken.legacyDefaultsKey) == nil)
    }

    /// A write that did not stick keeps the plaintext, so the only copy is not lost;
    /// the token is still returned for this run.
    ///
    /// Mutation: remove the plaintext without reading the Keychain back.
    @Test func aWriteThatDidNotStickKeepsThePlaintext() {
        let scratch = ScratchDefaults("github-token-locked")
        defer { scratch.clear() }
        scratch.defaults.set("ghp_legacy", forKey: GitHubToken.legacyDefaultsKey)
        let keychain = FakeKeychain(refusesWrites: true)

        #expect(stored(keychain, scratch.defaults) == "ghp_legacy")
        #expect(scratch.defaults.string(forKey: GitHubToken.legacyDefaultsKey) == "ghp_legacy")
        #expect(keychain.writes.count == 1)
    }

    /// An empty plaintext value is no token.
    @Test func anEmptyLegacyValueIsIgnored() {
        let scratch = ScratchDefaults("github-token-empty")
        defer { scratch.clear() }
        scratch.defaults.set("", forKey: GitHubToken.legacyDefaultsKey)
        let keychain = FakeKeychain([GitHubToken.keychainAccount: "ghp_pasted"])
        #expect(stored(keychain, scratch.defaults) == "ghp_pasted")
        #expect(keychain.writes.isEmpty)
    }

    /// The names are the ones the app has always used: a change here would strand
    /// every existing token.
    @Test func theNamesAreTheOnesAlreadyOnDisk() {
        #expect(GitHubToken.keychainAccount == "github-token")
        #expect(GitHubToken.legacyDefaultsKey == "GitHubToken")
    }
}
