import Foundation
import DuoUpdaterCore

/// Reads a flat `.pkg`'s declared `hostArchitectures` straight off the vendor's
/// server, without downloading the package.
///
/// **What this is for, and what it is emphatically not.** `PackageInstaller`
/// hands packages to macOS's own installer and never sees a `.app`, so the pkg
/// route runs neither Gate 5 (`verifyRunnableArchitecture`) nor Gate 5b — see
/// that actor's architecture-limitation comment, and #205/#415. The obvious
/// repair is "read the package's own `hostArchitectures` declaration instead",
/// and measuring it is how we learned that repair does not work:
///
///   - Measured 2026-09-07 across the whole pkg route (22 vendor specs + XQuartz):
///     **15 declared, all universal; 7 declared nothing; 1 unreadable** (Sunlogin
///     serves HTML at its install URL, and is a DMG-wrapped pkg besides).
///   - **The declaration has never once said "Intel-only" here**, so a gate built
///     on it would not have fired a single time.
///   - ⚠️ **The only architecture-specific packages in the registry are exactly
///     the ones that declare nothing**: WeChat DevTools ships
///     `wechat_devtools_..._darwin_arm64.pkg` with no `hostArchitectures` in its
///     `PackageInfo`. Where architecture varies the declaration is blind; where
///     the declaration exists architecture does not vary.
///
/// So this sweeps for DRIFT — a spec that stops declaring, or starts declaring a
/// single architecture — and must never be described as an installability check.
/// A vendor's claim is not the payload's slices; only reading the real Mach-O
/// answers that, which is Gate 5's whole point and what this cannot do.
///
/// `scripts/pkg_host_architectures.py` reads the same bytes in Python. It is kept
/// as the second witness, per CLAUDE.md: a rule this fiddly is worth checking
/// against an independent implementation on the real registry rather than
/// against its own unit tests.
public enum PackageArchitectureProbe {

    /// The endpoint answered without honouring `Range`. Surfaces as `infra` — it
    /// is a vendor/CDN property, not a recipe defect — but it must NOT be
    /// mistaken for a reading of the package.
    struct RangeUnsupported: LocalizedError {
        let status: Int
        var errorDescription: String? {
            "server ignored the Range request (HTTP \(status), expected 206)"
        }
    }

    /// What one package said about itself.
    public enum Declaration: Equatable, Sendable {
        /// `hostArchitectures` named every architecture we care about.
        case universal(String)
        /// It named exactly one. The event this sweep exists to notice.
        case single(String)
        /// No declaration in `Distribution` or `PackageInfo`. The common case,
        /// and NOT a defect — 7 of the 22 this sweep reads, including all three
        /// Edge channels and all three WeChat DevTools channels. Reported, never
        /// warned on.
        case absent
        /// The URL did not serve a flat package: a DMG-wrapped pkg, or a vendor
        /// serving an HTML interstitial. Not a finding either — `kind: .pkg`
        /// legitimately covers a `.dmg` that PackageInstaller unwraps.
        case notAFlatPackage(String)

        public var value: String {
            switch self {
            case .universal(let v), .single(let v): return v
            case .absent: return "ABSENT"
            case .notAFlatPackage(let why): return "NOT-XAR(\(why))"
            }
        }
    }

    /// A xar file is a 28-byte header, a zlib-compressed table of contents, then
    /// the heap. The TOC carries each member's offset and length inside the heap,
    /// so `Distribution` is reachable without the payload behind it.
    ///
    /// **THREE** range requests per package — header, TOC, member — and four when
    /// `Distribution` exists but carries no declaration and `PackageInfo` is tried
    /// after it. So the pkg route costs 66–88 requests, not the "two small
    /// requests" an earlier version of this comment claimed. Bytes are what stays
    /// small: ~197 KB for all 22, against GB-scale Office packages if the payload
    /// were expanded — which is why #400 ruled expansion out.
    static let headerLength = 28
    /// Caps a hostile or corrupt endpoint. Every Distribution in this registry is
    /// far under it; Edge's is 716 bytes.
    static let maxMemberBytes = 4 << 20

