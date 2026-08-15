import Testing
import Foundation
@testable import DuoUpdaterCore

/// The AX press itself needs a live Installer.app and Accessibility trust, so what
/// is covered here is the part that decides *which* window gets closed — a wrong
/// match would close a window the user is using.
struct InstallerWindowCloserTests {

    @Test func matchesTheDocumentURLInstallerReports() {
        let pkg = URL(fileURLWithPath: "/private/tmp/DuoUpdater-pkg-Example-1/Example.pkg")
        #expect(InstallerWindowCloser.isSamePackage(
            document: "file:///private/tmp/DuoUpdater-pkg-Example-1/Example.pkg", as: pkg))
        #expect(!InstallerWindowCloser.isSamePackage(
            document: "file:///private/tmp/DuoUpdater-pkg-Example-2/Example.pkg", as: pkg))
    }

    /// Installer reports the URL the document was opened with, which may keep the
    /// `/tmp` and `/var` symlinks unresolved while our stored path went through
    /// `FileManager.temporaryDirectory` (or the reverse). Both sides normalise, so
    /// the two spellings of one file match either way round.
    @Test func matchesAcrossSymlinkedTempPaths() {
        let short = URL(fileURLWithPath: "/tmp/DuoUpdater-pkg-Example-1/Example.pkg")
        let full = URL(fileURLWithPath: "/private/tmp/DuoUpdater-pkg-Example-1/Example.pkg")
        #expect(InstallerWindowCloser.isSamePackage(document: full.absoluteString, as: short))
        #expect(InstallerWindowCloser.isSamePackage(document: short.absoluteString, as: full))
        #expect(!InstallerWindowCloser.isSamePackage(
            document: "file:///private/tmp/DuoUpdater-pkg-Example-2/Example.pkg", as: short))
    }

    @Test func matchesPercentEncodedNames() {
        let pkg = URL(fileURLWithPath: "/private/tmp/DuoUpdater-pkg-Example-1/Example App.pkg")
        #expect(InstallerWindowCloser.isSamePackage(
            document: "file:///private/tmp/DuoUpdater-pkg-Example-1/Example%20App.pkg", as: pkg))
    }

    @Test func ignoresWindowsWithoutAUsableDocument() {
        let pkg = URL(fileURLWithPath: "/private/tmp/DuoUpdater-pkg-Example-1/Example.pkg")
        #expect(!InstallerWindowCloser.isSamePackage(document: nil, as: pkg))
        #expect(!InstallerWindowCloser.isSamePackage(document: "", as: pkg))
        #expect(!InstallerWindowCloser.isSamePackage(
            document: "https://example.com/Example.pkg", as: pkg))
    }
}
