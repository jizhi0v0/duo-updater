import Foundation

/// Windscribe (`com.windscribe.client`) — the first binding that has to DECODE
/// its preference rather than read it.
///
/// Every other resolver here reads a plist key straight (`Fork`'s
/// `sparkleIncludePrereleases`, `OrbStack`'s `updates_optinChannel`). Windscribe
/// serialises its whole engine-settings struct into one `QDataStream`, runs it
/// through `SimpleCrypt`, and stores the result as a single `engineSettings`
/// string. So the choice the user made in Preferences ▸ General ▸ Update Channel
/// is in there, and nothing else on the machine says it.
///
/// **That this is readable at all comes from the app being open source**, not
/// from breaking anything: the key is a plain constant in Windscribe's own
/// repository and `SimpleCrypt` is a published BSD snippet vendored into it.
/// The audit records an earlier verdict of "encrypted, so this is blocked" being
/// wrong on both of its halves.
///
/// | source | what it gives |
/// |---|---|
/// | `global_consts.h` | `SIMPLE_CRYPT_KEY = 0x4572A4ACF31A31BA` |
/// | `utils/simplecrypt.cpp` | Andre Somers' SimpleCrypt, version byte 3 |
/// | `types/enginesettings.cpp` | magic / version / language / updateChannel |
///
/// ## Why the parse is shallow enough to trust
///
/// `updateChannel` is the FOURTH field in the stream, and every one of
/// `loadFromSettings`'s version-gated branches (`if (version < 12)`, `if
/// (version >= 2)`, …) sits AFTER it. A vendor bump to
/// `versionForSerialization_` therefore adds or removes fields further down and
/// cannot move this one — which is the opposite of what an earlier version of
/// this analysis assumed, and the reason it wrongly called this route fragile.
///
/// Nor is a misread silent: `magic` must equal `0x7745C2AE` and SimpleCrypt
/// carries a `qChecksum` over the payload. Both are checked, and either failing
/// yields nil.
///
/// ## What it measures — and what it does not
///
/// This preference is **which track the user asked to follow**, which is exactly
/// the question the channel gate asks. It is NOT "which track this copy was
/// built from": those genuinely differ, and were observed differing on a real
/// installation — a Beta build with the preference on Guinea Pig. The build's
/// own track is visible too (a prerelease binary carries `WS_ASSERT`'s
/// `"Assertion failed! ("` and ~194 embedded `__FILE__` paths that a stable one
/// has none of), but that is a corroborating signal for provenance and must not
/// stand in for the preference. See the audit.
///
/// ## The ladder, and why `.stable` is answered as nil
///
/// Windscribe's tracks are a maturity ladder, not parallel trains: the vendor's
/// own page says a fix "will be released in the Guinea Pig channel first", and
/// the feed agrees — a cycle runs guinea pig → beta → release with the build
/// number climbing across all three. A user on level N is served the newest
/// build from tracks 0…N, which is what the recipes express.
///
/// The preference DEFAULTS to Release and nothing but the Settings pane ever
/// writes it — installing a beta dmg does not touch it — so "preference says
/// release" does not mean "this is a stable build". Answering `.stable` there
/// would be authoritative about a copy the preference has nothing to say about;
/// nil lets `ReleaseChannel.detect()` keep the last word, the same shape
/// `CotEditorChannel` uses and for the same reason.
enum WindscribeChannel {
    static let bundleID = "com.windscribe.client"

