import Foundation

enum AthasChannel {
    static let bundleID = "com.code.athas"

    static func resolve(
        bundleStrings: [String: String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ResolvedChannel {
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let legacy = support.appendingPathComponent("com.code.athas/settings.json")
        let native = support.appendingPathComponent("dev.athas.app/settings.json")
        // GPUI starts at 0.19. On first launch it reads the Tauri profile if its
        // own file is absent. A rolled-back Tauri copy only reads its own profile.
        let core = bundleStrings["CFBundleShortVersionString"]?.split(separator: "-", maxSplits: 1).first
        // 0.16.2 introduced the channel picker and request header. An older
        // Tauri build does not honor a beta choice left by a newer installation.
        if let core, VersionComparator.isNewer("0.16.2", than: String(core)) {
            return ResolvedChannel(channel: .stable)
        }
        let isTauri = core.map { VersionComparator.isNewer("0.19.0", than: String($0)) } ?? false
        let channel = isTauri ? read(legacy, allowsJSONC: false)
            : read(native, allowsJSONC: true) ?? read(legacy, allowsJSONC: true)
        return ResolvedChannel(channel: channel ?? .stable)
    }

    private static func read(_ url: URL, allowsJSONC: Bool) -> ReleaseChannel? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        // A readable GPUI file takes precedence even when its syntax or channel
        // key is invalid. Do not resurrect a beta opt-in from the old profile.
        let limit = 1024 * 1024
        guard let data = try? file.read(upToCount: limit + 1), data.count <= limit else { return .stable }
        guard String(data: data, encoding: .utf8) != nil else { return nil }
        return channel(in: data, allowsJSONC: allowsJSONC)
    }

    /// Tauri's store expects JSON. GPUI also strips comments and trailing commas
    /// before passing the document to serde_json. Foundation's JSON5 mode would
    /// accept settings that GPUI discards, such as an unquoted beta key.
    private static func channel(in data: Data, allowsJSONC: Bool) -> ReleaseChannel {
        var bytes = Array(data)
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if bytes.starts(with: bom) {
            guard allowsJSONC else { return .stable }
            bytes.removeFirst(bom.count)
        }

        let quote = UInt8(ascii: "\"")
        let space = UInt8(ascii: " ")
        let comma = UInt8(ascii: ",")
        var depth = 0
        var index = 0
        var previousToken: Int?
        var previousChannelKey: Range<Int>?
        let decoder = JSONDecoder()
        while index < bytes.count {
            let start = index
            let byte = bytes[index]
            index += 1
            switch byte {
            case space, UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                continue
            case quote:
                while index < bytes.count {
                    let character = bytes[index]
                    index += 1
                    if character == UInt8(ascii: "\\") {
                        index += 1
                    } else if character == quote {
                        break
                    }
                }
                guard index <= bytes.count, bytes[index - 1] == quote else { return .stable }
                if depth == 1, let previousToken, bytes[previousToken] == UInt8(ascii: "{") || bytes[previousToken] == comma,
                   (try? decoder.decode(String.self, from: Data(bytes[start..<index]))) == "updateChannel" {
                    // Foundation keeps the first duplicate key. serde_json's
                    // settings map keeps the last. Give earlier entries a key
                    // made of spaces without touching any values or offsets.
                    if let previousChannelKey {
                        for position in previousChannelKey { bytes[position] = space }
                    }
                    previousChannelKey = (start + 1)..<(index - 1)
                }
            case UInt8(ascii: "/") where index < bytes.count && bytes[index] == UInt8(ascii: "/"):
                guard allowsJSONC else { return .stable }
                while index < bytes.count && bytes[index] != UInt8(ascii: "\n") { index += 1 }
                for position in start..<index { bytes[position] = space }
                continue
            case UInt8(ascii: "/") where index < bytes.count && bytes[index] == UInt8(ascii: "*"):
                guard allowsJSONC else { return .stable }
                index += 1
                while index + 1 < bytes.count {
                    if bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/") { break }
                    index += 1
                }
                index = min(index + 2, bytes.count)
                for position in start..<index { bytes[position] = space }
                continue
            case comma:
                // Foundation tolerates a trailing comma on its own. Prevent
                // it from accepting the second comma after we strip the last.
                if let previousToken, bytes[previousToken] == comma { return .stable }
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                // serde_json's default recursion limit is 128.
                guard depth < 128 else { return .stable }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if let previousToken, bytes[previousToken] == comma {
                    guard allowsJSONC else { return .stable }
                    bytes[previousToken] = space
                }
            default:
                break
            }
            previousToken = start
        }

        // Foundation also auto-detects BOM-less UTF-16. A raw NUL in the
        // normalized UTF-8 document is invalid JSON in serde_json.
        guard !bytes.contains(0) else { return .stable }
        let settings = (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any]
        return settings?["updateChannel"] as? String == "beta" ? .beta : .stable
    }
}