    /// Read one package. Vendor-side trouble comes back as a value, never as a
    /// throw: this runs inside a sweep whose job is to report, and an endpoint
    /// that hangs up is `infra`, not a recipe defect.
    public static func declaration(
        at url: URL, session: URLSession = .updates
    ) async -> Result<Declaration, any Error> {
        do {
            let head = try await bytes(url, 0, headerLength - 1, session)
            // An empty or short body is its own story and must not be reported as
            // a wrong magic number. Measured on Sunlogin 2026-09-07: its install
            // URL 302s to the vendor's download page, which answers 206 with a
            // ZERO-length body to `URLSession` while `curl` gets 28 bytes of HTML
            // from the same request — so "we read nothing" is the true finding, and
            // `magic=0x` alone would have read as "we saw bytes and they were odd".
            guard head.count >= 24 else {
                return .success(.notAFlatPackage("short body (\(head.count) bytes)"))
            }
            guard head.prefix(4) == Data("xar!".utf8) else {
                // Hex, not the bytes themselves. A vendor serving an HTML
                // interstitial here starts the body `<!DO`, and `Redactor` — which
                // every `Finding` string goes through — strips markup, so the raw
                // spelling reaches the report as an EMPTY diagnostic. Measured on
                // Sunlogin: `NOT-XAR(magic=)`, which says nothing at all. Hex
                // survives redaction and still identifies what arrived.
                let magic = head.prefix(4).map { String(format: "%02x", $0) }.joined()
                return .success(.notAFlatPackage("magic=0x\(magic)"))
            }
            let headerSize = Int(head.withUnsafeBytes {
                UInt16(bigEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self))
            })
            // ⚠️ Range-check as UInt64 and only then narrow. `Int(someUInt64)` TRAPS
            // above `Int.max`, and a trap is not catchable — so a file whose first
            // four bytes are `xar!` and whose length field has the high bit set
            // would kill `duo verify` outright, from vendor-controlled bytes. The
            // Python witness gets this right by construction (`struct.unpack(">Q")`
            // is unsigned and its bound check runs on that value), and the two
            // disagreeing on a hostile input is exactly what a second witness is
            // for. Verified: 0x8000000000000000 now reports, rather than crashing.
            let tocRawLength = head.withUnsafeBytes {
                UInt64(bigEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
            }
            guard tocRawLength > 0, tocRawLength <= UInt64(maxMemberBytes) else {
                return .success(.notAFlatPackage("toc=\(tocRawLength)"))
            }
            let tocCompressed = Int(tocRawLength)
            let tocRaw = try await bytes(url, headerSize, headerSize + tocCompressed - 1, session)
            guard let toc = Inflate.zlib(tocRaw) else {
                return .success(.notAFlatPackage("toc-not-deflate"))
            }
            let heap = headerSize + tocCompressed
            // Distribution before PackageInfo: on a product archive it is the file
            // that carries the declaration, and a component PackageInfo beside it
            // need not repeat it.
            for name in ["Distribution", "PackageInfo"] {
                // `offset` and `length` are parsed out of vendor-controlled XML, so
                // they are attacker input in the same sense the header is. A
                // NEGATIVE length passed the old `<= maxMemberBytes` check and then
                // reached `prefix(-1)`, whose precondition failure is another
                // uncatchable trap; a huge offset overflowed the `heap + offset +
                // length` arithmetic. Both are bounded here, before any of it runs.
                guard let member = XarTOC.member(named: name, in: toc),
                      (0...maxMemberBytes).contains(member.length),
                      member.offset >= 0,
                      member.offset <= Int.max - heap - member.length else { continue }
                let raw = try await bytes(
                    url, heap + member.offset, heap + member.offset + member.length - 1, session)
                let body = member.isCompressed ? (Inflate.zlib(raw) ?? raw) : raw
                guard let value = hostArchitecturesAttribute(in: body) else { continue }
                return .success(classify(value))
            }
            return .success(.absent)
        } catch {
            return .failure(error)
        }
    }

    /// Universal vs single is decided by counting the architectures named, not by
    /// matching a spelling. Both orders are live — measured 2026-09-07, the
    /// PACKAGES declare `arm64,x86_64` 9 times and `x86_64,arm64` 6 times — so the
    /// order means nothing and a string comparison against one spelling would call
    /// the other single-architecture.
    ///
    /// ⚠️ Those counts are a property of the vendors' packages, not of this
    /// repository: `grep hostArchitectures` over the registry returns nothing. An
    /// earlier version of this comment said "the registry carries both", which
    /// sends a reader looking for something that is not there.
    ///
    /// An empty declaration (`hostArchitectures=""`) names nothing, so it counts as
    /// single and warns. That is deliberate — a vendor publishing an empty
    /// architecture list is worth a human look — but it has never been seen.
    static func classify(_ value: String) -> Declaration {
        let names = value.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        return Set(names).count <= 1 ? .single(value) : .universal(value)
    }

