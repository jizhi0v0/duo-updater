import Foundation
import Testing
@testable import DuoUpdaterCore

/// `VendorInstaller.unwrapNestedPayload`: the step that takes the real app out of
/// a vendor's stub installer (DoubaoIme's `Contents/Resources/DoubaoIme.zip`), two
/// steps upstream of a privileged swap. Called directly, because the route only
/// reaches it once the stub's signature verifies — see the function's comment.
///
/// Each refusal case puts a real, extractable payload at the place the path
/// points to, so a test passes only because the guard refused, not because
/// extraction failed for some other reason.
struct NestedPayloadUnwrapTests {

    /// A fresh scratch directory holding `Stub.app` and a `work` directory.
    private static func scratch() throws -> (root: URL, stub: URL, work: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-nested-\(UUID().uuidString)", isDirectory: true)
        let stub = root.appendingPathComponent("Stub.app", isDirectory: true)
        let work = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stub.appendingPathComponent("Contents/Resources", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return (root, stub, work)
    }

    /// Write a zip holding one `Payload.app` to `archive`.
    private static func writePayloadZip(to archive: URL) async throws {
        let staging = archive.deletingLastPathComponent()
            .appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let contents = staging.appendingPathComponent("Payload.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization
            .data(fromPropertyList: ["CFBundleIdentifier": "com.example.zzfixture.payload"],
                  format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.createDirectory(
            at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        let made = try await ChildProcess.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--keepParent",
             staging.appendingPathComponent("Payload.app").path, archive.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)
        try FileManager.default.removeItem(at: staging)
    }

    private static func isNestedPayloadMissing(_ error: Error) -> Bool {
        if case VendorInstaller.InstallError.nestedPayloadMissing = error { return true }
        return false
    }

    /// The payload is found where the path says, and unpacked into its own
    /// directory under `workDir`.
    ///
    /// Mutation: `inner` → `workDir` (extract into the shared work directory).
    @Test func thePayloadInsideTheStubIsExtractedIntoItsOwnDirectory() async throws {
        let (root, stub, work) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.writePayloadZip(
            to: stub.appendingPathComponent("Contents/Resources/Payload.zip"))

        let app = try await VendorInstaller.unwrapNestedPayload(
            at: "Contents/Resources/Payload.zip", inside: stub, workDir: work)

        #expect(app.lastPathComponent == "Payload.app")
        let inner = work.appendingPathComponent("nested-payload").standardizedFileURL.path
        #expect(app.standardizedFileURL.path.hasPrefix(inner + "/"))
    }

    /// A `..` that climbs out of the stub is refused, though a payload sits there.
    ///
    /// Mutation: drop the `nested.path.hasPrefix(root + "/")` condition.
    @Test func aPathThatClimbsOutOfTheStubIsRefused() async throws {
        let (root, stub, work) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.writePayloadZip(to: root.appendingPathComponent("Outside.zip"))

        do {
            let app = try await VendorInstaller.unwrapNestedPayload(
                at: "Contents/../../Outside.zip", inside: stub, workDir: work)
            Issue.record("extracted \(app.path) from outside the stub")
        } catch {
            #expect(Self.isNestedPayloadMissing(error), "got \(error)")
        }
    }

    /// A sibling whose name starts with the stub's (`Stub.app-x`) is outside it too.
    ///
    /// Mutation: `root + "/"` → `root`.
    @Test func aSiblingSharingTheStubsNamePrefixIsRefused() async throws {
        let (root, stub, work) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try await Self.writePayloadZip(
            to: root.appendingPathComponent("Stub.app-x/Payload.zip"))

        do {
            let app = try await VendorInstaller.unwrapNestedPayload(
                at: "../Stub.app-x/Payload.zip", inside: stub, workDir: work)
            Issue.record("extracted \(app.path) from a sibling of the stub")
        } catch {
            #expect(Self.isNestedPayloadMissing(error), "got \(error)")
        }
    }

    /// A path to nothing is named as the stub not holding it, not as a failed
    /// extraction.
    ///
    /// Mutation: drop the `fileExists` condition.
    @Test func aMissingPayloadIsNamedAsMissing() async throws {
        let (root, stub, work) = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            let app = try await VendorInstaller.unwrapNestedPayload(
                at: "Contents/Resources/Nowhere.zip", inside: stub, workDir: work)
            Issue.record("returned \(app.path) for a payload that does not exist")
        } catch {
            #expect(Self.isNestedPayloadMissing(error), "got \(error)")
        }
    }
}
