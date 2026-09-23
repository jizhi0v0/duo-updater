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
@Observable
final class AppleDeveloperSession {
    static let shared = AppleDeveloperSession()

    /// Fixed so the same on-disk store is found again at the next launch. A
    /// dedicated identifier (rather than `.default()`) keeps this session's
    /// cookies out of the app's other web views (release-notes rendering in the
    /// workbench) and vice versa.
    private static let dataStoreIdentifier = UUID(uuidString: "9F1E9A9C-9A9F-4A6B-8B8E-6E8C8F1E9A9C")!

    private static let keychainAccount = "apple-developer-session"

    @ObservationIgnored private(set) lazy var dataStore: WKWebsiteDataStore =
        WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)

    /// Guards `restore()` so it only ever runs once per launch, no matter how
    /// many call sites race to be first (app launch, and the sign-in window or
    /// downloader if either is used before launch wiring runs).
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    /// A `myacinfo` cookie is in the store — the app holds a session. Says
    /// nothing about whether Apple still honours it; `status` does.
    private(set) var isSignedIn = false

    /// What Apple last said about the held session (`check()`). `.unknown` until
    /// the first conclusive answer this launch.
    enum Status: Equatable { case unknown, signedIn, expired }
    private(set) var status: Status = .unknown

    /// When Apple last confirmed the session — by `check()`, a completed sign-in,
    /// or a finished download. Kept across launches for Settings → Xcode.
    private(set) var lastConfirmed: Date? =
        UserDefaults.standard.object(forKey: AppleDeveloperSession.lastConfirmedKey) as? Date

    private static let lastConfirmedKey = "appleDeveloperSessionLastConfirmed"

    /// Why the Xcode row cannot update right now, or nil when it can try.
    var signInNeed: AppleSignInNeed? {
        if !isSignedIn { return .notSignedIn }
        return status == .expired ? .expired : nil
    }

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
    /// sign-in completes and after each download finishes (the file response
    /// that authorized it is exactly when a fresh `ADCDownloadAuth`/session
    /// cookie shows up). Not hooked to app termination: there is no delegate
    /// available here to hold the process open for the async fetch and write,
    /// and these two call sites already cover every moment the session
    /// actually changes.
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
        // A renewal that lands after the erase would save a new session.
        if let renewal { _ = await renewal.value }
        Keychain.delete(account: Self.keychainAccount)
        status = .unknown
        renewalTried = false
        lastConfirmed = nil
        UserDefaults.standard.removeObject(forKey: Self.lastConfirmedKey)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records)
        isSignedIn = false
    }

    /// What an Xcode row says while `status` is `.expired`.
    static var expiredMessage: String {
        String(localized: "Your Apple Developer sign-in has expired. Sign in again to update Xcode.")
    }

    /// Apple sent a request that carried the session to sign-in instead.
    func noteExpired() {
        status = .expired
    }

    /// Apple just honoured the session: a sign-in completed or a download was
    /// authorized.
    func noteConfirmed() {
        status = .signedIn
        renewalTried = false
        let now = Date()
        lastConfirmed = now
        UserDefaults.standard.set(now, forKey: Self.lastConfirmedKey)
    }

    /// A silent renewal has been tried since Apple last confirmed the session.
    /// One try per expiry: when Apple's sign-in session has ended too, the next
    /// sign-in needs the user, and asking a hidden page every hour won't change
    /// that.
    @ObservationIgnored private var renewalTried = false
    @ObservationIgnored private var renewal: Task<AppleDeveloperSessionProbe.Verdict, Never>?

    /// Ask Apple whether the held session is still signed in (`ask()`), and when
    /// Apple says it has ended, try once to get a new one without the user
    /// (`AppleDeveloperSessionRenewal`): a hidden page on this store, then Apple
    /// is asked again. Only that second answer counts — a page that came back
    /// is not proof of a session.
    ///
    /// Not signed in at all → `.inconclusive` without a request: there is no
    /// session to ask about.
    ///
    /// `renewing: false` is for the sign-in window: the user is signing in, so it
    /// neither starts a renewal nor waits on one — it asks Apple directly.
    @discardableResult
    func check(renewing: Bool = true) async -> AppleDeveloperSessionProbe.Verdict {
        if renewing, let renewal { return await renewal.value }
        let verdict = await ask()
        guard AppleDeveloperSessionRenewal.shouldTry(
            verdict: verdict, alreadyTried: renewalTried, allowed: renewing)
        else { return verdict }
        renewalTried = true
        let task = Task { @MainActor in await self.renew() }
        renewal = task
        defer { renewal = nil }
        return await task.value
    }

    private func renew() async -> AppleDeveloperSessionProbe.Verdict {
        let since = lastConfirmed.map { Int(Date().timeIntervalSince($0) / 60) } ?? -1
        let started = Date()
        let landed = await AppleDeveloperSessionRenewer().run(in: dataStore)
        let verdict = landed ? await ask() : .expired
        let seconds = Int(Date().timeIntervalSince(started))
        Log.app.notice("apple session renewal: \(verdict == .signedIn ? "renewed" : "failed", privacy: .public) in \(seconds, privacy: .public)s, page \(landed ? "came back" : "stayed on sign-in", privacy: .public); last confirmed \(since, privacy: .public) min before")
        return verdict
    }

    /// One request to the authorized download endpoint, redirect not followed
    /// (`AppleDeveloperSessionProbe`). Updates `status`; an inconclusive answer
    /// (offline, a proxy page) leaves it as it was. Cookies the response sets are
    /// written back to the store and saved, as after a download.
    private func ask() async -> AppleDeveloperSessionProbe.Verdict {
        await restore()
        let cookies = await dataStore.httpCookieStore.allCookies()
        await refreshSignedInState(cookies: cookies)
        guard isSignedIn else { return .inconclusive }

        guard let (urlSession, jar) = Self.sessionCarrying(cookies) else { return .inconclusive }
        defer { urlSession.finishTasksAndInvalidate() }

        let verdict: AppleDeveloperSessionProbe.Verdict
        do {
            let (_, response) = try await urlSession.data(from: AppleDeveloperSessionProbe.probeURL)
            let http = response as? HTTPURLResponse
            verdict = AppleDeveloperSessionProbe.verdict(
                status: http?.statusCode ?? 0,
                location: http?.value(forHTTPHeaderField: "Location"))
            // Notice, not info: kept on disk, so an expiry can be dated afterwards.
            Log.app.notice("apple session check: \(http?.statusCode ?? 0, privacy: .public) → \(String(describing: verdict), privacy: .public)")
        } catch {
            Log.app.notice("apple session check failed: \(error.localizedDescription, privacy: .public)")
            return .inconclusive
        }

        switch verdict {
        case .signedIn:
            for cookie in AppleDeveloperCookieJar.decode(AppleDeveloperCookieJar.encode(jar.cookies ?? [])) {
                await dataStore.httpCookieStore.setCookie(cookie)
            }
            await save()
            noteConfirmed()
        case .expired:
            status = .expired
        case .inconclusive:
            break
        }
        return verdict
    }

    /// Apple's own list of developer downloads (`AppleDeveloperDownloadList`),
    /// fetched with the held session; nil when not signed in, or when Apple
    /// answers with anything but a 200 (a redirect to sign-in is not followed).
    /// Says nothing about the session either way — `check()` owns that.
    func fetchDownloadList() async -> Data? {
        await restore()
        let cookies = await dataStore.httpCookieStore.allCookies()
        await refreshSignedInState(cookies: cookies)
        guard signInNeed == nil,
              let (urlSession, _) = Self.sessionCarrying(cookies) else { return nil }
        defer { urlSession.finishTasksAndInvalidate() }
        var request = URLRequest(url: AppleDeveloperDownloadList.endpoint)
        request.httpMethod = "POST"
        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Log.app.info("apple download list: \(status, privacy: .public), \(data.count, privacy: .public) bytes")
            return status == 200 ? data : nil
        } catch {
            Log.app.info("apple download list failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// An ephemeral session carrying the store's `*.apple.com` cookies, redirects
    /// not followed. An ephemeral configuration's cookie storage is its own, in
    /// memory: nothing here touches the shared jar or disk. The encode/decode
    /// round trip is the jar's `*.apple.com` filter.
    private static func sessionCarrying(_ cookies: [HTTPCookie]) -> (URLSession, HTTPCookieStorage)? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        guard let jar = configuration.httpCookieStorage else { return nil }
        jar.cookieAcceptPolicy = .always
        for cookie in AppleDeveloperCookieJar.decode(AppleDeveloperCookieJar.encode(cookies)) {
            jar.setCookie(cookie)
        }
        let session = URLSession(
            configuration: configuration, delegate: RedirectRefuser(), delegateQueue: nil)
        return (session, jar)
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

/// Hands the redirect back as the response instead of following it — the
/// check only needs to know where Apple would send us.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
