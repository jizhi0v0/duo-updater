import Testing
import Foundation
@testable import DuoUpdaterCore

/// Windscribe's channel binding — the one that decodes its preference.
///
/// The encoder below is a test-local mirror of `SimpleCrypt::encryptToByteArray`,
/// which makes most of these round trips. A round trip cannot prove agreement
/// with Qt, only self-consistency: an encoder and a decoder that share a mistake
/// agree perfectly. That hole is real and it bit once — `qChecksum` was first
/// written to Qt 4's behaviour, with a trailing byte swap Qt dropped in 5.x, and
/// every round trip passed. So the checksum is pinned separately against a
/// PUBLISHED vector, and that test is the one holding the rest up.
struct WindscribeChannelTests {

    // MARK: - the independent anchor

    /// Qt 6's `qChecksum(Qt::ChecksumIso3309)` is CRC-16/X-25, whose published
    /// check value over the ASCII digits "123456789" is 0x906E.
    ///
    /// Mutation: restore Qt 4's trailing byte swap. This returns 0x6E90 and the
    /// test goes red — while every round trip in this file still passes, which
    /// is exactly the point of having it.
    @Test func qChecksumMatchesTheStandardVector() {
        #expect(WindscribeChannel.qChecksum(Data("123456789".utf8)) == 0x906E)
        // The empty-input value of the same parameterisation, for the init and
        // final-complement halves that the vector above cannot isolate.
        #expect(WindscribeChannel.qChecksum(Data()) == 0x0000)
    }

    /// The key, split the way `SimpleCrypt::splitKey` splits it — byte i is the
    /// i-th least significant. Pinned because a big-endian split would still
    /// decrypt *something*, just not the vendor's bytes.
    ///
    /// Mutation: reverse `keyParts`.
    @Test func theKeyIsSplitLeastSignificantByteFirst() {
        #expect(WindscribeChannel.key == 0x4572_A4AC_F31A_31BA)
        #expect(WindscribeChannel.keyParts == [0xBA, 0x31, 0x1A, 0xF3, 0xAC, 0xA4, 0x72, 0x45])
    }

    // MARK: - the mapping

    /// Release and the UI-unreachable `internal` both answer nil, so
    /// `ReleaseChannel.detect()` keeps the last word for a copy the preference
    /// has nothing to add about — the preference DEFAULTS to release, including
    /// on a freshly installed beta build.
    ///
    /// Mutation: return `ResolvedChannel(channel: .stable)` for 0.
    @Test func onlyTheTwoPrereleaseTracksResolve() {
        #expect(WindscribeChannel.resolve(updateChannel: 0) == nil)
        #expect(WindscribeChannel.resolve(updateChannel: 1)?.channel == .beta)
        #expect(WindscribeChannel.resolve(updateChannel: 2)?.channel == .guineaPig)
        #expect(WindscribeChannel.resolve(updateChannel: 3) == nil)   // internal
        #expect(WindscribeChannel.resolve(updateChannel: nil) == nil)
        #expect(WindscribeChannel.resolve(updateChannel: 99) == nil)
        // No feed swap, no headers, no sparkle tags: the channel selects which
        // VendorProbe recipe answers and nothing else.
        let beta = WindscribeChannel.resolve(updateChannel: 1)
        #expect(beta?.feedOverride == nil)
        #expect(beta?.feedHTTPHeaders.isEmpty == true)
        #expect(beta?.sparkleChannelNames.isEmpty == true)
    }

