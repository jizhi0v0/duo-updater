import Foundation
import Testing
@testable import DuoUpdaterCore

/// The scanners that read executables a chunk at a time (`ExecutableBytes`) give
/// what they gave over the whole mapped file, wherever the chunk boundaries fall:
/// each test runs every chunk size from 1 to past the file.
@Suite struct ChunkedScanTests {

    static func file(_ bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chunked-\(UUID().uuidString)")
        try bytes.write(to: url)
        return url
    }

    /// Bytes no scanner here matches, so what they find comes from the fixture.
    static func filler(_ count: Int) -> Data {
        Data((0..<count).map { UInt8([0x00, 0x01, 0x7F, 0x13][$0 % 4]) })
    }

    // MARK: forEachChunk

    /// Mutation: carry the wrong tail, or end without a last call.
    @Test func chunksCoverTheFileOnceAndCarryTheTail() throws {
        let bytes = Data((0..<97).map { UInt8($0) })
        let url = try Self.file(bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        for overlap in [0, 3, 200] {
            for size in 1...(bytes.count + 3) {
                var seen = Data()
                var previous = Data()
                var lasts = 0
                let read = ExecutableBytes.forEachChunk(of: url, overlap: overlap, chunkSize: size) { buffer, carried, isLast in
                    let current = Data(buffer)
                    #expect(current.prefix(carried) == previous.suffix(min(overlap, previous.count)))
                    seen.append(current.dropFirst(carried))
                    previous = current
                    if isLast { lasts += 1 }
                    return true
                }
                #expect(read)
                #expect(seen == bytes, "overlap \(overlap), chunk size \(size)")
                #expect(lasts == 1)
            }
        }
        #expect(!ExecutableBytes.forEachChunk(of: URL(fileURLWithPath: "/nowhere/x"), overlap: 0) { _, _, _ in true })
    }

    @Test func returningFalseStopsReading() throws {
        let url = try Self.file(Data(count: 100))
        defer { try? FileManager.default.removeItem(at: url) }
        var calls = 0
        #expect(ExecutableBytes.forEachChunk(of: url, overlap: 0, chunkSize: 10) { _, _, _ in
            calls += 1
            return false
        })
        #expect(calls == 1)
    }

    // MARK: MarkerSearch

    /// Overlapping occurrences included, each once, each with `before` bytes ahead
    /// of it in its buffer unless the file starts closer. Mutation: resume past the
    /// whole marker, or drop the carried tail.
    @Test func markerSearchFindsEveryOccurrenceOnceWithItsContext() throws {
        let marker = Data("\0Darwin\0".utf8)
        let bytes = Data("\0Darwin\0".utf8) + Self.filler(30) + Data("x\0Darwin\0Darwin\0y".utf8)
            + Self.filler(17) + Data("\0Darwin\0".utf8)
        let url = try Self.file(bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        var expected: [Int] = []
        var from = bytes.startIndex
        while let range = bytes.range(of: marker, in: from..<bytes.endIndex) {
            expected.append(range.lowerBound)
            from = range.lowerBound + 1
        }
        #expect(expected.count == 4)
        let before = 12
        for size in 1...(bytes.count + 3) {
            var search = ExecutableBytes.MarkerSearch(marker: marker, before: before)
            var found: [Int] = []
            var consumed = 0
            _ = ExecutableBytes.forEachChunk(of: url, overlap: search.overlap, chunkSize: size) { buffer, carried, _ in
                let bufferStart = consumed - carried
                search.feed(buffer, carried: carried) { at in
                    #expect(at >= before || bufferStart == 0, "chunk size \(size)")
                    #expect(Data(buffer[at..<(at + marker.count)]) == marker)
                    found.append(bufferStart + at)
                    return true
                }
                consumed += buffer.count - carried
                return true
            }
            #expect(found == expected, "chunk size \(size)")
        }
    }

    // MARK: Source paths

    /// A dot whose extension, or the byte that decides it, is in the next chunk; a
    /// path longer than the walk back; an extension at the very end of the file.
    /// Mutation: judge the last `lookAhead` dots early, or carry less than
    /// `longestPath` bytes.
    @Test func sourcePathsAreTheSameInEveryChunking() throws {
        let long = "/" + String(repeating: "deep/", count: 100) + "Long.swift"
        var bytes = Self.filler(500)
        for text in [
            "\0/ZZBuild/zzfixture/Module/Feature.swift\0",
            "\0ZZFixture/NotC.cpp\0", "\0ZZFixture/Only.c\0", "\0ZZFixture/Module.swiftmodule\0",
            "\0window ZZFixture/Window.swift\0", "\0" + long + "\0",
        ] {
            bytes += Data(text.utf8) + Self.filler(37)
        }
        bytes += Data("\0zz/EndOfFile.c".utf8)
        let url = try Self.file(bytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let whole = bytes.withUnsafeBytes { SourcePathScanner.paths(in: $0) }
        #expect(whole.isSuperset(of: [
            "/ZZBuild/zzfixture/Module/Feature.swift", "ZZFixture/NotC.cpp", "ZZFixture/Only.c",
            "ZZFixture/Window.swift", "zz/EndOfFile.c",
        ]))
        #expect(whole.contains { $0.hasSuffix("deep/Long.swift") && $0.utf8.count == 400 + 6 })
        for size in 1...(bytes.count + 3) {
            var stream = SourcePathScanner.Stream()
            _ = ExecutableBytes.forEachChunk(of: url, overlap: SourcePathScanner.Stream.overlap, chunkSize: size) {
                stream.feed($0, carried: $1, isLast: $2)
                return true
            }
            #expect(stream.found == whole, "chunk size \(size)")
        }
    }

    // MARK: Printable runs

    /// `PrintableRuns.append` as it was before it was a stream: the oracle.
    static func referenceRuns(_ bytes: UnsafeRawBufferPointer) -> Data {
        var blob = Data()
        let count = bytes.count
        var i = 0
        var runStart = -1
        while i < count {
            let byte = bytes[i]
            if byte >= 0x20 && byte <= 0x7E {
                if runStart < 0 { runStart = i }
                i += 1
            } else if byte >= 0xE0 && byte <= 0xEF, i + 2 < count,
                      bytes[i + 1] & 0xC0 == 0x80, bytes[i + 2] & 0xC0 == 0x80 {
                if runStart < 0 { runStart = i }
                i += 3
            } else {
                if runStart >= 0, i - runStart >= 4 {
                    blob.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[runStart..<i]))
                    blob.append(0x0A)
                }
                runStart = -1
                i += 1
            }
        }
        if runStart >= 0, count - runStart >= 4 {
            blob.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[runStart..<count]))
            blob.append(0x0A)
        }
        return blob
    }

    /// Runs of every length around the threshold, three-byte UTF-8 inside and at
    /// the edges of runs, a truncated sequence, a run longer than most chunks, and
    /// a lead byte as the file's last byte. Both with the overlap the stream asks
    /// for and with the one `BundleFactsReader` gives it. Mutation: decide a lead
    /// byte without its continuation, or drop a run shorter than four bytes at a
    /// chunk's end.
    @Test func printableRunsAreTheSameInEveryChunking() throws {
        var bytes = Data()
        for length in 1...6 {
            bytes += Data(String(repeating: "a", count: length).utf8) + Data([0])
        }
        bytes += Data("取消\0x取\0取\0ab取cd\0".utf8)
        bytes += Data([0x61, 0x62, 0x63, 0xE5, 0x8F, 0x00, 0x64, 0x65, 0x66, 0x67, 0xE5, 0x00])
        bytes += Data(String(repeating: "long run ", count: 20).utf8) + Data([0x01])
        bytes += Data("tail取".utf8) + Data([0xE5])
        let url = try Self.file(bytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let expected = bytes.withUnsafeBytes { Self.referenceRuns($0) }
        let single = bytes.withUnsafeBytes { buffer -> Data in
            var blob = Data()
            PrintableRuns.append(from: buffer, to: &blob)
            return blob
        }
        #expect(single == expected)
        #expect(String(decoding: expected, as: UTF8.self).contains("\n取消\n"))
        for overlap in [PrintableRuns.Stream.overlap, SourcePathScanner.Stream.overlap] {
            for size in 1...(bytes.count + 3) {
                var stream = PrintableRuns.Stream()
                var blob = Data("before\n".utf8)
                _ = ExecutableBytes.forEachChunk(of: url, overlap: overlap, chunkSize: size) {
                    stream.feed($0, carried: $1, isLast: $2, to: &blob)
                    return true
                }
                #expect(blob == Data("before\n".utf8) + expected, "overlap \(overlap), chunk size \(size)")
            }
        }
    }
}
