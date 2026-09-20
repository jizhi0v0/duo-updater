import Foundation

/// A snapshot of an input method's **user data** — the dictionary it learned, its
/// settings, its account state — taken beside the bundle rollback point that
/// `BackupStore` keeps, and restorable with it.
///
/// Why this exists at all, when `InPlaceSwap.rotateContents` provably touches
/// nothing outside `<App>.app/Contents`: the one-click for WeType shipped in
/// 0.3.25 and was withdrawn the same day because a user's input-method settings
/// were gone afterwards, and the evidence never convicted a specific step. What
/// *is* certain is where the loss would land — none of it lives in the bundle:
///
///     ~/Library/Application Support/WeType/userDict      the learned dictionary
///     ~/Library/Application Support/WeType/mmkv          settings and state
///     ~/Library/Preferences/com.tencent.inputmethod.wetype.plist
///
/// and that after a bundle swap the app itself gets to decide what to do with
/// them on next launch — a downgrade, a migration, a first-run path that thinks
/// it is a fresh install. That is the app's code running on the user's data, and
/// no gate of ours can stand in front of it. So this does the one thing that
/// survives being wrong about the cause: takes a copy first, and can put it back.
///
/// **It rides on the bundle rollback point, including when there isn't one.**
/// Taken from `InstallCoordinator.backUp`, so it happens exactly when a bundle
/// backup happens: it is skipped for an app whose bundle could not be copied, and
/// skipped entirely when the user has turned rollback points off. That is
/// deliberate — writing a copy of someone's data to disk after they asked for no
/// backups would be the wrong way to be careful — but it does mean "there is
/// always something to go back to" is true only while backups are on.
///
/// **The copy is close to free**, which is what makes "always, before every
/// input-method update" affordable: `ditto` clones on APFS, so the 578 MB
/// `DoubaoIme` support directory snapshots in 0.096 s (measured; `cp -Rc`, which
/// asks for `clonefile(2)` explicitly, takes the same 0.09 s — there was nothing
/// to win by reaching past `ditto`, which is also what every other copy in this
/// module's neighbourhood uses and the one that gets xattrs and ACLs right).
/// A consequence worth knowing before anyone reads a `du`: the snapshot *reports*
/// its full size while sharing nearly all of its blocks with the live data, and
/// only starts costing real space as the two diverge.
public enum InputMethodDataBackup {

    /// Test seam: when bound, discovery reads this instead of the real home.
    ///
    /// Task-local rather than a global, for the reason `BackupStore.rootOverride`
    /// spells out — Swift Testing runs suites in parallel, so a plain global would
    /// be visible to whatever else happened to be reading it.
    ///
    /// The trade that comes with it: task locals do not reach a `Task.detached`
    /// or a Dispatch thread. Every read of `home` today is on the calling task —
    /// `InstallCoordinator.backUp` awaits `save` directly, and the `offCooperativePool`
    /// hops in this file only exchange and delete — so the seam reaches `save` and
    /// `restore` whether a test calls them or drives `backUp`. A read of `home`
    /// moved into a hop would silently use the real home instead;
    /// `BackupStore.restore` reads its manifest before its hop for the same reason.
    @TaskLocal public static var homeOverride: URL?

