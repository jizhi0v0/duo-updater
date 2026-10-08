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
}
