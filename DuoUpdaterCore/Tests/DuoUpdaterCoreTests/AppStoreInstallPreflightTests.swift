import Testing
@testable import DuoUpdaterCore

/// #328 regression: the region-locked Updates-list route matches the app's row by
/// name and presses its button, so once the store has already landed the update
/// the row reads **Open** and the press launches the app. The pre-flight both App
/// Store routes now share is what keeps us from driving the store in that state;
/// these pin its rule.
@Suite("AppStoreInstallPreflight")
struct AppStoreInstallPreflightTests {

    private func side(_ marketing: String? = nil, _ build: String? = nil) -> VersionSide {
        VersionSide(marketing: marketing, build: build)
    }

    @Test("a bundle at the target is already there")
    func diskAtTheTarget() {
        #expect(AppStoreInstallPreflight.bundleAlreadyAt(target: side("1.0"), onDisk: side("1.0")))
    }

    @Test("a bundle past the target is already there too")
    func diskPastTheTarget() {
        #expect(AppStoreInstallPreflight.bundleAlreadyAt(target: side("1.0"), onDisk: side("1.1")))
        #expect(AppStoreInstallPreflight.bundleAlreadyAt(
            target: side("1.0", "9"), onDisk: side("1.0", "10")))
    }

    /// The #328 shape: the store target carries no build (the lookup reports only
    /// the marketing string), while the build the store landed carries one. The
    /// pair is "current", not "cannot tell".
    @Test("a target without a build still matches a disk that has one")
    func targetHasNoBuild() {
        #expect(AppStoreInstallPreflight.bundleAlreadyAt(
            target: side("1.0", nil), onDisk: side("1.0", "9")))
    }

    /// The guard would suppress every real update if it were too eager, so a
    /// genuinely-behind bundle must still be driven.
    @Test("a bundle behind the target is not")
    func diskBehindTheTarget() {
        #expect(!AppStoreInstallPreflight.bundleAlreadyAt(target: side("1.1"), onDisk: side("1.0")))
        #expect(!AppStoreInstallPreflight.bundleAlreadyAt(
            target: side("1.0", "10"), onDisk: side("1.0", "9")))
    }

    /// An empty side is never "already there": the caller must keep driving the
    /// store exactly as it did before the pre-flight existed.
    @Test("empty sides are never already current")
    func emptySides() {
        #expect(!AppStoreInstallPreflight.bundleAlreadyAt(target: nil, onDisk: side("1.0")))
        #expect(!AppStoreInstallPreflight.bundleAlreadyAt(target: side("1.0"), onDisk: VersionSide()))
        #expect(!AppStoreInstallPreflight.bundleAlreadyAt(target: VersionSide(), onDisk: side("1.0")))
    }

    /// The deliberate difference from `hasReached`: two *non-empty* sides that
    /// share no comparable field read as "already current" here, because the
    /// skip direction fails closed and the caller's `mas outdated` veto is the
    /// second opinion. `hasReached` would call this "not landed".
    @Test("a non-empty pair with no shared field fails toward already current")
    func incomparableButNonEmpty() {
        #expect(AppStoreInstallPreflight.bundleAlreadyAt(
            target: side(nil, "5"), onDisk: side("1.0", nil)))
    }

    // MARK: - The press-time guard (#328)

    /// The settled-press refusal is Updates-list-only, and that carve-out is
    /// load-bearing: the product page's settled button no-ops, and a drive that
    /// a `mas outdated` veto deliberately sent there must not be second-guessed
    /// at press time.
    @Test("the settled-press refusal applies only on the Updates list")
    func pressRefusalRouteCarveOut() {
        #expect(AppStoreAXInstaller.updatesListPressIsSettled(
            viaUpdatesList: true, target: side("1.0"), onDisk: side("1.0")))
        #expect(!AppStoreAXInstaller.updatesListPressIsSettled(
            viaUpdatesList: false, target: side("1.0"), onDisk: side("1.0")))
    }

    /// It needs both halves: no target (the caller has none) or a bundle genuinely
    /// behind the target must keep the press.
    @Test("the settled-press refusal needs a target and a settled disk")
    func pressRefusalNeedsBothHalves() {
        #expect(!AppStoreAXInstaller.updatesListPressIsSettled(
            viaUpdatesList: true, target: nil, onDisk: side("1.0")))
        #expect(!AppStoreAXInstaller.updatesListPressIsSettled(
            viaUpdatesList: true, target: side("1.1"), onDisk: side("1.0")))
    }
}
