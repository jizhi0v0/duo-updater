import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct PrivilegedReplacementShellTests {

    /// The real WeType and DoubaoIme bundles are both root:staff 775 at the app
    /// and Contents levels, while their downloaded archives unpack as 755. This
    /// runs the exact privileged shell transaction in a user-owned scratch folder
    /// and proves the live install's modes win without needing an administrator.
    @Test func aPrivilegedSwapPreservesTheInstalledDirectoryModes() throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory
            .appendingPathComponent("DuoPrivilegedSwapTest-\(UUID().uuidString)")
        let target = parent.appendingPathComponent("Fixture.app")
        let incoming = parent.appendingPathComponent("Incoming.app")
        defer { try? fm.removeItem(at: parent) }

        try fm.createDirectory(
            at: target.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: incoming.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("Contents/old"))
        try Data("new".utf8).write(to: incoming.appendingPathComponent("Contents/new"))
        try fm.setAttributes([.posixPermissions: 0o775], ofItemAtPath: target.path)
        try fm.setAttributes(
            [.posixPermissions: 0o775], ofItemAtPath: target.appendingPathComponent("Contents").path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: incoming.path)
        try fm.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: incoming.appendingPathComponent("Contents").path)

        let shell = try InPlaceSwap.privilegedReplacementShell(
            newApp: incoming, target: target)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shell]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(try mode(of: target) == 0o775)
        #expect(try mode(of: target.appendingPathComponent("Contents")) == 0o775)
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
        #expect(!fm.fileExists(atPath: target.appendingPathComponent("Contents/old").path))
    }

    private func mode(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attrs[.posixPermissions] as? NSNumber).intValue & 0o7777
    }
}
