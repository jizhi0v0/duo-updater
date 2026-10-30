import Foundation
import Testing
@testable import DuoUpdaterCore

/// The uv a managed group runs (`UvManagedBinary`): a runnable standalone copy
/// first, Homebrew's keg as the fallback. The keg fixtures are real directory
/// shapes under a temporary root; nothing here reads the Mac's Homebrew.
struct UvManagedBinaryTests {

    /// `/private`-resolved so the temporary root compares with the symlink
    /// target `URL.resolvingSymlinksInPath()` returns.
    static func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("UvManagedBinary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    static func keg(_ root: URL, version: String = "0.13.6", receipt: Bool = true) throws -> URL {
        let keg = root.appendingPathComponent("Cellar/uv/\(version)")
        let bin = keg.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("uv".utf8).write(to: bin.appendingPathComponent("uv"))
        if receipt {
            try Data("{}".utf8).write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))
        }
        let link = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: link.appendingPathComponent("uv").path,
            withDestinationPath: "../Cellar/uv/\(version)/bin/uv")
        return keg
    }

    static func homebrew(_ root: URL, quarantined: Bool = false) -> ManagedRoot.Binary? {
        UvManagedBinary.homebrew(
            roots: [root.path],
            contents: { FileManager.default.contents(atPath: $0) },
            isQuarantined: { _ in quarantined })
    }

    // MARK: the keg

    /// The formula's own `bin/uv`, its version from the keg and the keg's
    /// receipt: a Homebrew binary, trusted as D5.1 says. Mutation: trust it by
    /// Astral's Team ID (the formula's build is ad hoc) or take any `bin/uv`.
    @Test func aHomebrewKegIsTrustedAndNamesItsVersion() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.keg(root)
        let binary = try #require(Self.homebrew(root))
        #expect(binary.path == root.appendingPathComponent("bin/uv").path)
        #expect(binary.version == "0.13.6")
        #expect(binary.trust == .homebrewKeg)
        #expect(binary.trust.runnable)
    }

    /// No install receipt, no keg rule: a hand-copied `bin/uv` is not trusted.
    @Test func aMissingReceiptIsNotAHomebrewUv() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.keg(root, receipt: false)
        #expect(Self.homebrew(root) == nil)
    }

    /// A link to some other file under `bin` is not the formula's `bin/uv`.
    @Test func aPathOutsideTheKegIsNotAHomebrewUv() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("uv".utf8).write(to: root.appendingPathComponent("uv-real"))
        try FileManager.default.createSymbolicLink(
            atPath: bin.appendingPathComponent("uv").path, withDestinationPath: "../uv-real")
        #expect(Self.homebrew(root) == nil)
    }

    /// A quarantined keg is reported so the row can say why it is not run; it
    /// is never runnable.
    @Test func aQuarantinedKegIsReportedButNotRunnable() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.keg(root)
        let binary = try #require(Self.homebrew(root, quarantined: true))
        #expect(binary.trust == .quarantined)
        #expect(!binary.trust.runnable)
    }

    // MARK: which one runs

    /// Both exist: the standalone copy `uv self update` owns wins. Mutation:
    /// prefer Homebrew whenever a keg is found.
    @Test func aRunnableStandaloneUvWins() {
        let standalone = UvInstall(
            path: "/home/.local/bin/uv", executable: "/home/.local/bin/uv", version: "0.13.4",
            signature: .vendor)
        let homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/uv", version: "0.13.6", trust: .homebrewKeg)
        #expect(UvManagedBinary.resolve(standalone: standalone, homebrew: homebrew)?.path == "/home/.local/bin/uv")
    }

    /// The standalone copy exists but may not run: Homebrew's does.
    @Test func aHomebrewUvReplacesAnUntrustedStandaloneUv() {
        let standalone = UvInstall(
            path: "/home/.local/bin/uv", executable: "/home/.local/bin/uv", version: "0.13.4",
            signature: .adHoc)
        let homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/uv", version: "0.13.6", trust: .homebrewKeg)
        #expect(UvManagedBinary.resolve(standalone: standalone, homebrew: homebrew)?.trust == .homebrewKeg)
    }

    /// No standalone uv at all: Homebrew's is the one. Mutation: return nil
    /// when `UvScanner` finds nothing.
    @Test func homebrewIsUsedWhenThereIsNoStandaloneUv() {
        let homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/uv", version: "0.13.6", trust: .homebrewKeg)
        #expect(UvManagedBinary.resolve(standalone: nil, homebrew: homebrew)?.trust == .homebrewKeg)
    }

    /// Neither: nil, so the row reports the program was not found.
    @Test func neitherUvIsNil() {
        #expect(UvManagedBinary.resolve(standalone: nil, homebrew: nil) == nil)
    }
}
