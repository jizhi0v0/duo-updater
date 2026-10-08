import Foundation

/// Which GitHub credentials this process is using — counted, never held.
///
/// The token itself stays with whatever resolved it (`GitHubToken`,
/// `ChangelogService.gitHubToken`, the app's round); this only numbers the
/// changes to what they would resolve: the Settings token saved or cleared, the
/// "Use the GitHub CLI’s sign-in" switch flipped. Each change starts a new
/// generation, and what was learned under an older one says nothing about the
/// credentials in use now. Nothing here compares, stores or logs a token.
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
}
