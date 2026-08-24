import Foundation

/// A release track the VENDOR puts an account on, selected by a value the
/// request carries.
///
/// Three types in this codebase now answer "which build does this machine get",
/// and telling them apart is the whole reason this one exists:
///
///   * `ReleaseChannel` / `ChannelBinding` — the channel a user **chose**. Its
///     resolvers read a preference the user flipped, and its safety rule is
///     "never fall back to a higher channel", because the wrong answer means
///     pushing a prerelease at someone who didn't ask for one.
///   * `ProbeIdentity` — the machine's own **identity**: an id that selects a
///     rollout BUCKET inside one track and grants nothing. Fabricating one
///     lands you in a stranger's bucket, so it has no fallback and an
///     unreadable value skips the recipe.
///   * `RolloutTrack` (this) — a **track** the vendor assigns. Nobody chose it,
///     it identifies no machine, and the vendor defines a "don't know" value
///     for it, so unlike an identity it *can* fall back.
///
/// Structurally it is `TablePlusChannel` with a query parameter where that has a
/// header: ONE endpoint, ONE request-borne value, and the server decides which
/// builds come back. ChatGPT's `plan_type` is the instance — see the Codex
/// recipe in `VendorProbeRegistry` for what it selects and what it costs to get
/// wrong.
///
/// Getting it wrong is expensive in a specific, quiet way that
/// `ChannelArtifactProof` already describes for channel recipes: the version
/// resolves, the URL resolves, the download is a real notarized build from the
/// same vendor with the same Team ID, so every gate we have passes — and the
/// machine's own updater refuses the build, stages the one it wanted, and
/// applies it at the next quit. Our restart is that quit. Nothing in a normal
/// probe can see this, which is why `contrastValue` is part of the type.
public struct RolloutTrack: Sendable {

    /// How this machine's value is read, and the placeholder it replaces.
    ///
    /// Deliberately reuses `ProbeIdentity`: the mechanics are identical — one
    /// value out of one local file, held to a pattern and a character backstop,
    /// substituted inside the fetch and recorded nowhere. What differs is what
    /// the value MEANS, and that is what this type carries.
    public let selector: ProbeIdentity

    /// A value known to select a DIFFERENT track from this vendor.
    ///
    /// Not decoration — it is the only way to answer "is this parameter doing
    /// anything right now". Vendor tracks converge once a rollout finishes, and
    /// while they are converged our value and any other give the same answer.
    /// A check that looks only at our own answer therefore cannot distinguish
    /// "we picked the right track" from "it did not matter today", and will
    /// report healthy right up until the next rollout window opens.
    public let contrastValue: String

    /// What to call the track `contrastValue` selects, in a finding a human
    /// reads. ("the enterprise track", "the beta track".)
    public let contrastTrackName: String

    public init(selector: ProbeIdentity, contrastValue: String, contrastTrackName: String) {
        self.selector = selector
        self.contrastValue = contrastValue
        self.contrastTrackName = contrastTrackName
    }
}

/// What asking the endpoint twice — once with this machine's value, once with
/// `RolloutTrack.contrastValue` — established.
///
/// Deliberately a verification-time answer, not a runtime one. It costs an extra
/// request per check, which is fine inside a sweep that already makes ~150 and
/// wrong inside the app's periodic check.
public enum RolloutTrackVerdict: Sendable, Equatable {

    /// The two values resolved to different targets: the vendor is running two
    /// tracks *right now*, so which one we ask for decides what we offer.
    case diverged(ours: String, contrast: String)

    /// Both resolved alike. Either the rollout completed and the tracks merged,
    /// or the parameter stopped mattering. Indistinguishable from here, and in
    /// both cases nothing we send today can be wrong.
    case converged(String)

    /// A request failed, so nothing was established. Not a finding: the vendor
    /// being unreachable is not the recipe being wrong.
    case indeterminate

    public var name: String {
        switch self {
        case .diverged: return "diverged"
        case .converged: return "converged"
        case .indeterminate: return "indeterminate"
        }
    }
}
