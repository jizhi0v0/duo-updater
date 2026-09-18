import Foundation

/// A preferences domain for tests that write settings, kept off the real
/// `com.duoupdater.app` domain.
///
/// The name is fixed per `label` rather than a fresh UUID per test. A UUID domain
/// is a new plist in `~/Library/Preferences`, and a test cannot take it back:
/// `removePersistentDomain(forName:)` empties the domain but leaves the file, and
/// unlinking the file afterwards does not stick — removing the domain marks it
/// dirty, so cfprefsd writes it back out when the process exits. Measured
/// 2026-09-18 on Darwin 27, 40 suites per recipe, counted after exit:
/// remove + synchronize + unlink left 40/40. (Unlinking without removing the
/// domain first left 0/40 — but that is not cleanup: the values stay live in
/// cfprefsd, and it is the dirty flag, not the file, that decides.)
///
/// So the only lever is how many *names* the suite ever asks for: one per label
/// costs one file however often the suite runs. One per test had reached 10,093
/// files — about 90% of that directory — before they were swept by hand on
/// 2026-09-18. This suite alone opened seven of them per run, one per test.
///
/// That also means the file count is bounded whether or not `clear()` runs.
/// Cleanup still matters for a different reason: the domain outlives the
/// process, so a run that died before its teardown would otherwise hand its
/// values to the next run. `init` clears on the way in for exactly that case —
/// verified by killing a run mid-test, where the next one read the dead run's
/// value without it. `clear()` on the way out leaves the domain empty.
///
/// Callers give the label; two suites that could run concurrently must not share
/// one, since Swift Testing parallelises across suites.
struct ScratchDefaults {

    let label: String
    let defaults: UserDefaults

    init(_ label: String) {
        self.label = "com.duoupdater.tests.\(label)"
        // `!` is safe: the initialiser only returns nil for a name the process
        // cannot own, such as its own bundle identifier.
        self.defaults = UserDefaults(suiteName: self.label)!
        clear()
    }

    /// Empties the domain. Safe to call more than once, and on a domain that was
    /// never written.
    func clear() {
        defaults.removePersistentDomain(forName: label)
        defaults.synchronize()
    }
}
