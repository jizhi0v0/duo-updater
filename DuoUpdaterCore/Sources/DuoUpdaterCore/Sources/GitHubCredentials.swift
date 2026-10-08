import Foundation

/// Which GitHub credentials this process is using — counted, never held.
///
/// The token itself stays with whatever resolved it (`GitHubToken`,
/// `ChangelogService.gitHubToken`, the app's round); this only numbers the
/// changes to what they would resolve: the Settings token saved or cleared, the
/// "Use the GitHub CLI’s sign-in" switch flipped. Each change starts a new
/// generation, and what was learned under an older one says nothing about the
/// credentials in use now. Nothing here compares, stores or logs a token.
///
/// It also remembers, for the rest of a round, that GitHub rejected the token.
/// Sending a rejected token is worse than sending none: every request carrying
/// it fails, where anonymous ones would still be answered. So `countedData`
/// retries a request GitHub rejected once, without the token, and sends the
/// rest of the round's API requests without it — app sources, command-line
/// tool checks and release notes alike, since they all go through it. The next
/// full round (`beginRound`) tries the token again; a change in Settings
/// (`changed`) starts a generation nothing has rejected.
public final class GitHubCredentials: @unchecked Sendable {
    public static let shared = GitHubCredentials()

    private let lock = NSLock()
    private var generationValue = 0

    init() {}

    /// The credentials in use now. Starts at 0 and only grows.
    public var generation: Int { lock.withLock { generationValue } }

    /// The Settings token was saved or cleared, or the switch flipped. The app
    /// calls this from one place, `AppListModel.gitHubCredentialsChanged`.
    public func changed() {
        lock.withLock { generationValue += 1 }
    }

    /// The generation a request made in this task is sent under, when that is
    /// not the current one: a full round bakes the token it resolved into its
    /// sources and goes on sending it after a change, so it runs its check under
    /// the generation it resolved in. Read where the request is made, in the
    /// calling task — never in a session delegate callback, which runs outside
    /// the task's tree (see `RequestMetricsRecorder`).
    @TaskLocal public static var pinnedGeneration: Int?

    /// The generation a request made now, in this task, is sent under.
    func requestGeneration() -> Int { Self.pinnedGeneration ?? generation }

    // MARK: - A rejected token

    /// The instance `countedData` follows: `.shared`, except in a test that
    /// gives its requests their own.
    @TaskLocal static var current: GitHubCredentials = .shared

    /// The generations whose token GitHub rejected since the round began.
    private var rejectedGenerations: Set<Int> = []
    private var rejectionHandler: (@Sendable (Int) -> Void)?

    /// Whether GitHub rejected the token of the credentials in use now, this
    /// round. Cleared by a new round (`beginRound`) and by a change
    /// (`changed`, which starts a generation nothing has rejected yet).
    public var isRejected: Bool {
        lock.withLock { rejectedGenerations.contains(generationValue) }
    }

    func isRejected(generation: Int) -> Bool {
        lock.withLock { rejectedGenerations.contains(generation) }
    }

    /// Called with the generation when GitHub first rejects the token in use,
    /// on whatever thread the answer arrived. A rejection of a generation since
    /// replaced (a round still sending the old token) is not reported.
    public func onRejected(_ handler: @escaping @Sendable (Int) -> Void) {
        lock.withLock { rejectionHandler = handler }
    }

    /// A full round is starting: send the token again. If GitHub still rejects
    /// it, the first 401 rejects it for the rest of the round once more.
    public func beginRound() {
        lock.withLock { rejectedGenerations.removeAll() }
    }

    func recordRejection(generation: Int) {
        let handler: (@Sendable (Int) -> Void)? = lock.withLock {
            let first = rejectedGenerations.insert(generation).inserted
            return first && generation == generationValue ? rejectionHandler : nil
        }
        handler?(generation)
    }

    /// Whether `request` carries a token to the GitHub API — the only token a
    /// 401 from there speaks about. Strictly `ChangelogService.isGitHubAPI`.
    static func carriesToken(_ request: URLRequest) -> Bool {
        guard let url = request.url, ChangelogService.isGitHubAPI(url) else { return false }
        return request.value(forHTTPHeaderField: "Authorization") != nil
    }

    /// GitHub rejected the token `request` carried: a 401 from the API itself.
    /// Measured 2026-10-08: an invalid or revoked token is answered `401` with
    /// "Bad credentials" and no `x-ratelimit-*` headers. A 403 is not this: it
    /// keeps the rate-limit rule (`GitHubReleasesSource.statusError`).
    static func isRejection(of request: URLRequest, _ response: URLResponse) -> Bool {
        guard carriesToken(request), let http = response as? HTTPURLResponse, http.statusCode == 401,
              let url = http.url, ChangelogService.isGitHubAPI(url)
        else { return false }
        return true
    }

    static func anonymous(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        return request
    }
}
