import Foundation

/// The last value each recipe's service assigned to its
/// `RequestBody.EchoedField`, kept across checks, restarts, and the two
/// processes that check.
///
/// Exists for Omaha's `cohort` (#1621): sent back, it keeps every query in the
/// cohort the server last put us in, so the check that offers an update and the
/// pre-install re-check that confirms it are answered from the same rollout
/// group.
///
/// A file rather than memory so the cohort survives a restart, and one file for
/// the menu bar and `duo` so the two are one client to the service, not two
/// rolling separately — each process makes its own offers and re-checks them
/// itself. So this re-reads the file on every `value(for:)` rather than holding
/// a copy, and writes it through on every change. Both are cheap: one entry per
/// recipe that declares a field — one today — and the value changes only when
/// the server moves us.
///
/// One race is left, by choice: while the stored value is empty or outdated,
/// two probes of the same recipe in flight at once (the menu bar's round and a
/// `duo check`) are each rolled, and the later reply wins the file. If the
/// earlier one made an offer, its re-check is then asked as the other group.
/// It needs a stale moment and a sub-second overlap, and ends in the refusal
/// #1621 already words, not in a wrong install.
///
/// Keyed by `recipeID`, not by install: the cohort belongs to DuoUpdater as a
/// client of that service, and every copy of the app is asked about the same way.
///
/// A cohort names a rollout group, not a machine (Chromium's protocol document:
/// "A machine-readable string identifying the release cohort (channel) that the
/// app belongs to"), and it is only ever sent back to the service that assigned
/// it. A field holding anything that identifies a machine does not belong here.
public actor EchoedFieldStore {

    /// The instance the app and CLI share. Nothing defaults to it: a source
    /// built without a store sends the empty value and records nothing, so a
    /// test that constructs one directly never writes the real file. Only
    /// `SourceStack.make` callers wire it in.
    public static let shared = EchoedFieldStore()

    struct Entry: Codable, Sendable, Equatable {
        var value: String
        /// Never read; there so a human looking at the file can tell when the
        /// service last moved us.
        var assignedAt: Date
    }

    private let fileURL: URL

    /// - Parameter fileURL: defaults to
    ///   `<DuoStateDirectory.base>/com.duoupdater.app/echoed-request-fields.json`,
    ///   so a `duo verify` sweep pointed elsewhere by `DUO_STATE_DIR` keeps its
    ///   own cohorts out of the app's.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    static func defaultFileURL() -> URL {
        DuoStateDirectory.base
            .appendingPathComponent("com.duoupdater.app", isDirectory: true)
            .appendingPathComponent("echoed-request-fields.json")
    }

    /// What the service last assigned for this recipe, read from disk now.
    public func value(for recipeID: String) -> String? {
        Self.load(from: fileURL)[recipeID]?.value
    }

    /// Record what a reply assigned. An unchanged value writes nothing; an empty
    /// one removes the entry, which sends the empty value next time either way.
    public func record(_ value: String, for recipeID: String) {
        var entries = Self.load(from: fileURL)
        if value.isEmpty {
            guard entries.removeValue(forKey: recipeID) != nil else { return }
        } else {
            guard entries[recipeID]?.value != value else { return }
            entries[recipeID] = Entry(value: value, assignedAt: Date())
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Not fatal: the next request is then asked as a fresh client, which
            // is what every request was before this store existed.
            Log.source.error(
                "echoed-request-fields: could not write \(self.fileURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A corrupt or hand-edited file decodes to nothing: the next request is
    /// asked as a fresh client and the reply writes a good file back.
    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }
}