    /// Registered everywhere a binding has to be, not just in the switch.
    ///
    /// Mutation: remove the `boundBundleIDs` entry, or the `allResolutions` one.
    @Test func theBindingIsRegistered() {
        #expect(ChannelBinding.hasResolver(bundleID: WindscribeChannel.bundleID))
        #expect(ChannelBinding.boundBundleIDs.contains(
            WindscribeChannel.bundleID.lowercased()))
        // Backed by VendorProbe recipes rather than by a swapped feed, which is
        // what keeps it OUT of `allResolutions` — the population
        // `ChannelProofRegistry` demands artifact proof from. Same choice
        // OrbStack, Alfred, Tailscale and CapCut made; `everyBindingIsEnumerated`
        // and `vendorProbeBackedBindingsAreNotEnumerated` pin both halves, and
        // both went red when this was first added to the two lists at once.
        #expect(ChannelBinding.vendorProbeBackedBindings.contains(
            WindscribeChannel.bundleID.lowercased()))
        #expect(!ChannelBinding.allResolutions.contains {
            $0.bundleID.lowercased() == WindscribeChannel.bundleID.lowercased()
        })
        // The two tracks it can produce, asserted through the pure resolver since
        // the enumeration above deliberately does not carry them.
        #expect((0...3).compactMap { WindscribeChannel.resolve(updateChannel: $0)?.channel }
            == [.beta, .guineaPig])
    }

    // MARK: - the stream prefix

    /// `updateChannel` is the fourth field, and the parse walks to it rather than
    /// indexing a fixed offset — the language string in front of it is variable
    /// length.
    ///
    /// Mutation: skip the QString length and assume a fixed prefix.
    @Test func theChannelIsFoundPastAVariableLengthLanguage() {
        for language in ["", "en", "zh_CN", "pt_BR"] {
            let plain = Self.engineSettings(language: language, channel: 2)
            #expect(WindscribeChannel.updateChannel(inEngineSettings: plain) == 2,
                    "language \(language.isEmpty ? "<empty>" : language)")
        }
        // A null QString is 0xFFFFFFFF with NO body, not a 4GB one.
        var nullLanguage = Data()
        nullLanguage.append(contentsOf: Self.be32(0x7745_C2AE))
        nullLanguage.append(contentsOf: Self.be32(13))
        nullLanguage.append(contentsOf: Self.be32(0xFFFF_FFFF))
        nullLanguage.append(contentsOf: Self.be32(1))
        #expect(WindscribeChannel.updateChannel(inEngineSettings: nullLanguage) == 1)
    }

    /// Every version of the stream the vendor still accepts parses, because each
    /// of `loadFromSettings`'s version-gated branches sits AFTER this field.
    ///
    /// Mutation: none available — this is the claim the design rests on, and it
    /// is asserted so that a future layout change that moves the field breaks a
    /// test rather than a user's channel.
    @Test func everyStreamVersionKeepsTheFieldInTheSamePlace() {
        for version in [UInt32(1), 2, 11, 12, 13] {
            let plain = Self.engineSettings(language: "en", channel: 1, version: version)
            #expect(WindscribeChannel.updateChannel(inEngineSettings: plain) == 1,
                    "stream version \(version)")
        }
    }

    /// A body that is not this struct is refused rather than read at an offset
    /// that happens to hold a small number.
    ///
    /// Mutation: drop the magic check.
    @Test func aForeignBodyIsRefused() {
        var wrongMagic = Self.engineSettings(language: "en", channel: 1)
        wrongMagic.replaceSubrange(
            wrongMagic.startIndex..<wrongMagic.index(wrongMagic.startIndex, offsetBy: 4),
            with: Self.be32(0xDEAD_BEEF))
        #expect(WindscribeChannel.updateChannel(inEngineSettings: wrongMagic) == nil)
        #expect(WindscribeChannel.updateChannel(inEngineSettings: Data()) == nil)
        // Truncated right before the channel field.
        let full = Self.engineSettings(language: "en", channel: 1)
        #expect(WindscribeChannel.updateChannel(
            inEngineSettings: full.prefix(full.count - 601)) == nil)
    }

    // MARK: - SimpleCrypt

    /// Round trip, uncompressed, over the whole enum.
    ///
    /// Mutation: chain the XOR on the PLAINTEXT byte instead of the ciphertext
    /// one (the direction that differs between encrypt and decrypt).
    @Test func everyChannelValueSurvivesTheCipher() throws {
        for raw in 0...3 {
            let cipher = Self.simpleCryptEncrypt(
                Self.engineSettings(language: "en", channel: UInt32(raw)))
            let plain = try #require(WindscribeChannel.simpleCryptDecrypt(cipher))
            #expect(WindscribeChannel.updateChannel(inEngineSettings: plain) == raw)
        }
    }

    /// The compressed path, on a blob produced by zlib rather than by anything in
    /// this file: a `qCompress` payload is a 4-byte big-endian original length
    /// followed by a zlib stream, and getting either half wrong yields nil.
    ///
    /// Fixture: `magic / 13 / "en" / 2` plus 600 zero bytes standing in for the
    /// rest of the struct, encrypted with a fixed lead byte so it is stable.
    ///
    /// Mutation: feed the zlib bytes to the inflater without stripping the
    /// 2-byte header, or forget the 4-byte length prefix.
    @Test func aCompressedBlobIsInflated() throws {
        let fixture = "AwNdkhrpReP9wKC61xkBK9gcJwGTOY17EKedmJGhJZnunyUUbMVq3Q=="
        let cipher = try #require(Data(base64Encoded: fixture))
        #expect(cipher[cipher.index(cipher.startIndex, offsetBy: 1)] == 0x03,
                "flags must claim compression AND checksum, or this tests the wrong path")
        let plain = try #require(WindscribeChannel.simpleCryptDecrypt(cipher))
        #expect(WindscribeChannel.updateChannel(inEngineSettings: plain) == 2)
    }

    /// The checksum is the reason a misread is loud. Every single-byte flip in a
    /// real-shaped blob has to be refused.
    ///
    /// Mutation: skip the checksum comparison.
    @Test func anyCorruptionIsRefused() {
        let cipher = Self.simpleCryptEncrypt(
            Self.engineSettings(language: "en", channel: 1, padding: 8))
        for offset in 2..<cipher.count {
            var damaged = cipher
            damaged[damaged.index(damaged.startIndex, offsetBy: offset)] ^= 0xFF
            #expect(WindscribeChannel.simpleCryptDecrypt(damaged) == nil,
                    "a flip at byte \(offset) went unnoticed")
        }
        // And the framing itself: only version byte 3 is this format.
        var wrongVersion = cipher
        wrongVersion[wrongVersion.startIndex] = 2
        #expect(WindscribeChannel.simpleCryptDecrypt(wrongVersion) == nil)
    }

    // MARK: - the plist

    /// End to end from a file, which is the shape `resolveCurrent` uses. The path
    /// itself is the part no unit test can pin — only a live read on a machine
    /// with Windscribe installed says whether it is right.
    ///
    /// Mutation: read a different key than `engineSettings`.
    @Test func decodesFromAPlistOnDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("windscribe-channel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("com.windscribe.Windscribe2.plist")

        let cipher = Self.simpleCryptEncrypt(Self.engineSettings(language: "en", channel: 2))
        let plist: [String: Any] = [
            "engineSettings": cipher.base64EncodedString(),
            // The neighbours the real file carries, so the lookup has to pick.
            "language": "en", "pfIsEnabled": false,
        ]
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: file)
        #expect(WindscribeChannel.decodeUpdateChannel(at: file) == 2)

        // A file with no such key, and a file that is not there at all.
        let bare = dir.appendingPathComponent("bare.plist")
        try PropertyListSerialization
            .data(fromPropertyList: ["language": "en"], format: .binary, options: 0)
            .write(to: bare)
        #expect(WindscribeChannel.decodeUpdateChannel(at: bare) == nil)
        #expect(WindscribeChannel.decodeUpdateChannel(
            at: dir.appendingPathComponent("absent.plist")) == nil)
    }

    // MARK: - test-local builders

    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
         UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// `magic / version / language / updateChannel`, then filler standing in for
    /// the rest of the struct this parse never reads.
    private static func engineSettings(
        language: String, channel: UInt32, version: UInt32 = 13, padding: Int = 600
    ) -> Data {
        var out = Data()
        out.append(contentsOf: be32(0x7745_C2AE))
        out.append(contentsOf: be32(version))
        let utf16 = Array(language.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        out.append(contentsOf: be32(UInt32(utf16.count)))
        out.append(contentsOf: utf16)
        out.append(contentsOf: be32(channel))
        out.append(Data(count: padding))
        return out
    }

    /// `SimpleCrypt::encryptToByteArray` with compression off — the mirror whose
    /// symmetry `qChecksumMatchesTheStandardVector` exists to break.
    private static func simpleCryptEncrypt(_ plain: Data) -> Data {
        var body = Data()
        let checksum = WindscribeChannel.qChecksum(plain)
        body.append(UInt8(checksum >> 8))
        body.append(UInt8(checksum & 0xFF))
        body.append(plain)
        var chained = [UInt8]([0xE7] + body)   // fixed lead byte; the app randomises it
        var last: UInt8 = 0
        for i in chained.indices {
            chained[i] = chained[i] ^ WindscribeChannel.keyParts[i % 8] ^ last
            last = chained[i]
        }
        return Data([3, 0x02] + chained)       // v3, CryptoFlagChecksum
    }
}
