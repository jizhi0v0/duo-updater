import Foundation

/// Advice for the setup guide, never permission to quit or install. Static
/// declarations describe an app's role and OS termination support; only a
/// matching, explicitly recorded local observation recommends running updates.
public struct AutomaticUpdateSuggestion: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case menuBarApp, backgroundOnlyApp
        case automaticTermination, suddenTermination
        case networkExtension, fileSync, systemExtension, inputMethod
        case insufficientEvidence, unreadableBundle
    }

    /// A person-verified observation, not an inference from a successful install.
    /// Stored locally per installed copy. Its scope is deliberately exact: a
    /// later build can show the history without inheriting its recommendation.
    public struct Observation: Codable, Equatable, Sendable {
        public let bundleID: String
        public let version: String
        public let build: String
        public let observedOn: String
        public let macOSVersion: String
        public let summary: String

        public init(bundleID: String, version: String, build: String, observedOn: String,
                    macOSVersion: String, summary: String) {
            self.bundleID = bundleID; self.version = version; self.build = build
            self.observedOn = observedOn; self.macOSVersion = macOSVersion; self.summary = summary
        }

        func matches(_ info: [String: Any], macOSVersion: String) -> Bool {
            !bundleID.isEmpty && !version.isEmpty && !build.isEmpty && !summary.isEmpty && !observedOn.isEmpty
                && info["CFBundleIdentifier"] as? String == bundleID
                && info["CFBundleShortVersionString"] as? String == version
                && info["CFBundleVersion"] as? String == build
                && self.macOSVersion == macOSVersion
        }
    }

    public let reasons: [Reason]
    public let observation: Observation?
    public let observationMatches: Bool
    public var isSuggested: Bool { observationMatches }

    public static var currentMacOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    public static func classify(bundle: URL, observation: Observation? = nil,
                                macOSVersion: String = currentMacOSVersion) -> AutomaticUpdateSuggestion {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        guard let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else {
            return .init(reasons: [.unreadableBundle], observation: observation, observationMatches: false)
        }
        var reasons: [Reason] = []
        let points = extensionPoints(in: contents.appendingPathComponent("PlugIns", isDirectory: true))
        if points.contains(where: { $0.hasPrefix("com.apple.networkextension") }) { reasons.append(.networkExtension) }
        if points.contains(where: { $0.hasPrefix("com.apple.fileprovider") }) { reasons.append(.fileSync) }
        if UpdatePolicy.isInputMethod(bundle) || info["InputMethodConnectionName"] != nil { reasons.append(.inputMethod) }
        let extensions = contents.appendingPathComponent("Library/SystemExtensions", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(atPath: extensions.path),
           items.contains(where: { $0.hasSuffix(".systemextension") }) { reasons.append(.systemExtension) }
        if flag(info["LSUIElement"]) { reasons.append(.menuBarApp) }
        if flag(info["LSBackgroundOnly"]) { reasons.append(.backgroundOnlyApp) }
        if flag(info["NSSupportsAutomaticTermination"]) { reasons.append(.automaticTermination) }
        if flag(info["NSSupportsSuddenTermination"]) { reasons.append(.suddenTermination) }
        let matches = observation?.matches(info, macOSVersion: macOSVersion) == true
        if !matches { reasons.append(.insufficientEvidence) }
        return .init(reasons: reasons, observation: observation, observationMatches: matches)
    }

    static func flag(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String: return ["yes", "true", "1"].contains(string.lowercased())
        default: return false
        }
    }

    static func extensionPoints(in plugIns: URL) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: plugIns.path) else { return [] }
        return items.filter { $0.hasSuffix(".appex") }.compactMap { name in
            let plist = plugIns.appendingPathComponent(name).appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let info = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
            else { return nil }
            return (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        }
    }
}