    private static var home: URL {
        homeOverride ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Subdirectory of a `BackupStore` key directory. Written after
    /// `BackupStore.save` has swapped that directory into place, because save
    /// builds the directory in staging and replaces it wholesale — anything put
    /// there first would be thrown away with the copy it superseded.
    ///
    /// Living inside the key directory is what gives this retention, pruning and
    /// removal for free: it is the same generation as the bundle it was taken
    /// with, and it goes when that goes.
    static let directoryName = "UserData"

    /// The name of the directory this snapshot is built in before it is swapped
    /// into place. Derived from `BackupStore.stagingPrefix` rather than spelled
    /// out, because that prefix is what `BackupStore.sweepStagingLeftovers`
    /// reclaims — see the comment in `save`, and
    /// `aStrandedUserDataSnapshotIsReclaimedByTheNextBackup`, which pins the two
    /// against each other.
    static func stagingName(key: String) -> String {
        "\(BackupStore.stagingPrefix(key: key))-userdata-\(UUID().uuidString)"
    }

    /// One captured location: where it came from, and what it is called in the
    /// store. Stored names are flat and sanitized, so a snapshot directory is
    /// browsable and nothing can escape it via `..` or a nested path.
    public struct Location: Sendable, Equatable {
        public let original: URL
        public let storedName: String
    }

    /// Sidecar recording exactly what was captured, so a restore puts each item
    /// back where it came from rather than re-deriving paths from a heuristic
    /// that may have changed by then.
    private struct Manifest: Codable {
        struct Entry: Codable {
            let originalPath: String
            let storedName: String
        }
        let savedAt: Date
        let entries: [Entry]
    }

    // MARK: - Discovery

    /// The user-data locations belonging to the input method whose bundle is
    /// named `bundleName` (the `.app` filename without its extension) with bundle
    /// id `bundleID`.
    ///
    /// A heuristic, and deliberately a *logged* one — `save` records every path it
    /// captured, so a location this misses is visible in the record instead of
    /// being discovered by its absence after a rollback. It is built from the two
    /// naming conventions both input methods on record actually follow:
    ///
    ///   * `Application Support` is keyed by the **bundle name**: `WeType`,
    ///     `DoubaoIme`. Not by bundle id, for either of them.
    ///   * preferences are keyed by bundle id *or* by a sibling id that merely
    ///     contains the bundle name. DoubaoIme has three
    ///     (`com.bytedance.inputmethod.doubaoime`, `.settings`, `.installer`) and
    ///     a bundle-id prefix finds them all; WeType's settings pane writes to
    ///     `com.tencent.WeTypeSettings`, which shares no prefix with
    ///     `com.tencent.inputmethod.wetype` and is only reachable by name.
    ///
    /// Both rules are needed — either alone misses real settings on one of the two
    /// apps. Sandbox containers are included for whatever comes next; neither of
    /// these two has one.
    ///
    /// SogouInput is the app that showed the bundle name is not always the name on
    /// disk, so a third input is `declaredDataNames` — see there for what it is
    /// for and why it is declared rather than guessed. Every name in play, the
    /// bundle's own included, drives BOTH rules.
    public static func locations(bundleName: String, bundleID: String?) -> [Location] {
        let fm = FileManager.default
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var found: [Location] = []

        func add(_ url: URL) {
            guard fm.fileExists(atPath: url.path) else { return }
            let name = storedName(for: url)
            guard !found.contains(where: { $0.storedName == name }) else { return }
            found.append(Location(original: url, storedName: name))
        }

        let names = [bundleName] + (bundleID.flatMap { declaredDataNames[$0] } ?? [])
        for name in names {
            add(library.appendingPathComponent("Application Support/\(name)", isDirectory: true))
        }
        if let bundleID {
            add(library.appendingPathComponent("Containers/\(bundleID)", isDirectory: true))
        }

        let prefs = library.appendingPathComponent("Preferences", isDirectory: true)
        let entries = (try? fm.contentsOfDirectory(atPath: prefs.path)) ?? []
        for entry in entries where entry.hasSuffix(".plist") {
            let stem = String(entry.dropLast(".plist".count))
            let matchesID = bundleID.map { stem == $0 || stem.hasPrefix($0 + ".") } ?? false
            let matchesName = names.contains { stem.localizedCaseInsensitiveContains($0) }
            guard matchesID || matchesName else { continue }
            add(prefs.appendingPathComponent(entry))
        }
        return found
    }

    /// Extra names an input method's user data is filed under, for an app where
    /// the bundle name is not that name. Keyed by bundle id, and declared here
    /// rather than derived, for the same reason the vendor rotation names in
    /// `InPlaceSwap` are: a rule wide enough to *infer* these would take other
    /// apps' data with it.
    ///
    /// SogouInput (measured 2026-09-20, the machine this was written on) is why it
    /// exists. Its bundle is `SogouInput.app`, but nothing on disk is called that:
    ///
    ///     ~/Library/Application Support/Sogou/{InputMethod,PicFaceTool,ResHub,SkinShop}
    ///     ~/Library/Preferences/SogouServices.plist
    ///     ~/Library/Preferences/com.sogou.{SGInputStatPanel,SogouInstaller,
    ///                                      SogouPreference,SogouTaskManager}.plist
    ///     ~/Library/Preferences/com.sogou.inputmethod.sogou.plist
    ///
    /// That is SEVEN locations as this module counts them — a location is what
    /// gets captured, and the support directory is captured whole, so its four
    /// children above are one, not four. Of the seven, the rules above found
    /// exactly ONE: the last plist, by bundle id.
    /// `Application Support/SogouInput` does not exist, so the support rule
    /// captured nothing at all, and `com.sogou.SogouPreference` is the settings
    /// pane: the same shape as WeType's `com.tencent.WeTypeSettings`, which the
    /// name rule was added for and which the name `SogouInput` cannot reach.
    /// Declaring `Sogou` reaches all seven, the 17 MB learned dictionary included.
    ///
    /// The inference that was rejected: take the vendor token out of the bundle id
    /// (`com.sogou.…` → `Sogou`). It works here and misfires next door — the same
    /// rule reads `com.tencent.inputmethod.wetype` as `Tencent` and would snapshot
    /// `~/Library/Application Support/Tencent`, which WeType shares with every
    /// other Tencent app on the Mac.
    ///
    /// A name here widens BOTH rules, so it must be specific to this app's data.
    /// `Sogou` over `Preferences` is a substring match, and it is meant to be: the
    /// helpers that carry the user's state are named for the vendor, not for the
    /// bundle.
    static let declaredDataNames: [String: [String]] = [
        "com.sogou.inputmethod.sogou": ["Sogou"],
    ]

    /// A flat, filesystem-safe name for one captured location. Keeps the leaf
    /// readable and prefixes the library subdirectory it came from, so
    /// `Application Support/WeType` and a hypothetical `Containers/WeType` cannot
    /// collide in the same snapshot.
    private static func storedName(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let raw = "\(parent)-\(url.lastPathComponent)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(raw.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        })
    }

    // MARK: - Save

    /// Snapshot the input method's user data into the backup directory for `key`.
    ///
    /// Best-effort by contract, like the bundle backup it sits beside: a failure
    /// here must never block an update the user asked for. It is reported rather
    /// than swallowed — the caller logs what was captured — because a snapshot
    /// nobody knows is missing is worse than no snapshot at all.
    ///
    /// Returns the locations actually stored.
    @discardableResult
    public static func save(bundleName: String, bundleID: String?, key: String) async -> [Location] {
        let fm = FileManager.default
        let dir = BackupStore.root
            .appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        // Only ever written beside a bundle backup that already landed. Without
        // that directory there is no generation to attach this to, and a snapshot
        // in a directory `BackupStore` does not know about would never be pruned.
        guard fm.fileExists(atPath: BackupStore.root.appendingPathComponent(key).path) else {
            Log.install.error(
                "user data: no backup directory for \(key, privacy: .public) — nothing to attach a snapshot to")
            return []
        }
        let sources = locations(bundleName: bundleName, bundleID: bundleID)
        guard !sources.isEmpty else { return [] }

        // Built in a hidden sibling and swapped in, for the same reason
        // `BackupStore.save` does: a half-written snapshot must not replace a
        // complete one from the previous update.
        //
        // The name has to START `.staging-<key>`, and that is load-bearing rather
        // than cosmetic: `BackupStore.sweepStagingLeftovers` is what reclaims a
        // staging directory whose cleanup never ran, and it selects on exactly
        // that prefix. A name of our own (this read `.userdata-staging-<key>-…`
        // before) matches nothing it looks for, so a snapshot interrupted between
        // `createDirectory` and the swap below would be stranded PERMANENTLY —
        // and invisibly, because every scan of the store's root passes
        // `.skipsHiddenFiles`, so retention would never prune it and
        // `backupSize` would never count it. That is a copy of the user's whole
        // input-method data directory, one per interruption, that nothing on
        // screen could account for. Keep the prefix; put the distinguishing part
        // after the key.
        //
        // Safe against the sweep deleting one of ours mid-write: the sweep runs
        // at the top of `BackupStore.save`, and `InstallCoordinator.backUp` only
        // calls us once that has returned.
        let staging = BackupStore.root.appendingPathComponent(
            stagingName(key: key), isDirectory: true)
        try? fm.removeItem(at: staging)
        guard (try? fm.createDirectory(at: staging, withIntermediateDirectories: true)) != nil else {
            Log.install.error(
                "user data: could not create a staging directory for \(key, privacy: .public)")
            return []
        }
        // Whatever the snapshot did not swap into place is still in `staging` — up
        // to a copy of the whole data directory — so it is removed on Dispatch.
        defer { await removeItemOffCooperativePool(at: staging) }
        return await snapshot(sources, key: key, stagingIn: staging, into: dir)
    }

    /// `save` from the point its staging directory exists: copy, write the
    /// manifest, swap into `dir`. Returns the locations stored.
    private static func snapshot(
        _ sources: [Location], key: String, stagingIn staging: URL, into dir: URL
    ) async -> [Location] {
        var stored: [Location] = []
        for source in sources {
            let dest = staging.appendingPathComponent(source.storedName)
            guard await copyTree(from: source.original, to: dest) else {
                Log.install.error(
                    "user data: could not copy \(source.original.lastPathComponent, privacy: .public) — this snapshot will not include it")
                continue
            }
            stored.append(source)
        }
        guard !stored.isEmpty else { return [] }

        let manifest = Manifest(
            savedAt: Date(),
            entries: stored.map {
                Manifest.Entry(originalPath: $0.original.path, storedName: $0.storedName)
            })
        guard let data = try? JSONEncoder().encode(manifest),
              (try? data.write(to: staging.appendingPathComponent("userdata.json"), options: .atomic)) != nil
        else {
            Log.install.error(
                "user data: snapshot for \(key, privacy: .public) is complete but its manifest would not write — discarding it, since restore reads the manifest")
            return []
        }

        // `replaceItemAt` deletes the snapshot it displaces — a copy of the user's
        // whole input-method data directory — so the exchange goes to Dispatch.
        let failure: String? = await offCooperativePool(qos: .userInitiated) {
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: dir.path) {
                    _ = try fm.replaceItemAt(dir, withItemAt: staging)
                } else {
                    try fm.moveItem(at: staging, to: dir)
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        if let failure {
            Log.install.error(
                "user data: snapshot for \(key, privacy: .public) would not swap into place — \(failure, privacy: .public)")
            return []
        }
        return stored
    }

    // MARK: - Restore

    /// Put the snapshot stored for `key` back over the live locations it came
    /// from. Returns the locations restored; throws only when the caller asked for
    /// a restore and there is no snapshot to give.
    ///
    /// Each item is exchanged atomically, and the snapshot is left in the store —
    /// a rollback must not consume the only copy of what it rolled back to.
    @discardableResult
    public static func restore(forKey key: String) async throws -> [Location] {
        let fm = FileManager.default
        let dir = BackupStore.root
            .appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("userdata.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { throw BackupStore.BackupError.noBackup(key) }

        var restored: [Location] = []
        for entry in manifest.entries {
            let source = dir.appendingPathComponent(entry.storedName)
            let target = URL(fileURLWithPath: entry.originalPath)
            guard fm.fileExists(atPath: source.path) else { continue }
            // Copy out of the store first: the exchange consumes what it is handed,
            // and what it is handed must not be the stored snapshot itself. The key
            // is in the name so a leftover can be traced to its app.
            let scratch = fm.temporaryDirectory.appendingPathComponent(
                "DuoUpdater-userdata-\(key)-\(UUID().uuidString)", isDirectory: true)
            guard (try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil
            else { continue }
            // A copy that did not get exchanged is still in `scratch`, so it is
            // removed on Dispatch.
            defer { await removeItemOffCooperativePool(at: scratch) }
            if await restoreEntry(entry, from: source, to: target, stagingIn: scratch) {
                restored.append(Location(original: target, storedName: entry.storedName))
            }
        }
        return restored
    }

    /// One manifest entry of `restore`: stage it out of the store into `scratch`,
    /// then exchange it over `target`. True if it landed.
    private static func restoreEntry(
        _ entry: Manifest.Entry, from source: URL, to target: URL, stagingIn scratch: URL
    ) async -> Bool {
        let staged = scratch.appendingPathComponent(entry.storedName)
        guard await copyTree(from: source, to: staged) else {
            Log.install.error(
                "user data: could not stage \(entry.storedName, privacy: .public) out of the store")
            return false
        }
        // Off the cooperative pool: `replaceItemAt` deletes the live data it
        // displaces, which can be a large directory.
        let failure: String? = await offCooperativePool(qos: .userInitiated) {
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: target.path) {
                    _ = try fm.replaceItemAt(target, withItemAt: staged)
                } else {
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: staged, to: target)
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        if let failure {
            Log.install.error(
                "user data: could not restore \(entry.storedName, privacy: .public) — \(failure, privacy: .public)")
            return false
        }
        return true
    }

    // MARK: - Copying

    /// Copy `source` to `dest` with `ditto` — the same tool the bundle backup
    /// uses, for the same reasons (symlinks, xattrs and ACLs survive), and on APFS
    /// it clones rather than duplicating blocks. On a filesystem that cannot clone
    /// this is a real copy and a real cost; it still happens, because a snapshot
    /// that silently did not exist is the failure this module was written to
    /// prevent. Not killed on cancellation, for the same reason.
    private static func copyTree(from source: URL, to dest: URL) async -> Bool {
        guard let outcome = try? await ChildProcess.run(
            "/usr/bin/ditto", [source.path, dest.path],
            standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion)
        else { return false }
        return outcome.succeeded
    }
}
