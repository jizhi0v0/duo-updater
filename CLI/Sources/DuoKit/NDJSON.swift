import Foundation

/// The `--json` output format: one JSON object per line, opened by a header
/// naming the schema.
///
/// Newline-delimited rather than one array so a slow command streams — `duo
/// install --all --json | jq` should show each app as it lands, not everything
/// twenty minutes later. The header exists so a consumer can tell which shape it
/// is reading without guessing from the keys, and so a future change to a row's
/// fields is detectable rather than silent.
enum NDJSON {

    /// Bumped when a row's shape changes in a way a consumer could not absorb —
    /// a removed or repurposed key. Adding a new key is not a bump: readers are
    /// expected to ignore what they don't know.
    static let schemaVersion = 1

    /// Print the header line. Call once, before any rows.
    static func begin(_ command: String) {
        emit(["schemaVersion": schemaVersion, "command": command] as [String: Any])
    }

    static func row(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        print(String(decoding: data, as: UTF8.self))
    }

    static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]) else { return }
        print(String(decoding: data, as: UTF8.self))
    }
}
