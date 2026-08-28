import Foundation

/// One end of a version comparison: the two strings a macOS bundle actually
/// carries, kept together so the *comparison* can decide which of them
/// discriminates rather than each call site guessing.
///
/// **Why this type exists at all.** `CFBundleShortVersionString` is a marketing
/// string an app is free to leave alone across any number of builds — Amp shipped
/// ten builds called "1.0" on 2026-08-28, Surge has shipped four releases called
/// "6.9.0", JetBrains previews do the same. Any decision made by comparing that
/// string alone degenerates for those apps: `isNewer("1.0","1.0")` is always
/// false and `"1.0" == "1.0"` is always true, so "has it moved?" answers *no*
/// forever and "has it landed?" answers *yes* immediately.
///
/// The codebase used to pick a string per site — `shortVersion ?? buildVersion`
/// in some places, `buildVersion ?? shortVersion` in others, marketing-only in
/// the rest — and got it right about two thirds of the time. `UpdatePolicy`'s
/// staged-relaunch gate had both forms five lines apart. Passing the pair and
/// letting `VersionComparator` choose removes the decision from the call site,
/// which is the only way the fourteenth site cannot get it wrong.
///
/// Deliberately NOT a single "comparison version" string. A build number and a
/// marketing version live in different namespaces — "45830" against "1.96.0" is
/// meaningless — so anything that collapses the pair to one string has to decide
/// which namespace it is in, which is the problem, not the fix.
public struct VersionSide: Sendable, Equatable {
    /// `CFBundleShortVersionString` — what the app calls itself to a human.
    public var marketing: String?
    /// `CFBundleVersion` — what actually increments per build, when the vendor
    /// bothers. Nil is common and must never be read as "0".
    public var build: String?

    public init(marketing: String? = nil, build: String? = nil) {
        self.marketing = marketing
        self.build = build
    }

    /// Whether there is anything here at all. A side with neither string can be
    /// compared against nothing, and callers must treat that as "unknown" rather
    /// than as equality.
    public var isEmpty: Bool { marketing == nil && build == nil }

    /// "1.7.3 (194)", "1.7.3", or a bare "194" — whichever the parts support.
    /// A build equal to the marketing version is never repeated after it.
    public func text(withBuild: Bool) -> String {
        guard let marketing else { return build ?? "?" }
        guard withBuild, let build, build != marketing else { return marketing }
        return "\(marketing) (\(build))"
    }
}
