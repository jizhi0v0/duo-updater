import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticUpdateSuggestionTests {
    /// A throwaway bundle with the given Info.plist and, optionally, one app
    /// extension of the given point and a system extension.
    private func bundle(_ info: [String: Any], extensionPoint: String? = nil,
                        systemExtension: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suggest-\(UUID().uuidString)", isDirectory: true)
        let app = root.appendingPathComponent("Test.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try (info as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        if let point = extensionPoint {
            let appex = app.appendingPathComponent("PlugIns/Ext.appex/Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: appex, withIntermediateDirectories: true)
            try (["NSExtension": ["NSExtensionPointIdentifier": point]] as NSDictionary)
                .write(to: appex.appendingPathComponent("Info.plist"))
        }
        if systemExtension {
            let dir = app.appendingPathComponent("Library/SystemExtensions/x.systemextension", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return root.appendingPathComponent("Test.app")
    }

    @Test func menuBarAndSafeTerminationAppsAreSuggested() throws {
        #expect(AutomaticUpdateSuggestion.classify(bundle: try bundle(["LSUIElement": true]))
            == .suggested(.menuBarApp))
        #expect(AutomaticUpdateSuggestion.classify(bundle: try bundle(["LSUIElement": "1"]))
            == .suggested(.menuBarApp))
        #expect(AutomaticUpdateSuggestion.classify(bundle: try bundle(["NSSupportsAutomaticTermination": true]))
            == .suggested(.declaresSafeTermination))
        #expect(AutomaticUpdateSuggestion.classify(bundle: try bundle(["NSSupportsSuddenTermination": "YES"]))
            == .suggested(.declaresSafeTermination))
    }

    @Test func windowedAppsAreNotSuggested() throws {
        #expect(AutomaticUpdateSuggestion.classify(bundle: try bundle(["CFBundleName": "Editor"]))
            == .notSuggested(.windowedApp))
        #expect(AutomaticUpdateSuggestion.classify(bundle: try bundle(["LSUIElement": false]))
            == .notSuggested(.windowedApp))
    }

    /// The extension checks win over the menu-bar flag: a VPN is usually a
    /// menu-bar app, and it is the one quitting hurts most.
    @Test func extensionsOverrideTheMenuBarFlag() throws {
        let vpn = try bundle(["LSUIElement": true], extensionPoint: "com.apple.networkextension.packet-tunnel")
        #expect(AutomaticUpdateSuggestion.classify(bundle: vpn) == .notSuggested(.networkExtension))
        let sync = try bundle(["LSUIElement": true], extensionPoint: "com.apple.fileprovider-nonui")
        #expect(AutomaticUpdateSuggestion.classify(bundle: sync) == .notSuggested(.fileSync))
        let system = try bundle(["LSUIElement": true], systemExtension: true)
        #expect(AutomaticUpdateSuggestion.classify(bundle: system) == .notSuggested(.systemExtension))
        let share = try bundle(["LSUIElement": true], extensionPoint: "com.apple.share-services")
        #expect(AutomaticUpdateSuggestion.classify(bundle: share) == .suggested(.menuBarApp))
    }

    /// WeType declares `LSUIElement` too; quitting it takes away a keyboard layout.
    @Test func inputMethodsAreNotSuggested() throws {
        let ime = try bundle(["LSUIElement": true, "InputMethodConnectionName": "X_Connection"])
        #expect(AutomaticUpdateSuggestion.classify(bundle: ime) == .notSuggested(.inputMethod))
    }

    @Test func missingBundleIsNotSuggested() {
        let gone = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).app")
        #expect(AutomaticUpdateSuggestion.classify(bundle: gone) == .notSuggested(.windowedApp))
    }
}
