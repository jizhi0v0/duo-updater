import Foundation

/// KVO on arbitrary `UserDefaults` keys, which is the only mechanism that sees a
/// write from **another process**.
///
/// A shim rather than Swift's `defaults.observe(\.someKey)` because that form
/// needs an `@objc dynamic` property on `UserDefaults`, and these keys are
/// strings the app defines. The string-based API in turn needs an `NSObject`
/// observer, which the `@Observable` classes that want this are not.
///
/// Unregisters in `deinit`, so the owner only has to keep it alive.
final class DefaultsKeyObserver: NSObject {

    private let defaults: UserDefaults
    private let keys: [String]
    private let onChange: @Sendable () -> Void

    init(defaults: UserDefaults, keys: [String], onChange: @escaping @Sendable () -> Void) {
        self.defaults = defaults
        self.keys = keys
        self.onChange = onChange
        super.init()
        for key in keys {
            defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
    }

    deinit {
        for key in keys {
            defaults.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        // Delivered on whatever thread the defaults daemon's change lands on, so
        // hop to the main actor before touching observable app state. The
        // closure is captured rather than `self` so this does not send a
        // non-Sendable observer across the isolation boundary.
        let notify = onChange
        Task { @MainActor in notify() }
    }
}
