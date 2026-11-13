import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticUpdateSuggestionTests {
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("suggest-\(UUID().uuidString)")
        var bundle: URL { root.appendingPathComponent("Test.app") }
        func write(_ info: [String: Any], extensionPoint: String? = nil) throws {
            let contents = bundle.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            if let point = extensionPoint {
                let plugin = contents.appendingPathComponent("PlugIns/Ext.appex/Contents")
                try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList:
                    ["NSExtension": ["NSExtensionPointIdentifier": point]], format: .xml, options: 0)
                    .write(to: plugin.appendingPathComponent("Info.plist"))
            }
        }
    }
    private let identity: [String: Any] = ["CFBundleIdentifier": "test.app", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "42"]
    private let observation = AutomaticUpdateSuggestion.Observation(bundleID: "test.app", version: "1.0", build: "42",
        observedOn: "2026-11-13", macOSVersion: "27.3.0", summary: "A running task continued across this update.")

    @Test func staticDeclarationsAreDistinctEvidenceNotRunningUpdatePermission() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try f.write(["LSUIElement": true, "LSBackgroundOnly": "1", "NSSupportsAutomaticTermination": true,
                     "NSSupportsSuddenTermination": "YES"])
        let suggestion = AutomaticUpdateSuggestion.classify(bundle: f.bundle)
        #expect(!suggestion.isSuggested)
        #expect(suggestion.reasons == [.menuBarApp, .backgroundOnlyApp, .automaticTermination,
                                       .suddenTermination, .insufficientEvidence])
    }

    @Test func matchingObservationRecommendsButRetainsSpecificCautions() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try f.write(identity, extensionPoint: "com.apple.networkextension.packet-tunnel")
        let suggestion = AutomaticUpdateSuggestion.classify(bundle: f.bundle, observation: observation, macOSVersion: "27.3.0")
        #expect(suggestion.isSuggested)
        #expect(suggestion.reasons == [.networkExtension])
        #expect(suggestion.observation == observation)
    }

    @Test func anotherBuildIdentityOrOSShowsHistoryWithoutRecommending() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        for key in ["CFBundleVersion", "CFBundleIdentifier", "CFBundleShortVersionString"] {
            var changed = identity; changed[key] = "different"
            try f.write(changed)
            let suggestion = AutomaticUpdateSuggestion.classify(bundle: f.bundle, observation: observation, macOSVersion: "27.3.0")
            #expect(!suggestion.isSuggested)
            #expect(suggestion.observation == observation)
        }
        try f.write(identity)
        #expect(!AutomaticUpdateSuggestion.classify(bundle: f.bundle, observation: observation, macOSVersion: "27.4.0").isSuggested)
    }

    @Test func unreadableAndUnknownAppsDoNotInventWindowOrSafetyClaims() throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let missing = AutomaticUpdateSuggestion.classify(bundle: f.bundle, observation: observation, macOSVersion: "27.3.0")
        #expect(!missing.isSuggested)
        #expect(missing.reasons == [.unreadableBundle])
        try f.write(["CFBundleName": "Editor"])
        #expect(AutomaticUpdateSuggestion.classify(bundle: f.bundle).reasons == [.insufficientEvidence])
    }
}
