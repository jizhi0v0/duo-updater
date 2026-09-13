import Foundation

/// Which app the work in this task is being done for.
///
/// The request log can say what was fetched but not what for:
/// `objects.githubusercontent.com/…/asset/12345` names no app, and neither does
/// a vendor's `/api/v1/latest`. Attribution has to come from the caller, which
/// knows perfectly well.
///
/// **A task-local rather than a parameter**, because the alternative is threading
/// an app id through some forty call sites across twenty update sources — a
/// change on the path every single request takes, to carry a value almost none
/// of those frames look at. The scope where the app *is* known is one loop, so
/// one `withApp` wraps it.
///
/// This works precisely because it is read at the point the request is made
/// (``URLSession/countedData(for:purpose:store:)``), inside the calling task.
/// Reading it in the metrics callback does **not** work — that runs on the
/// session's delegate queue, outside this task's tree, and was measured
/// returning the default. Anything that later wants the app id further down must
/// take it as a parameter, not reach for this.
public enum RequestAttribution {

    @TaskLocal public static var appID: String?

    /// Runs `body` with every request it makes attributed to `appID`.
    ///
    /// Nesting is honest: an inner scope replaces the outer one for its duration,
    /// so a self-update kicked off while checking an app is not filed against
    /// that app.
    /// `isolation` is inherited from the caller so the operation stays on the
    /// actor that called it — without it the closure crosses an isolation
    /// boundary and has to be `Sendable`, which the install route's is not.
    public static func withApp<T>(
        _ appID: String?,
        isolation: isolated (any Actor)? = #isolation,
        operation body: () async throws -> T
    ) async rethrows -> T {
        // Swift 6.4 deprecates the `isolation:` overload in favour of a
        // `nonisolated(nonsending)` one, which runs its operation on whatever
        // executor calls it — here, `isolation`, so the contract above holds. The
        // wrapper closure is what selects it: passing `body` straight through
        // still resolves to the deprecated overload, because `body` is not typed
        // `nonisolated(nonsending)`. CI and the release build are on Swift 6.3,
        // whose `_Concurrency` has no such overload, hence the `#if`.
        #if compiler(>=6.4)
        try await $appID.withValue(appID) { () async throws -> T in try await body() }
        #else
        try await $appID.withValue(appID, operation: body, isolation: isolation)
        #endif
    }
}
