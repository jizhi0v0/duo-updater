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
    ///
    /// 2: `list`, `check` and `install` carry the menu-bar app's command-line
    /// tool rows after the apps (`CLIToolRows`). A tool row has `tool` and no
    /// `bundleID` (`list`, `check`) or `app` (`install`); its `name` and `path`
    /// are a tool's, so a reader that took every row for an app would act on
    /// something that is not one.
    static let schemaVersion = 2

    /// Print the header line. Call once, before any rows.
    static func begin(_ command: String, print: (String) -> Void = { Swift.print($0) }) {
        emit(["schemaVersion": schemaVersion, "command": command] as [String: Any], print: print)
    }

    static func row(_ value: some Encodable, print: (String) -> Void = { Swift.print($0) }) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // ISO-8601 throughout, matching how the Core stores persist dates. The
        // default is a bare epoch double, which is both ambiguous to read and
        // inconsistent with every other timestamp this project emits.
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        print(String(decoding: data, as: UTF8.self))
    }

    static func emit(_ object: [String: Any], print: (String) -> Void = { Swift.print($0) }) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]) else { return }
        print(String(decoding: data, as: UTF8.self))
    }
}