    /// QSettings is scoped `Windscribe` / `Windscribe2` (`WS_SETTINGS_ORG` /
    /// `WS_SETTINGS_APP`), which on macOS lands here. Not sandboxed, so unlike
    /// `CotEditorChannel` this is the real path and not a container.
    static var preferencesFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Preferences/com.windscribe.Windscribe2.plist", isDirectory: false)
    }

    static var preferencesDirectoryURL: URL {
        preferencesFileURL.deletingLastPathComponent()
    }

    /// The vendor's `UPDATE_CHANNEL` enum (`types/enums.h`), by its own numbering.
    /// `internal` exists in the enum and is not reachable from the UI; it maps to
    /// nil rather than to a channel we have no recipe for.
    static func channel(forRawValue raw: Int) -> ReleaseChannel? {
        switch raw {
        case 1: return .beta
        case 2: return .guineaPig
        default: return nil   // 0 = release (see the class doc), 3 = internal
        }
    }

    /// Map the decoded preference to a resolution. Pure and tested.
    static func resolve(updateChannel raw: Int?) -> ResolvedChannel? {
        guard let raw, let channel = channel(forRawValue: raw) else { return nil }
        return ResolvedChannel(channel: channel)
    }

    static func resolveCurrent() -> ResolvedChannel? {
        resolve(updateChannel: readUpdateChannel())
    }

    static func readUpdateChannel() -> Int? {
        decodeUpdateChannel(at: preferencesFileURL)
    }

    /// Split out so the decoding is testable against a plist written to a temp
    /// directory — the path itself is the part only a live read can confirm.
    static func decodeUpdateChannel(at url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any],
              let stored = plist["engineSettings"] as? String
        else { return nil }
        return updateChannel(inEncodedSettings: stored)
    }

    /// base64 → SimpleCrypt → the first four fields of the stream.
    static func updateChannel(inEncodedSettings stored: String) -> Int? {
        guard let cipher = Data(base64Encoded: stored),
              let plain = simpleCryptDecrypt(cipher)
        else { return nil }
        return updateChannel(inEngineSettings: plain)
    }

    // MARK: - SimpleCrypt

    static let key: UInt64 = 0x4572_A4AC_F31A_31BA

    /// `SimpleCrypt::splitKey` — byte i is the key's i-th least significant byte.
    static let keyParts: [UInt8] = (0..<8).map { UInt8((key >> (8 * UInt64($0))) & 0xFF) }

    /// Qt 6's `qChecksum(Qt::ChecksumIso3309)`: CRC-16/CCITT reflected, init
    /// 0xFFFF, final complement — and NO trailing byte swap.
    ///
    /// The swap is Qt 4's behaviour, and writing it is how the first version of
    /// this got it wrong: against a real blob the computed value came out the
    /// byte-reverse of the stored one (0xb863 against 0x63b8). A round-trip test
    /// cannot catch that, because the encoder would share the mistake — which is
    /// why `qChecksumMatchesTheStandardVector` pins this against CRC-16/X-25's
    /// published check value instead.
    static func qChecksum(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1
            }
        }
        return ~crc
    }

    /// Reverse `SimpleCrypt::encryptToByteArray`. Returns nil unless the version
    /// byte is 3, the checksum (when the flags claim one) matches, and any
    /// compression unpacks.
    static func simpleCryptDecrypt(_ cipher: Data) -> Data? {
        let bytes = [UInt8](cipher)
        guard bytes.count >= 3, bytes[0] == 3 else { return nil }
        let flags = bytes[1]

        // XOR chain: each byte is unmasked with the key byte and the PREVIOUS
        // ciphertext byte, so the previous byte has to be kept before it is
        // overwritten.
        var out = Array(bytes[2...])
        var last: UInt8 = 0
        for i in out.indices {
            let current = out[i]
            out[i] = current ^ last ^ keyParts[i % 8]
            last = current
        }
        guard !out.isEmpty else { return nil }
        out.removeFirst()   // the random lead byte

        var payload = Data(out)
        if flags & 0x02 != 0 {          // CryptoFlagChecksum
            guard payload.count >= 2 else { return nil }
            let stored = UInt16(payload[payload.startIndex]) << 8
                | UInt16(payload[payload.index(after: payload.startIndex)])
            payload = payload.dropFirst(2)
            guard qChecksum(payload) == stored else { return nil }
        } else if flags & 0x04 != 0 {   // CryptoFlagHash — not emitted by this app
            return nil
        }
        if flags & 0x01 != 0 {          // CryptoFlagCompression — Qt's qCompress
            guard payload.count > 4 else { return nil }
            let expected = Int(be32(payload, at: payload.startIndex))
            return GzipDecode.decompressZlib(Data(payload.dropFirst(4)), hint: expected)
        }
        return payload
    }

    // MARK: - the QDataStream prefix

    static let magic: UInt32 = 0x7745_C2AE

    /// Read `magic / version / language / updateChannel` and stop. Everything
    /// after `updateChannel` is settings this has no business decoding — proxy
    /// hosts, custom config paths, DNS — so it is never touched.
    ///
    /// QDataStream is big-endian by default and a `QString` is a 4-byte byte
    /// count followed by UTF-16 (`0xFFFFFFFF` marking a null string).
    static func updateChannel(inEngineSettings plain: Data) -> Int? {
        var i = plain.startIndex
        func take(_ n: Int) -> Data? {
            guard plain.distance(from: i, to: plain.endIndex) >= n else { return nil }
            defer { i = plain.index(i, offsetBy: n) }
            return plain[i..<plain.index(i, offsetBy: n)]
        }
        guard let magicField = take(4), be32(magicField, at: magicField.startIndex) == magic,
              take(4) != nil                                   // stream version
        else { return nil }
        guard let lengthField = take(4) else { return nil }
        let length = be32(lengthField, at: lengthField.startIndex)
        if length != 0xFFFF_FFFF {                             // null QString has no body
            guard length <= UInt32(Int32.max), take(Int(length)) != nil else { return nil }
        }
        guard let channelField = take(4) else { return nil }
        return Int(be32(channelField, at: channelField.startIndex))
    }

    private static func be32(_ data: Data, at index: Data.Index) -> UInt32 {
        var value: UInt32 = 0
        var idx = index
        for _ in 0..<4 {
            value = value << 8 | UInt32(data[idx])
            idx = data.index(after: idx)
        }
        return value
    }
}
