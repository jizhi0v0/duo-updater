import Foundation
import DuoUpdaterCore

/// `duo ignore` / `unignore` / `skip` / `unskip` — hide an app, or one version
/// of it, from update checks.
///
/// The only commands that **write** the app's preferences. Two things make that
/// safe rather than a race:
///
///  - The keys are derived by `InstallPreferenceKey`, shared with the app, and
///    their UserDefaults names come from `UpdateSettings`. A key derived even
///    slightly differently would not read as empty — it would build a second,
///    invisible ignore list while the app kept using the first.
///  - The running app re-reads both lists when another process changes them
///    (KVO on the defaults keys; see `Preferences.observeExternalWrites`).
///    Without that it would eventually write its cached copy back over ours and
///    this would look like it had silently done nothing.
///
/// Read-modify-write is not atomic across processes. Two writers racing on the
/// same key can lose one edit — acceptable here because both writers are the
/// user, acting seconds apart, and the loss is one hidden row rather than
/// anything destructive. A lock would be the wrong shape: these are instant.
public enum Visibility {

    public enum Action: String, Sendable, CaseIterable {
        case ignore, unignore, skip, unskip
    }

    public struct Options: Sendable {
        public var action: Action
        public var queries: [String]
        public var json = false
        public init(action: Action, queries: [String]) {
            self.action = action
            self.queries = queries
        }
    }

    public static func run(_ options: Options) async -> Int32 {
        guard !options.queries.isEmpty else {
            FileHandle.standardError.write(Data(
                "duo: name an app to \(options.action.rawValue)\n".utf8))
            return 2
        }
        let settings = Settings.load()
        let apps = await Inventory.scan(settings)
        let selected: [InstalledApp]
        switch Inventory.select(apps, matching: options.queries) {
        case .success(let matched): selected = matched
        case .failure(let failure):
            FileHandle.standardError.write(Data("duo: \(failure)\n".utf8))
            return 2
        }

        // `skip` needs to know which version is being declined, which only a
        // check can say. The others are offline.
        let results: [UpdateResult]
        if options.action == .skip {
            print("Checking \(selected.count) app\(selected.count == 1 ? "" : "s")…")
            results = await Inventory.checker(settings).check(selected)
        } else {
            results = selected.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        }

        guard let defaults = UserDefaults(suiteName: Settings.suiteName) else {
            FileHandle.standardError.write(Data(
                "duo: could not open the \(Settings.suiteName) preferences\n".utf8))
            return 1
        }

        var changed: [(String, String)] = []
        var refused: [(String, String)] = []
        for result in results {
            switch apply(options.action, to: result, in: defaults) {
            case .success(let note): changed.append((result.app.name, note))
            case .failure(let why):  refused.append((result.app.name, why))
            }
        }

        report(options.action, changed: changed, refused: refused, json: options.json)
        return refused.isEmpty ? 0 : 1
    }

    // MARK: - The writes

    enum Outcome {
        case success(String)
        case failure(String)
    }

    static func apply(_ action: Action, to result: UpdateResult, in defaults: UserDefaults) -> Outcome {
        let key = InstallPreferenceKey.key(for: result.app)
        let legacy = InstallPreferenceKey.legacyKey(for: result.app)

        switch action {
        case .ignore:
            var keys = Set(defaults.stringArray(forKey: UpdateSettings.ignoredKeysKey) ?? [])
            guard keys.insert(key).inserted else { return .failure("already ignored") }
            defaults.set(Array(keys).sorted(), forKey: UpdateSettings.ignoredKeysKey)
            return .success("ignored")

        case .unignore:
            var keys = Set(defaults.stringArray(forKey: UpdateSettings.ignoredKeysKey) ?? [])
            // Both forms, matching the app: un-ignoring must also clear a legacy
            // bundle-id entry, or the app would still consider it ignored.
            let removed = keys.remove(key) != nil || keys.remove(legacy) != nil
            guard removed else { return .failure("was not ignored") }
            defaults.set(Array(keys).sorted(), forKey: UpdateSettings.ignoredKeysKey)
            return .success("no longer ignored")

        case .skip:
            // `hasUpdate`, not `remote != nil`: an app that is already current
            // still reports a remote version, and keying on that recorded a skip
            // for the version the user is happily running — which would then
            // silently hide the *next* real update's row until it changed again.
            guard result.hasUpdate, let version = result.remote?.displayVersion else {
                return .failure("no update offered, so there is no version to skip")
            }
            var skipped = defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey)
                as? [String: String] ?? [:]
            guard skipped[key] != version else { return .failure("\(version) already skipped") }
            // Written under the per-path key only, like the app's `skipVersion`.
            skipped[key] = version
            defaults.set(skipped, forKey: UpdateSettings.skippedVersionsKey)
            return .success("skipping \(version)")

        case .unskip:
            var skipped = defaults.dictionary(forKey: UpdateSettings.skippedVersionsKey)
                as? [String: String] ?? [:]
            let had = skipped.removeValue(forKey: key) ?? skipped.removeValue(forKey: legacy)
            guard let had else { return .failure("no skipped version") }
            defaults.set(skipped, forKey: UpdateSettings.skippedVersionsKey)
            return .success("no longer skipping \(had)")
        }
    }

    // MARK: - Output

    static func report(
        _ action: Action, changed: [(String, String)], refused: [(String, String)], json: Bool
    ) {
        if json {
            NDJSON.begin(action.rawValue)
            for (name, note) in changed {
                NDJSON.emit(["app": name, "changed": true, "detail": note])
            }
            for (name, why) in refused {
                NDJSON.emit(["app": name, "changed": false, "detail": why])
            }
            return
        }
        for (name, note) in changed { print("  \(name)  \(note)") }
        for (name, why) in refused { print("  \(name)  —  \(why)") }
        if !changed.isEmpty {
            print("\nThe menu-bar app picks this up immediately; no restart needed.")
        }
    }
}
