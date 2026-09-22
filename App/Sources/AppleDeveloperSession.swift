import Foundation
import WebKit
import DuoUpdaterCore

/// Owns the Apple Developer sign-in session that the `.xcode` install route needs
/// — a dedicated `WKWebsiteDataStore` plus the cookies that keep it signed in
/// across launches.
///
/// WebKit drops session-only cookies (`myacinfo`, the one that actually proves
/// you're signed in) the moment the app quits, even with the default *persistent*
/// data store — measured 2026-09-22 with a standalone probe. So this class saves
/// the store's `*.apple.com` cookies to the Keychain by hand at the moments they
/// might have changed, and restores them into a fresh store at next launch,
/// before anything tries to use it.
///
/// This is Option C, chosen deliberately with the user: DuoUpdater signs in
/// inside its own web view and holds the session itself, reversing the app's
/// usual "never hold credentials" stance. That's why every place this data is
/// kept or sent is spelled out in the Xcode settings page, and why `signOut()`
/// is a real, complete erase rather than "log out and hope".
@MainActor
final class AppleDeveloperSession {
    static let shared = AppleDeveloperSession()

    /// Fixed so the same on-disk store is found again at the next launch. A
    /// dedicated identifier (rather than `.default()`) keeps this session's
    /// cookies out of the app's other web views (release-notes rendering in the
    /// workbench) and vice versa.
    private static let dataStoreIdentifier = UUID(uuidString: "9F1E9A9C-9A9F-4A6B-8B8E-6E8C8F1E9A9C")!

    private static let keychainAccount = "apple-developer-session"

    private(set) lazy var dataStore: WKWebsiteDataStore =
        WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)

    /// Guards `restore()` so it only ever runs once per launch, no matter how
    /// many call sites race to be first (app launch, and the sign-in window or
    /// downloader if either is used before launch wiring runs).
    private var restored = false
    private var restoreTask: Task<Void, Never>?

    private(set) var isSignedIn = false

    private init() {}

    /// Load the saved cookies into `dataStore`, once. Call this early at app
    /// launch, before anything reads `dataStore`'s cookies or loads a URL in it.
    func restore() async {
        if let restoreTask { await restoreTask.value; return }
        guard !restored else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            let data = Keychain.data(account: Self.keychainAccount) ?? Data()
            let cookies = AppleDeveloperCookieJar.decode(data)
            for cookie in cookies {
                await self.dataStore.httpCookieStore.setCookie(cookie)
            }
            await self.refreshSignedInState()
            self.restored = true
        }
        restoreTask = task
        await task.value
    }

    /// Snapshot the store's `*.apple.com` cookies and persist them. Call after
    /// sign-in completes, after each download is authorized (the file response
    /// arrives — that's when a fresh `ADCDownloadAuth`/session cookie shows up),
    /// and at app termination.
    func save() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
        let data = AppleDeveloperCookieJar.encode(cookies)
        if data.isEmpty {
            Keychain.delete(account: Self.keychainAccount)
        } else {
            Keychain.set(data, account: Self.keychainAccount)
        }
        await refreshSignedInState(cookies: cookies)
    }

    /// Forget everything: the Keychain entry and all website data in this store
    /// (cookies, cache, local storage — not just the session cookie), so the next
    /// sign-in starts from nothing. This also forgets Apple's "trust this device"
    /// cookie, so the next sign-in asks for 2FA again — the settings page says so.
    func signOut() async {
        Keychain.delete(account: Self.keychainAccount)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records)
        isSignedIn = false
    }

    /// Re-check `isSignedIn` against the store's live cookies, and return the
    /// result. Cheap (no network) — safe to call whenever the settings page
    /// appears or an action might have changed the answer.
    @discardableResult
    func refreshSignedInState() async -> Bool {
        await refreshSignedInState(cookies: await dataStore.httpCookieStore.allCookies())
    }

    @discardableResult
    private func refreshSignedInState(cookies: [HTTPCookie]) async -> Bool {
        isSignedIn = cookies.contains { $0.name == "myacinfo" }
        return isSignedIn
    }
}
