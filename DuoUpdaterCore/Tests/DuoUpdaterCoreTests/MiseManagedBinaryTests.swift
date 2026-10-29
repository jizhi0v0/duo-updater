import Foundation
import Testing
@testable import DuoUpdaterCore

/// The mise a managed group runs (`MiseManagedBinary`): a runnable standalone
/// copy first, Homebrew's keg as the fallback. The keg fixtures are real
/// directory shapes under a temporary root; nothing here reads the Mac's
/// Homebrew.
struct MiseManagedBinaryTests {

    /// `/private`-resolved so the temporary root compares with the symlink
    /// target `URL.resolvingSymlinksInPath()` returns.
    static func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("MiseManagedBinary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    static func keg(_ root: URL, version: String = "2026.10.23", receipt: Bool = true) throws -> URL {
        let keg = root.appendingPathComponent("Cellar/mise/\(version)")
        let bin = keg.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("mise".utf8).write(to: bin.appendingPathComponent("mise"))
        if receipt {
            try Data("{}".utf8).write(to: keg.appendingPathComponent("INSTALL_RECEIPT.json"))
        }
        let link = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: link, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: link.appendingPathComponent("mise").path,
            withDestinationPath: "../Cellar/mise/\(version)/bin/mise")
        return keg
    }

    static func homebrew(_ root: URL, quarantined: Bool = false) -> ManagedRoot.Binary? {
        MiseManagedBinary.homebrew(
            roots: [root.path],
            contents: { FileManager.default.contents(atPath: $0) },
            isQuarantined: { _ in quarantined })
    }

    // MARK: the keg

    /// The formula's own `bin/mise`, its version from the keg and the keg's
    /// receipt: a Homebrew binary, trusted as D5.1 says. Mutation: trust it by
    /// Jeffrey Dickey's Team ID (the formula's build is ad hoc) or take any
    /// `bin/mise`.
    @Test func aHomebrewKegIsTrustedAndNamesItsVersion() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.keg(root)
        let binary = try #require(Self.homebrew(root))
        #expect(binary.path == root.appendingPathComponent("bin/mise").path)
        #expect(binary.version == "2026.10.23")
        #expect(binary.trust == .homebrewKeg)
        #expect(binary.trust.runnable)
    }

    /// No install receipt, no keg rule: a hand-copied `bin/mise` is not trusted.
    @Test func aMissingReceiptIsNotAHomebrewMise() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.keg(root, receipt: false)
        #expect(Self.homebrew(root) == nil)
    }

    /// A link to some other file under `bin` is not the formula's `bin/mise`.
    @Test func aPathOutsideTheKegIsNotAHomebrewMise() throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("mise".utf8).write(to: root.appendingPathComponent("mise-real"))
        try FileManager.default.createSymbolicLink(
            atPath: bin.appendingPathComponent("mise").path, withDestinationPath: "../mise-real")
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

    /// Both exist: the standalone copy `mise self-update` owns wins. Mutation:
    /// prefer Homebrew whenever a keg is found.
    @Test func aRunnableStandaloneMiseWins() {
        let standalone = MiseInstall(
            path: "/home/.local/bin/mise", version: "2026.10.7", signature: .vendor)
        let homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/mise", version: "2026.10.23", trust: .homebrewKeg)
        #expect(MiseManagedBinary.resolve(standalone: standalone, homebrew: homebrew)?.path == "/home/.local/bin/mise")
    }

    /// The standalone copy exists but may not run: Homebrew's does.
    @Test func aHomebrewMiseReplacesAnUntrustedStandaloneMise() {
        let standalone = MiseInstall(
            path: "/home/.local/bin/mise", version: "2026.10.7", signature: .adHoc)
        let homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/mise", version: "2026.10.23", trust: .homebrewKeg)
        #expect(MiseManagedBinary.resolve(standalone: standalone, homebrew: homebrew)?.trust == .homebrewKeg)
    }

    /// No standalone mise at all: Homebrew's is the one. Mutation: return nil
    /// when `MiseScanner` finds nothing.
    @Test func homebrewIsUsedWhenThereIsNoStandaloneMise() {
        let homebrew = ManagedRoot.Binary(
            path: "/opt/homebrew/bin/mise", version: "2026.10.23", trust: .homebrewKeg)
        #expect(MiseManagedBinary.resolve(standalone: nil, homebrew: homebrew)?.trust == .homebrewKeg)
    }

    /// Neither: nil, so the row reports the program was not found.
    @Test func neitherMiseIsNil() {
        #expect(MiseManagedBinary.resolve(standalone: nil, homebrew: nil) == nil)
    }
}
