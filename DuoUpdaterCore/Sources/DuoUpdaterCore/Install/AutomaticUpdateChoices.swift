import Foundation

/// Explicit choices are separate from the default, including "when closed".
/// Existing opt-ins/opt-outs keep their keys. An absent old choice remains the
/// conservative default; migration never grants running-update permission.
public struct AutomaticUpdateChoices: Equatable, Sendable {
    public enum Mode: String, Codable, Equatable, Hashable, Sendable {
        case whenClosed, alsoWhenRunning, never
    }
    /// Setup is a saved preference, not permission to install the current offer.
    /// Sparkle's release-window hold may intentionally carry no download at all.
    /// Keep that copy configurable; execution still uses the full install policy.
    public static func canConfigure(remote: RemoteVersion?, installable: Bool?, awaitingRelaunch: Bool = false) -> Bool {
        if installable != false || awaitingRelaunch { return true }
        return remote?.sourceName == "Sparkle"
            && remote?.subscriptionHold?.recovery == .releaseWindow
            && remote?.downloadURL == nil
    }

    public static let runningKey = "AutomaticUpdateRelaunchKeys"
    public static let excludedKey = "AutomaticUpdateExcludedKeys"
    public static let closedKey = "AutomaticUpdateWhenClosedKeys"
    public static let observationsKey = "AutomaticUpdateObservations"

    public private(set) var running: Set<String>
    public private(set) var excluded: Set<String>
    public private(set) var closed: Set<String>

    public init(defaults: UserDefaults) {
        running = Set(defaults.stringArray(forKey: Self.runningKey) ?? [])
        excluded = Set(defaults.stringArray(forKey: Self.excludedKey) ?? [])
        closed = Set(defaults.stringArray(forKey: Self.closedKey) ?? [])
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(Array(running), forKey: Self.runningKey)
        defaults.set(Array(excluded), forKey: Self.excludedKey)
        defaults.set(Array(closed), forKey: Self.closedKey)
    }

    public func explicitMode(key: String, legacyKey: String) -> Mode? {
        // Preserve old exclusion precedence across both identities. Reading an
        // old conflicting pair must never turn a previous opt-out into consent.
        let keys = [key, legacyKey]
        if keys.contains(where: excluded.contains) { return .never }
        if closed.contains(key) { return .whenClosed }
        if keys.contains(where: running.contains) { return .alsoWhenRunning }
        if closed.contains(legacyKey) { return .whenClosed }
        return nil
    }

    public func setupMode(key: String, legacyKey: String, suggested: Bool) -> Mode {
        explicitMode(key: key, legacyKey: legacyKey) ?? (suggested ? .alsoWhenRunning : .whenClosed)
    }

    public mutating func set(_ mode: Mode, key: String, legacyKey: String) {
        for key in [key, legacyKey] { running.remove(key); excluded.remove(key); closed.remove(key) }
        switch mode {
        case .whenClosed: closed.insert(key)
        case .alsoWhenRunning: running.insert(key)
        case .never: excluded.insert(key)
        }
    }

    public mutating func migrate(from old: String, to new: String) {
        guard old != new else { return }
        if running.remove(old) != nil { running.insert(new) }
        if excluded.remove(old) != nil { excluded.insert(new) }
        if closed.remove(old) != nil { closed.insert(new) }
    }

    public static func observations(from defaults: UserDefaults) -> [String: AutomaticUpdateSuggestion.Observation] {
        guard let data = defaults.data(forKey: observationsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: AutomaticUpdateSuggestion.Observation].self, from: data)) ?? [:]
    }
}