    /// Whitespace around `=` is allowed because the attribute is XML, not a fixed
    /// vendor spelling — `xmllint --format` and hand edits both produce it.
    ///
    /// Built per call rather than held in a `static let`: `Regex` is not
    /// `Sendable`, and this runs from a concurrent sweep. Compiling one small
    /// pattern per package is nothing beside the two network round trips it sits
    /// between.
    static func hostArchitecturesAttribute(in body: Data) -> String? {
        guard let text = String(data: body, encoding: .utf8)
            ?? String(data: body, encoding: .isoLatin1) else { return nil }
        guard let pattern = try? NSRegularExpression(
            pattern: #"hostArchitectures\s*=\s*"([^"]*)""#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// Reads AT MOST the requested range, and stops the transfer rather than
    /// truncating after the fact.
    ///
    /// ⚠️ This must not go back to `countedData`. That buffers the whole response
    /// before returning, so `data.prefix(n)` on the result protects nothing: a
    /// server that ignores `Range` answers 200 with the entire file, and these
    /// URLs are installers measured in gigabytes. An earlier version of this
    /// function did exactly that and carried a comment claiming the prefix was
    /// what kept an Office package out of memory — it was not.
    ///
    /// `.other` rather than a purpose of its own, deliberately. These bytes are
    /// produced only by `duo verify --pkgarch` — the app never makes this request
    /// — and every row is already tagged `RequestClient.cli`, so they are
    /// separable without a new category. A new `RequestPurpose` case would have to
    /// be spelled in `RequestLogPane`'s three exhaustive switches, one of which is
    /// a `String(localized:)` legend, putting a new user-facing string and seven
    /// translations in front of every user for a bucket only a developer sweep can
    /// fill. Revisit if the app itself ever reads installer metadata.
    private static func bytes(
        _ url: URL, _ start: Int, _ end: Int, _ session: URLSession
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        let limit = end - start + 1
        let (stream, response) = try await session.countedBytes(for: request, purpose: .other)
        // ⚠️ A server that ignores `Range` answers **200 with the whole file**, and
        // the first `limit` bytes of a package are not the bytes that were asked
        // for. Reading them anyway is the worst outcome available: the TOC read
        // would get the file's opening bytes, fail to inflate, and the package
        // would be filed `notAFlatPackage` — status `ok`. A green verdict produced
        // by reading the wrong bytes, with the drift check silently off for that
        // vendor. Partial Content or nothing.
        if let http = response as? HTTPURLResponse, http.statusCode != 206 {
            throw PackageArchitectureProbe.RangeUnsupported(status: http.statusCode)
        }
        var out = Data()
        out.reserveCapacity(min(limit, maxMemberBytes))
        for try await byte in stream {
            out.append(byte)
            if out.count >= limit { break }
        }
        return out
    }
}

/// The two TOC fields this needs, so the XML walk lives in one place rather than
/// inline in the reader.
enum XarTOC {
    struct Member { let offset: Int; let length: Int; let isCompressed: Bool }

    static func member(named name: String, in toc: Data) -> Member? {
        guard let doc = try? XMLDocument(data: toc) else { return nil }
        guard let nodes = try? doc.nodes(
            forXPath: "//file[name='\(name)']/data") else { return nil }
        for node in nodes {
            guard let element = node as? XMLElement,
                  let offset = Int(element.elements(forName: "offset").first?.stringValue ?? ""),
                  let length = Int(element.elements(forName: "length").first?.stringValue ?? "")
            else { continue }
            let style = element.elements(forName: "encoding").first?
                .attribute(forName: "style")?.stringValue ?? ""
            return Member(offset: offset, length: length,
                          isCompressed: style.contains("gzip") || style.contains("zlib"))
        }
        return nil
    }
}

enum Inflate {
    /// ⚠️ Read the order carefully, because the obvious reading is backwards.
    /// Apple's `NSData.CompressionAlgorithm.zlib` is **raw DEFLATE** (RFC 1951,
    /// `windowBits = -15`), NOT the RFC 1950 zlib wrapper its name suggests. xar
    /// writes the RFC 1950 form, so the FIRST call here is the raw-deflate attempt
    /// — which fails on xar's 2-byte header — and the `dropFirst(2)` fallback is
    /// what actually reads a real package. The ordering is correct; an earlier
    /// version of this comment described it as "zlib-wrapped first", which inverts
    /// what each branch does and would mislead anyone trying to simplify it.
    ///
    /// Not verbatim-verified against Apple's documentation (those pages render as
    /// SPA shells); rests on Apple's Archive-format docs plus developer-forums
    /// thread 712115, and on the round-trip the unit tests exercise both ways.
    static func zlib(_ data: Data) -> Data? {
        if let out = try? (data as NSData).decompressed(using: .zlib) as Data { return out }
        if data.count > 2, let out = try? (data.dropFirst(2) as NSData)
            .decompressed(using: .zlib) as Data { return out }
        return nil
    }
}
